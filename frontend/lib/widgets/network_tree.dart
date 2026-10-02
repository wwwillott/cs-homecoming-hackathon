import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'growing_tree.dart';

const _heroTag = 'network-tree';
const _alertColor = AppColors.amber;
const _onAlert = Color(0xFF2A1B00);

const _stageNames = [
  'Seedling',
  'Sapling',
  'Young tree',
  'Growing tree',
  'Leafy tree',
  'Mighty tree',
  'Full bloom',
];

String _stageName(int level) => _stageNames[math.min(level, _stageNames.length - 1)];

double _visualGrowth(int level) => math.min(level, fullTreeGrowth).toDouble();

void _openTree(BuildContext context) {
  final app = AppScope.read(context);
  Navigator.of(context).push(_treeRoute(
    from: app.shownTreeLevel,
    growTo: app.treeGrowthPending ? app.treeLevel : null,
  ));
}

/// Home screen card: the tree, current network size and the next growth goal.
class HomeTreeCard extends StatelessWidget {
  const HomeTreeCard({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final oc = context.oc;
    final pending = app.treeGrowthPending;
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: pending ? _alertColor.withValues(alpha: 0.6) : oc.border,
          width: pending ? 1.4 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 24, 20),
        child: LayoutBuilder(builder: (context, constraints) {
          final wide = constraints.maxWidth >= 520;
          final tree = _TreeButton(width: wide ? 250 : math.min(constraints.maxWidth - 16, 280));
          if (wide) {
            return Row(
              children: [
                tree,
                const SizedBox(width: 24),
                const Expanded(child: _TreeGoals()),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(child: tree),
              const SizedBox(height: 16),
              const _TreeGoals(),
            ],
          );
        }),
      ),
    );
  }
}

class _TreeButton extends StatelessWidget {
  const _TreeButton({required this.width});
  final double width;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final pending = app.treeGrowthPending;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Tooltip(
          message: pending ? 'Watch your tree grow' : 'How we grow a network',
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => _openTree(context),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0, -0.1),
                    radius: 0.62,
                    colors: [
                      context.cs.primary.withValues(alpha: context.isDark ? 0.14 : 0.1),
                      context.cs.primary.withValues(alpha: 0),
                    ],
                  ),
                ),
                child: SizedBox(
                  width: width,
                  height: width / growingTreeAspect,
                  child: Hero(
                    tag: _heroTag,
                    child: _SwayingTree(growth: _visualGrowth(app.shownTreeLevel)),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (pending)
          Positioned(
            top: 0,
            right: 0,
            child: Tooltip(
              message: 'Goal reached! Watch your tree grow',
              child: GrowthAlertDot(size: 34, onTap: () => _openTree(context)),
            ),
          ),
      ],
    );
  }
}

class _TreeGoals extends StatelessWidget {
  const _TreeGoals();

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final oc = context.oc;
    final accent = context.cs.primary;
    final pending = app.treeGrowthPending;
    final level = app.shownTreeLevel;
    final count = app.contacts.length;
    final next = app.nextTreeGoal;
    final n = app.connectionsToNextGrowth;
    final reached = app.previousTreeGoal;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('YOUR TREE', style: context.tt.labelSmall?.copyWith(color: accent, letterSpacing: 1.2)),
        const SizedBox(height: 4),
        Text('Level ${level + 1} · ${_stageName(level)}', style: context.tt.titleLarge),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(child: _Figure(value: count, label: 'Network size')),
            Expanded(child: _Figure(value: next, label: 'Next goal', color: accent)),
          ],
        ),
        const SizedBox(height: 16),
        const _GrowthBar(height: 8),
        const SizedBox(height: 6),
        Row(
          children: [
            Text('${app.previousTreeGoal}', style: context.tt.labelSmall),
            const Spacer(),
            Text('$next', style: context.tt.labelSmall),
          ],
        ),
        const SizedBox(height: 12),
        if (pending)
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: 'You reached $reached connections! ',
                  style: TextStyle(
                    color: context.isDark ? _alertColor : const Color(0xFF9A6B00),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const TextSpan(text: 'Tap the ! to watch your tree grow.'),
              ],
            ),
            style: context.tt.bodyMedium?.copyWith(color: oc.muted),
          )
        else
          Text(
            'Add $n more connection${n == 1 ? '' : 's'} to reach $next and grow your tree.',
            style: context.tt.bodyMedium?.copyWith(color: oc.muted),
          ),
      ],
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.value, required this.label, this.color});
  final int value;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: value.toDouble()),
          duration: const Duration(milliseconds: 900),
          curve: Curves.easeOutCubic,
          builder: (context, v, _) => Text(
            '${v.round()}',
            style: context.tt.headlineMedium?.copyWith(
              color: color,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        Text(label, style: context.tt.bodySmall?.copyWith(color: context.oc.muted)),
      ],
    );
  }
}

