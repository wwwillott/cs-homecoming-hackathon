import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../graph/graph_options.dart';
import '../graph/graph_style.dart';
import '../graph/graph_view.dart';
import '../models/contact.dart';
import '../models/network_tree.dart';
import '../navigation.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import 'contact_detail_screen.dart';
import 'grow_screen.dart';

class NetworkScreen extends StatefulWidget {
  const NetworkScreen({super.key});

  @override
  State<NetworkScreen> createState() => _NetworkScreenState();
}

class _NetworkScreenState extends State<NetworkScreen> {
  final _graph = GraphViewController();
  bool _legendOpen = false;
  String? _lastFocus;
  bool _focusFromTap = false;

  void _onFocus(AppState app, String? id) {
    _focusFromTap = true;
    app.setGraphFocus(id);
  }

  void _focusAndCenter(AppState app, String id) {
    _focusFromTap = false;
    app.setGraphFocus(id);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final contacts = app.contacts;
    final wide = isSplitLayout(context);
    final narrow = MediaQuery.sizeOf(context).width < Breakpoints.rail;
    final focus = app.byId(app.graphFocusId);
    final legendOpen = _legendOpen;
    final myLabel = (app.username?.trim().isNotEmpty ?? false)
        ? app.username!.trim()
        : (app.userName.trim().isNotEmpty ? app.userName.trim() : 'You');
    final theirLabel = app.activeSharedTree?.shortLabel ?? 'Them';

    if (app.graphFocusId != _lastFocus) {
      final id = app.graphFocusId;
      _lastFocus = id;
      if (id != null && !_focusFromTap) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _graph.centerOn(id));
      }
      _focusFromTap = false;
    }

    if (contacts.isEmpty && !app.isSharedMode) {
      return EmptyState(
        icon: Icons.hub_outlined,
        title: 'Nothing to map yet',
        message: 'Add a few connections and your network graph will appear here.',
        action: FilledButton.tonal(
          onPressed: () => _openJoin(context, app),
          child: const Text('Join a shared tree'),
        ),
      );
    }

    final styler = GraphStyler(
      contacts: app.isSharedMode ? [...contacts, ...app.attachedContacts] : contacts,
      colorBy: app.colorBy,
      sizeBy: app.sizeBy,
    );

    final graphStack = Stack(
      children: [
        Positioned.fill(
          child: GraphView(
            contacts: contacts,
            attachedContacts: app.isSharedMode ? app.attachedContacts : const [],
            colorBy: app.colorBy,
            sizeBy: app.sizeBy,
            showPeerLinks: app.showPeerLinks,
            focusId: app.graphFocusId,
            onFocusChanged: (id) => _onFocus(app, id),
            controller: _graph,
            anchorLabel: myLabel,
            attachedAnchorLabel: theirLabel,
            fitPadding: EdgeInsets.fromLTRB(
              32,
              narrow ? (app.isSharedMode ? 150 : 120) : 96,
              narrow ? 32 : 190,
              narrow ? 220 : 60,
            ),
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(narrow ? 14 : 24, 14, narrow ? 14 : 24, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _TopBar(
                    compact: narrow,
                    contacts: contacts,
                    onSearch: () => _openSearch(context, app),
                    onShare: () => _openShare(context, app),
                    onJoin: () => _openJoin(context, app),
                    onLeave: app.isSharedMode ? app.leaveSharedMode : null,
                  ),
                  if (app.isSharedMode) ...[
                    const SizedBox(height: 8),
                    _SharedModeBanner(label: '$myLabel ↔ $theirLabel'),
                  ],
                ],
              ),
            ),
          ),
        ),
        if (!narrow) Positioned(right: 20, bottom: 24, child: _ZoomControls(controller: _graph)),
        Positioned(
          left: narrow ? 14 : 24,
          bottom: narrow ? 14 : 24,
          right: narrow ? 90 : null,
          child: IgnorePointer(
            ignoring: narrow && focus != null,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 250),
              opacity: narrow && focus != null ? 0 : 1,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    layoutBuilder: (current, previous) =>
                        Stack(alignment: Alignment.bottomLeft, children: [...previous, ?current]),
                    transitionBuilder: (child, a) => FadeTransition(
                      opacity: a,
                      child: SizeTransition(
                        sizeFactor: a,
                        alignment: Alignment.bottomLeft,
                        child: ScaleTransition(
                          scale: Tween(begin: 0.85, end: 1.0).animate(a),
                          alignment: Alignment.bottomLeft,
                          child: child,
                        ),
                      ),
                    ),
                    child: legendOpen
                        ? Padding(
                            key: const ValueKey('legend'),
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _Legend(styler: styler),
                          )
                        : const SizedBox.shrink(),
                  ),
                  _LegendButton(open: legendOpen, onTap: () => setState(() => _legendOpen = !legendOpen)),
                ],
              ),
            ),
          ),
        ),
        if (narrow)
          Positioned(
            left: 14,
            right: 14,
            bottom: 90,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 280),
              switchInCurve: Curves.easeOutCubic,
              transitionBuilder: (child, a) => FadeTransition(
                opacity: a,
                child: SlideTransition(
                  position: Tween(begin: const Offset(0, 0.2), end: Offset.zero).animate(a),
                  child: child,
                ),
              ),
              child: focus == null
                  ? const SizedBox.shrink()
                  : _PreviewCard(
                      key: ValueKey(focus.id),
                      contact: focus,
                      links: app.neighborsOf(focus.id).length,
                      onOpen: () => pushContactPage(app.navigatorKey.currentState!, focus.id),
                      onClose: () => _onFocus(app, null),
                    ),
            ),
          ),
      ],
    );

    if (!wide) return _withAssistant(context, app, graphStack);

    return _withAssistant(
      context,
      app,
      Row(
        children: [
          Expanded(child: graphStack),
          AnimatedContainer(
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
            width: focus == null ? 0 : 440,
            decoration: BoxDecoration(
              color: context.oc.background,
              border: Border(left: BorderSide(color: context.oc.border)),
            ),
            child: ClipRect(
              child: OverflowBox(
                alignment: Alignment.centerLeft,
                minWidth: 440,
                maxWidth: 440,
                child: focus == null
                    ? const SizedBox.shrink()
                    : SafeArea(
                        left: false,
                        child: ContactDetailView(
                          key: ValueKey(focus.id),
                          contactId: focus.id,
                          embedded: true,
                          onClose: () => _onFocus(app, null),
                          onOpenContact: (id) => _focusAndCenter(app, id),
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _withAssistant(BuildContext context, AppState app, Widget child) {
    final open = app.assistantOpen;
    final size = MediaQuery.sizeOf(context);
    final bottomPad = MediaQuery.paddingOf(context).bottom;
    return Stack(
      children: [
        child,
        Positioned.fill(
          child: IgnorePointer(
            ignoring: !open,
            child: AnimatedOpacity(
              opacity: open ? 1 : 0,
              duration: const Duration(milliseconds: 250),
              child: GestureDetector(
                onTap: () => app.setAssistantOpen(false),
                child: ColoredBox(color: Colors.black.withValues(alpha: context.isDark ? 0.45 : 0.25)),
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(12, 0, 12, bottomPad > 0 ? 8 : 16),
              child: AssistantDock(
                maxWidth: size.width,
                panelHeight: math.min(560.0, size.height - (bottomPad + 80)),
                collapsedStyle: AssistantCollapsedStyle.fab,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _openSearch(BuildContext context, AppState app) async {
    final id = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (_) => _SearchSheet(contacts: app.visibleContacts),
    );
    if (id != null) _focusAndCenter(app, id);
  }

  Future<void> _openShare(BuildContext context, AppState app) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 480),
      builder: (_) => const _ShareTreeSheet(),
    );
  }

  Future<void> _openJoin(BuildContext context, AppState app) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 480),
      builder: (_) => const _JoinTreeSheet(),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.compact,
    required this.contacts,
    required this.onSearch,
    required this.onShare,
    required this.onJoin,
    this.onLeave,
  });

  final bool compact;
  final List<Contact> contacts;
  final VoidCallback onSearch;
  final VoidCallback onShare;
  final VoidCallback onJoin;
  final VoidCallback? onLeave;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final name = (app.username?.trim().isNotEmpty ?? false)
        ? app.username!.trim()
        : (app.userName.trim().isNotEmpty ? app.userName.trim() : '');
    final title = name.isEmpty ? 'Your tree' : "$name's tree";

    final controls = [
      _GlassButton(tooltip: 'Share tree', onTap: onShare, child: const Icon(Icons.qr_code_2_rounded, size: 19)),
      _GlassButton(tooltip: 'Join a tree', onTap: onJoin, child: const Icon(Icons.login_rounded, size: 18)),
      if (onLeave != null)
        _GlassButton(tooltip: 'Leave shared mode', active: true, onTap: onLeave!, child: const Icon(Icons.link_off_rounded, size: 18)),
      _GlassButton(tooltip: 'Find someone', onTap: onSearch, child: const Icon(Icons.search_rounded, size: 19)),
    ];

    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, style: context.tt.headlineSmall),
        const SizedBox(height: 2),
        Text('${contacts.length} ${contacts.length == 1 ? 'person' : 'people'}', style: context.tt.bodySmall),
      ],
    );

    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          titleBlock,
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < controls.length; i++) ...[if (i > 0) const SizedBox(width: 8), controls[i]],
              ],
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: titleBlock),
            const SizedBox(width: 12),
            Flexible(
              child: Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.end, children: controls),
            ),
          ],
        ),
      ],
    );
  }
}

