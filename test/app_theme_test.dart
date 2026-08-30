import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shixuzhipei/ui/app_theme.dart';

void main() {
  testWidgets('workbench theme uses the scheduling semantic colors', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light(), home: const Scaffold()),
    );

    final scheme = Theme.of(tester.element(find.byType(Scaffold))).colorScheme;
    expect(scheme.primary, const Color(0xFF153F45));
    expect(scheme.error, const Color(0xFFA8493B));
    expect(
      Theme.of(tester.element(find.byType(Scaffold))).cardTheme.shape,
      isA<RoundedRectangleBorder>(),
    );
  });

  testWidgets('dark theme uses the dark semantic colors', (tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.dark(), home: const Scaffold()),
    );

    final scheme = Theme.of(tester.element(find.byType(Scaffold))).colorScheme;
    expect(scheme.primary, const Color(0xFFA8D7C9));
    expect(scheme.error, const Color(0xFFE18B7D));
  });
}