/// Pulsing "!" shown when the tree has a growth waiting to be watched.
class GrowthAlertDot extends StatefulWidget {
  const GrowthAlertDot({super.key, this.size = 24, this.onTap});
  final double size;
  final VoidCallback? onTap;

  @override
  State<GrowthAlertDot> createState() => _GrowthAlertDotState();
}

class _GrowthAlertDotState extends State<GrowthAlertDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    Widget dot = Container(
      width: s,
      height: s,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _alertColor,
        shape: BoxShape.circle,
        border: Border.all(color: context.oc.surface, width: 2),
        boxShadow: [BoxShadow(color: _alertColor.withValues(alpha: 0.55), blurRadius: 12)],
      ),
      child: Text(
        '!',
        style: TextStyle(color: _onAlert, fontWeight: FontWeight.w800, fontSize: s * 0.56, height: 1),
      ),
    );
    if (!MediaQuery.disableAnimationsOf(context)) {
      dot = ScaleTransition(
        scale: Tween(begin: 0.9, end: 1.12).animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut)),
        child: dot,
      );
    }
    if (widget.onTap == null) return dot;
    return Semantics(
      button: true,
      label: 'Watch your tree grow',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(onTap: widget.onTap, child: ExcludeSemantics(child: dot)),
      ),
    );
  }
}

class _GrowthBar extends StatelessWidget {
  const _GrowthBar({this.height = 4});
  final double height;

  @override
  Widget build(BuildContext context) {
    final progress = AppScope.of(context).treeGoalProgress;
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: progress),
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOutCubic,
        builder: (context, v, _) => LinearProgressIndicator(
          value: v,
          minHeight: height,
          color: context.cs.primary,
          backgroundColor: context.oc.surfaceHigh,
        ),
      ),
    );
  }
}

class _SwayingTree extends StatefulWidget {
  const _SwayingTree({required this.growth});
  final double growth;

  @override
  State<_SwayingTree> createState() => _SwayingTreeState();
}

class _SwayingTreeState extends State<_SwayingTree> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tree = GrowingTree(growth: widget.growth);
    if (MediaQuery.disableAnimationsOf(context)) return tree;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) => Transform.rotate(
        angle: (Curves.easeInOut.transform(_c.value) - 0.5) * 0.018,
        alignment: const Alignment(0, 0.6),
        child: child,
      ),
      child: tree,
    );
  }
}

Route<void> _treeRoute({required int from, int? growTo}) => PageRouteBuilder<void>(
      settings: const RouteSettings(name: 'tree'),
      transitionDuration: const Duration(milliseconds: 520),
      reverseTransitionDuration: const Duration(milliseconds: 380),
      pageBuilder: (_, _, _) => _TreePage(from: from, growTo: growTo),
      transitionsBuilder: (_, animation, _, child) => FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: const Interval(0, 0.6, curve: Curves.easeOut)),
        child: child,
      ),
    );

class _Principle {
  const _Principle(this.icon, this.title, this.body);
  final IconData icon;
  final String title;
  final String body;
}

const _principles = [
  _Principle(
    Icons.water_drop_outlined,
    'Focus on nurturing',
    'Many people feel dirty when they make networking instrumental. Instead, build your network by '
        'focusing on service, opening your tree with a water pail rather than a bucket for apples.',
  ),
  _Principle(
    Icons.alt_route_rounded,
    'Weak ties are bridges',
    'Studies show that weak ties — people you know but don\'t stay active with — are the ones who '
        'can bridge you to new experiences. Weak ties are the ones we\'re most likely to forget about, '
        'which is where Spruce comes in.',
  ),
  _Principle(
    Icons.handshake_outlined,
    'Referrals make you an asset',
    'As online application pools have grown to oceans, even hiring managers prefer strong referrals. '
        'Knowing someone who needs to fill a vacant position makes you an asset, not an annoyance.',
  ),
  _Principle(
    Icons.autorenew_rounded,
    'Reconnect with old friends',
    'Reconnecting with once strong ties leads to both novelty and trust, a combination of their new '
        'social setting and your old friendship. Spruce puts reconnecting back on your mind when the '
        'pressures of life turn us inward.',
  ),
];