class _GlassButton extends StatelessWidget {
  const _GlassButton({required this.child, required this.onTap, this.tooltip, this.active = false});
  final Widget child;
  final VoidCallback onTap;
  final String? tooltip;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final primary = context.cs.primary;
    final button = Material(
      color: active
          ? primary.withValues(alpha: context.isDark ? 0.25 : 0.12)
          : context.oc.surface.withValues(alpha: 0.92),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: active ? primary.withValues(alpha: 0.4) : context.oc.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: SizedBox(
          height: 40,
          width: 40,
          child: IconTheme(
            data: IconThemeData(color: active ? primary : context.oc.ink),
            child: Center(child: child),
          ),
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

class _OptionMenu<T> extends StatelessWidget {
  const _OptionMenu({
    required this.prefix,
    required this.icon,
    required this.value,
    required this.values,
    required this.label,
    required this.iconOf,
    required this.onSelected,
  });

  final String prefix;
  final IconData icon;
  final T value;
  final List<T> values;
  final String Function(T) label;
  final IconData Function(T) iconOf;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    return PopupMenuButton<T>(
      tooltip: '$prefix by',
      initialValue: value,
      onSelected: onSelected,
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      itemBuilder: (_) => [
        PopupMenuItem<T>(enabled: false, height: 32, child: Text('$prefix by', style: context.tt.labelSmall)),
        for (final v in values)
          PopupMenuItem<T>(
            value: v,
            child: Row(
              children: [
                Icon(iconOf(v), size: 18, color: v == value ? context.cs.primary : oc.muted),
                const SizedBox(width: 12),
                Expanded(child: Text(label(v))),
                if (v == value) Icon(Icons.check_rounded, size: 18, color: context.cs.primary),
              ],
            ),
          ),
      ],
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: oc.surface.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: oc.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: oc.muted),
            const SizedBox(width: 8),
            Text(
              '$prefix: ',
              style: TextStyle(color: oc.muted, fontWeight: FontWeight.w500, fontSize: 13.5),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Text(
                label(value),
                key: ValueKey(value),
                style: TextStyle(color: oc.ink, fontWeight: FontWeight.w600, fontSize: 13.5),
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.expand_more_rounded, size: 18, color: oc.muted),
          ],
        ),
      ),
    );
  }
}

