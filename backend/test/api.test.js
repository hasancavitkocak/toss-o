import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { PGlite } from '@electric-sql/pglite';
import { PGLiteSocketServer } from '@electric-sql/pglite-socket';
import { buildApp } from '../src/app.js';
import { createPool, grantAdmins, migrate } from '../src/db.js';
import { seed, TEST_PASSWORD } from '../src/seed.js';
import { seedGeo, randomLocation, distanceKm } from '../src/geo.js';
import { deliveryMinutes } from '../src/credits.js';

let db, server, pool, app;
const botReplies = [];

before(async () => {
  db = await PGlite.create();
  server = new PGLiteSocketServer({ db, port: 54331, host: '127.0.0.1' });
  await server.start();
  pool = createPool('postgres://postgres:postgres@127.0.0.1:54331/postgres', 1);
  await migrate(pool);
  await seedGeo(pool);
  // Diğer testler hak sınırına takılmasın: herkes bol hakla başlar;
  // hak kuralları kendi testlerinde sıfır hakla denenir
  await pool.query('alter table users alter column bonus_credits set default 1000');
  await seed(pool);
  await pool.query('update users set bonus_credits = 1000');
  app = buildApp({
    pool,
    jwtSecret: 'test',
    botAcceptMs: [10, 20],
    botReplyMs: [0, 0],
    deliveryMinutes: () => 0,
    onBotReply: (p) => botReplies.push(p),
    authRateLimit: { max: 1000, timeWindow: '1 minute' },
    allowTestPurchases: true,
    verifyGooglePurchase: async (productId, token) =>
      ({ ok: token.startsWith('good'), orderId: token.startsWith('good') ? `GPA.${token}` : null }),
  });
  await app.ready();
});

after(async () => {
  await app.close();
  await pool.end();
  await server.stop();
  await db.close();
});

const call = async (method, url, { token, body, lang } = {}) => {
  const headers = {};
  if (token) headers.authorization = `Bearer ${token}`;
  if (lang) headers['accept-language'] = lang;
  const res = await app.inject({ method, url, payload: body, headers });
  return { status: res.statusCode, body: res.body ? res.json() : null };
};

const login = async (username) =>
  (await call('POST', '/api/auth/login', { body: { username, password: TEST_PASSWORD } })).body.token;

test('giriş: doğru şifre token verir, yanlış şifre ve bot hesabı reddedilir', async () => {
  const ok = await call('POST', '/api/auth/login', { body: { username: 'Hasan ', password: TEST_PASSWORD } });
  assert.equal(ok.status, 200);
  assert.equal(ok.body.user.displayName, 'Hasan');
  assert.ok(ok.body.token);

  const bad = await call('POST', '/api/auth/login', { body: { username: 'hasan', password: 'yanlis' } });
  assert.equal(bad.status, 401);
  assert.match(bad.body.error, /hatalı/);

  const bot = await call('POST', '/api/auth/login', { body: { username: 'elif', password: TEST_PASSWORD } });
  assert.equal(bot.status, 401);
});

test('oturum olmadan korumalı uçlar 401 döner', async () => {
  assert.equal((await call('GET', '/api/me')).status, 401);
  assert.equal((await call('GET', '/api/friends', { token: 'bozuk' })).status, 401);
});

test('profil, istatistik ve arkadaş listesi veritabanından gelir', async () => {
  const token = await login('hasan');
  const me = await call('GET', '/api/me', { token });
  assert.equal(me.body.user.city, 'İstanbul');
  assert.equal(me.body.stats.unread, 1);

  const friends = await call('GET', '/api/friends', { token });
  assert.deepEqual(
    friends.body.map((f) => f.username).sort(),
    ['ayse', 'can', 'elif', 'mert', 'zeynep'],
  );
});

test('arkadaşa mektup: mesafe hesaplanır, bot cevap uçağı gönderir', async () => {
  const token = await login('hasan');
  const elif = (await call('GET', '/api/friends', { token })).body.find((f) => f.username === 'elif');
  const sent = await call('POST', '/api/letters', { token, body: { to: elif.id, body: 'canım arkadaşım,\nseni özledim!' } });
  assert.equal(sent.status, 201);
  assert.equal(sent.body.to.username, 'elif');
  assert.ok(sent.body.distanceKm > 200 && sent.body.distanceKm < 500, `${sent.body.distanceKm}`);

  await Promise.all(botReplies);
  const inbox = await call('GET', '/api/letters/inbox', { token });
  const reply = inbox.body.find((l) => l.replyTo === sent.body.id);
  assert.ok(reply, 'Elif cevap vermeli');
  assert.equal(reply.from.username, 'elif');
  assert.match(reply.body, /sevgiyle,\nelif\.$/);
  assert.equal(reply.openedAt, null);

  const opened = await call('POST', `/api/letters/${reply.id}/open`, { token });
  assert.equal(opened.status, 200);
  assert.ok(opened.body.openedAt);

  // İçerik tipi json olup gövde boşsa 500 değil 400 dönmeli
  const empty = await app.inject({
    method: 'POST',
    url: `/api/letters/${reply.id}/open`,
    headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' },
  });
  assert.equal(empty.statusCode, 400);
});

