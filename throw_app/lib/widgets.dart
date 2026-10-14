import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'api.dart';
import 'i18n.dart';
import 'models.dart';

// Logodaki renkler: lacivert + kırmızı
const kNavy = Color(0xFF0E1B33);
const kRed = Color(0xFFE5262C);
const kInk = Color(0xFF1F2E6E); // dolma kalem mürekkebi
const kGround = Color(0xFFF4F5F7);
const kMuted = Color(0xFF6B7280);

// Harita stili: varsayılan OpenFreeMap "liberty" (anahtarsız, 3D binalı).
// Yayında kendi harita sunucumuz verilir: --dart-define=MAP_STYLE=https://...
const kMapStyle = String.fromEnvironment('MAP_STYLE',
    defaultValue: 'https://tiles.openfreemap.org/styles/liberty');

TextStyle hand(double size, [double alpha = 1]) => TextStyle(
    fontFamily: 'Caveat',
    fontSize: size,
    fontWeight: FontWeight.w500,
    color: kInk.withValues(alpha: alpha),
    height: 1.15);

TextStyle ui(double size,
        {FontWeight weight = FontWeight.w500, Color color = kNavy}) =>
    TextStyle(
        fontFamily: 'Inter', fontSize: size, fontWeight: weight, color: color);

BoxDecoration glass(double radius) => BoxDecoration(
      color: Colors.white.withValues(alpha: .9),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: Colors.white, width: 1),
      boxShadow: const [
        BoxShadow(
            color: Color(0x1A0E1B33), blurRadius: 16, offset: Offset(0, 4))
      ],
    );

class Logo extends StatelessWidget {
  final double height;
  const Logo({super.key, this.height = 36});
  @override
  Widget build(BuildContext context) =>
      Image.asset('assets/logo.png', height: height, fit: BoxFit.contain);
}

/// Ufku beyaz gökyüzüne eriten sis + yolculukta pus
class Atmosphere extends StatelessWidget {
  final double haze;
  const Atmosphere({super.key, this.haze = 0});
  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: const [0, .2, .42, .8, 1],
              colors: [
                Colors.white,
                Colors.white.withValues(alpha: .85),
                const Color(0xFFEFF3F8).withValues(alpha: .04 + haze * .55),
                const Color(0xFFEFF3F8).withValues(alpha: .04 + haze * .4),
                Colors.white.withValues(alpha: .6),
              ],
            ),
          ),
        ),
      );
}

/// Web'de "/map/..." gibi göreli adres, sitenin kendi adresiyle tamamlanır
String mapStyleUrl() => kMapStyle.startsWith('/') && kIsWeb
    ? '${Uri.base.origin}$kMapStyle'
    : kMapStyle;

class Map3D extends StatelessWidget {
  final CameraPosition camera;
  final void Function(MapLibreMapController) onCreated;
  const Map3D({super.key, required this.camera, required this.onCreated});
  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: MapLibreMap(
          styleString: mapStyleUrl(),
          initialCameraPosition: camera,
          onMapCreated: onCreated,
          compassEnabled: false,
          rotateGesturesEnabled: false,
          scrollGesturesEnabled: false,
          zoomGesturesEnabled: false,
          tiltGesturesEnabled: false,
          doubleClickZoomEnabled: false,
          dragEnabled: false,
          myLocationEnabled: false,
          attributionButtonPosition: AttributionButtonPosition.bottomLeft,
        ),
      );
}

class GlassButton extends StatelessWidget {
  final Widget child;
  final VoidCallback onTap;
  final double size;
  final int badge;
  const GlassButton(
      {super.key,
      required this.child,
      required this.onTap,
      this.size = 56,
      this.badge = 0});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Stack(clipBehavior: Clip.none, children: [
          Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: glass(size / 2),
            child: child,
          ),
          if (badge > 0)
            Positioned(
              right: -3,
              top: -3,
              child: Container(
                constraints: const BoxConstraints(minWidth: 18),
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                    color: kRed,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: Colors.white, width: 2)),
                child: Text('$badge',
                    textAlign: TextAlign.center,
                    style:
                        ui(10, weight: FontWeight.w700, color: Colors.white)),
              ),
            ),
        ]),
      );
}

