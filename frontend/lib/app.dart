import 'package:flutter/material.dart';

import 'screens/auth_screen.dart';
import 'screens/home_shell.dart';
import 'screens/onboarding_screen.dart';
import 'state/app_state.dart';
import 'theme/app_theme.dart';

final _lightTheme = AppTheme.light();
final _darkTheme = AppTheme.dark();

class OrbitApp extends StatelessWidget {
  const OrbitApp({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: state,
      child: ListenableBuilder(
        listenable: state,
        builder: (context, _) => MaterialApp(
          title: 'Spruce',
          debugShowCheckedModeBanner: false,
          theme: _lightTheme,
          darkTheme: _darkTheme,
          themeMode: state.themeMode,
          navigatorKey: state.navigatorKey,
          home: const _RootGate(),
        ),
      ),
    );
  }
}

class _RootGate extends StatelessWidget {
  const _RootGate();

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final Widget child;
    if (!app.isSignedIn) {
      child = const AuthScreen(key: ValueKey('auth'));
    } else if (!app.onboarded) {
      child = const OnboardingScreen(key: ValueKey('onboarding'));
    } else {
      child = const HomeShell(key: ValueKey('shell'));
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 450),
      switchInCurve: Curves.easeOutCubic,
      child: child,
    );
  }
}