test('rastgele mektup arkadaş olmayan birine gider', async () => {
  // Eşleşme ülke içinde: Türkiye'de hasan'ın arkadaşı olmayan biri olsun
  await call('POST', '/api/auth/register', {
    body: { username: 'rastgele_tr', password: 'gizli123', displayName: 'R', country: 'TR', region: '35',
      acceptTerms: true, acceptNotice: true },
  });
  const token = await login('hasan');
  const friends = new Set((await call('GET', '/api/friends', { token })).body.map((f) => f.id));
  for (let i = 0; i < 5; i++) {
    const r = await call('POST', '/api/letters', { token, body: { to: 'random', body: 'merhaba dünya' } });
    assert.equal(r.status, 201);
    assert.ok(r.body.isRandom);
    assert.ok(!friends.has(r.body.to.id), `${r.body.to.username} arkadaş olmamalı`);
    assert.notEqual(r.body.to.username, 'hasan');
  }
  const me = await call('GET', '/api/me', { token });
  assert.equal(me.body.stats.sent, 6);
});

test('hatalı mektuplar reddedilir', async () => {
  const token = await login('hasan');
  assert.equal((await call('POST', '/api/letters', { token, body: { to: 'random', body: '   ' } })).status, 400);
  assert.equal((await call('POST', '/api/letters', { token, body: { to: 'random' } })).status, 400);
  assert.equal((await call('POST', '/api/letters', { token, body: { to: 'yok', body: 'x' } })).status, 404);
  const r = await call('POST', '/api/letters', {
    token,
    body: { to: 'random', body: 'x', replyTo: '00000000-0000-0000-0000-000000000000' },
  });
  assert.equal(r.status, 404);
});

test('kayıt ol, kullanıcı ara, arkadaş ekle; iki gerçek kullanıcı mektuplaşır', async () => {
  const reg = await call('POST', '/api/auth/register', {
    body: { username: 'deniz', password: 'gizli123', displayName: 'Deniz', country: 'TR', region: '61', acceptTerms: true, acceptNotice: true },
  });
  assert.equal(reg.status, 201);
  const token = reg.body.token;
  assert.equal(reg.body.user.city, 'Trabzon');
  assert.equal(reg.body.user.countryName, 'Türkiye');
  assert.equal('place' in reg.body.user, false); // ilçe paylaşılmaz
  // Trabzon ili sınırları içinde (kabaca)
  assert.ok(reg.body.user.lat > 40.4 && reg.body.user.lat < 41.3, `${reg.body.user.lat}`);
  assert.ok(reg.body.user.lng > 38.9 && reg.body.user.lng < 40.5, `${reg.body.user.lng}`);

  const dup = await call('POST', '/api/auth/register', {
    body: { username: 'deniz', password: 'gizli123', displayName: 'Deniz', country: 'TR', region: '61', acceptTerms: true, acceptNotice: true },
  });
  assert.equal(dup.status, 409);
  const badRegion = await call('POST', '/api/auth/register', {
    body: { username: 'deniz2', password: 'gizli123', displayName: 'D', country: 'TR', region: '999', acceptTerms: true, acceptNotice: true },
  });
  assert.equal(badRegion.status, 400);

  const found = await call('GET', '/api/users/search?q=ay', { token });
  const ayse = found.body.find((u) => u.username === 'ayse');
  assert.equal(ayse.relation, 'none');

  // Arkadaşlık isteği: ayşe onaylayana kadar arkadaş değiller
  const sentReq = await call('POST', '/api/friends/requests', { token, body: { username: 'ayse' } });
  assert.equal(sentReq.status, 201);
  assert.equal(sentReq.body.status, 'pending');
  assert.equal((await call('POST', '/api/friends/requests', { token, body: { username: 'ayse' } })).status, 409);
  assert.equal((await call('POST', '/api/friends/requests', { token, body: { username: 'deniz' } })).status, 400);
  assert.equal((await call('GET', '/api/users/search?q=ayse', { token })).body[0].relation, 'outgoing');

  const ayseToken = await login('ayse');
  const reqs = (await call('GET', '/api/friends/requests', { token: ayseToken })).body;
  const fromDeniz = reqs.incoming.find((r) => r.user.username === 'deniz');
  assert.ok(fromDeniz, 'ayşe isteği görmeli');
  assert.equal((await call('GET', '/api/me', { token: ayseToken })).body.stats.requests, 2);
  assert.equal(
    (await call('POST', `/api/friends/requests/${fromDeniz.id}/accept`, { token: ayseToken })).body.username,
    'deniz',
  );
  const denizFriends = (await call('GET', '/api/friends', { token })).body.map((f) => f.username);
  assert.ok(denizFriends.includes('ayse'));
  assert.equal((await call('POST', '/api/friends/requests', { token, body: { username: 'ayse' } })).status, 409);

  const sent = await call('POST', '/api/letters', { token, body: { to: ayse.id, body: 'selam ayşe' } });
  assert.equal(sent.status, 201);
  const inbox = await call('GET', '/api/letters/inbox', { token: ayseToken });
  assert.equal(inbox.body[0].from.username, 'deniz');
  assert.equal(inbox.body[0].body, 'selam ayşe');

  const back = await call('POST', '/api/letters', {
    token: ayseToken,
    body: { to: inbox.body[0].from.id, body: 'hoş geldin deniz', replyTo: inbox.body[0].id },
  });
  assert.equal(back.status, 201);
  assert.equal(back.body.replyTo, inbox.body[0].id);
});

