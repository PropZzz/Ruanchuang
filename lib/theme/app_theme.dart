import 'package:flutter/material.dart';

/// Semantic tokens for the scheduling workbench.
abstract final class AppThemeTokens {
  static const canvasLight = Color(0xFFFAF8FE);
  static const canvasDark = Color(0xFF101B1D);
  static const surfaceLight = Color(0xFFFFFFFF);
  static const surfaceDark = Color(0xFF1C2B2E);
  static const inkLight = Color(0xFF1A1B1F);
  static const inkDark = Color(0xFFE7F0ED);
  static const secondaryLight = Color(0xFF414848);
  static const secondaryDark = Color(0xFF9CB0AE);
  static const brandLight = Color(0xFF002727);
  static const brandDark = Color(0xFFA7CECD);
  static const actionLight = Color(0xFF005DB5);
  static const actionDark = Color(0xFF62A1FE);
  static const recoveryLight = Color(0xFF1DB84D);
  static const recoveryDark = Color(0xFF53E16F);
  static const successLight = Color(0xFF00531C);
  static const successDark = Color(0xFF72FE88);
  static const pressureLight = Color(0xFFE5A15B);
  static const pressureDark = Color(0xFFF2B56E);
  static const warningLight = Color(0xFF9A4D00);
  static const warningDark = Color(0xFFFFB340);
  static const actionButtonLight = Color(0xFF005DB5);
  static const actionButtonDark = Color(0xFF005DB5);
  // Legacy aliases kept for existing page accent references.
  static const deadlineLight = pressureLight;
  static const deadlineDark = pressureDark;
  static const riskLight = Color(0xFFBA1A1A);
  static const riskDark = Color(0xFFF07A6A);
  static const dividerLight = Color(0xFFC0C8C7);
  static const dividerDark = Color(0xFF38494A);
  static const sidebarLight = Color(0xFFF4F3F8);
  static const sidebarDark = Color(0xFF172426);
  static const selectedNavLight = Color(0xFF163D3D);
  static const selectedNavDark = Color(0xFF274D4D);
  static const selectedNavText = Colors.white;
}

/// Material hierarchy used by structural chrome and floating overlays.
enum AppMaterialLevel { canvas, surface, chrome, overlay }

/// Shared opacity, blur, and shadow values for the selective glass system.
abstract final class AppMaterialTokens {
  static const chromeLightOpacity = 0.76;
  static const chromeDarkOpacity = 0.72;
  static const overlayLightOpacity = 0.86;
  static const overlayDarkOpacity = 0.82;
  static const chromeBlur = 16.0;
  static const overlayBlur = 20.0;

  static double opacity(Brightness brightness, AppMaterialLevel level) {
    final isDark = brightness == Brightness.dark;
    return switch (level) {
      AppMaterialLevel.canvas || AppMaterialLevel.surface => 1,
      AppMaterialLevel.chrome =>
        isDark ? chromeDarkOpacity : chromeLightOpacity,
      AppMaterialLevel.overlay =>
        isDark ? overlayDarkOpacity : overlayLightOpacity,
    };
  }

  static double blur(AppMaterialLevel level) => switch (level) {
    AppMaterialLevel.canvas || AppMaterialLevel.surface => 0,
    AppMaterialLevel.chrome => chromeBlur,
    AppMaterialLevel.overlay => overlayBlur,
  };

  static double shadowAlpha(Brightness brightness, AppMaterialLevel level) {
    final isDark = brightness == Brightness.dark;
    return switch (level) {
      AppMaterialLevel.canvas || AppMaterialLevel.surface => 0,
      AppMaterialLevel.chrome => isDark ? 0.2 : 0.08,
      AppMaterialLevel.overlay => isDark ? 0.3 : 0.14,
    };
  }
}

enum AppWindowTone { neutral, focus, schedule, micro, team, profile }

abstract final class AppMotion {
  static const enter = Duration(milliseconds: 260);
  static const exit = Duration(milliseconds: 170);
  static const press = Duration(milliseconds: 100);

  static Duration resolve(BuildContext context, Duration duration) {
    return MediaQuery.maybeOf(context)?.disableAnimations == true
        ? Duration.zero
        : duration;
  }
}

