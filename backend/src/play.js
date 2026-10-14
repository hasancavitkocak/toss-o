// Google Play satın alma doğrulaması (Google Play Developer API).
// Gerekli ortam değişkenleri:
//   GOOGLE_PLAY_PACKAGE          uygulama paket adı (ör. com.tosso.app)
//   GOOGLE_PLAY_SERVICE_ACCOUNT  Play Console'a bağlı servis hesabının JSON
//                                anahtarı (dosya yolu ya da JSON metni)
import { createSign } from 'node:crypto';
import { readFileSync } from 'node:fs';

const b64url = (s) => Buffer.from(s).toString('base64url');

/** Ortam değişkenlerinden doğrulayıcı kur; ayarlı değilse null */
export function googlePlayFromEnv(env) {
  const pkg = env.GOOGLE_PLAY_PACKAGE;
  const raw = env.GOOGLE_PLAY_SERVICE_ACCOUNT;
  if (!pkg || !raw) return null;
  const sa = JSON.parse(raw.trim().startsWith('{') ? raw : readFileSync(raw, 'utf8'));
  return googlePlayVerifier({ packageName: pkg, serviceAccount: sa });
}

export function googlePlayVerifier({ packageName, serviceAccount }) {
  let cached = null;

  // Servis hesabıyla imzalı JWT -> OAuth erişim anahtarı
  async function accessToken() {
    if (cached && cached.exp > Date.now() + 60_000) return cached.token;
    const now = Math.floor(Date.now() / 1000);
    const head = b64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
    const claim = b64url(JSON.stringify({
      iss: serviceAccount.client_email,
      scope: 'https://www.googleapis.com/auth/androidpublisher',
      aud: 'https://oauth2.googleapis.com/token',
      iat: now,
      exp: now + 3600,
    }));
    const sig = createSign('RSA-SHA256').update(`${head}.${claim}`).sign(serviceAccount.private_key, 'base64url');
    const res = await fetch('https://oauth2.googleapis.com/token', {
      method: 'POST',
      headers: { 'content-type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
        assertion: `${head}.${claim}.${sig}`,
      }),
    });
    if (!res.ok) throw new Error(`Google OAuth hatası: ${res.status}`);
    const j = await res.json();
    cached = { token: j.access_token, exp: Date.now() + j.expires_in * 1000 };
    return cached.token;
  }

  /** Satın alma geçerli mi: { ok, orderId } */
  return async function verify(productId, purchaseToken) {
    const url = `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${
      encodeURIComponent(packageName)}/purchases/products/${encodeURIComponent(productId)}/tokens/${
      encodeURIComponent(purchaseToken)}`;
    const res = await fetch(url, { headers: { authorization: `Bearer ${await accessToken()}` } });
    if (res.status === 400 || res.status === 404 || res.status === 410) return { ok: false };
    if (!res.ok) throw new Error(`Google Play doğrulama hatası: ${res.status}`);
    const p = await res.json();
    // purchaseState 0 = satın alındı (1 iptal, 2 beklemede)
    return { ok: p.purchaseState === 0, orderId: p.orderId ?? null };
  };
}
