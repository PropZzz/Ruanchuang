import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shixuzhipei/theme/app_theme.dart';
import 'package:shixuzhipei/widgets/glass_surface.dart';

void main() {
  testWidgets(
    'GlassSurface composes a blur layer without changing child semantics',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GlassSurface(child: const Text('timeline slot')),
          ),
        ),
      );

      expect(find.byType(BackdropFilter), findsOneWidget);
      expect(find.text('timeline slot'), findsOneWidget);
      expect(tester.getSize(find.text('timeline slot')), isNot(Size.zero));
    },
  );

  testWidgets('glass falls back to an opaque surface when disabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: GlassSurface(
            level: AppMaterialLevel.overlay,
            enabled: false,
            child: Text('fallback content'),
          ),
        ),
      ),
    );

    expect(find.byType(BackdropFilter), findsNothing);
    expect(find.text('fallback content'), findsOneWidget);
  });

  testWidgets('glass falls back in high contrast mode', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: MediaQuery(
          data: const MediaQueryData(highContrast: true),
          child: const Scaffold(
            body: GlassSurface(
              level: AppMaterialLevel.chrome,
              child: Text('high contrast content'),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(BackdropFilter), findsNothing);
    expect(find.text('high contrast content'), findsOneWidget);
  });
}
