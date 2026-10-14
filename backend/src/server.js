import { buildApp } from './app.js';
import { backfillLocations, createPool, migrate, waitForDb } from './db.js';
import { seed } from './seed.js';
import { seedGeo } from './geo.js';
import { googlePlayFromEnv } from './play.js';

const env = process.env;
const DEFAULT_SECRET = 'gelistirme-anahtari-degistir';

const pool = createPool(
  env.DATABASE_URL ?? 'postgres://tosso:tosso@localhost:5432/tosso',
  Number(env.PG_POOL_MAX ?? 10),
);
await waitForDb(pool, { log: console.log });
await migrate(pool);
// Ülke/il/yerleşim verisi kayıt için her zaman gerekir
await seedGeo(pool, { log: console.log });
await backfillLocations(pool);
if (env.SEED !== 'false') await seed(pool, { log: console.log });

const app = buildApp({
  pool,
  jwtSecret: env.JWT_SECRET ?? DEFAULT_SECRET,
  logger: true,
  trustProxy: env.TRUST_PROXY || false,
  verifyGooglePurchase: googlePlayFromEnv(env),
  allowTestPurchases: env.ALLOW_TEST_PURCHASES === 'true',
});
if (env.ALLOW_TEST_PURCHASES === 'true') app.log.warn('TEST SATIN ALMA AÇIK: yayında kapatılmalı');
if (!env.JWT_SECRET) app.log.warn('JWT_SECRET ayarlı değil, geliştirme anahtarı kullanılıyor');

await app.listen({ port: Number(env.PORT ?? 3000), host: env.HOST ?? '0.0.0.0' });

for (const sig of ['SIGINT', 'SIGTERM']) {
  process.on(sig, async () => {
    await app.close();
    await pool.end();
    process.exit(0);
  });
}
