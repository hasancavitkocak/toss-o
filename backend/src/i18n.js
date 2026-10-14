// API dili: istemci `Accept-Language: en` gönderirse hata mesajları ve ülke
// adları İngilizce döner. Mesajlar kodda Türkçe yazılır, burada çevrilir.

const EN = {
  'Alıcı bulunamadı.': 'Recipient not found.',
  'Arkadaş bulunamadı.': 'Friend not found.',
  'Boş mektup gönderilemez.': "You can't send an empty letter.",
  'Bu il / bölge bulunamadı.': 'Region not found.',
  'Bu kişiye uçak gönderemezsin.': "You can't send a plane to this person.",
  'Bu kullanıcı adı alınmış.': 'This username is taken.',
  'Bu kullanıcı bulunamadı.': 'User not found.',
  'Bu ülke bulunamadı.': 'Country not found.',
  'Cevap verilen mektup bulunamadı.': 'The letter you are replying to was not found.',
  'Cevap, mektubu gönderen kişiye gitmeli.': 'A reply must go to the person who sent the letter.',
  'Fotoğraf bulunamadı.': 'Photo not found.',
  'Fotoğraf çok büyük, en fazla 2,5 MB olabilir.': 'Photo is too large, max 2.5 MB.',
  'Gönderilen dosya çok büyük.': 'The file is too large.',
  'Kendine istek gönderemezsin.': "You can't send a request to yourself.",
  'Kendine uçak atamazsın.': "You can't send a plane to yourself.",
  'Kendini engelleyemezsin.': "You can't block yourself.",
  'Kullanıcı adı ya da şifre hatalı.': 'Wrong username or password.',
  'Mektup bulunamadı.': 'Letter not found.',
  'Mevcut şifren hatalı.': 'Your current password is wrong.',
  'Oturumun geçersiz, lütfen tekrar giriş yap.': 'Your session has expired, please log in again.',
  'Sunucuda bir sorun oluştu, birazdan tekrar dene.': 'Something went wrong on our side, please try again shortly.',
  'Yalnızca JPG, PNG ya da WEBP fotoğraf yüklenebilir.': 'Only JPG, PNG or WEBP photos can be uploaded.',
  'Yalnızca arkadaşlarına ya da sana yazan birine uçak gönderebilirsin.':
    'You can only send planes to friends or to someone who wrote to you.',
  'Zaten arkadaşsınız.': "You're already friends.",
  'Çok fazla deneme yaptın, bir dakika bekleyip tekrar dene.': 'Too many attempts, please wait a minute and try again.',
  'İsim boş olamaz.': "Name can't be empty.",
  'İstek bulunamadı.': 'Request not found.',
  'İsteğin zaten gönderildi, onay bekleniyor.': 'Request already sent, waiting for approval.',
  'Şifren hatalı.': 'Wrong password.',
  'Eksik ya da hatalı bilgi gönderildi.': 'Some information is missing or invalid.',
  "toss-o şu an yalnızca Türkiye'de kullanılabilir.": 'toss-o is currently only available in Türkiye.',
  'Bugünkü ücretsiz mektup hakkını kullandın. Yarın yeni hakkın gelir ya da ek hak alabilirsin.':
    "You've used today's free letter. You'll get a new one tomorrow, or you can buy more.",
  'Satın alma şu an kullanılamıyor.': 'Purchases are not available right now.',
  'Satın alma doğrulanamadı, birazdan tekrar dene.': "We couldn't verify the purchase, please try again shortly.",
  'Satın alma geçersiz.': 'Invalid purchase.',
  'Bu satın alma başka bir hesapta kullanılmış.': 'This purchase was already used on another account.',
  'Hesabın askıya alındı.': 'Your account has been suspended.',
  'Bu paket bulunamadı.': 'Package not found.',
  'Bu işlem için yetkin yok.': "You don't have permission for this.",
  'Kayıt için Kullanım Koşulları ve Aydınlatma Metni onaylanmalı.':
    'You must accept the Terms of Use and the Privacy Notice to sign up.',
};

/** İstek dili: yalnızca 'tr' ya da 'en' */
export const langOf = (req) =>
  /^en\b/i.test(req?.headers?.['accept-language'] ?? '') ? 'en' : 'tr';

export const translate = (msg, lang) => (lang === 'en' ? EN[msg] ?? msg : msg);

export const MESSAGES = Object.keys(EN);
