import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'api.dart';
import 'engine3d.dart';
import 'friends.dart';
import 'i18n.dart';
import 'inbox.dart';
import 'legal.dart';
import 'location_picker.dart';
import 'models.dart';
import 'person_sheet.dart';
import 'profile.dart';
import 'widgets.dart';

/// Uçuşun toplam süresi (sn): kalkış 1.4 + yolculuk 3.0 + iniş 2.4
const kFlight = 6.8;

class HomeScreen extends StatefulWidget {
  final Api api;
  final Person me;
  final VoidCallback onLogout;
  const HomeScreen(
      {super.key, required this.api, required this.me, required this.onLogout});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  final text = TextEditingController();
  final focus = FocusNode();
  final clouds = CloudField();
  final clock = ValueNotifier<double>(0);
  late final Ticker _ticker;
  double _last = 0;
  PageController? pages;

  /// 0 = kağıt altta bekliyor, 1 = kağıt açık
  late final sheet = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 650));

  /// 0 = düz kağıt, 1 = kağıt uçak
  late final fold = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1300));
  late final flight = AnimationController(
      vsync: this, duration: Duration(milliseconds: (kFlight * 1000).round()));
  late final AnimationController spring = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 550))
    ..addListener(() => drag = Offset.lerp(
        _springFrom, Offset.zero, Curves.easeOutBack.transform(spring.value))!);

  Api get api => widget.api;
  late Person me = widget.me;
  Stats stats = const Stats();
  List<Person> friends = [];
  List<Letter> inbox = [];
  final _seen = <String>{};
  bool loaded = false;

  MapLibreMapController? map;
  int selected = 0;
  Person? dest;
  Letter? replyTo;
  _BannerInfo? bannerInfo;
  List<FriendRequest> incomingReqs = [];
  final _seenReqs = <String>{};
  bool friendsOpen = false;
  bool flying = false, landed = false;
  bool banner = false, inboxOpen = false;
  Offset drag = Offset.zero,
      launchDrag = Offset.zero,
      _springFrom = Offset.zero;
  double drift = 0;
  String hint = '';
  Timer? _hintTimer, _poll;
  final _timers = <Timer>[];

  List<Person> get targets => [Person.randomPick, ...friends];
  Person get target => replyTo?.from ?? targets[selected % targets.length];
  int get unread => inbox.where((l) => l.unread).length;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((e) {
      final t = e.inMicroseconds / 1e6;
      clouds.step((t - _last).clamp(0.0, .05), _cloudSpeed());
      _last = t;
      clock.value = t;
    })
      ..start();
    _refresh(first: true);
    _poll = Timer.periodic(const Duration(seconds: 6), (_) => _pollAll());
  }

  @override
  void dispose() {
    _ticker.dispose();
    _hintTimer?.cancel();
    _poll?.cancel();
    for (final t in _timers) {
      t.cancel();
    }
    for (final c in [sheet, fold, flight, spring]) {
      c.dispose();
    }
    clock.dispose();
    pages?.dispose();
    focus.dispose();
    text.dispose();
    super.dispose();
  }

  // ---------- veri ----------

  Future<void> _refresh({bool first = false}) async {
    try {
      final (m, st) = await api.me();
      final fr = await api.friends();
      final ib = await api.inbox();
      final rq = await api.requests();
      if (!mounted) return;
      setState(() {
        me = m;
        stats = st;
        _setFriends(fr);
        _applyInbox(ib);
        _applyRequests(rq.incoming);
        loaded = true;
        if (first) {
          selected = fr.isEmpty ? 0 : 1;
          pages = PageController(viewportFraction: .28, initialPage: selected);
        }
      });
      if (first) {
        // Uygulamadaki dil seçimi sunucuya (bot cevapları) yansısın
        if (api.settings.lang != language.value.name) {
          api.updateMe(lang: language.value.name).catchError((_) => me);
        }
        // Yasal metinler güncellendiyse ya da hiç onaylanmadıysa sor
        if (api.settings.needsLegal) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              askLegalConsent(context, api, onLogout: widget.onLogout);
            }
          });
        }
        _cam(_homeCam(), 800);
        _timers.add(Timer(const Duration(milliseconds: 500), () {
          if (mounted) sheet.forward();
        }));
      }
    } on ApiException catch (e) {
      if (e.status == 401) return widget.onLogout();
      _hint(e.message);
      if (first) {
        _timers.add(Timer(const Duration(seconds: 4), () {
          if (mounted && !loaded) _refresh(first: true);
        }));
      }
    }
  }

  /// Gelen mektupları, arkadaşlık isteklerini ve arkadaş listesini yokla
  Future<void> _pollAll() async {
    if (!loaded) return;
    try {
      final ib = await api.inbox();
      final rq = await api.requests();
      final fr = await api.friends();
      if (!mounted) return;
      final before = inbox.length;
      final known = friends.map((f) => f.id).toSet();
      final accepted = fr.where((f) => !known.contains(f.id)).toList();
      setState(() {
        _applyInbox(ib);
        _applyRequests(rq.incoming);
        // Uçuş/yazma sırasında kişi seçici kaymasın diye liste o an değişmez
        if (!flying && fold.value == 0 && !friendsOpen) _setFriends(fr);
      });
      if (accepted.isNotEmpty && !friendsOpen && identical(friends, fr)) {
        showToast(context,
            txt.acceptedYourRequest(accepted.map((p) => p.name).join(', ')));
      }
      if (ib.length != before || accepted.isNotEmpty) {
        final (_, st) = await api.me();
        if (mounted) setState(() => stats = st);
      }
    } on ApiException catch (e) {
      if (e.status == 401) widget.onLogout();
    }
  }

  /// Arkadaş listesini değiştir; seçici aynı kişide kalır, kişi gittiyse
  /// (arkadaşlıktan çıkarıldı / engellendi) "Rastgele"ye döner
  void _setFriends(List<Person> fr) {
    final cur = targets[selected % targets.length];
    friends = fr;
    final i = targets.indexOf(cur);
    final next = i < 0 ? 0 : i;
    if (next == selected) return;
    selected = next;
    if (replyTo == null && pages != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && (pages?.hasClients ?? false)) pages!.jumpToPage(next);
      });
    }
  }

  /// Yeni arkadaşlık isteği gelince (mektup bildirimi yoksa) üstten haber ver
  void _applyRequests(List<FriendRequest> incoming) {
    incomingReqs = incoming;
    final fresh = incoming.where((r) => !_seenReqs.contains(r.id)).toList();
    _seenReqs.addAll(incoming.map((r) => r.id));
    if (fresh.isEmpty || flying || inboxOpen || friendsOpen) return;
    if (banner && bannerInfo?.letter != null) return;
    final r = fresh.first;
    _showBanner(_BannerInfo(
      person: r.user,
      title: txt.sentYouRequest(r.user.name),
      sub: '@${r.user.username} · ${r.user.location}',
      action: txt.see,
      onTap: _openFriends,
    ));
  }

  void _showBanner(_BannerInfo info) {
    bannerInfo = info;
    banner = true;
    _timers.add(Timer(const Duration(seconds: 15), () {
      if (mounted && bannerInfo == info) setState(() => banner = false);
    }));
  }

  /// Yeni gelen okunmamış mektup varsa üstten bildirim göster.
  /// Uçuş sürerken bildirim bekler, iniş sonrası düşer.
  void _applyInbox(List<Letter> ib) {
    inbox = ib;
    if (flying || inboxOpen) return;
    final fresh = ib.where((l) => l.unread && !_seen.contains(l.id)).toList();
    _seen.addAll(ib.map((l) => l.id));
    if (fresh.isNotEmpty) {
      final l = fresh.first;
      _showBanner(_BannerInfo(
        person: l.from!,
        title: txt.sentYouPlane(l.from!.name),
        sub: '${l.from!.location} · ${txt.km(l.distanceKm)}',
        action: txt.open,
        letter: l,
        onTap: () => _openLetter(l),
      ));
    }
  }

  double get _ts => flight.value * kFlight;

  double _cloudSpeed() {
    if (!flying) return .6;
    final t = _ts;
    if (t < 1.4) return lerp(.6, 16, t / 1.4);
    if (t < 4.4) return 16;
    return lerp(16, 1.2, clamp01((t - 4.4) / 2.4));
  }

  double _cloudDensity() {
    if (landed) return .25;
    if (!flying) return .45;
    final t = _ts;
    if (t < 1.4) return lerp(.45, 1, t / 1.4);
    if (t < 4.4) return 1;
    return lerp(1, .15, clamp01((t - 4.4) / 1.8));
  }

  void _hint(String s) {
    _hintTimer?.cancel();
    setState(() => hint = s);
    _hintTimer = Timer(const Duration(milliseconds: 2600),
        () => mounted ? setState(() => hint = '') : null);
  }

  // ---------- kamera ----------

  double _bearingFor(Person p) => p.random ? 20 : bearingDeg(me.at, p.at);

  CameraPosition _homeCam([Person? p]) => CameraPosition(
      target: me.at, zoom: 16.2, tilt: 60, bearing: _bearingFor(p ?? target));

  void _cam(CameraPosition p, int ms) =>
      map?.animateCamera(CameraUpdate.newCameraPosition(p),
          duration: Duration(milliseconds: ms));

  void _select(int i) {
    setState(() => selected = i);
    // Harita seçilen kişinin yönüne döner: uçak o tarafa uçacak
    if (replyTo == null) _cam(_homeCam(targets[i]), 1100);
  }

  // ---------- kağıt ----------

  Future<void> _openSheet() async {
    if (flying || landed) return;
    await sheet.forward();
    if (mounted && fold.value == 0) focus.requestFocus();
  }

  void _closeSheet() {
    focus.unfocus();
    sheet.reverse();
  }

  bool get _empty => text.text.trim().isEmpty;

  // Katlama hareketi ham dokunuşlardan okunur: yazı alanının seçim/kaydırma
  // jestleri aşağı çekişi yutmasın.
  Offset? _pStart;
  bool _folding = false, _warned = false;
  double _foldBase = 0, _lastDy = 0;
  DateTime _lastMove = DateTime.now();
  double _foldVelocity = 0;

  void _paperDown(PointerDownEvent e) {
    _pStart = e.position;
    _folding = _warned = false;
    _foldBase = fold.value;
    _lastDy = 0;
  }

  void _paperMove(PointerMoveEvent e, double h) {
    final st = _pStart;
    if (st == null || sheet.value < .98) return;
    final d = e.position - st;
    if (!_folding) {
      if (d.dy < 14 || d.dy.abs() < d.dx.abs() * 1.4) return;
      if (_empty) {
        if (!_warned) _hint(txt.writeSomethingFirst);
        _warned = true;
        return;
      }
      _folding = true;
      focus.unfocus();
      text.selection = TextSelection.collapsed(offset: text.text.length);
    }
    final now = DateTime.now();
    final dt = now.difference(_lastMove).inMicroseconds / 1e6;
    if (dt > 0) _foldVelocity = (d.dy - _lastDy) / dt;
    _lastMove = now;
    _lastDy = d.dy;
    fold.value = clamp01(_foldBase + (d.dy - 14) / (h * .9));
  }

  void _paperUp(PointerEvent e) {
    _pStart = null;
    if (!_folding) return;
    _folding = false;
    if (fold.value > .3 || _foldVelocity > 600) {
      fold.animateTo(1, curve: Curves.easeOut);
    } else {
      fold.animateTo(0, curve: Curves.easeOut);
    }
  }

  void _foldButton() {
    if (_empty) return _hint(txt.writeSomethingFirst);
    focus.unfocus();
    fold.animateTo(1, curve: Curves.easeInOut);
  }

  Future<void> _unfold() async {
    await fold.animateTo(0, curve: Curves.easeInOut);
    if (mounted) focus.requestFocus();
  }

  // ---------- fırlatma ----------

  void _planeDragEnd(DragEndDetails d) {
    final v = d.velocity.pixelsPerSecond;
    if (v.dy < -450 || drag.dy < -160) {
      _launch(v);
    } else {
      if (drag.dy < -20 || v.dy < -80) _hint(txt.pushHarder);
      _springFrom = drag;
      spring.forward(from: 0);
    }
  }

  Future<void> _launch(Offset v) async {
    final t = target;
    setState(() {
      flying = true;
      banner = false;
      dest = t.random ? null : t;
      launchDrag = drag;
      drag = Offset.zero;
      drift = (v.dx / 1500 + launchDrag.dx / 300).clamp(-1.0, 1.0);
      hint = '';
    });
    _cam(
        CameraPosition(
            target: me.at, zoom: 12, tilt: 50, bearing: _bearingFor(t)),
        1400);
    final anim = flight.forward(from: 0);
    final started = DateTime.now();
    try {
      final letter = await api.send(
          to: t.random ? 'random' : t.id,
          body: text.text.trim(),
          replyTo: replyTo?.id);
      if (!mounted) return;
      setState(() => dest = letter.to);
      _flyCamera(letter.to!, DateTime.now().difference(started));
    } on ApiException catch (e) {
      // Gönderilemedi: uçak geri gelir, mektup kaybolmaz
      flight.stop();
      flight.value = 0;
      setState(() => flying = false);
      _cam(_homeCam(), 900);
      _hint(e.message);
      return;
    }
    await anim;
    if (!mounted) return;
    setState(() {
      flying = false;
      landed = true;
    });
    _refresh();
  }

  void _flyCamera(Person d, Duration elapsed) {
    final brg = bearingDeg(me.at, d.at);
    final dist = distanceKm(me.at, d.at);
    final cz = dist > 3000
        ? 2.8
        : dist > 600
            ? 4.4
            : dist > 150
                ? 6.0
                : 8.0;
    final e = elapsed.inMilliseconds;
    // Kalkışta yüksel, hedefe doğru yol al, hedefe alçal
    _cam(CameraPosition(target: me.at, zoom: cz + 1, tilt: 45, bearing: brg),
        math.max(300, 1400 - e));
    _timers
      ..add(Timer(
          Duration(milliseconds: math.max(0, 1400 - e)),
          () => _cam(
              CameraPosition(target: d.at, zoom: cz, tilt: 45, bearing: brg),
              3000)))
      ..add(Timer(
          Duration(milliseconds: math.max(0, 4400 - e)),
          () => _cam(
              CameraPosition(
                  target: d.at, zoom: 16.3, tilt: 62, bearing: brg + 25),
              2400)));
  }

  void _reset({bool open = true}) {
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
    text.clear();
    flight.value = 0;
    fold.value = 0;
    sheet.value = 0;
    setState(() {
      flying = landed = false;
      dest = null;
      replyTo = null;
      drag = Offset.zero;
    });
    _cam(_homeCam(), 1600);
    if (open) _openSheet();
  }

  // ---------- gelen kutusu ----------

  Future<void> _openInboxList() async {
    focus.unfocus();
    final l = await showInboxSheet(context, inbox, api);
    if (l != null && mounted) _openLetter(l);
  }

  Future<void> _openLetter(Letter l) async {
    focus.unfocus();
    setState(() {
      banner = false;
      inboxOpen = true;
      _seen.add(l.id);
    });
    // Gelen kutusu aynı haritayı kullanır: kamera senin şehrine geçer
    map?.moveCamera(CameraUpdate.newCameraPosition(
        CameraPosition(target: me.at, zoom: 15.2, tilt: 58, bearing: 195)));
    final r = await Navigator.of(context).push<String>(PageRouteBuilder(
      opaque: false,
      transitionDuration: const Duration(milliseconds: 450),
      pageBuilder: (_, __, ___) =>
          InboxScreen(letter: l, home: me.at, api: api, camera: _cam),
      transitionsBuilder: (_, a, __, child) =>
          FadeTransition(opacity: a, child: child),
    ));
    if (!mounted) return;
    setState(() => inboxOpen = false);
    _refresh();
    if (r == 'reply') {
      _reset(open: false);
      final i = friends.indexOf(l.from!);
      if (i >= 0) pages?.jumpToPage(i + 1);
      setState(() => replyTo = l);
      _cam(_homeCam(l.from), 1200);
      _openSheet();
    } else if (landed) {
      _reset(open: false);
    } else {
      _cam(_homeCam(), 1200);
    }
  }

  // ---------- arkadaş ekle / profil ----------

  Future<void> _openFriends() async {
    focus.unfocus();
    setState(() {
      banner = false;
      friendsOpen = true;
    });
    final write = await showFriendsSheet(context,
        api: api, friends: friends, home: me.at);
    if (!mounted) return;
    friendsOpen = false;
    await _reloadFriends();
    if (write != null && mounted) _writeTo(write);
  }

  Future<void> _reloadFriends() async {
    try {
      final fr = await api.friends();
      final rq = await api.requests();
      final ib = await api.inbox();
      final (_, st) = await api.me();
      if (!mounted) return;
      setState(() {
        _setFriends(fr);
        incomingReqs = rq.incoming;
        _seenReqs.addAll(rq.incoming.map((r) => r.id));
        inbox = ib;
        stats = st;
      });
    } on ApiException catch (e) {
      _hint(e.message);
    }
  }

  /// Bir arkadaşı seçip kağıdı aç: "mektup yaz" kısayolu
  void _writeTo(Person p) {
    if (flying) return;
    if (landed) _reset(open: false);
    final i = friends.indexOf(p);
    if (i < 0) return;
    setState(() {
      replyTo = null;
      selected = i + 1;
    });
    pages?.jumpToPage(i + 1);
    _cam(_homeCam(p), 1100);
    _openSheet();
  }

  /// Seçicideki bir arkadaşın kartı (uzun bas)
  Future<void> _openPerson(Person p) async {
    if (p.random || flying) return;
    focus.unfocus();
    final r = await showPersonSheet(context, api: api, person: p, home: me.at);
    if (!mounted || r == null) return;
    if (r == PersonAction.write) return _writeTo(p);
    await _reloadFriends();
  }

  void _profile() {
    focus.unfocus();
    showProfileSheet(
      context,
      api: api,
      me: me,
      stats: stats,
      onChanged: (p) => setState(() => me = p),
      onChangeLocation: _changeLocation,
      onLogout: widget.onLogout,
    );
  }

  Future<void> _changeLocation() async {
    final moved = await showModalBottomSheet<Person>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      builder: (_) => _LocationSheet(api: api, me: me),
    );
    if (moved == null || !mounted) return;
    setState(() => me = moved);
    _cam(_homeCam(), 2500);
    showToast(context, txt.newPlace(moved.location));
  }

  // ---------- çizim ----------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kGround,
      resizeToAvoidBottomInset: false,
      body: LayoutBuilder(
        builder: (context, c) => AnimatedBuilder(
          animation: Listenable.merge([clock, sheet, fold, flight, spring]),
          child: Map3D(
            camera: CameraPosition(target: me.at, zoom: 16.2, tilt: 60),
            onCreated: (m) => map = m,
          ),
          builder: (context, mapWidget) => _scene(c.biggest, mapWidget!),
        ),
      ),
    );
  }

  Pose _ready(Size s, double f, Offset d, double t) {
    const z = 6.2;
    return Pose(
      V3(
          d.dx * z / f - .3,
          (s.height / 2 - s.height * .74) * z / f -
              d.dy * z / f +
              .03 * math.sin(t * 2),
          z),
      // Arkadan ¾ bakış: iki kanat ve gövde birlikte görünür
      pitch: -.42 + .02 * math.sin(t * 2) + (d.dy * .0015).clamp(-.45, .2),
      yaw: .22 + (d.dx * .002).clamp(-.4, .4),
      roll: -.15 + .04 * math.sin(t * 1.3) + (-d.dx * .003).clamp(-.6, .6),
    );
  }

  /// Fırlatılan uçağın yolu: kalkış → bulutlar arasında yolculuk → iniş
  (Pose, double) _flightPose(double ts, Pose l, Size s, double f) {
    double yAt(double screenY, double z) => (s.height / 2 - screenY) * z / f;
    double sm(double v) => Curves.easeInOut.transform(clamp01(v));
    const zc = 9.0;
    final yc = yAt(s.height * .4, zc);
    Pose cruise(double tb) => Pose(
          V3(drift * .8 * (1 - sm(tb)) + .35 * math.sin(tb * 1.4),
              yc + .08 * math.sin(tb * 2.2), zc),
          pitch: -.3 + .1 * sm(tb),
          roll: -.3 * math.sin(tb * 1.4),
          yaw: .32 + .12 * math.sin(tb * 1.4),
        );
    if (ts < 1.4) {
      final u = ts / 1.4;
      final e = Curves.easeOutCubic.transform(u);
      final m = Curves.easeInOut.transform(u);
      final arc = math.sin(u * math.pi);
      return (
        Pose(
          V3(lerp(l.pos.x, drift * .8, e) + drift * .6 * arc,
              lerp(l.pos.y, yc, m), lerp(l.pos.z, zc, e)),
          pitch: lerp(l.pitch, -.3, u),
          roll: lerp(l.roll, 0, u) + drift * .5 * arc,
          yaw: lerp(l.yaw, .32, u) + drift * .15 * arc,
        ),
        lerp(.35, 3, u)
      );
    }
    if (ts < 4.4) return (cruise(ts - 1.4), 3);
    final u = clamp01((ts - 4.4) / 2.4);
    const zl = 10.0;
    final land =
        Pose(V3(0, yAt(s.height * .58, zl), zl), pitch: -.25, yaw: .35);
    final p = Pose.lerp(cruise(3), land, Curves.easeInOutCubic.transform(u));
    return (
      p.copyWith(roll: p.roll + .2 * math.sin(u * math.pi * 2) * (1 - u)),
      lerp(3, .02, Curves.easeIn.transform(u))
    );
  }

  Widget _scene(Size s, Widget mapWidget) {
    // Android'de ilk kare 0x0 boyutla gelir; geometri NaN üretmesin
    if (s.width < 10 || s.height < 10 || inboxOpen) {
      return Stack(children: [
        Positioned.fill(child: mapWidget),
        const Positioned.fill(child: Atmosphere()),
      ]);
    }
    final pad = MediaQuery.paddingOf(context);
    final kb = MediaQuery.viewInsetsOf(context).bottom;
    final w = s.width, h = s.height;
    final f = w * 2.2;
    final cen = Offset(w / 2, h / 2);
    final t = clock.value;
    final ts = _ts;

    // Kağıdın ekrandaki yeri: altta bekleme / ortada yazma (klavyeye göre)
    final hn = math.min(w * .86 * kSheetAspect, h * .5);
    Pose compose;
    if (kb > 0) {
      final top = pad.top + 150, bot = h - kb - 84;
      compose = paperPose((top + bot) / 2, math.min(hn, bot - top - 8), f, h);
    } else {
      compose = paperPose(h * .53, hn, f, h);
    }
    final peek = paperPose(h + hn / 2 - 130 - pad.bottom, hn, f, h);
    final paper =
        Pose.lerp(peek, compose, Curves.easeOutCubic.transform(sheet.value));

    Pose pose;
    double hover, foldV = fold.value;
    if (flying || landed) {
      final r =
          _flightPose(landed ? kFlight : ts, _ready(s, f, launchDrag, t), s, f);
      pose = r.$1;
      hover = r.$2;
      foldV = 1;
    } else {
      pose = Pose.lerp(
          paper, _ready(s, f, drag, t), Curves.easeInOut.transform(fold.value));
      hover = .35 * fold.value;
    }

    final rect = sheetRect(paper, f, cen);
    final writing = !flying && !landed && sheet.value > .98 && fold.value < .02;
    final ready = !flying && !landed && fold.value > .98;
    final chrome = flying ? 1 - clamp01(ts / .5) : (landed ? 0.0 : 1.0);
    final haze = flying
        ? (ts < 1.4
            ? ts / 1.4 * .7
            : ts < 4.4
                ? .7
                : lerp(.7, 0, clamp01((ts - 4.4) / 1.6)))
        : 0.0;
    final pinIn = landed ? 1.0 : (flying ? clamp01((ts - 5.4) / .6) : 0.0);

    var hintText = hint;
    if (hintText.isEmpty) {
      if (writing) hintText = txt.hintFold;
      if (ready) hintText = txt.hintPush;
    }

    return Stack(children: [
      Positioned.fill(child: mapWidget),
      Positioned.fill(child: Atmosphere(haze: haze)),
      Positioned.fill(
        child: IgnorePointer(
          child: CustomPaint(painter: CloudPainter(clouds, _cloudDensity(), f)),
        ),
      ),
      // Üst kısım: logo, arkadaş ekle, gelen kutusu, profil
      Positioned(
        key: const ValueKey('top'),
        top: pad.top + 6,
        left: 14,
        right: 14,
        child: IgnorePointer(
          ignoring: flying || landed,
          child: Opacity(
            opacity: chrome,
            child: Row(children: [
              const Logo(height: 42),
              const Spacer(),
              GlassButton(
                  size: 42,
                  onTap: _openFriends,
                  badge: incomingReqs.length,
                  child: const Icon(Icons.people_alt_outlined,
                      size: 20, color: kNavy)),
              const SizedBox(width: 8),
              GlassButton(
                  size: 42,
                  badge: unread,
                  onTap: _openInboxList,
                  child:
                      const Icon(Icons.inbox_outlined, size: 20, color: kNavy)),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _profile,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: const BoxDecoration(
                      color: Colors.white, shape: BoxShape.circle),
                  child: Avatar(person: me, size: 38),
                ),
              ),
            ]),
          ),
        ),
      ),
      Positioned(
        key: const ValueKey('carousel'),
        top: pad.top + 58,
        left: 0,
        right: 0,
        height: 128,
        child: IgnorePointer(
          ignoring: flying || landed || replyTo != null,
          child: Opacity(
              opacity: chrome * (replyTo != null ? .35 : 1),
              child: _carousel()),
        ),
      ),
      if (pinIn > 0 && dest != null)
        Positioned(
          key: const ValueKey('pin'),
          left: cen.dx - 100,
          width: 200,
          top: cen.dy - AvatarPin.tipOffset(58),
          child: Opacity(
            opacity: pinIn,
            child: AvatarPin(person: dest!, check: landed),
          ),
        ),
      // 3D kağıt / uçak: katlandıkça buruşur
      Positioned.fill(
        key: const ValueKey('mesh'),
        child: IgnorePointer(
          child: CustomPaint(
            painter: PaperPainter(
                pose: pose,
                fold: foldV,
                f: f,
                hover: hover,
                crumple: crumpleFor(foldV)),
          ),
        ),
      ),
      if (replyTo != null && !flying && !landed && fold.value < .5)
        Positioned(
          key: const ValueKey('reply'),
          left: 0,
          right: 0,
          top: rect.top - 40,
          child: Center(
            child: GestureDetector(
              onTap: () {
                setState(() => replyTo = null);
                _cam(_homeCam(), 900);
              },
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
                decoration: glass(16),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.reply, size: 16, color: kRed),
                  const SizedBox(width: 6),
                  Text(txt.replyTo(replyTo!.from!.name),
                      style: ui(13, weight: FontWeight.w700)),
                  const SizedBox(width: 6),
                  const Icon(Icons.close, size: 16, color: kMuted),
                ]),
              ),
            ),
          ),
        ),
      // Kağıdın üstündeki yazı alanı (kağıt düzken)
      if (!flying && !landed)
        Positioned.fromRect(
          key: const ValueKey('paper'),
          rect: rect,
          child: Opacity(
            opacity: clamp01(1 - fold.value * 6),
            child: IgnorePointer(
              ignoring: fold.value > .02,
              child: Listener(
                onPointerDown: _paperDown,
                onPointerMove: (e) => _paperMove(e, rect.height),
                onPointerUp: _paperUp,
                onPointerCancel: _paperUp,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: sheet.value < .5 ? _openSheet : null,
                  child: _paperFace(rect),
                ),
              ),
            ),
          ),
        ),
      // Uçağa dokun = aç, yukarı it = fırlat
      if (ready)
        Positioned.fromRect(
          key: const ValueKey('plane'),
          rect: meshBounds(pose, 1, f, cen).inflate(36),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _unfold,
            onPanStart: (_) => spring.stop(),
            onPanUpdate: (d) => drag += d.delta,
            onPanEnd: _planeDragEnd,
            child: const MouseRegion(cursor: SystemMouseCursors.grab),
          ),
        ),
      if (hintText.isNotEmpty)
        Positioned(
          key: const ValueKey('hint'),
          left: 24,
          right: 24,
          bottom:
              writing ? (kb > 0 ? kb + 76 : 92 + pad.bottom) : 22 + pad.bottom,
          child: IgnorePointer(
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: glass(18),
                child: Text(hintText,
                    textAlign: TextAlign.center,
                    style: ui(13, weight: FontWeight.w600)),
              ),
            ),
          ),
        ),
      if (!flying && !landed && sheet.value > .5 && fold.value < .5)
        Positioned(
          key: const ValueKey('bar'),
          left: 22,
          right: 22,
          bottom: kb > 0 ? kb + 14 : 22 + pad.bottom,
          child: Opacity(
              opacity:
                  clamp01(1 - fold.value * 2) * clamp01(sheet.value * 2 - 1),
              child: _composeBar()),
        ),
      if (flying || landed)
        Positioned(
          key: const ValueKey('status'),
          left: 0,
          right: 0,
          bottom: 0,
          child: Opacity(
              opacity: landed ? 1 : clamp01((ts - .3) / .4),
              child: _status(pad)),
        ),
      AnimatedPositioned(
        key: const ValueKey('banner'),
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutBack,
        top: banner ? pad.top + 6 : -140,
        left: 10,
        right: 10,
        child: _banner(),
      ),
    ]);
  }

  Widget _paperFace(Rect rect) {
    final fs = (rect.width * .078).clamp(18.0, 32.0);
    final open = sheet.value > .5;
    final to = target;
    return Stack(children: [
      Positioned.fill(
          child: CustomPaint(painter: RuledPainter(fs * 1.15, sheet.value))),
      Padding(
        padding: EdgeInsets.fromLTRB(rect.width * .14, rect.width * .1,
            rect.width * .07, rect.width * .06),
        child: open
            ? TextField(
                controller: text,
                focusNode: focus,
                maxLines: null,
                expands: true,
                maxLength: 2000,
                buildCounter: (_,
                        {required currentLength,
                        required isFocused,
                        maxLength}) =>
                    null,
                textAlign: TextAlign.center,
                scrollPhysics: const NeverScrollableScrollPhysics(),
                onChanged: (_) => setState(() {}),
                style: hand(fs),
                cursorColor: kInk,
                decoration: InputDecoration(
                  border: InputBorder.none,
                  hintText: replyTo != null
                      ? txt.writeReply(to.name)
                      : to.random
                          ? txt.writeRandom
                          : txt.writeTo(to.name),
                  hintStyle: hand(fs, .5),
                ),
              )
            : Align(
                alignment: Alignment.topCenter,
                child: Text(txt.tapToWrite, style: hand(fs * 1.1, .8)),
              ),
      ),
    ]);
  }

  Widget _carousel() {
    final pc = pages;
    if (pc == null) {
      return const Center(
          child: SizedBox(
              width: 22,
              height: 22,
              child:
                  CircularProgressIndicator(strokeWidth: 2.4, color: kNavy)));
    }
    return PageView.builder(
      controller: pc,
      itemCount: targets.length,
      onPageChanged: _select,
      itemBuilder: (_, i) => AnimatedBuilder(
        animation: pc,
        builder: (_, __) {
          var p = selected.toDouble();
          if (pc.positions.length == 1 && pc.position.haveDimensions) {
            p = pc.page ?? p;
          }
          final d = i - p;
          final a = d.abs().clamp(0.0, 1.5);
          return GestureDetector(
            onLongPress: () => _openPerson(targets[i]),
            onTap: () => pc.animateToPage(i,
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeOut),
            child: Transform.translate(
              offset: Offset(0, a * 24),
              child: Transform.rotate(
                angle: d * .28,
                child: Opacity(
                  opacity: (1 - a * .55).clamp(.25, 1.0),
                  child: Transform.scale(
                    scale: 1 - a * .3,
                    child: FriendBadge(person: targets[i], ring: a < .5),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _composeBar() => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          GlassButton(
              onTap: _closeSheet,
              child: const Icon(Icons.close, size: 22, color: kNavy)),
          // Yazılan karakter (mektup en fazla 2000 karakter)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: glass(20),
            child: Text('${text.text.characters.length} / 2000',
                style: ui(12.5, weight: FontWeight.w600, color: kMuted)),
          ),
          GlassButton(
            onTap: _foldButton,
            child: Transform.rotate(
                angle: -.5,
                child: const Icon(Icons.send_rounded, size: 21, color: kRed)),
          ),
        ],
      );

  Widget _status(EdgeInsets pad) {
    final d = dest;
    final total = d == null ? 0.0 : distanceKm(me.at, d.at);
    final progress = landed ? 1.0 : clamp01((_ts - .2) / (kFlight - .6));
    final random = target.random && replyTo == null;
    final title = landed && d != null
        ? txt.arrived(d.name)
        : random
            ? txt.flyingRandom
            : txt.flyingTo(d?.name ?? target.name);
    final sub = landed && d != null
        ? '${d.location} · ${txt.flew(txt.km(total))}'
        : random || d == null
            ? txt.somewhereOnEarth
            : '${d.location} · ${txt.left(txt.km(total * (1 - progress)))}';
    return Container(
      padding: EdgeInsets.fromLTRB(18, 34, 18, 18 + pad.bottom),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: .9),
            Colors.white,
          ],
        ),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (landed && random)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(txt.randomMatch,
                style: ui(11, weight: FontWeight.w700, color: kRed)),
          ),
        Text(title, style: ui(17, weight: FontWeight.w800)),
        const SizedBox(height: 3),
        Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.place_outlined, size: 13, color: kRed),
          const SizedBox(width: 3),
          Text(sub, style: ui(12, color: kMuted)),
        ]),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Stat(icon: '✈️', count: stats.sent, label: txt.sent),
            Stat(icon: '📬', count: stats.received, label: txt.received),
            Stat(icon: '🌍', count: stats.cities, label: txt.cities),
          ],
        ),
        if (landed) ...[
          const SizedBox(height: 14),
          GestureDetector(
            onTap: _reset,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
              decoration: BoxDecoration(
                  color: kNavy, borderRadius: BorderRadius.circular(24)),
              child: Text(txt.newLetter,
                  style: ui(14, weight: FontWeight.w700, color: Colors.white)),
            ),
          ),
        ],
      ]),
    );
  }

  Widget _banner() {
    final b = bannerInfo;
    if (b == null) return const SizedBox();
    return GestureDetector(
      onTap: b.onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
        decoration: BoxDecoration(
          color: kNavy.withValues(alpha: .95),
          borderRadius: BorderRadius.circular(22),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 20)],
        ),
        child: Row(children: [
          Avatar(person: b.person, size: 38),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(b.title,
                      style:
                          ui(14, weight: FontWeight.w700, color: Colors.white)),
                  Text(b.sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ui(12, color: Colors.white70)),
                ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
                color: kRed, borderRadius: BorderRadius.circular(16)),
            child: Text(b.action,
                style: ui(13, weight: FontWeight.w700, color: Colors.white)),
          ),
        ]),
      ),
    );
  }
}

