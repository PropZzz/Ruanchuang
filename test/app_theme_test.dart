import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shixuzhipei/theme/app_theme.dart';
import 'package:shixuzhipei/widgets/glass_surface.dart';
import 'package:shixuzhipei/widgets/workbench_surface.dart';

void main() {
  test('light and dark themes expose the approved semantic tokens', () {
    final light = AppTheme.light;
    final dark = AppTheme.dark;

    expect(light.scaffoldBackgroundColor, AppThemeTokens.canvasLight);
    expect(light.colorScheme.primary, AppThemeTokens.actionLight);
    expect(light.colorScheme.tertiary, AppThemeTokens.recoveryLight);
    expect(light.colorScheme.error, AppThemeTokens.riskLight);

    expect(dark.scaffoldBackgroundColor, AppThemeTokens.canvasDark);
    expect(dark.colorScheme.primary, AppThemeTokens.actionDark);
    expect(dark.colorScheme.tertiary, AppThemeTokens.recoveryDark);
    expect(dark.colorScheme.error, AppThemeTokens.riskDark);
  });

  test('themes use material 3 and keep readable body text sizing', () {
    final theme = AppTheme.light;

    expect(theme.useMaterial3, isTrue);
    expect(theme.textTheme.bodyMedium?.fontSize, greaterThanOrEqualTo(12));
    expect(theme.cardTheme.shape, isA<RoundedRectangleBorder>());
  });

  test('workbench status colors preserve success and warning semantics', () {
    final scheme = AppTheme.light.colorScheme;

    expect(
      WorkbenchStatus.success.colorOf(scheme),
      AppThemeTokens.successLight,
    );
    expect(
      WorkbenchStatus.warning.colorOf(scheme),
      AppThemeTokens.warningLight,
    );
  });

  test('filled button colors meet normal text contrast', () {
    final style = AppTheme.light.filledButtonTheme.style!;
    final foreground = style.foregroundColor!.resolve({})!;
    final background = style.backgroundColor!.resolve({})!;

    double relativeLuminance(Color color) {
      double channel(int value) {
        final normalized = value / 255;
        return normalized <= 0.03928
            ? normalized / 12.92
            : math.pow((normalized + 0.055) / 1.055, 2.4).toDouble();
      }

      return 0.2126 * channel((color.r * 255).round()) +
          0.7152 * channel((color.g * 255).round()) +
          0.0722 * channel((color.b * 255).round());
    }

    final lighter = relativeLuminance(foreground);
    final darker = relativeLuminance(background);
    final ratio = (lighter + 0.05) / (darker + 0.05);
    expect(ratio, greaterThanOrEqualTo(4.5));
  });

  test('floating feedback reserves space above mobile navigation', () {
    expect(
      AppTheme.light.snackBarTheme.insetPadding?.bottom,
      greaterThanOrEqualTo(88),
    );
  });

  testWidgets(
    'window tones stay distinct while glass surfaces keep semantics',
    (tester) async {
      Color? focus;
      Color? schedule;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Builder(
            builder: (context) {
              focus = AppWindowTones.canvas(context, AppWindowTone.focus);
              schedule = AppWindowTones.canvas(context, AppWindowTone.schedule);
              return const GlassSurface(child: Text('surface'));
            },
          ),
        ),
      );
      expect(focus, isNotNull);
      expect(schedule, isNotNull);
      expect(focus, isNot(schedule));
      expect(find.byType(BackdropFilter), findsOneWidget);
      expect(find.text('surface'), findsOneWidget);
    },
  );

  testWidgets('motion tokens honor reduced-motion preference', (tester) async {
    Duration? resolved;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Builder(
            builder: (context) {
              resolved = AppMotion.resolve(
                context,
                const Duration(milliseconds: 260),
              );
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    expect(resolved, Duration.zero);
  });
}
