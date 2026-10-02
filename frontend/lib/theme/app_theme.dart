import 'package:flutter/material.dart';

import '../models/contact.dart';

class OrbitColors extends ThemeExtension<OrbitColors> {
  const OrbitColors({
    required this.background,
    required this.surface,
    required this.surfaceHigh,
    required this.border,
    required this.ink,
    required this.muted,
    required this.subtle,
    required this.graphBackground,
    required this.graphGrid,
  });

  final Color background;
  final Color surface;
  final Color surfaceHigh;
  final Color border;
  final Color ink;
  final Color muted;
  final Color subtle;
  final Color graphBackground;
  final Color graphGrid;

  static const light = OrbitColors(
    background: Color(0xFFF5F6FA),
    surface: Color(0xFFFFFFFF),
    surfaceHigh: Color(0xFFEEF0F6),
    border: Color(0xFFE3E6EE),
    ink: Color(0xFF0E1324),
    muted: Color(0xFF5B6478),
    subtle: Color(0xFF98A1B3),
    graphBackground: Color(0xFFF8F9FC),
    graphGrid: Color(0xFFE9ECF3),
  );

  static const dark = OrbitColors(
    background: Color(0xFF0A0D16),
    surface: Color(0xFF121624),
    surfaceHigh: Color(0xFF1A2033),
    border: Color(0xFF242B40),
    ink: Color(0xFFE9ECF5),
    muted: Color(0xFF9099AF),
    subtle: Color(0xFF5E6780),
    graphBackground: Color(0xFF0B0F1A),
    graphGrid: Color(0xFF151B2B),
  );

  @override
  OrbitColors copyWith() => this;

  @override
  OrbitColors lerp(ThemeExtension<OrbitColors>? other, double t) {
    if (other is! OrbitColors) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return OrbitColors(
      background: l(background, other.background),
      surface: l(surface, other.surface),
      surfaceHigh: l(surfaceHigh, other.surfaceHigh),
      border: l(border, other.border),
      ink: l(ink, other.ink),
      muted: l(muted, other.muted),
      subtle: l(subtle, other.subtle),
      graphBackground: l(graphBackground, other.graphBackground),
      graphGrid: l(graphGrid, other.graphGrid),
    );
  }
}

extension OrbitThemeX on BuildContext {
  OrbitColors get oc => Theme.of(this).extension<OrbitColors>()!;
  ColorScheme get cs => Theme.of(this).colorScheme;
  TextTheme get tt => Theme.of(this).textTheme;
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
}

class AppColors {
  static const primary = Color(0xFF5B5BF0);
  static const primaryDark = Color(0xFF7C7CFF);
  static const teal = Color(0xFF14B8A6);
  static const amber = Color(0xFFF59E0B);
  static const rose = Color(0xFFF43F5E);
  static const ai = Color(0xFF8B5CF6);

  static const _strengthStops = [
    Color(0xFFA3AEC2),
    Color(0xFF38BDF8),
    Color(0xFF6366F1),
    Color(0xFFC026D3),
  ];

  /// Sequential scale from weak (slate) to strongest (magenta).
  static Color strength(num value) {
    final t = ((value - 1) / 9).clamp(0.0, 1.0) * (_strengthStops.length - 1);
    final i = t.floor().clamp(0, _strengthStops.length - 2);
    return Color.lerp(_strengthStops[i], _strengthStops[i + 1], t - i)!;
  }

  static String strengthWord(int value) {
    if (value >= 9) return 'Exceptional';
    if (value >= 7) return 'Strong';
    if (value >= 5) return 'Solid';
    if (value >= 3) return 'Light';
    return 'Weak';
  }

  static const category = {
    ContactCategory.recruiter: Color(0xFF0EA5E9),
    ContactCategory.mentor: Color(0xFFF59E0B),
    ContactCategory.engineer: Color(0xFF10B981),
    ContactCategory.founder: Color(0xFFEF4444),
    ContactCategory.peer: Color(0xFF8B5CF6),
    ContactCategory.alumni: Color(0xFF3B82F6),
    ContactCategory.candidate: Color(0xFFEC4899),
    ContactCategory.other: Color(0xFF94A3B8),
  };

  static const _hashPalette = [
    Color(0xFF6366F1),
    Color(0xFF0EA5E9),
    Color(0xFF10B981),
    Color(0xFFF59E0B),
    Color(0xFFEF4444),
    Color(0xFF8B5CF6),
    Color(0xFFEC4899),
    Color(0xFF14B8A6),
    Color(0xFFF97316),
    Color(0xFF84CC16),
  ];

