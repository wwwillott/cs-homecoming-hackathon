import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../navigation.dart';
import '../services/recap_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';

final _captureTheme = AppTheme.dark();

enum _Phase { idle, recording, processing, error }

class CaptureScreen extends StatefulWidget {
  const CaptureScreen({super.key});

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> with TickerProviderStateMixin {
  _Phase _phase = _Phase.idle;
  RecapKind _kind = RecapKind.recap;
  late final Ticker _ticker = createTicker(_onTick);
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );
  final _levels = ValueNotifier<List<double>>(List.filled(48, 0.05));
  final _transcriptScroll = ScrollController();
  final _rnd = math.Random();
  final List<Timer> _timers = [];

  Duration _elapsed = Duration.zero;
  int _wordsShown = 0;
  int _processingStep = 0;
  String? _error;

  static final _words = MockRecapService.demoTranscript.split(' ');
  static const _steps = [
    'Uploading audio',
    'Transcribing',
    'Finding people, companies, and details',
    'Drafting a profile',
  ];

  @override
  void dispose() {
    for (final t in _timers) {
      t.cancel();
    }
    _ticker.dispose();
    _pulse.dispose();
    _levels.dispose();
    _transcriptScroll.dispose();
    super.dispose();
  }

  void _start() {
    if (!mounted || _phase == _Phase.recording) return;
    setState(() {
      _phase = _Phase.recording;
      _elapsed = Duration.zero;
      _wordsShown = 0;
      _error = null;
    });
    _pulse.repeat();
    if (_ticker.isActive) _ticker.stop();
    _ticker.start();
  }

