import 'package:shixuzhipei/main.dart';
import 'package:shixuzhipei/models/models.dart';
import 'package:shixuzhipei/screens/auth_dialog.dart';
import 'package:shixuzhipei/services/app_services.dart';
import 'package:shixuzhipei/services/local_data_service.dart';
import 'package:shixuzhipei/services/local_persistence/local_persistence.dart';
import 'package:shixuzhipei/services/reminders/reminder_service.dart';
import 'package:shixuzhipei/widgets/stitch_form_sheet.dart';
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

  testWidgets('add schedule card previews the block on a narrow sheet', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    await tester.pumpWidget(const BattleManApp());
    await tester.pumpAndSettle();
    if (find.byType(AuthDialog).evaluate().isNotEmpty) {
      await tester.tap(find.byTooltip('关闭登录'));
      await tester.pumpAndSettle();
    }

    await tester.tap(find.byKey(const ValueKey('shell-nav-schedule')));
    await tester.pumpAndSettle();

    expect(find.byType(StitchFormSheet), findsNothing);
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    expect(find.byType(StitchFormSheet), findsOneWidget);
    expect(find.byKey(const ValueKey('calendar-add-preview')), findsOneWidget);
    // The tag label shows in both the preview strip and the tag chip.
    expect(find.text('深度工作'), findsNWidgets(2));
    expect(tester.takeException(), isNull);

    // Confirm stays disabled until a title is entered.
    final filledBefore = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '添加'),
    );
    expect(filledBefore.onPressed, isNull);

    await tester.enterText(find.byType(TextField).first, '写周报');
    await tester.pumpAndSettle();
    final filledAfter = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '添加'),
    );
    expect(filledAfter.onPressed, isNotNull);

    await tester.tap(find.text('添加'));
    await tester.pumpAndSettle();

    expect(find.byType(StitchFormSheet), findsNothing);
  });

  testWidgets('add schedule card renders in desktop dialog', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    await tester.pumpWidget(const BattleManApp());
    await tester.pumpAndSettle();
    if (find.byType(AuthDialog).evaluate().isNotEmpty) {
      await tester.tap(find.byTooltip('关闭登录'));
      await tester.pumpAndSettle();
    }

    await tester.tap(find.byKey(const ValueKey('shell-rail-schedule-icon')));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.byKey(const ValueKey('calendar-add-preview')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
