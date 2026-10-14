// Admin paneli API'si (/api/admin/*) ve panel dosyaları (/admin).
//
// Yetki her istekte veritabanından okunur: admin yetkisi geri alınınca anında
// geçerli olur. Her değişiklik admin_log'a yazılır.
// Gizlilik: panel mektup İÇERİKLERİNİ göstermez (haberleşmenin gizliliği,
// KVKK); yalnızca sayılar ve tarihler.
import { readFileSync } from 'node:fs';
import bcrypt from 'bcryptjs';
import { TZ, creditState, getSettings } from './credits.js';

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const PAGE = 25;

const STATIC = {
  '/admin': ['index.html', 'text/html; charset=utf-8'],
  '/admin/': ['index.html', 'text/html; charset=utf-8'],
  '/admin/app.js': ['app.js', 'application/javascript; charset=utf-8'],
  '/admin/style.css': ['style.css', 'text/css; charset=utf-8'],
  '/admin/logo.png': ['logo.png', 'image/png'],
};

const userRow = (u) => ({
  id: u.id,
  username: u.username,
  displayName: u.display_name,
  city: u.city,
  place: u.place,
  isBot: u.is_bot,
  isAdmin: u.is_admin,
  bannedAt: u.banned_at,
  banReason: u.ban_reason,
  bonus: u.bonus_credits,
  createdAt: u.created_at,
  hasPhoto: !!u.avatar_version,
  lang: u.lang,
  legalVersion: u.legal_version,
  termsAcceptedAt: u.terms_accepted_at,
  ...(u.sent !== undefined && { sent: u.sent, received: u.received, friends: u.friends }),
  ...(u.last_letter_at !== undefined && { lastLetterAt: u.last_letter_at }),
});

