// Ülke / il (bölge) / yerleşim verisi ve rastgele konum seçimi.
// Veri: data/geo.json.gz (scripts/build_geo.py ile GeoNames'ten üretilir)
import { readFileSync } from 'node:fs';
import { gunzipSync } from 'node:zlib';

const DATA = new URL('../data/geo.json.gz', import.meta.url);

const names = {
  tr: new Intl.DisplayNames(['tr'], { type: 'region' }),
  en: new Intl.DisplayNames(['en'], { type: 'region' }),
};
const collators = { tr: new Intl.Collator('tr'), en: new Intl.Collator('en') };

/** Ülke kodundan ülke adı: 'TR' -> 'Türkiye' (tr) / 'Türkiye' (en), 'DE' -> 'Almanya' / 'Germany' */
export const countryName = (code, lang = 'tr') => {
  try {
    return names[lang].of(code) ?? code;
  } catch {
    return code;
  }
};

export const sortTr = (rows, key = 'name', lang = 'tr') =>
  rows.sort((a, b) => collators[lang].compare(a[key], b[key]));

/** Ülke, bölge ve yerleşim tablolarını (boşsa) doldurur */
export async function seedGeo(pool, { log } = {}) {
  const { rows } = await pool.query('select count(*)::int as n from places');
  if (rows[0].n > 0) return false;
  const data = JSON.parse(gunzipSync(readFileSync(DATA)).toString('utf8'));

  const countries = [...new Set(data.regions.map((r) => r[0]))];
  await pool.query(
    `insert into countries (code, name)
     select * from unnest($1::text[], $2::text[]) on conflict do nothing`,
    [countries, countries.map((c) => countryName(c))],
  );
  await pool.query(
    `insert into regions (country, code, name)
     select * from unnest($1::text[], $2::text[], $3::text[]) on conflict do nothing`,
    [
      data.regions.map((r) => r[0]),
      data.regions.map((r) => r[1]),
      // Bölgesi olmayan küçük ülkelerde tek bölge ülkenin kendisidir
      data.regions.map((r) => r[2] ?? countryName(r[0])),
    ],
  );
  const BATCH = 5000;
  for (let i = 0; i < data.places.length; i += BATCH) {
    const chunk = data.places.slice(i, i + BATCH);
    await pool.query(
      `insert into places (country, region, name, lat, lng, population)
       select * from unnest($1::text[], $2::text[], $3::text[],
                            $4::float8[], $5::float8[], $6::int[])`,
      [0, 1, 2, 3, 4, 5].map((k) => chunk.map((p) => p[k])),
    );
  }
  log?.(`coğrafi veri yüklendi: ${countries.length} ülke, ${data.regions.length} bölge, ${data.places.length} yerleşim`);
  return true;
}

const rad = (d) => (d * Math.PI) / 180;

/** İki nokta arası büyük daire mesafesi (km) */
export function distanceKm(a, b) {
  const dLat = rad(b.lat - a.lat);
  const dLng = rad(b.lng - a.lng);
  const h =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(rad(a.lat)) * Math.cos(rad(b.lat)) * Math.sin(dLng / 2) ** 2;
  return 6371 * 2 * Math.asin(Math.sqrt(h));
}

/**
 * Seçilen ildeki rastgele bir noktayı döndürür.
 * Önce ildeki gerçek yerleşimlerden biri nüfusa göre (karekökle yumuşatılmış)
 * ağırlıklı seçilir, sonra büyüklüğüne göre birkaç km içinde rastgele kaydırılır.
 * Böylece kimse denizin ortasına düşmez ve gerçek konum hiç istenmez.
 */
export async function randomLocation(pool, country, region, rnd = Math.random) {
  const { rows } = await pool.query(
    `select r.name as region_name, p.name, p.lat, p.lng, p.population
     from regions r join places p on p.country = r.country and p.region = r.code
     where r.country = $1 and r.code = $2
     order by -ln(1 - random()) / sqrt(p.population) limit 1`,
    [country, region],
  );
  const p = rows[0];
  if (!p) return null;
  const maxKm = 0.4 + 0.8 * Math.log10(Math.max(p.population, 1000) / 1000);
  const d = maxKm * Math.sqrt(rnd());
  const angle = rnd() * 2 * Math.PI;
  return {
    country,
    region,
    regionName: p.region_name,
    place: p.name,
    lat: p.lat + (d * Math.cos(angle)) / 111.32,
    lng: p.lng + (d * Math.sin(angle)) / (111.32 * Math.cos(rad(p.lat))),
  };
}
