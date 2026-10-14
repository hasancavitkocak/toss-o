// KVKK (6698 sayılı Kanun) metinleri. [KÖŞELİ PARANTEZ] içindeki alanlar
// yayına almadan önce şirket bilgileriyle doldurulmalı ve hukukçuya
// kontrol ettirilmelidir. Metin değişince backend/src/legal.js içindeki
// LEGAL_VERSION ile buradaki kLegalVersion birlikte artırılır.

const kLegalVersion = '2026-10-14';

enum LegalDoc { notice, consent, terms }

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
  LegalDoc.consent: 'Yurt Dışına Aktarım Açık Rıza Metni',
  LegalDoc.terms: 'Kullanım Koşulları',
};

const legalTitlesEn = {
  LegalDoc.notice: 'Privacy Notice',
  LegalDoc.consent: 'Explicit Consent for Transfers Abroad',
  LegalDoc.terms: 'Terms of Use',
};

const legalTextsTr = {
  LegalDoc.notice: '''
toss-o olarak kişisel verilerinin güvenliğine önem veriyoruz. Bu metin, 6698 sayılı Kişisel Verilerin Korunması Kanunu'nun ("KVKK") 10. maddesi uyarınca seni bilgilendirmek için hazırlanmıştır.

1. Veri sorumlusu
$_controllerTr

2. Hangi verileri işliyoruz?
• Kimlik: adın (görünen ad) ve kullanıcı adın.
• Konum: seçtiğin ülke ve il / bölge ile bu ilde rastgele seçilen yaklaşık bir nokta ve yakınındaki yerleşim adı. Cihazının GPS konumunu ALMAYIZ.
• İletişim içeriği: yazdığın ve sana gelen mektuplar, mektupların gönderim / açılma zamanı ve iki kişi arasındaki mesafe.
• Sosyal ilişkiler: arkadaşlıkların, arkadaşlık isteklerin ve engellediğin kişiler.
• Görsel: yüklersen profil fotoğrafın.
• İşlem güvenliği: şifrenin geri döndürülemez özeti (şifrenin kendisi saklanmaz), oturum anahtarı, IP adresi ve sunucu kayıtları.
• Tercihler: dil seçimin, onay ve rıza kayıtların (tarih ve metin sürümüyle).

3. Hangi amaçlarla ve hangi hukuki sebeplerle?
• Hesabını oluşturmak, mektuplarını iletmek, arkadaşlık ve rastgele eşleşme özelliklerini sunmak: KVKK md. 5/2-c (sözleşmenin kurulması ve ifası).
• Hizmetin ve hesabının güvenliğini sağlamak, kötüye kullanımı (ör. şifre deneme saldırıları) önlemek: KVKK md. 5/2-f (meşru menfaat).
• Yasal yükümlülüklerimizi yerine getirmek ve yetkili makamların taleplerini karşılamak: KVKK md. 5/2-ç.
• Mektuplarının yurt dışındaki kullanıcılarla rastgele eşleşmesi: KVKK md. 9 kapsamında vereceğin açık rıza (isteğe bağlı, dilediğin an geri alabilirsin).

4. Verilerin kimlerle paylaşılır?
• Diğer kullanıcılar: adın, kullanıcı adın, fotoğrafın, il / yerleşim adın ve yaklaşık konumun; arkadaşların, mektup gönderdiğin kişiler ve seni aramada bulan kişiler tarafından görülebilir. Mektubun yalnızca alıcısı tarafından okunur.
• Barındırma hizmeti: verilerin [SUNUCU KONUMU / BARINDIRMA SAĞLAYICISI] üzerinde saklanır.
• Harita ve görünüm hizmetleri: harita görselleri OpenFreeMap'ten, yazı tipleri Google Fonts'tan, hazır avatar çizimleri DiceBear'dan yüklenir. Bu hizmetler cihazının IP adresini görebilir; avatar çizimi için kullanıcı adı DiceBear'a iletilir.
• Yetkili kamu kurumları: yalnızca hukuken zorunlu olduğunda.
Verilerini satmayız ve reklam amacıyla kullanmayız.

5. Yurt dışına aktarım
Rastgele eşleşme seçeneği mektubunu dünyanın herhangi bir yerindeki bir kullanıcıya ulaştırabilir; bu durumda adın, konum bilgin ve mektubun yurt dışındaki bir kişiye aktarılmış olur. Bunu yalnızca açık rıza vermişsen yaparız. Rıza vermezsen rastgele mektupların yalnızca kendi ülkendeki kullanıcılara gider. Yurt dışındaki bir arkadaşına kendi isteğinle mektup göndermen, seninle aramızdaki sözleşmenin ifası için zorunlu bir aktarımdır (KVKK md. 9/6-b).

6. Ne kadar süre saklıyoruz?
Verilerini hesabın açık olduğu sürece saklarız. Hesabını sildiğinde mektupların, arkadaşlıkların, isteklerin ve fotoğrafın derhal ve kalıcı olarak silinir; karşı tarafa gönderdiğin mektuplar da silinir. Güvenlik kayıtları [SÜRE] süreyle tutulur.

7. Verileri nasıl topluyoruz?
Uygulamaya girdiğin bilgilerden ve uygulamayı kullanırken oluşan kayıtlardan, otomatik yollarla elektronik ortamda topluyoruz.

8. Haklarınız (KVKK md. 11)
Verilerinin işlenip işlenmediğini öğrenme, bilgi talep etme, işleme amacını öğrenme, aktarıldığı kişileri bilme, eksik / yanlış işlenmişse düzeltilmesini, silinmesini veya yok edilmesini isteme, bunların aktarılan kişilere bildirilmesini isteme, otomatik analiz sonucu aleyhine bir sonuca itiraz etme ve zarara uğradıysan giderilmesini talep etme haklarına sahipsin.
• Uygulamada: Profil > "Hesabımı sil" ile tüm verilerini silebilir, Profil > KVKK ve yasal metinler ekranından yurt dışı aktarım rızanı dilediğin an geri alabilirsin.
• Hakkında tuttuğumuz verilerin bir kopyası ve diğer talepler için [KVKK E-POSTA ADRESİ] adresine yazabilirsin; başvurunu en geç 30 gün içinde ücretsiz yanıtlarız. Yanıtımızı yeterli bulmazsan Kişisel Verileri Koruma Kurulu'na şikâyette bulunabilirsin.

Sürüm: $kLegalVersion
''',
  LegalDoc.consent: '''
KVKK Aydınlatma Metni'ni okudum. Aşağıdaki konuda özgür irademle, bilgilendirilmiş olarak açık rıza veriyorum:

"Rastgele" seçeneğiyle gönderdiğim mektupların ve bu mektuplarla birlikte görünen adımın, kullanıcı adımın, profil fotoğrafımın, il / yerleşim adımın ve yaklaşık konumumun, toss-o tarafından yurt dışında yaşayan kullanıcılara iletilmesine; aynı şekilde yurt dışındaki kullanıcıların rastgele mektuplarının bana ulaştırılabilmesi için bu bilgilerimin eşleşmede kullanılmasına.

Biliyorum ki:
• Bu rıza isteğe bağlıdır; vermezsem uygulamayı kullanmaya devam edebilirim ve rastgele mektuplarım yalnızca kendi ülkemdeki kullanıcılara gider.
• Rızamı dilediğim an Profil > KVKK ve yasal metinler ekranından geri alabilirim. Geri almam, geri almadan önce yapılmış aktarımları etkilemez.
• Yurt dışındaki alıcılar, bulundukları ülkenin hukukuna tabidir ve bu ülkelerde Türkiye'deki ile aynı düzeyde koruma bulunmayabilir.

$_controllerTr

Sürüm: $kLegalVersion
''',
  LegalDoc.terms: '''
toss-o'yu kullanarak aşağıdaki koşulları kabul etmiş olursun.

1. Hizmet
toss-o, yazdığın mektubu kağıt uçak animasyonuyla arkadaşlarına ya da rastgele bir kullanıcıya göndermeni sağlar. Hizmet olduğu gibi sunulur; kesintisiz çalışacağını garanti etmeyiz.

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
• Location: the country and region you choose, plus an approximate point picked at random within that region and the name of a nearby place. We NEVER collect your device's GPS location.
• Communication content: the letters you write and receive, when they were sent / opened and the distance between the two people.
• Social connections: your friends, friend requests and the people you block.
• Image: your profile photo, if you upload one.
• Security: a one-way hash of your password (the password itself is never stored), session token, IP address and server logs.
• Preferences: your language and your consent records (with date and document version).

3. Why, and on what legal basis
• To create your account, deliver your letters and provide friends and random matching: KVKK Art. 5/2-c (performance of a contract).
• To keep the service and your account secure and prevent abuse (e.g. password guessing): KVKK Art. 5/2-f (legitimate interest).
• To comply with legal obligations and lawful requests from authorities: KVKK Art. 5/2-ç.
• To match your random letters with users abroad: your explicit consent under KVKK Art. 9 (optional, withdrawable at any time).

4. Who can see your data
• Other users: your name, username, photo, region / place name and approximate location can be seen by your friends, people you write to and people who find you in search. A letter is read only by its recipient.
• Hosting: your data is stored with [SERVER LOCATION / HOSTING PROVIDER].
• Map and display services: map tiles load from OpenFreeMap, fonts from Google Fonts and default avatar drawings from DiceBear. These services may see your device's IP address; your username is sent to DiceBear to draw your avatar.
• Public authorities: only where legally required.
We never sell your data or use it for advertising.

5. Transfers abroad
The random option can deliver your letter to a user anywhere in the world, which means your name, location details and letter are transferred to someone abroad. We only do this if you give explicit consent. Without it, your random letters only go to users in your own country. Sending a letter to a friend abroad at your own request is a transfer necessary to perform our contract with you (KVKK Art. 9/6-b).

6. How long we keep it
We keep your data while your account is open. When you delete your account, your letters, friendships, requests and photo are deleted immediately and permanently, including letters you sent to others. Security logs are kept for [PERIOD].

7. How we collect it
Electronically, from what you enter in the app and the records created while you use it.

8. Your rights (KVKK Art. 11)
You have the right to learn whether your data is processed, request information about it, learn the purpose of processing and who it is shared with, ask for incorrect data to be corrected, ask for deletion, ask for these to be notified to recipients, object to a decision against you based solely on automated processing, and claim compensation for damages.
• In the app: Profile > "Delete my account" erases all your data, and you can withdraw your consent for transfers abroad at any time in Profile > Privacy & legal.
• For a copy of the data we hold about you and other requests, write to [PRIVACY EMAIL]; we reply free of charge within 30 days. If you are not satisfied you can complain to the Turkish Personal Data Protection Board.

Version: $kLegalVersion
''',
  LegalDoc.consent: '''
I have read the Privacy Notice. Freely and on an informed basis, I give my explicit consent to the following:

toss-o may deliver the letters I send with the "Random" option, together with my display name, username, profile photo, region / place name and approximate location, to users living outside Türkiye; and may use this information in matching so that random letters from users abroad can reach me.

I understand that:
• This consent is optional. Without it I can keep using the app and my random letters only go to users in my own country.
• I can withdraw it at any time in Profile > Privacy & legal. Withdrawal does not affect transfers made before it.
• Recipients abroad are subject to the laws of their country, which may not offer the same level of protection as Türkiye.

$_controllerEn

Version: $kLegalVersion
''',
  LegalDoc.terms: '''
By using toss-o you agree to these terms.

1. The service
toss-o lets you send a letter as a paper plane animation to your friends or to a random user. The service is provided as is; we don't guarantee it will be uninterrupted.

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
