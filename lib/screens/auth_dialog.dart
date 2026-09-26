import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:image_picker/image_picker.dart';

import '../services/api_client.dart';
import '../services/app_services.dart';
import '../theme/app_theme.dart';
import '../utils/app_strings.dart';
import '../main.dart';
import '../widgets/glass_surface.dart';
import '../widgets/press_scale.dart';
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
  final TextEditingController _confirmPasswordController =
      TextEditingController();
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

    _enterAnimationController = AnimationController(
      vsync: this,
      duration: AppMotion.enter,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _enterAnimationController,
        curve: Curves.easeOutCubic,
      ),
    );
    _scaleAnimation = Tween<double>(begin: 0.96, end: 1.0).animate(
      CurvedAnimation(parent: _enterAnimationController, curve: Curves.easeOut),
    );

    if (WidgetsBinding
        .instance
        .platformDispatcher
        .accessibilityFeatures
        .disableAnimations) {
      _enterAnimationController.value = 1;
    } else {
      _enterAnimationController.forward();
    }
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
    final isZh = Localizations.localeOf(context).languageCode.startsWith('zh');

    setState(() => _errorMessage = null);

    if (account.isEmpty) {
      setState(
        () => _errorMessage = AppStrings.of(context, 'auth_error_empty'),
      );
      return;
    }
    if (!_isValidContact(account)) {
      setState(
        () =>
            _errorMessage = AppStrings.of(context, 'auth_error_invalid_phone'),
      );
      return;
    }
    if (password.length < 6) {
      setState(
        () => _errorMessage = isZh
            ? '密码长度不能少于 6 位'
            : 'Password must contain at least 6 characters.',
      );
      return;
    }
    if (isRegister) {
      if (nickname.isEmpty) {
        setState(() => _errorMessage = isZh ? '请填写昵称' : 'Enter a nickname.');
        return;
      }
      if (password != confirmPassword) {
        setState(
          () => _errorMessage = isZh
              ? '两次输入的密码不一致，请检查'
              : 'The passwords do not match.',
        );
        return;
      }
    }

    setState(() => _isLoading = true);
    FocusScope.of(context).unfocus();

    try {
      final dataService = AppServices.dataService;
      if (isRegister) {
        final success = await dataService.registerAccount(
          username: account,
          displayName: nickname,
          password: password,
        );
        if (!success) {
          setState(
            () => _errorMessage = isZh
                ? '该手机号或邮箱已注册，请切换到登录'
                : 'This phone or email is already registered. Sign in instead.',
          );
          return;
        }
        final user = await dataService.getCurrentUser();
        ProfilePage.globalNameNotifier.value = user?.displayName ?? nickname;
        ProfilePage.globalAvatarNotifier.value = _avatarBytes;

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppStrings.of(context, 'auth_success_register')),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          );
        }
      } else {
        final success = await dataService.login(account, password);
        if (!success) {
          setState(
            () => _errorMessage = isZh
                ? '手机号/邮箱或密码不正确'
                : 'The phone, email, or password is incorrect.',
          );
          return;
        }
        final user = await dataService.getCurrentUser();
        ProfilePage.globalNameNotifier.value = user?.displayName ?? account;
        ProfilePage.globalAvatarNotifier.value = null;
      }

      if (mounted) {
        await _enterAnimationController.reverse();
        widget.onAuthSuccess();
      }
    } catch (error) {
      if (mounted) {
        setState(
          () =>
              _errorMessage = _authErrorMessage(error, isRegister: isRegister),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleGuestLogin() async {
    setState(() => _isLoading = true);
    FocusScope.of(context).unfocus();
    final isZh = Localizations.localeOf(context).languageCode.startsWith('zh');

    try {
      await AppServices.dataService.startGuestSession();
      final guestId = DateTime.now().millisecondsSinceEpoch
          .toString()
          .substring(9);
      ProfilePage.globalNameNotifier.value = isZh
          ? '游客_$guestId'
          : 'Guest_$guestId';
      ProfilePage.globalAvatarNotifier.value = null;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isZh
                  ? '已进入本地游客模式，数据保存在本机'
                  : 'Using local guest mode; data stays on this device.',
            ),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
        await _enterAnimationController.reverse();
        widget.onAuthSuccess();
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _errorMessage = _authErrorMessage(error, isRegister: false),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _authErrorMessage(Object error, {required bool isRegister}) {
    final isZh = Localizations.localeOf(context).languageCode.startsWith('zh');
    if (error is ApiException) {
      if (error.statusCode == 401 && !isRegister) {
        return isZh
            ? '手机号/邮箱或密码不正确'
            : 'The phone, email, or password is incorrect.';
      }
      if (error.statusCode == 409 && isRegister) {
        return isZh
            ? '该手机号或邮箱已注册，请切换到登录'
            : 'This phone or email is already registered. Sign in instead.';
      }
      if (error.statusCode == 422) {
        return isZh
            ? '提交信息未通过服务器校验，请检查后重试'
            : 'The server rejected these details. Check them and try again.';
      }
      if (error.statusCode == 429) {
        return isZh
            ? '尝试次数过多，请稍后再试'
            : 'Too many attempts. Please try again later.';
      }
      if ((error.statusCode ?? 0) >= 500) {
        return isZh
            ? '认证服务暂时不可用，请稍后重试'
            : 'The authentication service is temporarily unavailable.';
      }
    }
    return isZh
        ? '暂时无法完成操作，请检查网络后重试'
        : 'Could not complete the request. Check your connection and try again.';
  }

  void _showLanguageDialog() {
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text(
          AppStrings.of(context, 'settings_language'),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
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

  Future<void> _dismiss() async {
    if (_isLoading) return;
    await _enterAnimationController.reverse();
    if (mounted) {
      Navigator.of(context).maybePop();
    }
  }

  Widget _buildTextField({
    Key? key,
    required TextEditingController controller,
    required FocusNode focusNode,
    FocusNode? nextFocusNode,
    required String labelText,
    required IconData icon,
    TextInputType? keyboardType,
    bool isPassword = false,
    bool obscureText = false,
    VoidCallback? onToggleObscure,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final textColor = scheme.onSurface;
    final fillColor = isDark
        ? scheme.surfaceContainerLow
        : scheme.surfaceContainerLowest;
    final primaryColor = scheme.secondary;
    final isZh = Localizations.localeOf(context).languageCode.startsWith('zh');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: fillColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: isDark ? 0.6 : 0.8),
        ),
      ),
      child: TextField(
        key: key,
        controller: controller,
        focusNode: focusNode,
        enabled: !_isLoading,
        obscureText: obscureText,
        keyboardType: keyboardType,
        textInputAction: nextFocusNode != null
            ? TextInputAction.next
            : TextInputAction.done,
        onSubmitted: (_) {
          if (nextFocusNode != null)
            FocusScope.of(context).requestFocus(nextFocusNode);
          else
            _handleAuth();
        },
        onChanged: (_) => setState(() {}),
        style: TextStyle(color: textColor, fontSize: 16),
        decoration: InputDecoration(
          labelText: labelText,
          labelStyle: TextStyle(
            color: scheme.onSurfaceVariant,
            fontSize: 15,
            letterSpacing: 0,
          ),
          prefixIcon: Icon(icon, color: scheme.onSurfaceVariant, size: 20),
          suffixIcon: isPassword
              ? Tooltip(
                  message: obscureText
                      ? (isZh ? '显示密码' : 'Show password')
                      : (isZh ? '隐藏密码' : 'Hide password'),
                  child: IconButton(
                    icon: Icon(
                      obscureText
                          ? CupertinoIcons.eye_slash_fill
                          : CupertinoIcons.eye_fill,
                      color: scheme.onSurfaceVariant,
                      size: 20,
                    ),
                    onPressed: onToggleObscure,
                  ),
                )
              : (controller.text.isNotEmpty && !_isLoading
                    ? Tooltip(
                        message: isZh ? '清空输入' : 'Clear field',
                        child: IconButton(
                          icon: Icon(
                            CupertinoIcons.clear_thick_circled,
                            color: scheme.onSurfaceVariant,
                            size: 18,
                          ),
                          onPressed: () {
                            controller.clear();
                            setState(() {});
                          },
                        ),
                      )
                    : null),
          border: InputBorder.none,
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: primaryColor, width: 1.5),
          ),
          contentPadding: const EdgeInsets.symmetric(
            vertical: 15,
            horizontal: 16,
          ),
        ),
      ),
    );
  }

  Widget _buildAvatarPicker() {
    final isZh = Localizations.localeOf(context).languageCode.startsWith('zh');
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).colorScheme.primary;
    final bgColor = isDark
        ? Colors.white.withValues(alpha: 0.05)
        : Colors.black.withValues(alpha: 0.03);

    return Column(
      children: [
        Semantics(
          button: true,
          label: isZh ? '选择本地头像' : 'Choose a local avatar',
          child: GestureDetector(
            onTap: _pickAvatar,
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: bgColor,
                shape: BoxShape.circle,
                border: Border.all(
                  color: _avatarBytes == null
                      ? primaryColor.withValues(alpha: 0.3)
                      : primaryColor,
                  width: 2,
                ),
              ),
              child: _avatarBytes == null
                  ? Icon(
                      CupertinoIcons.camera_fill,
                      color: primaryColor.withValues(alpha: 0.7),
                      size: 24,
                    )
                  : ClipOval(
                      child: Image.memory(
                        _avatarBytes!,
                        fit: BoxFit.cover,
                        width: 72,
                        height: 72,
                      ),
                    ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          isZh ? '上传头像 · 仅本机显示' : 'Avatar · saved on this device',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final isZh = Localizations.localeOf(context).languageCode.startsWith('zh');
    final isNarrow = MediaQuery.sizeOf(context).width < 480;
    final horizontalInset = isNarrow ? 16.0 : 24.0;
    final verticalInset = MediaQuery.sizeOf(context).height < 640 ? 12.0 : 24.0;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = (constraints.maxWidth - horizontalInset * 2).clamp(
              0.0,
              420.0,
            );
            final minHeight = (constraints.maxHeight - verticalInset * 2).clamp(
              0.0,
              double.infinity,
            );

            return SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.symmetric(
                horizontal: horizontalInset,
                vertical: verticalInset,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: minHeight),
                child: Center(
                  child: SizedBox(
                    width: width,
                    child: FadeTransition(
                      opacity: _fadeAnimation,
                      child: ScaleTransition(
                        scale: _scaleAnimation,
                        child: GlassSurface(
                          key: const ValueKey('auth-dialog-material'),
                          level: AppMaterialLevel.overlay,
                          padding: EdgeInsets.zero,
                          borderRadius: BorderRadius.circular(12),
                          tint: scheme.surface,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    20,
                                    24,
                                    12,
                                    18,
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Row(
                                          children: [
                                            Container(
                                              width: 40,
                                              height: 40,
                                              decoration: BoxDecoration(
                                                color: scheme.primaryContainer,
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                              ),
                                              child: Icon(
                                                Icons.auto_awesome_rounded,
                                                color:
                                                    scheme.onPrimaryContainer,
                                                size: 22,
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    AppStrings.of(
                                                      context,
                                                      'auth_title',
                                                    ),
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .titleLarge
                                                        ?.copyWith(
                                                          fontWeight:
                                                              FontWeight.w700,
                                                          color:
                                                              scheme.onSurface,
                                                        ),
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    isZh
                                                        ? '登录后同步日程与个人偏好'
                                                        : 'Sign in to sync your schedule and preferences',
                                                    maxLines: 2,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .labelSmall
                                                        ?.copyWith(
                                                          color: scheme
                                                              .onSurfaceVariant,
                                                        ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      IconButton(
                                        icon: const Icon(
                                          Icons.language_rounded,
                                        ),
                                        onPressed: _showLanguageDialog,
                                        tooltip: isZh
                                            ? '切换语言'
                                            : 'Change language',
                                        style: IconButton.styleFrom(
                                          minimumSize: const Size(44, 44),
                                          foregroundColor:
                                              scheme.onSurfaceVariant,
                                          backgroundColor:
                                              scheme.surfaceContainerLow,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      IconButton(
                                        icon: const Icon(Icons.close_rounded),
                                        onPressed: _dismiss,
                                        tooltip: isZh
                                            ? '关闭登录'
                                            : 'Close sign in',
                                        style: IconButton.styleFrom(
                                          minimumSize: const Size(44, 44),
                                          foregroundColor:
                                              scheme.onSurfaceVariant,
                                          backgroundColor:
                                              scheme.surfaceContainerLow,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                  ),
                                  child: Container(
                                    height: 48,
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: scheme.surfaceContainerLow,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: TabBar(
                                      controller: _tabController,
                                      indicator: BoxDecoration(
                                        borderRadius: BorderRadius.circular(8),
                                        color: scheme.surface,
                                        boxShadow: isDark
                                            ? const []
                                            : [
                                                BoxShadow(
                                                  color: Colors.black
                                                      .withValues(alpha: 0.06),
                                                  blurRadius: 6,
                                                  offset: const Offset(0, 1),
                                                ),
                                              ],
                                      ),
                                      indicatorSize: TabBarIndicatorSize.tab,
                                      dividerColor: Colors.transparent,
                                      labelColor: scheme.onSurface,
                                      unselectedLabelColor:
                                          scheme.onSurfaceVariant,
                                      labelStyle: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                      ),
                                      unselectedLabelStyle: const TextStyle(
                                        fontWeight: FontWeight.w500,
                                        fontSize: 14,
                                      ),
                                      tabs: [
                                        Tab(
                                          text: AppStrings.of(
                                            context,
                                            'auth_tab_login',
                                          ),
                                        ),
                                        Tab(
                                          text: AppStrings.of(
                                            context,
                                            'auth_tab_register',
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    20,
                                    22,
                                    20,
                                    16,
                                  ),
                                  child: Column(
                                    children: [
                                      if (_tabController.index == 1)
                                        _buildAvatarPicker(),
                                      _buildTextField(
                                        key: const ValueKey(
                                          'auth-account-input',
                                        ),
                                        controller: _accountController,
                                        focusNode: _accountFocus,
                                        nextFocusNode: _tabController.index == 1
                                            ? _nicknameFocus
                                            : _passwordFocus,
                                        labelText: AppStrings.of(
                                          context,
                                          'auth_label_contact',
                                        ),
                                        icon: CupertinoIcons.envelope_fill,
                                        keyboardType:
                                            TextInputType.emailAddress,
                                      ),
                                      if (_tabController.index == 1)
                                        _buildTextField(
                                          key: const ValueKey(
                                            'auth-nickname-input',
                                          ),
                                          controller: _nicknameController,
                                          focusNode: _nicknameFocus,
                                          nextFocusNode: _passwordFocus,
                                          labelText: AppStrings.of(
                                            context,
                                            'auth_label_name',
                                          ),
                                          icon: CupertinoIcons.person_solid,
                                        ),
                                      _buildTextField(
                                        key: const ValueKey(
                                          'auth-password-input',
                                        ),
                                        controller: _passwordController,
                                        focusNode: _passwordFocus,
                                        nextFocusNode: _tabController.index == 1
                                            ? _confirmPasswordFocus
                                            : null,
                                        labelText: isZh ? '密码' : 'Password',
                                        icon: CupertinoIcons.lock_shield_fill,
                                        isPassword: true,
                                        obscureText: _obscurePassword,
                                        onToggleObscure: () => setState(
                                          () => _obscurePassword =
                                              !_obscurePassword,
                                        ),
                                      ),
                                      if (_tabController.index == 1)
                                        _buildTextField(
                                          key: const ValueKey(
                                            'auth-confirm-password-input',
                                          ),
                                          controller:
                                              _confirmPasswordController,
                                          focusNode: _confirmPasswordFocus,
                                          labelText: isZh
                                              ? '确认密码'
                                              : 'Confirm password',
                                          icon: CupertinoIcons.lock_rotation,
                                          isPassword: true,
                                          obscureText: _obscureConfirmPassword,
                                          onToggleObscure: () => setState(
                                            () => _obscureConfirmPassword =
                                                !_obscureConfirmPassword,
                                          ),
                                        ),
                                      if (_errorMessage != null) ...[
                                        Semantics(
                                          liveRegion: true,
                                          child: Container(
                                            width: double.infinity,
                                            margin: const EdgeInsets.only(
                                              bottom: 12,
                                            ),
                                            padding: const EdgeInsets.all(10),
                                            decoration: BoxDecoration(
                                              color: scheme.errorContainer,
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Icon(
                                                  Icons.error_outline_rounded,
                                                  color:
                                                      scheme.onErrorContainer,
                                                  size: 18,
                                                ),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: Text(
                                                    _errorMessage!,
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .bodySmall
                                                        ?.copyWith(
                                                          color: scheme
                                                              .onErrorContainer,
                                                        ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                      const SizedBox(height: 4),
                                      PressScale(
                                        child: SizedBox(
                                          width: double.infinity,
                                          height: 52,
                                          child: FilledButton(
                                            onPressed: _isLoading
                                                ? null
                                                : _handleAuth,
                                            style: FilledButton.styleFrom(
                                              minimumSize:
                                                  const Size.fromHeight(52),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                            ),
                                            child: _isLoading
                                                ? const SizedBox(
                                                    height: 20,
                                                    width: 20,
                                                    child:
                                                        CircularProgressIndicator(
                                                          strokeWidth: 2,
                                                        ),
                                                  )
                                                : Row(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment
                                                            .center,
                                                    children: [
                                                      Icon(
                                                        _tabController.index ==
                                                                0
                                                            ? Icons
                                                                  .login_rounded
                                                            : Icons
                                                                  .person_add_alt_1_rounded,
                                                        size: 19,
                                                      ),
                                                      const SizedBox(width: 8),
                                                      Text(
                                                        AppStrings.of(
                                                          context,
                                                          _tabController
                                                                      .index ==
                                                                  0
                                                              ? 'auth_btn_login'
                                                              : 'auth_btn_register',
                                                        ),
                                                        style: const TextStyle(
                                                          fontSize: 15,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      TextButton.icon(
                                        onPressed: _isLoading
                                            ? null
                                            : _handleGuestLogin,
                                        icon: const Icon(
                                          Icons.person_outline_rounded,
                                          size: 19,
                                        ),
                                        label: Text(
                                          isZh ? '游客身份体验' : 'Continue as guest',
                                        ),
                                        style: TextButton.styleFrom(
                                          minimumSize: const Size.fromHeight(
                                            44,
                                          ),
                                          foregroundColor:
                                              scheme.onSurfaceVariant,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
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
          },
        ),
      ),
    );
  }
}
