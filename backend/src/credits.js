// Mektup hakları ve teslim süresi kuralları.
//
// - Herkesin günde 1 ücretsiz yeni mektup hakkı var (Türkiye saatiyle gece
//   yarısı yenilenir).
// - Sana gelen her mektuba 1 cevap ücretsizdir: spam olmaz, sohbet kopmaz.
// - Bunların dışındaki her mektup satın alınmış 1 hak harcar (süresiz).
// - Mektup anında değil, mesafeye göre uçarak ulaşır.

export const DAILY_FREE = 1;
export const TZ = 'Europe/Istanbul';

/** Google Play'deki tek seferlik ürünler: ürün kimliği -> hak sayısı */
export const PRODUCTS = {
  tosso_hak_5: 5,
  tosso_hak_15: 15,
  tosso_hak_40: 40,
};

/**
 * Kağıt uçağın yolculuk süresi (dakika): aynı şehirde ~15-30 dk,
 * İstanbul -> Ankara ~3,5 sa, en uzak iller arası en fazla 12 sa.
 */
export function deliveryMinutes(km) {
  return Math.round(Math.min(720, Math.max(15, 15 + km * 0.6)));
}

// Bugün (Türkiye saatiyle) günlük ücretsiz hak kullanıldı mı
const dailyUsedSql = (userParam) => `exists(
  select 1 from letters l where l.sender_id = ${userParam} and l.cost = 'daily'
    and (l.sent_at at time zone '${TZ}')::date = (now() at time zone '${TZ}')::date)`;

/** Kullanıcının hak durumu: kalan günlük, satın alınmış hak, yenilenme zamanı */
export async function creditState(db, userId) {
  const { rows } = await db.query(
    `select u.bonus_credits as bonus, ${dailyUsedSql('u.id')} as daily_used,
       (date_trunc('day', now() at time zone '${TZ}') + interval '1 day') at time zone '${TZ}' as resets_at
     from users u where u.id = $1`,
    [userId],
  );
  return rows[0] ?? null;
}

export const creditJson = (st, { testPurchases = false } = {}) => ({
  dailyLeft: st.daily_used ? 0 : DAILY_FREE,
  bonus: st.bonus,
  resetsAt: st.resets_at,
  products: Object.entries(PRODUCTS).map(([id, credits]) => ({ id, credits })),
  testPurchases,
});

/**
 * Gönderilecek mektubun bedelini belirle ve gerekiyorsa hakkı düş.
 * Bir işlem (transaction) içinde, kullanıcı satırı kilitliyken çağrılmalı.
 * Dönüş: 'reply' | 'daily' | 'credit' ya da hak yoksa null.
 */
export async function chargeLetter(c, userId, replyTo) {
  await c.query('select 1 from users where id = $1 for update', [userId]);
  if (replyTo) {
    const { rows } = await c.query(
      `select 1 from letters where sender_id = $1 and reply_to = $2 and cost = 'reply'`,
      [userId, replyTo],
    );
    if (!rows.length) return 'reply';
  }
  const st = await creditState(c, userId);
  if (!st.daily_used) return 'daily';
  const { rowCount } = await c.query(
    'update users set bonus_credits = bonus_credits - 1 where id = $1 and bonus_credits > 0',
    [userId],
  );
  return rowCount ? 'credit' : null;
}