class _ZoomControls extends StatelessWidget {
  const _ZoomControls({required this.controller});
  final GraphViewController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _GlassButton(tooltip: 'Zoom in', onTap: () => controller.zoomBy(1.3), child: const Icon(Icons.add_rounded)),
        const SizedBox(height: 6),
        _GlassButton(
          tooltip: 'Zoom out',
          onTap: () => controller.zoomBy(1 / 1.3),
          child: const Icon(Icons.remove_rounded),
        ),
      ],
    );
  }
}

class _LegendButton extends StatelessWidget {
  const _LegendButton({required this.open, required this.onTap});
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    final accent = Theme.of(context).colorScheme.primary;
    return Tooltip(
      message: open ? 'Hide options' : 'Color, size, and legend',
      child: Material(
        color: open ? accent.withValues(alpha: 0.12) : oc.surface.withValues(alpha: 0.94),
        shape: CircleBorder(side: BorderSide(color: open ? accent.withValues(alpha: 0.4) : oc.border)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox.square(
            dimension: 36,
            child: Icon(Icons.question_mark_rounded, size: 18, color: open ? accent : oc.muted),
          ),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.styler});
  final GraphStyler styler;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final oc = context.oc;
    final entries = styler.legend();
    return Container(
      width: 270,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: oc.surface.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: oc.border),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: context.isDark ? 0.3 : 0.06), blurRadius: 20)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _OptionMenu<ColorBy>(
            prefix: 'Color',
            icon: Icons.palette_outlined,
            value: app.colorBy,
            values: ColorBy.values,
            label: (v) => v.label,
            iconOf: (v) => v.icon,
            onSelected: app.setColorBy,
          ),
          const SizedBox(height: 12),
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topLeft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (styler.colorBy == ColorBy.strength)
                  _GradientScale(
                    colors: [for (var i = 1; i <= 10; i++) AppColors.strength(i)],
                    left: '1 · weak',
                    right: '10 · strongest',
                  )
                else if (styler.colorBy == ColorBy.recency)
                  _GradientScale(
                    colors: [
                      for (final d in [0, 7, 14, 30, 45, 80, 120]) AppColors.recency(d),
                    ],
                    left: 'This week',
                    right: '4+ months',
                  )
                else
                  Wrap(
                    spacing: 10,
                    runSpacing: 6,
                    children: [
                      for (final e in entries.take(10))
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 9,
                              height: 9,
                              decoration: BoxDecoration(color: e.color, shape: BoxShape.circle),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              e.label,
                              style: TextStyle(fontSize: 12, color: oc.ink, fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                    ],
                  ),
                const SizedBox(height: 12),
                Divider(color: oc.border),
                const SizedBox(height: 8),
                _OptionMenu<SizeBy>(
                  prefix: 'Size',
                  icon: Icons.bubble_chart_outlined,
                  value: app.sizeBy,
                  values: SizeBy.values,
                  label: (v) => v.label,
                  iconOf: (v) => v.icon,
                  onSelected: app.setSizeBy,
                ),
                const SizedBox(height: 8),
                _LegendLine(icon: Icons.bubble_chart_outlined, text: styler.sizeCaption),
                const _LegendLine(icon: Icons.linear_scale_rounded, text: 'Closer, thicker line = stronger tie'),
                const _LegendLine(icon: Icons.more_horiz_rounded, text: 'Dashed = they know each other'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GradientScale extends StatelessWidget {
  const _GradientScale({required this.colors, required this.left, required this.right});
  final List<Color> colors;
  final String left;
  final String right;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 10,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            gradient: LinearGradient(colors: colors),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(left, style: context.tt.labelSmall),
            Text(right, style: context.tt.labelSmall),
          ],
        ),
      ],
    );
  }
}

