import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/app_theme.dart';

const _treeAsset = 'assets/images/network_tree.svg';
const _heroTag = 'network-tree';
const _treeAspect = 460 / 410;

/// Tappable tree illustration that expands into the growing philosophy.
class NetworkTreeBadge extends StatefulWidget {
  const NetworkTreeBadge({super.key, this.width = 148});
  final double width;

  @override
  State<NetworkTreeBadge> createState() => _NetworkTreeBadgeState();
}

class _NetworkTreeBadgeState extends State<NetworkTreeBadge> {
  bool _hover = false;

  void _open() => Navigator.of(context).push(_philosophyRoute());

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    final accent = context.cs.primary;
    final pad = widget.width * 0.06;
    return Tooltip(
      message: 'How we grow a network',
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: AnimatedScale(
          scale: _hover ? 1.04 : 1,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          alignment: Alignment.bottomRight,
          child: Material(
            color: oc.surface.withValues(alpha: 0.94),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: _hover ? accent.withValues(alpha: 0.45) : oc.border),
            ),
            elevation: _hover ? 6 : 2,
            shadowColor: Colors.black26,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: _open,
              child: Padding(
                padding: EdgeInsets.all(pad),
                child: SizedBox(
                  width: widget.width - pad * 2,
                  height: (widget.width - pad * 2) / _treeAspect,
                  child: const Hero(tag: _heroTag, child: _SwayingTree()),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SwayingTree extends StatefulWidget {
  const _SwayingTree();

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
    final tree = SvgPicture.asset(_treeAsset, fit: BoxFit.contain);
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

Route<void> _philosophyRoute() => PageRouteBuilder<void>(
      settings: const RouteSettings(name: 'tree-philosophy'),
      transitionDuration: const Duration(milliseconds: 520),
      reverseTransitionDuration: const Duration(milliseconds: 380),
      pageBuilder: (_, _, _) => const _PhilosophyPage(),
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
    Icons.grass_rounded,
    'Roots before branches',
    'Your strongest ties are the trunk everything else grows from. Invest in the few people who '
        'know you well before chasing the many who don\'t.',
  ),
  _Principle(
    Icons.account_tree_outlined,
    'Grow from what you have',
    'New branches sprout from existing ones. The best introductions come through people who '
        'already trust you, so ask for warm intros instead of sending cold messages.',
  ),
  _Principle(
    Icons.water_drop_outlined,
    'Nourish, don\'t harvest',
    'Give before you ask. Share an article, make an intro, check in with no agenda. '
        'A relationship that only gets used will wither.',
  ),
  _Principle(
    Icons.eco_outlined,
    'Tend it a little, often',
    'A short note every few weeks keeps a connection green. Fresh leaves on your tree mean you\'ve '
        'been in touch lately; autumn tones are a nudge to reach out.',
  ),
  _Principle(
    Icons.wb_twilight_rounded,
    'Every branch has seasons',
    'Some ties go quiet, and that\'s natural. A dormant branch can bloom again with one '
        'thoughtful message. Remembering the details is what makes that possible.',
  ),
];

class _PhilosophyPage extends StatelessWidget {
  const _PhilosophyPage();

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    final route = ModalRoute.of(context)!;
    final reveal = CurvedAnimation(
      parent: route.animation!,
      curve: const Interval(0.35, 1, curve: Curves.easeOutCubic),
      reverseCurve: const Interval(0, 0.5, curve: Curves.easeInCubic),
    );

    final tree = DecoratedBox(
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
      child: const Hero(tag: _heroTag, child: _SwayingTree()),
    );

    final text = AnimatedBuilder(
      animation: reveal,
      builder: (context, child) => Opacity(
        opacity: reveal.value,
        child: Transform.translate(offset: Offset((1 - reveal.value) * 32, 0), child: child),
      ),
      child: const _PhilosophyText(),
    );

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
                            padding: const EdgeInsets.fromLTRB(40, 56, 16, 40),
                            child: Center(child: AspectRatio(aspectRatio: _treeAspect, child: tree)),
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
                        SizedBox(width: treeWidth, height: treeWidth / _treeAspect, child: tree),
                        const SizedBox(height: 16),
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
        Text('Networks grow like trees.', style: context.tt.headlineMedium),
        const SizedBox(height: 10),
        Text(
          'A network isn\'t a stack of business cards. It\'s something living: it grows slowly, '
          'from the roots up, and it needs a little care to stay healthy.',
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
