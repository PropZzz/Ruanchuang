import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shixuzhipei/theme/app_theme.dart';
import 'package:shixuzhipei/widgets/glass_surface.dart';

void main() {
  test('Apple Utility tokens expose the approved light and dark palette', () {
    expect(AppThemeTokens.canvasLight, const Color(0xFFF5F5F7));
    expect(AppThemeTokens.canvasDark, const Color(0xFF111214));
    expect(AppThemeTokens.actionLight, const Color(0xFF007AFF));
    expect(AppThemeTokens.actionDark, const Color(0xFF0A84FF));
    expect(AppThemeTokens.brandLight, const Color(0xFF163D3D));
    expect(AppThemeTokens.brandDark, const Color(0xFFA7D4C6));
    expect(AppThemeTokens.recoveryLight, const Color(0xFF34C759));
    expect(AppThemeTokens.pressureLight, const Color(0xFFFF9F0A));
    expect(AppThemeTokens.riskLight, const Color(0xFFFF3B30));
  });

  test(
    'material levels expose selective blur defaults and shell breakpoints',
    () {
      expect(AppTheme.shellBreakpoint, 1024);
      expect(AppTheme.comparisonBreakpoint, 760);
      expect(AppMaterialTokens.chromeBlur, 22);
      expect(AppMaterialTokens.overlayBlur, 28);
      expect(AppMaterialTokens.chromeLightOpacity, closeTo(0.76, 0.001));
      expect(AppMaterialTokens.overlayDarkOpacity, closeTo(0.82, 0.001));
    },
  );

  testWidgets('chrome glass keeps child semantics and renders a blur layer', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: GlassSurface(
            level: AppMaterialLevel.chrome,
            child: Text('glass content'),
          ),
        ),
      ),
    );

    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(find.text('glass content'), findsOneWidget);
    expect(tester.getSize(find.text('glass content')), isNot(Size.zero));
  });
}
