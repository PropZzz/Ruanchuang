import 'package:flutter/material.dart';

/// Semantic tokens for the scheduling workbench.
abstract final class AppThemeTokens {
  static const canvasLight = Color(0xFFF5F5F7);
  static const canvasDark = Color(0xFF111214);
  static const surfaceLight = Color(0xFFFFFFFF);
  static const surfaceDark = Color(0xFF1C1C1E);
  static const inkLight = Color(0xFF1D1D1F);
  static const inkDark = Color(0xFFF5F5F7);
  static const secondaryLight = Color(0xFF6E6E73);
  static const secondaryDark = Color(0xFF98989D);
  static const brandLight = Color(0xFF163D3D);
  static const brandDark = Color(0xFFA7D4C6);
  static const actionLight = Color(0xFF007AFF);
  static const actionDark = Color(0xFF0A84FF);
  static const recoveryLight = Color(0xFF34C759);
  static const recoveryDark = Color(0xFF30D158);
  static const successLight = Color(0xFF18794E);
  static const successDark = Color(0xFF8BE3C4);
  static const pressureLight = Color(0xFFFF9F0A);
  static const pressureDark = Color(0xFFFF9F0A);
  static const warningLight = Color(0xFF9A4D00);
  static const warningDark = Color(0xFFFFB340);
  static const actionButtonLight = Color(0xFF005FB8);
  static const actionButtonDark = Color(0xFF0066CC);
  // Legacy aliases kept for existing page accent references.
  static const deadlineLight = pressureLight;
  static const deadlineDark = pressureDark;
  static const riskLight = Color(0xFFFF3B30);
  static const riskDark = Color(0xFFFF453A);
  static const dividerLight = Color(0xFFE5E5EA);
  static const dividerDark = Color(0xFF38383A);
}

/// Material hierarchy used by structural chrome and floating overlays.
enum AppMaterialLevel { canvas, surface, chrome, overlay }

/// Shared opacity, blur, and shadow values for the selective glass system.
abstract final class AppMaterialTokens {
  static const chromeLightOpacity = 0.76;
  static const chromeDarkOpacity = 0.72;
  static const overlayLightOpacity = 0.86;
  static const overlayDarkOpacity = 0.82;
  static const chromeBlur = 22.0;
  static const overlayBlur = 28.0;

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
  static const focusLight = Color(0xFFEFF4F3);
  static const focusDark = Color(0xFF182525);
  static const focusSurfaceLight = Color(0xFFE2ECEA);
  static const focusSurfaceDark = Color(0xFF243634);
  static const scheduleLight = Color(0xFFF0F2F5);
  static const scheduleDark = Color(0xFF1A1D22);
  static const scheduleSurfaceLight = Color(0xFFE4E9EF);
  static const scheduleSurfaceDark = Color(0xFF252C35);
  static const microLight = Color(0xFFF4F1ED);
  static const microDark = Color(0xFF24211F);
  static const microSurfaceLight = Color(0xFFE9E3DA);
  static const microSurfaceDark = Color(0xFF332E29);
  static const teamLight = Color(0xFFEEF2F7);
  static const teamDark = Color(0xFF1B2027);
  static const teamSurfaceLight = Color(0xFFE0E8F1);
  static const teamSurfaceDark = Color(0xFF27323E);
  static const profileLight = Color(0xFFF3F0F0);
  static const profileDark = Color(0xFF241F20);
  static const profileSurfaceLight = Color(0xFFEAE2E4);
  static const profileSurfaceDark = Color(0xFF34292B);

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
    final pressure = isDark
        ? AppThemeTokens.pressureDark
        : AppThemeTokens.pressureLight;
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
          primary: action,
          onPrimary: Colors.white,
          secondary: pressure,
          onSecondary: AppThemeTokens.inkLight,
          tertiary: recovery,
          onTertiary: AppThemeTokens.inkLight,
          error: risk,
          onError: Colors.white,
          outline: divider,
          surfaceTint: Colors.transparent,
        );

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: canvas,
      colorScheme: scheme,
      dividerColor: divider,
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
          fontSize: 38,
          height: 1.1,
          fontWeight: FontWeight.w700,
          fontFeatures: const [FontFeature.tabularFigures()],
          letterSpacing: 0,
          color: ink,
        ),
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
          fontFamilyFallback: const ['PingFang SC', 'Noto Sans SC'],
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(44, 44),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 76,
        elevation: 0,
        backgroundColor: surface,
        indicatorColor: action.withValues(alpha: 0.12),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith<TextStyle?>((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 11,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? ink : secondary,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith<IconThemeData?>((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(color: selected ? action : secondary, size: 22);
        }),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: surface,
        useIndicator: true,
        indicatorColor: action.withValues(alpha: 0.12),
        selectedIconTheme: IconThemeData(color: action),
        unselectedIconTheme: IconThemeData(color: secondary),
        selectedLabelTextStyle: TextStyle(
          fontWeight: FontWeight.w700,
          color: ink,
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
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
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: action, width: 2),
        ),
      ),
      focusColor: action.withValues(alpha: 0.12),
    );
  }
}
