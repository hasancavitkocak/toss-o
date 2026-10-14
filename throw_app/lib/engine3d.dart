// Mini 3D motoru: mektup kağıdı ve kağıt uçak aynı üçgen ağından çizilir.
// Kamera uzayı: x sağ, y yukarı, z ekranın içine doğru.
import 'dart:math' as math;
import 'package:flutter/material.dart';

double clamp01(double v) => v.clamp(0.0, 1.0);
double lerp(double a, double b, double t) => a + (b - a) * t;

class V3 {
  final double x, y, z;
  const V3(this.x, this.y, this.z);
  V3 operator +(V3 o) => V3(x + o.x, y + o.y, z + o.z);
  V3 operator -(V3 o) => V3(x - o.x, y - o.y, z - o.z);
  V3 operator *(double k) => V3(x * k, y * k, z * k);
  double dot(V3 o) => x * o.x + y * o.y + z * o.z;
  V3 cross(V3 o) => V3(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x);
  double get length => math.sqrt(dot(this));
  V3 get unit => length == 0 ? this : this * (1 / length);
  static V3 lerp(V3 a, V3 b, double t) => a + (b - a) * t;
}

class Pose {
  final V3 pos;
  final double pitch, yaw, roll;
  const Pose(this.pos, {this.pitch = 0, this.yaw = 0, this.roll = 0});

  /// Model noktasını kamera uzayına taşır (roll → pitch → yaw → öteleme)
  V3 apply(V3 p) {
    final cr = math.cos(roll), sr = math.sin(roll);
    final x = p.x * cr - p.y * sr, y1 = p.x * sr + p.y * cr;
    final cp = math.cos(pitch), sp = math.sin(pitch);
    final y = y1 * cp - p.z * sp, z = y1 * sp + p.z * cp;
    final cy = math.cos(yaw), sy = math.sin(yaw);
    return V3(x * cy + z * sy + pos.x, y + pos.y, -x * sy + z * cy + pos.z);
  }

  Pose copyWith({V3? pos, double? pitch, double? yaw, double? roll}) =>
      Pose(pos ?? this.pos,
          pitch: pitch ?? this.pitch,
          yaw: yaw ?? this.yaw,
          roll: roll ?? this.roll);

  static Pose lerp(Pose a, Pose b, double t) => Pose(V3.lerp(a.pos, b.pos, t),
      pitch: _l(a.pitch, b.pitch, t),
      yaw: _l(a.yaw, b.yaw, t),
      roll: _l(a.roll, b.roll, t));
  static double _l(double a, double b, double t) => a + (b - a) * t;
}

class _Facet {
  final List<V3> flat, plane;
  final double start, end;
  const _Facet(this.flat, this.plane, this.start, this.end);
}

// Klasik "dart" kağıt uçak (burun +z): gövde V şeklinde aşağı sarkar,
// kanatlar gövdenin üst kenarından hafif yukarı açıyla uzanır, arka kenar düz.
const _n = V3(0, .02, 1.05);
const _t = V3(0, -.30, -.85); // omurga (gövdenin alt ucu)
const _lm = V3(-.045, .03, -.85), _lw = V3(-.62, .13, -.85); // kök, kanat ucu
const _rm = V3(.045, .03, -.85), _rw = V3(.62, .13, -.85);
// Düz kağıt (xz düzleminde 1.6 x 1.9)
const _tc = V3(0, 0, 1.0), _bc = V3(0, 0, -.9);
const _tl = V3(-.8, 0, 1.0), _bl = V3(-.8, 0, -.9);
const _tr = V3(.8, 0, 1.0), _br = V3(.8, 0, -.9);
const kSheetCorners = [_tl, _tr, _br, _bl];
const kSheetAspect = 1.9 / 1.6;

/// Üst köşeler aşağı doğru katlanıp kanat olur, sonra iki yan gövde olur
const kFacets = [
  _Facet([_tc, _bl, _tl], [_n, _lm, _lw], 0, .6),
  _Facet([_tc, _br, _tr], [_n, _rm, _rw], .06, .66),
  _Facet([_tc, _bc, _bl], [_n, _t, _lm], .25, .92),
  _Facet([_tc, _bc, _br], [_n, _t, _rm], .3, 1),
];

/// Katlandıkça buruşur; uçak bitince kenarlar net kalsın diye biraz düzelir
double crumpleFor(double fold) => .008 + .045 * fold * (1 - .6 * fold);

final kLight = const V3(-.35, .75, -.55).unit;

