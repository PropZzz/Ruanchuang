import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shixuzhipei/screens/smart_calendar_page.dart';
import 'package:shixuzhipei/services/app_services.dart';
import 'package:shixuzhipei/services/mock_data_service.dart';
import 'package:shixuzhipei/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    AppServices.installTestOverrides(dataService: MockDataService());
  });

  tearDown(AppServices.resetForTests);

  testWidgets('calendar exposes the time-map workbench regions', (
    tester,
  ) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    for (final width in [390.0, 1440.0]) {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.light, home: const SmartCalendarPage()),
      );
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));

      expect(
        find.byWidgetPredicate((widget) => widget is SegmentedButton),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('calendar-today-status')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('calendar-time-map')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('schedule-timeline-track')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('calendar-rescue-summary')),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.bolt), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}
