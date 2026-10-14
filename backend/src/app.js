import crypto from 'node:crypto';
import Fastify from 'fastify';
import cors from '@fastify/cors';
import jwt from '@fastify/jwt';
import rateLimit from '@fastify/rate-limit';
import bcrypt from 'bcryptjs';
import { countryName, distanceKm, randomLocation, sortTr } from './geo.js';
import { scheduleBotAccept, scheduleBotReply } from './bots.js';
import { langOf, translate } from './i18n.js';
import { LEGAL_VERSION } from './legal.js';
import {
  activeProducts, chargeLetter, creditJson, creditState, deliveryMinutes as defaultDelivery, getSettings,
} from './credits.js';
import { adminRoutes } from './admin.js';

/** Hizmet verilen tek ülke: kayıt ve il seçimi yalnızca Türkiye'den */
export const SERVICE_COUNTRY = 'TR';

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const publicUser = (u) => ({
  id: u.id,
  username: u.username,
  displayName: u.display_name,
  city: u.city,
  place: u.place ?? null,
  country: u.country ?? null,
  countryName: u.country ? countryName(u.country) : null,
  lat: u.lat,
  lng: u.lng,
  // Yüklenmiş profil fotoğrafının API'ye göre yolu; yoksa uygulama çizgi avatar gösterir
  photo: u.avatar_version ? `/users/${u.id}/avatar?v=${u.avatar_version}` : null,
});

const letterJson = (l, other) => ({
  id: l.id,
  body: l.body,
  isRandom: l.is_random,
  replyTo: l.reply_to,
  distanceKm: Math.round(l.distance_km),
  sentAt: l.sent_at,
  deliverAt: l.deliver_at,
  openedAt: l.opened_at,
  ...other,
});

// Mektubun karşı tarafını tek sorguda json olarak getirmek için
const userJsonSql = (alias) =>
  `json_build_object('id', ${alias}.id, 'username', ${alias}.username,
     'display_name', ${alias}.display_name, 'city', ${alias}.city,
     'place', ${alias}.place, 'country', ${alias}.country,
     'lat', ${alias}.lat, 'lng', ${alias}.lng,
     'avatar_version', ${alias}.avatar_version)`;

// İki kullanıcıdan biri diğerini engellemiş mi
const blockedSql = (a, b) =>
  `exists(select 1 from blocks where (blocker_id = ${a} and blocked_id = ${b})
     or (blocker_id = ${b} and blocked_id = ${a}))`;

// Benimle ilişki sütunları: arkadaş mı, bekleyen istek var mı
const relationSql = (meParam, alias) => `
  exists(select 1 from friendships f where f.user_id = ${meParam} and f.friend_id = ${alias}.id) as is_friend,
  (select id from friend_requests r
    where r.from_id = ${meParam} and r.to_id = ${alias}.id and r.status = 'pending') as outgoing_id,
  (select id from friend_requests r
    where r.from_id = ${alias}.id and r.to_id = ${meParam} and r.status = 'pending') as incoming_id`;

const relationJson = (u) => ({
  relation: u.is_friend ? 'friend' : u.incoming_id ? 'incoming' : u.outgoing_id ? 'outgoing' : 'none',
  requestId: u.incoming_id ?? u.outgoing_id ?? null,
});

/** Yanıttaki tüm kullanıcıların ülke adını istenen dile çevir */
function localizeCountries(value, lang, depth = 0) {
  if (depth > 6 || value === null || typeof value !== 'object') return;
  if (Array.isArray(value)) {
    for (const v of value) localizeCountries(v, lang, depth + 1);
    return;
  }
  if (typeof value.country === 'string' && 'countryName' in value) {
    value.countryName = countryName(value.country, lang);
  }
  for (const v of Object.values(value)) localizeCountries(v, lang, depth + 1);
}

/** Kendi hesabının özel ayarları (yalnızca sahibine döner) */
const settingsJson = (u) => ({
  lang: u.lang,
  termsAcceptedAt: u.terms_accepted_at,
  noticeAckAt: u.notice_ack_at,
  legalVersion: u.legal_version,
  currentLegalVersion: LEGAL_VERSION,
});

// Rastgele eşleşme yalnızca aynı ülke içinde ($1 gönderen id, u aday):
// kişisel veriler rastgele bir yabancıya, yurt dışına aktarılmaz
const randomOkSql = `u.country is not distinct from (select country from users where id = $1)
  and u.banned_at is null`;

/** Fotoğrafın türünü dosyanın ilk baytlarından bul (uzantıya güvenme) */
function imageMime(b) {
  if (b.length > 3 && b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff) return 'image/jpeg';
  if (b.length > 8 && b.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))) {
    return 'image/png';
  }
  if (b.length > 12 && b.toString('ascii', 0, 4) === 'RIFF' && b.toString('ascii', 8, 12) === 'WEBP') {
    return 'image/webp';
  }
  return null;
}

