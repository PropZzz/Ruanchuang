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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppStrings.of(context, 'profile_title'))),
      body: ListView(
        children: [
          const SizedBox(height: 20),
          const Center(
            child: CircleAvatar(
              radius: 40,
              child: Icon(Icons.person, size: 40),
            ),
          ),
          FutureBuilder<UserProfile>(
            future: AppServices.dataService.getUserProfile(),
            builder: (ctx, snap) {
              final p = snap.data;
              final name = p?.displayName ?? 'BattleMan User';
              final status = p?.status ?? '';
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      name,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (status.isNotEmpty)
                    Text(status, style: const TextStyle(color: Colors.grey)),
                ],
              );
            },
          ),
          const Divider(),
          Container(
            height: 200,
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceVariant,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.radar,
                      size: 60, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(height: 6),
                  Text(
                    AppStrings.of(context, 'profile_model_card'),
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.watch),
            title: Text(AppStrings.of(context, 'profile_device')),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const BluetoothPage()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.sync),
            title: Text(AppStrings.of(context, 'profile_auth')),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const IntegrationsPage()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.flag_outlined),
            title: Text(AppStrings.of(context, 'goal_title')),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const GoalsPage()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.monitor_heart_outlined),
            title: Text(AppStrings.of(context, 'emo_title')),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const EmotionPage()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.auto_graph),
            title: Text(AppStrings.of(context, 'review_title')),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ReviewPage()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.settings),
            title: Text(AppStrings.of(context, 'settings_title')),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () => _openSettingsPanel(context),
          ),
        ],
      ),
    );
  }

  void _openSettingsPanel(BuildContext context) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
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

