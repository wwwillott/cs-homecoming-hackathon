import 'package:flutter/material.dart';

import '../navigation.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import 'dashboard_screen.dart';
import 'grow_screen.dart';
import 'network_screen.dart';
import 'people_screen.dart';
import 'settings_sheet.dart';

class _Dest {
  const _Dest(this.tab, this.label, this.icon, this.selectedIcon, [this.shortLabel]);
  final AppTab tab;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final String? shortLabel;
}

String treeTitleFor(AppState app) {
  final name = (app.username?.trim().isNotEmpty ?? false)
      ? app.username!.trim()
      : (app.userName.trim().isNotEmpty ? app.userName.trim() : '');
  if (name.isEmpty) return 'Your tree';
  return "$name's tree";
}

const _destinations = [
  _Dest(AppTab.home, 'Home', Icons.space_dashboard_outlined, Icons.space_dashboard_rounded),
  _Dest(AppTab.people, 'People', Icons.people_alt_outlined, Icons.people_alt_rounded),
  _Dest(AppTab.network, 'Tree', Icons.park_outlined, Icons.park_rounded, 'Tree'),
  _Dest(AppTab.grow, 'Nourish your Network', Icons.park_outlined, Icons.park_rounded, 'Nourish'),
];

class HomeShell extends StatelessWidget {
  const HomeShell({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= Breakpoints.rail;

    final body = _FadeIndexedStack(
      index: app.tab.index,
      children: const [DashboardScreen(), PeopleScreen(), NetworkScreen(), GrowScreen()],
    );

    if (wide) {
      return Scaffold(
        body: Column(
          children: [
            if (app.isSharedMode) const _SharedModeChip(),
            Expanded(
              child: Row(
                children: [
                  _SideNav(extended: width >= Breakpoints.extendedRail),
                  VerticalDivider(width: 1, color: context.oc.border),
                  Expanded(child: body),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      body: Column(
        children: [
          if (app.isSharedMode) const _SharedModeChip(),
          Expanded(child: body),
        ],
      ),
      floatingActionButton: app.tab == AppTab.grow
          ? null
          : const Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                AddContactFab(),
                SizedBox(height: 12),
                CaptureFab(),
              ],
            ),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(border: Border(top: BorderSide(color: context.oc.border))),
        child: NavigationBar(
          selectedIndex: app.tab.index,
          onDestinationSelected: (i) => app.setTab(AppTab.values[i]),
          destinations: [
            for (final d in _destinations)
              NavigationDestination(
                icon: _TabIcon(dest: d, child: Icon(d.icon)),
                selectedIcon: Icon(d.selectedIcon),
                label: d.shortLabel ?? d.label,
              ),
          ],
        ),
      ),
    );
  }
}

class _SharedModeChip extends StatelessWidget {
  const _SharedModeChip();

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final label = app.activeSharedTree?.shortLabel ?? 'shared tree';
    final primary = context.cs.primary;
    return Material(
      color: primary.withValues(alpha: context.isDark ? 0.22 : 0.12),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Row(
            children: [
              Icon(Icons.hub_rounded, size: 18, color: primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Shared with $label · attached tree is read-only',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.tt.labelLarge?.copyWith(color: context.oc.ink),
                ),
              ),
              TextButton(
                onPressed: app.leaveSharedMode,
                child: const Text('Leave'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CaptureFab extends StatelessWidget {
  const CaptureFab({super.key, this.size = 60});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Record a voice recap',
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.4),
              blurRadius: 22,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Material(
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: Ink(
            width: size,
            height: size,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: AppColors.brand,
              ),
            ),
            child: InkWell(
              onTap: () => openCapture(context),
              child: const Icon(Icons.mic_rounded, color: AppColors.mistCream, size: 28),
            ),
          ),
        ),
      ),
    );
  }
}

class _FadeIndexedStack extends StatelessWidget {
  const _FadeIndexedStack({required this.index, required this.children});
  final int index;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        for (var i = 0; i < children.length; i++)
          IgnorePointer(
            ignoring: i != index,
            child: ExcludeFocus(
              excluding: i != index,
              child: ExcludeSemantics(
                excluding: i != index,
                child: AnimatedOpacity(
                  opacity: i == index ? 1 : 0,
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                  child: AnimatedSlide(
                    offset: i == index ? Offset.zero : const Offset(0, 0.012),
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutCubic,
                    child: TickerMode(enabled: i == index, child: children[i]),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _SideNav extends StatelessWidget {
  const _SideNav({required this.extended});
  final bool extended;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final oc = context.oc;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      width: extended ? 248 : 88,
      color: oc.surface,
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: extended ? 16 : 14, vertical: 20),
          child: Column(
            crossAxisAlignment: extended ? CrossAxisAlignment.stretch : CrossAxisAlignment.center,
            children: [
              Row(
                mainAxisAlignment: extended ? MainAxisAlignment.start : MainAxisAlignment.center,
                children: [
                  const OrbitLogo(size: 36),
                  if (extended) ...[
                    const SizedBox(width: 12),
                    Text('Spruce', style: context.tt.titleLarge),
                  ],
                ],
              ),
              const SizedBox(height: 28),
              extended
                  ? _RecordButton(onTap: () => openCapture(context))
                  : const CaptureFab(size: 56),
              const SizedBox(height: 10),
              _AddContactButton(extended: extended),
              const SizedBox(height: 24),
              for (final d in _destinations)
                _NavItem(
                  dest: d.tab == AppTab.network
                      ? _Dest(d.tab, treeTitleFor(app), d.icon, d.selectedIcon, d.shortLabel)
                      : d,
                  extended: extended,
                  selected: app.tab == d.tab,
                  onTap: () => app.setTab(d.tab),
                ),
              const Spacer(),
              _NavItem(
                dest: const _Dest(AppTab.home, 'Settings', Icons.settings_outlined, Icons.settings),
                extended: extended,
                selected: false,
                onTap: () => showSettingsSheet(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecordButton extends StatelessWidget {
  const _RecordButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.3),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: AppColors.brand),
          ),
          child: InkWell(
            onTap: onTap,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Icon(Icons.mic_rounded, color: AppColors.mistCream, size: 22),
                  SizedBox(width: 10),
                  Text(
                    'Record recap',
                    style: TextStyle(color: AppColors.mistCream, fontWeight: FontWeight.w600, fontSize: 15),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AddContactButton extends StatelessWidget {
  const _AddContactButton({required this.extended});
  final bool extended;

  @override
  Widget build(BuildContext context) {
    final primary = context.cs.primary;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: BorderSide(color: primary.withValues(alpha: 0.35), width: 1.2),
    );
    final style = TextStyle(color: primary, fontWeight: FontWeight.w600, fontSize: extended ? 15 : 11.5);
    final child = extended
        ? Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            child: Row(
              children: [
                Icon(Icons.person_add_alt_1_rounded, color: primary, size: 22),
                const SizedBox(width: 10),
                Text('Add contact', style: style),
              ],
            ),
          )
        : SizedBox(
            width: 60,
            height: 56,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.person_add_alt_1_rounded, color: primary, size: 21),
                const SizedBox(height: 2),
                Text('Add', style: style),
              ],
            ),
          );
    final button = Material(
      color: primary.withValues(alpha: context.isDark ? 0.14 : 0.06),
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: () => openEditor(context), child: child),
    );
    return extended ? button : Tooltip(message: 'Add contact', child: button);
  }
}

class AddContactFab extends StatelessWidget {
  const AddContactFab({super.key});

  @override
  Widget build(BuildContext context) {
    final primary = context.cs.primary;
    return Material(
      color: context.oc.surface,
      elevation: 3,
      shadowColor: Colors.black26,
      shape: StadiumBorder(side: BorderSide(color: primary.withValues(alpha: 0.35), width: 1.2)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => openEditor(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.person_add_alt_1_rounded, color: primary, size: 19),
              const SizedBox(width: 7),
              Text('Add', style: TextStyle(color: primary, fontWeight: FontWeight.w600, fontSize: 14)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Adds the "!" to the Home tab while a tree growth is waiting to be watched there.
class _TabIcon extends StatelessWidget {
  const _TabIcon({required this.dest, required this.child});
  final _Dest dest;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final alert = dest == _destinations.first && app.treeGrowthPending && app.tab != AppTab.home;
    return Badge(
      isLabelVisible: alert,
      label: const Text('!', style: TextStyle(fontWeight: FontWeight.w800)),
      backgroundColor: AppColors.amber,
      textColor: const Color(0xFF2A1B00),
      offset: const Offset(8, -6),
      child: child,
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.dest,
    required this.extended,
    required this.selected,
    required this.onTap,
  });

  final _Dest dest;
  final bool extended;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final primary = context.cs.primary;
    final oc = context.oc;
    final content = AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      height: 46,
      width: extended ? double.infinity : 56,
      padding: EdgeInsets.symmetric(horizontal: extended ? 14 : 0),
      decoration: BoxDecoration(
        color: selected ? primary.withValues(alpha: context.isDark ? 0.2 : 0.1) : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisAlignment: extended ? MainAxisAlignment.start : MainAxisAlignment.center,
        children: [
          _TabIcon(
            dest: dest,
            child: Icon(selected ? dest.selectedIcon : dest.icon, size: 22, color: selected ? primary : oc.muted),
          ),
          if (extended) ...[
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                dest.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected ? oc.ink : oc.muted,
                  fontSize: 14.5,
                ),
              ),
            ),
          ],
        ],
      ),
    );
    final item = Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: content,
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: extended ? item : Tooltip(message: dest.label, child: item),
    );
  }
}