class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool busy;
  const PrimaryButton(
      {super.key, required this.label, this.onTap, this.busy = false});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: busy ? null : onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: onTap == null ? kNavy.withValues(alpha: .4) : kNavy,
            borderRadius: BorderRadius.circular(26),
          ),
          child: busy
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.4, color: Colors.white))
              : Text(label,
                  style: ui(15, weight: FontWeight.w700, color: Colors.white)),
        ),
      );
}

class Stat extends StatelessWidget {
  final String icon, label;
  final int count;
  const Stat(
      {super.key,
      required this.icon,
      required this.count,
      required this.label});
  @override
  Widget build(BuildContext context) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Text(icon, style: const TextStyle(fontSize: 14)),
        const SizedBox(width: 6),
        Text('$count', style: ui(14, weight: FontWeight.w700)),
        const SizedBox(width: 4),
        Text(label, style: ui(13, color: kMuted)),
      ]);
}

class Avatar extends StatelessWidget {
  final Person person;
  final double size;
  const Avatar({super.key, required this.person, this.size = 52});
  @override
  Widget build(BuildContext context) {
    if (person.random) {
      return Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
              colors: [kNavy, Color(0xFF2B4A85)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight),
        ),
        child: Icon(Icons.public, color: Colors.white, size: size * .52),
      );
    }
    // Fotoğraf yoksa baş harf: dış servise (avatar üreticisi) istek gitmez
    final initial = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: _avatarColors(person.id),
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Text(
          person.name.isEmpty
              ? '?'
              : person.name.characters.first.toUpperCase(),
          style: ui(size * .42, weight: FontWeight.w800, color: Colors.white)),
    );
    if (person.photo == null) return initial;
    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: Image.network(
          '${Api.root}${person.photo}',
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => initial,
        ),
      ),
    );
  }
}

/// Kişiye özgü, kimlikten türetilen sabit renk çifti
List<Color> _avatarColors(String id) {
  const palette = [
    [Color(0xFF2B4A85), Color(0xFF5B7FC7)],
    [Color(0xFFE5262C), Color(0xFFFF7A59)],
    [Color(0xFF138A72), Color(0xFF4CC9A6)],
    [Color(0xFF7A4BC2), Color(0xFFB08AE8)],
    [Color(0xFFD97706), Color(0xFFFBBF24)],
    [Color(0xFF0E7490), Color(0xFF38BDF8)],
    [Color(0xFFBE185D), Color(0xFFF472B6)],
    [Color(0xFF4D7C0F), Color(0xFFA3E635)],
  ];
  var h = 0;
  for (final c in id.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return palette[h % palette.length];
}

/// Üstteki kişi seçici: ortadaki kişide elle çizilmiş halka
class FriendBadge extends StatelessWidget {
  final Person person;
  final bool ring;
  const FriendBadge({super.key, required this.person, this.ring = false});
  @override
  Widget build(BuildContext context) =>
      Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          width: 68,
          height: 68,
          child: Stack(alignment: Alignment.center, children: [
            Container(
              width: 60,
              height: 60,
              decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: Color(0x220E1B33), blurRadius: 8)
                  ]),
            ),
            Avatar(person: person, size: 52),
            if (ring)
              const Positioned.fill(
                  child: CustomPaint(painter: SketchRingPainter())),
          ]),
        ),
        const SizedBox(height: 4),
        Text(person.random ? txt.randomName : person.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: ui(13, weight: FontWeight.w700)),
        Text(person.random ? txt.somewhere : person.city,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: ui(11, color: kMuted)),
      ]);
}

