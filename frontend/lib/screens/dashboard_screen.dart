import 'package:flutter/material.dart';

import '../models/contact.dart';
import '../navigation.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/common.dart';
import '../widgets/network_tree.dart';
import 'settings_sheet.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final showSettings = MediaQuery.sizeOf(context).width < Breakpoints.rail;
    final header = _Header(showSettings: showSettings);

    if (app.contacts.isEmpty) {
      return SafeArea(
        child: Column(
          children: [
            Padding(padding: const EdgeInsets.fromLTRB(20, 16, 20, 0), child: header),
            Expanded(
              child: EmptyState(
                icon: Icons.hub_outlined,
                title: 'Your tree is bare',
                message: 'Record a quick recap after you meet someone, or add a contact by hand.',
                action: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  alignment: WrapAlignment.center,
                  children: [
                    FilledButton.icon(
                      onPressed: () => openCapture(context),
                      icon: const Icon(Icons.mic_rounded),
                      label: const Text('Record recap'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => openEditor(context),
                      icon: const Icon(Icons.person_add_alt_1_outlined),
                      label: const Text('Add contact'),
                    ),
                    TextButton(onPressed: app.loadDemoData, child: const Text('Load sample network')),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return SafeArea(
      bottom: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final hPad = constraints.maxWidth >= 600 ? 32.0 : 18.0;
          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(hPad, 20, hPad, 140),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    header,
                    const SizedBox(height: 24),
                    const FadeSlideIn(index: 0, child: HomeTreeCard()),
                    const SizedBox(height: 28),
                    const FadeSlideIn(index: 1, child: _RecentlyMet()),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.showSettings});
  final bool showSettings;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final name = app.userName.isEmpty ? '' : ', ${app.userName}';
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${greeting()}$name', style: context.tt.headlineSmall),
              const SizedBox(height: 4),
              Text(
                app.contacts.isEmpty ? 'Let\'s start building your network.' : 'Here\'s your network at a glance.',
                style: context.tt.bodyMedium?.copyWith(color: context.oc.muted),
              ),
            ],
          ),
        ),
        if (showSettings)
          IconButton(
            tooltip: 'Settings',
            onPressed: () => showSettingsSheet(context),
            icon: const Icon(Icons.settings_outlined),
          ),
      ],
    );
  }
}

class _RecentlyMet extends StatelessWidget {
  const _RecentlyMet();

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final list = app.contacts.where((c) => c.metOn != null).toList()
      ..sort((a, b) => b.metOn!.compareTo(a.metOn!));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text('Recently met', style: context.tt.titleMedium)),
            TextButton(onPressed: () => app.setTab(AppTab.people), child: const Text('See everyone')),
          ],
        ),
        const SizedBox(height: 6),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            child: Column(
              children: [
                for (var i = 0; i < list.length && i < 5; i++) ...[
                  if (i > 0) Divider(height: 1, indent: 64, color: context.oc.border),
                  _Row(contact: list[i]),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.contact});
  final Contact contact;

  @override
  Widget build(BuildContext context) {
    final c = contact;
    final meta = [if (c.metAt.isNotEmpty) c.metAt, relativePast(c.metOn!)].join(' · ');
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => openContact(context, c.id),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        child: Row(
          children: [
            ContactAvatar(contact: c, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.tt.titleSmall),
                  const SizedBox(height: 2),
                  Text(
                    meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.tt.bodySmall?.copyWith(color: context.oc.muted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            StrengthBadge(value: c.strength),
          ],
        ),
      ),
    );
  }
}
