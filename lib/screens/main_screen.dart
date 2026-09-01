// lib/screens/main_screen.dart
import 'package:flutter/material.dart';

import '../services/app_services.dart';
import '../theme/app_theme.dart';
import '../utils/app_strings.dart';
import '../utils/mobile_feedback.dart';
import '../widgets/workspace_status_bar.dart';
import 'auth_dialog.dart';
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
  // Keep the logical-width breakpoint aligned with existing Flutter test and
  // desktop behavior; phones remain below this threshold in production.
  static const double _wideBreakpoint = 1024;
  int _selectedIndex = 0;
  bool _startupAuthPromptShown = false;

  final List<Widget> _pages = const [
    FocusPage(),
    SmartCalendarPage(),
    MicroTaskPage(),
    TeamPage(),
    ProfilePage(),
  ];

  @override
  void initState() {
    super.initState();
    _hydrateCurrentUser();
  }

  Future<void> _hydrateCurrentUser() async {
    if (ProfilePage.globalNameNotifier.value != null) return;
    try {
      final user = await AppServices.dataService.getCurrentUser();
      if (!mounted) return;
      if (user == null) {
        _showStartupAuthPopup();
        return;
      }
      ProfilePage.globalNameNotifier.value = user.displayName;
    } catch (_) {
      // Remote auth may be unavailable during local-first use; keep the shell usable.
      if (mounted) {
        _showStartupAuthPopup();
      }
    }
  }

  void _showStartupAuthPopup() {
    if (_startupAuthPromptShown ||
        ProfilePage.globalNameNotifier.value != null) {
      return;
    }
    _startupAuthPromptShown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || ProfilePage.globalNameNotifier.value != null) return;
      showGeneralDialog(
        context: context,
        barrierDismissible: true,
        barrierLabel: '关闭登录',
        barrierColor: Colors.transparent,
        transitionDuration: AppMotion.resolve(context, AppMotion.enter),
        pageBuilder: (ctx, anim1, anim2) {
          return AuthDialog(
            onAuthSuccess: () {
              Navigator.of(ctx).pop();
            },
          );
        },
        transitionBuilder: (ctx, anim1, anim2, child) {
          return FadeTransition(opacity: anim1, child: child);
        },
      );
    });
  }

  List<_ShellDestination> _destinations(BuildContext context) {
    return [
      _ShellDestination(
        id: 'focus',
        icon: Icons.timer_outlined,
        selectedIcon: Icons.timer,
        label: AppStrings.of(context, 'nav_focus'),
      ),
      _ShellDestination(
        id: 'schedule',
        icon: Icons.calendar_month_outlined,
        selectedIcon: Icons.calendar_month,
        label: AppStrings.of(context, 'nav_schedule'),
      ),
      _ShellDestination(
        id: 'micro',
        icon: Icons.bubble_chart_outlined,
        selectedIcon: Icons.bubble_chart,
        label: AppStrings.of(context, 'nav_micro'),
      ),
      _ShellDestination(
        id: 'team',
        icon: Icons.group_outlined,
        selectedIcon: Icons.group,
        label: AppStrings.of(context, 'nav_team'),
      ),
      _ShellDestination(
        id: 'profile',
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
        top: false,
        bottom: false,
        child: AnimatedSwitcher(
          duration: AppMotion.resolve(context, AppMotion.enter),
          reverseDuration: AppMotion.resolve(context, AppMotion.exit),
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
                  brand: AppStrings.of(context, 'app_title'),
                  activeLabel: active.label,
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
    required this.brand,
    required this.activeLabel,
    required this.selectedIndex,
    required this.destinations,
    required this.onSelect,
    required this.child,
  });

  final String brand;
  final String activeLabel;
  final int selectedIndex;
  final List<_ShellDestination> destinations;
  final ValueChanged<int> onSelect;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final compactLabels = MobileFeedback.isNarrow(context, breakpoint: 420);

    return Column(
      children: [
        WorkspaceStatusBar(
          brand: brand,
          title: activeLabel,
          compact: true,
          onSettings: () => onSelect(4),
        ),
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: Padding(
                  padding: EdgeInsets.only(
                    bottom: 92 + MediaQuery.paddingOf(context).bottom,
                  ),
                  child: ClipRRect(child: child),
                ),
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: 10 + MediaQuery.paddingOf(context).bottom,
                child: Material(
                  key: const ValueKey('shell-floating-navigation'),
                  color: theme.colorScheme.surface.withValues(alpha: 0.96),
                  elevation: 7,
                  shadowColor: Colors.black.withValues(
                    alpha: theme.brightness == Brightness.dark ? 0.28 : 0.14,
                  ),
                  shape: const StadiumBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: SizedBox(
                    height: compactLabels ? 68 : 72,
                    child: NavigationBar(
                      backgroundColor: Colors.transparent,
                      elevation: 0,
                      labelBehavior: compactLabels
                          ? NavigationDestinationLabelBehavior.onlyShowSelected
                          : NavigationDestinationLabelBehavior.alwaysShow,
                      selectedIndex: selectedIndex,
                      onDestinationSelected: onSelect,
                      destinations: [
                        for (final d in destinations)
                          NavigationDestination(
                            key: ValueKey('shell-nav-${d.id}'),
                            icon: Icon(d.icon, size: compactLabels ? 20 : 22),
                            selectedIcon: Icon(
                              d.selectedIcon,
                              size: compactLabels ? 20 : 22,
                            ),
                            label: d.label,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
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
    return Row(
      children: [
        Container(
          width: railExtended ? 260 : 100,
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border(right: BorderSide(color: theme.colorScheme.outline)),
          ),
          child: SafeArea(
            right: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    railExtended ? 24 : 0,
                    24,
                    railExtended ? 24 : 0,
                    24,
                  ),
                  child: Row(
                    mainAxisAlignment: railExtended
                        ? MainAxisAlignment.start
                        : MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.schedule_rounded,
                          size: 17,
                          color: Colors.white,
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
                              letterSpacing: 0,
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
                          icon: Icon(
                            d.icon,
                            key: ValueKey('shell-rail-${d.id}-icon'),
                          ),
                          selectedIcon: Icon(
                            d.selectedIcon,
                            key: ValueKey('shell-rail-${d.id}-selected-icon'),
                          ),
                          label: Text(d.label),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: SafeArea(
            left: false,
            bottom: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.zero,
                  child: WorkspaceStatusBar(
                    brand: title,
                    title: activeLabel,
                    compact: !railExtended,
                    onSettings: () => onSelect(4),
                  ),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(14),
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
    required this.id,
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final String id;
  final IconData icon;
  final IconData selectedIcon;
  final String label;
}
