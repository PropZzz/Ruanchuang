import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shixuzhipei/main.dart';
import 'package:shixuzhipei/models/models.dart';
import 'package:shixuzhipei/screens/auth_dialog.dart';
import 'package:shixuzhipei/screens/smart_calendar_page.dart';
import 'package:shixuzhipei/services/app_services.dart';
import 'package:shixuzhipei/services/data_service.dart';
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

class _RecordingReminderService extends _NoopReminderService {
  _RecordingReminderService({this.throwOnReschedule = false});

  final bool throwOnReschedule;
  final List<List<ScheduleEntry>> rescheduleCalls = [];

  @override
  Future<void> rescheduleDay({
    required DateTime day,
    required List<ScheduleEntry> entries,
  }) async {
    rescheduleCalls.add(List<ScheduleEntry>.from(entries));
    if (throwOnReschedule) {
      throw StateError('reminder unavailable');
    }
  }
}

class _FatigueDataService implements DataService {
  _FatigueDataService(this._inner);

  final DataService _inner;
  final Map<String, TaskEvent> _taskEvents = {};

  @override
  Future<EmotionType> getCurrentEmotion() async => EmotionType.fatigue;

  @override
  Future<EmotionState> getEmotionState() => _inner.getEmotionState();

  @override
  Future<void> addEmotionCheckIn(EmotionCheckIn checkIn) =>
      _inner.addEmotionCheckIn(checkIn);

  @override
  Future<List<EmotionCheckIn>> getEmotionCheckIns(DateTime day) =>
      _inner.getEmotionCheckIns(day);

  @override
  Future<EnergyStatus> getEnergyStatus() => _inner.getEnergyStatus();

  @override
  Future<List<Goal>> getGoals() => _inner.getGoals();

  @override
  Future<void> upsertGoal(Goal goal) => _inner.upsertGoal(goal);

  @override
  Future<void> deleteGoal(String goalId) => _inner.deleteGoal(goalId);

  @override
  Future<Task> getCurrentTask() => _inner.getCurrentTask();

  @override
  Future<List<Task>> getNextTasks() => _inner.getNextTasks();

  @override
  Future<List<ScheduleEntry>> getScheduleEntries() =>
      _inner.getScheduleEntries();

  @override
  Future<void> addScheduleEntry(ScheduleEntry entry) =>
      _inner.addScheduleEntry(entry);

  @override
  Future<void> removeScheduleEntry(ScheduleEntry entry) =>
      _inner.removeScheduleEntry(entry);

  @override
  Future<List<MicroTask>> getMicroTasks() => _inner.getMicroTasks();

  @override
  Future<void> addMicroTask(MicroTask task) => _inner.addMicroTask(task);

  @override
  Future<void> removeMicroTask(MicroTask task) => _inner.removeMicroTask(task);

  @override
  Future<void> updateMicroTask(MicroTask task) => _inner.updateMicroTask(task);

  @override
  Future<List<TeamMember>> getTeamMembers() => _inner.getTeamMembers();

  @override
  Future<UserProfile> getUserProfile() => _inner.getUserProfile();

  @override
  Future<void> setFavoriteDevice(String deviceId) =>
      _inner.setFavoriteDevice(deviceId);

  @override
  Future<String?> getFavoriteDevice() => _inner.getFavoriteDevice();

  @override
  Future<String> getThemeMode() => _inner.getThemeMode();

  @override
  Future<void> setThemeMode(String themeMode) => _inner.setThemeMode(themeMode);

  @override
  Future<String> getLocale() => _inner.getLocale();

  @override
  Future<void> setLocale(String locale) => _inner.setLocale(locale);

  @override
  Future<void> logTaskEvent(TaskEvent event) => upsertTaskEvents([event]);

  @override
  Future<void> upsertTaskEvents(List<TaskEvent> events) async {
    for (final event in events) {
      _taskEvents[event.id] = event;
    }
  }

