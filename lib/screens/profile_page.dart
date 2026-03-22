import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../main.dart';
import '../models/models.dart';
import '../services/app_services.dart';
import '../utils/app_strings.dart';
import 'bluetooth_page.dart';
import 'debug/diagnostics_page.dart';
import 'emotion_page.dart';
import 'goals_page.dart';
import 'integrations_page.dart';
import 'review_page.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  bool _supportsDeviceEntry() {
    if (kIsWeb) return false;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
        return true;
      case TargetPlatform.fuchsia:
        return false;
    }
  }

  String? _deviceSubtitle() {
    if (kIsWeb) {
      return 'Web 预览：无法访问设备。';
    }
    if (!_supportsDeviceEntry()) {
      return '当前平台不支持设备入口。';
    }
    return null;
  }

  void _openDeviceEntry(BuildContext context) {
    if (!_supportsDeviceEntry()) {
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(AppStrings.of(ctx, 'profile_device')),
          content: const Text(
            '当前平台暂不支持设备功能。'
            '请在支持蓝牙的移动端或桌面端设备上打开。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(AppStrings.of(ctx, 'btn_confirm')),
            ),
          ],
        ),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const BluetoothPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final deviceSubtitle = _deviceSubtitle();
    return Scaffold(
      appBar: AppBar(title: Text(AppStrings.of(context, 'profile_title'))),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              theme.colorScheme.primaryContainer.withValues(alpha: 0.22),
              theme.colorScheme.surface,
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1120),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth >= 900;
                  return ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      FutureBuilder<UserProfile>(
                        future: AppServices.dataService.getUserProfile(),
                        builder: (ctx, snap) {
                          final p = snap.data;
                          final name = p?.displayName ?? '时序智配用户';
                          final status = p?.status ?? '';
                          return Card(
                            elevation: 0,
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                children: [
                                  const CircleAvatar(
                                    radius: 30,
                                    child: Icon(Icons.person, size: 30),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          name,
                                          style: const TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        if (status.isNotEmpty)
                                          Text(
                                            status,
                                            style: const TextStyle(color: Colors.grey),
                                          ),
                                      ],
                                    ),
                                  ),
                                  FilledButton.tonalIcon(
                                    onPressed: () => _openSettingsPanel(context),
                                    icon: const Icon(Icons.settings),
                                    label: Text(
                                      AppStrings.of(context, 'settings_title'),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Icon(
                                Icons.radar,
                                size: 36,
                                color: theme.colorScheme.primary,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  AppStrings.of(context, 'profile_model_card'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (isWide)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _sectionCard(
                                context,
                                title: '日常操作',
                                children: [
                                  _profileActionTile(
                                    context,
                                    icon: Icons.watch,
                                    title: AppStrings.of(context, 'profile_device'),
                                    subtitle: deviceSubtitle,
                                    onTap: () => _openDeviceEntry(context),
                                  ),
                                  _profileActionTile(
                                    context,
                                    icon: Icons.sync,
                                    title: AppStrings.of(context, 'profile_auth'),
                                    onTap: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) => const IntegrationsPage(),
                                        ),
                                      );
                                    },
                                  ),
                                  _profileActionTile(
                                    context,
                                    icon: Icons.flag_outlined,
                                    title: AppStrings.of(context, 'goal_title'),
                                    onTap: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) => const GoalsPage(),
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _sectionCard(
                                context,
                                title: '洞察',
                                children: [
                                  _profileActionTile(
                                    context,
                                    icon: Icons.monitor_heart_outlined,
                                    title: AppStrings.of(context, 'emo_title'),
                                    onTap: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) => const EmotionPage(),
                                        ),
                                      );
                                    },
                                  ),
                                  _profileActionTile(
                                    context,
                                    icon: Icons.auto_graph,
                                    title: AppStrings.of(context, 'review_title'),
                                    onTap: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) => const ReviewPage(),
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ],
                        )
                      else ...[
                        _sectionCard(
                          context,
                          title: '日常操作',
                          children: [
                            _profileActionTile(
                              context,
                              icon: Icons.watch,
                              title: AppStrings.of(context, 'profile_device'),
                              subtitle: deviceSubtitle,
                              onTap: () => _openDeviceEntry(context),
                            ),
                            _profileActionTile(
                              context,
                              icon: Icons.sync,
                              title: AppStrings.of(context, 'profile_auth'),
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => const IntegrationsPage(),
                                  ),
                                );
                              },
                            ),
                            _profileActionTile(
                              context,
                              icon: Icons.flag_outlined,
                              title: AppStrings.of(context, 'goal_title'),
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(builder: (_) => const GoalsPage()),
                                );
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _sectionCard(
                          context,
                          title: '洞察',
                          children: [
                            _profileActionTile(
                              context,
                              icon: Icons.monitor_heart_outlined,
                              title: AppStrings.of(context, 'emo_title'),
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => const EmotionPage(),
                                  ),
                                );
                              },
                            ),
                            _profileActionTile(
                              context,
                              icon: Icons.auto_graph,
                              title: AppStrings.of(context, 'review_title'),
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => const ReviewPage(),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionCard(
    BuildContext context, {
    required String title,
    required List<Widget> children,
  }) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            const SizedBox(height: 4),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _profileActionTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle),
      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
      onTap: onTap,
    );
  }

  void _openSettingsPanel(BuildContext context) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '关闭',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (ctx, anim1, anim2) {
        return Align(
          alignment: Alignment.centerRight,
          child: Material(
            elevation: 16,
            borderRadius: const BorderRadius.horizontal(
              left: Radius.circular(16),
            ),
            child: Container(
              width: MediaQuery.of(context).size.width * 0.75,
              height: double.infinity,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.horizontal(
                  left: Radius.circular(16),
                ),
              ),
              child: Column(
                children: [
                  AppBar(
                    title: Text(AppStrings.of(context, 'settings_title')),
                    backgroundColor: Colors.transparent,
                    elevation: 0,
                    foregroundColor: Theme.of(context).colorScheme.onSurface,
                    automaticallyImplyLeading: false,
                    actions: [
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                    ],
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.language),
                    title: Text(AppStrings.of(context, 'settings_language')),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () => _showLanguageDialog(ctx),
                  ),
                  ListTile(
                    leading: const Icon(Icons.notifications_outlined),
                    title: Text(AppStrings.of(context, 'settings_notify')),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  ),
                  ListTile(
                    leading: const Icon(Icons.bug_report_outlined),
                    title: Text(AppStrings.of(context, 'diag_title')),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const DiagnosticsPage()),
                      );
                    },
                  ),
                  ExpansionTile(
                    leading: const Icon(Icons.dark_mode_outlined),
                    title: Builder(
                      builder: (context) {
                        final currentThemeMode = _getCurrentThemeMode(context);
                        String themeModeName;
                        switch (currentThemeMode) {
                          case ThemeMode.system:
                            themeModeName = AppStrings.of(context, 'theme_system');
                            break;
                          case ThemeMode.light:
                            themeModeName = AppStrings.of(context, 'theme_light');
                            break;
                          case ThemeMode.dark:
                            themeModeName = AppStrings.of(context, 'theme_dark');
                            break;
                        }
                        return Text(
                            '${AppStrings.of(context, 'settings_dark')}: $themeModeName');
                      },
                    ),
                    children: [
                      RadioListTile<ThemeMode>(
                        title: Text(AppStrings.of(context, 'theme_system')),
                        value: ThemeMode.system,
                        groupValue: _getCurrentThemeMode(context),
                        onChanged: (value) {
                          if (value != null) {
                            BattleManApp.setThemeMode(context, value);
                          }
                        },
                      ),
                      RadioListTile<ThemeMode>(
                        title: Text(AppStrings.of(context, 'theme_light')),
                        value: ThemeMode.light,
                        groupValue: _getCurrentThemeMode(context),
                        onChanged: (value) {
                          if (value != null) {
                            BattleManApp.setThemeMode(context, value);
                          }
                        },
                      ),
                      RadioListTile<ThemeMode>(
                        title: Text(AppStrings.of(context, 'theme_dark')),
                        value: ThemeMode.dark,
                        groupValue: _getCurrentThemeMode(context),
                        onChanged: (value) {
                          if (value != null) {
                            BattleManApp.setThemeMode(context, value);
                          }
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
      transitionBuilder: (ctx, anim1, anim2, child) {
        return SlideTransition(
          position: Tween(begin: const Offset(1, 0), end: Offset.zero).animate(
            CurvedAnimation(parent: anim1, curve: Curves.easeInOut),
          ),
          child: child,
        );
      },
    );
  }

  ThemeMode _getCurrentThemeMode(BuildContext context) {
    return BattleManApp.getThemeMode(context);
  }

  void _showLanguageDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(AppStrings.of(context, 'settings_language')),
        children: [
          SimpleDialogOption(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
            onPressed: () {
              BattleManApp.setLocale(context, const Locale('zh', 'CN'));
              Navigator.pop(ctx);
            },
            child: Text(
              AppStrings.of(context, 'lang_zh'),
              style: const TextStyle(fontSize: 16),
            ),
          ),
          SimpleDialogOption(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
            onPressed: () {
              BattleManApp.setLocale(context, const Locale('en', 'US'));
              Navigator.pop(ctx);
            },
            child: Text(
              AppStrings.of(context, 'lang_en'),
              style: const TextStyle(fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }
}