class _LegendLine extends StatelessWidget {
  const _LegendLine({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(width: 20, child: Icon(icon, size: 16, color: context.oc.subtle)),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: context.tt.bodySmall?.copyWith(fontSize: 12))),
        ],
      ),
    );
  }
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({
    super.key,
    required this.contact,
    required this.links,
    required this.onOpen,
    required this.onClose,
  });

  final Contact contact;
  final int links;
  final VoidCallback onOpen;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final c = contact;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
      decoration: BoxDecoration(
        color: context.oc.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.oc.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: context.isDark ? 0.4 : 0.12),
            blurRadius: 30,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ContactAvatar(contact: c, size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.name, style: context.tt.titleMedium),
                    if (c.roleLine.isNotEmpty)
                      Text(
                        c.roleLine,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.tt.bodySmall?.copyWith(color: context.oc.muted),
                      ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onClose,
                icon: Icon(Icons.close_rounded, size: 20, color: context.oc.muted),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              StrengthBadge(value: c.strength),
              Pill(label: c.category.label, icon: c.category.icon, color: AppColors.category[c.category], filled: true),
              Pill(label: links == 1 ? 'Knows 1 person here' : 'Knows $links people here', icon: Icons.hub_outlined),
              if (c.metAt.isNotEmpty) Pill(label: c.metAt, icon: Icons.place_outlined),
            ],
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(onPressed: onOpen, child: const Text('Open profile')),
          ),
        ],
      ),
    );
  }
}

