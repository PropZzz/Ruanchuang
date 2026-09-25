import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class StitchMobileBottomBar extends StatelessWidget {
  const StitchMobileBottomBar({
    super.key,
    required this.selectedIndex,
    required this.onSelect,
    this.useCupertino = false,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final bool useCupertino;

  static const _items =
      <({String id, String label, IconData icon, IconData selectedIcon})>[
        (
          id: 'focus',
          label: '专注',
          icon: Icons.timer_outlined,
          selectedIcon: Icons.timer_rounded,
        ),
        (
          id: 'schedule',
          label: '日程',
          icon: Icons.calendar_month_outlined,
          selectedIcon: Icons.calendar_month_rounded,
        ),
        (
          id: 'micro',
          label: '微任务',
          icon: Icons.grid_view_outlined,
          selectedIcon: Icons.grid_view_rounded,
        ),
        (
          id: 'team',
          label: '团队',
          icon: Icons.group_outlined,
          selectedIcon: Icons.group_rounded,
        ),
        (
          id: 'profile',
          label: '我的',
          icon: Icons.person_outline_rounded,
          selectedIcon: Icons.person_rounded,
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final Widget navigation = useCupertino
        ? CupertinoTabBar(
            currentIndex: selectedIndex,
            onTap: onSelect,
            backgroundColor: scheme.surface,
            activeColor: scheme.primary,
            inactiveColor: scheme.onSurfaceVariant,
            border: Border(top: BorderSide(color: scheme.outlineVariant)),
            items: [
              for (final item in _items)
                BottomNavigationBarItem(
                  icon: Icon(item.icon, size: 21),
                  activeIcon: Icon(item.selectedIcon, size: 21),
                  label: item.label,
                ),
            ],
          )
        : NavigationBar(
            selectedIndex: selectedIndex,
            onDestinationSelected: onSelect,
            height: 68,
            backgroundColor: scheme.surface,
            indicatorColor: Colors.transparent,
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            destinations: [
              for (final item in _items)
                NavigationDestination(
                  key: ValueKey('shell-nav-${item.id}'),
                  icon: Icon(item.icon, size: 21),
                  selectedIcon: Icon(item.selectedIcon, size: 21),
                  label: item.label,
                ),
            ],
          );
    return KeyedSubtree(
      key: const ValueKey('shell-bottom-capsule'),
      child: KeyedSubtree(
        key: const ValueKey('stitch-mobile-bottom-bar'),
        child: Material(
          key: ValueKey(
            useCupertino ? 'shell-bottom-cupertino' : 'shell-bottom-material',
          ),
          color: scheme.surface,
          borderRadius: BorderRadius.zero,
          child: SafeArea(
            top: false,
            child: Stack(
              children: [
                navigation,
                for (final item in _items)
                  Positioned(
                    left: 0,
                    top: 0,
                    child: SizedBox(
                      key: ValueKey('stitch-mobile-nav-${item.id}'),
                      width: 0,
                      height: 0,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