test('ülke ve il listeleri: hizmet yalnızca Türkiye, 81 il Türkçe adlarla', async () => {
  const countries = (await call('GET', '/api/geo/countries')).body;
  assert.deepEqual(countries, [{ code: 'TR', name: 'Türkiye' }]);

  const iller = (await call('GET', '/api/geo/countries/tr/regions')).body;
  assert.equal(iller.length, 81);
  const names = iller.map((r) => r.name);
  for (const n of ['İstanbul', 'İzmir', 'Çanakkale', 'Niğde', 'Şanlıurfa', 'Hakkari']) {
    assert.ok(names.includes(n), `${n} listede olmalı`);
  }
  assert.ok(!names.some((n) => n.endsWith('Province')));
  // Türkçe alfabetik sıra: Çankırı, Ç ile C'den sonra gelir
  assert.ok(names.indexOf('Çankırı') > names.indexOf('Bursa'));

  assert.equal((await call('GET', '/api/geo/countries/DE/regions')).status, 404);
  assert.equal((await call('GET', '/api/geo/countries/XX/regions')).status, 404);
});

test('rastgele konum: hep seçilen ilin içinde, her seferinde farklı nokta', async () => {
  const center = { lat: 41.0, lng: 28.95 };
  const points = [];
  for (let i = 0; i < 25; i++) {
    const loc = await randomLocation(pool, 'TR', '34');
    assert.equal(loc.regionName, 'İstanbul');
    assert.ok(distanceKm(center, loc) < 90, `${loc.place} çok uzak`);
    points.push(`${loc.lat.toFixed(4)},${loc.lng.toFixed(4)}`);
  }
  assert.ok(new Set(points).size > 20, 'noktalar birbirinden farklı olmalı');
  assert.equal(await randomLocation(pool, 'TR', '999'), null);
});

test('il değiştirince kullanıcı yeni ilde yeni bir noktaya taşınır', async () => {
  const token = await login('ayse');
  const r = await call('PUT', '/api/me/location', { token, body: { region: '61' } });
  assert.equal(r.status, 200);
  assert.equal(r.body.city, 'Trabzon');
  assert.equal(r.body.countryName, 'Türkiye');
  assert.ok(distanceKm({ lat: 41.0, lng: 39.72 }, r.body) < 120);
  const abroad = await call('PUT', '/api/me/location', { token, body: { country: 'DE', region: '16' } });
  assert.equal(abroad.status, 400);
  assert.match(abroad.body.error, /yalnızca Türkiye/);
  const bad = await call('PUT', '/api/me/location', { token, body: { country: 'TR', region: '0' } });
  assert.equal(bad.status, 400);
});

test('istekler: bot onaylar, karşılıklı istek kabul sayılır, reddet ve geri al', async () => {
  const hasan = await login('hasan');
  const ayse = await login('ayse');

  // Tohum verisi: Lucía hasan'a istek atmış
  const incoming = (await call('GET', '/api/friends/requests', { token: hasan })).body.incoming;
  assert.deepEqual(incoming.map((r) => r.user.username), ['defne']);

  // Bota istek: birkaç saniye içinde kendisi onaylar
  botReplies.length = 0;
  const r = await call('POST', '/api/friends/requests', { token: hasan, body: { username: 'emre' } });
  assert.equal(r.body.status, 'pending');
  await Promise.all(botReplies);
  assert.ok((await call('GET', '/api/friends', { token: hasan })).body.some((f) => f.username === 'emre'));

  // Karşı taraf zaten istek atmışsa yeni istek kabul sayılır (kerem -> ayse)
  const kerem = await call('POST', '/api/friends/requests', { token: ayse, body: { username: 'kerem' } });
  assert.equal(kerem.body.status, 'accepted');
  assert.ok((await call('GET', '/api/friends', { token: ayse })).body.some((f) => f.username === 'kerem'));

  // Reddet: arkadaşlık kurulmaz, liste boşalır
  const defne = incoming[0];
  assert.equal((await call('POST', `/api/friends/requests/${defne.id}/decline`, { token: hasan })).status, 204);
  assert.equal((await call('POST', `/api/friends/requests/${defne.id}/accept`, { token: hasan })).status, 404);
  assert.ok(!(await call('GET', '/api/friends', { token: hasan })).body.some((f) => f.username === 'defne'));
  assert.equal((await call('GET', '/api/friends/requests', { token: hasan })).body.incoming.length, 0);

  // Başkasının isteğini kabul edemezsin; kendi isteğini geri alabilirsin
  // (bot değil: bot isteği hemen kendisi onaylayabilir)
  await register('geri_al');
  const req = await call('POST', '/api/friends/requests', { token: ayse, body: { username: 'geri_al' } });
  assert.equal((await call('POST', `/api/friends/requests/${req.body.requestId}/accept`, { token: ayse })).status, 404);
  assert.equal((await call('DELETE', `/api/friends/requests/${req.body.requestId}`, { token: ayse })).status, 204);
  assert.equal((await call('GET', '/api/friends/requests', { token: ayse })).body.outgoing.length, 0);
  await Promise.all(botReplies);
});

const register = async (username) =>
  (await call('POST', '/api/auth/register', {
    body: { username, password: 'gizli123', displayName: username, country: 'TR', region: '68', acceptTerms: true, acceptNotice: true },
  })).body;