/// Low-saturation window tints. They distinguish work areas without turning
/// the product into a collection of bright themed pages.
abstract final class AppWindowTones {
  static const neutralLight = AppThemeTokens.canvasLight;
  static const neutralDark = AppThemeTokens.canvasDark;
  static const focusLight = neutralLight;
  static const focusDark = neutralDark;
  static const focusSurfaceLight = AppThemeTokens.surfaceLight;
  static const focusSurfaceDark = AppThemeTokens.surfaceDark;
  static const scheduleLight = neutralLight;
  static const scheduleDark = neutralDark;
  static const scheduleSurfaceLight = AppThemeTokens.surfaceLight;
  static const scheduleSurfaceDark = AppThemeTokens.surfaceDark;
  static const microLight = neutralLight;
  static const microDark = neutralDark;
  static const microSurfaceLight = AppThemeTokens.surfaceLight;
  static const microSurfaceDark = AppThemeTokens.surfaceDark;
  static const teamLight = neutralLight;
  static const teamDark = neutralDark;
  static const teamSurfaceLight = AppThemeTokens.surfaceLight;
  static const teamSurfaceDark = AppThemeTokens.surfaceDark;
  static const profileLight = neutralLight;
  static const profileDark = neutralDark;
  static const profileSurfaceLight = AppThemeTokens.surfaceLight;
  static const profileSurfaceDark = AppThemeTokens.surfaceDark;

  static Color canvas(BuildContext context, AppWindowTone tone) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return switch (tone) {
      AppWindowTone.neutral => isDark ? neutralDark : neutralLight,
      AppWindowTone.focus => isDark ? focusDark : focusLight,
      AppWindowTone.schedule => isDark ? scheduleDark : scheduleLight,
      AppWindowTone.micro => isDark ? microDark : microLight,
      AppWindowTone.team => isDark ? teamDark : teamLight,
      AppWindowTone.profile => isDark ? profileDark : profileLight,
    };
  }

  static Color surface(BuildContext context, AppWindowTone tone) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return switch (tone) {
      AppWindowTone.neutral =>
        isDark ? AppThemeTokens.surfaceDark : AppThemeTokens.surfaceLight,
      AppWindowTone.focus => isDark ? focusSurfaceDark : focusSurfaceLight,
      AppWindowTone.schedule =>
        isDark ? scheduleSurfaceDark : scheduleSurfaceLight,
      AppWindowTone.micro => isDark ? microSurfaceDark : microSurfaceLight,
      AppWindowTone.team => isDark ? teamSurfaceDark : teamSurfaceLight,
      AppWindowTone.profile =>
        isDark ? profileSurfaceDark : profileSurfaceLight,
    };
  }
}

abstract final class AppTheme {
  /// Compact rail threshold: >= 720 uses a side navigation shell.
  static const double compactShellBreakpoint = 720;

  /// Desktop shell threshold: >= 1200 uses the expanded navigation shell.
  static const double shellBreakpoint = 1200;

  /// Rescue comparison threshold: >= 760 uses side-by-side columns.
  static const double comparisonBreakpoint = 760;

  static ThemeData get light => build(Brightness.light);

  static ThemeData get dark => build(Brightness.dark);

  static ThemeData build(Brightness brightness, {Color? accentColor}) {
    final isDark = brightness == Brightness.dark;
    final canvas = isDark
        ? AppThemeTokens.canvasDark
        : AppThemeTokens.canvasLight;
    final surface = isDark
        ? AppThemeTokens.surfaceDark
        : AppThemeTokens.surfaceLight;
    final ink = isDark ? AppThemeTokens.inkDark : AppThemeTokens.inkLight;
    final secondary = isDark
        ? AppThemeTokens.secondaryDark
        : AppThemeTokens.secondaryLight;
    final brand = isDark ? AppThemeTokens.brandDark : AppThemeTokens.brandLight;
    final action = isDark
        ? AppThemeTokens.actionDark
        : AppThemeTokens.actionLight;
    final actionButton = isDark
        ? AppThemeTokens.actionButtonDark
        : AppThemeTokens.actionButtonLight;
    final recovery =
        accentColor ??
        (isDark ? AppThemeTokens.recoveryDark : AppThemeTokens.recoveryLight);
    final risk = isDark ? AppThemeTokens.riskDark : AppThemeTokens.riskLight;
    final divider = isDark
        ? AppThemeTokens.dividerDark
        : AppThemeTokens.dividerLight;

    final scheme =
        ColorScheme.fromSeed(
          seedColor: brand,
          brightness: brightness,
          surface: surface,
          onSurface: ink,
        ).copyWith(
          primary: brand,
          onPrimary: Colors.white,
          primaryContainer: isDark
              ? AppThemeTokens.selectedNavDark
              : AppThemeTokens.selectedNavLight,
          onPrimaryContainer: AppThemeTokens.selectedNavText,
          secondary: action,
          onSecondary: Colors.white,
          secondaryContainer: isDark
              ? const Color(0xFF00376F)
              : const Color(0xFFD6E3FF),
          onSecondaryContainer: isDark ? Colors.white : const Color(0xFF001B3D),
          tertiaryContainer: isDark
              ? const Color(0xFF004114)
              : const Color(0xFFC2EAE9),
          tertiary: recovery,
          onTertiary: AppThemeTokens.inkLight,
          error: risk,
          onError: Colors.white,
          outline: divider,
          outlineVariant: isDark
              ? AppThemeTokens.dividerDark
              : const Color(0xFFC0C8C7),
          onSurfaceVariant: secondary,
          surfaceTint: Colors.transparent,
        );

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: canvas,
      colorScheme: scheme,
      dividerColor: divider,
      fontFamily: 'StitchInter',
      fontFamilyFallback: const ['PingFang SC', 'Noto Sans SC'],
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
    );
    final text = base.textTheme;

