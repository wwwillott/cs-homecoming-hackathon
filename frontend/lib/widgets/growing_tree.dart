import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path_parsing/path_parsing.dart';

const growingTreeAspect = 460 / 410;
const _viewBox = Rect.fromLTWH(72, 32, 460, 410);
const fullTreeGrowth = 6;

/// The network tree drawn at [growth], from 0 (seedling) to [fullTreeGrowth] (full bloom).
/// Fractional values render the in-between frames of a growth animation.
class GrowingTree extends StatelessWidget {
  const GrowingTree({super.key, required this.growth});
  final double growth;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _TreePainter(growth), size: Size.infinite);
  }
}

class _SvgPath extends PathProxy {
  final path = Path();

  @override
  void moveTo(double x, double y) => path.moveTo(x, y);

  @override
  void lineTo(double x, double y) => path.lineTo(x, y);

  @override
  void cubicTo(double x1, double y1, double x2, double y2, double x3, double y3) =>
      path.cubicTo(x1, y1, x2, y2, x3, y3);

  @override
  void close() => path.close();
}

Path _p(String d) {
  final proxy = _SvgPath();
  writeSvgPathDataToPath(d, proxy);
  return proxy.path;
}

class _Branch {
  _Branch(String d, this.width, this.from, this.to) : path = _p(d) {
    bounds = path.getBounds();
  }
  final Path path;
  final double width;
  final double from;
  final double to;
  late final Rect bounds;
}

class _Crown {
  const _Crown(this.dx, this.dy, this.scale, this.shape, this.palette, this.from, this.to);
  final double dx;
  final double dy;
  final double scale;
  final int shape;
  final int palette;
  final double from;
  final double to;
}

class _Flower {
  const _Flower(this.dx, this.dy, this.rotation, this.from, this.to);
  final double dx;
  final double dy;
  final double rotation;
  final double from;
  final double to;
}

final _crownShapes = [
  _p('M-65 8C-80-9-72-31-54-38C-57-58-37-72-18-65C-3-84 26-79 34-60C56-64 76-45 68-24C86-6 73 18 54 22C40 42 18 38 5 32C-17 43-39 33-43 23C-54 27-66 20-65 8Z'),
  _p('M-64 8C-80-12-65-36-48-38C-46-61-20-74-2-64C17-82 44-70 48-50C73-45 78-23 65-8C76 11 55 32 39 27C24 43 0 40-12 29C-35 40-57 29-57 19C-63 18-66 15-64 8Z'),
  _p('M-65 3C-72-18-57-38-41-39C-44-59-18-72 0-59C16-76 39-64 42-47C65-51 81-25 67-9C82 8 62 31 44 27C33 43 11 40 0 30C-20 42-41 32-45 22C-57 26-69 16-65 3Z'),
];
final _crownBounds = [for (final c in _crownShapes) c.getBounds()];

const _foliagePalettes = [
  [Color(0xFF82AA7D), Color(0xFF507F61)],
  [Color(0xFFA1C28B), Color(0xFF66986F)],
  [Color(0xFFBFD29B), Color(0xFF85AD7B)],
];

const _woodColors = [Color(0xFF9B6E50), Color(0xFFBB8962), Color(0xFF835C45)];
const _woodStops = [0.0, 0.48, 1.0];

final _soil = _p('M-148 0C-129-18-69-23-10-22C55-23 113-16 142-3C162 7 129 18 74 21C14 27-74 25-120 16C-140 12-156 6-148 0Z');
final _soilShine = _p('M-128-4C-83-15-53-14-24-15M65-12Q96-10 112-5');
final _grass = _p('M-86-4Q-91-17-98-19M-87-4Q-84-20-78-24M-85-5Q-79-14-73-14M96 1Q100-12 108-15M96 1Q94-9 90-12');

final _trunk = _p('M-27 0C-11-15-13-45-10-77C-8-109-16-147-6-178C1-199 5-219 1-241C15-220 11-193 7-171C1-145 8-121 12-96C18-62 12-23 30-2C13 5-8 6-27 0Z');
final _trunkShine = _p('M-5-9C1-32-3-52 0-76C3-102-6-122-4-144');
final _trunkShade = _p('M12-13Q7-33 9-48M-5-169Q4-193 3-213');
final _roots = _p('M-13-2Q-25 2-35 0M17-1Q28 4 36 2');

