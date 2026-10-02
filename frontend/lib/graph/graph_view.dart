import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../models/contact.dart';
import '../theme/app_theme.dart';
import 'graph_options.dart';
import 'graph_style.dart';

/// Imperative handle for camera moves from outside the graph.
class GraphViewController {
  _GraphViewState? _state;

  void fitToView() => _state?._fit(animate: true);
  void centerOn(String id) => _state?._centerOn(id);
  void zoomBy(double factor) => _state?._zoomAboutCenter(factor);
}

class GraphNode {
  GraphNode(this.id, this.contact, this.pos);

  final String id;
  Contact? contact;
  Offset pos;
  Offset vel = Offset.zero;
  double radius = 0;
  double targetRadius = 14;
  Color color = const Color(0xFF94A3B8);
  Color targetColor = const Color(0xFF94A3B8);
  double emphasis = 1;
  double targetEmphasis = 1;
  bool dragging = false;

  bool get isYou => contact == null;
}

class GraphEdge {
  GraphEdge(this.a, this.b, {required this.toYou});
  final GraphNode a;
  final GraphNode b;
  final bool toYou;
}

class _GraphModel extends ChangeNotifier {
  void repaint() => notifyListeners();
}

class GraphView extends StatefulWidget {
  const GraphView({
    super.key,
    required this.contacts,
    required this.colorBy,
    required this.sizeBy,
    required this.showPeerLinks,
    required this.focusId,
    required this.onFocusChanged,
    this.controller,
    this.fitPadding = const EdgeInsets.all(48),
  });

  final List<Contact> contacts;
  final ColorBy colorBy;
  final SizeBy sizeBy;
  final bool showPeerLinks;
  final String? focusId;
  final ValueChanged<String?> onFocusChanged;
  final GraphViewController? controller;
  final EdgeInsets fitPadding;

  @override
  State<GraphView> createState() => _GraphViewState();
}

class _GraphViewState extends State<GraphView> with SingleTickerProviderStateMixin {
  static const youId = '__you__';
  static const _youRadius = 24.0;

  final _model = _GraphModel();
  late final Ticker _ticker = createTicker(_onTick);
  final List<GraphNode> _nodes = [];
  final Map<String, GraphNode> _byId = {};
  List<GraphEdge> _edges = [];
  Set<String> _focusSet = {};

  double _alpha = 0;
  Duration _lastTick = Duration.zero;
  double _accum = 0;

  double _scale = 1;
  Offset _pan = Offset.zero;
  Size _size = Size.zero;

  _CameraTween? _camera;
  String? _hoverId;
  GraphNode? _dragNode;
  double _gestureStartScale = 1;
  Offset _gestureWorldAnchor = Offset.zero;
  Offset _downPos = Offset.zero;
  String _signature = '';

  @override
  void initState() {
    super.initState();
    widget.controller?._state = this;
    final you = GraphNode(youId, null, Offset.zero)
      ..targetRadius = _youRadius
      ..radius = 0;
    _nodes.add(you);
    _byId[youId] = you;
    _sync(initial: true);
  }

