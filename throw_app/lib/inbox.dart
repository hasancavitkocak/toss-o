import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:maplibre_gl/maplibre_gl.dart' show CameraPosition, LatLng;
import 'api.dart';
import 'engine3d.dart';
import 'i18n.dart';
import 'models.dart';
import 'person_sheet.dart';
import 'store.dart';
import 'widgets.dart';

/// Gelen / gönderilen mektuplar (alt sayfa). Açılacak gelen mektubu döndürür.
Future<Letter?> showInboxSheet(
        BuildContext context, List<Letter> letters, Api api) =>
    showModalBottomSheet<Letter>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      builder: (_) => _LettersSheet(letters: letters, api: api),
    );

class _LettersSheet extends StatefulWidget {
  final List<Letter> letters;
  final Api api;
  const _LettersSheet({required this.letters, required this.api});
  @override
  State<_LettersSheet> createState() => _LettersSheetState();
}

class _LettersSheetState extends State<_LettersSheet>
    with SingleTickerProviderStateMixin {
  late final tabs = TabController(length: 2, vsync: this);
  List<Letter>? sent;
  String? error;

  @override
  void initState() {
    super.initState();
    _loadSent();
  }

  @override
  void dispose() {
    tabs.dispose();
    super.dispose();
  }

  Future<void> _loadSent() async {
    try {
      final l = await widget.api.sent();
      if (mounted) setState(() => sent = l);
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    }
  }

  Widget _empty(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(32, 40, 32, 48),
        child: Text(text,
            textAlign: TextAlign.center, style: ui(14, color: kMuted)),
      );

  Widget _tile(Letter l, {required bool incoming}) {
    final p = incoming ? l.from! : l.to!;
    final bold = incoming && l.unread;
    return ListTile(
      onTap: () =>
          incoming ? Navigator.pop(context, l) : showSentLetter(context, l),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      tileColor: bold ? const Color(0xFFFFF4F4) : null,
      leading: Avatar(person: p, size: 46),
      title: Row(children: [
        if (!incoming) ...[
          const Icon(Icons.north_east, size: 14, color: kRed),
          const SizedBox(width: 4),
        ],
        Flexible(
          child: Text('${p.name} · ${p.city}',
              overflow: TextOverflow.ellipsis,
              style: ui(15, weight: bold ? FontWeight.w800 : FontWeight.w600)),
        ),
        if (l.isRandom) ...[
          const SizedBox(width: 6),
          const Icon(Icons.public, size: 14, color: kMuted),
        ],
      ]),
      subtitle: Text(l.body.split('\n').first,
          maxLines: 1, overflow: TextOverflow.ellipsis, style: hand(19, .8)),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(txt.ago(l.sentAt), style: ui(11, color: kMuted)),
          const SizedBox(height: 6),
          if (incoming && l.unread)
            Container(
                width: 10,
                height: 10,
                decoration:
                    const BoxDecoration(color: kRed, shape: BoxShape.circle)),
          if (!incoming)
            Text(sentStatus(l),
                style: ui(11,
                    weight: FontWeight.w700,
                    color: l.inFlight
                        ? kRed
                        : l.unread
                            ? kMuted
                            : const Color(0xFF22B45A))),
        ],
      ),
    );
  }

  Widget _list(List<Letter> items, {required bool incoming}) =>
      ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 4),
        itemBuilder: (_, i) => _tile(items[i], incoming: incoming),
      );

  @override
  Widget build(BuildContext context) {
    final letters = widget.letters;
    final unread = letters.where((l) => l.unread).length;
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .75,
      child: Column(children: [
        const SizedBox(height: 10),
        Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
                color: Colors.black12, borderRadius: BorderRadius.circular(2))),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 16, 22, 2),
          child: Row(children: [
            Text(txt.letters, style: ui(20, weight: FontWeight.w800)),
            const Spacer(),
            if (unread > 0)
              Text(txt.unreadCount(unread),
                  style: ui(13, weight: FontWeight.w700, color: kRed)),
          ]),
        ),
        TabBar(
          controller: tabs,
          labelColor: kNavy,
          unselectedLabelColor: kMuted,
          indicatorColor: kRed,
          labelStyle: ui(14, weight: FontWeight.w700),
          tabs: [
            Tab(text: txt.inboxTab(letters.length)),
            Tab(
                text: sent == null
                    ? txt.sentTab(null)
                    : txt.sentTab(sent!.length)),
          ],
        ),
        Expanded(
          child: TabBarView(controller: tabs, children: [
            letters.isEmpty
                ? _empty(txt.noLetters)
                : _list(letters, incoming: true),
            error != null
                ? _empty(error!)
                : sent == null
                    ? const Center(
                        child: CircularProgressIndicator(color: kNavy))
                    : sent!.isEmpty
                        ? _empty(txt.noSent)
                        : _list(sent!, incoming: false),
          ]),
        ),
      ]),
    );
  }
}

