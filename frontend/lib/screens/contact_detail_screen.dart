import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/contact.dart';
import '../navigation.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/common.dart';

class ContactDetailScreen extends StatelessWidget {
  const ContactDetailScreen({super.key, required this.contactId});
  final String contactId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: SafeArea(child: ContactDetailView(contactId: contactId)));
  }
}

class ContactDetailView extends StatelessWidget {
  const ContactDetailView({
    super.key,
    required this.contactId,
    this.embedded = false,
    this.onClose,
    this.onOpenContact,
  });

  final String contactId;
  final bool embedded;
  final VoidCallback? onClose;
  final ValueChanged<String>? onOpenContact;

  void _open(BuildContext context, String id) {
    if (onOpenContact != null) {
      onOpenContact!(id);
    } else {
      openContact(context, id);
    }
  }

  Future<void> _delete(BuildContext context, Contact c) async {
    final app = AppScope.read(context);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove ${c.firstName}?'),
        content: const Text('They\'ll be removed from your network and the graph.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.rose),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    if (!embedded) Navigator.of(context).pop();
    app.delete(c.id);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('${c.name} removed'),
        action: SnackBarAction(label: 'Undo', onPressed: () => app.upsert(c)),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final c = app.byId(contactId);
    if (c == null) {
      return const EmptyState(
        icon: Icons.person_off_outlined,
        title: 'Contact not found',
        message: 'This person may have been removed.',
      );
    }

    final toolbar = Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Row(
        children: [
          if (!embedded)
            IconButton(
              tooltip: 'Back',
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.arrow_back_rounded),
            )
          else if (onClose != null)
            IconButton(tooltip: 'Close', onPressed: onClose, icon: const Icon(Icons.close_rounded)),
          const Spacer(),
          IconButton(
            tooltip: c.favorite ? 'Unfavorite' : 'Favorite',
            onPressed: () => app.toggleFavorite(c.id),
            icon: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (child, a) => ScaleTransition(scale: a, child: child),
              child: Icon(
                c.favorite ? Icons.star_rounded : Icons.star_outline_rounded,
                key: ValueKey(c.favorite),
                color: c.favorite ? AppColors.amber : null,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Edit',
            onPressed: () => openEditor(context, initial: c),
            icon: const Icon(Icons.edit_outlined),
          ),
          PopupMenuButton<String>(
            tooltip: 'More',
            position: PopupMenuPosition.under,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            onSelected: (v) {
              if (v == 'delete') _delete(context, c);
              if (v == 'log') _showLogSheet(context, c);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'log', child: Text('Log a touchpoint')),
              PopupMenuItem(value: 'delete', child: Text('Remove from network')),
            ],
          ),
        ],
      ),
    );

    return Column(
      children: [
        toolbar,
        Expanded(
          child: LayoutBuilder(builder: (context, constraints) {
            final twoCol = constraints.maxWidth >= 760;
            final hPad = constraints.maxWidth >= 600 ? 28.0 : 18.0;
            final left = <Widget>[
              _StrengthCard(contact: c),
              if (c.aiSummary.isNotEmpty) _SummaryCard(contact: c),
              if (c.notes.isNotEmpty ||
                  c.conversationHooks.isNotEmpty ||
                  c.howTheyCanHelp.isNotEmpty ||
                  c.howICanHelp.isNotEmpty)
                _NotesCard(contact: c),
            ];
            final right = <Widget>[
              _MetCard(contact: c, onOpen: (id) => _open(context, id)),
              _InfoCard(contact: c),
              if (c.school.isNotEmpty || c.skills.isNotEmpty || c.tags.isNotEmpty) _BackgroundCard(contact: c),
              _ConnectionsCard(contact: c, onOpen: (id) => _open(context, id)),
              _TimelineCard(contact: c),
            ];
            List<Widget> spaced(List<Widget> items) => [
                  for (var i = 0; i < items.length; i++) ...[
                    if (i > 0) const SizedBox(height: 14),
                    FadeSlideIn(index: i, child: items[i]),
                  ],
                ];

            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(hPad, 4, hPad, 40),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 980),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _Header(contact: c),
                      const SizedBox(height: 24),
                      if (twoCol)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: Column(children: spaced(left))),
                            const SizedBox(width: 14),
                            Expanded(child: Column(children: spaced(right))),
                          ],
                        )
                      else
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: spaced([...left, ...right]),
                        ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }
}