/// Kağıt buruşukluğu: düz kağıt koordinatına bağlı, dikişsiz dalgalanma
double paperNoise(double x, double z) =>
    .5 * math.sin(7.3 * x + 1.1) * math.sin(6.1 * z + .4) +
    .3 * math.sin(12.7 * x + 5.3 * z + 2.1) +
    .22 * math.sin(-9.4 * x + 14.2 * z + .6) +
    .14 * math.sin(21 * x - 17 * z + 1.7);

class Tri {
  final List<V3> p;
  final double depth, light;
  const Tri(this.p, this.depth, this.light);
}

class Mesh {
  final List<Tri> tris;
  final List<List<V3>> creases;
  const Mesh(this.tris, this.creases);
}

const _sub = 4;

/// [fold] 0 = düz kağıt, 1 = uçak. [crumple] buruşukluk genliği.
Mesh buildMesh(Pose pose, double fold, double crumple) {
  final tris = <Tri>[];
  final creases = <List<V3>>[];
  for (final fc in kFacets) {
    final l = Curves.easeInOutCubic
        .transform(clamp01((fold - fc.start) / (fc.end - fc.start)));
    V3 point(double w0, double w1) {
      final w2 = 1 - w0 - w1;
      final a = fc.flat[0] * w0 + fc.flat[1] * w1 + fc.flat[2] * w2;
      final b = fc.plane[0] * w0 + fc.plane[1] * w1 + fc.plane[2] * w2;
      // Katlanan köşe kağıttan kalkıp kavis çizerek yerine iner
      final lift = math.sin(math.pi * l) * .3 * (b - a).length;
      final bump = crumple * paperNoise(a.x, a.z);
      return pose.apply(V3.lerp(a, b, l) + V3(0, lift + bump, 0));
    }

    final grid = <List<V3>>[
      for (var i = 0; i <= _sub; i++)
        [for (var j = 0; j <= _sub - i; j++) point(i / _sub, j / _sub)]
    ];
    void add(V3 a, V3 b, V3 c) {
      var n = (b - a).cross(c - a).unit;
      final m = (a + b + c) * (1 / 3);
      if (n.dot(m) > 0) n = n * -1;
      tris.add(Tri([a, b, c], m.z, clamp01(n.dot(kLight))));
    }

    for (var i = 0; i < _sub; i++) {
      for (var j = 0; j < _sub - i; j++) {
        add(grid[i][j], grid[i + 1][j], grid[i][j + 1]);
        if (j < _sub - i - 1) {
          add(grid[i + 1][j], grid[i + 1][j + 1], grid[i][j + 1]);
        }
      }
    }
    creases.add([grid[_sub][0], grid[0][_sub], grid[0][0]]);
  }
  tris.sort((a, b) => b.depth.compareTo(a.depth));
  return Mesh(tris, creases);
}

Offset project(V3 p, double f, Offset c) =>
    Offset(c.dx + p.x * f / p.z, c.dy - p.y * f / p.z);

Rect sheetRect(Pose pose, double f, Offset c) => Rect.fromPoints(
    project(pose.apply(_tl), f, c), project(pose.apply(_br), f, c));

Rect meshBounds(Pose pose, double fold, double f, Offset c) {
  Rect? r;
  for (final fc in kFacets) {
    for (final v in fold >= 1 ? fc.plane : fc.flat) {
      final p = project(pose.apply(v), f, c);
      final pr = Rect.fromPoints(p, p);
      r = r == null ? pr : r.expandToInclude(pr);
    }
  }
  return r ?? Rect.zero;
}

/// Kağıdın ekranda [centerY] merkezli, [height] yüksekliğinde dik durduğu poz
Pose paperPose(double centerY, double height, double f, double screenH,
    {double yaw = 0}) {
  final z = 1.9 * f / height;
  return Pose(V3(0, (screenH / 2 - centerY) * z / f - .05, z),
      pitch: -math.pi / 2, yaw: yaw);
}

const kPaper = Color(0xFFFFFDF7);
const kPaperShade = Color(0xFFB4AEA2);

/// Kağıdı / uçağı ışık-gölge, buruşukluk ve yere düşen gölgeyle çizer
class PaperPainter extends CustomPainter {
  final Pose pose;
  final double fold, hover, f, opacity, crumple;
  PaperPainter(
      {required this.pose,
      required this.fold,
      required this.f,
      required this.crumple,
      this.hover = .3,
      this.opacity = 1});

