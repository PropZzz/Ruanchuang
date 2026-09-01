// lib/screens/main_screen.dart
import 'package:flutter/material.dart';

import '../services/app_services.dart';
import '../ui/app_theme.dart';
import '../utils/app_strings.dart';
import '../widgets/glass_surface.dart';
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
  int _selectedIndex = 0;
  bool _railExpanded = true;
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
    final width = MediaQuery.sizeOf(context).width;
    final isWide = width >= AppTheme.compactShellBreakpoint;
    final isDesktop = width >= AppTheme.shellBreakpoint;
    final destinations = _destinations(context);
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
                  selectedIndex: _selectedIndex,
                  destinations: destinations,
                  onSelect: _onSelect,
                  compact: !isDesktop,
                  railExpanded: isDesktop && _railExpanded,
                  onToggleRail: () {
                    setState(() {
                      _railExpanded = !_railExpanded;
                    });
                  },
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
    return Column(
      children: [
        Expanded(child: ClipRRect(child: child)),
        Padding(
          key: const ValueKey('shell-bottom-capsule'),
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          child: GlassSurface(
            key: const ValueKey('shell-bottom-material'),
            level: AppMaterialLevel.chrome,
            borderRadius: BorderRadius.circular(24),
            opacity: 0.9,
            padding: EdgeInsets.zero,
            showShadow: true,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8.0,
                  vertical: 4.0,
                ),
                child: NavigationBar(
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  height: null,
                  labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
                  selectedIndex: selectedIndex,
                  onDestinationSelected: onSelect,
                  destinations: [
                    for (final d in destinations)
                      NavigationDestination(
                        key: ValueKey('shell-nav-${d.id}'),
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
      ],
    );
  }
}

class _WideShell extends StatelessWidget {
  const _WideShell({
    super.key,
    required this.title,
    required this.selectedIndex,
    required this.destinations,
    required this.onSelect,
    required this.railExpanded,
    required this.onToggleRail,
    required this.child,
    this.compact = false,
  });

  final String title;
  final int selectedIndex;
  final List<_ShellDestination> destinations;
  final ValueChanged<int> onSelect;
  final bool railExpanded;
  final VoidCallback onToggleRail;
  final Widget child;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final text = theme.textTheme;
    final profileIndex = destinations.indexWhere((d) => d.id == 'profile');
    final railWidth = compact ? 88.0 : (railExpanded ? 260.0 : 76.0);
    final railToggleLabel = AppStrings.of(
      context,
      railExpanded ? 'nav_rail_collapse' : 'nav_rail_expand',
    );

    return Row(
      children: [
        SizedBox(
          width: railWidth,
          child: GlassSurface(
            key: const ValueKey('shell-rail-material'),
            level: AppMaterialLevel.chrome,
            borderRadius: BorderRadius.zero,
            padding: EdgeInsets.zero,
            showShadow: false,
            child: SafeArea(
              right: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      railExpanded ? 20 : 0,
                      24,
                      railExpanded ? 20 : 0,
                      12,
                    ),
                    child: Row(
                      mainAxisAlignment: railExpanded
                          ? MainAxisAlignment.start
                          : MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: scheme.primary,
                          ),
                        ),
                        if (railExpanded) ...[
                          const SizedBox(width: 12),
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
                  if (!compact)
                    Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: railExpanded ? 12 : 14,
                        vertical: 4,
                      ),
                      child: Tooltip(
                        message: railToggleLabel,
                        child: IconButton(
                          key: const ValueKey('shell-rail-toggle'),
                          onPressed: onToggleRail,
                          icon: Icon(
                            railExpanded
                                ? Icons.chevron_left
                                : Icons.chevron_right,
                          ),
                        ),
                      ),
                    ),
                  Expanded(
                    child: NavigationRail(
                      key: ValueKey(
                        compact
                            ? 'shell-rail-compact'
                            : railExpanded
                            ? 'shell-rail-expanded'
                            : 'shell-rail-collapsed',
                      ),
                      backgroundColor: Colors.transparent,
                      extended: railExpanded,
                      minWidth: compact ? 88 : 76,
                      minExtendedWidth: 260,
                      labelType: railExpanded
                          ? null
                          : NavigationRailLabelType.none,
                      selectedIndex: selectedIndex,
                      onDestinationSelected: onSelect,
                      destinations: [
                        for (final destination in destinations)
                          NavigationRailDestination(
                            icon: Icon(
                              destination.icon,
                              key: ValueKey(
                                'shell-rail-${destination.id}-icon',
                              ),
                            ),
                            selectedIcon: Icon(
                              destination.selectedIcon,
                              key: ValueKey(
                                'shell-rail-${destination.id}-selected-icon',
                              ),
                            ),
                            label: Text(
                              destination.label,
                              key: ValueKey(
                                'shell-rail-${destination.id}-label',
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (railExpanded)
                    Container(
                      decoration: BoxDecoration(
                        border: Border(top: BorderSide(color: scheme.outline)),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              borderRadius: BorderRadius.circular(6),
                              onTap: profileIndex >= 0
                                  ? () => onSelect(profileIndex)
                                  : null,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 8,
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.person_outline,
                                      size: 20,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: ValueListenableBuilder<String?>(
                                        valueListenable:
                                            ProfilePage.globalNameNotifier,
                                        builder: (context, name, _) {
                                          return Text(
                                            name ?? '未登录',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: text.bodySmall?.copyWith(
                                              color: scheme.onSurfaceVariant,
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.notifications_none,
                              size: 20,
                            ),
                            tooltip: '通知',
                            color: scheme.onSurfaceVariant,
                            onPressed: null,
                          ),
                          IconButton(
                            icon: const Icon(Icons.settings_outlined, size: 20),
                            tooltip: '设置',
                            color: scheme.onSurfaceVariant,
                            onPressed: profileIndex >= 0
                                ? () => onSelect(profileIndex)
                                : null,
                          ),
                        ],
                      ),
                    )
                  else
                    Container(
                      decoration: BoxDecoration(
                        border: Border(top: BorderSide(color: scheme.outline)),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        children: [
                          IconButton(
                            tooltip: '我的',
                            color: scheme.onSurfaceVariant,
                            icon: const Icon(Icons.person_outline, size: 20),
                            onPressed: profileIndex >= 0
                                ? () => onSelect(profileIndex)
                                : null,
                          ),
                          IconButton(
                            icon: const Icon(Icons.settings_outlined, size: 20),
                            tooltip: '设置',
                            color: scheme.onSurfaceVariant,
                            onPressed: profileIndex >= 0
                                ? () => onSelect(profileIndex)
                                : null,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: SafeArea(
            left: false,
            bottom: false,
            child: Container(
              color: theme.scaffoldBackgroundColor,
              child: child,
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
