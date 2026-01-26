import 'package:flutter/material.dart';
import '../main.dart';
import '../utils/app_strings.dart'; // 1. 引入字典

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 使用字典
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
          const Center(
            child: Padding(
              padding: EdgeInsets.all(8.0),
              child: Text(
                "BattleMan User",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ),
          ),

          const Divider(),

          // ... (雷达图和建议卡片代码保持不变，因为这些通常是用户数据或服务端下发的) ...
          Container(
            height: 200,
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.radar, size: 60, color: Colors.indigo),
                  // 此处如果需要国际化也可以替换，暂且保留演示核心 UI
                  Text(
                    "AI 认知效率模型 (每周更新)",
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),

          // ... (建议卡片代码省略) ...
          const SizedBox(height: 10),

          ListTile(
            leading: const Icon(Icons.watch),
            title: Text(AppStrings.of(context, 'profile_device')),
            trailing: Text(
              AppStrings.of(context, 'profile_connected'),
              style: const TextStyle(color: Colors.green),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.sync),
            title: Text(AppStrings.of(context, 'profile_auth')),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
          ),

          // --- 系统设置 ---
          ListTile(
            leading: const Icon(Icons.settings),
            title: Text(
              AppStrings.of(context, 'settings_title'),
            ), // "系统设置" or "System Settings"
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
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.horizontal(
                  left: Radius.circular(16),
                ),
              ),
              child: Column(
                children: [
                  AppBar(
                    title: Text(
                      AppStrings.of(context, 'settings_title'),
                    ), // 动态标题
                    backgroundColor: Colors.transparent,
                    elevation: 0,
                    foregroundColor: Colors.black,
                    automaticallyImplyLeading: false,
                    actions: [
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                    ],
                  ),
                  const Divider(height: 1),

                  // 更改语言
                  ListTile(
                    leading: const Icon(Icons.language),
                    title: Text(
                      AppStrings.of(context, 'settings_language'),
                    ), // "更改语言" or "Change Language"
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () {
                      _showLanguageDialog(ctx);
                    },
                  ),

                  ListTile(
                    leading: const Icon(Icons.notifications_outlined),
                    title: Text(AppStrings.of(context, 'settings_notify')),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  ),
                  ListTile(
                    leading: const Icon(Icons.dark_mode_outlined),
                    title: Text(AppStrings.of(context, 'settings_dark')),
                    trailing: const Switch(value: false, onChanged: null),
                  ),
                ],
              ),
            ),
          ),
        );
      },
      transitionBuilder: (ctx, anim1, anim2, child) {
        return SlideTransition(
          position: Tween(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: anim1, curve: Curves.easeInOut)),
          child: child,
        );
      },
    );
  }

  void _showLanguageDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(AppStrings.of(context, 'settings_language')), // 动态标题
        children: [
          SimpleDialogOption(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
            onPressed: () {
              BattleManApp.setLocale(context, const Locale('zh', 'CN'));
              Navigator.pop(ctx);
            },
            child: Row(
              children: [
                Text(
                  AppStrings.of(context, 'lang_zh'),
                  style: const TextStyle(fontSize: 16),
                ),
              ],
            ),
          ),
          SimpleDialogOption(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
            onPressed: () {
              BattleManApp.setLocale(context, const Locale('en', 'US'));
              Navigator.pop(ctx);
            },
            child: Row(
              children: [
                Text(
                  AppStrings.of(context, 'lang_en'),
                  style: const TextStyle(fontSize: 16),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