/// Gönderdiğin mektubu kağıt üstünde göster
Future<void> showSentLetter(BuildContext context, Letter l) => showDialog(
      context: context,
      barrierColor: Colors.black45,
      builder: (context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Material(
            color: Colors.transparent,
            child: AspectRatio(
              aspectRatio: 1 / kSheetAspect,
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFFDFBF6),
                  borderRadius: BorderRadius.circular(6),
                  boxShadow: const [
                    BoxShadow(color: Colors.black26, blurRadius: 24)
                  ],
                ),
                child: LayoutBuilder(
                  builder: (context, c) => Stack(children: [
                    Positioned.fill(
                        child: CustomPaint(
                            painter: RuledPainter(c.maxWidth * .09, 1))),
                    Padding(
                      padding: EdgeInsets.fromLTRB(c.maxWidth * .14,
                          c.maxWidth * .1, c.maxWidth * .06, c.maxWidth * .1),
                      child: Center(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: ConstrainedBox(
                            constraints:
                                BoxConstraints(maxWidth: c.maxWidth * .8),
                            child: Text(l.body,
                                textAlign: TextAlign.center, style: hand(26)),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 14,
                      right: 14,
                      bottom: 10,
                      child: Text(
                          '${txt.toName(l.to!.name)} · ${txt.ago(l.sentAt)} · '
                          '${l.inFlight ? sentStatus(l) : l.unread ? txt.notOpenedYet : txt.readMark}',
                          textAlign: TextAlign.center,
                          style: ui(11, color: kMuted)),
                    ),
                    Positioned(
                      right: 2,
                      top: 2,
                      child: IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close, color: kMuted)),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );

/// Gelen uçak: ufuktan burnu önde düz gelir, iner, açılır ve mektup olur
class InboxScreen extends StatefulWidget {
  final Letter letter;
  final LatLng home;
  final Api api;
  final void Function(CameraPosition, int) camera;
  const InboxScreen(
      {super.key,
      required this.letter,
      required this.home,
      required this.api,
      required this.camera});
  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

const kIncoming = 6.2; // yaklaşma 3.6 + oturma 0.8 + açılma 1.4 (sn)

class _InboxScreenState extends State<InboxScreen>
    with TickerProviderStateMixin {
  late final seq = AnimationController(
      vsync: this, duration: Duration(milliseconds: (kIncoming * 1000).round()))
    ..addListener(_markOpened);
  final clouds = CloudField();
  final clock = ValueNotifier<double>(0);
  late final Ticker _ticker;
  double _last = 0;
  Timer? _start;
  bool _opened = false;

  double get _ts => seq.value * kIncoming;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((e) {
      final t = e.inMicroseconds / 1e6;
      clouds.step(
          (t - _last).clamp(0.0, .05), lerp(12, .5, clamp01(_ts / 3.6)));
      _last = t;
      clock.value = t;
    })
      ..start();
    // Daha önce açılmış mektup uçmadan, yerde açılır
    if (!widget.letter.unread) seq.value = 3.6 / kIncoming;
    _start = Timer(const Duration(milliseconds: 450), () {
      seq.forward();
      widget.camera(
          CameraPosition(
              target: widget.home, zoom: 16.5, tilt: 62, bearing: 215),
          widget.letter.unread ? 4200 : 1200);
    });
  }

  void _markOpened() {
    if (_opened || _ts < 4.4 || !widget.letter.unread) return;
    _opened = true;
    widget.api.open(widget.letter.id).catchError((_) {});
  }

  /// Gönderenin kartı: arkadaş ekle, engelle, ona yaz
  Future<void> _openSender() async {
    final from = widget.letter.from!;
    final r = await showPersonSheet(context,
        api: widget.api, person: from, home: widget.home);
    if (!mounted || r == null) return;
    if (r == PersonAction.write) return Navigator.pop(context, 'reply');
    // Engellendiyse mektup ekranı kapanır (ana ekran yenilenir)
    try {
      final p = await widget.api.user(from.id);
      if (p.blocked && mounted) Navigator.pop(context);
    } on ApiException catch (_) {}
  }

  @override
  void dispose() {
    _start?.cancel();
    _ticker.dispose();
    seq.dispose();
    clock.dispose();
    super.dispose();
  }

  /// (poz, yerden yükseklik, katlanma)
  (Pose, double, double) _pose(Size s, double f) {
    final cy = s.height / 2;
    double yAt(double screenY, double z) => (cy - screenY) * z / f;
    const zl = 6.8, landX = -.2;
    final landY = yAt(s.height * .68, zl);
    final startY = yAt(s.height * .3, 60);

    V3 path(double u) {
      final e = 1 - math.pow(1 - u, 2.2).toDouble();
      return V3(lerp(-1.3, landX, e) + .3 * math.sin(e * math.pi) * (1 - e),
          lerp(startY, landY, Curves.easeInOut.transform(u)), lerp(60, zl, e));
    }

    // Burun her zaman gidiş yönüne baksın
    double heading(double u) {
      final a = path(math.max(0, u - .01)), b = path(math.min(.97, u + .01));
      final d = b - a;
      return math.atan2(d.x, d.z);
    }

    final yawLand = heading(.96);
    final land = Pose(V3(landX, landY, zl), yaw: yawLand, pitch: -.03);
    final ground = landY - .02;
    final hn = math.min(s.width * .9 * kSheetAspect, s.height * .6);
    final upright = (yawLand / (2 * math.pi)).round() * 2 * math.pi;
    final letter = paperPose(s.height * .47, hn, f, s.height, yaw: upright);

    final ts = _ts;
    if (ts < 3.6) {
      final u = ts / 3.6;
      final e = 1 - math.pow(1 - u, 2.2).toDouble();
      final p = path(u);
      return (
        Pose(p,
            yaw: heading(math.min(u, .96)),
            roll: -.3 * math.sin(e * math.pi) * (1 - e),
            pitch: -.03 + .1 * (1 - e)),
        p.y - ground,
        1
      );
    }
    if (ts < 4.4) {
      final u = (ts - 3.6) / .8;
      final b = .05 * math.sin(u * math.pi) * (1 - u);
      return (land.copyWith(pos: land.pos + V3(0, b, 0)), .02 + b, 1);
    }
    final u = Curves.easeInOutCubic.transform(clamp01((ts - 4.4) / 1.4));
    return (Pose.lerp(land, letter, u), .02, 1 - u);
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    final l = widget.letter;
    final from = l.from!;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: LayoutBuilder(builder: (context, c) {
        final s = c.biggest;
        final f = s.width * 2.2;
        final cen = s.center(Offset.zero);
        return AnimatedBuilder(
          animation: Listenable.merge([clock, seq]),
          builder: (context, _) {
            if (s.width < 10 || s.height < 10) return const SizedBox();
            final ts = _ts;
            final (pose, hover, fold) = _pose(s, f);
            final letterIn = clamp01((ts - 5.7) / .5);
            final arrived = ts > 3.6;
            final rect = sheetRect(pose, f, cen);
            return Stack(children: [
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                      painter: CloudPainter(
                          clouds, lerp(.9, .15, clamp01(ts / 3)), f)),
                ),
              ),
              Positioned(
                top: pad.top + 10,
                left: 0,
                right: 0,
                child: Column(children: [
                  Text(txt.inbox, style: ui(18, weight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: _openSender,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: glass(22),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Avatar(person: from, size: 30),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                              arrived
                                  ? '${txt.fromName(from.name)} · ${from.location} · ${txt.km(l.distanceKm)}'
                                  : txt.planeComing(from.name),
                              overflow: TextOverflow.ellipsis,
                              style: ui(13, weight: FontWeight.w600)),
                        ),
                        const Icon(Icons.chevron_right,
                            size: 18, color: kMuted),
                      ]),
                    ),
                  ),
                ]),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: PaperPainter(
                        pose: pose,
                        fold: fold,
                        f: f,
                        hover: hover,
                        // Uçak olarak gelen mektup açılınca da buruşuk kalır
                        crumple: .03),
                  ),
                ),
              ),
              if (letterIn > 0)
                Positioned.fromRect(
                  rect: rect,
                  child: IgnorePointer(
                    child: Opacity(
                      opacity: letterIn,
                      child: Stack(children: [
                        Positioned.fill(
                            child: CustomPaint(
                                painter: RuledPainter(rect.width * .09, 1))),
                        Padding(
                          padding: EdgeInsets.fromLTRB(
                              rect.width * .14,
                              rect.width * .08,
                              rect.width * .06,
                              rect.width * .06),
                          child: Center(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: ConstrainedBox(
                                constraints:
                                    BoxConstraints(maxWidth: rect.width * .8),
                                child: Text(l.body,
                                    textAlign: TextAlign.center,
                                    style: hand(26)),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          right: 12,
                          bottom: 8,
                          child: Text(txt.ago(l.sentAt),
                              style: ui(10, color: kMuted)),
                        ),
                      ]),
                    ),
                  ),
                ),
              Positioned(
                top: rect.bottom + 18,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  ignoring: letterIn < 1,
                  child: Opacity(
                    opacity: letterIn,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _action(Icons.close, txt.close,
                            () => Navigator.pop(context)),
                        const SizedBox(width: 12),
                        _action(Icons.reply, txt.replyToName(from.name),
                            () => Navigator.pop(context, 'reply'),
                            primary: true),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 18,
                bottom: 22 + pad.bottom,
                child: GlassButton(
                  size: 48,
                  onTap: () => Navigator.pop(context),
                  child: const Icon(Icons.chevron_left, color: kNavy),
                ),
              ),
            ]);
          },
        );
      }),
    );
  }

  Widget _action(IconData icon, String label, VoidCallback onTap,
          {bool primary = false}) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: primary
              ? BoxDecoration(
                  color: kNavy, borderRadius: BorderRadius.circular(24))
              : glass(24),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 18, color: primary ? Colors.white : kNavy),
            const SizedBox(width: 6),
            Text(label,
                style: ui(14,
                    weight: FontWeight.w700,
                    color: primary ? Colors.white : kNavy)),
          ]),
        ),
      );
}