enum _GrowPhase { idle, waiting, growing, grown }

class _TreePage extends StatefulWidget {
  const _TreePage({required this.from, this.growTo});
  final int from;
  final int? growTo;

  @override
  State<_TreePage> createState() => _TreePageState();
}

class _TreePageState extends State<_TreePage> with SingleTickerProviderStateMixin {
  late final AnimationController _growth = AnimationController(
    vsync: this,
    upperBound: fullTreeGrowth.toDouble(),
    value: _visualGrowth(widget.from),
  );
  late _GrowPhase _phase = widget.growTo == null ? _GrowPhase.idle : _GrowPhase.waiting;

  @override
  void initState() {
    super.initState();
    if (widget.growTo != null) {
      Future.delayed(const Duration(milliseconds: 700), _grow);
    }
  }

  Future<void> _grow() async {
    if (!mounted) return;
    final to = _visualGrowth(widget.growTo!);
    AppScope.read(context).markTreeGrown();
    setState(() => _phase = _GrowPhase.growing);
    final levels = (to - _growth.value).round();
    if (levels > 0) {
      await _growth.animateTo(
        to,
        duration: Duration(milliseconds: 1800 + 700 * (levels - 1).clamp(0, 5)),
        curve: Curves.easeInOutCubic,
      );
    } else {
      await Future<void>.delayed(const Duration(milliseconds: 600));
    }
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    setState(() => _phase = _GrowPhase.grown);
  }

