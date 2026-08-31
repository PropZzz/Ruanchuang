import 'package:flutter/material.dart';

/// Shared semantic colors for the scheduling workbench.
abstract final class AppThemeTokens {
  static const canvasLight = Color(0xFFEEF2F0);
  static const canvasDark = Color(0xFF101B1D);
  static const inkLight = Color(0xFF183238);
  static const inkDark = Color(0xFFE7F0ED);
  static const surfaceLight = Color(0xFFFFFFFF);
  static const surfaceDark = Color(0xFF1C2B2E);
  static const recoveryLight = Color(0xFF83AFA5);
  static const recoveryDark = Color(0xFF8EC8B7);
  static const deadlineLight = Color(0xFFE5A15B);
  static const deadlineDark = Color(0xFFF2B56E);
  static const riskLight = Color(0xFFC85A4B);
  static const riskDark = Color(0xFFF07A6A);
  static const mutedLight = Color(0xFF647579);
  static const mutedDark = Color(0xFF9CB0AE);
}

abstract final class AppTheme {
  static ThemeData get light => build(Brightness.light);

  static ThemeData get dark => build(Brightness.dark);

  static ThemeData build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final canvas = isDark
        ? AppThemeTokens.canvasDark
        : AppThemeTokens.canvasLight;
    final surface = isDark
        ? AppThemeTokens.surfaceDark
        : AppThemeTokens.surfaceLight;
    final ink = isDark ? AppThemeTokens.inkDark : AppThemeTokens.inkLight;
    final muted = isDark
        ? AppThemeTokens.mutedDark
        : AppThemeTokens.mutedLight;
    final recovery = isDark
        ? AppThemeTokens.recoveryDark
        : AppThemeTokens.recoveryLight;
    final deadline = isDark
        ? AppThemeTokens.deadlineDark
        : AppThemeTokens.deadlineLight;
    final risk = isDark ? AppThemeTokens.riskDark : AppThemeTokens.riskLight;

    final scheme = ColorScheme.fromSeed(
      seedColor: ink,
      brightness: brightness,
      surface: surface,
      onSurface: ink,
    ).copyWith(
      primary: ink,
      onPrimary: isDark ? AppThemeTokens.canvasDark : Colors.white,
      secondary: deadline,
      onSecondary: AppThemeTokens.inkLight,
      tertiary: recovery,
      onTertiary: AppThemeTokens.inkLight,
      error: risk,
      onError: Colors.white,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: 'NotoSerifSC',
      scaffoldBackgroundColor: canvas,
      colorScheme: scheme,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      visualDensity: VisualDensity.standard,
    );
    final text = base.textTheme;

    return base.copyWith(
      textTheme: text.copyWith(
        headlineMedium: text.headlineMedium?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
          color: ink,
        ),
        titleLarge: text.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
          color: ink,
        ),
        titleMedium: text.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
          color: ink,
        ),
        bodyLarge: text.bodyLarge?.copyWith(
          fontSize: 16,
          height: 1.5,
          letterSpacing: 0,
          color: ink,
        ),
        bodyMedium: text.bodyMedium?.copyWith(
          fontSize: 14,
          height: 1.5,
          letterSpacing: 0,
          color: muted,
        ),
        labelLarge: text.labelLarge?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: 0.1,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: ink,
          fontFamily: 'NotoSerifSC',
          fontSize: 22,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: surface,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 76,
        elevation: 0,
        backgroundColor: surface.withValues(alpha: isDark ? 0.84 : 0.9),
        indicatorColor: recovery.withValues(alpha: isDark ? 0.28 : 0.2),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith<TextStyle?>((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 11,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? ink : muted,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith<IconThemeData?>((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? ink : muted,
            size: selected ? 23 : 22,
          );
        }),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: surface.withValues(alpha: isDark ? 0.84 : 0.92),
        useIndicator: true,
        indicatorColor: recovery.withValues(alpha: isDark ? 0.28 : 0.2),
        selectedIconTheme: IconThemeData(color: ink),
        unselectedIconTheme: IconThemeData(color: muted),
        selectedLabelTextStyle: TextStyle(
          fontWeight: FontWeight.w700,
          color: ink,
          fontSize: 12,
        ),
        unselectedLabelTextStyle: TextStyle(
          fontWeight: FontWeight.w500,
          color: muted,
          fontSize: 12,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: ink,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        contentTextStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface.withValues(alpha: isDark ? 0.7 : 0.86),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: muted.withValues(alpha: 0.26)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: muted.withValues(alpha: 0.26)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: recovery, width: 2),
        ),
      ),
    );
  }
}
