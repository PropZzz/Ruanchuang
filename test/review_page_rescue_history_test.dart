import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shixuzhipei/models/models.dart';
import 'package:shixuzhipei/screens/review_page.dart';
import 'package:shixuzhipei/services/app_services.dart';
import 'package:shixuzhipei/services/data_service.dart';
import 'package:shixuzhipei/services/local_data_service.dart';
import 'package:shixuzhipei/services/local_persistence/local_persistence.dart';

class _FailingReviewDataService implements DataService {
  _FailingReviewDataService(this._inner);

  final DataService _inner;
  bool failTaskEvents = false;
  bool failWeeklyReport = false;
  bool failUpsertTaskEvents = false;
  int upsertTaskEventsCalls = 0;

  @override
  Future<void> logTaskEvent(TaskEvent event) => _inner.logTaskEvent(event);

  @override
  Future<void> upsertTaskEvents(List<TaskEvent> events) {
    upsertTaskEventsCalls++;
    if (failUpsertTaskEvents) {
      return Future<void>.error(StateError('event batch unavailable'));
    }
    return _inner.upsertTaskEvents(events);
  }

  @override
  Future<List<TaskEvent>> getTaskEvents(DateTime from, DateTime to) {
    if (failTaskEvents) {
      return Future<List<TaskEvent>>.error(StateError('events unavailable'));
    }
    return _inner.getTaskEvents(from, to);
  }