final _branches = [
  _Branch('M-3-143Q-32-146-56-177', 10, 0.2, 0.9),
  _Branch('M3-181Q25-185 43-212', 8, 0.2, 0.9),
  _Branch('M0-95C-26-120-51-142-82-189', 17, 0, 0.7),
  _Branch('M6-127C29-136 55-150 75-197', 14, 0, 0.7),
  _Branch('M-38-145Q-79-145-115-186M-58-164Q-59-203-76-224', 10, 1, 1.6),
  _Branch('M37-150Q78-147 114-189M44-157Q42-200 63-224', 10, 1, 1.6),
  _Branch('M-63-158Q-118-150-151-195M-90-171Q-105-197-100-222', 8, 2, 2.6),
  _Branch('M66-162Q111-145 151-194M102-168Q96-198 114-228', 8, 2, 2.6),
  _Branch('M-103-169Q-158-159-190-207M-144-177Q-147-209-167-226', 6, 3, 3.6),
  _Branch('M103-170Q160-165 192-208M147-180Q151-212 165-236', 6, 3, 3.6),
];

final _branchShine = [
  _Branch('M0-95C-26-120-51-142-82-189', 2.5, 0, 0.7),
  _Branch('M6-127C29-136 55-150 75-197', 2.2, 0, 0.7),
  _Branch('M-38-145Q-79-145-115-186', 1.8, 1, 1.6),
  _Branch('M37-150Q78-147 114-189', 1.8, 1, 1.6),
];

/// Back-to-front paint order; inner clusters appear first, the crown last.
const _crowns = [
  _Crown(-159, -211, .75, 1, 0, 2.3, 2.9),
  _Crown(157, -209, .78, 2, 1, 2.4, 3.0),
  _Crown(-108, -266, .80, 2, 1, 3.3, 3.9),
  _Crown(111, -262, .81, 0, 2, 3.4, 4.0),
  _Crown(5, -273, .98, 1, 2, 4.0, 4.8),
  _Crown(-115, -177, .73, 2, 0, 1.3, 1.8),
  _Crown(115, -181, .76, 0, 0, 1.4, 1.9),
  _Crown(64, -244, .94, 1, 1, 1.5, 2.0),
  _Crown(-69, -250, .91, 0, 2, 1.5, 2.0),
  _Crown(-85, -196, .86, 0, 0, 0.3, 0.8),
  _Crown(84, -192, .84, 1, 1, 0.4, 0.9),
  _Crown(-19, -248, .85, 2, 2, 0.5, 1.0),
  _Crown(-44, -174, .67, 1, 1, -2, -1),
  _Crown(45, -181, .65, 2, 0, -2, -1),
  _Crown(0, -224, .73, 0, 2, -2, -1),
];

final _leaf = _p('M0 0C-20-3-31-19-26-39C-6-36 8-21 0 0Z');
final _leafVein = _p('M0 0Q-11-14-21-31');
final _flower = _p('M0-2C-10-14-14-1-4 1C-15 7-5 15 1 5C7 16 15 5 5 1C15-5 4-14 0-2Z');

const _flowers = [
  _Flower(-140, -231, 0, 5.0, 5.4),
  _Flower(98, -261, 21, 5.1, 5.5),
  _Flower(45, -207, 42, 5.2, 5.6),
  _Flower(-62, -268, -18, 5.3, 5.7),
  _Flower(140, -212, 30, 5.4, 5.8),
  _Flower(-18, -312, 12, 5.5, 5.9),
  _Flower(-96, -198, -35, 5.6, 6.0),
];

final _motes = [
  _p('M130 254Q130 260 124 260Q130 260 130 266Q130 260 136 260Q130 260 130 254Z'),
  _p('M477 142Q477 150 469 150Q477 150 477 158Q477 150 485 150Q477 150 477 142Z'),
];

class _TreePainter extends CustomPainter {
  _TreePainter(this.growth);
  final double growth;

  double _phase(double from, double to) => ((growth - from) / (to - from)).clamp(0.0, 1.0);

  static double _pop(double p) => p >= 1 ? 1 : Curves.easeOutBack.transform(p);

  static Paint _stroke(Color color, double width, [double opacity = 1]) => Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..color = color.withValues(alpha: opacity);

  static ui.Gradient _wood(Rect r) => ui.Gradient.linear(r.topLeft, r.bottomRight, _woodColors, _woodStops);

  static Path _trim(Path path, double t) {
    if (t >= 1) return path;
    final out = Path();
    for (final m in path.computeMetrics()) {
      out.addPath(m.extractPath(0, m.length * t), Offset.zero);
    }
    return out;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final k = math.min(size.width / _viewBox.width, size.height / _viewBox.height);
    final t = (growth / fullTreeGrowth).clamp(0.0, 1.0);
    canvas
      ..save()
      ..translate((size.width - _viewBox.width * k) / 2, (size.height - _viewBox.height * k) / 2)
      ..scale(k)
      ..translate(-_viewBox.left, -_viewBox.top);
    _paintGround(canvas, 0.72 + 0.28 * t);
    _paintTree(canvas, 0.45 + 0.55 * Curves.easeOut.transform(t));
    _paintMotes(canvas, _phase(5.4, 6));
    canvas.restore();
  }