test('arkadaşlıktan çıkar: iki taraftan da silinir, artık doğrudan mektup atılamaz', async () => {
  const a = await register('cikar_a');
  const b = await register('cikar_b');
  const r = await call('POST', '/api/friends/requests', { token: a.token, body: { username: 'cikar_b' } });
  await call('POST', `/api/friends/requests/${r.body.requestId}/accept`, { token: b.token });
  assert.equal((await call('GET', '/api/friends', { token: b.token })).body.length, 1);

  const card = await call('GET', `/api/users/${b.user.id}`, { token: a.token });
  assert.equal(card.body.relation, 'friend');
  assert.ok(card.body.friendsSince);

  assert.equal((await call('DELETE', `/api/friends/${b.user.id}`, { token: a.token })).status, 204);
  assert.equal((await call('DELETE', `/api/friends/${b.user.id}`, { token: a.token })).status, 404);
  assert.equal((await call('GET', '/api/friends', { token: b.token })).body.length, 0);
  assert.equal((await call('GET', `/api/users/${b.user.id}`, { token: a.token })).body.relation, 'none');

  // Arkadaş olmayana mektup: yalnızca onun mektubuna cevap olarak
  const direct = await call('POST', '/api/letters', { token: a.token, body: { to: b.user.id, body: 'selam' } });
  assert.equal(direct.status, 403);
});

test('engelle: arkadaşlık biter, mektup/istek gidemez, aramada ve gelen kutusunda görünmez', async () => {
  const a = await register('blok_a');
  const b = await register('blok_b');
  const r = await call('POST', '/api/friends/requests', { token: a.token, body: { username: 'blok_b' } });
  await call('POST', `/api/friends/requests/${r.body.requestId}/accept`, { token: b.token });
  await call('POST', '/api/letters', { token: b.token, body: { to: a.user.id, body: 'önceki mektup' } });
  assert.equal((await call('GET', '/api/letters/inbox', { token: a.token })).body.length, 1);

  assert.equal((await call('POST', `/api/users/${b.user.id}/block`, { token: a.token })).status, 204);
  assert.equal((await call('GET', '/api/friends', { token: a.token })).body.length, 0);
  assert.equal((await call('GET', '/api/letters/inbox', { token: a.token })).body.length, 0);
  assert.equal((await call('GET', '/api/me', { token: a.token })).body.stats.unread, 0);
  assert.deepEqual((await call('GET', '/api/blocks', { token: a.token })).body.map((u) => u.username), ['blok_b']);

  // Engellenen taraf: mektup, istek, arama, profil kartı kapalı
  assert.equal((await call('POST', '/api/letters', { token: b.token, body: { to: a.user.id, body: 'x' } })).status, 403);
  assert.equal((await call('POST', '/api/friends/requests', { token: b.token, body: { username: 'blok_a' } })).status, 404);
  assert.equal((await call('GET', '/api/users/search?q=blok_a', { token: b.token })).body.length, 0);
  assert.equal((await call('GET', `/api/users/${a.user.id}`, { token: b.token })).status, 404);
  for (let i = 0; i < 8; i++) {
    const rnd = await call('POST', '/api/letters', { token: b.token, body: { to: 'random', body: 'merhaba' } });
    assert.notEqual(rnd.body.to.id, a.user.id);
  }

  assert.equal((await call('DELETE', `/api/users/${b.user.id}/block`, { token: a.token })).status, 204);
  assert.equal((await call('GET', '/api/letters/inbox', { token: a.token })).body.length, 1);
  assert.equal((await call('GET', `/api/users/${a.user.id}`, { token: b.token })).status, 200);
});

test('profil fotoğrafı: yükle, herkese açık adresten gelir, kaldır; sahte dosya reddedilir', async () => {
  const a = await register('foto_a');
  // 1x1 PNG
  const png =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';
  const up = await call('PUT', '/api/me/avatar', { token: a.token, body: { image: png } });
  assert.equal(up.status, 200);
  assert.match(up.body.photo, /^\/users\/.+\/avatar\?v=1$/);

  const img = await app.inject({ method: 'GET', url: `/api${up.body.photo}` });
  assert.equal(img.statusCode, 200);
  assert.equal(img.headers['content-type'], 'image/png');
  assert.equal(img.rawPayload.length, Buffer.from(png, 'base64').length);

  // Başkası aradığında da yeni fotoğraf yolu görünür
  const again = await call('PUT', '/api/me/avatar', { token: a.token, body: { image: `data:image/png;base64,${png}` } });
  assert.match(again.body.photo, /v=2$/);
  const found = await call('GET', '/api/users/search?q=foto_a', { token: await login('hasan') });
  assert.equal(found.body[0].photo, again.body.photo);

  const fake = Buffer.from('<script>alert(1)</script> bu bir resim değil').toString('base64');
  assert.equal((await call('PUT', '/api/me/avatar', { token: a.token, body: { image: fake } })).status, 400);

  const del = await call('DELETE', '/api/me/avatar', { token: a.token });
  assert.equal(del.body.photo, null);
  assert.equal((await app.inject({ method: 'GET', url: `/api${up.body.photo}` })).statusCode, 404);
});

test('isim ve şifre değiştir, hesabı sil', async () => {
  const a = await register('hesap_a');
  const named = await call('PATCH', '/api/me', { token: a.token, body: { displayName: '  Yeni İsim ' } });
  assert.equal(named.body.user.displayName, 'Yeni İsim');
  assert.equal((await call('PATCH', '/api/me', { token: a.token, body: { displayName: '   ' } })).status, 400);

  const wrong = await call('PUT', '/api/me/password', { token: a.token, body: { current: 'yanlis', next: 'yepyeni1' } });
  assert.equal(wrong.status, 403);
  assert.equal(
    (await call('PUT', '/api/me/password', { token: a.token, body: { current: 'gizli123', next: 'yepyeni1' } })).status,
    204,
  );
  const relog = await call('POST', '/api/auth/login', { body: { username: 'hesap_a', password: 'yepyeni1' } });
  assert.equal(relog.status, 200);

  assert.equal((await call('DELETE', '/api/me', { token: a.token, body: { password: 'gizli123' } })).status, 403);
  assert.equal((await call('DELETE', '/api/me', { token: a.token, body: { password: 'yepyeni1' } })).status, 204);
  assert.equal((await call('GET', '/api/me', { token: a.token })).status, 401);
  assert.equal(
    (await call('POST', '/api/auth/login', { body: { username: 'hesap_a', password: 'yepyeni1' } })).status,
    401,
  );
});