const MAX_PHOTO = 2.5 * 1024 * 1024;

export function buildApp({
  pool,
  jwtSecret,
  logger = false,
  // Bot arkadaşlık isteğini birkaç sn içinde onaylar, mektubu okuyup cevap yazması 5-20 dk sürer
  botAcceptMs = [3000, 6000],
  botReplyMs = [5 * 60_000, 20 * 60_000],
  onBotReply,
  // Mesafeye göre uçuş süresi (dakika); testlerde 0
  deliveryMinutes = defaultDelivery,
  // Google Play satın alma doğrulayıcısı (play.js); yoksa satın alma kapalı
  verifyGooglePurchase = null,
  // Geliştirmede ödeme yapmadan hak ekleme (yayında kapalı olmalı)
  allowTestPurchases = false,
  // Giriş / kayıt denemesi sınırı (IP başına), şifre tahminini yavaşlatır
  authRateLimit = { max: 10, timeWindow: '1 minute' },
  // nginx arkasında gerçek istemci IP'si için güvenilen vekil adresleri
  trustProxy = false,
}) {
  const app = Fastify({ logger, trustProxy });
  // Tarayıcıdan PUT/PATCH/DELETE de gelir (il değiştir, fotoğraf, istek geri al)
  app.register(cors, { origin: true, methods: ['GET', 'HEAD', 'POST', 'PUT', 'PATCH', 'DELETE'] });
  app.register(jwt, { secret: jwtSecret, sign: { expiresIn: '30d' } });
  app.register(rateLimit, { global: false });
  app.addHook('preSerialization', async (req, reply, payload) => {
    const lang = langOf(req);
    if (lang !== 'tr') localizeCountries(payload, lang);
    return payload;
  });
  const limited = { config: { rateLimit: authRateLimit } };

  const one = async (text, params) => (await pool.query(text, params)).rows[0];
  const fail = (reply, code, error) =>
    reply.code(code).send({ error: translate(error, langOf(reply.request)) });
  const auth = {
    onRequest: async (req, reply) => {
      try {
        await req.jwtVerify();
      } catch {
        return fail(reply, 401, 'Oturumun geçersiz, lütfen tekrar giriş yap.');
      }
      // Askıya alınmış hesap hiçbir işlem yapamaz
      const u = await one('select banned_at from users where id = $1', [req.user.sub]);
      if (u?.banned_at) return fail(reply, 403, 'Hesabın askıya alındı.');
    },
  };
  const me = (req) => req.user.sub;

  /** Tek bağlantı üzerinde işlem (transaction); içeride yalnızca c kullanılmalı */
  const tx = async (fn) => {
    const c = await pool.connect();
    try {
      await c.query('begin');
      const r = await fn(c);
      await c.query('commit');
      return r;
    } catch (err) {
      await c.query('rollback').catch(() => {});
      throw err;
    } finally {
      c.release();
    }
  };
  const credits = async (userId) =>
    creditJson(await creditState(pool, userId), await activeProducts(pool), {
      testPurchases: allowTestPurchases,
    });
  const token = (u) => app.jwt.sign({ sub: u.id });

  app.setErrorHandler((err, req, reply) => {
    if (err.statusCode === 429) {
      return fail(reply, 429, 'Çok fazla deneme yaptın, bir dakika bekleyip tekrar dene.');
    }
    if (err.statusCode === 413) return fail(reply, 413, 'Gönderilen dosya çok büyük.');
    if (err.validation || (err.statusCode >= 400 && err.statusCode < 500)) {
      return fail(reply, err.statusCode ?? 400, 'Eksik ya da hatalı bilgi gönderildi.');
    }
    req.log.error(err);
    return fail(reply, 500, 'Sunucuda bir sorun oluştu, birazdan tekrar dene.');
  });

  // Rotalar eklentiler (rate-limit) yüklendikten sonra kaydedilir
  app.register(async (app) => {
    adminRoutes(app, { pool, one, fail, tx, token, limited });

    app.get('/api/health', async () => {
      await pool.query('select 1');
      return { ok: true };
    });

    // ---------- ülke / il listeleri ----------

    // Hizmet yalnızca Türkiye'de: ülke listesi tek ülke, iller yalnızca Türkiye'nin
    app.get('/api/geo/countries', async (req) => [
      { code: SERVICE_COUNTRY, name: countryName(SERVICE_COUNTRY, langOf(req)) },
    ]);

    app.get('/api/geo/countries/:code/regions', async (req, reply) => {
      const code = req.params.code.toUpperCase();
      const { rows } = code === SERVICE_COUNTRY
        ? await pool.query('select code, name from regions where country = $1', [code])
        : { rows: [] };
      if (!rows.length) return fail(reply, 404, 'Bu ülke bulunamadı.');
      return sortTr(rows);
    });

    const locationSchema = {
      country: { type: 'string', pattern: '^[A-Za-z]{2}$' },
      region: { type: 'string', minLength: 1, maxLength: 20 },
    };

    /** Seçilen ülke hizmet verilen ülke mi (gönderilmezse Türkiye sayılır) */
    const serviceCountry = (body) => {
      const c = (body.country ?? SERVICE_COUNTRY).toUpperCase();
      return c === SERVICE_COUNTRY ? c : null;
    };

    // ---------- oturum ----------

    app.post('/api/auth/register', {
      ...limited,
      schema: {
        body: {
          type: 'object',
          required: ['username', 'password', 'displayName', 'region'],
          properties: {
            username: { type: 'string', pattern: '^[a-z0-9_.]{3,20}$' },
            password: { type: 'string', minLength: 6, maxLength: 72 },
            displayName: { type: 'string', minLength: 1, maxLength: 30 },
            ...locationSchema,
            lang: { type: 'string', enum: ['tr', 'en'] },
            acceptTerms: { type: 'boolean' },
            acceptNotice: { type: 'boolean' },
          },
        },
      },
    }, async (req, reply) => {
      const { username, password, displayName } = req.body;
      if (!displayName.trim()) return fail(reply, 400, 'İsim boş olamaz.');
      // KVKK: aydınlatma metninin okunduğu ve koşulların kabulü kayıt şartı
      if (req.body.acceptTerms !== true || req.body.acceptNotice !== true) {
        return fail(reply, 400, 'Kayıt için Kullanım Koşulları ve Aydınlatma Metni onaylanmalı.');
      }
      if (await one('select 1 from users where username = $1', [username])) {
        return fail(reply, 409, 'Bu kullanıcı adı alınmış.');
      }
      const country = serviceCountry(req.body);
      if (!country) return fail(reply, 400, 'toss-o şu an yalnızca Türkiye\'de kullanılabilir.');
      // Gerçek konum istenmez: seçilen ilde rastgele bir noktaya yerleştirilir
      const loc = await randomLocation(pool, country, req.body.region);
      if (!loc) return fail(reply, 400, 'Bu il / bölge bulunamadı.');
      const u = await one(
        `insert into users (username, display_name, password_hash, city, lat, lng,
                            country, region_code, place, lang,
                            terms_accepted_at, notice_ack_at, legal_version)
         values ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, now(), now(), $11)
         returning *`,
        [username, displayName.trim(), await bcrypt.hash(password, 10), loc.regionName,
          loc.lat, loc.lng, loc.country, loc.region, loc.place, req.body.lang ?? langOf(req),
          LEGAL_VERSION],
      );
      return reply.code(201).send({ token: token(u), user: publicUser(u), settings: settingsJson(u) });
    });

    app.post('/api/auth/login', {
      ...limited,
      schema: {
        body: {
          type: 'object',
          required: ['username', 'password'],
          properties: { username: { type: 'string' }, password: { type: 'string' } },
        },
      },
    }, async (req, reply) => {
      const u = await one('select * from users where username = $1', [
        req.body.username.trim().toLowerCase(),
      ]);
      if (!u || u.is_bot || !(await bcrypt.compare(req.body.password, u.password_hash))) {
        return fail(reply, 401, 'Kullanıcı adı ya da şifre hatalı.');
      }
      if (u.banned_at) return fail(reply, 403, 'Hesabın askıya alındı.');
      return { token: token(u), user: publicUser(u), settings: settingsJson(u) };
    });

    app.get('/api/me', auth, async (req, reply) => {
      const u = await one('select * from users where id = $1', [me(req)]);
      if (!u) return fail(reply, 401, 'Oturumun geçersiz, lütfen tekrar giriş yap.');
      const stats = await one(
        `select
           (select count(*) from letters where sender_id = $1)::int as sent,
           (select count(*) from letters where recipient_id = $1 and deliver_at <= now())::int as received,
           (select count(*) from letters l where recipient_id = $1 and opened_at is null
             and deliver_at <= now()
             and not exists(select 1 from blocks b where b.blocker_id = $1 and b.blocked_id = l.sender_id))::int as unread,
           (select count(*) from friend_requests where to_id = $1 and status = 'pending')::int as requests,
           (select count(distinct r.city) from letters l join users r on r.id = l.recipient_id
             where l.sender_id = $1)::int as cities`,
        [u.id],
      );
      return { user: publicUser(u), stats, settings: settingsJson(u), credits: await credits(u.id) };
    });

    // ---------- haklar ve satın alma ----------

    app.get('/api/credits', auth, async (req) => credits(me(req)));

    /** Satın alınan hakları ekle; aynı satın alma iki kez sayılmaz */
    const grantPurchase = async (userId, product, platform, purchaseToken, orderId) =>
      tx(async (c) => {
        const { rows } = await c.query(
          `insert into purchases (user_id, product_id, credits, platform, purchase_token, order_id)
           values ($1, $2, $3, $4, $5, $6) on conflict (purchase_token) do nothing returning user_id`,
          [userId, product.id, product.credits, platform, purchaseToken, orderId],
        );
        if (rows.length) {
          await c.query('update users set bonus_credits = bonus_credits + $2 where id = $1', [
            userId,
            product.credits,
          ]);
          return true;
        }
        const prev = await c.query('select user_id from purchases where purchase_token = $1', [purchaseToken]);
        return prev.rows[0]?.user_id === userId;
      });

    const productSchema = { type: 'string', minLength: 1, maxLength: 64 };
    // Paketler admin panelinden yönetilir; satıştan kalkmış bir paketin eski
    // satın alması yine geçerlidir (yalnızca test satın alma aktif ister)
    const productOf = (id, { activeOnly = false } = {}) =>
      one(`select id, credits from products where id = $1 ${activeOnly ? 'and active' : ''}`, [id]);

    // Google Play: uygulama satın alma anahtarını gönderir, sunucu Google'a doğrulatır
    app.post('/api/purchases/google', {
      ...auth,
      schema: {
        body: {
          type: 'object',
          required: ['productId', 'purchaseToken'],
          properties: { productId: productSchema, purchaseToken: { type: 'string', minLength: 10 } },
        },
      },
    }, async (req, reply) => {
      if (!verifyGooglePurchase) return fail(reply, 503, 'Satın alma şu an kullanılamıyor.');
      const { productId, purchaseToken } = req.body;
      let v;
      try {
        v = await verifyGooglePurchase(productId, purchaseToken);
      } catch (err) {
        req.log.error({ err }, 'Google Play doğrulaması başarısız');
        return fail(reply, 502, 'Satın alma doğrulanamadı, birazdan tekrar dene.');
      }
      if (!v.ok) return fail(reply, 400, 'Satın alma geçersiz.');
      const product = await productOf(productId);
      if (!product) return fail(reply, 400, 'Bu paket bulunamadı.');
      const ok = await grantPurchase(me(req), product, 'google', purchaseToken, v.orderId);
      if (!ok) return fail(reply, 409, 'Bu satın alma başka bir hesapta kullanılmış.');
      return credits(me(req));
    });

    // Yalnızca geliştirme: ödeme yapmadan paket ekle
    app.post('/api/purchases/test', {
      ...auth,
      schema: { body: { type: 'object', required: ['productId'], properties: { productId: productSchema } } },
    }, async (req, reply) => {
      if (!allowTestPurchases) return fail(reply, 404, 'Satın alma şu an kullanılamıyor.');
      const product = await productOf(req.body.productId, { activeOnly: true });
      if (!product) return fail(reply, 400, 'Bu paket bulunamadı.');
      await grantPurchase(me(req), product, 'test', `test-${crypto.randomUUID()}`, null);
      return credits(me(req));
    });

    // İl değiştir: yeni ilde yeni rastgele bir nokta
    app.put('/api/me/location', {
      ...auth,
      schema: {
        body: { type: 'object', required: ['region'], properties: locationSchema },
      },
    }, async (req, reply) => {
      const country = serviceCountry(req.body);
      if (!country) return fail(reply, 400, 'toss-o şu an yalnızca Türkiye\'de kullanılabilir.');
      const loc = await randomLocation(pool, country, req.body.region);
      if (!loc) return fail(reply, 400, 'Bu il / bölge bulunamadı.');
      const u = await one(
        `update users set city = $2, lat = $3, lng = $4, country = $5, region_code = $6, place = $7
         where id = $1 returning *`,
        [me(req), loc.regionName, loc.lat, loc.lng, loc.country, loc.region, loc.place],
      );
      if (!u) return fail(reply, 401, 'Oturumun geçersiz, lütfen tekrar giriş yap.');
      return publicUser(u);
    });

    // İsim, dil ya da güncel yasal metinlerin onayı
    app.patch('/api/me', {
      ...auth,
      schema: {
        body: {
          type: 'object',
          minProperties: 1,
          properties: {
            displayName: { type: 'string', minLength: 1, maxLength: 30 },
            lang: { type: 'string', enum: ['tr', 'en'] },
            acceptLegal: { type: 'boolean', const: true },
          },
        },
      },
    }, async (req, reply) => {
      const { displayName, lang, acceptLegal } = req.body;
      const name = displayName?.trim();
      if (displayName !== undefined && !name) return fail(reply, 400, 'İsim boş olamaz.');
      const u = await one(
        `update users set
           display_name = coalesce($2, display_name),
           lang = coalesce($3, lang),
           terms_accepted_at = case when $4 then now() else terms_accepted_at end,
           notice_ack_at = case when $4 then now() else notice_ack_at end,
           legal_version = case when $4 then $5 else legal_version end
         where id = $1 returning *`,
        [me(req), name ?? null, lang ?? null, acceptLegal === true, LEGAL_VERSION],
      );
      if (!u) return fail(reply, 401, 'Oturumun geçersiz, lütfen tekrar giriş yap.');
      return { user: publicUser(u), settings: settingsJson(u) };
    });

    app.put('/api/me/password', {
      ...auth,
      ...limited,
      schema: {
        body: {
          type: 'object',
          required: ['current', 'next'],
          properties: {
            current: { type: 'string' },
            next: { type: 'string', minLength: 6, maxLength: 72 },
          },
        },
      },
    }, async (req, reply) => {
      const u = await one('select * from users where id = $1', [me(req)]);
      if (!u || !(await bcrypt.compare(req.body.current, u.password_hash))) {
        return fail(reply, 403, 'Mevcut şifren hatalı.');
      }
      await pool.query('update users set password_hash = $2 where id = $1', [
        u.id,
        await bcrypt.hash(req.body.next, 10),
      ]);
      return reply.code(204).send();
    });

    // Hesabı sil: mektuplar, arkadaşlıklar, istekler ve fotoğraf da silinir
    app.delete('/api/me', {
      ...auth,
      ...limited,
      schema: {
        body: { type: 'object', required: ['password'], properties: { password: { type: 'string' } } },
      },
    }, async (req, reply) => {
      const u = await one('select * from users where id = $1', [me(req)]);
      if (!u || !(await bcrypt.compare(req.body.password, u.password_hash))) {
        return fail(reply, 403, 'Şifren hatalı.');
      }
      await pool.query('delete from users where id = $1', [u.id]);
      return reply.code(204).send();
    });

    // Profil fotoğrafı: base64 JPG / PNG / WEBP (uygulama yüklemeden önce küçültür)
    app.put('/api/me/avatar', {
      ...auth,
      bodyLimit: 4 * 1024 * 1024,
      schema: {
        body: {
          type: 'object',
          required: ['image'],
          properties: { image: { type: 'string', minLength: 16 } },
        },
      },
    }, async (req, reply) => {
      const data = Buffer.from(req.body.image.replace(/^data:[^,]*,/, ''), 'base64');
      if (data.length > MAX_PHOTO) return fail(reply, 413, 'Fotoğraf çok büyük, en fazla 2,5 MB olabilir.');
      const mime = imageMime(data);
      if (!mime) return fail(reply, 400, 'Yalnızca JPG, PNG ya da WEBP fotoğraf yüklenebilir.');
      await pool.query(
        `insert into avatars (user_id, data, mime) values ($1, $2, $3)
         on conflict (user_id) do update set data = excluded.data, mime = excluded.mime`,
        [me(req), data, mime],
      );
      const u = await one(
        'update users set avatar_version = coalesce(avatar_version, 0) + 1 where id = $1 returning *',
        [me(req)],
      );
      return publicUser(u);
    });

    app.delete('/api/me/avatar', auth, async (req) => {
      await pool.query('delete from avatars where user_id = $1', [me(req)]);
      return publicUser(
        await one('update users set avatar_version = null where id = $1 returning *', [me(req)]),
      );
    });

    // Fotoğraflar herkese açık; adres sürüm içerdiği için uzun süre önbelleğe alınabilir
    app.get('/api/users/:id/avatar', async (req, reply) => {
      const a = UUID.test(req.params.id)
        ? await one('select data, mime from avatars where user_id = $1', [req.params.id])
        : null;
      if (!a) return fail(reply, 404, 'Fotoğraf bulunamadı.');
      return reply
        .header('cache-control', 'public, max-age=31536000, immutable')
        .type(a.mime)
        .send(a.data);
    });

    // Bir kişinin profil kartı: ilişki, aradaki mektup sayıları
    app.get('/api/users/:id', auth, async (req, reply) => {
      const u = UUID.test(req.params.id)
        ? await one(
          `select u.*, ${relationSql('$1', 'u')},
             (select created_at from friendships where user_id = $1 and friend_id = u.id) as friends_since,
             (select count(*) from letters where sender_id = $1 and recipient_id = u.id)::int as sent,
             (select count(*) from letters where sender_id = u.id and recipient_id = $1)::int as received,
             exists(select 1 from blocks where blocker_id = $1 and blocked_id = u.id) as blocked
           from users u
           where u.id = $2 and u.id <> $1
             and not exists(select 1 from blocks where blocker_id = u.id and blocked_id = $1)`,
          [me(req), req.params.id],
        )
        : null;
      if (!u) return fail(reply, 404, 'Bu kullanıcı bulunamadı.');
      return {
        ...publicUser(u),
        ...relationJson(u),
        friendsSince: u.friends_since,
        sent: u.sent,
        received: u.received,
        blocked: u.blocked,
      };
    });

    // ---------- engelleme ----------

    app.get('/api/blocks', auth, async (req) => {
      const { rows } = await pool.query(
        `select u.* from blocks b join users u on u.id = b.blocked_id
         where b.blocker_id = $1 order by b.created_at desc`,
        [me(req)],
      );
      return rows.map(publicUser);
    });

    // Engelle: arkadaşlık biter, bekleyen istekler iptal olur
    app.post('/api/users/:id/block', auth, async (req, reply) => {
      const myId = me(req);
      const target = UUID.test(req.params.id)
        ? await one('select id from users where id = $1', [req.params.id])
        : null;
      if (!target) return fail(reply, 404, 'Bu kullanıcı bulunamadı.');
      if (target.id === myId) return fail(reply, 400, 'Kendini engelleyemezsin.');
      await pool.query(
        'insert into blocks (blocker_id, blocked_id) values ($1, $2) on conflict do nothing',
        [myId, target.id],
      );
      await pool.query(
        `delete from friendships where (user_id = $1 and friend_id = $2)
           or (user_id = $2 and friend_id = $1)`,
        [myId, target.id],
      );
      await pool.query(
        `update friend_requests set status = 'cancelled', responded_at = now()
         where status = 'pending' and ((from_id = $1 and to_id = $2) or (from_id = $2 and to_id = $1))`,
        [myId, target.id],
      );
      return reply.code(204).send();
    });

    app.delete('/api/users/:id/block', auth, async (req, reply) => {
      if (UUID.test(req.params.id)) {
        await pool.query('delete from blocks where blocker_id = $1 and blocked_id = $2', [
          me(req),
          req.params.id,
        ]);
      }
      return reply.code(204).send();
    });

    // ---------- arkadaşlar ----------

    app.get('/api/friends', auth, async (req) => {
      const { rows } = await pool.query(
        `select u.* from friendships f join users u on u.id = f.friend_id
         where f.user_id = $1 order by f.created_at, u.display_name`,
        [me(req)],
      );
      return rows.map(publicUser);
    });

    // Kullanıcı ara; her sonuçla ilişki durumu döner:
    // friend | incoming (bana istek atmış) | outgoing (ben istek atmışım) | none
    app.get('/api/users/search', {
      ...auth,
      schema: {
        querystring: {
          type: 'object',
          required: ['q'],
          properties: { q: { type: 'string', minLength: 1, maxLength: 30 } },
        },
      },
    }, async (req) => {
      const like = `%${req.query.q.trim().replace(/[%_\\]/g, '\\$&')}%`;
      const { rows } = await pool.query(
        `select u.*, ${relationSql('$1', 'u')}
         from users u
         where u.id <> $1 and u.banned_at is null and (u.username ilike $2 or u.display_name ilike $2)
           and not ${blockedSql('$1', 'u.id')}
         order by u.display_name limit 15`,
        [me(req), like],
      );
      return rows.map((u) => ({ ...publicUser(u), ...relationJson(u) }));
    });

    // ---------- arkadaşlık istekleri ----------

    /** Bekleyen isteği kabul et: karşılıklı arkadaşlık kurulur */
    const acceptRequest = async (id, toId) => {
      const r = await one(
        `update friend_requests set status = 'accepted', responded_at = now()
         where id = $1 and to_id = $2 and status = 'pending' returning *`,
        [id, toId],
      );
      if (!r) return null;
      await pool.query(
        `insert into friendships (user_id, friend_id) values ($1, $2), ($2, $1)
         on conflict do nothing`,
        [r.from_id, r.to_id],
      );
      return r;
    };

    app.get('/api/friends/requests', auth, async (req) => {
      const { rows } = await pool.query(
        `select r.id, r.created_at, r.from_id = $1 as mine,
                ${userJsonSql('o')} as other
         from friend_requests r
         join users o on o.id = case when r.from_id = $1 then r.to_id else r.from_id end
         where (r.from_id = $1 or r.to_id = $1) and r.status = 'pending'
         order by r.created_at desc`,
        [me(req)],
      );
      const item = (r) => ({ id: r.id, createdAt: r.created_at, user: publicUser(r.other) });
      return {
        incoming: rows.filter((r) => !r.mine).map(item),
        outgoing: rows.filter((r) => r.mine).map(item),
      };
    });

    app.post('/api/friends/requests', {
      ...auth,
      schema: {
        body: {
          type: 'object',
          required: ['username'],
          properties: { username: { type: 'string', minLength: 1 } },
        },
      },
    }, async (req, reply) => {
      const myId = me(req);
      const target = await one('select * from users where username = $1', [
        req.body.username.trim().toLowerCase(),
      ]);
      if (!target) return fail(reply, 404, 'Bu kullanıcı bulunamadı.');
      if (target.id === myId) return fail(reply, 400, 'Kendine istek gönderemezsin.');
      if ((await one(`select ${blockedSql('$1', '$2')} as b`, [myId, target.id])).b) {
        return fail(reply, 404, 'Bu kullanıcı bulunamadı.');
      }
      if (await one('select 1 from friendships where user_id = $1 and friend_id = $2', [myId, target.id])) {
        return fail(reply, 409, 'Zaten arkadaşsınız.');
      }
      // O da bana istek atmışsa ikisi de istiyor demektir: hemen arkadaş olun
      const incoming = await one(
        `select id from friend_requests
         where from_id = $1 and to_id = $2 and status = 'pending'`,
        [target.id, myId],
      );
      if (incoming) {
        await acceptRequest(incoming.id, myId);
        return { status: 'accepted', user: publicUser(target) };
      }
      if (await one(
        `select 1 from friend_requests where from_id = $1 and to_id = $2 and status = 'pending'`,
        [myId, target.id],
      )) {
        return fail(reply, 409, 'İsteğin zaten gönderildi, onay bekleniyor.');
      }
      const r = await one(
        'insert into friend_requests (from_id, to_id) values ($1, $2) returning *',
        [myId, target.id],
      );
      if (target.is_bot) {
        onBotReply?.(scheduleBotAccept({ accept: () => acceptRequest(r.id, target.id), delayMs: botAcceptMs, log: req.log }));
      }
      return reply.code(201).send({ status: 'pending', requestId: r.id, user: publicUser(target) });
    });

    app.post('/api/friends/requests/:id/accept', auth, async (req, reply) => {
      const r = UUID.test(req.params.id) ? await acceptRequest(req.params.id, me(req)) : null;
      if (!r) return fail(reply, 404, 'İstek bulunamadı.');
      return publicUser(await one('select * from users where id = $1', [r.from_id]));
    });

    app.post('/api/friends/requests/:id/decline', auth, async (req, reply) => {
      const r = UUID.test(req.params.id)
        ? await one(
          `update friend_requests set status = 'declined', responded_at = now()
           where id = $1 and to_id = $2 and status = 'pending' returning id`,
          [req.params.id, me(req)],
        )
        : null;
      if (!r) return fail(reply, 404, 'İstek bulunamadı.');
      return reply.code(204).send();
    });

    // Gönderdiğim isteği geri al
    app.delete('/api/friends/requests/:id', auth, async (req, reply) => {
      const r = UUID.test(req.params.id)
        ? await one(
          `update friend_requests set status = 'cancelled', responded_at = now()
           where id = $1 and from_id = $2 and status = 'pending' returning id`,
          [req.params.id, me(req)],
        )
        : null;
      if (!r) return fail(reply, 404, 'İstek bulunamadı.');
      return reply.code(204).send();
    });

    // Arkadaşlıktan çıkar (iki taraftan da)
    app.delete('/api/friends/:id', auth, async (req, reply) => {
      if (!UUID.test(req.params.id)) return fail(reply, 404, 'Arkadaş bulunamadı.');
      const { rowCount } = await pool.query(
        `delete from friendships where (user_id = $1 and friend_id = $2)
           or (user_id = $2 and friend_id = $1)`,
        [me(req), req.params.id],
      );
      if (!rowCount) return fail(reply, 404, 'Arkadaş bulunamadı.');
      return reply.code(204).send();
    });

    // ---------- mektuplar ----------

    app.post('/api/letters', {
      ...auth,
      schema: {
        body: {
          type: 'object',
          required: ['to', 'body'],
          properties: {
            to: { type: 'string' },
            body: { type: 'string', minLength: 1, maxLength: 2000 },
            replyTo: { type: 'string' },
          },
        },
      },
    }, async (req, reply) => {
      const sender = await one('select * from users where id = $1', [me(req)]);
      if (!sender) return fail(reply, 401, 'Oturumun geçersiz, lütfen tekrar giriş yap.');
      const body = req.body.body.trim();
      if (!body) return fail(reply, 400, 'Boş mektup gönderilemez.');

      let recipient;
      const isRandom = req.body.to === 'random';
      if (isRandom) {
        // Önce arkadaş olmayan biri; kimse yoksa herhangi biri
        recipient =
          (await one(
            `select * from users u where u.id <> $1 and not ${blockedSql('$1', 'u.id')}
               and ${randomOkSql}
               and not exists (select 1 from friendships f where f.user_id = $1 and f.friend_id = u.id)
             order by random() limit 1`,
            [sender.id],
          )) ??
          (await one(
            `select * from users u where u.id <> $1 and not ${blockedSql('$1', 'u.id')}
               and ${randomOkSql}
             order by random() limit 1`,
            [sender.id],
          ));
      } else if (UUID.test(req.body.to)) {
        recipient = await one('select * from users where id = $1', [req.body.to]);
      }
      if (!recipient) return fail(reply, 404, 'Alıcı bulunamadı.');
      if (recipient.id === sender.id) return fail(reply, 400, 'Kendine uçak atamazsın.');

      let replyTo = null;
      if (req.body.replyTo) {
        const orig = UUID.test(req.body.replyTo)
          ? await one(`select id, sender_id from letters
                       where id = $1 and recipient_id = $2 and deliver_at <= now()`, [
            req.body.replyTo,
            sender.id,
          ])
          : null;
        if (!orig) return fail(reply, 404, 'Cevap verilen mektup bulunamadı.');
        if (!isRandom && orig.sender_id !== recipient.id) {
          return fail(reply, 400, 'Cevap, mektubu gönderen kişiye gitmeli.');
        }
        replyTo = orig.id;
      }
      if (!isRandom) {
        const rel = await one(
          `select ${blockedSql('$1', '$2')} as blocked,
             exists(select 1 from friendships where user_id = $1 and friend_id = $2) as friend`,
          [sender.id, recipient.id],
        );
        if (rel.blocked) return fail(reply, 403, 'Bu kişiye uçak gönderemezsin.');
        // Arkadaş olmayana yalnızca sana yazdığı mektuba cevap olarak yazılır
        if (!rel.friend && !replyTo) {
          return fail(reply, 403, 'Yalnızca arkadaşlarına ya da sana yazan birine uçak gönderebilirsin.');
        }
      }

      const km = distanceKm(sender, recipient);
      // Admin panelindeki "anlık teslim" açıksa uçuş ve bot düşünme süresi atlanır
      const { instantDelivery } = await getSettings(pool);
      const flightMinutes = instantDelivery ? () => 0 : deliveryMinutes;
      const letter = await tx(async (c) => {
        const cost = await chargeLetter(c, sender.id, replyTo);
        if (!cost) return null;
        const { rows } = await c.query(
          `insert into letters (sender_id, recipient_id, body, is_random, reply_to, distance_km, cost, deliver_at)
           values ($1, $2, $3, $4, $5, $6, $7, now() + make_interval(mins => $8)) returning *`,
          [sender.id, recipient.id, body, isRandom, replyTo, km, cost, flightMinutes(km)],
        );
        return rows[0];
      });
      if (!letter) {
        return reply.code(402).send({
          error: translate('Bugünkü ücretsiz mektup hakkını kullandın. Yarın yeni hakkın gelir ya da ek hak alabilirsin.', langOf(req)),
          code: 'no_credits',
          credits: await credits(sender.id),
        });
      }
      if (recipient.is_bot) {
        const p = scheduleBotReply({
          pool, letter, bot: recipient, sender, log: req.log,
          thinkMs: instantDelivery ? botAcceptMs : botReplyMs, deliveryMinutes: flightMinutes,
        });
        if (p) onBotReply?.(p);
      }
      return reply.code(201).send({
        ...letterJson(letter, { to: publicUser(recipient) }),
        cost: letter.cost,
        credits: await credits(sender.id),
      });
    });

    app.get('/api/letters/inbox', auth, async (req) => {
      const { rows } = await pool.query(
        `select l.*, ${userJsonSql('s')} as other
         from letters l join users s on s.id = l.sender_id
         where l.recipient_id = $1 and l.deliver_at <= now()
           and not exists(select 1 from blocks b where b.blocker_id = $1 and b.blocked_id = l.sender_id)
         order by l.deliver_at desc limit 100`,
        [me(req)],
      );
      return rows.map((l) => letterJson(l, { from: publicUser(l.other) }));
    });

    app.get('/api/letters/sent', auth, async (req) => {
      const { rows } = await pool.query(
        `select l.*, ${userJsonSql('r')} as other
         from letters l join users r on r.id = l.recipient_id
         where l.sender_id = $1 order by l.sent_at desc limit 100`,
        [me(req)],
      );
      return rows.map((l) => letterJson(l, { to: publicUser(l.other) }));
    });

    app.post('/api/letters/:id/open', auth, async (req, reply) => {
      if (!UUID.test(req.params.id)) return fail(reply, 404, 'Mektup bulunamadı.');
      const l = await one(
        `update letters set opened_at = coalesce(opened_at, now())
         where id = $1 and recipient_id = $2 and deliver_at <= now() returning *`,
        [req.params.id, me(req)],
      );
      if (!l) return fail(reply, 404, 'Mektup bulunamadı.');
      return letterJson(l, {});
    });
  });

  return app;
}
