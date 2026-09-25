// lib/screens/main_screen.dart
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../services/app_services.dart';
import '../ui/app_theme.dart';
import '../utils/app_strings.dart';
import 'auth_dialog.dart';
import 'focus_page.dart';
import 'micro_task_page.dart';
import 'profile_page.dart';
import 'smart_calendar_page.dart';
import 'team_page.dart';
import '../widgets/stitch_mobile_scaffold.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key, this.secondaryPage, this.secondaryTabIndex = 0});

  final Widget? secondaryPage;
  final int secondaryTabIndex;

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  bool _showSecondaryPage = false;
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
    _selectedIndex = widget.secondaryTabIndex
        .clamp(0, _pages.length - 1)
        .toInt();
    _showSecondaryPage = widget.secondaryPage != null;
    if (!_showSecondaryPage) _hydrateCurrentUser();
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
        group: 'nav_group_today',
        icon: Icons.timer_outlined,
        selectedIcon: Icons.timer,
        label: AppStrings.of(context, 'nav_focus'),
      ),
      _ShellDestination(
        id: 'schedule',
        group: 'nav_group_today',
        icon: Icons.calendar_month_outlined,
        selectedIcon: Icons.calendar_month,
        label: AppStrings.of(context, 'nav_schedule'),
      ),
      _ShellDestination(
        id: 'micro',
        group: 'nav_group_plan',
        icon: Icons.bubble_chart_outlined,
        selectedIcon: Icons.bubble_chart,
        label: AppStrings.of(context, 'nav_micro'),
      ),
      _ShellDestination(
        id: 'team',
        group: 'nav_group_collab',
        icon: Icons.group_outlined,
        selectedIcon: Icons.group,
        label: AppStrings.of(context, 'nav_team'),
      ),
      _ShellDestination(
        id: 'profile',
        group: 'nav_group_system',
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
    final pageStack = _showSecondaryPage
        ? widget.secondaryPage!
        : IndexedStack(index: _selectedIndex, children: _pages);

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
                  title: AppStrings.of(context, 'app_title'),
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
    if (index == _selectedIndex && !_showSecondaryPage) return;
    setState(() {
      _selectedIndex = index;
      _showSecondaryPage = false;
    });
  }
}

class _NarrowShell extends StatelessWidget {
  const _NarrowShell({
    super.key,
    required this.title,
    required this.selectedIndex,
    required this.destinations,
    required this.onSelect,
    required this.child,
  });

  final String title;
  final int selectedIndex;
  final List<_ShellDestination> destinations;
  final ValueChanged<int> onSelect;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return StitchMobileScaffold(
      title: title,
      pageLabel: destinations[selectedIndex].label,
      selectedIndex: selectedIndex,
      onSelect: onSelect,
      onNotify: () {},
      onProfile: () => onSelect(destinations.length - 1),
      child: ClipRRect(child: child),
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
          child: Material(
            key: const ValueKey('shell-rail-material'),
            color: Theme.of(context).brightness == Brightness.dark
                ? AppThemeTokens.sidebarDark
                : AppThemeTokens.sidebarLight,
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
                        Image.asset(
                          'stitch/assets/images/a2aaefce0709.png',
                          width: 28,
                          height: 28,
                          fit: BoxFit.contain,
                          semanticLabel: title,
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
                                letterSpacing: 0,
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
                    child: railExpanded
                        ? _GroupedSidebar(
                            key: const ValueKey('shell-rail-expanded'),
                            destinations: destinations,
                            selectedIndex: selectedIndex,
                            onSelect: onSelect,
                          )
                        : NavigationRail(
                            key: ValueKey(
                              compact
                                  ? 'shell-rail-compact'
                                  : 'shell-rail-collapsed',
                            ),
                            backgroundColor: Colors.transparent,
                            extended: false,
                            minWidth: compact ? 88 : 76,
                            labelType: NavigationRailLabelType.none,
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
                                            name ??
                                                AppStrings.of(
                                                  context,
                                                  'nav_signed_out',
                                                ),
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
                            tooltip: AppStrings.of(
                              context,
                              'nav_notifications_reserved',
                            ),
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

class _GroupedSidebar extends StatelessWidget {
  const _GroupedSidebar({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onSelect,
  });

  final List<_ShellDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  static const List<String> _groupOrder = [
    'nav_group_today',
    'nav_group_plan',
    'nav_group_collab',
    'nav_group_system',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final text = theme.textTheme;

    final children = <Widget>[];
    for (final groupKey in _groupOrder) {
      final groupDestinations = <_ShellDestination>[];
      for (final destination in destinations) {
        if (destination.group == groupKey) {
          groupDestinations.add(destination);
        }
      }
      if (groupDestinations.isEmpty) continue;
      children.add(
        Padding(
          key: ValueKey('shell-rail-group-$groupKey'),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
          child: Text(
            AppStrings.of(context, groupKey),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
      for (final destination in groupDestinations) {
        final index = destinations.indexOf(destination);
        children.add(
          _GroupedSidebarItem(
            destination: destination,
            selected: index == selectedIndex,
            onTap: () => onSelect(index),
          ),
        );
      }
    }

    return ListView(padding: EdgeInsets.zero, children: children);
  }
}

class _GroupedSidebarItem extends StatelessWidget {
  const _GroupedSidebarItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final _ShellDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final foreground = selected
        ? AppThemeTokens.selectedNavText
        : scheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Tooltip(
        message: destination.label,
        child: Semantics(
          button: true,
          selected: selected,
          label: destination.label,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: selected ? scheme.primaryContainer : null,
              ),
              child: Row(
                children: [
                  Icon(
                    selected ? destination.selectedIcon : destination.icon,
                    key: ValueKey('shell-rail-${destination.id}-icon'),
                    size: 20,
                    color: foreground,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      destination.label,
                      key: ValueKey('shell-rail-${destination.id}-label'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodyMedium?.copyWith(
                        color: foreground,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
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

class _ShellDestination {
  const _ShellDestination({
    required this.id,
    required this.group,
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final String id;
  final String group;
  final IconData icon;
  final IconData selectedIcon;
  final String label;
}
