// lib/screens/profile_page.dart
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../main.dart';
import '../models/models.dart';
import '../services/app_services.dart';
import '../utils/app_strings.dart';
import '../utils/mobile_feedback.dart';
import 'bluetooth_page.dart';
import 'debug/diagnostics_page.dart';
import 'emotion_page.dart';
import 'goals_page.dart';
import 'integrations_page.dart';
import 'review_page.dart';
import 'auth_dialog.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  static final ValueNotifier<String?> globalNameNotifier = ValueNotifier<String?>(null);
  static final ValueNotifier<Uint8List?> globalAvatarNotifier = ValueNotifier<Uint8List?>(null);

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final ImagePicker _picker = ImagePicker();

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
            '当前平台暂不支持设备功能。\n请在支持蓝牙的移动端或桌面端设备上打开。',
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
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BluetoothPage()));
  }

  void _showAuthPopup(BuildContext context) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '关闭登录',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 300),
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
  }

  Future<void> _pickAvatar() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );
      if (image != null) {
        final bytes = await image.readAsBytes();
        ProfilePage.globalAvatarNotifier.value = bytes;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('头像修改成功')),
        );
      }
    } catch (e) {
      debugPrint('获取头像失败: $e');
    }
  }

  void _showEditNameDialog() {
    final ctrl = TextEditingController(text: ProfilePage.globalNameNotifier.value ?? '时序智配用户');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('修改昵称', style: TextStyle(fontWeight: FontWeight.bold)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: TextField(
          controller: ctrl,
          decoration: InputDecoration(
            labelText: '新昵称',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          ElevatedButton(
            onPressed: () {
              final newName = ctrl.text.trim();
              if (newName.isNotEmpty) {
                ProfilePage.globalNameNotifier.value = newName;
              }
              Navigator.pop(ctx);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final deviceSubtitle = _deviceSubtitle();

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF2F2F7),
      appBar: AppBar(
        title: Text(AppStrings.of(context, 'profile_title'), style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: AppStrings.of(context, 'settings_title'),
            onPressed: () => _openSettingsPanel(context),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860),
            child: ListView(
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.fromLTRB(16, 8, 16, MediaQuery.of(context).padding.bottom + 100),
              children: [
                _buildUserProfileCard(context),
                const SizedBox(height: 24),
                
                _buildActionGroup(context, children: [
                  _profileActionTile(
                    context,
                    icon: Icons.radar_rounded,
                    iconColor: Colors.blueAccent,
                    title: AppStrings.of(context, 'profile_model_card'),
                    showTrailing: false,
                    onTap: () {},
                  ),
                ]),
                const SizedBox(height: 24),

                Padding(
                  padding: const EdgeInsets.only(left: 16, bottom: 8),
                  child: Text('核心操作', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: theme.colorScheme.onSurface.withOpacity(0.5))),
                ),
                _buildActionGroup(context, children: [
                  _profileActionTile(
                    context,
                    icon: Icons.watch_rounded,
                    iconColor: Colors.teal,
                    title: AppStrings.of(context, 'profile_device'),
                    subtitle: deviceSubtitle,
                    onTap: () => _openDeviceEntry(context),
                  ),
                  _buildDivider(context),
                  _profileActionTile(
                    context,
                    icon: Icons.sync_rounded,
                    iconColor: Colors.orange,
                    title: AppStrings.of(context, 'profile_auth'),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const IntegrationsPage())),
                  ),
                  _buildDivider(context),
                  _profileActionTile(
                    context,
                    icon: Icons.flag_rounded,
                    iconColor: Colors.redAccent,
                    title: AppStrings.of(context, 'goal_title'),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const GoalsPage())),
                  ),
                ]),
                const SizedBox(height: 24),

                Padding(
                  padding: const EdgeInsets.only(left: 16, bottom: 8),
                  child: Text('洞察分析', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: theme.colorScheme.onSurface.withOpacity(0.5))),
                ),
                _buildActionGroup(context, children: [
                  _profileActionTile(
                    context,
                    icon: Icons.monitor_heart_rounded,
                    iconColor: Colors.pinkAccent,
                    title: AppStrings.of(context, 'emo_title'),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EmotionPage())),
                  ),
                  _buildDivider(context),
                  _profileActionTile(
                    context,
                    icon: Icons.auto_graph_rounded,
                    iconColor: Colors.deepPurpleAccent,
                    title: AppStrings.of(context, 'review_title'),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ReviewPage())),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUserProfileCard(BuildContext context) {
    return FutureBuilder<UserProfile>(
      future: AppServices.dataService.getUserProfile(),
      builder: (ctx, snap) {
        final p = snap.data;
        final status = p?.status ?? '';
        return Column(
          children: [
            const SizedBox(height: 16),
            GestureDetector(
              onTap: _pickAvatar,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [Theme.of(context).colorScheme.primary.withOpacity(0.5), Colors.transparent],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    ValueListenableBuilder<Uint8List?>(
                      valueListenable: ProfilePage.globalAvatarNotifier,
                      builder: (context, avatarBytes, child) {
                        return CircleAvatar(
                          radius: 46,
                          backgroundColor: Colors.white,
                          child: CircleAvatar(
                            radius: 42,
                            backgroundColor: const Color(0xFFE5E5EA),
                            backgroundImage: avatarBytes != null ? MemoryImage(avatarBytes) : null,
                            child: avatarBytes == null ? const Icon(Icons.person_rounded, size: 48, color: Colors.grey) : null,
                          ),
                        );
                      },
                    ),
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        shape: BoxShape.circle,
                        border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 2.5),
                      ),
                      child: const Icon(Icons.edit, size: 14, color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: _showEditNameDialog,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: ValueListenableBuilder<String?>(
                      valueListenable: ProfilePage.globalNameNotifier,
                      builder: (context, overrideName, child) {
                        final name = overrideName ?? p?.displayName ?? '时序智配用户';
                        return Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.edit_outlined, size: 18, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5)),
                ],
              ),
            ),
            if (status.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(status, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6), fontSize: 15)),
            ],
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }

  Widget _buildActionGroup(BuildContext context, {required List<Widget> children}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: isDark ? [] : [
          BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(children: children),
    );
  }

  Widget _profileActionTile(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String title,
    String? subtitle,
    bool showTrailing = true,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5))),
                  ],
                ],
              ),
            ),
            if (showTrailing)
              Icon(Icons.chevron_right_rounded, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3)),
          ],
        ),
      ),
    );
  }

  Widget _buildDivider(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 60),
      child: Divider(height: 1, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.05)),
    );
  }

  void _openSettingsPanel(BuildContext context) {
    if (MobileFeedback.isNarrow(context, breakpoint: 760)) {
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => _buildSettingsPanelBody(
          ctx, 
          onClose: () => Navigator.of(ctx).pop(),
          onSwitchAccount: () {
            Navigator.of(ctx).pop();
            _showAuthPopup(context);
          }
        ),
      );
      return;
    }

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
            borderRadius: const BorderRadius.horizontal(left: Radius.circular(24)),
            child: Container(
              width: MediaQuery.of(context).size.width.clamp(360.0, 460.0),
              height: double.infinity,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: const BorderRadius.horizontal(left: Radius.circular(24)),
              ),
              child: _buildSettingsPanelBody(
                ctx,
                onClose: () => Navigator.of(ctx).pop(),
                onSwitchAccount: () {
                  Navigator.of(ctx).pop();
                  _showAuthPopup(context);
                }
              ),
            ),
          ),
        );
      },
      transitionBuilder: (ctx, anim1, anim2, child) {
        return SlideTransition(
          position: Tween(begin: const Offset(1, 0), end: Offset.zero).animate(CurvedAnimation(parent: anim1, curve: Curves.easeOutCubic)),
          child: child,
        );
      },
    );
  }

  ThemeMode _getCurrentThemeMode(BuildContext context) {
    return BattleManApp.getThemeMode(context);
  }

  Widget _buildSettingsPanelBody(BuildContext context, {required VoidCallback onClose, required VoidCallback onSwitchAccount}) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const SizedBox(width: 48), 
                Expanded(
                  child: Text(
                    AppStrings.of(context, 'settings_title'), 
                    textAlign: TextAlign.center,
                    maxLines: 1, 
                    overflow: TextOverflow.ellipsis, 
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)
                  )
                ),
                IconButton(
                  icon: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(color: theme.colorScheme.onSurface.withOpacity(0.1), shape: BoxShape.circle),
                    child: const Icon(Icons.close, size: 20),
                  ),
                  onPressed: onClose,
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              physics: const BouncingScrollPhysics(),
              children: [
                _buildActionGroup(context, children: [
                  _profileActionTile(context, icon: Icons.switch_account_rounded, iconColor: Colors.blueAccent, title: AppStrings.of(context, 'profile_switch_account'), onTap: onSwitchAccount),
                  _buildDivider(context),
                  _profileActionTile(context, icon: Icons.language_rounded, iconColor: Colors.teal, title: AppStrings.of(context, 'settings_language'), onTap: () => _showLanguageDialog(context)),
                  _buildDivider(context),
                  _profileActionTile(context, icon: Icons.notifications_rounded, iconColor: Colors.orange, title: AppStrings.of(context, 'settings_notify'), onTap: (){}),
                ]),
                const SizedBox(height: 24),
                _buildActionGroup(context, children: [
                  ExpansionTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: Colors.deepPurpleAccent.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
                      child: const Icon(Icons.dark_mode_rounded, color: Colors.deepPurpleAccent, size: 22),
                    ),
                    title: Builder(
                      builder: (context) {
                        final currentThemeMode = _getCurrentThemeMode(context);
                        String themeModeName = currentThemeMode == ThemeMode.system ? AppStrings.of(context, 'theme_system') : currentThemeMode == ThemeMode.light ? AppStrings.of(context, 'theme_light') : AppStrings.of(context, 'theme_dark');
                        return Text('${AppStrings.of(context, 'settings_dark')}: $themeModeName', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w500));
                      },
                    ),
                    shape: const Border(),
                    children: [
                      RadioGroup<ThemeMode>(
                        groupValue: _getCurrentThemeMode(context),
                        onChanged: (value) { if (value != null) BattleManApp.setThemeMode(context, value); },
                        child: Column(
                          children: [
                            RadioListTile<ThemeMode>(title: Text(AppStrings.of(context, 'theme_system')), value: ThemeMode.system),
                            RadioListTile<ThemeMode>(title: Text(AppStrings.of(context, 'theme_light')), value: ThemeMode.light),
                            RadioListTile<ThemeMode>(title: Text(AppStrings.of(context, 'theme_dark')), value: ThemeMode.dark),
                          ],
                        ),
                      ),
                    ],
                  ),
                ]),
                const SizedBox(height: 24),
                _buildActionGroup(context, children: [
                  _profileActionTile(
                    context, icon: Icons.bug_report_rounded, iconColor: Colors.grey, title: AppStrings.of(context, 'diag_title'), 
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DiagnosticsPage())),
                  ),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showLanguageDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(AppStrings.of(context, 'settings_language'), style: const TextStyle(fontWeight: FontWeight.bold)),
        children: [
          SimpleDialogOption(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
            onPressed: () { BattleManApp.setLocale(context, const Locale('zh', 'CN')); Navigator.pop(ctx); },
            child: Text(AppStrings.of(context, 'lang_zh'), style: const TextStyle(fontSize: 16)),
          ),
          SimpleDialogOption(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
            onPressed: () { BattleManApp.setLocale(context, const Locale('en', 'US')); Navigator.pop(ctx); },
            child: Text(AppStrings.of(context, 'lang_en'), style: const TextStyle(fontSize: 16)),
          ),
        ],
      ),
    );
  }
}