test('giriş denemesi sınırı aşılınca 429 ve Türkçe mesaj', async () => {
  const limited = buildApp({ pool, jwtSecret: 'test', authRateLimit: { max: 2, timeWindow: '1 minute' } });
  await limited.ready();
  const tryLogin = () =>
    limited.inject({ method: 'POST', url: '/api/auth/login', payload: { username: 'hasan', password: 'yanlis' } });
  assert.equal((await tryLogin()).statusCode, 401);
  assert.equal((await tryLogin()).statusCode, 401);
  const res = await tryLogin();
  assert.equal(res.statusCode, 429);
  assert.match(res.json().error, /Çok fazla deneme/);
  await limited.close();
});

test('tarayıcı ön kontrolü (CORS) PUT, PATCH ve DELETE isteklerine izin verir', async () => {
  const res = await app.inject({
    method: 'OPTIONS',
    url: '/api/me/avatar',
    headers: { origin: 'http://localhost:8091', 'access-control-request-method': 'PUT' },
  });
  assert.equal(res.statusCode, 204);
  for (const m of ['PUT', 'PATCH', 'DELETE']) {
    assert.match(res.headers['access-control-allow-methods'], new RegExp(m));
  }
});

test('KVKK: onaysız kayıt reddedilir, onaylar ve metin sürümü kaydedilir', async () => {
  const body = { username: 'kvkk_a', password: 'gizli123', displayName: 'K', country: 'TR', region: '68' };
  const no = await call('POST', '/api/auth/register', { body });
  assert.equal(no.status, 400);
  assert.match(no.body.error, /Aydınlatma Metni/);
  const half = await call('POST', '/api/auth/register', { body: { ...body, acceptTerms: true } });
  assert.equal(half.status, 400);

  const ok = await call('POST', '/api/auth/register', { body: { ...body, acceptTerms: true, acceptNotice: true } });
  assert.equal(ok.status, 201);
  assert.ok(ok.body.settings.termsAcceptedAt);
  assert.ok(ok.body.settings.noticeAckAt);
  assert.equal(ok.body.settings.legalVersion, ok.body.settings.currentLegalVersion);
  assert.equal('abroadConsent' in ok.body.settings, false);

  // Metin sürümü eskiyse yeniden onay: acceptLegal güncel sürümü yazar
  const again = await call('PATCH', '/api/me', { token: ok.body.token, body: { acceptLegal: true } });
  assert.equal(again.body.settings.legalVersion, again.body.settings.currentLegalVersion);
});

test('hizmet yalnızca Türkiye: yurt dışından kayıt reddedilir, rastgele mektup Türkiye içinde kalır', async () => {
  const de = await call('POST', '/api/auth/register', {
    body: { username: 'yerli_de', password: 'gizli123', displayName: 'Y', country: 'DE', region: '16',
      acceptTerms: true, acceptNotice: true },
  });
  assert.equal(de.status, 400);
  // Ülke gönderilmezse Türkiye sayılır
  const reg = await call('POST', '/api/auth/register', {
    body: { username: 'yerli_tr', password: 'gizli123', displayName: 'Y', region: '68', acceptTerms: true, acceptNotice: true },
  });
  assert.equal(reg.status, 201);
  assert.equal(reg.body.user.country, 'TR');
  for (let i = 0; i < 15; i++) {
    const r = await call('POST', '/api/letters', { token: reg.body.token, body: { to: 'random', body: 'merhaba' } });
    assert.equal(r.status, 201);
    assert.equal(r.body.to.country, 'TR', `${r.body.to.username} Türkiye'den olmalı`);
  }
});

test('İngilizce: hata mesajları, ülke adları ve bot cevabı İngilizce', async () => {
  const bad = await call('POST', '/api/auth/login', { lang: 'en', body: { username: 'hasan', password: 'x' } });
  assert.equal(bad.body.error, 'Wrong username or password.');
  const val = await call('POST', '/api/letters', { lang: 'en-US', token: await login('hasan'), body: {} });
  assert.equal(val.body.error, 'Some information is missing or invalid.');

  const countries = (await call('GET', '/api/geo/countries', { lang: 'en' })).body;
  assert.deepEqual(countries.map((c) => c.code), ['TR']);

  const reg = await call('POST', '/api/auth/register', {
    lang: 'en',
    body: { username: 'english_a', password: 'secret12', displayName: 'Jo', region: '68',
      acceptTerms: true, acceptNotice: true },
  });
  assert.equal(reg.status, 201);
  assert.equal(reg.body.settings.lang, 'en');

  // Bot, İngilizce kullanıcıya İngilizce cevap verir
  const t = reg.body.token;
  const r = await call('POST', '/api/friends/requests', { token: t, body: { username: 'burak' } });
  botReplies.length = 0;
  await Promise.all([...botReplies]);
  await new Promise((res) => setTimeout(res, 60));
  const noah = (await call('GET', '/api/friends', { token: t })).body.find((f) => f.username === 'burak');
  assert.ok(noah, `burak isteği kabul etmeli (${r.body.status})`);
  botReplies.length = 0;
  const sent = await call('POST', '/api/letters', { token: t, body: { to: noah.id, body: 'hi burak' } });
  assert.equal(sent.status, 201);
  await Promise.all(botReplies);
  const reply = (await call('GET', '/api/letters/inbox', { token: t })).body.find((l) => l.replyTo === sent.body.id);
  assert.match(reply.body, /\nlove,\nburak\.$/);

  // Dil sonradan değiştirilebilir
  const sw = await call('PATCH', '/api/me', { token: t, body: { lang: 'tr' } });
  assert.equal(sw.body.settings.lang, 'tr');
});


