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
            const _Hero(large: false),
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

class _Hero extends StatelessWidget {
  const _Hero({required this.large});
  final bool large;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF070D09), Color(0xFF0E2215), Color(0xFF173A22)],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: large ? const EdgeInsets.all(48) : const EdgeInsets.fromLTRB(24, 20, 24, 36),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: large ? MainAxisAlignment.center : MainAxisAlignment.start,
            children: [
              Row(
                children: [
                  const OrbitLogo(size: 32),
                  const SizedBox(width: 10),
                  Text('Spruce', style: context.tt.titleMedium?.copyWith(color: Colors.white)),
                ],
              ),
              SizedBox(height: large ? 40 : 28),
              FadeSlideIn(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Know who you\nknow.',
                    style: context.tt.displayLarge?.copyWith(
                      color: Colors.white,
                      fontSize: large ? 76 : 50,
                      fontWeight: FontWeight.w800,
                      height: 1.02,
                      letterSpacing: -1.5,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
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
        Text('How will you use Spruce?', style: context.tt.labelMedium),
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