  static Color forKey(String key) {
    if (key.isEmpty) return const Color(0xFF94A3B8);
    var h = 0;
    for (final c in key.toLowerCase().codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return _hashPalette[h % _hashPalette.length];
  }

  /// Warm when recently in touch, cold when it has been a while.
  static Color recency(int days) {
    const stops = [
      (0, Color(0xFFF97316)),
      (14, Color(0xFFEAB308)),
      (45, Color(0xFF38BDF8)),
      (120, Color(0xFF64748B)),
    ];
    if (days <= 0) return stops.first.$2;
    for (var i = 0; i < stops.length - 1; i++) {
      final (d0, c0) = stops[i];
      final (d1, c1) = stops[i + 1];
      if (days <= d1) return Color.lerp(c0, c1, (days - d0) / (d1 - d0))!;
    }
    return stops.last.$2;
  }
}

class AppTheme {
  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final oc = isDark ? OrbitColors.dark : OrbitColors.light;
    final primary = isDark ? AppColors.primaryDark : AppColors.primary;

    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: brightness,
    ).copyWith(
      primary: primary,
      onPrimary: Colors.white,
      secondary: AppColors.teal,
      surface: oc.surface,
      onSurface: oc.ink,
      onSurfaceVariant: oc.muted,
      outline: oc.border,
      outlineVariant: oc.border,
      surfaceContainerLowest: oc.background,
      surfaceContainerLow: oc.surface,
      surfaceContainer: oc.surface,
      surfaceContainerHigh: oc.surfaceHigh,
      surfaceContainerHighest: oc.surfaceHigh,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      fontFamily: 'Inter',
    );

    final text = base.textTheme.apply(bodyColor: oc.ink, displayColor: oc.ink).copyWith(
          displaySmall: base.textTheme.displaySmall?.copyWith(
              fontWeight: FontWeight.w800, letterSpacing: -1.2, color: oc.ink),
          headlineMedium: base.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w700, letterSpacing: -0.8, color: oc.ink),
          headlineSmall: base.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700, letterSpacing: -0.6, color: oc.ink),
          titleLarge: base.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700, letterSpacing: -0.4, color: oc.ink),
          titleMedium: base.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600, letterSpacing: -0.2, color: oc.ink),
          titleSmall: base.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600, color: oc.ink),
          bodyMedium: base.textTheme.bodyMedium?.copyWith(color: oc.ink, height: 1.45),
          bodySmall: base.textTheme.bodySmall?.copyWith(color: oc.muted, height: 1.4),
          labelLarge: base.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
          labelMedium: base.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600, color: oc.muted, letterSpacing: 0.2),
          labelSmall: base.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w600, color: oc.muted, letterSpacing: 0.4),
        );

    final radius = BorderRadius.circular(14);

    return base.copyWith(
      textTheme: text,
      scaffoldBackgroundColor: oc.background,
      canvasColor: oc.background,
      dividerColor: oc.border,
      splashFactory: InkSparkle.splashFactory,
      extensions: [oc],
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: FadeForwardsPageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: oc.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        foregroundColor: oc.ink,
        titleTextStyle: text.titleLarge,
      ),
      cardTheme: CardThemeData(
        color: oc.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: oc.border),
        ),
      ),
      dividerTheme: DividerThemeData(color: oc.border, thickness: 1, space: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: oc.surface,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        labelStyle: TextStyle(color: oc.muted),
        hintStyle: TextStyle(color: oc.subtle),
        border: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: oc.border)),
        enabledBorder:
            OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: oc.border)),
        focusedBorder:
            OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: primary, width: 1.6)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 46),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          shape: RoundedRectangleBorder(borderRadius: radius),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 46),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          foregroundColor: oc.ink,
          side: BorderSide(color: oc.border),
          shape: RoundedRectangleBorder(borderRadius: radius),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: radius),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: oc.surface,
        selectedColor: primary.withValues(alpha: isDark ? 0.25 : 0.12),
        side: BorderSide(color: oc.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        labelStyle: TextStyle(color: oc.ink, fontWeight: FontWeight.w500, fontSize: 13),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        showCheckmark: false,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: oc.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: primary.withValues(alpha: isDark ? 0.22 : 0.12),
        elevation: 0,
        height: 68,
        labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: states.contains(WidgetState.selected) ? oc.ink : oc.muted,
            )),
        iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
              color: states.contains(WidgetState.selected) ? primary : oc.muted,
            )),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: oc.surface,
        indicatorColor: primary.withValues(alpha: isDark ? 0.22 : 0.12),
        selectedIconTheme: IconThemeData(color: primary),
        unselectedIconTheme: IconThemeData(color: oc.muted),
        selectedLabelTextStyle:
            TextStyle(color: oc.ink, fontWeight: FontWeight.w600, fontSize: 12),
        unselectedLabelTextStyle:
            TextStyle(color: oc.muted, fontWeight: FontWeight.w500, fontSize: 12),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: oc.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: oc.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
      sliderTheme: SliderThemeData(
        trackHeight: 6,
        inactiveTrackColor: oc.surfaceHigh,
        overlayShape: SliderComponentShape.noOverlay,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? oc.surfaceHigh : oc.ink,
        contentTextStyle: TextStyle(color: isDark ? oc.ink : Colors.white, fontFamily: 'Inter'),
        shape: RoundedRectangleBorder(borderRadius: radius),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: isDark ? oc.surfaceHigh : oc.ink,
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: TextStyle(color: isDark ? oc.ink : Colors.white, fontSize: 12),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          side: BorderSide(color: oc.border),
          selectedBackgroundColor: primary.withValues(alpha: isDark ? 0.25 : 0.12),
          selectedForegroundColor: oc.ink,
          foregroundColor: oc.muted,
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
      ),
    );
  }
}
