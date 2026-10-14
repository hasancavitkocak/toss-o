# toss-o

Mektubunu yaz, kağıdı aşağı kaydırıp uçak yap, parmağınla it — kağıt uçak 3D
harita üzerinde bulutların arasından arkadaşına (ya da dünyanın bir yerindeki
rastgele birine) uçsun. Cevaplar da uçak olarak geri gelir.

```
throw_app/
├── docker-compose.yml   # db + api + web
├── .env.example         # JWT_SECRET, DB_PASSWORD
├── backend/             # Node.js (Fastify) + PostgreSQL API
├── web/                 # Flutter web derlemesi + nginx (Dockerfile)
└── throw_app/           # Flutter uygulaması (Android + web)
```

## Docker ile çalıştırma

Gerekenler: Docker Desktop (Windows'ta WSL2 ile).

```bash
cp .env.example .env          # JWT_SECRET'i uzun rastgele bir değerle değiştir
docker compose up --build
```

| Servis | Adres | Ne yapar |
|---|---|---|
| web | http://localhost:8080 | Flutter web uygulaması; `/api` isteklerini api'ye iletir |
| api | http://localhost:3000/api | REST API |
| db  | (iç ağ) | PostgreSQL 16, veriler `pgdata` biriminde kalır |

İlk açılışta tablolar kurulur ve örnek veriler eklenir (`SEED=false` ile kapatılır).

### Deneme hesapları

| Kullanıcı | Şifre | Şehir |
|---|---|---|
| `hasan` | `toss1234` | İstanbul |
| `ayse` | `toss1234` | Bursa |

Elif, Can, Zeynep, Mert, Yuki, Lucía, Noah, Amara, Leila ve Mateo **bot**
kullanıcılardır: onlara giden her mektuba birkaç saniye içinde cevap uçağı
gönderirler. İki gerçek kullanıcı (hasan ↔ ayse) birbirine de yazabilir.

## Telefonda (Android)

Uygulama varsayılan olarak `http://localhost:8080/api` adresine bağlanır.
USB ile bağlı telefonda bilgisayardaki sunucuya yönlendirmek için:

```bash
adb reverse tcp:8080 tcp:8080     # docker ile
adb reverse tcp:8080 tcp:3000     # docker'sız geliştirmede (aşağıya bak)
cd throw_app && flutter run
```

Aynı Wi-Fi'daki telefon için adresi derlerken ver:
`flutter run --dart-define=API_URL=http://<bilgisayar-ip>:3000/api`

## Docker olmadan geliştirme

`backend/scripts/dev.js`, PGlite (WASM Postgres) ile gerçek Postgres
protokolünü yerelde açar; API birebir aynı kodla ona bağlanır.

```bash
cd backend && npm install
JWT_SECRET=gelistirme npm run dev          # API: http://localhost:3000
npm test                                   # API testleri

cd ../throw_app
flutter run -d chrome --dart-define=API_URL=http://localhost:3000/api
flutter test
```

## API

Tüm uçlar `/api` altında; oturum gerektirenler `Authorization: Bearer <token>` ister.
Hata yanıtları `{ "error": "Türkçe mesaj" }` biçimindedir.

| Yöntem | Yol | Açıklama |
|---|---|---|
| GET | `/health` | Sağlık kontrolü |
| GET | `/geo/countries` | Tüm ülkeler (Türkçe adlar, Türkiye en üstte) |
| GET | `/geo/countries/:code/regions` | O ülkenin illeri / bölgeleri |
| POST | `/auth/register` | `{username, password, displayName, country, region, lang, acceptTerms, acceptNotice, consentAbroad?}` → `{token, user, settings}` |
| POST | `/auth/login` | `{username, password}` → `{token, user}` |
| GET | `/me` | Profil + istatistik (gönderilen, gelen, okunmamış, istek, şehir) |
| PATCH | `/me` | `{displayName?, lang?, consentAbroad?, acceptLegal?}`: isim, dil, yurt dışı rızası, güncel yasal metin onayı |
| PUT | `/me/location` | `{country, region}` ile il değiştir |
| PUT | `/me/password` | `{current, next}` ile şifre değiştir |
| DELETE | `/me` | `{password}` ile hesabı ve tüm verileri sil |
| PUT | `/me/avatar` | `{image: base64}` profil fotoğrafı (JPG/PNG/WEBP, en fazla 2,5 MB) |
| DELETE | `/me/avatar` | Profil fotoğrafını kaldır |
| GET | `/users/:id/avatar` | Profil fotoğrafı (herkese açık, oturumsuz) |
| GET | `/users/:id` | Kişi kartı: ilişki, aradaki mektup sayıları, arkadaşlık tarihi |
| GET | `/users/search?q=` | Kullanıcı ara (her sonuçta `relation`: friend / incoming / outgoing / none) |
| GET | `/friends` | Arkadaş listesi |
| DELETE | `/friends/:id` | Arkadaşlıktan çıkar (iki taraftan da) |
| GET | `/friends/requests` | Bekleyen istekler: `{incoming, outgoing}` |
| POST | `/friends/requests` | `{username}` ile istek gönder (karşı taraf da istemişse hemen arkadaş olunur) |
| POST | `/friends/requests/:id/accept` | İsteği kabul et |
| POST | `/friends/requests/:id/decline` | İsteği reddet |
| DELETE | `/friends/requests/:id` | Gönderdiğin isteği geri al |
| GET | `/blocks` | Engellediklerin |
| POST | `/users/:id/block` | Engelle (arkadaşlık biter, bekleyen istekler iptal olur) |
| DELETE | `/users/:id/block` | Engeli kaldır |
| POST | `/letters` | `{to: <kullanıcı id> \| "random", body, replyTo?}` → mektup + alıcı |
| GET | `/letters/inbox` | Gelen mektuplar |
| GET | `/letters/sent` | Gönderilen mektuplar (`openedAt` ile okundu bilgisi) |
| POST | `/letters/:id/open` | Mektubu okundu işaretle |

Kurallar:

- Rastgele gönderimde alıcı, arkadaşın olmayan ve engelleşmediğin kullanıcılar arasından seçilir.
- Arkadaş olmayan birine yalnızca **sana yazdığı mektuba cevap** olarak yazılabilir.
- Engellenen kişi sana mektup ya da istek gönderemez, seni aramada göremez; ondan gelen eski mektuplar gelen kutundan gizlenir.
- Giriş, kayıt, şifre değiştirme ve hesap silme IP başına dakikada 10 denemeyle sınırlıdır.

## Konum nasıl belirlenir?

Kullanıcıdan gerçek konum (GPS) **istenmez**. Kayıtta ülke ve il seçilir; sunucu:

1. O ildeki gerçek yerleşimlerden (ilçe, kasaba — nüfusu 1000+) birini nüfusa
   göre ağırlıklı seçer (karekökle yumuşatılır, böylece herkes il merkezine yığılmaz),
2. Noktayı yerleşimin büyüklüğüne göre 0,4–4 km içinde rastgele kaydırır.

Kullanıcı haritada "Ataşehir, İstanbul" gibi gerçekçi bir yerde görünür ama tam
adresi bilinmez. Profilden il değiştirilebilir.

Veri: [GeoNames](https://www.geonames.org/) (CC BY 4.0) — 238 ülke, 3.560 il/bölge,
148.000 yerleşim. `backend/data/geo.json.gz` dosyası `python scripts/build_geo.py`
ile yeniden üretilir; API ilk açılışta veritabanına yükler.

## Dil

Uygulama Türkçe ve İngilizce. İlk açılışta cihaz dili seçilir; giriş
ekranında ve Profil'de **TR | EN** ile değiştirilir. Seçim sunucuya da
kaydedilir: istemci her istekte `Accept-Language` gönderir, API hata
mesajlarını ve ülke adlarını o dilde döner; bot cevapları da kullanıcının
dilinde gelir. Uygulama metinleri `throw_app/lib/i18n.dart`, API çevirileri
`backend/src/i18n.js` içindedir.

## KVKK

- **Metinler:** `throw_app/lib/legal_texts.dart` dosyasında Aydınlatma Metni (KVKK md. 10), Yurt Dışına Aktarım Açık Rıza Metni (md. 9) ve Kullanım Koşulları var (TR + EN).
  **Yayına almadan önce** `[ŞİRKET UNVANI]`, `[ADRES]`, `[KVKK E-POSTA ADRESİ]`, `[SUNUCU KONUMU]`, `[SÜRE]` gibi alanları doldurup metni bir hukukçuya kontrol ettirin.
- **Kayıt:** Aydınlatma Metni ve Kullanım Koşulları onayı zorunlu. Yurt dışı aktarım rızası isteğe bağlı; açık rıza hizmet şartı yapılamaz. Onaylar tarih ve metin sürümüyle (`users.legal_version`) saklanır.
- **Rastgele eşleşme:** Rıza vermeyen kullanıcının rastgele mektubu yalnızca kendi ülkesindeki kullanıcılara gider. Rıza veren de yalnızca rıza vermiş yabancılarla eşleşir.
- **Metin değişirse:** `backend/src/legal.js` içindeki `LEGAL_VERSION` ile `legal_texts.dart` içindeki `kLegalVersion` birlikte artırılır. Uygulama açılışta kullanıcıdan yeniden onay ister.
- **Haklar (md. 11):** Profil > KVKK ve yasal metinler ekranında yurt dışı rızası açılıp kapatılır, Profil > Hesabımı sil tüm verileri siler; veri kopyası gibi diğer talepler metindeki e-posta adresine yapılır.
- **Toplanmayan veriler:** GPS konumu ve ses kaydı alınmaz; sesli yazma özelliği kaldırıldı, mikrofon izni yok.
