import 'dart:ui';

import 'package:flutter/material.dart';

import '../utils/app_strings.dart';
import 'focus_page.dart';
import 'micro_task_page.dart';
import 'profile_page.dart';
import 'smart_calendar_page.dart';
import 'team_page.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  static const double _wideBreakpoint = 1024;
  int _selectedIndex = 0;

  final List<Widget> _pages = const [
    FocusPage(),
    SmartCalendarPage(),
    MicroTaskPage(),
    TeamPage(),
    ProfilePage(),
  ];

  List<_ShellDestination> _destinations(BuildContext context) {
    return [
      _ShellDestination(
        icon: Icons.timer_outlined,
        selectedIcon: Icons.timer,
        label: AppStrings.of(context, 'nav_focus'),
      ),
      _ShellDestination(
        icon: Icons.calendar_month_outlined,
        selectedIcon: Icons.calendar_month,
        label: AppStrings.of(context, 'nav_schedule'),
      ),
      _ShellDestination(
        icon: Icons.bubble_chart_outlined,
        selectedIcon: Icons.bubble_chart,
        label: AppStrings.of(context, 'nav_micro'),
      ),
      _ShellDestination(
        icon: Icons.group_outlined,
        selectedIcon: Icons.group,
        label: AppStrings.of(context, 'nav_team'),
      ),
      _ShellDestination(
        icon: Icons.person_outline,
        selectedIcon: Icons.person,
        label: AppStrings.of(context, 'nav_profile'),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= _wideBreakpoint;
    final destinations = _destinations(context);
    final active = destinations[_selectedIndex];
    final pageStack = IndexedStack(index: _selectedIndex, children: _pages);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        top: false, // 让内容可以延伸至顶部
        bottom: false,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: isWide
              ? _WideShell(
                  key: const ValueKey('wide-shell'),
                  title: AppStrings.of(context, 'app_title'),
                  activeLabel: active.label,
                  selectedIndex: _selectedIndex,
                  destinations: destinations,
                  onSelect: _onSelect,
                  child: pageStack,
                )
              : _NarrowShell(
                  key: const ValueKey('narrow-shell'),
                  selectedIndex: _selectedIndex,
                  destinations: destinations,
                  onSelect: _onSelect,
                  child: pageStack,
                ),
        ),
      ),
    );
  }

  void _onSelect(int index) {
    if (index == _selectedIndex) return;
    setState(() {
      _selectedIndex = index;
    });
  }
}

class _NarrowShell extends StatelessWidget {
  const _NarrowShell({
    super.key,
    required this.selectedIndex,
    required this.destinations,
    required this.onSelect,
    required this.child,
  });

  final int selectedIndex;
  final List<_ShellDestination> destinations;
  final ValueChanged<int> onSelect;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Stack(
      children: [
        // 主内容区
        Positioned.fill(child: child),
        // 底部悬浮导航栏
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: ClipRRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface.withOpacity(
                    isDark ? 0.75 : 0.85,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(isDark ? 0.2 : 0.03),
                      blurRadius: 30,
                      offset: const Offset(0, -10),
                    ),
                  ],
                ),
                child: SafeArea(
                  top: false,
                  child: NavigationBar(
                    backgroundColor: Colors.transparent,
                    elevation: 0,
                    height: 56,
                    selectedIndex: selectedIndex,
                    onDestinationSelected: onSelect,
                    destinations: [
                      for (final d in destinations)
                        NavigationDestination(
                          icon: Icon(d.icon, size: 22),
                          selectedIcon: Icon(d.selectedIcon, size: 22),
                          label: d.label,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _WideShell extends StatelessWidget {
  const _WideShell({
    super.key,
    required this.title,
    required this.activeLabel,
    required this.selectedIndex,
    required this.destinations,
    required this.onSelect,
    required this.child,
  });

  final String title;
  final String activeLabel;
  final int selectedIndex;
  final List<_ShellDestination> destinations;
  final ValueChanged<int> onSelect;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final railExtended = MediaQuery.sizeOf(context).width >= 1220;
    final isDark = theme.brightness == Brightness.dark;

    return Row(
      children: [
        // 左侧侧边栏 (极其干净，无边框)
        Container(
          width: railExtended ? 260 : 100,
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.2 : 0.02),
                blurRadius: 40,
                offset: const Offset(10, 0),
              ),
            ],
          ),
          child: SafeArea(
            right: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    railExtended ? 32 : 0,
                    40,
                    0,
                    40,
                  ),
                  child: Row(
                    mainAxisAlignment: railExtended
                        ? MainAxisAlignment.start
                        : MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      if (railExtended) ...[
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Expanded(
                  child: NavigationRail(
                    backgroundColor: Colors.transparent,
                    selectedIndex: selectedIndex,
                    onDestinationSelected: onSelect,
                    extended: railExtended,
                    minExtendedWidth: 260,
                    labelType: railExtended
                        ? NavigationRailLabelType.none
                        : NavigationRailLabelType.selected,
                    destinations: [
                      for (final d in destinations)
                        NavigationRailDestination(
                          icon: Icon(d.icon),
                          selectedIcon: Icon(d.selectedIcon),
                          label: Text(d.label),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        // 右侧主内容区
        Expanded(
          child: SafeArea(
            left: false,
            bottom: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 顶部状态提示
                Padding(
                  padding: const EdgeInsets.fromLTRB(40, 40, 40, 20),
                  child: Text(
                    activeLabel,
                    style: text.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontSize: 28,
                    ),
                  ),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(40),
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        color: theme.scaffoldBackgroundColor,
                      ),
                      child: child,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ShellDestination {
  const _ShellDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}
