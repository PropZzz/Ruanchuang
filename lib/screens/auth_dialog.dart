import 'dart:ui';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

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
  final TextEditingController _confirmPasswordController = TextEditingController(); 
  final TextEditingController _nicknameController = TextEditingController();

  final FocusNode _accountFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();
  final FocusNode _confirmPasswordFocus = FocusNode(); 
  final FocusNode _nicknameFocus = FocusNode();

  bool _isLoading = false;
  String? _errorMessage;

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  Uint8List? _avatarBytes;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {
          _errorMessage = null;
          _passwordController.clear();
          _confirmPasswordController.clear();
        });
      }
    });

    _enterAnimationController = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _enterAnimationController, curve: Curves.easeOutCubic));
    _scaleAnimation = Tween<double>(begin: 0.90, end: 1.0).animate(CurvedAnimation(parent: _enterAnimationController, curve: Curves.easeOutBack));

    _enterAnimationController.forward();
  }

  @override
  void dispose() {
    _enterAnimationController.dispose();
    _tabController.dispose();
    _accountController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _nicknameController.dispose();
    _accountFocus.dispose();
    _passwordFocus.dispose();
    _confirmPasswordFocus.dispose();
    _nicknameFocus.dispose();
    super.dispose();
  }

  bool _isValidContact(String value) {
    final emailReg = RegExp(r'^[^@]+@[^@]+\.[^@]+$');
    final phoneReg = RegExp(r'^\d{11}$');
    return emailReg.hasMatch(value) || phoneReg.hasMatch(value);
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
        setState(() {
          _avatarBytes = bytes;
        });
      }
    } catch (e) {
      debugPrint('获取头像失败: $e');
    }
  }

  Future<void> _handleAuth() async {
    final account = _accountController.text.trim();
    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;
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
    if (isRegister) {
      if (nickname.isEmpty) {
        setState(() => _errorMessage = '请填写昵称');
        return;
      }
      if (password != confirmPassword) {
        setState(() => _errorMessage = '两次输入的密码不一致，请检查');
        return;
      }
    }

    setState(() => _isLoading = true);
    FocusScope.of(context).unfocus(); 

    try {
      if (isRegister) {
        final success = await AppServices.dataService.registerAccount(username: account, password: password);
        if (!success) {
          setState(() => _errorMessage = '该手机号/邮箱已被注册');
          return;
        }
        ProfilePage.globalNameNotifier.value = nickname; 
        ProfilePage.globalAvatarNotifier.value = _avatarBytes; 

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
        ProfilePage.globalNameNotifier.value = account; 
        ProfilePage.globalAvatarNotifier.value = null; 
      }

      if (mounted) {
        await _enterAnimationController.reverse();
        widget.onAuthSuccess();
      }
    } catch (e) {
      if (mounted) setState(() => _errorMessage = '操作失败，请重试');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // 新增：处理游客登录的逻辑
  Future<void> _handleGuestLogin() async {
    setState(() => _isLoading = true);
    FocusScope.of(context).unfocus(); 

    // 模拟轻微加载延迟，提升交互质感
    await Future.delayed(const Duration(milliseconds: 600));

    // 为游客分配一个带有随机编号的默认昵称，并且强制清空自定义头像
    final isZh = Localizations.localeOf(context).languageCode.startsWith('zh');
    final guestId = DateTime.now().millisecondsSinceEpoch.toString().substring(9);
    ProfilePage.globalNameNotifier.value = isZh ? '游客_$guestId' : 'Guest_$guestId';
    ProfilePage.globalAvatarNotifier.value = null;

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isZh ? '已作为游客身份进入' : 'Logged in as guest'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      await _enterAnimationController.reverse();
      widget.onAuthSuccess();
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
            onPressed: () { BattleManApp.setLocale(context, const Locale('zh', 'CN')); Navigator.pop(ctx); },
            child: const Text('简体中文', style: TextStyle(fontSize: 16)),
          ),
          SimpleDialogOption(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
            onPressed: () { BattleManApp.setLocale(context, const Locale('en', 'US')); Navigator.pop(ctx); },
            child: const Text('English', style: TextStyle(fontSize: 16)),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required FocusNode focusNode,
    FocusNode? nextFocusNode,
    required String labelText,
    required IconData icon,
    bool isPassword = false,
    bool obscureText = false,
    VoidCallback? onToggleObscure,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? const Color(0xFFE5E5EA) : const Color(0xFF2D2D2D);
    final fillColor = isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.03);
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: fillColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.08), width: 1),
      ),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        enabled: !_isLoading,
        obscureText: obscureText,
        textInputAction: nextFocusNode != null ? TextInputAction.next : TextInputAction.done,
        onSubmitted: (_) {
          if (nextFocusNode != null) FocusScope.of(context).requestFocus(nextFocusNode);
          else _handleAuth();
        },
        onChanged: (_) => setState((){}), 
        style: TextStyle(color: textColor, fontSize: 16, letterSpacing: obscureText ? 2 : 0),
        decoration: InputDecoration(
          labelText: labelText,
          labelStyle: TextStyle(color: textColor.withOpacity(0.4), fontSize: 15, letterSpacing: 0),
          prefixIcon: Icon(icon, color: textColor.withOpacity(0.4), size: 22),
          suffixIcon: isPassword
              ? IconButton(
                  icon: Icon(
                    obscureText ? CupertinoIcons.eye_slash_fill : CupertinoIcons.eye_fill,
                    color: textColor.withOpacity(0.3),
                    size: 20,
                  ),
                  onPressed: onToggleObscure,
                )
              : (controller.text.isNotEmpty && !_isLoading
                  ? IconButton(
                      icon: Icon(CupertinoIcons.clear_thick_circled, color: textColor.withOpacity(0.2), size: 18),
                      onPressed: () {
                        controller.clear();
                        setState(() {});
                      },
                    )
                  : null),
          border: InputBorder.none,
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide(color: primaryColor.withOpacity(0.8), width: 1.5),
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
        ),
      ),
    );
  }

  Widget _buildAvatarPicker() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).colorScheme.primary;
    final bgColor = isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.03);

    return Column(
      children: [
        GestureDetector(
          onTap: _pickAvatar,
          child: Container(
            width: 86,
            height: 86,
            decoration: BoxDecoration(
              color: bgColor,
              shape: BoxShape.circle,
              border: Border.all(
                color: _avatarBytes == null ? primaryColor.withOpacity(0.3) : primaryColor,
                width: 2,
              ),
              boxShadow: _avatarBytes == null ? [] : [
                BoxShadow(color: primaryColor.withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 5))
              ],
            ),
            child: _avatarBytes == null
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(CupertinoIcons.camera_fill, color: primaryColor.withOpacity(0.6), size: 28),
                      const SizedBox(height: 2),
                      Text('上传头像', style: TextStyle(fontSize: 10, color: primaryColor.withOpacity(0.8), fontWeight: FontWeight.bold)),
                    ],
                  )
                : ClipOval(
                    child: Image.memory(
                      _avatarBytes!,
                      fit: BoxFit.cover,
                      width: 86,
                      height: 86,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? const Color(0xFFE5E5EA) : const Color(0xFF2D2D2D);
    final primaryColor = Theme.of(context).colorScheme.primary;
    final sigma = (kIsWeb || defaultTargetPlatform == TargetPlatform.android) ? 15.0 : 30.0;
    final isZh = Localizations.localeOf(context).languageCode.startsWith('zh');

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        child: Center(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: ScaleTransition(
                scale: _scaleAnimation,
                child: Container(
                  width: MediaQuery.of(context).size.width.clamp(320.0, 420.0),
                  margin: EdgeInsets.fromLTRB(24, MediaQuery.of(context).padding.top + 24, 24, 24),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        isDark ? Colors.white.withOpacity(0.12) : Colors.white.withOpacity(0.9),
                        isDark ? Colors.white.withOpacity(0.04) : Colors.white.withOpacity(0.5),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(36),
                    border: Border.all(color: isDark ? Colors.white.withOpacity(0.15) : Colors.white, width: 1.5),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(isDark ? 0.3 : 0.08), blurRadius: 60, spreadRadius: -10, offset: const Offset(0, 20)),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(36),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 顶部区域
                        Padding(
                          padding: const EdgeInsets.fromLTRB(32, 36, 24, 24),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(color: primaryColor.withOpacity(isDark ? 0.2 : 0.1), borderRadius: BorderRadius.circular(16)),
                                    child: Icon(Icons.auto_awesome_rounded, color: primaryColor, size: 28),
                                  ),
                                  const SizedBox(height: 20),
                                  Text(
                                    AppStrings.of(context, 'auth_title'),
                                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800, color: textColor, letterSpacing: 0.5),
                                  ),
                                ],
                              ),
                              IconButton(
                                icon: Icon(Icons.language_rounded, color: textColor.withOpacity(0.5)),
                                onPressed: _showLanguageDialog,
                                tooltip: '切换语言',
                                style: IconButton.styleFrom(backgroundColor: isDark ? Colors.white10 : Colors.black.withOpacity(0.05)),
                              ),
                            ],
                          ),
                        ),

                        // 定制化分段器
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: Container(
                            height: 52,
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(color: isDark ? Colors.black.withOpacity(0.3) : Colors.black.withOpacity(0.04), borderRadius: BorderRadius.circular(26)),
                            child: TabBar(
                              controller: _tabController,
                              indicator: BoxDecoration(
                                borderRadius: BorderRadius.circular(22),
                                color: isDark ? Colors.white.withOpacity(0.15) : Colors.white,
                                boxShadow: isDark ? [] : [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))],
                              ),
                              indicatorSize: TabBarIndicatorSize.tab,
                              dividerColor: Colors.transparent,
                              labelColor: isDark ? Colors.white : Colors.black87,
                              unselectedLabelColor: textColor.withOpacity(0.5),
                              labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
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
                          padding: const EdgeInsets.fromLTRB(32, 32, 32, 24),
                          child: AnimatedSize(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeOutCubic,
                            alignment: Alignment.topCenter,
                            child: Column(
                              children: [
                                // 注册时显示头像上传控件
                                if (_tabController.index == 1) _buildAvatarPicker(),

                                _buildTextField(
                                  controller: _accountController,
                                  focusNode: _accountFocus,
                                  nextFocusNode: _tabController.index == 1 ? _nicknameFocus : _passwordFocus,
                                  labelText: AppStrings.of(context, 'auth_label_contact'),
                                  icon: CupertinoIcons.envelope_fill,
                                ),
                                
                                if (_tabController.index == 1) ...[
                                  _buildTextField(
                                    controller: _nicknameController,
                                    focusNode: _nicknameFocus,
                                    nextFocusNode: _passwordFocus,
                                    labelText: AppStrings.of(context, 'auth_label_name'),
                                    icon: CupertinoIcons.person_solid,
                                  ),
                                ],

                                _buildTextField(
                                  controller: _passwordController,
                                  focusNode: _passwordFocus,
                                  nextFocusNode: _tabController.index == 1 ? _confirmPasswordFocus : null,
                                  labelText: isZh ? '密码' : 'Password',
                                  icon: CupertinoIcons.lock_shield_fill,
                                  isPassword: true,
                                  obscureText: _obscurePassword,
                                  onToggleObscure: () => setState(() => _obscurePassword = !_obscurePassword),
                                ),

                                if (_tabController.index == 1) ...[
                                  _buildTextField(
                                    controller: _confirmPasswordController,
                                    focusNode: _confirmPasswordFocus,
                                    labelText: isZh ? '确认密码' : 'Confirm Password',
                                    icon: CupertinoIcons.lock_rotation,
                                    isPassword: true,
                                    obscureText: _obscureConfirmPassword,
                                    onToggleObscure: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                                  ),
                                ],

                                // 错误提示区
                                if (_errorMessage != null) ...[
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4, bottom: 12),
                                    child: Row(
                                      children: [
                                        Icon(CupertinoIcons.exclamationmark_circle_fill, color: Colors.red.shade400, size: 16),
                                        const SizedBox(width: 8),
                                        Expanded(child: Text(_errorMessage!, style: TextStyle(color: Colors.red.shade400, fontSize: 13, fontWeight: FontWeight.w600))),
                                      ],
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 8),

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
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                    ).copyWith(
                                      elevation: WidgetStateProperty.resolveWith<double>((states) {
                                        if (states.contains(WidgetState.pressed)) return 2;
                                        if (states.contains(WidgetState.disabled)) return 0;
                                        return 8; 
                                      }),
                                    ),
                                    child: _isLoading
                                        ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                                        : Text(
                                            _tabController.index == 0 ? AppStrings.of(context, 'auth_btn_login') : AppStrings.of(context, 'auth_btn_register'),
                                            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, letterSpacing: 1.0),
                                          ),
                                  ),
                                ),

                                // 新增：游客登录按钮
                                const SizedBox(height: 12),
                                TextButton(
                                  onPressed: _isLoading ? null : _handleGuestLogin,
                                  style: TextButton.styleFrom(
                                    foregroundColor: textColor.withOpacity(0.6),
                                    minimumSize: const Size(double.infinity, 48),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                  ),
                                  child: Text(
                                    isZh ? '游客身份体验' : 'Continue as Guest',
                                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
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