  @override
  void dispose() {
    _growth.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    final route = ModalRoute.of(context)!;
    final reveal = CurvedAnimation(
      parent: route.animation!,
      curve: const Interval(0.35, 1, curve: Curves.easeOutCubic),
      reverseCurve: const Interval(0, 0.5, curve: Curves.easeInCubic),
    );

    final tree = Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0, -0.1),
              radius: 0.62,
              colors: [
                context.cs.primary.withValues(alpha: context.isDark ? 0.16 : 0.12),
                context.cs.primary.withValues(alpha: 0),
              ],
            ),
          ),
          child: Hero(
            tag: _heroTag,
            child: AnimatedBuilder(
              animation: _growth,
              builder: (context, _) => _SwayingTree(growth: _growth.value),
            ),
          ),
        ),
        Positioned.fill(child: _Sparkles(play: _phase == _GrowPhase.grown)),
      ],
    );

    Widget fadeIn(Widget child) => AnimatedBuilder(
          animation: reveal,
          builder: (context, child) => Opacity(
            opacity: reveal.value,
            child: Transform.translate(offset: Offset((1 - reveal.value) * 32, 0), child: child),
          ),
          child: child,
        );

    final level = widget.growTo ?? AppScope.of(context).shownTreeLevel;
    final status = fadeIn(_TreeStatus(phase: _phase, level: level));
    final text = fadeIn(const _PhilosophyText());

    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(context).maybePop()},
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: oc.background,
          body: SafeArea(
            child: Stack(
              children: [
                LayoutBuilder(builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 860;
                  if (wide) {
                    return Row(
                      children: [
                        Expanded(
                          flex: 5,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(40, 56, 16, 32),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Flexible(child: AspectRatio(aspectRatio: growingTreeAspect, child: tree)),
                                const SizedBox(height: 20),
                                status,
                              ],
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 6,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.fromLTRB(24, 56, 48, 40),
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 560),
                                child: text,
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  }
                  final treeWidth = math.min(constraints.maxWidth - 48, 420.0);
                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 56, 24, 32),
                    child: Column(
                      children: [
                        SizedBox(width: treeWidth, height: treeWidth / growingTreeAspect, child: tree),
                        const SizedBox(height: 16),
                        status,
                        const SizedBox(height: 32),
                        text,
                      ],
                    ),
                  );
                }),
                Positioned(
                  top: 8,
                  left: 8,
                  child: IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: Icon(Icons.close_rounded, color: oc.muted),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TreeStatus extends StatelessWidget {
  const _TreeStatus({required this.phase, required this.level});
  final _GrowPhase phase;
  final int level;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final oc = context.oc;
    final accent = context.cs.primary;
    final count = app.contacts.length;
    final next = app.nextTreeGoal;
    final n = app.connectionsToNextGrowth;
    final growing = phase == _GrowPhase.waiting || phase == _GrowPhase.growing;

    final Widget headline = switch (phase) {
      _GrowPhase.waiting || _GrowPhase.growing => Text(
          'Your tree is growing…',
          key: const ValueKey('growing'),
          style: context.tt.titleLarge?.copyWith(color: accent),
        ),
      _GrowPhase.grown => Row(
          key: const ValueKey('grown'),
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.celebration_rounded, color: _alertColor, size: 24),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'Your tree grew to level ${level + 1}!',
                style: context.tt.titleLarge,
              ),
            ),
          ],
        ),
      _GrowPhase.idle => Text(
          'Level ${level + 1} · ${_stageName(level)}',
          key: const ValueKey('idle'),
          style: context.tt.titleLarge,
        ),
    };

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 380),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            transitionBuilder: (child, a) => FadeTransition(
              opacity: a,
              child: ScaleTransition(scale: Tween(begin: 0.9, end: 1.0).animate(a), child: child),
            ),
            child: headline,
          ),
          const SizedBox(height: 6),
          Text(
            growing && level > 0
                ? 'You reached ${AppState.treeGoal(level - 1)} connections.'
                : '${_stageName(level)} · Network size $count · Next goal $next',
            style: context.tt.bodySmall?.copyWith(color: oc.muted),
          ),
          const SizedBox(height: 14),
          AnimatedOpacity(
            opacity: growing ? 0 : 1,
            duration: const Duration(milliseconds: 300),
            child: Column(
              children: [
                const _GrowthBar(height: 6),
                const SizedBox(height: 10),
                Text(
                  'Add $n more connection${n == 1 ? '' : 's'} to reach your next goal of $next.',
                  textAlign: TextAlign.center,
                  style: context.tt.bodyMedium?.copyWith(color: oc.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Sparkles extends StatefulWidget {
  const _Sparkles({required this.play});
  final bool play;

  @override
  State<_Sparkles> createState() => _SparklesState();
}

class _SparklesState extends State<_Sparkles> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1300));

  @override
  void didUpdateWidget(_Sparkles old) {
    super.didUpdateWidget(old);
    if (widget.play && !old.play) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(child: CustomPaint(painter: _SparklePainter(_c)));
  }
}

class _SparklePainter extends CustomPainter {
  _SparklePainter(this.animation) : super(repaint: animation);
  final Animation<double> animation;

  static const _colors = [AppColors.amber, AppColors.freshLeaf, Color(0xFFFAF3D5)];

  @override
  void paint(Canvas canvas, Size size) {
    final t = animation.value;
    if (t <= 0 || t >= 1) return;
    final travel = Curves.easeOutCubic.transform(t);
    final center = size.center(Offset(0, -size.height * 0.12));
    const count = 22;
    for (var i = 0; i < count; i++) {
      final angle = i / count * math.pi * 2 + (i.isEven ? 0.12 : -0.08);
      final reach = size.shortestSide * (0.2 + 0.32 * travel) * (0.75 + 0.5 * ((i * 37) % 10) / 10);
      final pos = center + Offset(math.cos(angle), math.sin(angle)) * reach;
      final radius = (i % 3 == 0 ? 4.5 : 2.8) * (1 - t * 0.5);
      canvas.drawCircle(pos, radius, Paint()..color = _colors[i % 3].withValues(alpha: 1 - t));
    }
  }

  @override
  bool shouldRepaint(_SparklePainter old) => false;
}

class _PhilosophyText extends StatelessWidget {
  const _PhilosophyText();

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    final accent = context.cs.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'OUR PHILOSOPHY',
          style: context.tt.labelSmall?.copyWith(color: accent, letterSpacing: 1.4),
        ),
        const SizedBox(height: 8),
        Text('Your network should be your own.', style: context.tt.headlineMedium),
        const SizedBox(height: 10),
        Text(
          'Spruce helps you track your network and points you towards resources without systematizing '
          'your friendships. Backed by decades of social network research, we designed this app to be an '
          'organizational tool, not an automated agent. Spruce organizes your tree. You nurture it.',
          style: context.tt.bodyLarge?.copyWith(color: oc.muted, height: 1.5),
        ),
        const SizedBox(height: 28),
        for (final p in _principles)
          Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: context.isDark ? 0.18 : 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(p.icon, size: 21, color: accent),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.title, style: context.tt.titleMedium),
                      const SizedBox(height: 4),
                      Text(p.body, style: context.tt.bodyMedium?.copyWith(color: oc.muted)),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
