import 'package:flutter/material.dart';

/// 调度工作台视觉令牌：语义色、6px/8px 圆角与实心组件表面。
class AppTheme {
  AppTheme._();

  /// 桌面壳切换阈值：>= 1024 使用左侧导航栏。
  static const double shellBreakpoint = 1024;

  /// 方案比较面板切换阈值：>= 760 使用多列并列。
  static const double comparisonBreakpoint = 760;

  static const Color _bgLight = Color(0xFFF6F8F8);
  static const Color _surfaceLight = Color(0xFFFFFFFF);
  static const Color _primaryLight = Color(0xFF153F45);
  static const Color _successLight = Color(0xFF2D7A69);
  static const Color _warningLight = Color(0xFFB87B16);
  static const Color _errorLight = Color(0xFFA8493B);
  static const Color _textPrimaryLight = Color(0xFF17212B);
  static const Color _textSecondaryLight = Color(0xFF5C6870);
  static const Color _dividerLight = Color(0xFFD9E1E0);

  static const Color _bgDark = Color(0xFF101B1D);
  static const Color _surfaceDark = Color(0xFF17272A);
  static const Color _primaryDark = Color(0xFFA8D7C9);
  static const Color _successDark = Color(0xFF8ECFBF);
  static const Color _warningDark = Color(0xFFE5B65A);
  static const Color _errorDark = Color(0xFFE18B7D);
  static const Color _textPrimaryDark = Color(0xFFECF3F2);
  static const Color _textSecondaryDark = Color(0xFFAAB9B7);
  static const Color _dividerDark = Color(0xFF2A3D40);

  static ThemeData light() => _build(
    brightness: Brightness.light,
    bg: _bgLight,
    surface: _surfaceLight,
    primary: _primaryLight,
    onPrimary: _surfaceLight,
    success: _successLight,
    warning: _warningLight,
    error: _errorLight,
    textPrimary: _textPrimaryLight,
    textSecondary: _textSecondaryLight,
    divider: _dividerLight,
  );

  static ThemeData dark() => _build(
    brightness: Brightness.dark,
    bg: _bgDark,
    surface: _surfaceDark,
    primary: _primaryDark,
    onPrimary: _bgDark,
    success: _successDark,
    warning: _warningDark,
    error: _errorDark,
    textPrimary: _textPrimaryDark,
    textSecondary: _textSecondaryDark,
    divider: _dividerDark,
  );

  static ThemeData _build({
    required Brightness brightness,
    required Color bg,
    required Color surface,
    required Color primary,
    required Color onPrimary,
    required Color success,
    required Color warning,
    required Color error,
    required Color textPrimary,
    required Color textSecondary,
    required Color divider,
  }) {
    final scheme = ColorScheme(
      brightness: brightness,
      primary: primary,
      onPrimary: onPrimary,
      secondary: success,
      onSecondary: onPrimary,
      tertiary: warning,
      onTertiary: onPrimary,
      error: error,
      onError: onPrimary,
      surface: surface,
      onSurface: textPrimary,
      onSurfaceVariant: textSecondary,
      outline: divider,
      outlineVariant: divider,
    );

    final base = ThemeData(
      useMaterial3: true,
      fontFamily: 'NotoSerifSC',
      scaffoldBackgroundColor: bg,
      colorScheme: scheme,
      disabledColor: textSecondary.withValues(alpha: 0.6),
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
    );

    final text = base.textTheme;

    return base.copyWith(
      textTheme: text.copyWith(
        headlineMedium: text.headlineMedium?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
          color: textPrimary,
        ),
        titleLarge: text.titleLarge?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
          color: textPrimary,
        ),
        titleMedium: text.titleMedium?.copyWith(
          fontWeight: FontWeight.w500,
          letterSpacing: 0.2,
          color: textPrimary,
        ),
        bodyLarge: text.bodyLarge?.copyWith(
          height: 1.6,
          letterSpacing: 0.1,
          color: textPrimary,
        ),
        bodyMedium: text.bodyMedium?.copyWith(
          height: 1.6,
          color: textSecondary,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        foregroundColor: textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 22,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: surface,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: divider),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 80,
        elevation: 0,
        backgroundColor: surface,
        indicatorColor: primary.withValues(alpha: 0.12),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith<TextStyle?>((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 11,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? textPrimary : textSecondary,
            letterSpacing: 0.2,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith<IconThemeData?>((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? textPrimary : textSecondary,
            size: 24,
          );
        }),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: surface,
        useIndicator: true,
        indicatorColor: primary.withValues(alpha: 0.12),
        selectedIconTheme: IconThemeData(color: textPrimary),
        unselectedIconTheme: IconThemeData(color: textSecondary),
        selectedLabelTextStyle: TextStyle(
          fontWeight: FontWeight.w600,
          color: textPrimary,
          fontSize: 12,
        ),
        unselectedLabelTextStyle: TextStyle(
          fontWeight: FontWeight.w400,
          color: textSecondary,
          fontSize: 12,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: divider),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: brightness == Brightness.dark
            ? _surfaceDark
            : _primaryLight,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        contentTextStyle: TextStyle(
          color: brightness == Brightness.dark
              ? _textPrimaryDark
              : _surfaceLight,
          fontWeight: FontWeight.w500,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: onPrimary,
          disabledBackgroundColor: divider,
          disabledForegroundColor: textSecondary,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textPrimary,
          side: BorderSide(color: divider),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: primary),
        ),
      ),
      dividerTheme: DividerThemeData(color: divider, thickness: 1, space: 1),
    );
  }
}
