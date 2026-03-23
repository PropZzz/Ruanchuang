import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shixuzhipei/main.dart';
import 'package:shixuzhipei/models/models.dart';
import 'package:shixuzhipei/services/app_services.dart';
import 'package:shixuzhipei/services/local_data_service.dart';
import 'package:shixuzhipei/services/local_persistence/local_persistence.dart';
import 'package:shixuzhipei/services/reminders/reminder_service.dart';

class _NoopReminderService extends ReminderService {
  @override
  Future<void> rescheduleDay({
    required DateTime day,
    required List<ScheduleEntry> entries,
  }) async {}

  @override
  Future<void> scheduleEntry({
    required DateTime day,
    required ScheduleEntry entry,
    DateTime? now,
  }) async {}
}

void main() {
  setUp(() {
    AppServices.resetForTests();
    AppServices.installTestOverrides(
      dataService: LocalDataService.forPersistence(InMemoryLocalPersistence()),
      reminderService: _NoopReminderService(),
    );
  });

  tearDown(() {
    AppServices.resetForTests();
  });

  testWidgets('BattleManApp builds shell', (tester) async {
    await tester.pumpWidget(const BattleManApp());
    await tester.pump();

    final hasNavBar = find.byType(NavigationBar).evaluate().isNotEmpty;
    final hasRail = find.byType(NavigationRail).evaluate().isNotEmpty;
    expect(hasNavBar || hasRail, true);
  });

  testWidgets('Smart calendar month view fits on small screens', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    try {
      await tester.pumpWidget(const BattleManApp());
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.calendar_month_outlined).first);
      await tester.pumpAndSettle();

      await tester.tap(find.text('月').last);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    } finally {
      await tester.binding.setSurfaceSize(null);
    }
  });

  testWidgets('Smart calendar gantt switch fits on small screens', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    try {
      await tester.pumpWidget(const BattleManApp());
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.calendar_month_outlined).first);
      await tester.pumpAndSettle();

      await tester.tap(find.text('甘特').last);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    } finally {
      await tester.binding.setSurfaceSize(null);
    }
  });
}
