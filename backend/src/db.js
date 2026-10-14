import pg from 'pg';

export function createPool(connectionString, max = 10) {
  return new pg.Pool({ connectionString, max });
}

/** Veritabanı ayağa kalkana kadar bekle (docker'da db api'den geç açılabilir) */
export async function waitForDb(pool, { tries = 30, delayMs = 1000, log } = {}) {
  for (let i = 1; ; i++) {
    try {
      await pool.query('select 1');
      return;
    } catch (err) {
      if (i >= tries) throw err;
      log?.(`veritabanı bekleniyor (${i}/${tries})…`);
      await new Promise((r) => setTimeout(r, delayMs));
    }
  }
}

const SCHEMA = `
create table if not exists countries (
  code text primary key,
  name text not null
);

create table if not exists regions (
  country text not null references countries(code),
  code text not null,
  name text not null,
  primary key (country, code)
);

create table if not exists places (
  id serial primary key,
  country text not null,
  region text not null,
  name text not null,
  lat double precision not null,
  lng double precision not null,
  population integer not null,
  foreign key (country, region) references regions(country, code)
);
create index if not exists places_region_idx on places (country, region);

create table if not exists users (
  id uuid primary key default gen_random_uuid(),
  username text not null unique,
  display_name text not null,
  password_hash text not null,
  city text not null,
  lat double precision not null,
  lng double precision not null,
  is_bot boolean not null default false,
  created_at timestamptz not null default now()
);

create table if not exists friendships (
  user_id uuid not null references users(id) on delete cascade,
  friend_id uuid not null references users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, friend_id),
  check (user_id <> friend_id)
);

create table if not exists letters (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null references users(id) on delete cascade,
  recipient_id uuid not null references users(id) on delete cascade,
  body text not null check (char_length(body) between 1 and 2000),
  is_random boolean not null default false,
  reply_to uuid references letters(id) on delete set null,
  distance_km double precision not null,
  sent_at timestamptz not null default now(),
  opened_at timestamptz
);

create table if not exists friend_requests (
  id uuid primary key default gen_random_uuid(),
  from_id uuid not null references users(id) on delete cascade,
  to_id uuid not null references users(id) on delete cascade,
  status text not null default 'pending'
    check (status in ('pending', 'accepted', 'declined', 'cancelled')),
  created_at timestamptz not null default now(),
  responded_at timestamptz,
  check (from_id <> to_id)
);
-- Aynı yönde aynı anda tek bekleyen istek olabilir
create unique index if not exists friend_requests_pending_idx
  on friend_requests (from_id, to_id) where status = 'pending';
create index if not exists friend_requests_to_idx on friend_requests (to_id, status);

-- Konum: kullanıcının seçtiği ülke + il; enlem/boylam o ilde rastgele bir nokta.
-- city = il adı (gösterim), place = yakınındaki yerleşim (ilçe/kasaba)
alter table users add column if not exists country text;
alter table users add column if not exists region_code text;
alter table users add column if not exists place text;

-- Engellenen kişi mektup / istek gönderemez, aramada ve rastgele eşleşmede çıkmaz
create table if not exists blocks (
  blocker_id uuid not null references users(id) on delete cascade,
  blocked_id uuid not null references users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);

-- Profil fotoğrafı; users.avatar_version her yüklemede artar (önbellek kırıcı)
create table if not exists avatars (
  user_id uuid primary key references users(id) on delete cascade,
  data bytea not null,
  mime text not null
);
alter table users add column if not exists avatar_version integer;

-- Arayüz dili (bot cevapları bu dilde gelir) ve KVKK kayıtları:
-- ne zaman hangi metni onayladı
alter table users add column if not exists lang text not null default 'tr';
alter table users add column if not exists terms_accepted_at timestamptz;
alter table users add column if not exists notice_ack_at timestamptz;
alter table users add column if not exists legal_version text;
-- Yurt dışı rastgele eşleşme kaldırıldı: eşleşme yalnızca aynı ülke içinde
alter table users drop column if exists abroad_consent;
alter table users drop column if exists abroad_consent_at;

-- Haklar: satın alınmış (süresiz) mektup hakları ve satın alma kayıtları
alter table users add column if not exists bonus_credits integer not null default 0;
create table if not exists purchases (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references users(id) on delete cascade,
  product_id text not null,
  credits integer not null,
  platform text not null,
  purchase_token text not null unique,
  order_id text,
  created_at timestamptz not null default now()
);

-- Mektubun bedeli (daily | reply | credit | bot | legacy) ve varış zamanı:
-- mektup mesafeye göre uçar, deliver_at gelmeden alıcı göremez
alter table letters add column if not exists cost text not null default 'legacy';
alter table letters add column if not exists deliver_at timestamptz not null default now();
create index if not exists letters_deliver_idx on letters (recipient_id, deliver_at);

create index if not exists letters_recipient_idx on letters (recipient_id, sent_at desc);
create index if not exists letters_sender_idx on letters (sender_id, sent_at desc);
`;

export async function migrate(pool) {
  await pool.query(SCHEMA);
}

/** Eski kayıtlar (yalnızca şehir adı olan) aynı adlı il ile eşleştirilir */
export async function backfillLocations(pool) {
  await pool.query(
    `update users u set country = r.country, region_code = r.code
     from regions r where u.country is null and r.name = u.city`,
  );
}
