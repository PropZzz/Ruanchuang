import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

import '../services/app_services.dart';
import '../utils/app_strings.dart';
import '../main.dart';
import 'profile_page.dart';

class AuthDialog extends StatefulWidget {
  final VoidCallback onAuthSuccess;

  const AuthDialog({super.key, required this.onAuthSuccess});

  @override
  State<AuthDialog> createState() => _AuthDialogState();
}

class _AuthDialogState extends State<AuthDialog> with TickerProviderStateMixin {
  late TabController _tabController;
  late AnimationController _enterAnimationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  final TextEditingController _accountController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _nicknameController = TextEditingController();

  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // Tab 控制器
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() => _errorMessage = null);
      }
    });

    // 优雅的入场动画
    _enterAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _enterAnimationController, curve: Curves.easeOutCubic),
    );
    _scaleAnimation = Tween<double>(begin: 0.95, end: 1.0).animate(
      CurvedAnimation(parent: _enterAnimationController, curve: Curves.easeOutBack),
    );

    _enterAnimationController.forward();
  }

  @override
  void dispose() {
    _enterAnimationController.dispose();
    _tabController.dispose();
    _accountController.dispose();
    _passwordController.dispose();
    _nicknameController.dispose();
    super.dispose();
  }

  bool _isValidContact(String value) {
    final emailReg = RegExp(r'^[^@]+@[^@]+\.[^@]+$');
    final phoneReg = RegExp(r'^\d{11}$');
    return emailReg.hasMatch(value) || phoneReg.hasMatch(value);
  }

  Future<void> _handleAuth() async {
    final account = _accountController.text.trim();
    final password = _passwordController.text;
    final nickname = _nicknameController.text.trim();
    final isRegister = _tabController.index == 1;

    setState(() => _errorMessage = null);

    if (account.isEmpty) {
      setState(() => _errorMessage = AppStrings.of(context, 'auth_error_empty'));
      return;
    }
    if (!_isValidContact(account)) {
      setState(() => _errorMessage = AppStrings.of(context, 'auth_error_invalid_phone'));
      return;
    }
    if (password.length < 6) {
      setState(() => _errorMessage = '密码长度不能少于 6 位');
      return;
    }
    if (isRegister && nickname.isEmpty) {
      setState(() => _errorMessage = '请填写昵称');
      return;
    }

    setState(() => _isLoading = true);

    try {
      if (isRegister) {
        final success = await AppServices.dataService.registerAccount(
          username: account,
          password: password,
        );
        if (!success) {
          setState(() => _errorMessage = '该手机号/邮箱已被注册');
          return;
        }
        ProfilePage.globalNameOverride = nickname;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppStrings.of(context, 'auth_success_register')),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          );
        }
      } else {
        final success = await AppServices.dataService.login(account, password);
        if (!success) {
          setState(() => _errorMessage = '账号或密码错误');
          return;
        }
      }

      if (mounted) {
        // 登录成功时播放退出动画后回调
        await _enterAnimationController.reverse();
        widget.onAuthSuccess();
      }
    } catch (e) {
      if (mounted) setState(() => _errorMessage = '操作失败，请重试');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showLanguageDialog() {
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(AppStrings.of(context, 'settings_language'), style: const TextStyle(fontWeight: FontWeight.bold)),
        children: [
          SimpleDialogOption(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
            onPressed: () {
              BattleManApp.setLocale(context, const Locale('zh', 'CN'));
              Navigator.pop(ctx);
            },
            child: const Text('简体中文', style: TextStyle(fontSize: 16)),
          ),
          SimpleDialogOption(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
            onPressed: () {
              BattleManApp.setLocale(context, const Locale('en', 'US'));
              Navigator.pop(ctx);
            },
            child: const Text('English', style: TextStyle(fontSize: 16)),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String labelText,
    required IconData icon,
    bool obscureText = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? const Color(0xFFE5E5EA) : const Color(0xFF2D2D2D);
    final fillColor = isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.03);
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: fillColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? Colors.white12 : Colors.black12, width: 1),
      ),
      child: TextField(
        controller: controller,
        enabled: !_isLoading,
        obscureText: obscureText,
        style: TextStyle(color: textColor, fontSize: 16, letterSpacing: obscureText ? 2 : 0),
        decoration: InputDecoration(
          labelText: labelText,
          labelStyle: TextStyle(color: textColor.withOpacity(0.5), fontSize: 14, letterSpacing: 0),
          prefixIcon: Icon(icon, color: textColor.withOpacity(0.4), size: 22),
          border: InputBorder.none,
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: primaryColor.withOpacity(0.7), width: 1.5),
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? const Color(0xFFE5E5EA) : const Color(0xFF2D2D2D);
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30), // 极致模糊背景
        child: Center(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: ScaleTransition(
                scale: _scaleAnimation,
                child: Container(
                  width: MediaQuery.of(context).size.width.clamp(320.0, 400.0),
                  margin: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    // 模拟真实玻璃的材质渐变
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        isDark ? Colors.white.withOpacity(0.1) : Colors.white.withOpacity(0.8),
                        isDark ? Colors.white.withOpacity(0.05) : Colors.white.withOpacity(0.4),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(32),
                    border: Border.all(
                      color: isDark ? Colors.white.withOpacity(0.15) : Colors.white.withOpacity(0.8),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(isDark ? 0.4 : 0.1),
                        blurRadius: 50,
                        spreadRadius: -10,
                        offset: const Offset(0, 20),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 顶部区域：Logo、标题与语言切换
                        Padding(
                          padding: const EdgeInsets.fromLTRB(32, 32, 24, 24),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: primaryColor.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(Icons.auto_awesome, color: primaryColor, size: 28),
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    AppStrings.of(context, 'auth_title'),
                                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                          fontWeight: FontWeight.w800,
                                          color: textColor,
                                          letterSpacing: 0.5,
                                        ),
                                  ),
                                ],
                              ),
                              IconButton(
                                icon: Icon(Icons.language_rounded, color: textColor.withOpacity(0.5)),
                                onPressed: _showLanguageDialog,
                                tooltip: '切换语言',
                                style: IconButton.styleFrom(
                                  backgroundColor: isDark ? Colors.white10 : Colors.black.withOpacity(0.05),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // 定制化分段器 (Segmented TabBar)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: Container(
                            height: 48,
                            decoration: BoxDecoration(
                              color: isDark ? Colors.black.withOpacity(0.2) : Colors.black.withOpacity(0.04),
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: TabBar(
                              controller: _tabController,
                              indicator: BoxDecoration(
                                borderRadius: BorderRadius.circular(24),
                                color: isDark ? Colors.white.withOpacity(0.15) : Colors.white,
                                boxShadow: isDark
                                    ? []
                                    : [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))],
                              ),
                              indicatorSize: TabBarIndicatorSize.tab,
                              dividerColor: Colors.transparent,
                              labelColor: isDark ? Colors.white : Colors.black87,
                              unselectedLabelColor: textColor.withOpacity(0.4),
                              labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                              unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 15),
                              tabs: [
                                Tab(text: AppStrings.of(context, 'auth_tab_login')),
                                Tab(text: AppStrings.of(context, 'auth_tab_register')),
                              ],
                            ),
                          ),
                        ),

                        // 输入表单与按钮区域
                        Padding(
                          padding: const EdgeInsets.all(32),
                          child: AnimatedSize(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeOutCubic,
                            alignment: Alignment.topCenter,
                            child: Column(
                              children: [
                                _buildTextField(
                                  controller: _accountController,
                                  labelText: AppStrings.of(context, 'auth_label_contact'),
                                  icon: CupertinoIcons.person_alt_circle,
                                ),
                                if (_tabController.index == 1) ...[
                                  _buildTextField(
                                    controller: _nicknameController,
                                    labelText: AppStrings.of(context, 'auth_label_name'),
                                    icon: CupertinoIcons.tag_fill,
                                  ),
                                ],
                                _buildTextField(
                                  controller: _passwordController,
                                  labelText: '密码',
                                  icon: CupertinoIcons.lock_shield_fill,
                                  obscureText: true,
                                ),

                                // 错误提示区
                                if (_errorMessage != null) ...[
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8, bottom: 8),
                                    child: Row(
                                      children: [
                                        Icon(CupertinoIcons.exclamationmark_circle_fill, color: Colors.red.shade400, size: 16),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(_errorMessage!, style: TextStyle(color: Colors.red.shade400, fontSize: 13, fontWeight: FontWeight.w500)),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],

                                const SizedBox(height: 24),

                                // 主操作按钮
                                SizedBox(
                                  width: double.infinity,
                                  height: 56,
                                  child: ElevatedButton(
                                    onPressed: _isLoading ? null : _handleAuth,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: primaryColor,
                                      foregroundColor: Colors.white,
                                      elevation: 0,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                                      shadowColor: primaryColor.withOpacity(0.5),
                                    ).copyWith(
                                      elevation: WidgetStateProperty.resolveWith<double>((states) {
                                        if (states.contains(WidgetState.pressed)) return 2;
                                        if (states.contains(WidgetState.disabled)) return 0;
                                        return 8; // 悬浮阴影感
                                      }),
                                    ),
                                    child: _isLoading
                                        ? const SizedBox(
                                            height: 24,
                                            width: 24,
                                            child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                                          )
                                        : Text(
                                            _tabController.index == 0 ? AppStrings.of(context, 'auth_btn_login') : AppStrings.of(context, 'auth_btn_register'),
                                            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, letterSpacing: 1.5),
                                          ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
