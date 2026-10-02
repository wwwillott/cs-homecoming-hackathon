import 'package:flutter/material.dart';

import '../models/user_mode.dart';
import '../navigation.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';

Future<void> showSettingsSheet(BuildContext context) {
  if (MediaQuery.sizeOf(context).width >= Breakpoints.rail) {
    return showDialog(
      context: context,
      builder: (_) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: const Padding(padding: EdgeInsets.fromLTRB(24, 24, 24, 16), child: _SettingsBody()),
        ),
      ),
    );
  }
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: _SettingsBody(),
    ),
  );
}

class _SettingsBody extends StatelessWidget {
  const _SettingsBody();

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Settings', style: context.tt.headlineSmall),
          const SizedBox(height: 22),
          Text('I\'m using Spruce as a', style: context.tt.labelMedium),
          const SizedBox(height: 8),
          SegmentedButton<UserMode>(
            segments: const [
              ButtonSegment(value: UserMode.seeker, label: Text('Job seeker'), icon: Icon(Icons.travel_explore)),
              ButtonSegment(value: UserMode.recruiter, label: Text('Recruiter'), icon: Icon(Icons.badge_outlined)),
            ],
            selected: {app.mode},
            onSelectionChanged: (s) => app.setMode(s.first),
          ),
          const SizedBox(height: 6),
          Text(app.mode.description, style: context.tt.bodySmall),
          const SizedBox(height: 20),
          Text('Appearance', style: context.tt.labelMedium),
          const SizedBox(height: 8),
          SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(value: ThemeMode.system, label: Text('System')),
              ButtonSegment(value: ThemeMode.light, label: Text('Light')),
              ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
            ],
            selected: {app.themeMode},
            onSelectionChanged: (s) => app.setThemeMode(s.first),
          ),
          const SizedBox(height: 18),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Demo mode'),
            subtitle: Text(
              app.demoMode
                  ? 'Sample voice and assistant answers stay on this device.'
                  : 'Live transcription and the AI assistant are on.',
            ),
            value: app.demoMode,
            onChanged: app.setDemoMode,
          ),
          const SizedBox(height: 8),
          const Divider(),
          const SizedBox(height: 6),
          if (app.username != null) ...[
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.account_circle_outlined, color: context.oc.muted),
              title: Text(app.username!, style: context.tt.titleSmall),
              subtitle: Text('Signed in', style: context.tt.bodySmall),
            ),
            _ActionRow(
              icon: Icons.logout_rounded,
              title: 'Sign out',
              subtitle: 'Return to the login screen',
              onTap: () async {
                Navigator.of(context).pop();
                await app.signOut();
              },
            ),
          ],
          _ActionRow(
            icon: Icons.auto_awesome_motion_outlined,
            title: 'Load sample network',
            subtitle: 'Replaces your contacts with 27 sample people',
            onTap: () async {
              final ok = await _confirm(
                context,
                'Load sample network?',
                'This replaces the contacts currently on this device.',
              );
              if (ok && context.mounted) {
                app.loadDemoData();
                Navigator.of(context).pop();
              }
            },
          ),
          _ActionRow(
            icon: Icons.restart_alt_rounded,
            title: 'Reset app',
            subtitle: 'Clear everything and start from the welcome screen',
            destructive: true,
            onTap: () async {
              final ok = await _confirm(context, 'Reset Spruce?', 'All contacts on this device will be removed.');
              if (ok && context.mounted) {
                Navigator.of(context).pop();
                await app.resetApp();
              }
            },
          ),
        ],
      ),
    );
  }

  Future<bool> _confirm(BuildContext context, String title, String body) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Continue')),
        ],
      ),
    );
    return result ?? false;
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? AppColors.rose : context.oc.ink;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        child: Row(
          children: [
            Icon(icon, color: destructive ? AppColors.rose : context.oc.muted),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: context.tt.titleSmall?.copyWith(color: color)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: context.tt.bodySmall),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: context.oc.subtle),
          ],
        ),
      ),
    );
  }
}