class _SearchSheet extends StatefulWidget {
  const _SearchSheet({required this.contacts});
  final List<Contact> contacts;

  @override
  State<_SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends State<_SearchSheet> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final q = _q.toLowerCase();
    final results =
        widget.contacts
            .where(
              (c) =>
                  q.isEmpty ||
                  c.name.toLowerCase().contains(q) ||
                  c.company.toLowerCase().contains(q) ||
                  c.metAt.toLowerCase().contains(q),
            )
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name));
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                autofocus: true,
                onChanged: (v) => setState(() => _q = v.trim()),
                decoration: const InputDecoration(
                  hintText: 'Find someone on the map',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                itemCount: results.length,
                itemBuilder: (context, i) {
                  final c = results[i];
                  return ListTile(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    leading: ContactAvatar(contact: c, size: 38),
                    title: Text(c.name, style: context.tt.titleSmall),
                    subtitle: Text(c.roleLine, maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: StrengthBadge(value: c.strength, compact: true),
                    onTap: () => Navigator.pop(context, c.id),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SharedModeBanner extends StatelessWidget {
  const _SharedModeBanner({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    final primary = context.cs.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: primary.withValues(alpha: context.isDark ? 0.18 : 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: primary.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(Icons.link_rounded, size: 18, color: primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Shared mode · $label',
              style: context.tt.bodySmall?.copyWith(color: oc.ink, fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _ShareTreeSheet extends StatefulWidget {
  const _ShareTreeSheet();

  @override
  State<_ShareTreeSheet> createState() => _ShareTreeSheetState();
}

class _ShareTreeSheetState extends State<_ShareTreeSheet> {
  String? _token;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _export());
  }

  Future<void> _export() async {
    final app = AppScope.read(context);
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final code = await app.exportPrimaryTree();
      if (!mounted) return;
      setState(() {
        _token = code.token;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = _friendlyNetworkError(error);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    final token = _token;
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 8, 24, 24 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Share your tree', style: context.tt.titleLarge),
          const SizedBox(height: 6),
          Text(
            'Show this one-time code so someone nearby can attach a read-only copy of your network.',
            style: context.tt.bodyMedium?.copyWith(color: oc.muted),
          ),
          const SizedBox(height: 20),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null) ...[
            Text(_error!, style: TextStyle(color: context.cs.error)),
            const SizedBox(height: 16),
            FilledButton(onPressed: _export, child: const Text('Try again')),
          ] else if (token != null) ...[
            Center(
              child: Container(
                width: 180,
                height: 180,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: oc.surfaceHigh,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: oc.border),
                ),
                child: CustomPaint(painter: _ShareCodePainter(token: token, color: oc.ink)),
              ),
            ),
            const SizedBox(height: 18),
            SelectableText(
              token,
              textAlign: TextAlign.center,
              style: context.tt.displaySmall?.copyWith(
                letterSpacing: 6,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: token));
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Share code copied')),
                );
              },
              icon: const Icon(Icons.copy_rounded),
              label: const Text('Copy code'),
            ),
          ],
        ],
      ),
    );
  }
}

class _JoinTreeSheet extends StatefulWidget {
  const _JoinTreeSheet();

  @override
  State<_JoinTreeSheet> createState() => _JoinTreeSheetState();
}

class _JoinTreeSheetState extends State<_JoinTreeSheet> {
  final _controller = TextEditingController();
  String? _error;
  bool _loading = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    final code = _controller.text.trim().toUpperCase();
    if (code.length < 4) {
      setState(() => _error = 'Enter the 6-character share code.');
      return;
    }
    final app = AppScope.read(context);
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await app.joinSharedTree(code);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Attached ${app.activeSharedTree?.label ?? 'shared network'}')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = _friendlyNetworkError(error);
        _loading = false;
      });
    }
  }

  Future<void> _reopen(NetworkTree tree) async {
    final app = AppScope.read(context);
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await app.enterSharedMode(tree);
      if (!mounted) return;
      Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = _friendlyNetworkError(error);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final oc = context.oc;
    final attached = app.trees.where((tree) => !tree.isPrimary).toList();
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 8, 24, 24 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Join a shared tree', style: context.tt.titleLarge),
          const SizedBox(height: 6),
          Text(
            'Enter the code from someone nearby to attach their network as a second cloud.',
            style: context.tt.bodyMedium?.copyWith(color: oc.muted),
          ),
          if (attached.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Already attached', style: context.tt.labelLarge),
            const SizedBox(height: 8),
            for (final tree in attached)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.hub_outlined, color: context.cs.primary),
                title: Text(tree.label),
                subtitle: const Text('Tap to show again'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: _loading ? null : () => _reopen(tree),
              ),
            const Divider(height: 28),
          ] else
            const SizedBox(height: 18),
          TextField(
            controller: _controller,
            autofocus: attached.isEmpty,
            textCapitalization: TextCapitalization.characters,
            textAlign: TextAlign.center,
            style: context.tt.headlineSmall?.copyWith(letterSpacing: 6, fontWeight: FontWeight.w700),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
              LengthLimitingTextInputFormatter(6),
              _UpperCaseFormatter(),
            ],
            decoration: const InputDecoration(hintText: 'ABC123'),
            onSubmitted: (_) => _join(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: TextStyle(color: context.cs.error)),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _loading ? null : _join,
            child: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Attach tree'),
          ),
        ],
      ),
    );
  }
}

