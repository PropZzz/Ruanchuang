import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shixuzhipei/screens/smart_calendar_page.dart';
import 'package:shixuzhipei/services/app_services.dart';
import 'package:shixuzhipei/services/mock_data_service.dart';
import 'package:shixuzhipei/theme/app_theme.dart';
import 'package:shixuzhipei/widgets/rescue_plan_comparison.dart';

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
      expect(
        find.byKey(const ValueKey('calendar-source-label')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    }
  });

  Future<void> openRescueComparison(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const SmartCalendarPage()),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    await tester.tap(find.byIcon(Icons.bolt));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    final narrow = size.width < 760;
    if (narrow) {
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      await tester.tap(find.text('Insert urgent task and replan').last);
    } else {
      await tester.tap(find.byTooltip('Insert urgent task and replan'));
    }
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    await tester.tap(find.text('Insert and replan'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
  }

  testWidgets('rescue comparison uses a bottom sheet on phones', (
    tester,
  ) async {
    await openRescueComparison(tester, const Size(390, 844));

    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byType(RescuePlanComparison), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);

    await tester.tap(find.text('Keep current plan'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.byType(BottomSheet), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rescue comparison uses a fullscreen dialog on wide screens', (
    tester,
  ) async {
    await openRescueComparison(tester, const Size(1024, 768));

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byType(RescuePlanComparison), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);

    await tester.tap(find.text('Keep current plan'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.byType(Dialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
