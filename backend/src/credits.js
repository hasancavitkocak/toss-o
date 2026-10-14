// Mektup hakları ve teslim süresi kuralları.
//
// - Herkesin günde N ücretsiz yeni mektup hakkı var (varsayılan 1; admin
//   panelinden değiştirilir). Türkiye saatiyle gece yarısı yenilenir.
// - Sana gelen her mektuba 1 cevap ücretsizdir: spam olmaz, sohbet kopmaz.
// - Bunların dışındaki her mektup satın alınmış 1 hak harcar (süresiz).
// - Mektup anında değil, mesafeye göre uçarak ulaşır.

export const TZ = 'Europe/Istanbul';

/** İlk kurulumdaki paketler (sonrası admin panelinden yönetilir) */
export const DEFAULT_PRODUCTS = [
  ['tosso_hak_5', 5, 1],
  ['tosso_hak_15', 15, 2],
  ['tosso_hak_40', 40, 3],
];

/**
 * Kağıt uçağın yolculuk süresi (dakika): aynı şehirde ~15-30 dk,
 * İstanbul -> Ankara ~3,5 sa, en uzak iller arası en fazla 12 sa.
 */
export function deliveryMinutes(km) {
  return Math.round(Math.min(720, Math.max(15, 15 + km * 0.6)));
}

/** Uygulama ayarları (admin panelinden değişir) */
export async function getSettings(db) {
  const { rows } = await db.query('select key, value from app_settings');
  const s = Object.fromEntries(rows.map((r) => [r.key, r.value]));
  return { dailyFree: Number(s.daily_free ?? 1) };
}

/** Satıştaki paketler, sıralı */
export async function activeProducts(db) {
  const { rows } = await db.query(
    'select id, credits from products where active order by sort, credits',
  );
  return rows;
}

/** Kullanıcının hak durumu: bugün kullanılan ücretsiz hak, satın alınmış hak, yenilenme */
export async function creditState(db, userId) {
  const { rows } = await db.query(
    `select u.bonus_credits as bonus,
       (select count(*) from letters l where l.sender_id = u.id and l.cost = 'daily'
          and (l.sent_at at time zone '${TZ}')::date = (now() at time zone '${TZ}')::date)::int as daily_used,
       (date_trunc('day', now() at time zone '${TZ}') + interval '1 day') at time zone '${TZ}' as resets_at
     from users u where u.id = $1`,
    [userId],
  );
  if (!rows[0]) return null;
  const { dailyFree } = await getSettings(db);
  return { ...rows[0], daily_free: dailyFree };
}

export const creditJson = (st, products, { testPurchases = false } = {}) => ({
  dailyLeft: Math.max(0, st.daily_free - st.daily_used),
  bonus: st.bonus,
  resetsAt: st.resets_at,
  products,
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
  if (st.daily_used < st.daily_free) return 'daily';
  const { rowCount } = await c.query(
    'update users set bonus_credits = bonus_credits - 1 where id = $1 and bonus_credits > 0',
    [userId],
  );
  return rowCount ? 'credit' : null;
}