  void _paintGround(Canvas c, double s) {
    c
      ..save()
      ..translate(300, 400)
      ..scale(s, 1);
    c.drawOval(
      Rect.fromCenter(center: const Offset(0, 8), width: 314, height: 34),
      Paint()..color = const Color(0xFFB8AD8F).withValues(alpha: .09),
    );
    final soil = _soil.getBounds();
    c.drawPath(
      _soil,
      Paint()
        ..shader = ui.Gradient.linear(
          soil.topCenter,
          soil.bottomCenter,
          const [Color(0xFFEDE6D5), Color(0xFFDED6BD)],
        ),
    );
    c.drawPath(_soilShine, _stroke(const Color(0xFFFFFAF0), 3, .65));
    c.drawOval(
      Rect.fromCenter(center: const Offset(0, 1), width: 92, height: 16),
      Paint()..color = const Color(0xFF958C70).withValues(alpha: .12),
    );
    c.drawPath(_grass, _stroke(const Color(0xFF8D9C74), 2.6));
    c.restore();
  }

  void _paintTree(Canvas c, double s) {
    c
      ..save()
      ..translate(300, 397)
      ..scale(s);

    for (final b in _branches) {
      final p = _phase(b.from, b.to);
      if (p <= 0) continue;
      c.drawPath(_trim(b.path, p), _stroke(Colors.white, b.width)..shader = _wood(b.bounds));
    }
    for (final b in _branchShine) {
      final p = _phase(b.from, b.to);
      if (p <= 0) continue;
      c.drawPath(_trim(b.path, p), _stroke(const Color(0xFFE7B98B), b.width, .28));
    }

    c.drawPath(_trunk, Paint()..shader = _wood(_trunk.getBounds()));
    c.drawPath(_trunkShine, _stroke(const Color(0xFFECC297), 3, .45));
    c.drawPath(_trunkShade, _stroke(const Color(0xFF684C3D), 2.2, .22));
    c.drawPath(_roots, _stroke(Colors.white, 5)..shader = _wood(_roots.getBounds()));

    for (final crown in _crowns) {
      final p = _phase(crown.from, crown.to);
      if (p <= 0) continue;
      final bounds = _crownBounds[crown.shape];
      final colors = _foliagePalettes[crown.palette];
      c
        ..save()
        ..translate(crown.dx, crown.dy)
        ..scale(crown.scale * _pop(p));
      c.drawPath(
        _crownShapes[crown.shape],
        Paint()..shader = ui.Gradient.linear(bounds.topLeft, bounds.bottomRight, colors),
      );
      c.restore();
    }

    final leaves = _phase(4.5, 5.0);
    if (leaves > 0) {
      _paintLeaf(c, -103, -151, -53, .58 * _pop(leaves), const Color(0xFFA9C981), const Color(0xFF739C64));
      _paintLeaf(c, 104, -151, 122, .57 * _pop(leaves), const Color(0xFF689D70), const Color(0xFF426F54));
    }

    for (final f in _flowers) {
      final p = _phase(f.from, f.to);
      if (p <= 0) continue;
      c
        ..save()
        ..translate(f.dx, f.dy)
        ..rotate(f.rotation * math.pi / 180)
        ..scale(_pop(p));
      c.drawPath(_flower, Paint()..color = const Color(0xFFFAF3D5).withValues(alpha: .92));
      c.drawCircle(Offset.zero, 2.3, Paint()..color = const Color(0xFFD5AB60));
      c.restore();
    }

    c.restore();
  }

  void _paintLeaf(Canvas c, double dx, double dy, double degrees, double scale, Color fill, Color vein) {
    c
      ..save()
      ..translate(dx, dy)
      ..rotate(degrees * math.pi / 180)
      ..scale(scale);
    c.drawPath(_leaf, Paint()..color = fill);
    c.drawPath(_leafVein, _stroke(vein, 1.4, .6));
    c.restore();
  }

  void _paintMotes(Canvas c, double opacity) {
    if (opacity <= 0) return;
    final star = Paint()..color = const Color(0xFFC3AD6A).withValues(alpha: .5 * opacity);
    for (final m in _motes) {
      c.drawPath(m, star);
    }
    c.drawCircle(
      const Offset(465, 296),
      2.5,
      Paint()..color = const Color(0xFFC5B67D).withValues(alpha: .5 * opacity),
    );
  }

  @override
  bool shouldRepaint(_TreePainter old) => old.growth != growth;
}
