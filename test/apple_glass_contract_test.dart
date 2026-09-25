import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shixuzhipei/theme/app_theme.dart';
import 'package:shixuzhipei/widgets/glass_surface.dart';
import 'package:shixuzhipei/widgets/workspace_status_bar.dart';

void main() {
  test('Stitch tokens expose the approved light and dark palette', () {
    expect(AppThemeTokens.canvasLight, const Color(0xFFFAF8FE));
    expect(AppThemeTokens.canvasDark, const Color(0xFF101B1D));
    expect(AppThemeTokens.actionLight, const Color(0xFF005DB5));
    expect(AppThemeTokens.actionDark, const Color(0xFF62A1FE));
    expect(AppThemeTokens.brandLight, const Color(0xFF002727));
    expect(AppThemeTokens.brandDark, const Color(0xFFA7CECD));
    expect(AppThemeTokens.recoveryLight, const Color(0xFF1DB84D));
    expect(AppThemeTokens.pressureLight, const Color(0xFFE5A15B));
    expect(AppThemeTokens.riskLight, const Color(0xFFBA1A1A));
  });

  test(
    'material levels expose selective blur defaults and shell breakpoints',
    () {
      expect(AppTheme.shellBreakpoint, 1200);
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

  testWidgets('workspace status chrome keeps its status-bar semantics', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: WorkspaceStatusBar(brand: '时序智配', title: '专注'),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('workspace-status-bar')), findsOneWidget);
    expect(find.byType(BackdropFilter), findsOneWidget);
  });
}