const newUser = async (username, { bonus = 0 } = {}) => {
  const r = await call('POST', '/api/auth/register', {
    body: { username, password: 'gizli123', displayName: username, region: '34', acceptTerms: true, acceptNotice: true },
  });
  await pool.query('update users set bonus_credits = $2 where id = $1', [r.body.user.id, bonus]);
  return r.body;
};
const befriend = async (a, b) => {
  const r = await call('POST', '/api/friends/requests', { token: a.token, body: { username: b.user.username } });
  await call('POST', `/api/friends/requests/${r.body.requestId}/accept`, { token: b.token });
};

test('teslim süresi mesafeye göre: en az 15 dk, en fazla 12 saat', () => {
  assert.equal(deliveryMinutes(0), 15);
  assert.equal(deliveryMinutes(5), 18);
  assert.equal(deliveryMinutes(350), 225); // İstanbul -> Ankara ~3,5 sa
  assert.equal(deliveryMinutes(1250), 720); // en uzak iller arası: 12 sa sınırı
});

test('haklar: günde 1 ücretsiz mektup, gelen mektuba 1 ücretsiz cevap, sonra satın alınan hak', async () => {
  const a = await newUser('hak_a');
  const b = await newUser('hak_b');
  await befriend(a, b);

  const me0 = (await call('GET', '/api/me', { token: a.token })).body.credits;
  assert.equal(me0.dailyLeft, 1);
  assert.equal(me0.bonus, 0);
  assert.ok(me0.resetsAt);
  assert.deepEqual(me0.products.map((p) => p.credits), [5, 15, 40]);

  const first = await call('POST', '/api/letters', { token: a.token, body: { to: b.user.id, body: 'ilk' } });
  assert.equal(first.status, 201);
  assert.equal(first.body.cost, 'daily');
  assert.equal(first.body.credits.dailyLeft, 0);

  // Hak bitti: 402 ve güncel hak durumu
  const second = await call('POST', '/api/letters', { token: a.token, body: { to: b.user.id, body: 'ikinci' } });
  assert.equal(second.status, 402);
  assert.equal(second.body.code, 'no_credits');
  assert.match(second.body.error, /hakkını kullandın/);
  const rnd = await call('POST', '/api/letters', { token: a.token, body: { to: 'random', body: 'rastgele' } });
  assert.equal(rnd.status, 402);

  // b'nin günlük hakkı ayrı; a'ya gelen mektuba a ücretsiz cevap verir
  const fromB = await call('POST', '/api/letters', { token: b.token, body: { to: a.user.id, body: 'selam a' } });
  assert.equal(fromB.body.cost, 'daily');
  const rep1 = await call('POST', '/api/letters', {
    token: a.token, body: { to: b.user.id, body: 'cevap', replyTo: fromB.body.id },
  });
  assert.equal(rep1.status, 201);
  assert.equal(rep1.body.cost, 'reply');
  // Aynı mektuba ikinci cevap ücretsiz değil
  const rep2 = await call('POST', '/api/letters', {
    token: a.token, body: { to: b.user.id, body: 'cevap 2', replyTo: fromB.body.id },
  });
  assert.equal(rep2.status, 402);

  // Paket al: 5 hak eklenir, sonraki mektup haktan düşer
  const bought = await call('POST', '/api/purchases/test', { token: a.token, body: { productId: 'tosso_hak_5' } });
  assert.equal(bought.body.bonus, 5);
  const paid = await call('POST', '/api/letters', { token: a.token, body: { to: b.user.id, body: 'paralı' } });
  assert.equal(paid.body.cost, 'credit');
  assert.equal(paid.body.credits.bonus, 4);
  assert.equal(
    (await call('POST', '/api/purchases/test', { token: a.token, body: { productId: 'yok' } })).status,
    400,
  );
});