  void _onTick(Duration elapsed) {
    final secs = elapsed.inMilliseconds / 1000;

    const wordsPerSec = 3.2;
    final words = math.min(_words.length, (secs * wordsPerSec).floor());
    final talking = words < _words.length;

    final prev = _levels.value;
    final next = List<double>.generate(prev.length, (i) {
      if (i < prev.length - 1) return prev[i + 1];
      if (!talking) return 0.05 + _rnd.nextDouble() * 0.05;
      final base = 0.35 + 0.3 * math.sin(secs * 7.3) * math.sin(secs * 2.1 + 1);
      return (base + _rnd.nextDouble() * 0.45).clamp(0.08, 1.0);
    });
    _levels.value = next;

    if (elapsed.inSeconds != _elapsed.inSeconds || words != _wordsShown) {
      setState(() {
        _elapsed = elapsed;
        _wordsShown = words;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_transcriptScroll.hasClients) {
          _transcriptScroll.jumpTo(_transcriptScroll.position.maxScrollExtent);
        }
      });
    }

  }

  Future<void> _stop() async {
    if (_phase != _Phase.recording) return;
    _ticker.stop();
    _pulse.stop();
    setState(() {
      _phase = _Phase.processing;
      _processingStep = 0;
    });
    for (var i = 1; i < _steps.length; i++) {
      _timers.add(Timer(Duration(milliseconds: 650 * i), () {
        if (mounted && _phase == _Phase.processing) setState(() => _processingStep = i);
      }));
    }
    try {
      final app = AppScope.read(context);
      final nav = Navigator.of(context);
      final draft = await app.recapService.summarize(
        audio: Uint8List(0),
        mimeType: 'audio/webm',
        kind: _kind,
      );
      if (!mounted) return;
      setState(() => _processingStep = _steps.length);
      await Future<void>.delayed(const Duration(milliseconds: 450));
      if (!mounted) return;
      nav.pushReplacement(draftRoute(draft));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _error = 'We couldn\'t summarize that recording. Check your connection and try again.';
      });
    }
  }

  String get _clock {
    final m = _elapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = _elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: _captureTheme,
      child: Builder(builder: (context) {
        return Scaffold(
          backgroundColor: const Color(0xFF080C09),
          body: Container(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0, -0.2),
                radius: 1.2,
                colors: [Color(0xFF173F24), Color(0xFF0C1910), Color(0xFF080C09)],
              ),
            ),
            child: SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 620),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            IconButton(
                              tooltip: 'Close',
                              onPressed: () => Navigator.of(context).maybePop(),
                              icon: const Icon(Icons.close_rounded, color: Colors.white),
                            ),
                            const SizedBox(width: 4),
                            Text('Voice recap', style: context.tt.titleLarge?.copyWith(color: Colors.white)),
                          ],
                        ),
                        const SizedBox(height: 16),
                        AnimatedOpacity(
                          opacity: _phase == _Phase.idle ? 1 : 0.4,
                          duration: const Duration(milliseconds: 250),
                          child: IgnorePointer(
                            ignoring: _phase != _Phase.idle,
                            child: Column(
                              children: [
                                SegmentedButton<RecapKind>(
                                  segments: const [
                                    ButtonSegment(
                                      value: RecapKind.recap,
                                      label: Text('My recap'),
                                      icon: Icon(Icons.record_voice_over_outlined),
                                    ),
                                    ButtonSegment(
                                      value: RecapKind.conversation,
                                      label: Text('Conversation'),
                                      icon: Icon(Icons.groups_2_outlined),
                                    ),
                                  ],
                                  selected: {_kind},
                                  onSelectionChanged: (s) => setState(() => _kind = s.first),
                                ),
                                const SizedBox(height: 8),
                                Text(_kind.description, style: context.tt.bodySmall),
                              ],
                            ),
                          ),
                        ),
                        Expanded(
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 350),
                            switchInCurve: Curves.easeOutCubic,
                            child: _phase == _Phase.processing
                                ? _Processing(key: const ValueKey('p'), step: _processingStep, steps: _steps)
                                : _RecorderBody(
                                    key: const ValueKey('r'),
                                    phase: _phase,
                                    clock: _clock,
                                    levels: _levels,
                                    pulse: _pulse,
                                    error: _error,
                                    onTap: _phase == _Phase.recording ? _stop : _start,
                                  ),
                          ),
                        ),
                        AnimatedSize(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOutCubic,
                          child: _phase == _Phase.recording && _wordsShown > 0
                              ? _TranscriptPreview(
                                  text: _words.take(_wordsShown).join(' '),
                                  controller: _transcriptScroll,
                                )
                              : _phase == _Phase.idle
                                  ? const _Tips()
                                  : const SizedBox(width: double.infinity),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _RecorderBody extends StatelessWidget {
  const _RecorderBody({
    super.key,
    required this.phase,
    required this.clock,
    required this.levels,
    required this.pulse,
    required this.onTap,
    this.error,
  });

  final _Phase phase;
  final String clock;
  final ValueNotifier<List<double>> levels;
  final Animation<double> pulse;
  final VoidCallback onTap;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final recording = phase == _Phase.recording;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        AnimatedOpacity(
          opacity: recording ? 1 : 0.35,
          duration: const Duration(milliseconds: 300),
          child: SizedBox(
            height: 70,
            width: double.infinity,
            child: RepaintBoundary(
              child: CustomPaint(painter: _WavePainter(levels, recording)),
            ),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          recording ? clock : '00:00',
          style: context.tt.headlineMedium?.copyWith(
            color: Colors.white,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 28),
        _MicButton(recording: recording, pulse: pulse, onTap: onTap),
        const SizedBox(height: 22),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: Text(
            error ?? (recording ? 'Tap to finish' : 'Tap to start recording'),
            key: ValueKey('${error != null}$recording'),
            textAlign: TextAlign.center,
            style: context.tt.bodyMedium?.copyWith(
              color: error != null ? AppColors.rose : Colors.white.withValues(alpha: 0.7),
            ),
          ),
        ),
      ],
    );
  }
}

