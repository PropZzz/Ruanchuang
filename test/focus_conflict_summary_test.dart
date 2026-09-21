import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shixuzhipei/models/models.dart';
import 'package:shixuzhipei/screens/focus_page.dart';
import 'package:shixuzhipei/services/app_services.dart';
import 'package:shixuzhipei/services/mock_data_service.dart';
import 'package:shixuzhipei/theme/app_theme.dart';
import 'package:shixuzhipei/utils/schedule_occurrence.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    AppServices.installTestOverrides(dataService: MockDataService());
  });

  tearDown(AppServices.resetForTests);

  group('countScheduleConflicts', () {
    ScheduleEntry entry(int hour, int minute, double height) {
      return ScheduleEntry(
        title: 't$hour$minute',
        tag: 'work',
        height: height,
        color: Colors.blue,
        time: TimeOfDay(hour: hour, minute: minute),
      );
    }

    test('returns zero for non-overlapping entries', () {
      expect(countScheduleConflicts([entry(9, 0, 80), entry(10, 0, 80)]), 0);
    });

    test('counts each overlapping pair once', () {
      expect(countScheduleConflicts([entry(9, 0, 80), entry(9, 30, 80)]), 1);
      expect(
        countScheduleConflicts([
          entry(9, 0, 160),
          entry(9, 30, 80),
          entry(10, 0, 80),
        ]),
        3,
      );
    });

    test('touching boundaries do not conflict', () {
      expect(countScheduleConflicts([entry(9, 0, 80), entry(10, 0, 40)]), 0);
    });
  });

  group('focus page rhythm summary', () {
    Future<void> pumpFocus(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.light, home: const FocusPage()),
      );
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    testWidgets('shows the real conflict count for overlapping entries', (
      tester,
    ) async {
      final service = MockDataService();
      final today = dateOnly(DateTime.now());
      final a = ScheduleEntry(
        day: today,
        title: '冲突任务A',
        tag: 'work',
        height: 160,
        color: Colors.blue,
        time: const TimeOfDay(hour: 23, minute: 0),
      );
      final b = ScheduleEntry(
        day: today,
        title: '冲突任务B',
        tag: 'work',
        height: 80,
        color: Colors.red,
        time: const TimeOfDay(hour: 23, minute: 30),
      );
      // MockDataService uses real Future.delayed; run the seeding outside the
      // fake-async test zone so the futures can complete.
      await tester.runAsync(() async {
        await service.addScheduleEntry(a);
        await service.addScheduleEntry(b);
      });
      addTearDown(() async {
        await service.removeScheduleEntry(a);
        await service.removeScheduleEntry(b);
      });

      await pumpFocus(tester);

      final summary = find.byKey(const ValueKey('focus-conflict-summary'));
      expect(summary, findsOneWidget);
      expect(tester.widget<Text>(summary).data, contains('Needs attention 1'));
    });

    testWidgets('marks team windows as reserved instead of fake availability', (
      tester,
    ) async {
      await pumpFocus(tester);

      final teamWindow = find.byKey(
        const ValueKey('focus-team-window-summary'),
      );
      expect(teamWindow, findsOneWidget);
      expect(tester.widget<Text>(teamWindow).data, 'Team windows coming soon');
    });
  });
}
