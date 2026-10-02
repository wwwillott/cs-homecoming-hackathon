import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/growing_tree.dart';

const _guestUsername = 'guest';
const _guestPassword = 'spruce-guest';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  var _busy = false;

  @override
  void initState() {
    super.initState();
    AppScope.read(context).authService.wake();
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  /// Signing in never blocks: blank fields use the guest account, unknown usernames are
  /// registered on the fly, and an unreachable server falls back to an on-device session.
  /// The timeout covers a free-tier host waking from sleep; offline devices fail immediately.
  Future<void> _submit() async {
    final typed = _username.text.trim();
    final username = typed.isEmpty ? _guestUsername : typed;
    final password = _password.text.isEmpty ? _guestPassword : _password.text;

    setState(() => _busy = true);
    final app = AppScope.read(context);
    AuthSession session;
    try {
      session = await _serverSession(app.authService, username, password)
          .timeout(const Duration(seconds: 60));
    } catch (_) {
      session = AuthSession(userId: 'local-${username.toLowerCase()}', username: username);
    }
    await app.signIn(session);
    if (mounted) setState(() => _busy = false);
  }

  Future<AuthSession> _serverSession(AuthService auth, String username, String password) async {
    try {
      return await auth.login(username: username, password: password);
    } on StateError {
      return auth.register(username: username, password: password);
    }
  }

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const FadeSlideIn(child: Center(child: _TreeMark())),
                    const SizedBox(height: 12),
                    FadeSlideIn(
                      index: 1,
                      child: Column(
                        children: [
                          Text('Spruce', style: context.tt.headlineMedium, textAlign: TextAlign.center),
                          const SizedBox(height: 6),
                          Text(
                            'Sign in to tend your network.',
                            style: context.tt.bodyMedium?.copyWith(color: oc.muted),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),
                    FadeSlideIn(
                      index: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextField(
                            controller: _username,
                            autofillHints: const [AutofillHints.username],
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'Username',
                              prefixIcon: Icon(Icons.person_outline_rounded),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _password,
                            obscureText: true,
                            autofillHints: const [AutofillHints.password],
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => _busy ? null : _submit(),
                            decoration: const InputDecoration(
                              labelText: 'Password',
                              prefixIcon: Icon(Icons.lock_outline_rounded),
                            ),
                          ),
                          const SizedBox(height: 24),
                          SizedBox(
                            height: 52,
                            child: FilledButton(
                              onPressed: _busy ? null : _submit,
                              child: _busy
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Text('Sign in'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TreeMark extends StatelessWidget {
  const _TreeMark();

  @override
  Widget build(BuildContext context) {
    const width = 190.0;
    return DecoratedBox(
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
      child: const SizedBox(
        width: width,
        height: width / growingTreeAspect,
        child: GrowingTree(growth: fullTreeGrowth * 1.0),
      ),
    );
  }
}