class SketchRingPainter extends CustomPainter {
  const SketchRingPainter();
  @override
  void paint(Canvas c, Size s) {
    final center = s.center(Offset.zero);
    final r = s.shortestSide / 2 - 2;
    for (final phase in [0.0, 1.7]) {
      final path = Path();
      for (var i = 0; i <= 64; i++) {
        final a = i / 64 * 2 * math.pi;
        final rr = r *
            (1 +
                .025 * math.sin(3 * a + phase) +
                .015 * math.sin(7 * a + phase * 2));
        final p = center + Offset(math.cos(a), math.sin(a)) * rr;
        i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
      }
      c.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = phase == 0 ? 2.6 : 1.2
          ..color = phase == 0 ? kRed : kNavy.withValues(alpha: .5),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

/// Logodaki gibi kırmızı konum pini; ucu widget'ın tepesinden [tipOffset] aşağıda
class AvatarPin extends StatelessWidget {
  final Person person;
  final bool check;
  final double size;
  const AvatarPin(
      {super.key, required this.person, this.check = false, this.size = 58});

  static double tipOffset(double size) => size * 1.25;

  @override
  Widget build(BuildContext context) =>
      Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          width: size + 20,
          height: tipOffset(size) + 6,
          child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.topCenter,
              children: [
                Positioned(
                  top: tipOffset(size) - 3,
                  child: Container(
                    width: size * .7,
                    height: 8,
                    decoration: BoxDecoration(
                        color: const Color(0xFF9AA7C0).withValues(alpha: .7),
                        borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                CustomPaint(
                    size: Size(size, tipOffset(size)), painter: _PinPainter()),
                Positioned(
                    top: 6, child: Avatar(person: person, size: size - 12)),
                Positioned(
                  top: size - 24,
                  right: 4,
                  child: AnimatedScale(
                    scale: check ? 1 : 0,
                    duration: const Duration(milliseconds: 350),
                    curve: Curves.easeOutBack,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                          color: const Color(0xFF22B45A),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2)),
                      child: const Icon(Icons.check,
                          size: 12, color: Colors.white),
                    ),
                  ),
                ),
              ]),
        ),
        const SizedBox(height: 2),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .92),
              borderRadius: BorderRadius.circular(8)),
          child: Text('${person.name} · ${person.location}',
              style: ui(12, weight: FontWeight.w700)),
        ),
      ]);
}

class _PinPainter extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    final r = s.width / 2;
    final path = Path()
      ..addOval(Rect.fromCircle(center: Offset(r, r), radius: r))
      ..moveTo(r - r * .55, r + r * .8)
      ..lineTo(r, s.height)
      ..lineTo(r + r * .55, r + r * .8)
      ..close();
    c.drawShadow(path, kNavy, 4, false);
    c.drawPath(
        path,
        Paint()
          ..shader = const LinearGradient(
            colors: [Color(0xFFFF4B4B), kRed, Color(0xFFC81E24)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ).createShader(Offset.zero & s));
    c.drawCircle(Offset(r, r), r - 4, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

/// Mektup kağıdındaki silik çizgiler ve kenar boşluğu çizgisi
class RuledPainter extends CustomPainter {
  final double gap, alpha;
  RuledPainter(this.gap, this.alpha);
  @override
  void paint(Canvas c, Size s) {
    final line = Paint()
      ..color = const Color(0xFF7A8BB5).withValues(alpha: .16 * alpha)
      ..strokeWidth = 1;
    for (var y = s.height * .1 + gap; y < s.height * .94; y += gap) {
      c.drawLine(Offset(s.width * .06, y), Offset(s.width * .94, y), line);
    }
    c.drawLine(
        Offset(s.width * .11, s.height * .04),
        Offset(s.width * .11, s.height * .96),
        Paint()
          ..color = kRed.withValues(alpha: .18 * alpha)
          ..strokeWidth = 1);
  }

  @override
  bool shouldRepaint(RuledPainter old) => old.gap != gap || old.alpha != alpha;
}

void showToast(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(text, style: ui(14, color: Colors.white)),
      backgroundColor: kNavy,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ));
}