class _LocationSheet extends StatefulWidget {
  final Api api;
  final Person me;
  const _LocationSheet({required this.api, required this.me});
  @override
  State<_LocationSheet> createState() => _LocationSheetState();
}

class _LocationSheetState extends State<_LocationSheet> {
  GeoOption? country = kServiceCountry;
  GeoOption? region;
  bool busy = false;
  String? error;

  Future<void> _save() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final p = await widget.api.updateLocation(country!.code, region!.code);
      if (mounted) Navigator.pop(context, p);
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(txt.whereDoYouLive, style: ui(20, weight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(txt.currentlyIn(widget.me.location),
              style: ui(13, color: kMuted)),
          const SizedBox(height: 16),
          LocationFields(
            api: widget.api,
            country: country,
            region: region,
            onChanged: (c, r) => setState(() {
              country = c;
              region = r;
            }),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(error!, style: ui(13, color: kRed)),
            ),
          const SizedBox(height: 18),
          PrimaryButton(
            label: txt.save,
            busy: busy,
            onTap: country != null && region != null ? _save : null,
          ),
        ]),
      );
}

/// Üstten düşen bildirim: gelen mektup ya da arkadaşlık isteği
class _BannerInfo {
  final Person person;
  final String title, sub, action;
  final VoidCallback onTap;
  final Letter? letter;
  const _BannerInfo(
      {required this.person,
      required this.title,
      required this.sub,
      required this.action,
      required this.onTap,
      this.letter});
}