Future<void> _showLogSheet(BuildContext context, Contact c) async {
  final app = AppScope.read(context);
  final note = TextEditingController();
  var type = InteractionType.message;
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(ctx).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Log a touchpoint with ${c.firstName}', style: ctx.tt.titleMedium),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in InteractionType.values.where((t) => t != InteractionType.voiceRecap))
                  ChoiceChip(
                    avatar: Icon(t.icon, size: 16),
                    label: Text(t.label),
                    selected: type == t,
                    onSelected: (_) => setState(() => type = t),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: note,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(hintText: 'What did you talk about? (optional)'),
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save touchpoint')),
          ],
        ),
      ),
    ),
  );
  if (saved == true) {
    app.logInteraction(c.id, Interaction(date: DateTime.now(), type: type, note: note.text.trim()));
  }
  note.dispose();
}

class _Header extends StatelessWidget {
  const _Header({required this.contact});
  final Contact contact;

  @override
  Widget build(BuildContext context) {
    final c = contact;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        ContactAvatar(contact: c, size: 72),
        const SizedBox(width: 18),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(c.name, style: context.tt.headlineSmall),
              if (c.roleLine.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(c.roleLine, style: context.tt.bodyMedium?.copyWith(color: context.oc.muted)),
              ],
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  Pill(
                    label: c.category.label,
                    icon: c.category.icon,
                    color: AppColors.category[c.category],
                    filled: true,
                  ),
                  if (c.canRefer)
                    const Pill(label: 'Can refer', icon: Icons.handshake_outlined, color: AppColors.primary, filled: true),
                  if (c.location.isNotEmpty) Pill(label: c.location, icon: Icons.location_on_outlined),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StrengthCard extends StatelessWidget {
  const _StrengthCard({required this.contact});
  final Contact contact;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = contact.strength;
    final color = AppColors.strength(s);
    return SectionCard(
      title: app.mode.strengthLabel,
      icon: Icons.local_fire_department_outlined,
      trailing: Text(
        AppColors.strengthWord(s),
        style: TextStyle(fontWeight: FontWeight.w700, color: color, fontSize: 13),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$s',
                style: context.tt.displaySmall?.copyWith(color: color, height: 1, fontSize: 40),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 4, left: 4),
                child: Text('/ 10', style: context.tt.titleSmall?.copyWith(color: context.oc.subtle)),
              ),
              const Spacer(),
              if (contact.daysSinceContact > 0)
                Text(
                  'Last contact ${relativePast(contact.lastContacted ?? contact.metOn ?? DateTime.now())}',
                  style: context.tt.bodySmall,
                ),
            ],
          ),
          const SizedBox(height: 14),
          StrengthBar(value: s),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.contact});
  final Contact contact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(1.4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(19),
        gradient: const LinearGradient(colors: [Color(0xFF6D6DF7), Color(0xFFB146E0), Color(0xFF38BDF8)]),
      ),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: context.oc.surface, borderRadius: BorderRadius.circular(18)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_awesome, size: 18, color: AppColors.ai),
                const SizedBox(width: 8),
                Expanded(child: Text('Recap summary', style: context.tt.titleSmall)),
                Text('From voice recap', style: context.tt.labelSmall),
              ],
            ),
            const SizedBox(height: 12),
            Text(contact.aiSummary, style: context.tt.bodyMedium),
          ],
        ),
      ),
    );
  }
}

class _NotesCard extends StatelessWidget {
  const _NotesCard({required this.contact});
  final Contact contact;

