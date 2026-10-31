import 'package:shixuzhipei/main.dart';
import 'package:shixuzhipei/models/models.dart';
import 'package:shixuzhipei/screens/auth_dialog.dart';
import 'package:shixuzhipei/services/app_services.dart';
import 'package:shixuzhipei/services/local_data_service.dart';
import 'package:shixuzhipei/services/local_persistence/local_persistence.dart';
import 'package:shixuzhipei/services/reminders/reminder_service.dart';
import 'package:shixuzhipei/widgets/stitch_form_sheet.dart';
import 'package:shixuzhipei/widgets/urgent_task_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
    AppServices.logStore.clear();
    AppServices.installTestOverrides(
      dataService: LocalDataService.forPersistence(InMemoryLocalPersistence()),
      reminderService: _NoopReminderService(),
    );
  });

  tearDown(() {
    AppServices.resetForTests();
  });

  Future<void> launchApp(WidgetTester tester) async {
    await tester.pumpWidget(const BattleManApp());
    await tester.pumpAndSettle();
    if (find.byType(AuthDialog).evaluate().isNotEmpty) {
      await tester.tap(find.byTooltip('关闭登录'));
      await tester.pumpAndSettle();
    }
  }

  testWidgets('urgent card previews the block and returns the draft', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    await launchApp(tester);

    PlanTask? result;
    final context = tester.element(find.byType(Scaffold).first);
    showUrgentTaskDialog(
      context,
      // A past schedule day would fail the deadline validation on confirm.
      scheduleDay: DateTime.now(),
    ).then((value) {
      result = value;
    });
    await tester.pumpAndSettle();

    expect(find.byType(StitchFormSheet), findsOneWidget);
    expect(find.byKey(const ValueKey('calendar-urgent-preview')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('calendar-urgent-deadline-date')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('calendar-urgent-deadline-time')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    // The default title is pre-filled, so confirm starts enabled.
    final filledBefore = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '插入并重新规划'),
    );
    expect(filledBefore.onPressed, isNotNull);

    await tester.enterText(find.byType(TextField).first, '');
    await tester.pumpAndSettle();
    final filledEmpty = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '插入并重新规划'),
    );
    expect(filledEmpty.onPressed, isNull);

    await tester.enterText(find.byType(TextField).first, '处理线上故障');
    await tester.pumpAndSettle();
    await tester.tap(find.text('15'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('高'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('插入并重新规划'));
    await tester.pumpAndSettle();

    expect(find.byType(StitchFormSheet), findsNothing);
    expect(result, isNotNull);
    expect(result!.title, '处理线上故障');
    expect(result!.durationMinutes, 15);
    expect(result!.priority, 5);
    expect(result!.load, CognitiveLoad.high);
    expect(result!.tag, 'Urgent');
  });

  testWidgets('urgent card renders in desktop dialog', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    await launchApp(tester);

    await tester.tap(find.byKey(const ValueKey('shell-rail-schedule-icon')));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('插入紧急任务并重新规划'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.byKey(const ValueKey('calendar-urgent-preview')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
