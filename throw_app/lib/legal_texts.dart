// KVKK (6698 sayılı Kanun) metinleri. [KÖŞELİ PARANTEZ] içindeki alanlar
// yayına almadan önce şirket bilgileriyle doldurulmalı ve hukukçuya
// kontrol ettirilmelidir. Metin değişince backend/src/legal.js içindeki
// LEGAL_VERSION ile buradaki kLegalVersion birlikte artırılır.

const kLegalVersion = '2026-10-14.2';

enum LegalDoc { notice, terms }

const _controllerTr = '''
Veri sorumlusu: [ŞİRKET UNVANI]
Adres: [ADRES]
E-posta: [KVKK E-POSTA ADRESİ]
MERSİS / VERBİS: [NUMARA]''';

const _controllerEn = '''
Data controller: [COMPANY NAME]
Address: [ADDRESS]
Email: [PRIVACY EMAIL]
Registry no: [NUMBER]''';

const legalTitlesTr = {
  LegalDoc.notice: 'KVKK Aydınlatma Metni',
  LegalDoc.terms: 'Kullanım Koşulları',
};

const legalTitlesEn = {
  LegalDoc.notice: 'Privacy Notice',
  LegalDoc.terms: 'Terms of Use',
};

const legalTextsTr = {
  LegalDoc.notice: '''
toss-o olarak kişisel verilerinin güvenliğine önem veriyoruz. Bu metin, 6698 sayılı Kişisel Verilerin Korunması Kanunu'nun ("KVKK") 10. maddesi uyarınca seni bilgilendirmek için hazırlanmıştır.

1. Veri sorumlusu
$_controllerTr

2. Hangi verileri işliyoruz?
• Kimlik: adın (görünen ad) ve kullanıcı adın.
• Konum: seçtiğin il ile bu ilde rastgele seçilen yaklaşık bir nokta ve yakınındaki yerleşim adı. Cihazının GPS konumunu ALMAYIZ.
• İletişim içeriği: yazdığın ve sana gelen mektuplar, mektupların gönderim / açılma zamanı ve iki kişi arasındaki mesafe.
• Sosyal ilişkiler: arkadaşlıkların, arkadaşlık isteklerin ve engellediğin kişiler.
• Görsel: yüklersen profil fotoğrafın.
• İşlem güvenliği: şifrenin geri döndürülemez özeti (şifrenin kendisi saklanmaz), oturum anahtarı, IP adresi ve sunucu kayıtları.
• Onaylar: aydınlatma metni ve kullanım koşulları onay kayıtların (tarih ve metin sürümüyle).

3. Hangi amaçlarla ve hangi hukuki sebeplerle?
• Hesabını oluşturmak, mektuplarını iletmek, arkadaşlık ve rastgele eşleşme özelliklerini sunmak: KVKK md. 5/2-c (sözleşmenin kurulması ve ifası).
• Hizmetin ve hesabının güvenliğini sağlamak, kötüye kullanımı (ör. şifre deneme saldırıları) önlemek: KVKK md. 5/2-f (meşru menfaat).
• Yasal yükümlülüklerimizi yerine getirmek ve yetkili makamların taleplerini karşılamak: KVKK md. 5/2-ç.
Açık rızaya dayanan bir işleme faaliyetimiz yoktur.

4. Verilerin kimlerle paylaşılır?
• Diğer kullanıcılar: adın, kullanıcı adın, fotoğrafın, il / yerleşim adın ve yaklaşık konumun; arkadaşların, mektup gönderdiğin kişiler ve seni aramada bulan kişiler tarafından görülebilir. Mektubun yalnızca alıcısı tarafından okunur.
• Barındırma hizmeti: verilerin [BARINDIRMA SAĞLAYICISI], Türkiye üzerinde saklanır.
• Harita, yazı tipleri ve avatarlar: uygulama yalnızca bizim sunucularımıza bağlanır. Harita görselleri (kaynak: OpenStreetMap / OpenFreeMap) sunucumuz üzerinden önbellekli olarak iletilir; harita sağlayıcısına yalnızca sunucumuz bağlanır, IP adresin ya da başka bir verin iletilmez. Yazı tipleri ve avatarlar uygulamanın içindedir.
• Yetkili kamu kurumları: yalnızca hukuken zorunlu olduğunda.
Verilerini satmayız ve reklam amacıyla kullanmayız.

5. Yurt dışına aktarım
toss-o yalnızca Türkiye'de hizmet verir. Verilerin Türkiye'deki sunucularda saklanır ve yurt dışına aktarılmaz. Uygulama yalnızca bizim sunucularımıza bağlanır.

6. Ne kadar süre saklıyoruz?
Verilerini hesabın açık olduğu sürece saklarız. Hesabını sildiğinde mektupların, arkadaşlıkların, isteklerin ve fotoğrafın derhal ve kalıcı olarak silinir; karşı tarafa gönderdiğin mektuplar da silinir. Güvenlik kayıtları [SÜRE] süreyle tutulur.

7. Verileri nasıl topluyoruz?
Uygulamaya girdiğin bilgilerden ve uygulamayı kullanırken oluşan kayıtlardan, otomatik yollarla elektronik ortamda topluyoruz.

8. Haklarınız (KVKK md. 11)
Verilerinin işlenip işlenmediğini öğrenme, bilgi talep etme, işleme amacını öğrenme, aktarıldığı kişileri bilme, eksik / yanlış işlenmişse düzeltilmesini, silinmesini veya yok edilmesini isteme, bunların aktarılan kişilere bildirilmesini isteme, otomatik analiz sonucu aleyhine bir sonuca itiraz etme ve zarara uğradıysan giderilmesini talep etme haklarına sahipsin.
• Uygulamada: Profil'den adını, ilini ve fotoğrafını düzeltebilir; Profil > "Hesabımı sil" ile tüm verilerini silebilirsin.
• Hakkında tuttuğumuz verilerin bir kopyası ve diğer talepler için [KVKK E-POSTA ADRESİ] adresine yazabilirsin; başvurunu en geç 30 gün içinde ücretsiz yanıtlarız. Yanıtımızı yeterli bulmazsan Kişisel Verileri Koruma Kurulu'na şikâyette bulunabilirsin.

Sürüm: $kLegalVersion
''',
  LegalDoc.terms: '''
toss-o'yu kullanarak aşağıdaki koşulları kabul etmiş olursun.

1. Hizmet
toss-o, yazdığın mektubu kağıt uçak animasyonuyla arkadaşlarına ya da Türkiye'deki rastgele bir kullanıcıya göndermeni sağlar. Hizmet olduğu gibi sunulur; kesintisiz çalışacağını garanti etmeyiz.

2. Hesabın
• Uygulamayı kullanmak için en az 13 yaşında olmalısın.
• Hesabının ve şifrenin güvenliğinden sen sorumlusun; şifreni kimseyle paylaşma.
• Başkasının kimliğine bürünemezsin.

3. Kurallar
Mektuplarda ve profilinde şunları paylaşamazsın:
• Hakaret, taciz, tehdit, nefret söylemi ya da ayrımcılık,
• Müstehcen içerik, şiddet ya da yasa dışı faaliyet,
• Başkalarının kişisel verileri (adres, telefon vb.) ya da izinsiz fotoğrafları,
• Spam, reklam ya da dolandırıcılık.
Rahatsız olduğun kişiyi engelleyebilirsin. Kurallara uymayan hesapları uyarmadan askıya alabilir ya da silebiliriz.

4. İçerik
Yazdığın mektuplar sana aittir. Onları alıcıya iletebilmemiz için gereken ölçüde işlememize izin vermiş olursun. Gönderilmiş bir mektup alıcının gelen kutusunda kalır.

5. Sorumluluk
Kullanıcıların birbirine gönderdiği içerikten içeriği gönderen sorumludur. Yasaların izin verdiği ölçüde, hizmetin kullanımından doğan dolaylı zararlardan sorumlu değiliz.

6. Değişiklikler ve fesih
Koşulları değiştirebiliriz; önemli değişikliklerde uygulamada yeniden onayını isteriz. Hesabını istediğin zaman Profil > Hesabımı sil ile kapatabilirsin.

7. Uygulanacak hukuk
Bu koşullara Türkiye Cumhuriyeti hukuku uygulanır.

İletişim: [İLETİŞİM E-POSTA ADRESİ]
Sürüm: $kLegalVersion
''',
};

