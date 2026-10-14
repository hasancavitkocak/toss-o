// Uygulama metinleri: Türkçe ve İngilizce. Her metin iki dilde yan yana durur,
// böylece biri eklenip diğeri unutulmaz. Kullanım: `txt.login`, `txt.toName(n)`.
import 'package:flutter/widgets.dart';
import 'tr.dart';

enum Lang { tr, en }

/// Uygulama dili. toss-o şu an yalnızca Türkiye'de ve Türkçe; İngilizce
/// metinler ileride açılabilsin diye her metnin yanında duruyor.
final language = ValueNotifier<Lang>(Lang.tr);

S get txt => language.value == Lang.en ? const S(true) : const S(false);

class S {
  final bool en;
  const S(this.en);
  String _(String tr, String en) => this.en ? en : tr;

  String get code => en ? 'en' : 'tr';
  String get languageName => _('Türkçe', 'English');

  // ---------- Türkçe ekler / İngilizce edatlar ----------
  /// "Elif'e" / "to Elif"
  String toName(String n) => en ? 'to $n' : dative(n);

  /// "Elif'ten" / "from Elif"
  String fromName(String n) => en ? 'from $n' : ablative(n);

  String km(num v) {
    final str = v.round().toString();
    final b = StringBuffer();
    for (var i = 0; i < str.length; i++) {
      if (i > 0 && (str.length - i) % 3 == 0) b.write(en ? ',' : '.');
      b.write(str[i]);
    }
    return '$b km';
  }

  String ago(DateTime t, [DateTime? now]) {
    final d = (now ?? DateTime.now()).difference(t);
    if (d.inMinutes < 1) return _('az önce', 'just now');
    if (d.inHours < 1) {
      return _('${d.inMinutes} dk önce', '${d.inMinutes} min ago');
    }
    if (d.inDays < 1) return _('${d.inHours} sa önce', '${d.inHours} h ago');
    if (d.inDays < 7) return _('${d.inDays} gün önce', '${d.inDays} d ago');
    return date(t);
  }