  @override
  Widget build(BuildContext context) {
    final c = contact;
    final items = [
      if (c.notes.isNotEmpty) (Icons.notes_rounded, 'Notes', c.notes),
      if (c.conversationHooks.isNotEmpty) (Icons.forum_outlined, 'Conversation hooks', c.conversationHooks),
      if (c.howTheyCanHelp.isNotEmpty) (Icons.volunteer_activism_outlined, 'How they can help', c.howTheyCanHelp),
      if (c.howICanHelp.isNotEmpty) (Icons.redeem_outlined, 'How I can help', c.howICanHelp),
    ];
    return SectionCard(
      title: 'What you know',
      icon: Icons.lightbulb_outline_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(items[i].$1, size: 17, color: context.oc.subtle),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(items[i].$2, style: context.tt.labelMedium),
                      const SizedBox(height: 3),
                      Text(items[i].$3, style: context.tt.bodyMedium),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _MetCard extends StatelessWidget {
  const _MetCard({required this.contact, required this.onOpen});
  final Contact contact;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final c = contact;
    final intro = app.byId(c.introducedById);
    return SectionCard(
      title: 'How you met',
      icon: Icons.place_outlined,
      child: Column(
        children: [
          _KV(label: 'Where', value: c.metAt.isEmpty ? '—' : c.metAt),
          _KV(label: 'When', value: c.metOn == null ? '—' : '${shortDate(c.metOn!)} · ${relativePast(c.metOn!)}'),
          if (intro != null)
            _KV(
              label: 'Introduced by',
              valueWidget: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => onOpen(intro.id),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ContactAvatar(contact: intro, size: 22),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        intro.name,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontWeight: FontWeight.w600, color: context.cs.primary),
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

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.contact});
  final Contact contact;

  @override
  Widget build(BuildContext context) {
    final c = contact;
    final rows = [
      (Icons.mail_outline_rounded, c.email),
      (Icons.call_outlined, c.phone),
      (Icons.link_rounded, c.linkedin),
    ].where((r) => r.$2.isNotEmpty).toList();
    return SectionCard(
      title: 'Contact info',
      icon: Icons.contact_mail_outlined,
      child: rows.isEmpty
          ? Text('No contact info yet.', style: context.tt.bodySmall)
          : Column(
              children: [
                for (final r in rows)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Icon(r.$1, size: 17, color: context.oc.subtle),
                        const SizedBox(width: 12),
                        Expanded(child: SelectableText(r.$2, style: context.tt.bodyMedium)),
                        IconButton(
                          tooltip: 'Copy',
                          visualDensity: VisualDensity.compact,
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: r.$2));
                            ScaffoldMessenger.of(context)
                              ..hideCurrentSnackBar()
                              ..showSnackBar(const SnackBar(content: Text('Copied')));
                          },
                          icon: Icon(Icons.copy_rounded, size: 16, color: context.oc.subtle),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

class _BackgroundCard extends StatelessWidget {
  const _BackgroundCard({required this.contact});
  final Contact contact;

  @override
  Widget build(BuildContext context) {
    final c = contact;
    return SectionCard(
      title: 'Background & tags',
      icon: Icons.sell_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (c.school.isNotEmpty) _KV(label: 'School', value: c.school),
          if (c.skills.isNotEmpty) ...[
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [for (final s in c.skills) Pill(label: s, icon: Icons.bolt_rounded)],
            ),
          ],
          if (c.tags.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [for (final t in c.tags) Pill(label: '#$t', color: AppColors.forKey(t), filled: true)],
            ),
          ],
        ],
      ),
    );
  }
}

class _ConnectionsCard extends StatelessWidget {
  const _ConnectionsCard({required this.contact, required this.onOpen});
  final Contact contact;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final people = app.neighborsOf(contact.id).map(app.byId).whereType<Contact>().toList()
      ..sort((a, b) => b.strength.compareTo(a.strength));
    return SectionCard(
      title: 'Mutual connections',
      icon: Icons.hub_outlined,
      trailing: people.isEmpty ? null : Pill(label: '${people.length}'),
      child: people.isEmpty
          ? Text('No one else in your network knows ${contact.firstName} yet.', style: context.tt.bodySmall)
          : Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final p in people)
                  ActionChip(
                    avatar: ContactAvatar(contact: p, size: 22),
                    label: Text(p.name),
                    onPressed: () => onOpen(p.id),
                  ),
              ],
            ),
    );
  }
}

class _TimelineCard extends StatelessWidget {
  const _TimelineCard({required this.contact});
  final Contact contact;

  @override
  Widget build(BuildContext context) {
    final items = [...contact.interactions]..sort((a, b) => b.date.compareTo(a.date));
    return SectionCard(
      title: 'Timeline',
      icon: Icons.timeline_rounded,
      child: items.isEmpty
          ? Text('No touchpoints logged yet.', style: context.tt.bodySmall)
          : Column(
              children: [
                for (var i = 0; i < items.length; i++)
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Column(
                          children: [
                            Container(
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                color: context.oc.surfaceHigh,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(items[i].type.icon, size: 15, color: context.oc.muted),
                            ),
                            if (i < items.length - 1)
                              Expanded(child: Container(width: 1.5, color: context.oc.border)),
                          ],
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(bottom: i < items.length - 1 ? 14 : 0, top: 5),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(child: Text(items[i].type.label, style: context.tt.titleSmall)),
                                    Text(relativePast(items[i].date), style: context.tt.labelSmall),
                                  ],
                                ),
                                if (items[i].note.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(items[i].note, style: context.tt.bodySmall),
                                ],
                              ],
                            ),
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

class _KV extends StatelessWidget {
  const _KV({required this.label, this.value, this.valueWidget});
  final String label;
  final String? value;
  final Widget? valueWidget;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 110, child: Text(label, style: context.tt.bodySmall)),
          Expanded(child: valueWidget ?? Text(value ?? '', style: context.tt.bodyMedium)),
        ],
      ),
    );
  }
}
