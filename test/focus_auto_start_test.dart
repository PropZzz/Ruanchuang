import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shixuzhipei/main.dart';
import 'package:shixuzhipei/models/models.dart';
import 'package:shixuzhipei/screens/auth_dialog.dart';
import 'package:shixuzhipei/services/app_services.dart';
import 'package:shixuzhipei/services/local_data_service.dart';
import 'package:shixuzhipei/services/local_persistence/local_persistence.dart';
import 'package:shixuzhipei/utils/schedule_occurrence.dart';

import 'support/noop_reminder_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    AppServices.resetForTests();
    AppServices.logStore.clear();
  });

  tearDown(() {
    AppServices.resetForTests();
  });

  Future<LocalDataService> installService(
    InMemoryLocalPersistence persistence,
  ) async {
    final service = LocalDataService.forPersistence(persistence);
    AppServices.installTestOverrides(
      dataService: service,
      reminderService: NoopReminderService(),
    );
    return service;
  }

  /// Schedule entries live at minute granularity, so round up to the next
  /// minute and add a full minute of margin: the auto-start watcher then
  /// always waits 61-120 real seconds and cannot fire while the test is
  /// still pumping the initial frames.
  TimeOfDay startAfterMargin() {
    final now = DateTime.now();
    final nextMinute = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute,
    ).add(const Duration(minutes: 2));
    return TimeOfDay(hour: nextMinute.hour, minute: nextMinute.minute);
  }

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(const BattleManApp());
    await tester.pumpAndSettle();
    if (find.byType(AuthDialog).evaluate().isNotEmpty) {
      await tester.tap(find.byTooltip('关闭登录'));
      await tester.pumpAndSettle();
    }
  }

  Future<Map<String, Object?>> persistedEntry(
    InMemoryLocalPersistence persistence,
    String id,
  ) async {
    final raw = await persistence.read();
    final root = Map<String, Object?>.from(jsonDecode(raw!) as Map);
    final schedule = (root['schedule'] as List).cast<Map>();
    return Map<String, Object?>.from(
      schedule.firstWhere((entry) => entry['id'] == id),
    );
  }

  testWidgets('the pomodoro card previews the next task and starts it on '
      'schedule', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final persistence = InMemoryLocalPersistence();
    final service = await installService(persistence);
    await service.addScheduleEntry(
      ScheduleEntry(
        id: 'sch_focus_auto',
        day: dateOnly(DateTime.now()),
        title: '自动开始测试任务',
        tag: 'Deep Work',
        height: 80,
        color: Colors.teal,
        time: startAfterMargin(),
      ),
    );

    await pumpApp(tester);

    // Before the start time the card previews the next task with its planned
    // countdown (60 minutes) and the automatic-start hint.
    expect(find.text('自动开始测试任务'), findsWidgets);
    expect(find.text('1:00:00'), findsOneWidget);
    expect(find.textContaining('到点自动开始'), findsWidgets);
    expect(find.text('结算'), findsNothing);

    // Advance past the scheduled start (61-120s away): the task promotes
    // itself and the countdown begins ticking without user action. (The
    // auto-start snackbar dismisses itself inside this window, so assert the
    // resulting running state.)
    await tester.pump(const Duration(seconds: 130));
    expect(find.text('专注状态中'), findsWidgets);

    await tester.pump(const Duration(seconds: 3));
    expect(find.text('1:00:00'), findsNothing);
  });

  testWidgets('settling a running task waits for the next scheduled start', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final persistence = InMemoryLocalPersistence();
    final service = await installService(persistence);
    final now = DateTime.now();
    for (final entry in [
      ScheduleEntry(
        id: 'running',
        day: dateOnly(now),
        title: '正在执行任务',
        tag: 'Routine',
        height: 80,
        color: Colors.teal,
        time: TimeOfDay(hour: now.hour, minute: now.minute),
      ),
      ScheduleEntry(
        id: 'waiting',
        day: dateOnly(now),
        title: '下一计划任务',
        tag: 'Routine',
        height: 40,
        color: Colors.teal,
        time: startAfterMargin(),
      ),
    ]) {
      await service.addScheduleEntry(entry);
    }
    await pumpApp(tester);
    await tester.tap(find.text('开始专注'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('专注状态中'), findsWidgets);
    await tester.tap(find.text('结算'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    expect(find.textContaining('到点自动开始'), findsWidgets);
    expect(find.text('30:00'), findsNWidgets(2));
    expect(find.text('专注状态中'), findsNothing);
    await tester.pump(const Duration(seconds: 130));
    expect(find.text('专注状态中'), findsWidgets);
  });

  for (final floating in [false, true]) {
    testWidgets(
      floating
          ? 'starting a floating daily task preserves its recurrence'
          : 'starting the next task early moves its calendar slot to now',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final persistence = InMemoryLocalPersistence();
        final service = await installService(persistence);
        final scheduledStart = DateTime.now().add(const Duration(minutes: 10));
        await service.addScheduleEntry(
          ScheduleEntry(
            id: 'sch_focus_early',
            day: floating ? null : dateOnly(DateTime.now()),
            title: '提前开始测试任务',
            tag: 'Deep Work',
            height: 80,
            color: Colors.teal,
            time: TimeOfDay(
              hour: scheduledStart.hour,
              minute: scheduledStart.minute,
            ),
          ),
        );

        await pumpApp(tester);

        final beforeTap = DateTime.now();
        await tester.tap(find.text('开始专注'));
        await tester.pump(const Duration(milliseconds: 200));
        await tester.pump(const Duration(milliseconds: 200));
        final afterTap = DateTime.now();

        if (!floating) expect(find.textContaining('已提前开始'), findsOneWidget);
        expect(find.text('专注状态中'), findsWidgets);

        final moved = await persistedEntry(persistence, 'sch_focus_early');
        final movedTime = Map<String, Object?>.from(moved['time'] as Map);
        final movedMinutes =
            (movedTime['hour'] as int) * 60 + (movedTime['minute'] as int);
        final firstMinute = beforeTap.hour * 60 + beforeTap.minute;
        final lastMinute = afterTap.hour * 60 + afterTap.minute;
        final scheduledMinutes =
            scheduledStart.hour * 60 + scheduledStart.minute;
        if (floating) {
          expect(moved['day'], isNull);
          expect(movedMinutes, scheduledMinutes);
        } else {
          expect(movedMinutes, inInclusiveRange(firstMinute, lastMinute));
          expect(movedMinutes, isNot(scheduledMinutes));
        }
      },
    );
  }
}