  @override
  Future<List<TaskEvent>> getTaskEvents(DateTime from, DateTime to) async =>
      _taskEvents.values
          .where((event) => !event.at.isBefore(from) && event.at.isBefore(to))
          .toList(growable: false);

  @override
  Future<ReviewReport> getWeeklyReport(DateTime weekStart) =>
      _inner.getWeeklyReport(weekStart);

  @override
  Future<SchedulingTuning> getSchedulingTuning() =>
      _inner.getSchedulingTuning();

  @override
  Future<void> setSchedulingTuning(SchedulingTuning tuning) =>
      _inner.setSchedulingTuning(tuning);

  @override
  Future<List<TeamMemberCalendar>> getTeamCalendars(DateTime day) =>
      _inner.getTeamCalendars(day);

  @override
  Future<void> upsertTeamMember(TeamMemberCalendar member) =>
      _inner.upsertTeamMember(member);

  @override
  Future<void> deleteTeamMember(String memberId) =>
      _inner.deleteTeamMember(memberId);

  @override
  Future<void> updateTeamSharePermission(
    String memberId,
    TeamSharePermission permission,
  ) => _inner.updateTeamSharePermission(memberId, permission);

  @override
  Future<void> bookTeamMeeting(DateTime day, TeamMeetingRequest request) =>
      _inner.bookTeamMeeting(day, request);

  @override
  Future<UserAccount?> getCurrentUser() => _inner.getCurrentUser();

  @override
  Future<bool> login(String account, String password) =>
      _inner.login(account, password);

  @override
  Future<bool> registerAccount({
    required String username,
    required String password,
  }) => _inner.registerAccount(username: username, password: password);

  @override
  Future<void> logout() => _inner.logout();
}

class _UndoPersistenceFailingDataService extends _FatigueDataService {
  _UndoPersistenceFailingDataService(super.inner);

  bool failScheduleWrites = false;

  @override
  Future<void> addScheduleEntry(ScheduleEntry entry) {
    if (failScheduleWrites) {
      throw StateError('schedule write unavailable');
    }
    return super.addScheduleEntry(entry);
  }

  @override
  Future<void> removeScheduleEntry(ScheduleEntry entry) {
    if (failScheduleWrites) {
      throw StateError('schedule write unavailable');
    }
    return super.removeScheduleEntry(entry);
  }
}

class _EventFailingDataService extends _FatigueDataService {
  _EventFailingDataService(super.inner);

  @override
  Future<void> logTaskEvent(TaskEvent event) =>
      Future<void>.error(StateError('event store unavailable'));
}

class _EmptyTeamDataService extends _FatigueDataService {
  _EmptyTeamDataService(super.inner);

  @override
  Future<List<TeamMember>> getTeamMembers() async => const [];

  @override
  Future<List<TeamMemberCalendar>> getTeamCalendars(DateTime day) async =>
      const [];
}

class _BlockingImportDataService extends _FatigueDataService {
  _BlockingImportDataService(super.inner);

  final Completer<void> addScheduleEntryCompleter = Completer<void>();
  final Completer<List<ScheduleEntry>> reloadEntriesCompleter = Completer();
  bool blockReloadEntries = false;

  @override
  Future<List<ScheduleEntry>> getScheduleEntries() {
    if (blockReloadEntries) return reloadEntriesCompleter.future;
    return super.getScheduleEntries();
  }

  @override
  Future<void> addScheduleEntry(ScheduleEntry entry) async {
    await addScheduleEntryCompleter.future;
    await super.addScheduleEntry(entry);
  }
}

class _BlockingReminderService extends _NoopReminderService {
  final Completer<void> rescheduleCompleter = Completer<void>();
  bool blockReschedule = false;

  @override
  Future<void> rescheduleDay({
    required DateTime day,
    required List<ScheduleEntry> entries,
  }) {
    if (blockReschedule) return rescheduleCompleter.future;
    return super.rescheduleDay(day: day, entries: entries);
  }
}

