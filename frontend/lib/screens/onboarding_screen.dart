import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/user_mode.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  UserMode _mode = UserMode.seeker;
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _start({required bool demoData}) async {
    final app = AppScope.read(context);
    await app.completeOnboarding(mode: _mode, withDemoData: demoData, name: _name.text);
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 920;
    final form = _Form(
      mode: _mode,
      name: _name,
      onMode: (m) => setState(() => _mode = m),
      onSample: () => _start(demoData: true),
      onFresh: () => _start(demoData: false),
    );

    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            const Expanded(flex: 11, child: _Hero(large: true)),
            Expanded(
              flex: 9,
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(48),
                  child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 440), child: form),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 360, child: _Hero(large: false)),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 26, 22, 32),
              child: SafeArea(top: false, child: form),
            ),
          ],
        ),
      ),
    );
  }
}

class _Hero extends StatefulWidget {
  const _Hero({required this.large});
  final bool large;

  @override
  State<_Hero> createState() => _HeroState();
}

class _HeroState extends State<_Hero> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 60),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0B0E1A), Color(0xFF15123A), Color(0xFF2A1243)],
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(painter: _OrbitArtPainter(_c)),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: EdgeInsets.all(widget.large ? 48 : 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const OrbitLogo(size: 36),
                      const SizedBox(width: 12),
                      Text(
                        'Orbit',
                        style: context.tt.titleLarge?.copyWith(color: Colors.white),
                      ),
                    ],
                  ),
                  const Spacer(),
                  FadeSlideIn(
                    child: Text(
                      'Every connection,\nin one orbit.',
                      style: (widget.large ? context.tt.displaySmall : context.tt.headlineMedium)
                          ?.copyWith(color: Colors.white, height: 1.1),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FadeSlideIn(
                    index: 2,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: Text(
                        'Remember who you met, where you met them, and how strong the connection is. Then see your whole network at a glance.',
                        style: context.tt.bodyMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.72),
                          fontSize: widget.large ? 16 : 14,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OrbitArtPainter extends CustomPainter {
  _OrbitArtPainter(this.animation) : super(repaint: animation);
  final Animation<double> animation;

  static final _dots = List.generate(18, (i) {
    final rnd = math.Random(i * 7919 + 3);
    return (
      ring: i % 3,
      phase: rnd.nextDouble() * math.pi * 2,
      speed: 0.6 + rnd.nextDouble() * 0.8,
      strength: 2 + rnd.nextInt(9),
      size: 4.0 + rnd.nextDouble() * 6,
    );
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * 0.68, size.height * 0.4);
    final base = math.min(size.width, size.height) * 0.16;
    final t = animation.value * math.pi * 2;

    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: 0.08);
    for (var r = 0; r < 3; r++) {
      canvas.drawCircle(center, base * (1 + r * 0.75), ringPaint);
    }

    final positions = <Offset>[];
    for (final d in _dots) {
      final radius = base * (1 + d.ring * 0.75);
      final angle = d.phase + t * d.speed * (d.ring.isEven ? 1 : -1);
      positions.add(center + Offset(math.cos(angle), math.sin(angle) * 0.92) * radius);
    }

    for (var i = 0; i < _dots.length; i++) {
      final d = _dots[i];
      final color = AppColors.strength(d.strength);
      canvas.drawLine(
        center,
        positions[i],
        Paint()
          ..strokeWidth = 0.5 + d.strength * 0.18
          ..color = color.withValues(alpha: 0.1 + d.strength * 0.02),
      );
    }

    for (var i = 0; i < _dots.length; i++) {
      final d = _dots[i];
      final color = AppColors.strength(d.strength);
      if (d.strength >= 8) {
        canvas.drawCircle(
          positions[i],
          d.size + 6,
          Paint()
            ..color = color.withValues(alpha: 0.35)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
        );
      }
      canvas.drawCircle(positions[i], d.size, Paint()..color = color);
    }

    canvas.drawCircle(
      center,
      base * 0.42,
      Paint()
        ..color = const Color(0xFF7C6CF7).withValues(alpha: 0.5)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 26),
    );
    canvas.drawCircle(
      center,
      base * 0.3,
      Paint()
        ..shader = const LinearGradient(colors: [Color(0xFF6D6DF7), Color(0xFFB146E0)])
            .createShader(Rect.fromCircle(center: center, radius: base * 0.3)),
    );
  }

  @override
  bool shouldRepaint(_OrbitArtPainter old) => false;
}

class _Form extends StatelessWidget {
  const _Form({
    required this.mode,
    required this.name,
    required this.onMode,
    required this.onSample,
    required this.onFresh,
  });

  final UserMode mode;
  final TextEditingController name;
  final ValueChanged<UserMode> onMode;
  final VoidCallback onSample;
  final VoidCallback onFresh;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Let\'s get you set up', style: context.tt.headlineSmall),
        const SizedBox(height: 6),
        Text('You can change any of this later in Settings.', style: context.tt.bodySmall),
        const SizedBox(height: 26),
        Text('How will you use Orbit?', style: context.tt.labelMedium),
        const SizedBox(height: 10),
        for (final m in UserMode.values) ...[
          _ModeCard(mode: m, selected: m == mode, onTap: () => onMode(m)),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 10),
        TextField(
          controller: name,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Your first name (optional)',
            prefixIcon: Icon(Icons.person_outline_rounded),
          ),
        ),
        const SizedBox(height: 26),
        FilledButton.icon(
          onPressed: onSample,
          icon: const Icon(Icons.hub_outlined, size: 20),
          label: const Text('Explore the sample network'),
        ),
        const SizedBox(height: 4),
        TextButton(onPressed: onFresh, child: const Text('Start with an empty network')),
      ],
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({required this.mode, required this.selected, required this.onTap});
  final UserMode mode;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final primary = context.cs.primary;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: selected ? primary.withValues(alpha: context.isDark ? 0.16 : 0.06) : context.oc.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: selected ? primary : context.oc.border, width: selected ? 1.6 : 1),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: (selected ? primary : context.oc.muted).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    mode == UserMode.seeker ? Icons.travel_explore_rounded : Icons.badge_outlined,
                    color: selected ? primary : context.oc.muted,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(mode.label, style: context.tt.titleSmall),
                      const SizedBox(height: 2),
                      Text(mode.description, style: context.tt.bodySmall),
                    ],
                  ),
                ),
                AnimatedScale(
                  scale: selected ? 1 : 0,
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutBack,
                  child: Icon(Icons.check_circle_rounded, color: primary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