test('mektup mesafeye göre gecikmeli ulaşır: varmadan görünmez, açılamaz', async () => {
  const slow = buildApp({ pool, jwtSecret: 'test', deliveryMinutes: () => 90, botReplyMs: [0, 0] });
  await slow.ready();
  const req = async (method, url, token, body) => {
    const res = await slow.inject({ method, url, payload: body, headers: { authorization: `Bearer ${token}` } });
    return { status: res.statusCode, body: res.body ? res.json() : null };
  };
  const a = await newUser('yavas_a', { bonus: 5 });
  const b = await newUser('yavas_b');
  await befriend(a, b);

  const sent = await req('POST', '/api/letters', a.token, { to: b.user.id, body: 'yolda bir mektup' });
  assert.equal(sent.status, 201);
  const eta = (new Date(sent.body.deliverAt) - Date.now()) / 60000;
  assert.ok(eta > 85 && eta <= 90, `varış ${eta} dk sonra olmalı`);

  // Alıcı henüz göremez ve açamaz; gönderen "yolda" görür
  assert.equal((await req('GET', '/api/letters/inbox', b.token)).body.length, 0);
  assert.equal((await req('GET', '/api/me', b.token)).body.stats.unread, 0);
  assert.equal((await req('POST', `/api/letters/${sent.body.id}/open`, b.token)).status, 404);
  const mine = (await req('GET', '/api/letters/sent', a.token)).body.find((l) => l.id === sent.body.id);
  assert.ok(new Date(mine.deliverAt) > new Date());

  // Varış zamanı gelince görünür
  await pool.query("update letters set deliver_at = now() - interval '1 second' where id = $1", [sent.body.id]);
  const inbox = (await req('GET', '/api/letters/inbox', b.token)).body;
  assert.equal(inbox[0].id, sent.body.id);
  assert.equal((await req('POST', `/api/letters/${sent.body.id}/open`, b.token)).status, 200);

  // Admin "anlık teslim" açınca beklemeden ulaşır
  await pool.query(`insert into app_settings (key, value) values ('instant_delivery', 'true')
                    on conflict (key) do update set value = excluded.value`);
  const fast = await req('POST', '/api/letters', a.token, { to: b.user.id, body: 'hemen gelsin' });
  assert.ok(new Date(fast.body.deliverAt) <= new Date());
  assert.equal((await req('GET', '/api/letters/inbox', b.token)).body[0].id, fast.body.id);
  await pool.query("delete from app_settings where key = 'instant_delivery'");
  await slow.close();
});

test('Google Play satın alma: doğrulanır, aynı satın alma iki kez sayılmaz', async () => {
  const a = await newUser('play_a');
  const b = await newUser('play_b');
  const buy = (u, token, productId = 'tosso_hak_15') =>
    call('POST', '/api/purchases/google', { token: u.token, body: { productId, purchaseToken: token } });

  const ok = await buy(a, 'good-token-0001');
  assert.equal(ok.status, 200);
  assert.equal(ok.body.bonus, 15);
  // Uygulama aynı satın almayı tekrar gönderirse hak ikinci kez eklenmez
  assert.equal((await buy(a, 'good-token-0001')).body.bonus, 15);
  // Başka hesap aynı satın almayı kullanamaz
  assert.equal((await buy(b, 'good-token-0001')).status, 409);
  // Geçersiz satın alma
  assert.equal((await buy(b, 'bad-token-0001')).status, 400);
  const { rows } = await pool.query("select count(*)::int as n from purchases where purchase_token = 'good-token-0001'");
  assert.equal(rows[0].n, 1);

  // Doğrulayıcı yoksa satın alma kapalı
  const off = buildApp({ pool, jwtSecret: 'test' });
  await off.ready();
  const res = await off.inject({
    method: 'POST', url: '/api/purchases/google',
    payload: { productId: 'tosso_hak_5', purchaseToken: 'good-token-0002' },
    headers: { authorization: `Bearer ${a.token}` },
  });
  assert.equal(res.statusCode, 503);
  const test = await off.inject({
    method: 'POST', url: '/api/purchases/test', payload: { productId: 'tosso_hak_5' },
    headers: { authorization: `Bearer ${a.token}` },
  });
  assert.equal(test.statusCode, 404);
  await off.close();
});

test('admin: yetkisiz erişim reddedilir, panel güvenlik başlıklarıyla sunulur', async () => {
  const ayse = await login('ayse');
  assert.equal((await call('GET', '/api/admin/stats', { token: ayse })).status, 403);
  assert.equal((await call('GET', '/api/admin/stats')).status, 401);
  const notAdmin = await call('POST', '/api/admin/login', { body: { username: 'ayse', password: TEST_PASSWORD } });
  assert.equal(notAdmin.status, 403);

  const page = await app.inject({ method: 'GET', url: '/admin' });
  assert.equal(page.statusCode, 200);
  assert.match(page.headers['content-security-policy'], /script-src 'self'/);
  assert.equal(page.headers['x-frame-options'], 'DENY');
  assert.equal((await app.inject({ method: 'GET', url: '/admin/app.js' })).statusCode, 200);
});