  @override
  void paint(Canvas canvas, Size s) {
    if (opacity <= 0) return;
    final c = s.center(Offset.zero);
    final mesh = buildMesh(pose, fold, crumple);
    if (mesh.tris.any((t) => t.p.any((p) => p.z < .3))) return;
    if (opacity < 1) {
      canvas.saveLayer(
          null, Paint()..color = Colors.black.withValues(alpha: opacity));
    }
    Offset pr(V3 p) => project(p, f, c);

    // Düz kağıdın yumuşak gölgesi
    if (fold < 1) {
      final sheet = Path()
        ..addPolygon([for (final v in kSheetCorners) pr(pose.apply(v))], true);
      canvas.drawPath(
          sheet.shift(const Offset(0, 14)),
          Paint()
            ..color = Colors.black.withValues(alpha: .13 * (1 - fold))
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18));
    }
    // Uçağın yere düşen gölgesi: yükseldikçe silikleşir ve dağılır
    if (fold > 0 && hover < 3) {
      final gy = pose.pos.y - .36 - hover;
      final sp = Path();
      for (final t in mesh.tris) {
        sp.addPolygon([for (final p in t.p) pr(V3(p.x, gy, p.z))], true);
      }
      canvas.drawPath(
          sp,
          Paint()
            ..color = const Color(0xFF0E1B33)
                .withValues(alpha: .14 * fold * clamp01(1 - hover / 3))
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4 + hover * 10));
    }
    for (final t in mesh.tris) {
      final path = Path()..addPolygon([for (final p in t.p) pr(p)], true);
      final col = Color.lerp(
          kPaperShade, kPaper, (.55 + .62 * t.light).clamp(0.0, 1.0))!;
      canvas.drawPath(path, Paint()..color = col);
      // Üçgenler arası ince dikişleri kapat
      canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = .9
            ..color = col);
    }
    // Katlama izleri
    if (fold > .05) {
      final crease = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = .9
        ..strokeJoin = StrokeJoin.round
        ..color = const Color(0xFF6F6A60).withValues(alpha: .45 * fold);
      for (final edge in mesh.creases) {
        canvas.drawPath(
            Path()..addPolygon([for (final p in edge) pr(p)], true), crease);
      }
    }
    if (opacity < 1) canvas.restore();
  }

  @override
  bool shouldRepaint(PaperPainter old) => true;
}

// ---------- bulutlar: kameraya doğru akan 3D bulut alanı ----------

class Cloud {
  double x, y, z;
  final double r, seed;
  Cloud(this.x, this.y, this.z, this.r, this.seed);
}

class CloudField {
  final _r = math.Random(11);
  late final List<Cloud> items =
      List.generate(20, (_) => _spawn(2 + _r.nextDouble() * 40));

  Cloud _spawn(double z) => Cloud(
      (_r.nextDouble() * 2 - 1) * 9,
      -1.4 + _r.nextDouble() * 4.4,
      z,
      .8 + _r.nextDouble() * 1.6,
      _r.nextDouble());

  void step(double dt, double speed) {
    for (var i = 0; i < items.length; i++) {
      final c = items[i];
      c.z -= speed * dt;
      c.x += .06 * dt;
      if (c.z < 1) items[i] = _spawn(40 + _r.nextDouble() * 8);
    }
  }
}

class CloudPainter extends CustomPainter {
  final CloudField field;
  final double density, f;
  CloudPainter(this.field, this.density, this.f);

  @override
  void paint(Canvas canvas, Size s) {
    if (density <= .01) return;
    final c = s.center(Offset.zero);
    final list = [...field.items]..sort((a, b) => b.z.compareTo(a.z));
    for (final cl in list) {
      final p = project(V3(cl.x, cl.y, cl.z), f, c);
      final r = cl.r * f / cl.z;
      if (p.dx + r * 1.3 < 0 || p.dx - r * 1.3 > s.width) continue;
      if (p.dy + r < 0 || p.dy - r > s.height) continue;
      final a = density *
          .8 *
          clamp01((cl.z - 1) / 3) *
          clamp01((46 - cl.z) / 10) *
          clamp01((3 * s.width - r) / s.width);
      if (a <= .01) continue;
      final blur =
          MaskFilter.blur(BlurStyle.normal, (r * .35).clamp(4.0, 40.0));
      // Altta hafif gri-mavi gölge: beyaz gökyüzünde de bulut seçilsin
      canvas.drawOval(
          Rect.fromCenter(
              center: p + Offset(0, r * .18), width: r * 2.4, height: r * 1.0),
          Paint()
            ..color = const Color(0xFFC9D3E2).withValues(alpha: a * .55)
            ..maskFilter = blur);
      final white = Paint()
        ..color = Colors.white.withValues(alpha: a)
        ..maskFilter = blur;
      canvas.drawOval(
          Rect.fromCenter(center: p, width: r * 2.4, height: r * 1.1), white);
      canvas.drawOval(
          Rect.fromCenter(
              center: p + Offset(r * (cl.seed - .5), -r * .3),
              width: r * 1.4,
              height: r * .9),
          white);
    }
  }

  @override
  bool shouldRepaint(CloudPainter old) => true;
}