const legalTextsEn = {
  LegalDoc.notice: '''
At toss-o we care about the security of your personal data. This notice is provided under Article 10 of the Turkish Personal Data Protection Law No. 6698 ("KVKK").

1. Data controller
$_controllerEn

2. What data we process
• Identity: your display name and username.
• Location: the province you choose, plus an approximate point picked at random within that region and the name of a nearby place. We NEVER collect your device's GPS location.
• Communication content: the letters you write and receive, when they were sent / opened and the distance between the two people.
• Social connections: your friends, friend requests and the people you block.
• Image: your profile photo, if you upload one.
• Security: a one-way hash of your password (the password itself is never stored), session token, IP address and server logs.
• Approvals: your records of accepting the privacy notice and terms (with date and document version).

3. Why, and on what legal basis
• To create your account, deliver your letters and provide friends and random matching: KVKK Art. 5/2-c (performance of a contract).
• To keep the service and your account secure and prevent abuse (e.g. password guessing): KVKK Art. 5/2-f (legitimate interest).
• To comply with legal obligations and lawful requests from authorities: KVKK Art. 5/2-ç.
We do not carry out any processing based on explicit consent.

4. Who can see your data
• Other users: your name, username, photo, region / place name and approximate location can be seen by your friends, people you write to and people who find you in search. A letter is read only by its recipient.
• Hosting: your data is stored with [HOSTING PROVIDER], Türkiye.
• Map, fonts and avatars: the app only connects to our own servers. Map tiles (source: OpenStreetMap / OpenFreeMap) are relayed and cached by our server; only our server contacts the map provider, so your IP address and other data are never passed on. Fonts and avatars are built into the app.
• Public authorities: only where legally required.
We never sell your data or use it for advertising.

5. Transfers abroad
toss-o is only available in Türkiye. Your data is stored on servers in Türkiye and is not transferred abroad. The app only connects to our own servers.

6. How long we keep it
We keep your data while your account is open. When you delete your account, your letters, friendships, requests and photo are deleted immediately and permanently, including letters you sent to others. Security logs are kept for [PERIOD].

7. How we collect it
Electronically, from what you enter in the app and the records created while you use it.

8. Your rights (KVKK Art. 11)
You have the right to learn whether your data is processed, request information about it, learn the purpose of processing and who it is shared with, ask for incorrect data to be corrected, ask for deletion, ask for these to be notified to recipients, object to a decision against you based solely on automated processing, and claim compensation for damages.
• In the app: you can correct your name, region and photo in Profile, and erase all your data with Profile > "Delete my account".
• For a copy of the data we hold about you and other requests, write to [PRIVACY EMAIL]; we reply free of charge within 30 days. If you are not satisfied you can complain to the Turkish Personal Data Protection Board.

Version: $kLegalVersion
''',
  LegalDoc.terms: '''
By using toss-o you agree to these terms.

1. The service
toss-o lets you send a letter as a paper plane animation to your friends or to a random user in Türkiye. The service is provided as is; we don't guarantee it will be uninterrupted.

2. Your account
• You must be at least 13 years old to use the app.
• You're responsible for keeping your account and password safe; don't share your password.
• You may not impersonate anyone.

3. Rules
You may not share in letters or on your profile:
• Insults, harassment, threats, hate speech or discrimination,
• Sexually explicit content, violence or illegal activity,
• Other people's personal data (address, phone etc.) or photos without permission,
• Spam, advertising or scams.
You can block anyone who bothers you. We may suspend or delete accounts that break the rules without notice.

4. Content
Your letters belong to you. You allow us to process them as needed to deliver them to the recipient. A delivered letter stays in the recipient's inbox.

5. Liability
The sender is responsible for the content users send each other. To the extent permitted by law, we're not liable for indirect damages arising from use of the service.

6. Changes and termination
We may change these terms; for significant changes we'll ask for your approval again in the app. You can close your account any time via Profile > Delete my account.

7. Governing law
These terms are governed by the laws of the Republic of Türkiye.

Contact: [CONTACT EMAIL]
Version: $kLegalVersion
''',
};