  String date(DateTime t) => en
      ? '${const [
          'Jan',
          'Feb',
          'Mar',
          'Apr',
          'May',
          'Jun',
          'Jul',
          'Aug',
          'Sep',
          'Oct',
          'Nov',
          'Dec'
        ][t.month - 1]} ${t.day}, ${t.year}'
      : '${t.day}.${t.month}.${t.year}';

  // ---------- genel ----------
  String get serverUnreachable => _(
      'Sunucuya ulaşılamadı. İnternetini ve sunucunun açık olduğunu kontrol et.',
      "Can't reach the server. Check your internet connection.");
  String get unexpectedError =>
      _('Beklenmeyen bir hata oluştu.', 'Something went wrong.');
  String get save => _('Kaydet', 'Save');
  String get close => _('kapat', 'close');
  String get search => _('ara', 'search');
  String get noResults => _('Sonuç yok', 'No results');
  String get listFailed => _('Liste yüklenemedi.', "Couldn't load the list.");
  String get sent => _('gönderilen', 'sent');
  String get received => _('gelen', 'received');
  String get cities => _('şehir', 'cities');

  // ---------- giriş / kayıt ----------
  String get tagline => _('mektubunu kağıt uçak yap,\nsevdiklerine fırlat.',
      'fold your letter into a paper plane,\nthrow it to someone you love.');
  String get yourName => _('Adın', 'Your name');
  String get username => _('Kullanıcı adı', 'Username');
  String get password => _('Şifre', 'Password');
  String get createAccount => _('Hesap oluştur', 'Create account');
  String get login => _('Giriş yap', 'Log in');
  String get haveAccount =>
      _('Zaten hesabın var mı? Giriş yap', 'Already have an account? Log in');
  String get noAccount => _('Hesabın yok mu? Kayıt ol', 'New here? Sign up');
  String get testAccount => _(
      'Deneme hesabı: hasan / toss1234 (ya da ayse)\nDoldurmak için dokun',
      'Test account: hasan / toss1234 (or ayse)\nTap to fill in');
  String get errCredentials =>
      _('Kullanıcı adı ve şifreyi yaz.', 'Enter your username and password.');
  String get errName => _('Adını yaz.', 'Enter your name.');
  String get errLocation =>
      _('Ülkeni ve ilini seç.', 'Choose your country and region.');
  String get errUsername => _(
      'Kullanıcı adı 3-20 karakter olmalı; küçük harf, rakam, _ ve . kullanabilirsin.',
      'Username must be 3-20 characters: lowercase letters, digits, _ and .');
  String get errPassword => _('Şifre en az 6 karakter olmalı.',
      'Password must be at least 6 characters.');
  String get errConsent => _(
      'Devam etmek için Aydınlatma Metni\'ni okuduğunu onayla.',
      'Please confirm you have read the Privacy Notice to continue.');
  String get consentNotice => _('Aydınlatma Metni\'ni okudum ve anladım.',
      'I have read and understood the Privacy Notice.');
  String get consentTerms =>
      _('Kullanım Koşulları\'nı kabul ediyorum.', 'I accept the Terms of Use.');
  String get read => _('oku', 'read');

  // ---------- konum ----------
  String get country => _('Ülke', 'Country');
  String regionLabel(bool turkey) =>
      turkey ? _('İl', 'Province') : _('İl / bölge', 'Region');
  String get pickCountry => _('Ülkeni seç', 'Choose your country');
  String pickRegion(String countryCode, String countryName) =>
      countryCode == 'TR'
          ? _('İlini seç', 'Choose your province')
          : _('$countryName: bölgeni seç', '$countryName: choose your region');
  String get locationPrivacy => _(
      'Tam konumun alınmaz; seçtiğin ilde rastgele bir noktaya yerleşirsin.',
      "We never take your exact location; you're placed at a random spot in the region you choose.");
  String get whereDoYouLive => _('Nerede yaşıyorsun?', 'Where do you live?');
  String currentlyIn(String loc) => _('Şu an: $loc', 'Currently: $loc');
  String newPlace(String loc) =>
      _('Yeni yerin: $loc ✈', 'Your new spot: $loc ✈');

  // ---------- ana ekran ----------
  String get randomName => _('Rastgele', 'Random');
  String get somewhere => _("Türkiye'den biri", 'someone in Türkiye');
  String get writeSomethingFirst =>
      _('önce kağıda bir şeyler yaz ✎', 'write something on the paper first ✎');
  String get pushHarder => _('biraz daha güçlü it! ↑', 'push a bit harder! ↑');
  String get hintFold => _('bitince kağıdı aşağı kaydır, uçak olsun ↓',
      'when done, swipe the paper down to fold it ↓');
  String get hintPush => _('uçağı parmağınla yukarı doğru it ↑',
      'push the plane up with your finger ↑');
  String replyTo(String n) => _('${dative(n)} cevap', 'reply to $n');
  String writeReply(String n) =>
      _('${dative(n)} cevabını yaz...', 'write your reply to $n...');
  String get writeRandom => _("Türkiye'de rastgele birine yaz...",
      'write to someone random in Türkiye...');
  String writeTo(String n) =>
      _('${dative(n)} bir şeyler yaz...', 'write something to $n...');
  String get tapToWrite => _('✎ dokun ve yaz', '✎ tap to write');
  String arrived(String n) => _('${dative(n)} ulaştı', 'landed with $n');
  String get flyingRandom =>
      _('rastgele birine uçuyor…', 'flying to someone random…');
  String flyingTo(String n) => _('${dative(n)} uçuyor…', 'flying to $n…');
  String flew(String km) => _('$km uçtu', 'flew $km');
  String get somewhereOnEarth =>
      _("Türkiye'nin bir yerine", 'somewhere in Türkiye');
  String left(String km) => _('$km kaldı', '$km to go');
  String get randomMatch => _('🌍 rastgele eşleşme', '🌍 random match');
  String get newLetter => _('✎  yeni mektup yaz', '✎  write a new letter');
  String acceptedYourRequest(String names) => _(
      '$names arkadaşlık isteğini kabul etti 🎉',
      '$names accepted your friend request 🎉');
  String get sentYouRequest =>
      _('sana arkadaşlık isteği gönderdi', 'sent you a friend request');
  String get see => _('gör', 'view');
  String get sentYouPlane => _('sana bir uçak gönderdi', 'sent you a plane');
  String get open => _('aç', 'open');
  String get newSealedLetter => _('yeni mektup · açılmadı', 'new letter · unopened');
  String get openedLetter => _('okudun', 'opened');

  // ---------- arkadaşlar ----------
  String get friends => _('Arkadaşlar', 'Friends');
  String friendsCount(int n) => _('Arkadaşlar ($n)', 'Friends ($n)');
  String get requests => _('İstekler', 'Requests');
  String get add => _('Ekle', 'Add');
  String nowFriends(String n) =>
      _('$n ile artık arkadaşsınız ✈', 'You and $n are now friends ✈');
  String requestSent(String n) => _(
      '${dative(n)} istek gönderildi, onay bekleniyor',
      'Request sent to $n, waiting for approval');
  String get noRequests => _(
      'Bekleyen istek yok.\n"Ekle" sekmesinden arkadaşlarını bul.',
      'No pending requests.\nFind your friends in the "Add" tab.');
  String get incomingSection => _('SANA GELENLER', 'RECEIVED');
  String get outgoingSection => _('GÖNDERDİKLERİN', 'SENT');
  String get accept => _('Kabul et', 'Accept');
  String get decline => _('Reddet', 'Decline');
  String get waitingApproval => _('onay bekleniyor', 'waiting for approval');
  String get undo => _('Geri al', 'Undo');
  String get noFriends => _(
      'Henüz arkadaşın yok.\n"Ekle" sekmesinden istek gönder.',
      'No friends yet.\nSend a request from the "Add" tab.');
  String get tapPersonHint => _(
      'Mektup yazmak, arkadaşlıktan çıkarmak ya da engellemek için kişiye dokun.',
      'Tap a person to write to them, unfriend or block.');
  String get searchHint =>
      _('kullanıcı adı ya da isim ara', 'search by username or name');
  String get searchEmpty => _(
      'Arkadaşının kullanıcı adını ya da ismini yaz.\nO onaylayınca arkadaş olursunuz.',
      "Type your friend's username or name.\nYou'll be friends once they accept.");
  String get nobodyFound => _('Kimse bulunamadı.', 'Nobody found.');
  String get searchFriends => _('arkadaşlarında ara', 'search your friends');
  String showMore(int n) => _('Daha fazla göster ($n)', 'Show more ($n)');
  String get yourFriend => _('arkadaşın ✓', 'friend ✓');
  String get requestSentShort => _('İstek gönderildi', 'Request sent');
  String get requestCancelled => _('İstek geri alındı', 'Request cancelled');
  String get sendRequest => _('İstek gönder', 'Add friend');

  // ---------- kişi kartı ----------
  String get areYouSure => _('Emin misin? Tekrar dokun', 'Sure? Tap again');
  String get unblock => _('Engeli kaldır', 'Unblock');
  String unblocked(String n) => _('$n artık engelli değil', '$n is unblocked');
  String writeLetterTo(String n) =>
      _('✎  ${dative(n)} mektup yaz', '✎  Write to $n');
  String get acceptRequest => _('İsteği kabul et', 'Accept request');
  String get requestSentUndo =>
      _('İstek gönderildi · geri al', 'Request sent · undo');
  String get sendFriendRequest =>
      _('Arkadaşlık isteği gönder', 'Send friend request');
  String away(String km) => _('$km uzakta', '$km away');
  String youSent(int n) => _('$n gönderdin', '$n sent');
  String theySent(int n) => _('$n geldi', '$n received');
  String friendsSince(DateTime d) =>
      _('${date(d)} beri arkadaş', 'friends since ${date(d)}');
  String get unfriend => _('Arkadaşlıktan çıkar', 'Unfriend');
  String unfriended(String n) =>
      _('$n arkadaşlarından çıkarıldı', '$n was removed from your friends');
  String get block => _('Engelle', 'Block');
  String blockedToast(String n) => _(
      '$n engellendi. Sana uçak ya da istek gönderemez.',
      "$n is blocked. They can't send you planes or requests.");

  // ---------- mektuplar ----------
  String get letters => _('Mektuplar', 'Letters');
  String unreadCount(int n) => _('$n okunmamış', '$n unread');
  String inboxTab(int n) => _('Gelen ($n)', 'Inbox ($n)');
  String sentTab(int? n) =>
      n == null ? _('Gönderilen', 'Sent') : _('Gönderilen ($n)', 'Sent ($n)');
  String get noLetters => _(
      'Henüz uçak gelmedi.\nBir arkadaşına uçak at, cevabı buraya düşsün ✈',
      'No planes yet.\nThrow one to a friend and the reply will land here ✈');
  String get noSent =>
      _('Henüz uçak göndermedin.', "You haven't sent a plane yet.");
  String get notOpened => _('açılmadı', 'not opened');
  String get notOpenedYet => _('henüz açılmadı', 'not opened yet');
  String get readMark => _('okundu ✓', 'read ✓');
  String get inbox => _('Gelen kutusu', 'Inbox');
  String planeComing(String n) =>
      _('${ablative(n)} bir uçak geliyor…', 'a plane is coming from $n…');
  String replyToName(String n) => _('${dative(n)} cevap yaz', 'Reply to $n');

  // ---------- profil ----------
  String get profilePhoto => _('Profil fotoğrafı', 'Profile photo');
  String get fromGallery => _('Galeriden seç', 'Choose from gallery');
  String get takePhoto => _('Fotoğraf çek', 'Take a photo');
  String get removePhoto => _('Fotoğrafı kaldır', 'Remove photo');
  String get photoFailed =>
      _('Fotoğraf seçilemedi.', "Couldn't pick the photo.");
  String get photoTooBig => _('Fotoğraf çok büyük, daha küçük bir tane seç.',
      'That photo is too large, pick a smaller one.');
  String get photoRemoved => _('Fotoğraf kaldırıldı', 'Photo removed');
  String get photoUpdated =>
      _('Profil fotoğrafın güncellendi 📸', 'Profile photo updated 📸');
  String get yourNameHint => _('ismin', 'your name');
  String get changeRegion => _('İlimi değiştir', 'Change my region');
  String get changePassword => _('Şifremi değiştir', 'Change password');
  String get blockedUsers => _('Engellediklerim', 'Blocked users');
  String get languageLabel => _('Dil / Language', 'Language / Dil');
  String get legal => _('KVKK ve yasal metinler', 'Privacy & legal');
  String get logout => _('Çıkış yap', 'Log out');
  String get deleteAccount => _('Hesabımı sil', 'Delete my account');
  String get newPasswordShort => _('Yeni şifre en az 6 karakter olmalı.',
      'New password must be at least 6 characters.');
  String get passwordChanged => _('Şifren değişti 🔒', 'Password changed 🔒');
  String get currentPassword => _('mevcut şifre', 'current password');
  String get newPassword =>
      _('yeni şifre (en az 6 karakter)', 'new password (min. 6 characters)');
  String get blockedInfo => _(
      'Engellediğin kişiler sana uçak ya da istek gönderemez.',
      "People you block can't send you planes or requests.");
  String get noBlocked =>
      _('Kimseyi engellemedin.', "You haven't blocked anyone.");
  String get accountDeleted =>
      _('Hesabın silindi. Görüşmek üzere ✈', 'Your account was deleted. Bye ✈');
  String get deleteTitle => _('Hesabını sil', 'Delete your account');
  String get deleteWarning => _(
      'Tüm mektupların, arkadaşlıkların ve fotoğrafın kalıcı olarak silinir. Bu işlem geri alınamaz.',
      'All your letters, friendships and photo will be permanently deleted. This cannot be undone.');
  String get confirmPassword =>
      _('onaylamak için şifren', 'your password to confirm');
  String get deleteForever =>
      _('Hesabımı kalıcı olarak sil', 'Delete my account permanently');

  // ---------- haklar / mağaza ----------
  String get creditsTitle => _('Mektup hakların', 'Your letters');
  String get dailyFreeLeft =>
      _('Bugün 1 ücretsiz mektup hakkın var', 'You have 1 free letter today');
  String dailyUsed(String left) => _(
      'Bugünkü ücretsiz hakkını kullandın · $left sonra yenilenir',
      "You've used today's free letter · renews in $left");
  String bonusCount(int n) =>
      _('Satın aldığın haklar: $n', 'Purchased letters: $n');
  String get replyFreeInfo => _('Sana gelen her mektuba 1 cevap ücretsiz.',
      'Replying once to each letter you receive is free.');
  String packLabel(int n) => _('$n mektup hakkı', '$n letters');
  String get buyMore => _('EK HAK SATIN AL', 'BUY MORE LETTERS');
  String get purchaseNote => _(
      'Ödeme Google Play hesabın üzerinden alınır. Haklar hesabına anında tanımlanır; dijital içerik anında teslim edildiği için cayma hakkı bulunmaz (Mesafeli Sözleşmeler Yönetmeliği md. 15/1-ğ).',
      'Payment is charged to your Google Play account. Letters are added immediately; as digital content delivered immediately, they are not subject to a right of withdrawal.');
  String get testFree => _('test · ücretsiz', 'test · free');
  String get storeUnavailable => _(
      'Satın alma Google Play üzerinden yapılır; uygulama mağazada yayınlanınca açılacak.',
      'Purchases are made via Google Play and will open once the app is published.');
  String creditsAdded(int n) =>
      _('$n mektup hakkı eklendi ✉', '$n letters added ✉');
  String get purchaseFailed =>
      _('Satın alma tamamlanamadı.', "The purchase couldn't be completed.");
  String get purchasePending => _(
      'Ödemen onay bekliyor; onaylanınca hakların eklenecek.',
      'Your payment is pending; letters will be added once it is approved.');
  String get noLettersLeft => _('Bugünkü ücretsiz mektubunu gönderdin ✉',
      "You've sent today's free letter ✉");

  // ---------- teslim ----------
  String get planeOnItsWay =>
      _('Uçağın yola çıktı ✈', 'Your plane is on its way ✈');
  String arrivesIn(String dur, String hm) =>
      _('yaklaşık $dur sonra varır ($hm)', 'arrives in about $dur ($hm)');
  String inFlight(String dur) => _('yolda · $dur', 'in flight · $dur');
  String get delivered => _('ulaştı', 'delivered');
}