  @override
  Future<ReviewReport> getWeeklyReport(DateTime weekStart) {
    if (failWeeklyReport) {
      return Future<ReviewReport>.error(StateError('report unavailable'));
    }
    return _inner.getWeeklyReport(weekStart);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _BlockingReviewDataService implements DataService {
  _BlockingReviewDataService(this._inner);

  final DataService _inner;
  final events = Completer<List<TaskEvent>>();

  @override
  Future<void> logTaskEvent(TaskEvent event) => _inner.logTaskEvent(event);

  @override
  Future<List<TaskEvent>> getTaskEvents(DateTime from, DateTime to) =>
      events.future;

  @override
  Future<ReviewReport> getWeeklyReport(DateTime weekStart) =>
      _inner.getWeeklyReport(weekStart);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

TaskEvent _event({
  required String id,
  required DateTime at,
  required String reason,
  required String title,
}) {
  return TaskEvent(
    id: id,
    taskId: 'urgent-1',
    title: title,
    tag: 'Urgent',
    at: at,
    type: TaskEventType.interrupt,
    reason: reason,
  );
}

ButtonStyleButton _buttonWithIcon(WidgetTester tester, IconData icon) {
  return tester.widget<ButtonStyleButton>(
    find.ancestor(
      of: find.byIcon(icon),
      matching: find.byWidgetPredicate((widget) => widget is ButtonStyleButton),
    ),
  );
}

void main() {
  setUp(() {
    AppServices.resetForTests();
    AppServices.logStore.clear();
  });

  tearDown(() {
    AppServices.resetForTests();
    AppServices.logStore.clear();
  });

  testWidgets('review page shows rescue acceptance and undo records', (
    tester,
  ) async {
    final fixed = DateTime(2026, 8, 6, 12);
    final day = DateTime(fixed.year, fixed.month, fixed.day);
    final local = LocalDataService.forPersistence(InMemoryLocalPersistence());
    await local.logTaskEvent(
      _event(
        id: 'rescue-accept',
        at: day.add(const Duration(hours: 9)),
        reason: 'rescue_accept:protectRecovery',
        title: '客户紧急问题',
      ),
    );
    await local.logTaskEvent(
      _event(
        id: 'rescue-undo',
        at: day.add(const Duration(hours: 10)),
        reason: 'rescue_undo:protectRecovery',
        title: '客户紧急问题',
      ),
    );
    await local.logTaskEvent(
      _event(
        id: 'unrelated-interrupt',
        at: day.add(const Duration(hours: 11)),
        reason: 'notifications',
        title: '无关打断事件',
      ),
    );
    AppServices.installTestOverrides(dataService: local);

    await tester.pumpWidget(
      MaterialApp(
        locale: Locale('zh', 'CN'),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: [Locale('zh', 'CN')],
        home: ReviewPage(clock: () => fixed),
      ),
    );
    await tester.tap(find.text('生成报告'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('日程救援记录'),
      250,
      scrollable: find.byType(Scrollable),
    );

    expect(find.text('日程救援记录'), findsOneWidget);
    expect(find.text('客户紧急问题'), findsNWidgets(2));
    expect(find.textContaining('优先保留恢复时间'), findsNWidgets(2));
    expect(find.text('已采用'), findsOneWidget);
    expect(find.text('已撤销'), findsOneWidget);
    expect(find.text('无关打断事件'), findsNothing);

    final rescueTiles = tester.widgetList<ListTile>(find.byType(ListTile));
    expect((rescueTiles.first.trailing! as Text).data, '已撤销');
  });

  testWidgets('review history uses English text and a neutral separator', (
    tester,
  ) async {
    final fixed = DateTime(2026, 8, 6, 12);
    final local = LocalDataService.forPersistence(InMemoryLocalPersistence());
    await local.logTaskEvent(
      _event(
        id: 'english-rescue',
        at: DateTime(2026, 8, 6, 10),
        reason: 'rescue_accept:protectRecovery',
        title: 'Customer escalation',
      ),
    );
    AppServices.installTestOverrides(dataService: local);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en', 'US'),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('en', 'US')],
        home: ReviewPage(clock: () => fixed),
      ),
    );
    await tester.tap(find.text('Generate Report'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Schedule Rescue History'),
      250,
      scrollable: find.byType(Scrollable),
    );

    expect(find.text('Schedule Rescue History'), findsOneWidget);
    expect(find.textContaining(' - Protect Recovery Time'), findsOneWidget);
    expect(find.text('优先保留恢复时间'), findsNothing);
    expect(find.text('已采用'), findsNothing);
    expect(find.textContaining('路'), findsNothing);
  });

  testWidgets('failed review generation restores controls and keeps history', (
    tester,
  ) async {
    final fixed = DateTime(2026, 8, 6, 12);
    final local = LocalDataService.forPersistence(InMemoryLocalPersistence());
    await local.logTaskEvent(
      _event(
        id: 'existing-rescue',
        at: DateTime(2026, 8, 6, 10),
        reason: 'rescue_accept:protectDeadline',
        title: 'Existing rescue',
      ),
    );
    final dataService = _FailingReviewDataService(local);
    AppServices.installTestOverrides(dataService: dataService);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en', 'US'),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('en', 'US')],
        home: ReviewPage(clock: () => fixed),
      ),
    );
    await tester.tap(find.text('Generate Report'));
    await tester.pumpAndSettle();
    expect(find.text('Completion'), findsOneWidget);
    expect(find.text('0% (0/0)'), findsOneWidget);

    dataService.failTaskEvents = true;
    await tester.tap(find.text('Generate Report'));
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Generate Report'),
          )
          .onPressed,
      isNotNull,
    );
    expect(find.text('Completion'), findsOneWidget);
    expect(find.text('0% (0/0)'), findsOneWidget);
    expect(
      find.text('Unable to generate the review. Please try again.'),
      findsOneWidget,
    );

    await tester.scrollUntilVisible(
      find.text('Schedule Rescue History'),
      250,
      scrollable: find.byType(Scrollable),
    );
    expect(find.text('Existing rescue'), findsOneWidget);
  });

  testWidgets('review range navigation is disabled while generating', (
    tester,
  ) async {
    final fixed = DateTime(2026, 8, 6, 12);
    final local = LocalDataService.forPersistence(InMemoryLocalPersistence());
    final dataService = _BlockingReviewDataService(local);
    AppServices.installTestOverrides(dataService: dataService);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'CN'),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('zh', 'CN')],
        home: ReviewPage(clock: () => fixed),
      ),
    );
    await tester.tap(find.text('生成报告'));
    await tester.pump();

    final loadingSegmentedButton =
        tester.widget(
              find.byWidgetPredicate((widget) => widget is SegmentedButton),
            )
            as dynamic;
    expect(loadingSegmentedButton.onSelectionChanged, isNull);

    expect(
      tester
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.chevron_left),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.chevron_right),
          )
          .onPressed,
      isNull,
    );
    expect(_buttonWithIcon(tester, Icons.science_outlined).onPressed, isNull);
    expect(_buttonWithIcon(tester, Icons.refresh).onPressed, isNull);

    dataService.events.complete(const []);
    await tester.pumpAndSettle();
    final completedSegmentedButton =
        tester.widget(
              find.byWidgetPredicate((widget) => widget is SegmentedButton),
            )
            as dynamic;
    expect(completedSegmentedButton.onSelectionChanged, isNotNull);
    expect(
      tester
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.chevron_left),
          )
          .onPressed,
      isNotNull,
    );
    expect(
      _buttonWithIcon(tester, Icons.science_outlined).onPressed,
      isNotNull,
    );
    expect(_buttonWithIcon(tester, Icons.refresh).onPressed, isNotNull);
  });

  testWidgets(
    'failed batch persistence leaves simulation unreported and local history unchanged',
    (tester) async {
    final fixed = DateTime(2026, 8, 6, 12);
    final local = LocalDataService.forPersistence(InMemoryLocalPersistence());
    final dataService = _FailingReviewDataService(local)
      ..failUpsertTaskEvents = true;
    AppServices.installTestOverrides(dataService: dataService);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en', 'US'),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('en', 'US')],
        home: ReviewPage(clock: () => fixed),
      ),
    );
    await tester.tap(find.text('Simulate 1 Week'));
    await tester.pumpAndSettle();

    expect(dataService.upsertTaskEventsCalls, 1);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(
      _buttonWithIcon(tester, Icons.science_outlined).onPressed,
      isNotNull,
    );
    expect(
      find.text('Unable to simulate the week. Please try again.'),
      findsOneWidget,
    );
    expect(find.text('Completion'), findsNothing);
    expect(
      await local.getTaskEvents(DateTime(2026, 8, 3), DateTime(2026, 8, 10)),
      isEmpty,
    );
    expect(
      AppServices.logStore.entries
          .map((entry) => entry.message)
          .where((message) => message == 'simulate failed'),
      hasLength(1),
    );
    },
  );

  testWidgets('failed week shifts keep the previous report and history range', (
    tester,
  ) async {
    final fixed = DateTime(2026, 8, 6, 12);
    final local = LocalDataService.forPersistence(InMemoryLocalPersistence());
    await local.logTaskEvent(
      _event(
        id: 'week-rescue',
        at: DateTime(2026, 8, 6, 10),
        reason: 'rescue_accept:protectDeadline',
        title: 'Week rescue',
      ),
    );
    final dataService = _FailingReviewDataService(local);
    AppServices.installTestOverrides(dataService: dataService);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en', 'US'),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('en', 'US')],
        home: ReviewPage(clock: () => fixed),
      ),
    );
    await tester.tap(find.text('Generate Report'));
    await tester.pumpAndSettle();
    expect(find.text('2026-08-03'), findsOneWidget);
    expect(find.text('Completion'), findsOneWidget);

    dataService.failTaskEvents = true;
    await tester.tap(find.widgetWithIcon(IconButton, Icons.chevron_right));
    await tester.pumpAndSettle();

    expect(find.text('2026-08-03'), findsOneWidget);
    expect(find.text('Completion'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Schedule Rescue History'),
      250,
      scrollable: find.byType(Scrollable),
    );
    expect(find.text('Week rescue'), findsOneWidget);
  });

  testWidgets(
    'simulation reports one generate error when event writes succeed',
    (tester) async {
      final fixed = DateTime(2026, 8, 6, 12);
      final local = LocalDataService.forPersistence(InMemoryLocalPersistence());
      final dataService = _FailingReviewDataService(local)
        ..failWeeklyReport = true;
      AppServices.installTestOverrides(dataService: dataService);

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en', 'US'),
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          supportedLocales: const [Locale('en', 'US')],
          home: ReviewPage(clock: () => fixed),
        ),
      );
      await tester.tap(find.text('Simulate 1 Week'));
      await tester.pumpAndSettle();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(
        find.text('Unable to generate the review. Please try again.'),
        findsOneWidget,
      );
      expect(
        find.text('Unable to simulate the week. Please try again.'),
        findsNothing,
      );
      final messages = AppServices.logStore.entries.map(
        (entry) => entry.message,
      );
      expect(
        messages.where((message) => message == 'generate failed'),
        hasLength(1),
      );
      expect(
        messages.where((message) => message == 'simulate failed'),
        isEmpty,
      );
    },
  );

  testWidgets(
    'failed week-to-month changes keep the previous report and history range',
    (tester) async {
      final fixed = DateTime(2026, 8, 6, 12);
      final local = LocalDataService.forPersistence(InMemoryLocalPersistence());
      await local.logTaskEvent(
        _event(
          id: 'week-to-month-rescue',
          at: DateTime(2026, 8, 6, 10),
          reason: 'rescue_accept:protectDeadline',
          title: 'Week to month rescue',
        ),
      );
      final dataService = _FailingReviewDataService(local);
      AppServices.installTestOverrides(dataService: dataService);

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en', 'US'),
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          supportedLocales: const [Locale('en', 'US')],
          home: ReviewPage(clock: () => fixed),
        ),
      );
      await tester.tap(find.text('Generate Report'));
      await tester.pumpAndSettle();
      expect(find.text('2026-08-03'), findsOneWidget);
      expect(find.text('Completion'), findsOneWidget);

      dataService.failTaskEvents = true;
      await tester.tap(find.text('月'));
      await tester.pumpAndSettle();

      expect(find.text('2026-08-03'), findsOneWidget);
      expect(find.text('Completion'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Schedule Rescue History'),
        250,
        scrollable: find.byType(Scrollable),
      );
      expect(find.text('Week to month rescue'), findsOneWidget);
    },
  );

  testWidgets(
    'failed month shifts keep the previous monthly report and history range',
    (tester) async {
      final fixed = DateTime(2026, 8, 6, 12);
      final local = LocalDataService.forPersistence(InMemoryLocalPersistence());
      await local.logTaskEvent(
        _event(
          id: 'month-shift-rescue',
          at: DateTime(2026, 8, 6, 10),
          reason: 'rescue_accept:protectDeadline',
          title: 'Month shift rescue',
        ),
      );
      final dataService = _FailingReviewDataService(local);
      AppServices.installTestOverrides(dataService: dataService);

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en', 'US'),
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          supportedLocales: const [Locale('en', 'US')],
          home: ReviewPage(clock: () => fixed),
        ),
      );
      await tester.tap(find.text('月'));
      await tester.pumpAndSettle();
      expect(find.text('August 2026'), findsOneWidget);
      expect(find.text('月度完成率'), findsOneWidget);

      dataService.failTaskEvents = true;
      await tester.tap(find.widgetWithIcon(IconButton, Icons.chevron_right));
      await tester.pumpAndSettle();

      expect(find.text('August 2026'), findsOneWidget);
      expect(find.text('月度完成率'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Schedule Rescue History'),
        250,
        scrollable: find.byType(Scrollable),
      );
      expect(find.text('Month shift rescue'), findsOneWidget);
    },
  );
}
