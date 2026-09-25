import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

abstract final class StitchMobileTokens {
  static const pageInset = 16.0;
  static const sectionGap = 12.0;
  static const controlRadius = 10.0;
  static const componentRadius = 14.0;
  static const sheetRadius = 24.0;
  static const headerHeight = 84.0;
  static const bottomBarHeight = 68.0;

  static Color canvas(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? AppThemeTokens.canvasDark
      : AppThemeTokens.canvasLight;

  static Color surface(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? AppThemeTokens.surfaceDark
      : AppThemeTokens.surfaceLight;

  static Color surfaceLow(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFF243235)
      : const Color(0xFFF4F3F8);

  static Color surfaceHigh(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFF314245)
      : const Color(0xFFE9E7ED);

  static TextStyle pageTitle(BuildContext context) =>
      Theme.of(context).textTheme.titleLarge!.copyWith(
        fontFamily: 'NotoSerifSC',
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: Theme.of(context).colorScheme.onSurface,
      );

  static TextStyle sectionTitle(BuildContext context) =>
      Theme.of(context).textTheme.titleMedium!.copyWith(
        fontFamily: 'NotoSerifSC',
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: Theme.of(context).colorScheme.primary,
      );

  static TextStyle label(BuildContext context) => Theme.of(context)
      .textTheme
      .labelMedium!
      .copyWith(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0);
}