test('admin: haklar, askıya alma, ayarlar, paketler, iade ve işlem kaydı', async () => {
  assert.equal(await grantAdmins(pool, 'hasan'), 1);
  const adm = await call('POST', '/api/admin/login', { body: { username: 'hasan', password: TEST_PASSWORD } });
  assert.equal(adm.status, 200);
  const t = adm.body.token;
  const hasanId = adm.body.user.id;

  const stats = await call('GET', '/api/admin/stats', { token: t });
  assert.ok(stats.body.users > 0);
  assert.equal(stats.body.days.length, 14);

  const u = await newUser('panel_u');
  const found = await call('GET', '/api/admin/users?q=panel_u', { token: t });
  assert.equal(found.body.users[0].username, 'panel_u');

  // Hak ekle / düş: bakiye sıfırın altına inmez, gerekçe zorunlu
  assert.equal((await call('POST', `/api/admin/users/${u.user.id}/credits`, { token: t, body: { amount: 10, reason: '' } })).status, 400);
  assert.equal((await call('POST', `/api/admin/users/${u.user.id}/credits`, { token: t, body: { amount: 10, reason: 'hoş geldin hediyesi' } })).body.bonus, 10);
  assert.equal((await call('POST', `/api/admin/users/${u.user.id}/credits`, { token: t, body: { amount: -100, reason: 'düzeltme' } })).body.bonus, 0);
  const detail = (await call('GET', `/api/admin/users/${u.user.id}`, { token: t })).body;
  assert.deepEqual(detail.grants.map((g) => g.amount), [-10, 10]);
  assert.equal(detail.grants[0].admin, 'hasan');
  // Panel mektup içeriği döndürmez
  assert.equal(JSON.stringify(detail).includes('"body"'), false);

  // Askıya al: giriş ve mevcut oturum kapanır, aramada çıkmaz
  assert.equal((await call('POST', `/api/admin/users/${hasanId}/ban`, { token: t, body: { reason: 'kendim' } })).status, 400);
  assert.equal((await call('POST', `/api/admin/users/${u.user.id}/ban`, { token: t, body: { reason: 'taciz şikâyeti' } })).status, 204);
  assert.equal((await call('GET', '/api/me', { token: u.token })).status, 403);
  const blocked = await call('POST', '/api/auth/login', { body: { username: 'panel_u', password: 'gizli123' } });
  assert.equal(blocked.status, 403);
  assert.match(blocked.body.error, /askıya/);
  assert.equal((await call('GET', '/api/users/search?q=panel_u', { token: await login('ayse') })).body.length, 0);
  assert.equal((await call('DELETE', `/api/admin/users/${u.user.id}/ban`, { token: t })).status, 204);
  assert.equal((await call('GET', '/api/me', { token: u.token })).status, 200);

  // Günlük ücretsiz hak: 2 yapılınca iki mektup ücretsiz
  assert.equal((await call('PUT', '/api/admin/settings', { token: t, body: { dailyFree: 2 } })).body.dailyFree, 2);
  const v = await newUser('panel_v');
  await befriend(u, v);
  assert.equal((await call('GET', '/api/credits', { token: u.token })).body.dailyLeft, 2);
  for (let i = 0; i < 2; i++) {
    const r = await call('POST', '/api/letters', { token: u.token, body: { to: v.user.id, body: `mektup ${i}` } });
    assert.equal(r.body.cost, 'daily');
  }
  assert.equal((await call('POST', '/api/letters', { token: u.token, body: { to: v.user.id, body: 'üçüncü' } })).status, 402);
  await call('PUT', '/api/admin/settings', { token: t, body: { dailyFree: 1 } });

  // Anlık teslim bayrağı ve yoldaki mektupları hemen ulaştırma
  const inst = await call('PUT', '/api/admin/settings', { token: t, body: { instantDelivery: true } });
  assert.deepEqual(inst.body, { dailyFree: 1, instantDelivery: true });
  assert.equal((await call('PUT', '/api/admin/settings', { token: t, body: {} })).status, 400);
  await call('PUT', '/api/admin/settings', { token: t, body: { instantDelivery: false } });
  const { rows: [late] } = await pool.query(
    `insert into letters (sender_id, recipient_id, body, distance_km, cost, deliver_at)
     values ($1, $2, 'yolda', 0, 'credit', now() + interval '1 hour') returning id`, [u.user.id, v.user.id]);
  assert.ok((await call('POST', '/api/admin/letters/deliver-now', { token: t })).body.delivered >= 1);
  const { rows: [landed] } = await pool.query('select deliver_at <= now() as ok from letters where id = $1', [late.id]);
  assert.ok(landed.ok);

  // Paketler: yeni paket eklenir; pasif paket uygulamada görünmez ve test satın alınamaz
  const add = await call('POST', '/api/admin/products', { token: t, body: { id: 'tosso_hak_100', credits: 100 } });
  assert.equal(add.status, 201);
  assert.equal((await call('POST', '/api/admin/products', { token: t, body: { id: 'tosso_hak_100', credits: 1 } })).status, 409);
  assert.ok((await call('GET', '/api/credits', { token: u.token })).body.products.some((p) => p.id === 'tosso_hak_100'));
  await call('PUT', '/api/admin/products/tosso_hak_100', { token: t, body: { active: false } });
  assert.ok(!(await call('GET', '/api/credits', { token: u.token })).body.products.some((p) => p.id === 'tosso_hak_100'));
  assert.equal((await call('POST', '/api/purchases/test', { token: u.token, body: { productId: 'tosso_hak_100' } })).status, 400);

  // İade: haklar bakiyeden düşer, ikinci iade yapılamaz
  await call('POST', '/api/purchases/test', { token: u.token, body: { productId: 'tosso_hak_15' } });
  const list = (await call('GET', '/api/admin/purchases?platform=test', { token: t })).body.purchases;
  const p = list.find((x) => x.username === 'panel_u');
  const rev = await call('POST', `/api/admin/purchases/${p.id}/revoke`, { token: t, body: { reason: 'kullanıcı iade istedi' } });
  assert.equal(rev.body.bonus, 0);
  assert.equal((await call('POST', `/api/admin/purchases/${p.id}/revoke`, { token: t, body: { reason: 'tekrar' } })).status, 404);

  // Admin yetkisi: kendi yetkisini kaldıramaz
  assert.equal((await call('PUT', `/api/admin/users/${hasanId}/admin`, { token: t, body: { isAdmin: false } })).status, 400);

  // Silme: kullanıcı adı yazılarak onaylanır
  assert.equal((await call('DELETE', `/api/admin/users/${v.user.id}`, { token: t, body: { confirm: 'yanlis' } })).status, 400);
  assert.equal((await call('DELETE', `/api/admin/users/${v.user.id}`, { token: t, body: { confirm: 'panel_v' } })).status, 204);

  const log = (await call('GET', '/api/admin/log', { token: t })).body.entries.map((e) => e.action);
  for (const a of ['credits', 'ban', 'unban', 'settings', 'product_add', 'product_edit', 'revoke_purchase', 'delete_user', 'deliver_now']) {
    assert.ok(log.includes(a), `${a} kaydedilmeli`);
  }
});
