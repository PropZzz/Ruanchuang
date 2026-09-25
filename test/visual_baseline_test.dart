import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shixuzhipei/models/models.dart';
import 'package:shixuzhipei/screens/focus_page.dart';
import 'package:shixuzhipei/screens/smart_calendar_page.dart';
import 'package:shixuzhipei/services/app_services.dart';
import 'package:shixuzhipei/services/mock_data_service.dart';
import 'package:shixuzhipei/theme/app_theme.dart';
import 'package:shixuzhipei/utils/schedule_occurrence.dart';

import 'support/noop_reminder_service.dart';

/// Five-size layout baseline for the member-C main path (Focus + calendar).
///
/// Golden PNGs render with the test font, so they capture layout, overflow
/// and state structure — not brand typography. Real-device screenshots are a
/// separate acceptance step (see docs/visual-qa/member-c-baseline.md).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const sizes = <String, Size>{
    '375x812': Size(375, 812),
    '390x844': Size(390, 844),
    '720x900': Size(720, 900),
    '1024x768': Size(1024, 768),
    '1440x900': Size(1440, 900),
  };

  setUp(() {
    AppServices.installTestOverrides(
      dataService: MockDataService(),
      reminderService: NoopReminderService(),
    );
  });

  tearDown(AppServices.resetForTests);

  Future<void> seedSchedule(
    WidgetTester tester,
    MockDataService service,
  ) async {
    final today = dateOnly(DateTime.now());
    final entries = [
      ScheduleEntry(
        day: today,
        title: 'Baseline deep work',
        tag: 'work',
        height: 160,
        color: Colors.blue,
        time: const TimeOfDay(hour: 9, minute: 0),
      ),
      ScheduleEntry(
        day: today,
        title: 'Baseline review',
        tag: 'work',
        height: 80,
        color: Colors.green,
        time: const TimeOfDay(hour: 14, minute: 0),
      ),
    ];
    await tester.runAsync(() async {
      for (final entry in entries) {
        await service.addScheduleEntry(entry);
      }
    });
    addTearDown(() async {
      for (final entry in entries) {
        await service.removeScheduleEntry(entry);
      }
    });
  }

  Future<void> pumpPage(WidgetTester tester, Size size, Widget page) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: page));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 400));
  }

  for (final entry in sizes.entries) {
    testWidgets('focus page baseline ${entry.key}', (tester) async {
      await seedSchedule(tester, MockDataService());
      await pumpPage(tester, entry.value, const FocusPage());
      // Focus is wall-clock dependent (current/next task split), so it gets a
      // structural baseline instead of a pixel golden.
      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const ValueKey('focus-conflict-summary')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('focus-source-label')), findsOneWidget);
    });

    testWidgets('calendar page baseline ${entry.key}', (tester) async {
      await seedSchedule(tester, MockDataService());
      await pumpPage(tester, entry.value, const SmartCalendarPage());
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(SmartCalendarPage),
        matchesGoldenFile('goldens/visual_baseline/calendar_${entry.key}.png'),
      );
    });
  }
}
