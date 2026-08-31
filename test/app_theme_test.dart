import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shixuzhipei/theme/app_theme.dart';

void main() {
  test('light and dark themes expose the approved semantic tokens', () {
    final light = AppTheme.light;
    final dark = AppTheme.dark;

    expect(light.scaffoldBackgroundColor, AppThemeTokens.canvasLight);
    expect(light.colorScheme.primary, AppThemeTokens.inkLight);
    expect(light.colorScheme.tertiary, AppThemeTokens.recoveryLight);
    expect(light.colorScheme.error, AppThemeTokens.riskLight);

    expect(dark.scaffoldBackgroundColor, AppThemeTokens.canvasDark);
    expect(dark.colorScheme.primary, AppThemeTokens.inkDark);
    expect(dark.colorScheme.tertiary, AppThemeTokens.recoveryDark);
    expect(dark.colorScheme.error, AppThemeTokens.riskDark);
  });

  test('themes use material 3 and keep readable body text sizing', () {
    final theme = AppTheme.light;

    expect(theme.useMaterial3, isTrue);
    expect(theme.textTheme.bodyMedium?.fontSize, greaterThanOrEqualTo(12));
    expect(theme.cardTheme.shape, isA<RoundedRectangleBorder>());
  });
}