export function adminRoutes(app, { pool, one, fail, tx, token, limited }) {
  // ---------- panel dosyaları ----------
  for (const [path, [file, type]] of Object.entries(STATIC)) {
    app.get(path, async (req, reply) =>
      reply
        .type(type)
        .header('cache-control', 'no-cache')
        // Panel yalnızca kendi dosyalarını ve API'yi kullanır
        .header('content-security-policy',
          "default-src 'self'; img-src 'self' data:; style-src 'self'; script-src 'self'; frame-ancestors 'none'")
        .header('x-frame-options', 'DENY')
        .send(readFileSync(new URL(`../admin/${file}`, import.meta.url))));
  }

  // ---------- yetki ----------
  const admin = {
    onRequest: async (req, reply) => {
      try {
        await req.jwtVerify();
      } catch {
        return fail(reply, 401, 'Oturumun geçersiz, lütfen tekrar giriş yap.');
      }
      const u = await one('select id, is_admin, banned_at from users where id = $1', [req.user.sub]);
      if (!u?.is_admin || u.banned_at) return fail(reply, 403, 'Bu işlem için yetkin yok.');
      req.adminId = u.id;
    },
  };
  const log = (c, req, action, target, details) =>
    (c ?? pool).query(
      'insert into admin_log (admin_id, action, target_user, details) values ($1, $2, $3, $4)',
      [req.adminId, action, target ?? null, details ? JSON.stringify(details) : null],
    );
  const userOr404 = async (reply, id) => {
    const u = UUID.test(id) ? await one('select * from users where id = $1', [id]) : null;
    if (!u) fail(reply, 404, 'Bu kullanıcı bulunamadı.');
    return u;
  };

  // Admin girişi: yalnızca admin yetkili ve askıda olmayan hesaplar
  app.post('/api/admin/login', {
    ...limited,
    schema: {
      body: {
        type: 'object',
        required: ['username', 'password'],
        properties: { username: { type: 'string' }, password: { type: 'string' } },
      },
    },
  }, async (req, reply) => {
    const u = await one('select * from users where username = $1', [req.body.username.trim().toLowerCase()]);
    if (!u || u.is_bot || !(await bcrypt.compare(req.body.password, u.password_hash))) {
      return fail(reply, 401, 'Kullanıcı adı ya da şifre hatalı.');
    }
    if (!u.is_admin || u.banned_at) return fail(reply, 403, 'Bu işlem için yetkin yok.');
    return { token: token(u), user: userRow(u) };
  });

  app.get('/api/admin/me', admin, async (req) =>
    userRow(await one('select * from users where id = $1', [req.adminId])));

  // ---------- gösterge ----------
  app.get('/api/admin/stats', admin, async () => {
    const s = await one(
      `select
         (select count(*) from users where not is_bot)::int as users,
         (select count(*) from users where not is_bot and created_at > now() - interval '1 day')::int as users_1d,
         (select count(*) from users where not is_bot and created_at > now() - interval '7 days')::int as users_7d,
         (select count(distinct sender_id) from letters l join users u on u.id = l.sender_id
           where not u.is_bot and l.sent_at > now() - interval '7 days')::int as active_7d,
         (select count(*) from users where banned_at is not null)::int as banned,
         (select count(*) from letters where cost <> 'bot')::int as letters,
         (select count(*) from letters where cost <> 'bot' and sent_at > now() - interval '1 day')::int as letters_1d,
         (select count(*) from letters where deliver_at > now())::int as in_flight,
         (select count(*) from letters where is_random)::int as random_letters,
         (select count(*) from friendships)::int / 2 as friendships,
         (select count(*) from purchases where revoked_at is null and platform <> 'test')::int as purchases,
         (select coalesce(sum(credits), 0) from purchases where revoked_at is null and platform <> 'test')::int as credits_sold,
         (select count(*) from purchases where platform = 'test')::int as test_purchases,
         (select coalesce(sum(bonus_credits), 0) from users)::int as credits_outstanding,
         (select count(*) from letters where cost = 'credit')::int as credits_used`,
    );
    const { rows: days } = await pool.query(
      `with d as (
         select generate_series((now() at time zone '${TZ}')::date - 13, (now() at time zone '${TZ}')::date, '1 day')::date as day)
       select d.day,
         (select count(*) from users u where not u.is_bot and (u.created_at at time zone '${TZ}')::date = d.day)::int as signups,
         (select count(*) from letters l where l.cost <> 'bot' and (l.sent_at at time zone '${TZ}')::date = d.day)::int as letters,
         (select count(*) from purchases p where p.platform <> 'test' and p.revoked_at is null
            and (p.created_at at time zone '${TZ}')::date = d.day)::int as purchases
       from d order by d.day`,
    );
    const { rows: costs } = await pool.query(
      `select cost, count(*)::int as n from letters group by cost order by n desc`,
    );
    return { ...s, days, costs };
  });

  // ---------- kullanıcılar ----------
  app.get('/api/admin/users', {
    ...admin,
    schema: {
      querystring: {
        type: 'object',
        properties: {
          q: { type: 'string', maxLength: 50 },
          filter: { type: 'string', enum: ['all', 'banned', 'admin', 'bots', 'buyers'] },
          page: { type: 'integer', minimum: 0, default: 0 },
        },
      },
    },
  }, async (req) => {
    const { q = '', filter = 'all', page } = req.query;
    const like = `%${q.trim().replace(/[%_\\]/g, '\\$&')}%`;
    const where = {
      all: 'true',
      banned: 'u.banned_at is not null',
      admin: 'u.is_admin',
      bots: 'u.is_bot',
      buyers: "exists(select 1 from purchases p where p.user_id = u.id and p.platform <> 'test')",
    }[filter];
    const { rows } = await pool.query(
      `select u.*, count(*) over()::int as total,
         (select count(*) from letters where sender_id = u.id)::int as sent,
         (select count(*) from letters where recipient_id = u.id and deliver_at <= now())::int as received,
         (select count(*) from friendships where user_id = u.id)::int as friends,
         (select max(sent_at) from letters where sender_id = u.id) as last_letter_at
       from users u
       where ${where} and ($1 = '%%' or u.username ilike $1 or u.display_name ilike $1 or u.city ilike $1)
       order by u.created_at desc limit ${PAGE} offset $2`,
      [like, page * PAGE],
    );
    return { total: rows[0]?.total ?? 0, page, pageSize: PAGE, users: rows.map(userRow) };
  });

  app.get('/api/admin/users/:id', admin, async (req, reply) => {
    const u = await userOr404(reply, req.params.id);
    if (!u) return reply;
    const id = u.id;
    const q = async (text) => (await pool.query(text, [id])).rows;
    const st = await creditState(pool, id);
    const counts = await one(
      `select
         (select count(*) from letters where sender_id = $1)::int as sent,
         (select count(*) from letters where recipient_id = $1 and deliver_at <= now())::int as received,
         (select count(*) from letters where sender_id = $1 and deliver_at > now())::int as in_flight,
         (select count(*) from letters where sender_id = $1 and is_random)::int as random_sent,
         (select count(*) from friendships where user_id = $1)::int as friends,
         (select count(*) from blocks where blocker_id = $1)::int as blocking,
         (select count(*) from blocks where blocked_id = $1)::int as blocked_by,
         (select count(*) from friend_requests where to_id = $1 and status = 'pending')::int as pending_requests`,
      [id],
    );
    return {
      user: userRow(u),
      counts,
      credits: { dailyLeft: Math.max(0, st.daily_free - st.daily_used), dailyFree: st.daily_free, bonus: st.bonus },
      purchases: await q(
        `select id, product_id, credits, platform, order_id, created_at, revoked_at, revoke_reason
         from purchases where user_id = $1 order by created_at desc`,
      ),
      grants: await q(
        `select g.amount, g.reason, g.created_at, a.username as admin
         from credit_grants g left join users a on a.id = g.admin_id
         where g.user_id = $1 order by g.created_at desc limit 50`,
      ),
      // Mektup içerikleri gösterilmez: yalnızca kime / ne zaman / bedel
      recentLetters: await q(
        `select l.sent_at, l.deliver_at, l.opened_at, l.cost, l.is_random, round(l.distance_km)::int as km,
           case when l.sender_id = $1 then 'out' else 'in' end as dir,
           o.username as other
         from letters l join users o on o.id = case when l.sender_id = $1 then l.recipient_id else l.sender_id end
         where l.sender_id = $1 or l.recipient_id = $1
         order by l.sent_at desc limit 20`,
      ),
      log: await q(
        `select g.action, g.details, g.created_at, a.username as admin
         from admin_log g left join users a on a.id = g.admin_id
         where g.target_user = $1 order by g.created_at desc limit 30`,
      ),
    };
  });

  // Hak ekle / düş (gerekçe zorunlu); bakiye sıfırın altına inmez
  app.post('/api/admin/users/:id/credits', {
    ...admin,
    schema: {
      body: {
        type: 'object',
        required: ['amount', 'reason'],
        properties: {
          amount: { type: 'integer', minimum: -100000, maximum: 100000, not: { const: 0 } },
          reason: { type: 'string', minLength: 3, maxLength: 200 },
        },
      },
    },
  }, async (req, reply) => {
    const u = await userOr404(reply, req.params.id);
    if (!u) return reply;
    const { amount, reason } = req.body;
    const bonus = await tx(async (c) => {
      const { rows } = await c.query(
        'update users set bonus_credits = greatest(0, bonus_credits + $2) where id = $1 returning bonus_credits',
        [u.id, amount],
      );
      const applied = rows[0].bonus_credits - u.bonus_credits;
      await c.query(
        'insert into credit_grants (user_id, admin_id, amount, reason) values ($1, $2, $3, $4)',
        [u.id, req.adminId, applied, reason.trim()],
      );
      await log(c, req, 'credits', u.id, { requested: amount, applied, reason: reason.trim() });
      return rows[0].bonus_credits;
    });
    return { bonus };
  });

  // Askıya al / kaldır: askıdaki hesap giriş yapamaz, istek atamaz, eşleşmez
  app.post('/api/admin/users/:id/ban', {
    ...admin,
    schema: {
      body: { type: 'object', required: ['reason'], properties: { reason: { type: 'string', minLength: 3, maxLength: 200 } } },
    },
  }, async (req, reply) => {
    const u = await userOr404(reply, req.params.id);
    if (!u) return reply;
    if (u.id === req.adminId) return fail(reply, 400, 'Kendi hesabını askıya alamazsın.');
    await pool.query('update users set banned_at = now(), ban_reason = $2 where id = $1', [u.id, req.body.reason.trim()]);
    await log(null, req, 'ban', u.id, { reason: req.body.reason.trim() });
    return reply.code(204).send();
  });

  app.delete('/api/admin/users/:id/ban', admin, async (req, reply) => {
    const u = await userOr404(reply, req.params.id);
    if (!u) return reply;
    await pool.query('update users set banned_at = null, ban_reason = null where id = $1', [u.id]);
    await log(null, req, 'unban', u.id);
    return reply.code(204).send();
  });

  app.put('/api/admin/users/:id/admin', {
    ...admin,
    schema: { body: { type: 'object', required: ['isAdmin'], properties: { isAdmin: { type: 'boolean' } } } },
  }, async (req, reply) => {
    const u = await userOr404(reply, req.params.id);
    if (!u) return reply;
    if (u.id === req.adminId && !req.body.isAdmin) {
      return fail(reply, 400, 'Kendi admin yetkini kaldıramazsın.');
    }
    if (u.is_bot) return fail(reply, 400, 'Bot hesaplar admin olamaz.');
    await pool.query('update users set is_admin = $2 where id = $1', [u.id, req.body.isAdmin]);
    await log(null, req, req.body.isAdmin ? 'admin_on' : 'admin_off', u.id);
    return reply.code(204).send();
  });

  app.delete('/api/admin/users/:id', {
    ...admin,
    schema: { body: { type: 'object', required: ['confirm'], properties: { confirm: { type: 'string' } } } },
  }, async (req, reply) => {
    const u = await userOr404(reply, req.params.id);
    if (!u) return reply;
    if (u.id === req.adminId) return fail(reply, 400, 'Kendi hesabını buradan silemezsin.');
    // Yanlışlıkla silmeye karşı kullanıcı adı yazılarak onaylanır
    if (req.body.confirm !== u.username) return fail(reply, 400, 'Onay için kullanıcı adını doğru yaz.');
    await pool.query('delete from users where id = $1', [u.id]);
    await log(null, req, 'delete_user', null, { username: u.username });
    return reply.code(204).send();
  });

  // ---------- satın almalar ----------
  app.get('/api/admin/purchases', {
    ...admin,
    schema: {
      querystring: {
        type: 'object',
        properties: {
          page: { type: 'integer', minimum: 0, default: 0 },
          platform: { type: 'string', enum: ['all', 'google', 'test'] },
        },
      },
    },
  }, async (req) => {
    const { page, platform = 'all' } = req.query;
    const { rows } = await pool.query(
      `select p.id, p.product_id, p.credits, p.platform, p.order_id, p.created_at, p.revoked_at, p.revoke_reason,
         u.id as user_id, u.username, count(*) over()::int as total
       from purchases p join users u on u.id = p.user_id
       where ($1 = 'all' or p.platform = $1)
       order by p.created_at desc limit ${PAGE} offset $2`,
      [platform, page * PAGE],
    );
    return { total: rows[0]?.total ?? 0, page, pageSize: PAGE, purchases: rows };
  });

  // İade: satın alma geçersiz sayılır, verilen haklar (kalan kadarı) geri alınır
  app.post('/api/admin/purchases/:id/revoke', {
    ...admin,
    schema: {
      body: { type: 'object', required: ['reason'], properties: { reason: { type: 'string', minLength: 3, maxLength: 200 } } },
    },
  }, async (req, reply) => {
    if (!UUID.test(req.params.id)) return fail(reply, 404, 'Satın alma bulunamadı.');
    const r = await tx(async (c) => {
      const { rows } = await c.query(
        `update purchases set revoked_at = now(), revoke_reason = $2
         where id = $1 and revoked_at is null returning *`,
        [req.params.id, req.body.reason.trim()],
      );
      const p = rows[0];
      if (!p) return null;
      const { rows: u } = await c.query(
        `update users set bonus_credits = greatest(0, bonus_credits - $2) where id = $1
         returning bonus_credits`,
        [p.user_id, p.credits],
      );
      await log(c, req, 'revoke_purchase', p.user_id, { purchase: p.id, product: p.product_id, reason: p.revoke_reason });
      return { bonus: u[0].bonus_credits };
    });
    if (!r) return fail(reply, 404, 'Satın alma bulunamadı ya da zaten iade edilmiş.');
    return r;
  });

  // ---------- paketler ----------
  app.get('/api/admin/products', admin, async () => {
    const { rows } = await pool.query(
      `select p.*, (select count(*) from purchases x where x.product_id = p.id and x.revoked_at is null
                      and x.platform <> 'test')::int as sold
       from products p order by p.sort, p.credits`,
    );
    return rows;
  });

  const productBody = {
    type: 'object',
    properties: {
      credits: { type: 'integer', minimum: 1, maximum: 10000 },
      active: { type: 'boolean' },
      sort: { type: 'integer', minimum: 0, maximum: 1000 },
    },
  };

  // Yeni paket: kimlik Google Play Console'daki ürün kimliğiyle aynı olmalı
  app.post('/api/admin/products', {
    ...admin,
    schema: {
      body: {
        ...productBody,
        required: ['id', 'credits'],
        properties: { ...productBody.properties, id: { type: 'string', pattern: '^[a-z0-9_.]{3,60}$' } },
      },
    },
  }, async (req, reply) => {
    const { id, credits, active = true, sort = 99 } = req.body;
    const r = await one(
      'insert into products (id, credits, active, sort) values ($1, $2, $3, $4) on conflict do nothing returning *',
      [id, credits, active, sort],
    );
    if (!r) return fail(reply, 409, 'Bu kimlikte bir paket zaten var.');
    await log(null, req, 'product_add', null, { id, credits, active });
    return reply.code(201).send(r);
  });

  app.put('/api/admin/products/:id', { ...admin, schema: { body: { ...productBody, minProperties: 1 } } },
    async (req, reply) => {
      const { credits, active, sort } = req.body;
      const r = await one(
        `update products set credits = coalesce($2, credits), active = coalesce($3, active),
           sort = coalesce($4, sort) where id = $1 returning *`,
        [req.params.id, credits ?? null, active ?? null, sort ?? null],
      );
      if (!r) return fail(reply, 404, 'Paket bulunamadı.');
      await log(null, req, 'product_edit', null, { id: r.id, ...req.body });
      return r;
    });

  // ---------- ayarlar ----------
  app.get('/api/admin/settings', admin, async () => getSettings(pool));

  app.put('/api/admin/settings', {
    ...admin,
    schema: {
      body: {
        type: 'object',
        minProperties: 1,
        additionalProperties: false,
        properties: {
          dailyFree: { type: 'integer', minimum: 0, maximum: 20 },
          instantDelivery: { type: 'boolean' },
        },
      },
    },
  }, async (req) => {
    const keys = { dailyFree: 'daily_free', instantDelivery: 'instant_delivery' };
    for (const [field, key] of Object.entries(keys)) {
      if (req.body[field] === undefined) continue;
      await pool.query(
        `insert into app_settings (key, value) values ($1, $2::jsonb)
         on conflict (key) do update set value = excluded.value`,
        [key, JSON.stringify(req.body[field])],
      );
    }
    await log(null, req, 'settings', null, req.body);
    return getSettings(pool);
  });

  // Test için: yolda olan tüm mektupları (bot cevapları dahil) hemen ulaştır
  app.post('/api/admin/letters/deliver-now', admin, async (req) => {
    const { rowCount } = await pool.query(
      `update letters set sent_at = least(sent_at, now()), deliver_at = now() where deliver_at > now()`,
    );
    await log(null, req, 'deliver_now', null, { letters: rowCount });
    return { delivered: rowCount };
  });

  // ---------- işlem kaydı ----------
  app.get('/api/admin/log', {
    ...admin,
    schema: { querystring: { type: 'object', properties: { page: { type: 'integer', minimum: 0, default: 0 } } } },
  }, async (req) => {
    const { rows } = await pool.query(
      `select g.id, g.action, g.details, g.created_at, a.username as admin, t.username as target,
         count(*) over()::int as total
       from admin_log g left join users a on a.id = g.admin_id left join users t on t.id = g.target_user
       order by g.created_at desc limit ${PAGE} offset $1`,
      [req.query.page * PAGE],
    );
    return { total: rows[0]?.total ?? 0, page: req.query.page, pageSize: PAGE, entries: rows };
  });
}
