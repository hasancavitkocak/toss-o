import bcrypt from 'bcryptjs';
import { randomBytes } from 'node:crypto';
import { distanceKm, randomLocation } from './geo.js';
import { LEGAL_VERSION } from './legal.js';

// Test hesapları (şifre: toss1234) ve otomatik cevap veren bot kullanıcılar.
// Konum: [ülke kodu, il/bölge kodu] — kullanıcı o ilde rastgele bir yere düşer.
const HUMANS = [
  ['hasan', 'Hasan', 'TR', '34'], // İstanbul
  ['ayse', 'Ayşe', 'TR', '16'], // Bursa
];
const BOTS = [
  ['elif', 'Elif', 'TR', '35'], // İzmir
  ['can', 'Can', 'TR', '68'], // Ankara
  ['zeynep', 'Zeynep', 'TR', '07'], // Antalya
  ['mert', 'Mert', 'DE', '16'], // Berlin
  ['yuki', 'Yuki', 'JP', '40'], // Tokyo
  ['lucia', 'Lucía', 'ES', '56'], // Katalonya
  ['noah', 'Noah', 'US', 'NY'], // New York
  ['amara', 'Amara', 'PT', '14'], // Lizbon
  ['leila', 'Leila', 'MA', '07'], // Marakeş-Safi
  ['mateo', 'Mateo', 'AR', '07'], // Buenos Aires
];
const FRIENDS = [
  ['hasan', 'elif'],
  ['hasan', 'can'],
  ['hasan', 'zeynep'],
  ['hasan', 'mert'],
  ['hasan', 'ayse'],
  ['ayse', 'elif'],
  ['ayse', 'can'],
];
// Onay bekleyen istekler: [gönderen, alıcı]
const REQUESTS = [
  ['lucia', 'hasan'],
  ['mateo', 'ayse'],
];
const LETTERS = [
  ['elif', 'hasan', 'hoş geldin !!\nilk uçağımı sana atıyorum.\nbakalım kim daha uzağa fırlatacak?\nsevgiyle,\nelif.', false, true],
  ['yuki', 'ayse', 'konnichiwa !!\ntokyodan rastgele bir merhaba.\nburada kiraz ağaçları çiçek açtı.\nyuki.', true, false],
];

export const TEST_PASSWORD = 'toss1234';

export async function seed(pool, { log } = {}) {
  const { rows } = await pool.query('select count(*)::int as n from users');
  if (rows[0].n > 0) return false;

  const humanHash = await bcrypt.hash(TEST_PASSWORD, 10);
  const users = {};
  for (const [list, isBot] of [[HUMANS, false], [BOTS, true]]) {
    for (const [username, name, country, region] of list) {
      const loc = await randomLocation(pool, country, region);
      if (!loc) throw new Error(`örnek kullanıcı için bölge yok: ${country}.${region}`);
      const hash = isBot ? await bcrypt.hash(randomBytes(16).toString('hex'), 4) : humanHash;
      const r = await pool.query(
        `insert into users (username, display_name, password_hash, city, lat, lng,
                            country, region_code, place, is_bot, lang,
                            terms_accepted_at, notice_ack_at, legal_version,
                            abroad_consent, abroad_consent_at)
         values ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, now(), now(), $12, true, now())
         returning *`,
        [username, name, hash, loc.regionName, loc.lat, loc.lng, country, region, loc.place, isBot,
          country === 'TR' ? 'tr' : 'en', LEGAL_VERSION],
      );
      users[username] = r.rows[0];
    }
  }
  for (const [a, b] of FRIENDS) {
    await pool.query(
      'insert into friendships (user_id, friend_id) values ($1, $2), ($2, $1)',
      [users[a].id, users[b].id],
    );
  }
  for (const [from, to] of REQUESTS) {
    await pool.query('insert into friend_requests (from_id, to_id) values ($1, $2)', [
      users[from].id,
      users[to].id,
    ]);
  }
  for (const [from, to, body, isRandom, unread] of LETTERS) {
    await pool.query(
      `insert into letters (sender_id, recipient_id, body, is_random, distance_km, opened_at)
       values ($1, $2, $3, $4, $5, $6)`,
      [users[from].id, users[to].id, body, isRandom, distanceKm(users[from], users[to]),
        unread ? null : new Date()],
    );
  }
  log?.(`örnek veriler eklendi: ${HUMANS.length + BOTS.length} kullanıcı`);
  return true;
}