class _MicButton extends StatelessWidget {
  const _MicButton({required this.recording, required this.pulse, required this.onTap});
  final bool recording;
  final Animation<double> pulse;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const size = 112.0;
    return SizedBox(
      width: size * 2,
      height: size * 2,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (recording)
            AnimatedBuilder(
              animation: pulse,
              builder: (context, _) => CustomPaint(
                size: const Size(size * 2, size * 2),
                painter: _PulsePainter(pulse.value),
              ),
            ),
          GestureDetector(
            onTap: onTap,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: recording
                        ? const [Color(0xFFFB7185), Color(0xFFE11D48)]
                        : const [AppColors.freshLeaf, AppColors.spruce],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: (recording ? AppColors.rose : AppColors.freshLeaf).withValues(alpha: 0.4),
                      blurRadius: 40,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  transitionBuilder: (child, a) => ScaleTransition(scale: a, child: child),
                  child: Icon(
                    recording ? Icons.stop_rounded : Icons.mic_rounded,
                    key: ValueKey(recording),
                    color: Colors.white,
                    size: 46,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PulsePainter extends CustomPainter {
  _PulsePainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    for (var i = 0; i < 3; i++) {
      final p = (t + i / 3) % 1;
      final r = 56 + p * 56;
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = AppColors.rose.withValues(alpha: (1 - p) * 0.5),
      );
    }
  }

  @override
  bool shouldRepaint(_PulsePainter old) => old.t != t;
}

class _WavePainter extends CustomPainter {
  _WavePainter(this.levels, this.active) : super(repaint: levels);
  final ValueNotifier<List<double>> levels;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    final values = levels.value;
    final n = values.length;
    final gap = 4.0;
    final barW = (size.width - gap * (n - 1)) / n;
    final mid = size.height / 2;
    for (var i = 0; i < n; i++) {
      final h = math.max(4.0, values[i] * size.height);
      final x = i * (barW + gap);
      final t = i / (n - 1);
      final color = Color.lerp(AppColors.spruce, AppColors.freshLeaf, t)!;
      final fade = math.min(1.0, math.min(t, 1 - t) * 6);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(x + barW / 2, mid), width: barW, height: h),
          Radius.circular(barW),
        ),
        Paint()..color = color.withValues(alpha: (active ? 0.95 : 0.6) * (0.25 + 0.75 * fade)),
      );
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) => old.active != active;
}

class _TranscriptPreview extends StatelessWidget {
  const _TranscriptPreview({required this.text, required this.controller});
  final String text;
  final ScrollController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 150),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(color: AppColors.rose, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text('Live preview', style: context.tt.labelSmall?.copyWith(color: Colors.white70)),
            ],
          ),
          const SizedBox(height: 8),
          Flexible(
            child: SingleChildScrollView(
              controller: controller,
              child: Text(
                text,
                style: context.tt.bodyMedium?.copyWith(color: Colors.white.withValues(alpha: 0.88)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tips extends StatelessWidget {
  const _Tips();

  @override
  Widget build(BuildContext context) {
    const tips = [
      (Icons.person_outline, 'Say their name, role, and company'),
      (Icons.place_outlined, 'Mention where you met and who introduced you'),
      (Icons.local_fire_department_outlined, 'Finish with a 1 to 10 rating of the conversation'),
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('For the best draft', style: context.tt.labelMedium?.copyWith(color: Colors.white70)),
          const SizedBox(height: 10),
          for (final t in tips)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(t.$1, size: 17, color: AppColors.freshLeaf),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      t.$2,
                      style: context.tt.bodySmall?.copyWith(color: Colors.white.withValues(alpha: 0.8)),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Processing extends StatelessWidget {
  const _Processing({super.key, required this.step, required this.steps});
  final int step;
  final List<String> steps;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_awesome, color: AppColors.freshLeaf),
                const SizedBox(width: 10),
                Text('Summarizing your recap', style: context.tt.titleMedium?.copyWith(color: Colors.white)),
              ],
            ),
            const SizedBox(height: 18),
            for (var i = 0; i < steps.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  children: [
                    SizedBox(
                      width: 22,
                      height: 22,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        child: i < step
                            ? const Icon(Icons.check_circle_rounded, key: ValueKey('done'), color: AppColors.freshLeaf, size: 22)
                            : i == step
                                ? const Padding(
                                    key: ValueKey('busy'),
                                    padding: EdgeInsets.all(3),
                                    child: CircularProgressIndicator(strokeWidth: 2.2, color: AppColors.freshLeaf),
                                  )
                                : Icon(
                                    Icons.circle_outlined,
                                    key: const ValueKey('todo'),
                                    color: Colors.white.withValues(alpha: 0.25),
                                    size: 22,
                                  ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 250),
                        style: context.tt.bodyMedium!.copyWith(
                          color: Colors.white.withValues(alpha: i <= step ? 0.92 : 0.4),
                          fontWeight: i == step ? FontWeight.w600 : FontWeight.w400,
                        ),
                        child: Text(steps[i]),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