  @override
  void didUpdateWidget(GraphView old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller?._state = null;
      widget.controller?._state = this;
    }
    if (!identical(old.contacts, widget.contacts) ||
        old.colorBy != widget.colorBy ||
        old.sizeBy != widget.sizeBy ||
        old.showPeerLinks != widget.showPeerLinks ||
        old.focusId != widget.focusId) {
      _sync();
    }
  }

  @override
  void dispose() {
    if (widget.controller?._state == this) widget.controller?._state = null;
    _ticker.dispose();
    _model.dispose();
    super.dispose();
  }

  double _restLength(int strength) => 62 + (10 - strength) * 25 + _youRadius;

  Offset _seedPosition(Contact c) {
    var h = 0;
    for (final u in c.id.codeUnits) {
      h = (h * 131 + u) & 0x7fffffff;
    }
    final angle = (h % 3600) / 3600 * math.pi * 2;
    final intro = c.introducedById == null ? null : _byId[c.introducedById!];
    if (intro != null && !intro.isYou) {
      return intro.pos + Offset(math.cos(angle), math.sin(angle)) * 40;
    }
    return Offset(math.cos(angle), math.sin(angle)) * _restLength(c.strength);
  }

  void _sync({bool initial = false}) {
    final styler = GraphStyler(
      contacts: widget.contacts,
      colorBy: widget.colorBy,
      sizeBy: widget.sizeBy,
    );

    final ids = <String>{youId};
    for (final c in widget.contacts) {
      ids.add(c.id);
      final node = _byId[c.id];
      if (node == null) {
        final n = GraphNode(c.id, c, _seedPosition(c));
        _nodes.add(n);
        _byId[c.id] = n;
      } else {
        node.contact = c;
      }
    }
    _nodes.removeWhere((n) => !ids.contains(n.id));
    _byId.removeWhere((k, _) => !ids.contains(k));

    for (final n in _nodes) {
      final c = n.contact;
      if (c == null) continue;
      n.targetColor = styler.colorFor(c);
      n.targetRadius = styler.radiusFor(c);
      if (initial) n.color = n.targetColor;
    }

    final you = _byId[youId]!;
    _edges = [
      for (final n in _nodes)
        if (!n.isYou) GraphEdge(you, n, toYou: true),
      if (widget.showPeerLinks)
        for (final (a, b) in styler.edges) GraphEdge(_byId[a]!, _byId[b]!, toYou: false),
    ];

    final focus = widget.focusId;
    if (focus != null && _byId.containsKey(focus)) {
      _focusSet = {focus, youId};
      for (final (a, b) in styler.edges) {
        if (a == focus) _focusSet.add(b);
        if (b == focus) _focusSet.add(a);
      }
    } else {
      _focusSet = {};
    }
    for (final n in _nodes) {
      n.targetEmphasis = _focusSet.isEmpty || _focusSet.contains(n.id) ? 1 : 0.14;
    }

    final signature = [
      for (final n in _nodes) '${n.id}:${n.contact?.strength}:${n.targetRadius.round()}',
      for (final e in _edges) '${e.a.id}-${e.b.id}',
    ].join(',');
    if (signature != _signature) {
      _signature = signature;
      if (initial) {
        _alpha = 1;
        for (var i = 0; i < 320; i++) {
          _step();
        }
        _alpha = 0.08;
      } else {
        _alpha = math.max(_alpha, 0.4);
      }
    }
    _wake();
  }

  void _wake() {
    if (!_ticker.isActive) {
      _lastTick = Duration.zero;
      _ticker.start();
    }
  }

  void _step() {
    final n = _nodes.length;
    final fx = Float64List(n);
    final fy = Float64List(n);
    final index = <GraphNode, int>{for (var i = 0; i < n; i++) _nodes[i]: i};

    for (var i = 0; i < n; i++) {
      final a = _nodes[i];
      for (var j = i + 1; j < n; j++) {
        final b = _nodes[j];
        var dx = b.pos.dx - a.pos.dx;
        var dy = b.pos.dy - a.pos.dy;
        var d2 = dx * dx + dy * dy;
        if (d2 < 0.01) {
          dx = (i - j) * 0.37;
          dy = (j % 3 - 1) * 0.29 + 0.1;
          d2 = dx * dx + dy * dy;
        }
        final d = math.sqrt(d2);
        var f = 2400 / d2;
        final minD = a.targetRadius + b.targetRadius + 12;
        if (d < minD) f += (minD - d) * 0.6;
        final ux = dx / d * f;
        final uy = dy / d * f;
        fx[i] -= ux;
        fy[i] -= uy;
        fx[j] += ux;
        fy[j] += uy;
      }
    }

    for (final e in _edges) {
      final ia = index[e.a]!;
      final ib = index[e.b]!;
      final dx = e.b.pos.dx - e.a.pos.dx;
      final dy = e.b.pos.dy - e.a.pos.dy;
      final d = math.max(math.sqrt(dx * dx + dy * dy), 0.01);
      final double rest;
      final double k;
      if (e.toYou) {
        rest = _restLength(e.b.contact!.strength);
        k = 0.04;
      } else {
        rest = 120;
        k = 0.006;
      }
      final f = (d - rest) * k;
      final ux = dx / d * f;
      final uy = dy / d * f;
      fx[ia] += ux;
      fy[ia] += uy;
      fx[ib] -= ux;
      fy[ib] -= uy;
    }

    for (var i = 0; i < n; i++) {
      final node = _nodes[i];
      if (node.isYou) {
        node.pos = Offset.zero;
        node.vel = Offset.zero;
        continue;
      }
      if (node.dragging) {
        node.vel = Offset.zero;
        continue;
      }
      fx[i] -= node.pos.dx * 0.002;
      fy[i] -= node.pos.dy * 0.002;
      var v = (node.vel + Offset(fx[i], fy[i]) * _alpha) * 0.6;
      final speed = v.distance;
      if (speed > 30) v = v / speed * 30;
      node.vel = v;
      node.pos += v;
    }

    _alpha *= 0.985;
    if (_alpha < 0.004) _alpha = 0;
  }

  void _onTick(Duration elapsed) {
    final dt = _lastTick == Duration.zero ? 16.6 : (elapsed - _lastTick).inMicroseconds / 1000;
    _lastTick = elapsed;

    var active = false;

    if (_alpha > 0) {
      _accum += dt;
      var steps = 0;
      while (_accum >= 16.6 && steps < 3) {
        _step();
        _accum -= 16.6;
        steps++;
      }
      if (steps == 3) _accum = 0;
      active = true;
    }

    final t = 1 - math.pow(0.82, dt / 16.6).toDouble();
    for (final n in _nodes) {
      if ((n.radius - n.targetRadius).abs() > 0.05) {
        n.radius += (n.targetRadius - n.radius) * t;
        active = true;
      } else {
        n.radius = n.targetRadius;
      }
      if (n.color != n.targetColor) {
        final next = Color.lerp(n.color, n.targetColor, t)!;
        n.color = _closeColor(next, n.targetColor) ? n.targetColor : next;
        active = true;
      }
      if ((n.emphasis - n.targetEmphasis).abs() > 0.01) {
        n.emphasis += (n.targetEmphasis - n.emphasis) * t;
        active = true;
      } else {
        n.emphasis = n.targetEmphasis;
      }
    }

    final cam = _camera;
    if (cam != null) {
      cam.progress = (cam.progress + dt / cam.durationMs).clamp(0.0, 1.0);
      final e = Curves.easeInOutCubic.transform(cam.progress);
      _scale = ui.lerpDouble(cam.fromScale, cam.toScale, e)!;
      _pan = Offset.lerp(cam.fromPan, cam.toPan, e)!;
      if (cam.progress >= 1) _camera = null;
      active = true;
    }

    if (_dragNode != null) active = true;

    _model.repaint();
    if (!active) _ticker.stop();
  }

  bool _closeColor(Color a, Color b) =>
      (a.r - b.r).abs() < 0.004 && (a.g - b.g).abs() < 0.004 && (a.b - b.b).abs() < 0.004;

  Offset _toWorld(Offset screen) => (screen - _pan) / _scale;

  GraphNode? _hitTest(Offset screen) {
    final w = _toWorld(screen);
    GraphNode? best;
    var bestD = double.infinity;
    for (final n in _nodes) {
      final d = (n.pos - w).distance;
      final slop = math.max(n.radius, 10 / _scale) + 4 / _scale;
      if (d <= slop && d < bestD) {
        best = n;
        bestD = d;
      }
    }
    return best;
  }

  Rect _worldBounds() {
    var rect = Rect.fromCircle(center: Offset.zero, radius: _youRadius);
    for (final n in _nodes) {
      rect = rect.expandToInclude(Rect.fromCircle(center: n.pos, radius: n.targetRadius + 18));
    }
    return rect;
  }

  void _fit({bool animate = false}) {
    if (_size.isEmpty) return;
    final p = widget.fitPadding;
    final avail = Size(
      math.max(_size.width - p.horizontal, 100),
      math.max(_size.height - p.vertical, 100),
    );
    final b = _worldBounds();
    final scale = math.min(avail.width / b.width, avail.height / b.height).clamp(0.3, 1.5);
    final center = Offset(p.left + avail.width / 2, p.top + avail.height / 2);
    final pan = center - b.center * scale;
    _moveCamera(scale, pan, animate: animate);
  }

  void _centerOn(String id) {
    final n = _byId[id];
    if (n == null || _size.isEmpty) return;
    final scale = math.max(_scale, 1.1).clamp(0.3, 2.0);
    final p = widget.fitPadding;
    final center = Offset(
      p.left + (_size.width - p.horizontal) / 2,
      p.top + (_size.height - p.vertical) / 2,
    );
    _moveCamera(scale, center - n.pos * scale, animate: true);
  }

  void _zoomAboutCenter(double factor) {
    final focal = _size.center(Offset.zero);
    final next = (_scale * factor).clamp(0.25, 4.0);
    final world = _toWorld(focal);
    _moveCamera(next, focal - world * next, animate: true, durationMs: 260);
  }

  void _moveCamera(double scale, Offset pan, {required bool animate, double durationMs = 650}) {
    if (!animate) {
      _camera = null;
      _scale = scale;
      _pan = pan;
      _model.repaint();
      return;
    }
    _camera = _CameraTween(_scale, scale, _pan, pan, durationMs);
    _wake();
  }

  void _zoomAt(Offset focal, double factor) {
    _camera = null;
    final next = (_scale * factor).clamp(0.25, 4.0);
    final world = _toWorld(focal);
    _scale = next;
    _pan = focal - world * next;
    _model.repaint();
  }

  void _onScaleStart(ScaleStartDetails d) {
    _camera = null;
    _downPos = d.localFocalPoint;
    final hit = d.pointerCount <= 1 ? _hitTest(d.localFocalPoint) : null;
    if (hit != null && !hit.isYou) {
      _dragNode = hit..dragging = true;
      _wake();
    } else {
      _dragNode = null;
    }
    _gestureStartScale = _scale;
    _gestureWorldAnchor = _toWorld(d.localFocalPoint);
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    final drag = _dragNode;
    if (drag != null && d.pointerCount <= 1) {
      drag.pos = _toWorld(d.localFocalPoint);
      if ((d.localFocalPoint - _downPos).distance > 4) _alpha = math.max(_alpha, 0.25);
      _wake();
      return;
    }
    _scale = (_gestureStartScale * d.scale).clamp(0.25, 4.0);
    _pan = d.localFocalPoint - _gestureWorldAnchor * _scale;
    _model.repaint();
  }

  void _onScaleEnd(ScaleEndDetails d) {
    final drag = _dragNode;
    if (drag != null) {
      drag.dragging = false;
      _dragNode = null;
      _alpha = math.max(_alpha, 0.2);
      _wake();
    }
  }

  void _onTapUp(TapUpDetails d) {
    final hit = _hitTest(d.localPosition);
    if (hit == null || hit.isYou) {
      widget.onFocusChanged(null);
    } else {
      widget.onFocusChanged(hit.id == widget.focusId ? null : hit.id);
    }
  }

  void _onHover(PointerHoverEvent e) {
    final hit = _hitTest(e.localPosition)?.id;
    if (hit != _hoverId) {
      setState(() => _hoverId = hit);
      _model.repaint();
    }
  }

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        if (size != _size) {
          final previous = _size;
          _size = size;
          if (previous.isEmpty) {
            _fit();
          } else {
            _pan += size.center(Offset.zero) - previous.center(Offset.zero);
            final focus = widget.focusId;
            if (focus != null && focus != youId) _centerOn(focus);
          }
        }
        return Listener(
          onPointerSignal: (e) {
            if (e is PointerScrollEvent) {
              GestureBinding.instance.pointerSignalResolver.register(e, (event) {
                final s = event as PointerScrollEvent;
                _zoomAt(s.localPosition, math.exp(-s.scrollDelta.dy / 500));
              });
            }
          },
          child: MouseRegion(
            cursor: _hoverId != null && _hoverId != youId
                ? SystemMouseCursors.click
                : SystemMouseCursors.grab,
            onHover: _onHover,
            onExit: (_) {
              if (_hoverId != null) {
                setState(() => _hoverId = null);
                _model.repaint();
              }
            },
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onScaleStart: _onScaleStart,
              onScaleUpdate: _onScaleUpdate,
              onScaleEnd: _onScaleEnd,
              onTapUp: _onTapUp,
              child: RepaintBoundary(
                child: ClipRect(
                  child: CustomPaint(
                    size: size,
                    painter: _GraphPainter(
                      state: this,
                      repaint: _model,
                      oc: oc,
                      primary: context.cs.primary,
                      dark: context.isDark,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CameraTween {
  _CameraTween(this.fromScale, this.toScale, this.fromPan, this.toPan, this.durationMs);
  final double fromScale;
  final double toScale;
  final Offset fromPan;
  final Offset toPan;
  final double durationMs;
  double progress = 0;
}

class _GraphPainter extends CustomPainter {
  _GraphPainter({
    required this.state,
    required Listenable repaint,
    required this.oc,
    required this.primary,
    required this.dark,
  }) : super(repaint: repaint);

  final _GraphViewState state;
  final OrbitColors oc;
  final Color primary;
  final bool dark;

  static final Map<String, TextPainter> _textCache = {};

  TextPainter _text(String key, String text, TextStyle style) {
    final cacheKey = '$key|$text|${style.color?.toARGB32()}|${style.fontSize}';
    return _textCache.putIfAbsent(cacheKey, () {
      if (_textCache.length > 600) _textCache.clear();
      return TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: 160);
    });
  }

  @override
  void paint(Canvas canvas, Size size) {
    final scale = state._scale;
    final pan = state._pan;
    final nodes = state._nodes;
    final focusId = state.widget.focusId;
    final hoverId = state._hoverId;
    final focusing = state._focusSet.isNotEmpty;

    canvas.drawRect(Offset.zero & size, Paint()..color = oc.graphBackground);
    _paintGrid(canvas, size, scale, pan);

    canvas.save();
    canvas.translate(pan.dx, pan.dy);
    canvas.scale(scale);

    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1 / scale
      ..color = oc.border.withValues(alpha: dark ? 0.7 : 0.9);
    for (final s in [9, 6, 3]) {
      canvas.drawCircle(Offset.zero, state._restLength(s), ringPaint);
    }

    final edgePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (final e in state._edges) {
      if (e.toYou) continue;
      final em = math.min(e.a.emphasis, e.b.emphasis);
      final appear = _appear(e.a) * _appear(e.b);
      final highlighted = focusing && em > 0.5;
      edgePaint
        ..strokeWidth = (highlighted ? 2 : 1.2) / math.max(scale, 0.6)
        ..color = (highlighted ? primary : oc.muted)
            .withValues(alpha: (highlighted ? 0.7 : (dark ? 0.32 : 0.28)) * em * appear);
      _dashedLine(canvas, e.a.pos, e.b.pos, edgePaint, 5 / scale, 4 / scale);
    }
    for (final e in state._edges) {
      if (!e.toYou) continue;
      final c = e.b.contact!;
      final em = e.b.emphasis;
      final appear = _appear(e.b);
      final color = AppColors.strength(c.strength);
      final from = e.a.pos;
      final dir = e.b.pos - from;
      final len = dir.distance;
      if (len < 1) continue;
      final unit = dir / len;
      final start = from + unit * (e.a.radius + 2);
      final end = e.b.pos - unit * (e.b.radius + 1);
      edgePaint
        ..strokeWidth = 0.6 + c.strength * 0.38
        ..shader = ui.Gradient.linear(start, end, [
          color.withValues(alpha: (0.12 + c.strength * 0.025) * em * appear),
          color.withValues(alpha: (0.3 + c.strength * 0.05) * em * appear),
        ]);
      canvas.drawLine(start, end, edgePaint);
      edgePaint.shader = null;
    }

    final ordered = [...nodes]..sort((a, b) {
        int rank(GraphNode n) =>
            n.id == focusId ? 3 : (n.id == hoverId ? 2 : (n.emphasis > 0.5 ? 1 : 0));
        return rank(a).compareTo(rank(b));
      });

    for (final n in ordered) {
      _paintNode(canvas, n, scale, n.id == focusId, n.id == hoverId);
    }
    canvas.restore();

    for (final n in ordered) {
      if (n.isYou) continue;
      final related = focusing && state._focusSet.contains(n.id);
      final show = n.id == hoverId ||
          n.id == focusId ||
          related ||
          (!focusing && scale > 0.62 && n.radius * scale >= 11.5);
      if (!show || n.radius < 2) continue;
      final emphasized = n.id == hoverId || n.id == focusId;
      final tp = _text(
        'label',
        n.contact!.name,
        TextStyle(
          fontFamily: 'Inter',
          fontSize: emphasized ? 12.5 : 11.5,
          fontWeight: emphasized ? FontWeight.w700 : FontWeight.w600,
          color: oc.ink.withValues(alpha: 0.92),
        ),
      );
      final p = pan + (n.pos + Offset(0, n.radius + 4)) * scale;
      final rect = Rect.fromLTWH(p.dx - tp.width / 2 - 6, p.dy + 1, tp.width + 12, tp.height + 4);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(6)),
        Paint()..color = oc.graphBackground.withValues(alpha: 0.82),
      );
      tp.paint(canvas, Offset(p.dx - tp.width / 2, p.dy + 3));
    }
  }

  double _appear(GraphNode n) =>
      n.targetRadius <= 0 ? 0 : (n.radius / n.targetRadius).clamp(0.0, 1.0);

  void _paintGrid(Canvas canvas, Size size, double scale, Offset pan) {
    var spacing = 32 * scale;
    while (spacing < 18) {
      spacing *= 2;
    }
    final ox = pan.dx % spacing;
    final oy = pan.dy % spacing;
    final points = <Offset>[];
    for (var x = ox; x < size.width; x += spacing) {
      for (var y = oy; y < size.height; y += spacing) {
        points.add(Offset(x, y));
      }
    }
    canvas.drawPoints(
      ui.PointMode.points,
      points,
      Paint()
        ..color = oc.graphGrid
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round,
    );
  }

  void _dashedLine(Canvas canvas, Offset a, Offset b, Paint paint, double dash, double gap) {
    final total = (b - a).distance;
    if (total < 1) return;
    final dir = (b - a) / total;
    var t = 0.0;
    while (t < total) {
      final end = math.min(t + dash, total);
      canvas.drawLine(a + dir * t, a + dir * end, paint);
      t = end + gap;
    }
  }

  void _paintNode(Canvas canvas, GraphNode n, double scale, bool focused, bool hovered) {
    if (n.radius < 0.5) return;
    final r = n.radius * (hovered && !focused ? 1.08 : 1);
    final em = n.emphasis;

    if (n.isYou) {
      canvas.drawCircle(
        n.pos,
        r + 10,
        Paint()
          ..color = primary.withValues(alpha: 0.28)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
      );
      canvas.drawCircle(
        n.pos,
        r,
        Paint()
          ..shader = ui.Gradient.linear(
            n.pos - Offset(r, r),
            n.pos + Offset(r, r),
            const [Color(0xFF6D6DF7), Color(0xFFB146E0)],
          ),
      );
      canvas.drawCircle(
        n.pos,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = oc.graphBackground,
      );
      final tp = _text(
        'you',
        'You',
        const TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white),
      );
      tp.paint(canvas, n.pos - Offset(tp.width / 2, tp.height / 2));
      return;
    }

    final c = n.contact!;
    final color = n.color;

    if (c.strength >= 8 && em > 0.5) {
      canvas.drawCircle(
        n.pos,
        r + 4,
        Paint()
          ..color = color.withValues(alpha: (dark ? 0.45 : 0.3) * em)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.45 + 3),
      );
    }

    final faded = Color.lerp(oc.graphBackground, color, 0.15 + 0.85 * em)!;
    canvas.drawCircle(
      n.pos,
      r,
      Paint()
        ..shader = ui.Gradient.radial(
          n.pos - Offset(r * 0.35, r * 0.4),
          r * 1.4,
          [Color.lerp(faded, Colors.white, 0.18)!, faded],
        ),
    );
    canvas.drawCircle(
      n.pos,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = oc.graphBackground,
    );

    if (focused) {
      canvas.drawCircle(
        n.pos,
        r + 5,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..color = primary,
      );
    }

    if (r * scale >= 11 && em > 0.3) {
      final tp = _text(
        'init',
        c.initials,
        TextStyle(
          fontFamily: 'Inter',
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          letterSpacing: 0.2,
        ),
      );
      final s = (r / 15).clamp(0.75, 1.6);
      canvas.save();
      canvas.translate(n.pos.dx, n.pos.dy);
      canvas.scale(s);
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_GraphPainter old) =>
      old.oc != oc || old.primary != primary || old.dark != dark || old.state != state;
}