Future<void> _dismissStartupAuthIfShown(WidgetTester tester) async {
  if (find.byType(AuthDialog).evaluate().isEmpty) return;
  await tester.tap(find.byTooltip('关闭登录'));
  await tester.pumpAndSettle();
}

Future<void> _openSmartCalendar(WidgetTester tester) async {
  await tester.pumpWidget(const BattleManApp());
  await tester.pumpAndSettle();
  await _dismissStartupAuthIfShown(tester);

  await tester.tap(find.byKey(const ValueKey('shell-rail-schedule-icon')));
  await tester.pumpAndSettle();

  await tester.tap(find.byTooltip('切换到智能规划'));
  await tester.pumpAndSettle();
}

Future<void> _selectDefaultRescue(WidgetTester tester) async {
  await tester.tap(find.byTooltip('插入紧急任务并重新规划'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('插入并重新规划'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('优先保住截止时间'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('采用此方案'));
  await tester.pumpAndSettle();
}

String _validIcsFor(DateTime day) {
  final date =
      '${day.year.toString().padLeft(4, '0')}${day.month.toString().padLeft(2, '0')}${day.day.toString().padLeft(2, '0')}';
  return '''
BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
UID:import-blocked
DTSTART:${date}T090000
DTEND:${date}T093000
SUMMARY:Imported calendar event
END:VEVENT
END:VCALENDAR
''';
}

void _setWideSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1024, 900);
  tester.view.devicePixelRatio = 1.0;
}

void _resetSurface(WidgetTester tester) {
  tester.view.resetPhysicalSize();
  tester.view.resetDevicePixelRatio();
}

Iterable<ScheduleEntry> _urgentEntries(List<ScheduleEntry> entries) =>
    entries.where((entry) => entry.id?.startsWith('urgent_') ?? false);

void main() {
  test('Fatigue fake batch upserts events by stable ID', () async {
    final fake = _FatigueDataService(
      LocalDataService.forPersistence(InMemoryLocalPersistence()),
    );
    final first = TaskEvent(
      id: 'smoke-event-1',
      taskId: 'task-1',
      title: 'First',
      tag: 'Focus',
      at: DateTime(2026, 8, 6, 9),
      type: TaskEventType.start,
    );
    final second = TaskEvent(
      id: 'smoke-event-2',
      taskId: 'task-2',
      title: 'Second',
      tag: 'Study',
      at: DateTime(2026, 8, 6, 10),
      type: TaskEventType.complete,
    );

    await fake.upsertTaskEvents([first, second]);
    await fake.upsertTaskEvents([
      TaskEvent(
        id: first.id,
        taskId: first.taskId,
        title: 'First updated',
        tag: first.tag,
        at: first.at,
        type: first.type,
      ),
    ]);

    final events = await fake.getTaskEvents(
      DateTime(2026, 8, 6),
      DateTime(2026, 8, 7),
    );
    expect(events, hasLength(2));
    expect(
      events.singleWhere((event) => event.id == first.id).title,
      'First updated',
    );
  });

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

  testWidgets('BattleManApp builds shell', (tester) async {
    await tester.pumpWidget(const BattleManApp());
    await tester.pumpAndSettle();

    expect(find.byType(AuthDialog), findsOneWidget);
    await _dismissStartupAuthIfShown(tester);

    final hasNavBar = find.byType(NavigationBar).evaluate().isNotEmpty;
    final hasRail = find.byType(NavigationRail).evaluate().isNotEmpty;
    expect(hasNavBar || hasRail, true);
  });

  testWidgets('wide shell exposes all primary destinations', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    try {
      await tester.pumpWidget(const BattleManApp());
      await tester.pumpAndSettle();
      await _dismissStartupAuthIfShown(tester);

      for (final label in ['专注', '日程', '微任务', '团队', '我的']) {
        expect(find.text(label), findsWidgets);
      }
      expect(tester.takeException(), isNull);
    } finally {
      await tester.binding.setSurfaceSize(null);
    }
  });

  testWidgets('narrow shell exposes keyed destinations', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    try {
      await tester.pumpWidget(const BattleManApp());
      await tester.pumpAndSettle();
      await _dismissStartupAuthIfShown(tester);

      for (final id in ['focus', 'schedule', 'micro', 'team', 'profile']) {
        expect(find.byKey(ValueKey('shell-nav-$id')), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    } finally {
      await tester.binding.setSurfaceSize(null);
    }
  });

  testWidgets('focus page keeps the current task action visible on mobile', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    try {
      await tester.pumpWidget(const BattleManApp());
      await tester.pumpAndSettle();
      await _dismissStartupAuthIfShown(tester);

      expect(find.text('当前任务'), findsOneWidget);
      expect(find.text('开始').first, findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.binding.setSurfaceSize(null);
    }
  });

  testWidgets('micro task page keeps add and batch actions accessible', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    try {
      await tester.pumpWidget(const BattleManApp());
      await tester.pumpAndSettle();
      await _dismissStartupAuthIfShown(tester);

      await tester.tap(find.byKey(const ValueKey('shell-nav-micro')));
      await tester.pumpAndSettle();

      expect(find.text('添加微任务'), findsOneWidget);
      expect(find.byTooltip('批量模式'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.binding.setSurfaceSize(null);
    }
  });

  testWidgets('Smart calendar month view fits on small screens', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    try {
      await tester.pumpWidget(const BattleManApp());
      await tester.pumpAndSettle();
      await _dismissStartupAuthIfShown(tester);

      await tester.tap(find.byKey(const ValueKey('shell-nav-schedule')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('月').last);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    } finally {
      await tester.binding.setSurfaceSize(null);
    }
  });

  testWidgets('Fatigue hint does not block shell navigation', (tester) async {
    final local = LocalDataService.forPersistence(InMemoryLocalPersistence());
    AppServices.installTestOverrides(
      dataService: _FatigueDataService(local),
      reminderService: _NoopReminderService(),
    );
    await tester.binding.setSurfaceSize(const Size(390, 844));

    try {
      await tester.pumpWidget(const BattleManApp());
      await tester.pumpAndSettle();
      await _dismissStartupAuthIfShown(tester);

      expect(find.byType(AlertDialog), findsNothing);

      await tester.tap(find.byKey(const ValueKey('shell-nav-schedule')));
      await tester.pumpAndSettle();

      expect(find.byType(SmartCalendarPage), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.binding.setSurfaceSize(null);
    }
  });

  testWidgets('Smart calendar gantt switch fits on small screens', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    try {
      await tester.pumpWidget(const BattleManApp());
      await tester.pumpAndSettle();
      await _dismissStartupAuthIfShown(tester);

      await tester.tap(find.byKey(const ValueKey('shell-nav-schedule')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('甘特').last);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    } finally {
      await tester.binding.setSurfaceSize(null);
    }
  });

  testWidgets('Urgent task dialog opens a deadline date picker', (
    tester,
  ) async {
    _setWideSurface(tester);
    try {
      await _openSmartCalendar(tester);

      await tester.tap(find.byTooltip('插入紧急任务并重新规划'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('calendar-urgent-deadline')),
        findsOneWidget,
      );
      expect(find.text('截止日期'), findsOneWidget);
      expect(find.text('截止时间'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('calendar-urgent-deadline-date')),
      );
      await tester.pumpAndSettle();

      expect(find.byType(DatePickerDialog), findsOneWidget);
    } finally {
      _resetSurface(tester);
    }
  });

  testWidgets('Urgent task dialog opens a deadline time picker', (
    tester,
  ) async {
    _setWideSurface(tester);
    try {
      await _openSmartCalendar(tester);

      await tester.tap(find.byTooltip('插入紧急任务并重新规划'));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('calendar-urgent-deadline-time')),
      );
      await tester.pumpAndSettle();

      expect(find.byType(TimePickerDialog), findsOneWidget);
    } finally {
      _resetSurface(tester);
    }
  });

  testWidgets('Urgent rescue reschedules reminders on accept and undo', (
    tester,
  ) async {
    final local = LocalDataService.forPersistence(InMemoryLocalPersistence());
    final reminderService = _RecordingReminderService();
    AppServices.installTestOverrides(
      dataService: local,
      reminderService: reminderService,
    );
    _setWideSurface(tester);

    try {
      await _openSmartCalendar(tester);
      final reschedulesBeforeRescue = reminderService.rescheduleCalls.length;
      await _selectDefaultRescue(tester);

      expect(_urgentEntries(await local.getScheduleEntries()), isNotEmpty);
      expect(
        reminderService.rescheduleCalls,
        hasLength(reschedulesBeforeRescue + 1),
      );
      expect(_urgentEntries(reminderService.rescheduleCalls.last), isNotEmpty);

      await tester.tap(find.text('撤销救援'));
      await tester.pumpAndSettle();

      expect(_urgentEntries(await local.getScheduleEntries()), isEmpty);
      expect(
        reminderService.rescheduleCalls,
        hasLength(reschedulesBeforeRescue + 2),
      );
      expect(reminderService.rescheduleCalls.last, isNotEmpty);
      expect(_urgentEntries(reminderService.rescheduleCalls.last), isEmpty);
    } finally {
      _resetSurface(tester);
    }
  });

  testWidgets('Reminder failure keeps the accepted rescue visible', (
    tester,
  ) async {
    final local = LocalDataService.forPersistence(InMemoryLocalPersistence());
    final reminderService = _RecordingReminderService(throwOnReschedule: true);
    AppServices.installTestOverrides(
      dataService: local,
      reminderService: reminderService,
    );
    _setWideSurface(tester);

    try {
      await _openSmartCalendar(tester);
      final reschedulesBeforeRescue = reminderService.rescheduleCalls.length;
      await _selectDefaultRescue(tester);

      expect(_urgentEntries(await local.getScheduleEntries()), isNotEmpty);
      expect(find.text('撤销救援'), findsOneWidget);
      expect(
        reminderService.rescheduleCalls,
        hasLength(reschedulesBeforeRescue + 1),
      );
      expect(
        AppServices.logStore.entries.map((entry) => entry.message),
        contains('rescue reminder reschedule failed'),
      );
      expect(
        AppServices.logStore.entries.map((entry) => entry.message),
        isNot(contains('rescue planning failed')),
      );
    } finally {
      _resetSurface(tester);
    }
  });

  testWidgets('Undo persistence failure keeps the accepted rescue visible', (
    tester,
  ) async {
    final local = LocalDataService.forPersistence(InMemoryLocalPersistence());
    final dataService = _UndoPersistenceFailingDataService(local);
    AppServices.installTestOverrides(
      dataService: dataService,
      reminderService: _NoopReminderService(),
    );
    _setWideSurface(tester);

    try {
      await _openSmartCalendar(tester);
      await _selectDefaultRescue(tester);
      dataService.failScheduleWrites = true;

      await tester.tap(find.text('撤销救援'));
      await tester.pumpAndSettle();

      expect(find.text('撤销救援'), findsOneWidget);
      expect(_urgentEntries(await local.getScheduleEntries()), isNotEmpty);
    } finally {
      _resetSurface(tester);
    }
  });

  testWidgets('Event logging failure keeps the accepted rescue visible', (
    tester,
  ) async {
    final local = LocalDataService.forPersistence(InMemoryLocalPersistence());
    final dataService = _EventFailingDataService(local);
    AppServices.installTestOverrides(
      dataService: dataService,
      reminderService: _NoopReminderService(),
    );
    _setWideSurface(tester);

    try {
      await _openSmartCalendar(tester);
      await _selectDefaultRescue(tester);

      expect(find.text('撤销救援'), findsOneWidget);
      expect(_urgentEntries(await local.getScheduleEntries()), isNotEmpty);
      expect(
        AppServices.logStore.entries.map((entry) => entry.message),
        contains('rescue event logging failed'),
      );
    } finally {
      _resetSurface(tester);
    }
  });

  testWidgets('ICS import preserves the loading guard through its reload', (
    tester,
  ) async {
    final importDay = DateTime.now();
    final local = LocalDataService.forPersistence(InMemoryLocalPersistence());
    final dataService = _BlockingImportDataService(local);
    final reminderService = _BlockingReminderService();
    AppServices.installTestOverrides(
      dataService: dataService,
      reminderService: reminderService,
    );
    _setWideSurface(tester);

    try {
      await _openSmartCalendar(tester);
      await tester.tap(find.byTooltip('切换到手动模式'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('导入 iCal（ICS）'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), _validIcsFor(importDay));
      await tester.tap(find.text('导入'));
      await tester.pump();

      final refresh = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.refresh),
      );
      expect(refresh.onPressed, isNull);

      dataService.blockReloadEntries = true;
      reminderService.blockReschedule = true;
      dataService.addScheduleEntryCompleter.complete();
      await tester.pump();

      final duringReload = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.refresh),
      );
      expect(duringReload.onPressed, isNull);

      dataService.reloadEntriesCompleter.complete(
        await local.getScheduleEntries(),
      );
      await tester.pump();

      final afterReloadRead = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.refresh),
      );
      expect(afterReloadRead.onPressed, isNull);

      reminderService.rescheduleCompleter.complete();
      await tester.pumpAndSettle();

      final enabledRefresh = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.refresh),
      );
      expect(enabledRefresh.onPressed, isNotNull);
    } finally {
      _resetSurface(tester);
    }
  });

  testWidgets('profile hub exposes review and settings entries', (tester) async {
    await tester.pumpWidget(const BattleManApp());
    await tester.pumpAndSettle();
    await _dismissStartupAuthIfShown(tester);
    await tester.tap(find.byKey(const ValueKey('shell-nav-profile')));
    await tester.pumpAndSettle();

    expect(find.text('复盘'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('设置'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('设置'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('team page keeps collaboration heading and empty state readable at 390px', (
    tester,
  ) async {
    AppServices.installTestOverrides(
      dataService: _EmptyTeamDataService(
        LocalDataService.forPersistence(InMemoryLocalPersistence()),
      ),
      reminderService: _NoopReminderService(),
    );
    await tester.binding.setSurfaceSize(const Size(390, 844));
    try {
      await tester.pumpWidget(const BattleManApp());
      await tester.pumpAndSettle();
      await _dismissStartupAuthIfShown(tester);

      await tester.tap(find.byKey(const ValueKey('shell-nav-team')));
      await tester.pumpAndSettle();

      expect(find.text('协作黄金窗口'), findsOneWidget);
      expect(find.text('未找到团队成员。'), findsWidgets);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.binding.setSurfaceSize(null);
    }
  });

  testWidgets('urgent rescue presents all strategies before acceptance', (tester) async {
    _setWideSurface(tester);
    await _openSmartCalendar(tester);
    await tester.tap(find.byTooltip('插入紧急任务并重新规划'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('插入并重新规划'));
    await tester.pumpAndSettle();

    expect(find.text('优先保住截止时间'), findsOneWidget);
    expect(find.text('优先保留恢复时间'), findsOneWidget);
    expect(find.text('尽量少动原计划'), findsOneWidget);
    expect(find.text('采用此方案'), findsNothing);
  });
}
