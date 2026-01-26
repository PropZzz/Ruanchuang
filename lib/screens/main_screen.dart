import 'package:flutter/material.dart';
import 'focus_page.dart';
import 'smart_calendar_page.dart';
import 'micro_task_page.dart';
import 'team_page.dart';
import 'profile_page.dart';
import '../utils/app_strings.dart'; // 引入字典

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;

  final List<Widget> _pages = [
    const FocusPage(),
    const SmartCalendarPage(),
    const MicroTaskPage(),
    const TeamPage(),
    const ProfilePage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (int index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        // 使用 AppStrings 动态获取 Label
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.timer_outlined),
            label: AppStrings.of(context, 'nav_focus'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.calendar_month_outlined),
            label: AppStrings.of(context, 'nav_schedule'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.bubble_chart_outlined),
            label: AppStrings.of(context, 'nav_micro'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.group_outlined),
            label: AppStrings.of(context, 'nav_team'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.person_outline),
            label: AppStrings.of(context, 'nav_profile'),
          ),
        ],
      ),
    );
  }
}