    return base.copyWith(
      textTheme: text.copyWith(
        displaySmall: text.displaySmall?.copyWith(
          fontFamily: 'NotoSerifSC',
          fontSize: 38,
          height: 1.1,
          fontWeight: FontWeight.w700,
          fontFeatures: const [FontFeature.tabularFigures()],
          letterSpacing: 0,
          color: ink,
        ),
        headlineMedium: text.headlineMedium?.copyWith(
          fontFamily: 'NotoSerifSC',
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
          color: ink,
        ),
        titleLarge: text.titleLarge?.copyWith(
          fontFamily: 'NotoSerifSC',
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
          height: 1.45,
          letterSpacing: 0,
          color: secondary,
        ),
        labelLarge: text.labelLarge?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        toolbarHeight: 64,
        titleTextStyle: TextStyle(
          color: ink,
          fontFamily: 'NotoSerifSC',
          fontSize: 22,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
        ),
      ),
      cardTheme: CardThemeData(
        clipBehavior: Clip.antiAlias,
        elevation: 1,
        color: surface,
        shadowColor: isDark
            ? Colors.black.withValues(alpha: 0.32)
            : Colors.black.withValues(alpha: 0.06),
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(44, 44),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          backgroundColor: actionButton,
          foregroundColor: Colors.white,
          overlayColor: Colors.white.withValues(alpha: 0.14),
          elevation: 1,
          animationDuration: const Duration(milliseconds: 120),
          iconAlignment: IconAlignment.start,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(44, 44),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          side: BorderSide(color: divider),
          foregroundColor: ink,
          overlayColor: action.withValues(alpha: 0.1),
          animationDuration: const Duration(milliseconds: 120),
          iconAlignment: IconAlignment.start,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(44, 44),
          foregroundColor: action,
          overlayColor: action.withValues(alpha: 0.1),
          animationDuration: const Duration(milliseconds: 120),
          iconAlignment: IconAlignment.start,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        elevation: 0,
        backgroundColor: surface,
        indicatorColor: Colors.transparent,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith<TextStyle?>((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 11,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? brand : secondary,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith<IconThemeData?>((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(color: selected ? brand : secondary, size: 22);
        }),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: surface,
        useIndicator: true,
        indicatorColor: isDark
            ? AppThemeTokens.selectedNavDark
            : AppThemeTokens.selectedNavLight,
        selectedIconTheme: const IconThemeData(color: Colors.white),
        unselectedIconTheme: IconThemeData(color: secondary),
        selectedLabelTextStyle: TextStyle(
          fontWeight: FontWeight.w700,
          color: Colors.white,
          fontSize: 13,
        ),
        unselectedLabelTextStyle: TextStyle(
          fontWeight: FontWeight.w500,
          color: secondary,
          fontSize: 13,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        insetPadding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
        backgroundColor: ink,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        contentTextStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? surface : AppThemeTokens.canvasLight,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 13,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: action, width: 2),
        ),
      ),
      focusColor: action.withValues(alpha: 0.12),
    );
  }
}
