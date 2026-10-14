// Docker olmadan geliştirme: PGlite (WASM Postgres) gerçek Postgres protokolüyle
// yerelde ayağa kalkar, API ona bağlanır. Veriler .devdata/ altında kalır.
import { PGlite } from '@electric-sql/pglite';
import { PGLiteSocketServer } from '@electric-sql/pglite-socket';

const port = Number(process.env.DEV_DB_PORT ?? 54329);
const db = await PGlite.create(process.env.DEV_DB_DIR ?? './.devdata');
const server = new PGLiteSocketServer({ db, port, host: '127.0.0.1' });
await server.start();
console.log(`PGlite veritabanı 127.0.0.1:${port} üzerinde`);

// Geliştirmede ödeme yapmadan hak eklenebilsin (mağazadaki test butonları)
process.env.ALLOW_TEST_PURCHASES ??= 'true';
// Geliştirmede deneme hesabı hasan admin paneline girebilir
process.env.ADMIN_USERNAMES ??= 'hasan';
process.env.DATABASE_URL ??= `postgres://postgres:postgres@127.0.0.1:${port}/postgres`;
process.env.PG_POOL_MAX ??= '1';
await import('../src/server.js');
