import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shixuzhipei/screens/focus_page.dart';
import 'package:shixuzhipei/screens/smart_calendar_page.dart';
import 'package:shixuzhipei/services/app_services.dart';
import 'package:shixuzhipei/services/mock_data_service.dart';
import 'package:shixuzhipei/theme/app_theme.dart';
import 'package:shixuzhipei/widgets/energy_status_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    AppServices.installTestOverrides(dataService: MockDataService());
  });

  tearDown(AppServices.resetForTests);

  testWidgets(
    'focus page exposes energy status and an actionable empty state',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.light, home: const FocusPage()),
      );
      await tester.pumpAndSettle(const Duration(milliseconds: 100));

      expect(find.byKey(const ValueKey('focus-energy-status')), findsOneWidget);
      expect(find.byKey(const ValueKey('focus-task-empty')), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.textContaining('85%'), findsOneWidget);
    },
  );

  testWidgets('focus timeline action opens the full calendar', (tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const FocusPage()),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    await tester.tap(find.textContaining('View full calendar'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(find.byType(SmartCalendarPage), findsOneWidget);
  });

  testWidgets('energy card shows unavailable state when energy is missing', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const EnergyStatusCard(energy: null, emotion: null),
      ),
    );
    await tester.pump();

    expect(find.text('Energy data unavailable'), findsOneWidget);
    expect(find.textContaining('85%'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('focus header uses the current localized date', (tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const FocusPage()),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    final currentDate = MaterialLocalizations.of(
      tester.element(find.byType(FocusPage)),
    ).formatMediumDate(DateTime.now());
    expect(find.textContaining(currentDate), findsOneWidget);
    expect(find.textContaining('08 月 31 日'), findsNothing);
  });
}