class _UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}

class _ShareCodePainter extends CustomPainter {
  _ShareCodePainter({required this.token, required this.color});

  final String token;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const cells = 11;
    final cell = size.shortestSide / cells;
    final paint = Paint()..color = color;
    final seed = token.codeUnits.fold<int>(0, (sum, unit) => (sum * 31 + unit) & 0x7fffffff);
    for (var y = 0; y < cells; y++) {
      for (var x = 0; x < cells; x++) {
        final corner = (x < 3 && y < 3) || (x > cells - 4 && y < 3) || (x < 3 && y > cells - 4);
        final bit = ((seed >> ((x * 3 + y) % 28)) ^ (x * 17 + y * 13)) & 1;
        if (corner || bit == 1) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(x * cell + 1, y * cell + 1, cell - 2, cell - 2),
              const Radius.circular(2),
            ),
            paint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ShareCodePainter oldDelegate) =>
      oldDelegate.token != token || oldDelegate.color != color;
}

String _friendlyNetworkError(Object error) {
  final raw = error.toString().replaceFirst('Bad state: ', '');
  final lower = raw.toLowerCase();
  if (lower.contains('failed to fetch') ||
      lower.contains('clientexception') ||
      lower.contains('xmlhttprequest') ||
      lower.contains('network error')) {
    return 'Could not reach the sharing API. Wait a few seconds for the server to wake up, then try again.';
  }
  return raw;
}
