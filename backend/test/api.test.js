import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { PGlite } from '@electric-sql/pglite';
import { PGLiteSocketServer } from '@electric-sql/pglite-socket';
import { buildApp } from '../src/app.js';
import { createPool, migrate } from '../src/db.js';
import { seed, TEST_PASSWORD } from '../src/seed.js';
import { seedGeo, randomLocation, distanceKm } from '../src/geo.js';

let db, server, pool, app;
const botReplies = [];

before(async () => {
  db = await PGlite.create();
  server = new PGLiteSocketServer({ db, port: 54331, host: '127.0.0.1' });
  await server.start();
  pool = createPool('postgres://postgres:postgres@127.0.0.1:54331/postgres', 1);
  await migrate(pool);
  await seedGeo(pool);
  await seed(pool);
  app = buildApp({
    pool,
    jwtSecret: 'test',
    botDelayMs: [10, 20],
    onBotReply: (p) => botReplies.push(p),
    authRateLimit: { max: 1000, timeWindow: '1 minute' },
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
  assert.ok(sent.body.distanceKm > 250 && sent.body.distanceKm < 450, `${sent.body.distanceKm}`);

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
  assert.ok(reg.body.user.place);
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

test('ülke ve il listeleri: tüm dünya, Türkçe adlar, Türkiye en üstte', async () => {
  const countries = (await call('GET', '/api/geo/countries')).body;
  assert.ok(countries.length > 200, `${countries.length}`);
  assert.deepEqual(countries[0], { code: 'TR', name: 'Türkiye' });
  assert.ok(countries.some((c) => c.code === 'DE' && c.name === 'Almanya'));

  const iller = (await call('GET', '/api/geo/countries/tr/regions')).body;
  assert.equal(iller.length, 81);
  const names = iller.map((r) => r.name);
  for (const n of ['İstanbul', 'İzmir', 'Çanakkale', 'Niğde', 'Şanlıurfa', 'Hakkari']) {
    assert.ok(names.includes(n), `${n} listede olmalı`);
  }
  assert.ok(!names.some((n) => n.endsWith('Province')));
  // Türkçe alfabetik sıra: Çankırı, Ç ile C'den sonra gelir
  assert.ok(names.indexOf('Çankırı') > names.indexOf('Bursa'));

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
  const r = await call('PUT', '/api/me/location', { token, body: { country: 'de', region: '16' } });
  assert.equal(r.status, 200);
  assert.equal(r.body.city, 'Berlin');
  assert.equal(r.body.countryName, 'Almanya');
  assert.ok(distanceKm({ lat: 52.52, lng: 13.405 }, r.body) < 40);
  const bad = await call('PUT', '/api/me/location', { token, body: { country: 'TR', region: '0' } });
  assert.equal(bad.status, 400);
});

test('istekler: bot onaylar, karşılıklı istek kabul sayılır, reddet ve geri al', async () => {
  const hasan = await login('hasan');
  const ayse = await login('ayse');

  // Tohum verisi: Lucía hasan'a istek atmış
  const incoming = (await call('GET', '/api/friends/requests', { token: hasan })).body.incoming;
  assert.deepEqual(incoming.map((r) => r.user.username), ['lucia']);

  // Bota istek: birkaç saniye içinde kendisi onaylar
  botReplies.length = 0;
  const r = await call('POST', '/api/friends/requests', { token: hasan, body: { username: 'yuki' } });
  assert.equal(r.body.status, 'pending');
  await Promise.all(botReplies);
  assert.ok((await call('GET', '/api/friends', { token: hasan })).body.some((f) => f.username === 'yuki'));

  // Karşı taraf zaten istek atmışsa yeni istek kabul sayılır (mateo -> ayse)
  const mateo = await call('POST', '/api/friends/requests', { token: ayse, body: { username: 'mateo' } });
  assert.equal(mateo.body.status, 'accepted');
  assert.ok((await call('GET', '/api/friends', { token: ayse })).body.some((f) => f.username === 'mateo'));

  // Reddet: arkadaşlık kurulmaz, liste boşalır
  const lucia = incoming[0];
  assert.equal((await call('POST', `/api/friends/requests/${lucia.id}/decline`, { token: hasan })).status, 204);
  assert.equal((await call('POST', `/api/friends/requests/${lucia.id}/accept`, { token: hasan })).status, 404);
  assert.ok(!(await call('GET', '/api/friends', { token: hasan })).body.some((f) => f.username === 'lucia'));
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

test('KVKK: onaysız kayıt reddedilir, onaylar ve sürüm kaydedilir, yurt dışı rızası isteğe bağlı', async () => {
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
  assert.equal(ok.body.settings.abroadConsent, false);

  // Rıza verilir ve geri alınır
  const t = ok.body.token;
  const on = await call('PATCH', '/api/me', { token: t, body: { consentAbroad: true } });
  assert.equal(on.body.settings.abroadConsent, true);
  assert.ok(on.body.settings.abroadConsentAt);
  const off = await call('PATCH', '/api/me', { token: t, body: { consentAbroad: false } });
  assert.equal(off.body.settings.abroadConsent, false);
  assert.equal(off.body.settings.abroadConsentAt, null);
});

test('yurt dışı rızası yoksa rastgele mektup yalnızca aynı ülkeden birine gider', async () => {
  const reg = await call('POST', '/api/auth/register', {
    body: { username: 'yerli_a', password: 'gizli123', displayName: 'Y', country: 'TR', region: '68',
      acceptTerms: true, acceptNotice: true },
  });
  const t = reg.body.token;
  for (let i = 0; i < 12; i++) {
    const r = await call('POST', '/api/letters', { token: t, body: { to: 'random', body: 'merhaba' } });
    assert.equal(r.status, 201);
    assert.equal(r.body.to.country, 'TR', `${r.body.to.username} Türkiye'den olmalı`);
  }
  // Rızayla birlikte bütün dünya açılır (bot hesaplar rızalı)
  await call('PATCH', '/api/me', { token: t, body: { consentAbroad: true } });
  const countries = new Set();
  for (let i = 0; i < 40; i++) {
    const r = await call('POST', '/api/letters', { token: t, body: { to: 'random', body: 'hello' } });
    countries.add(r.body.to.country);
  }
  assert.ok(countries.size > 1, `farklı ülkeler beklenirdi: ${[...countries]}`);
});

test('İngilizce: hata mesajları, ülke adları ve bot cevabı İngilizce', async () => {
  const bad = await call('POST', '/api/auth/login', { lang: 'en', body: { username: 'hasan', password: 'x' } });
  assert.equal(bad.body.error, 'Wrong username or password.');
  const val = await call('POST', '/api/letters', { lang: 'en-US', token: await login('hasan'), body: {} });
  assert.equal(val.body.error, 'Some information is missing or invalid.');

  const countries = (await call('GET', '/api/geo/countries', { lang: 'en' })).body;
  assert.ok(countries.some((c) => c.code === 'DE' && c.name === 'Germany'));
  assert.equal(countries[0].name, 'Afghanistan');

  const reg = await call('POST', '/api/auth/register', {
    lang: 'en',
    body: { username: 'english_a', password: 'secret12', displayName: 'Jo', country: 'DE', region: '16',
      acceptTerms: true, acceptNotice: true, consentAbroad: true },
  });
  assert.equal(reg.status, 201);
  assert.equal(reg.body.settings.lang, 'en');
  assert.equal(reg.body.user.countryName, 'Germany');
  const tr = await call('GET', '/api/me', { token: reg.body.token });
  assert.equal(tr.body.user.countryName, 'Almanya');

  // Bot, İngilizce kullanıcıya İngilizce cevap verir
  const t = reg.body.token;
  const r = await call('POST', '/api/friends/requests', { token: t, body: { username: 'noah' } });
  botReplies.length = 0;
  await Promise.all([...botReplies]);
  await new Promise((res) => setTimeout(res, 60));
  const noah = (await call('GET', '/api/friends', { token: t })).body.find((f) => f.username === 'noah');
  assert.ok(noah, `noah isteği kabul etmeli (${r.body.status})`);
  botReplies.length = 0;
  const sent = await call('POST', '/api/letters', { token: t, body: { to: noah.id, body: 'hi noah' } });
  assert.equal(sent.status, 201);
  await Promise.all(botReplies);
  const reply = (await call('GET', '/api/letters/inbox', { token: t })).body.find((l) => l.replyTo === sent.body.id);
  assert.match(reply.body, /\nlove,\nnoah\.$/);

  // Dil sonradan değiştirilebilir
  const sw = await call('PATCH', '/api/me', { token: t, body: { lang: 'tr' } });
  assert.equal(sw.body.settings.lang, 'tr');
});

