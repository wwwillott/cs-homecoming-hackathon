import 'package:flutter/material.dart';

import '../models/contact.dart';
import '../navigation.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/contact_tile.dart';
import 'contact_detail_screen.dart';

enum _QuickFilter {
  all('All', null),
  favorites('Favorites', Icons.star_rounded),
  canRefer('Can refer', Icons.handshake_outlined);

  const _QuickFilter(this.label, this.icon);
  final String label;
  final IconData? icon;
}

class PeopleScreen extends StatefulWidget {
  const PeopleScreen({super.key});

  @override
  State<PeopleScreen> createState() => _PeopleScreenState();
}

class _PeopleScreenState extends State<PeopleScreen> {
  final _search = TextEditingController();
  String _query = '';
  _QuickFilter _filter = _QuickFilter.all;
  ContactCategory? _category;
  String? _tag;
  SortBy _sort = SortBy.recent;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _matches(Contact c) {
    switch (_filter) {
      case _QuickFilter.all:
        break;
      case _QuickFilter.favorites:
        if (!c.favorite) return false;
      case _QuickFilter.canRefer:
        if (!c.canRefer) return false;
    }
    if (_category != null && c.category != _category) return false;
    if (_tag != null && !c.tags.contains(_tag)) return false;
    if (_query.isEmpty) return true;
    final q = _query.toLowerCase();
    return c.name.toLowerCase().contains(q) ||
        c.company.toLowerCase().contains(q) ||
        c.title.toLowerCase().contains(q) ||
        c.metAt.toLowerCase().contains(q) ||
        c.location.toLowerCase().contains(q) ||
        c.notes.toLowerCase().contains(q) ||
        c.tags.any((t) => t.toLowerCase().contains(q));
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final split = isSplitLayout(context);
    final list = app.sorted(app.contacts.where(_matches), _sort);

    final listPane = SafeArea(
      bottom: false,
      right: !split,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
            child: Row(
              children: [
                Text('People', style: context.tt.headlineSmall),
                const SizedBox(width: 10),
                Pill(label: '${app.contacts.length}'),
                const Spacer(),
                _SortMenu(value: _sort, onChanged: (s) => setState(() => _sort = s)),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: TextField(
                    controller: _search,
                    onChanged: (v) => setState(() => _query = v.trim()),
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: 'Search name, company, event, tag…',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close_rounded),
                              onPressed: () {
                                _search.clear();
                                setState(() => _query = '');
                              },
                            ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 38,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    children: [
                      for (final f in _QuickFilter.values) ...[
                        ChoiceChip(
                          avatar: f.icon == null ? null : Icon(f.icon, size: 16),
                          label: Text(f.label),
                          selected: _filter == f,
                          onSelected: (_) => setState(() => _filter = f),
                        ),
                        const SizedBox(width: 8),
                      ],
                      _MenuChip<ContactCategory>(
                        label: _category?.label ?? 'Relationship',
                        active: _category != null,
                        items: ContactCategory.values,
                        itemLabel: (c) => c.label,
                        onSelected: (c) => setState(() => _category = c == _category ? null : c),
                        onClear: () => setState(() => _category = null),
                      ),
                      const SizedBox(width: 8),
                      _MenuChip<String>(
                        label: _tag ?? 'Tag',
                        active: _tag != null,
                        items: app.allTags,
                        itemLabel: (t) => t,
                        onSelected: (t) => setState(() => _tag = t == _tag ? null : t),
                        onClear: () => setState(() => _tag = null),
                      ),
                    ],
                  ),
                ),
              ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: list.isEmpty
                ? EmptyState(
                    icon: app.contacts.isEmpty ? Icons.people_outline_rounded : Icons.search_off_rounded,
                    title: app.contacts.isEmpty ? 'No connections yet' : 'No matches',
                    message: app.contacts.isEmpty
                        ? 'Add someone by hand or record a recap after your next conversation.'
                        : 'Try a different search or clear your filters.',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final c = list[i];
                      Widget tile = ContactTile(
                        key: ValueKey(c.id),
                        contact: c,
                        selected: split && app.selectedContactId == c.id,
                        onTap: () => openContact(context, c.id),
                      );
                      return i < 14 ? FadeSlideIn(index: i, child: tile) : tile;
                    },
                  ),
          ),
        ],
      ),
    );

    if (!split) return listPane;

    final selected = app.byId(app.selectedContactId);
    return Row(
      children: [
        SizedBox(width: 400, child: listPane),
        VerticalDivider(width: 1, color: context.oc.border),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            switchInCurve: Curves.easeOutCubic,
            transitionBuilder: (child, a) => FadeTransition(
              opacity: a,
              child: SlideTransition(
                position: Tween(begin: const Offset(0.02, 0), end: Offset.zero).animate(a),
                child: child,
              ),
            ),
            child: selected == null
                ? const EmptyState(
                    key: ValueKey('none'),
                    icon: Icons.touch_app_outlined,
                    title: 'Select someone',
                    message: 'Pick a person from the list to see everything you know about them.',
                  )
                : ContactDetailView(
                    key: ValueKey(selected.id),
                    contactId: selected.id,
                    embedded: true,
                    onClose: () => app.selectContact(null),
                  ),
          ),
        ),
      ],
    );
  }
}

class _SortMenu extends StatelessWidget {
  const _SortMenu({required this.value, required this.onChanged});
  final SortBy value;
  final ValueChanged<SortBy> onChanged;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<SortBy>(
      tooltip: 'Sort',
      initialValue: value,
      onSelected: onChanged,
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      itemBuilder: (_) => [
        for (final s in SortBy.values)
          PopupMenuItem(
            value: s,
            child: Row(
              children: [
                Icon(
                  Icons.check_rounded,
                  size: 18,
                  color: s == value ? context.cs.primary : Colors.transparent,
                ),
                const SizedBox(width: 10),
                Text(s.label),
              ],
            ),
          ),
      ],
      icon: Icon(Icons.swap_vert_rounded, color: context.oc.muted),
    );
  }
}

class _MenuChip<T> extends StatelessWidget {
  const _MenuChip({
    required this.label,
    required this.active,
    required this.items,
    required this.itemLabel,
    required this.onSelected,
    required this.onClear,
  });

  final String label;
  final bool active;
  final List<T> items;
  final String Function(T) itemLabel;
  final ValueChanged<T> onSelected;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<T>(
      tooltip: '',
      onSelected: onSelected,
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      constraints: const BoxConstraints(maxHeight: 360, minWidth: 180),
      itemBuilder: (_) => [for (final i in items) PopupMenuItem(value: i, child: Text(itemLabel(i)))],
      child: IgnorePointer(
        child: FilterChip(
          label: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label),
              const SizedBox(width: 4),
              Icon(Icons.expand_more_rounded, size: 16, color: context.oc.muted),
            ],
          ),
          selected: active,
          onSelected: (_) {},
        ),
      ),
    );
  }
}
