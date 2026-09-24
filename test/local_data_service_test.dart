import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shixuzhipei/models/models.dart';
import 'package:shixuzhipei/services/local_data_service.dart';
import 'package:shixuzhipei/services/local_persistence/local_persistence.dart';

class _ControllableLocalPersistence implements LocalPersistence {
  final Map<String, String> _contentByNamespace = <String, String>{};
  bool failWrites = false;
  int readAttempts = 0;
  int writeAttempts = 0;

  @override
  Future<bool> exists({String namespace = legacyLocalNamespace}) async =>
      _contentByNamespace.containsKey(namespace);

  @override
  Future<String?> read({String namespace = legacyLocalNamespace}) async {
    readAttempts++;
    return _contentByNamespace[namespace];
  }

  void seed(String content, {String namespace = legacyLocalNamespace}) {
    _contentByNamespace[namespace] = content;
  }

  @override
  Future<void> write(
    String content, {
    String namespace = legacyLocalNamespace,
  }) async {
    writeAttempts++;
    if (failWrites) {
      throw StateError('write failed');
    }
    _contentByNamespace[namespace] = content;
  }
}

class _DelayedFailingLocalPersistence implements LocalPersistence {
  final Map<String, String> _contentByNamespace = <String, String>{};
  final List<String> writeSnapshots = [];
  int _activeWrites = 0;
  int maxConcurrentWrites = 0;
  bool _delayNextWrite = false;
  bool _failDelayedWrite = false;
  Completer<void>? _delayedWriteStarted;
  Completer<void>? _releaseDelayedWrite;

  @override
  Future<bool> exists({String namespace = legacyLocalNamespace}) async =>
      _contentByNamespace.containsKey(namespace);

  @override
  Future<String?> read({String namespace = legacyLocalNamespace}) async =>
      _contentByNamespace[namespace];

  void delayNextWrite() {
    _delayNextWrite = true;
    _failDelayedWrite = false;
    _delayedWriteStarted = Completer<void>();
    _releaseDelayedWrite = Completer<void>();
  }

  void delayNextWriteAndFail() {
    _delayNextWrite = true;
    _failDelayedWrite = true;
    _delayedWriteStarted = Completer<void>();
    _releaseDelayedWrite = Completer<void>();
  }

  Future<void> get delayedWriteStarted =>
      _delayedWriteStarted!.future.timeout(const Duration(seconds: 2));

  void releaseDelayedWrite() => _releaseDelayedWrite!.complete();

  void clearWriteHistory() {
    writeSnapshots.clear();
    maxConcurrentWrites = 0;
  }

  @override
  Future<void> write(
    String content, {
    String namespace = legacyLocalNamespace,
  }) async {
    writeSnapshots.add(content);
    _activeWrites++;
    if (_activeWrites > maxConcurrentWrites) {
      maxConcurrentWrites = _activeWrites;
    }

    final shouldDelay = _delayNextWrite;
    final shouldFail = _failDelayedWrite;
    _delayNextWrite = false;
    _failDelayedWrite = false;
    try {
      if (shouldDelay) {
        _delayedWriteStarted!.complete();
        await _releaseDelayedWrite!.future.timeout(const Duration(seconds: 2));
        if (shouldFail) {
          throw StateError('delayed write failed');
        }
      }
      _contentByNamespace[namespace] = content;
    } finally {
      _activeWrites--;
    }
  }
}

List<String> _savedTaskEventIds(String raw) {
  final saved = Map<String, Object?>.from(
    jsonDecode(raw) as Map<dynamic, dynamic>,
  );
  return (saved['taskEvents'] as List)
      .cast<Map<dynamic, dynamic>>()
      .map((event) => event['id'] as String)
      .toList(growable: false);
}

List<String> _savedGoalIds(String raw) {
  final saved = Map<String, Object?>.from(
    jsonDecode(raw) as Map<dynamic, dynamic>,
  );
  return (saved['goals'] as List)
      .cast<Map<dynamic, dynamic>>()
      .map((goal) => goal['id'] as String)
      .toList(growable: false);
}

UserAccount _cachedUser(String id) => UserAccount(
  userId: id,
  contactAddress: '$id@example.com',
  displayName: 'Profile $id',
  identityState: ClientIdentityState.offlineCached,
);

Future<void> _populateIdentity(LocalDataService service, String prefix) async {
  final day = DateTime(2026, 9, 24);
  await service.addScheduleEntry(
    ScheduleEntry(
      id: '$prefix-schedule',
      day: day,
      title: '$prefix schedule',
      tag: 'Focus',
      height: 80,
      color: Colors.teal,
      time: const TimeOfDay(hour: 8, minute: 0),
    ),
  );
  await service.addMicroTask(
    MicroTask(
      id: '$prefix-micro',
      title: '$prefix micro',
      tag: 'Focus',
      minutes: 10,
    ),
  );
  await service.upsertGoal(
    Goal(
      id: '$prefix-goal',
      title: '$prefix goal',
      due: day.add(const Duration(days: 1)),
      priority: 4,
      tasks: const [],
    ),
  );
  await service.upsertTeamMember(
    TeamMemberCalendar(
      memberId: '$prefix-member',
      displayName: '$prefix member',
      role: 'Developer',
      energy: EnergyTier.medium,
      permission: TeamSharePermission.details,
      busy: const [],
    ),
  );
  await service.addEmotionCheckIn(
    EmotionCheckIn(
      id: '$prefix-emotion',
      at: day.add(const Duration(hours: 9)),
      state: EmotionState.efficient,
    ),
  );
  await service.logTaskEvent(
    TaskEvent(
      id: '$prefix-event',
      taskId: '$prefix-task',
      title: '$prefix event',
      tag: 'Focus',
      at: day.add(const Duration(hours: 10)),
      type: TaskEventType.complete,
    ),
  );
  await service.setSchedulingTuning(
    SchedulingTuning(tagDurationMultiplier: {prefix: 1.25}),
  );
  await service.setFavoriteDevice('$prefix-device');
  await service.setThemeMode('$prefix-theme');
  await service.setLocale('$prefix-locale');
}

Future<void> _expectIdentityValues(
  LocalDataService service,
  String prefix, {
  required bool present,
}) async {
  final day = DateTime(2026, 9, 24);
  final checks = <bool>[
    (await service.getScheduleEntries()).any(
      (entry) => entry.id == '$prefix-schedule',
    ),
    (await service.getMicroTasks()).any((task) => task.id == '$prefix-micro'),
    (await service.getGoals()).any((goal) => goal.id == '$prefix-goal'),
    (await service.getTeamCalendars(
      day,
    )).any((member) => member.memberId == '$prefix-member'),
    (await service.getEmotionCheckIns(
      day,
    )).any((checkIn) => checkIn.id == '$prefix-emotion'),
    (await service.getTaskEvents(
      day,
      day.add(const Duration(days: 1)),
    )).any((event) => event.id == '$prefix-event'),
    (await service.getSchedulingTuning()).tagDurationMultiplier.containsKey(
      prefix,
    ),
    await service.getFavoriteDevice() == '$prefix-device',
    await service.getThemeMode() == '$prefix-theme',
    await service.getLocale() == '$prefix-locale',
  ];
  expect(checks, everyElement(present), reason: 'identity=$prefix');
}

void main() {
  test(
    'legacy UserAccount JSON remains an offline identity without user id',
    () {
      final account = UserAccount.fromJson({
        'contactAddress': 'legacy@example.com',
        'displayName': 'Legacy user',
      });

      expect(account.userId, isNull);
      expect(account.identityState, ClientIdentityState.offlineCached);
      expect(account.toJson(), isNot(contains('id')));
    },
  );

  test('LocalDataService migrates legacy keys and persists ids', () async {
    final persistence = InMemoryLocalPersistence();
    final legacyEntry = <String, Object?>{
      'title': 'Legacy Task',
      'tag': 'Legacy',
      'height': 80.0,
      'color': Colors.teal.toARGB32(),
      'time': const {'hour': 9, 'minute': 0},
    };
    final legacyPayload = <String, Object?>{
      'version': 1,
      'scheduleEntries': [legacyEntry],
    };
    await persistence.write(jsonEncode(legacyPayload));

    final service = LocalDataService.forPersistence(persistence);
    final entries = await service.getScheduleEntries();

    expect(entries.length, 1);
    expect(entries.first.id, isNotNull);
    expect(entries.first.id!.isNotEmpty, true);

    final savedRaw = await persistence.read(namespace: 'guest');
    expect(savedRaw, isNotNull);
    final saved = Map<String, Object?>.from(
      jsonDecode(savedRaw!) as Map<dynamic, dynamic>,
    );
    expect(saved['schedule'], isA<List>());
    expect(saved['scheduleEntries'], isNull);
    expect(saved['version'], isA<int>());

    final schedule = (saved['schedule'] as List).cast<Map<dynamic, dynamic>>();
    final savedId = schedule.first['id'] as String?;
    expect(savedId, isNotNull);
    expect(savedId!.isNotEmpty, true);
  });

  test('LocalDataService upserts schedule entries by id', () async {
    final persistence = InMemoryLocalPersistence();
    final service = LocalDataService.forPersistence(persistence);

    final entry = ScheduleEntry(
      id: 'sch_test_unique',
      title: 'Original',
      tag: 'Focus',
      height: 80.0,
      color: Colors.teal,
      time: const TimeOfDay(hour: 9, minute: 0),
    );
    await service.addScheduleEntry(entry);
    await service.addScheduleEntry(entry.copyWith(title: 'Updated'));

    final entries = await service.getScheduleEntries();
    final testEntry = entries.firstWhere((e) => e.id == 'sch_test_unique');
    expect(testEntry.title, 'Updated');

    final savedRaw = await persistence.read(namespace: 'guest');
    final saved = Map<String, Object?>.from(
      jsonDecode(savedRaw!) as Map<dynamic, dynamic>,
    );
    final schedule = (saved['schedule'] as List).cast<Map<dynamic, dynamic>>();
    final savedEntry = schedule.firstWhere((e) => e['id'] == 'sch_test_unique');
    expect(savedEntry['title'], 'Updated');
  });

  test('LocalDataService persists team permission updates', () async {
    final persistence = InMemoryLocalPersistence();
    final service = LocalDataService.forPersistence(persistence);
    final day = DateTime(2026, 1, 1);

    final calendars = await service.getTeamCalendars(day);
    expect(calendars.isNotEmpty, isTrue);
    final member = calendars.first;
    final nextPermission = member.permission == TeamSharePermission.details
        ? TeamSharePermission.freeBusy
        : TeamSharePermission.details;

    await service.updateTeamSharePermission(member.memberId, nextPermission);

    final reloaded = LocalDataService.forPersistence(persistence);
    final calendars2 = await reloaded.getTeamCalendars(day);
    final updated = calendars2.firstWhere((c) => c.memberId == member.memberId);

    expect(updated.permission, nextPermission);
  });

  test('LocalDataService derives team members with progress', () async {
    final persistence = InMemoryLocalPersistence();
    final service = LocalDataService.forPersistence(persistence);

    final members = await service.getTeamMembers();

    expect(members, isNotEmpty);
    expect(members.first.progress, inInclusiveRange(0.0, 1.0));
  });

  test('LocalDataService rolls back a failed task event batch write', () async {
    final persistence = _ControllableLocalPersistence();
    final service = LocalDataService.forPersistence(persistence);
    final from = DateTime(2026, 1, 1);
    final to = from.add(const Duration(days: 1));
    final existing = TaskEvent(
      id: 'evt_existing',
      taskId: 'task_existing',
      title: 'Existing event',
      tag: 'Focus',
      at: DateTime(2026, 1, 1, 8),
      type: TaskEventType.start,
    );
    final first = TaskEvent(
      id: 'evt_batch_first',
      taskId: 'task_1',
      title: 'First event',
      tag: 'Focus',
      at: DateTime(2026, 1, 1, 9),
      type: TaskEventType.start,
    );
    final second = TaskEvent(
      id: 'evt_batch_second',
      taskId: 'task_2',
      title: 'Second event',
      tag: 'Focus',
      at: DateTime(2026, 1, 1, 10),
      type: TaskEventType.complete,
    );

    await service.logTaskEvent(existing);
    final persistedBefore = await persistence.read(namespace: 'guest');
    final writeAttemptsBefore = persistence.writeAttempts;
    persistence.failWrites = true;

    await expectLater(
      service.upsertTaskEvents([first, second]),
      throwsA(isA<StateError>()),
    );

    persistence.failWrites = false;
    final events = await service.getTaskEvents(from, to);
    expect(events.map((event) => event.id), ['evt_existing']);
    expect(events.map((event) => event.id), isNot(contains(first.id)));
    expect(events.map((event) => event.id), isNot(contains(second.id)));
    expect(await persistence.read(namespace: 'guest'), persistedBefore);
    expect(persistence.writeAttempts, writeAttemptsBefore + 1);
  });

  test(
    'LocalDataService serializes a failed event batch before a later batch',
    () async {
      final persistence = _DelayedFailingLocalPersistence();
      final service = LocalDataService.forPersistence(persistence);
      final from = DateTime(2026, 1, 1);
      final to = from.add(const Duration(days: 1));
      final baseline = TaskEvent(
        id: 'evt_baseline',
        taskId: 'task_baseline',
        title: 'Baseline event',
        tag: 'Focus',
        at: DateTime(2026, 1, 1, 8),
        type: TaskEventType.start,
      );
      final batchA = TaskEvent(
        id: 'evt_batch_a',
        taskId: 'task_a',
        title: 'Failed batch event',
        tag: 'Focus',
        at: DateTime(2026, 1, 1, 9),
        type: TaskEventType.start,
      );
      final batchB = TaskEvent(
        id: 'evt_batch_b',
        taskId: 'task_b',
        title: 'Queued batch event',
        tag: 'Focus',
        at: DateTime(2026, 1, 1, 10),
        type: TaskEventType.start,
      );

      await service.logTaskEvent(baseline);
      persistence.clearWriteHistory();
      persistence.delayNextWriteAndFail();

      final failedBatch = service.upsertTaskEvents([batchA]);
      final failedBatchExpectation = expectLater(
        failedBatch,
        throwsA(isA<StateError>()),
      );
      await persistence.delayedWriteStarted;
      final queuedBatch = service.upsertTaskEvents([batchB]);
      await Future<void>.delayed(Duration.zero);
      persistence.releaseDelayedWrite();

      await failedBatchExpectation;
      await queuedBatch;

      final events = await service.getTaskEvents(from, to);
      expect(events.map((event) => event.id), ['evt_baseline', 'evt_batch_b']);
      expect(persistence.maxConcurrentWrites, 1);
      expect(persistence.writeSnapshots, hasLength(2));
      expect(_savedTaskEventIds(persistence.writeSnapshots.first), [
        'evt_baseline',
        'evt_batch_a',
      ]);
      expect(_savedTaskEventIds(persistence.writeSnapshots.last), [
        'evt_baseline',
        'evt_batch_b',
      ]);
      expect(
        _savedTaskEventIds((await persistence.read(namespace: 'guest'))!),
        ['evt_baseline', 'evt_batch_b'],
      );
    },
  );

  test(
    'LocalDataService repairs blank and duplicate legacy task event ids',
    () async {
      final persistence = InMemoryLocalPersistence();
      await persistence.write(
        jsonEncode({
          'version': 5,
          'taskEvents': [
            {
              'id': '',
              'taskId': 'task_blank',
              'title': 'Blank id',
              'tag': 'Focus',
              'at': '2026-01-01T08:00:00.000',
              'type': 'start',
            },
            {
              'id': 'evt_duplicate',
              'taskId': 'task_first_duplicate',
              'title': 'First duplicate',
              'tag': 'Focus',
              'at': '2026-01-01T09:00:00.000',
              'type': 'start',
            },
            {
              'id': 'evt_duplicate',
              'taskId': 'task_later_duplicate',
              'title': 'Later duplicate',
              'tag': 'Focus',
              'at': '2026-01-01T10:00:00.000',
              'type': 'complete',
            },
          ],
        }),
      );

      final service = LocalDataService.forPersistence(persistence);
      final events = await service.getTaskEvents(
        DateTime(2026, 1, 1),
        DateTime(2026, 1, 2),
      );

      expect(events, hasLength(3));
      expect(events.map((event) => event.title), [
        'Blank id',
        'First duplicate',
        'Later duplicate',
      ]);
      expect(events.every((event) => event.id.trim().isNotEmpty), isTrue);
      expect(events.map((event) => event.id).toSet(), hasLength(3));

      final savedIds = _savedTaskEventIds(
        (await persistence.read(namespace: 'guest'))!,
      );
      expect(savedIds, hasLength(3));
      expect(savedIds.every((id) => id.trim().isNotEmpty), isTrue);
      expect(savedIds.toSet(), hasLength(3));
    },
  );

  test(
    'LocalDataService overwrites retried task events by stable id',
    () async {
      final persistence = InMemoryLocalPersistence();
      final service = LocalDataService.forPersistence(persistence);
      final from = DateTime(2026, 1, 1);
      final to = from.add(const Duration(days: 1));
      final firstAttempt = TaskEvent(
        id: 'evt_retry',
        taskId: 'task_retry',
        title: 'First attempt',
        tag: 'Focus',
        at: DateTime(2026, 1, 1, 9),
        type: TaskEventType.start,
        plannedMinutes: 25,
      );
      final secondAttempt = TaskEvent(
        id: 'evt_retry',
        taskId: 'task_retry',
        title: 'Second attempt',
        tag: 'Focus',
        at: DateTime(2026, 1, 1, 9, 5),
        type: TaskEventType.complete,
        actualMinutes: 20,
      );

      await service.logTaskEvent(firstAttempt);
      await service.logTaskEvent(secondAttempt);

      final events = await service.getTaskEvents(from, to);
      expect(events, hasLength(1));
      expect(events.single.title, 'Second attempt');

      final raw = await persistence.read(namespace: 'guest');
      final saved = Map<String, Object?>.from(
        jsonDecode(raw!) as Map<dynamic, dynamic>,
      );
      final savedEvents = (saved['taskEvents'] as List)
          .cast<Map<dynamic, dynamic>>();
      expect(savedEvents, hasLength(1));
      expect(savedEvents.single['title'], 'Second attempt');
    },
  );

  test(
    'LocalDataService persists goal completion when event batch save succeeds',
    () async {
      final persistence = InMemoryLocalPersistence();
      final service = LocalDataService.forPersistence(persistence);
      final goal = Goal(
        id: 'goal_complete_1',
        title: 'Goal',
        due: DateTime(2026, 1, 2),
        priority: 3,
        tasks: const [
          GoalTask(
            id: 'goal_task_complete_1',
            title: 'Goal task',
            durationMinutes: 30,
            load: CognitiveLoad.medium,
            tag: 'Focus',
          ),
        ],
      );
      await service.upsertGoal(goal);
      await service.addScheduleEntry(
        ScheduleEntry(
          id: 'schedule_complete_1',
          title: 'Scheduled goal task',
          tag: 'Focus',
          goalId: goal.id,
          goalTaskId: goal.tasks.single.id,
          height: 40.0,
          color: Colors.teal,
          time: const TimeOfDay(hour: 9, minute: 0),
        ),
      );

      await service.upsertTaskEvents([
        TaskEvent(
          id: 'evt_complete_goal_task_success',
          taskId: 'schedule_complete_1',
          title: 'Scheduled goal task',
          tag: 'Focus',
          at: DateTime(2026, 1, 1, 9, 30),
          type: TaskEventType.complete,
        ),
      ]);

      expect((await service.getGoals()).single.tasks.single.done, isTrue);

      final reloaded = LocalDataService.forPersistence(persistence);
      expect((await reloaded.getGoals()).single.tasks.single.done, isTrue);
    },
  );

  test(
    'LocalDataService rolls back goal completion when event batch save fails',
    () async {
      final persistence = _ControllableLocalPersistence();
      final service = LocalDataService.forPersistence(persistence);
      final goal = Goal(
        id: 'goal_1',
        title: 'Goal',
        due: DateTime(2026, 1, 2),
        priority: 3,
        tasks: const [
          GoalTask(
            id: 'goal_task_1',
            title: 'Goal task',
            durationMinutes: 30,
            load: CognitiveLoad.medium,
            tag: 'Focus',
          ),
        ],
      );
      await service.upsertGoal(goal);
      await service.addScheduleEntry(
        ScheduleEntry(
          id: 'schedule_1',
          title: 'Scheduled goal task',
          tag: 'Focus',
          goalId: goal.id,
          goalTaskId: goal.tasks.single.id,
          height: 40.0,
          color: Colors.teal,
          time: const TimeOfDay(hour: 9, minute: 0),
        ),
      );
      final persistedBefore = await persistence.read(namespace: 'guest');
      persistence.failWrites = true;

      await expectLater(
        service.upsertTaskEvents([
          TaskEvent(
            id: 'evt_complete_goal_task',
            taskId: 'schedule_1',
            title: 'Scheduled goal task',
            tag: 'Focus',
            at: DateTime(2026, 1, 1, 9, 30),
            type: TaskEventType.complete,
          ),
        ]),
        throwsA(isA<StateError>()),
      );

      persistence.failWrites = false;
      expect((await service.getGoals()).single.tasks.single.done, isFalse);
      expect(await persistence.read(namespace: 'guest'), persistedBefore);
    },
  );

  test(
    'LocalDataService serializes concurrent event and goal persistence',
    () async {
      final persistence = _DelayedFailingLocalPersistence();
      final service = LocalDataService.forPersistence(persistence);
      final day = DateTime(2026, 1, 1);
      final event = TaskEvent(
        id: 'evt_race',
        taskId: 'task_race',
        title: 'Concurrent event',
        tag: 'Focus',
        at: DateTime(2026, 1, 1, 9),
        type: TaskEventType.start,
      );
      final goal = Goal(
        id: 'goal_race',
        title: 'Concurrent goal',
        due: day.add(const Duration(days: 1)),
        priority: 3,
        tasks: const [],
      );

      await service.getGoals();
      persistence.clearWriteHistory();
      persistence.delayNextWrite();

      final eventWrite = service.upsertTaskEvents([event]);
      await persistence.delayedWriteStarted;
      final goalWrite = service.upsertGoal(goal);
      await Future<void>.delayed(Duration.zero);
      persistence.releaseDelayedWrite();

      await eventWrite;
      await goalWrite;

      expect(persistence.maxConcurrentWrites, 1);
      expect(
        (await service.getTaskEvents(
          day,
          day.add(const Duration(days: 1)),
        )).map((savedEvent) => savedEvent.id),
        ['evt_race'],
      );
      expect((await service.getGoals()).map((savedGoal) => savedGoal.id), [
        'goal_race',
      ]);

      final saved = (await persistence.read(namespace: 'guest'))!;
      expect(_savedTaskEventIds(saved), ['evt_race']);
      expect(_savedGoalIds(saved), ['goal_race']);
    },
  );

  test(
    'LocalDataService copies task event batches before queuing them',
    () async {
      final persistence = _DelayedFailingLocalPersistence();
      final service = LocalDataService.forPersistence(persistence);
      final day = DateTime(2026, 1, 1);
      final blockingEvent = TaskEvent(
        id: 'evt_blocking',
        taskId: 'task_blocking',
        title: 'Blocking event',
        tag: 'Focus',
        at: DateTime(2026, 1, 1, 9),
        type: TaskEventType.start,
      );
      final queuedEvent = TaskEvent(
        id: 'evt_copied',
        taskId: 'task_copied',
        title: 'Copied event',
        tag: 'Focus',
        at: DateTime(2026, 1, 1, 10),
        type: TaskEventType.complete,
      );

      await service.getTaskEvents(day, day.add(const Duration(days: 1)));
      persistence.delayNextWrite();
      final blockingWrite = service.upsertTaskEvents([blockingEvent]);
      await persistence.delayedWriteStarted;
      final callerOwnedBatch = <TaskEvent>[queuedEvent];
      final queuedWrite = service.upsertTaskEvents(callerOwnedBatch);
      callerOwnedBatch.clear();
      persistence.releaseDelayedWrite();

      await blockingWrite;
      await queuedWrite;

      expect(
        (await service.getTaskEvents(
          day,
          day.add(const Duration(days: 1)),
        )).map((event) => event.id),
        ['evt_blocking', 'evt_copied'],
      );
      expect(
        _savedTaskEventIds((await persistence.read(namespace: 'guest'))!),
        ['evt_blocking', 'evt_copied'],
      );
    },
  );

  test(
    'LocalDataService retries a failed shared legacy task event migration',
    () async {
      final persistence = _ControllableLocalPersistence();
      persistence.seed(
        jsonEncode({
          'version': 5,
          'taskEvents': [
            {
              'id': '',
              'taskId': 'task_blank',
              'title': 'Blank id',
              'tag': 'Focus',
              'at': '2026-01-01T08:00:00.000',
              'type': 'start',
            },
            {
              'id': 'evt_duplicate',
              'taskId': 'task_first_duplicate',
              'title': 'First duplicate',
              'tag': 'Focus',
              'at': '2026-01-01T09:00:00.000',
              'type': 'start',
            },
            {
              'id': 'evt_duplicate',
              'taskId': 'task_later_duplicate',
              'title': 'Later duplicate',
              'tag': 'Focus',
              'at': '2026-01-01T10:00:00.000',
              'type': 'complete',
            },
          ],
        }),
      );
      final service = LocalDataService.forPersistence(persistence);
      final day = DateTime(2026, 1, 1);
      persistence.failWrites = true;

      final firstLoad = service.getTaskEvents(
        day,
        day.add(const Duration(days: 1)),
      );
      final secondLoad = service.getTaskEvents(
        day,
        day.add(const Duration(days: 1)),
      );
      await expectLater(firstLoad, throwsA(isA<StateError>()));
      await expectLater(secondLoad, throwsA(isA<StateError>()));
      expect(persistence.readAttempts, 2);

      persistence.failWrites = false;
      final events = await service.getTaskEvents(
        day,
        day.add(const Duration(days: 1)),
      );

      expect(persistence.readAttempts, 3);
      expect(events, hasLength(3));
      expect(events.every((event) => event.id.trim().isNotEmpty), isTrue);
      expect(events.map((event) => event.id).toSet(), hasLength(3));
      final savedIds = _savedTaskEventIds(
        (await persistence.read(namespace: 'guest'))!,
      );
      expect(savedIds, hasLength(3));
      expect(savedIds.every((id) => id.trim().isNotEmpty), isTrue);
      expect(savedIds.toSet(), hasLength(3));
    },
  );

  test(
    'LocalDataService rolls back a failed ordinary mutation before a later save',
    () async {
      final persistence = _ControllableLocalPersistence();
      final service = LocalDataService.forPersistence(persistence);
      await service.getGoals();
      final persistedBefore = await persistence.read(namespace: 'guest');
      final failedGoal = Goal(
        id: 'goal_failed_ordinary_mutation',
        title: 'Must not survive',
        due: DateTime(2026, 1, 3),
        priority: 4,
        tasks: const [],
      );

      persistence.failWrites = true;
      await expectLater(
        service.upsertGoal(failedGoal),
        throwsA(isA<StateError>()),
      );

      persistence.failWrites = false;
      await service.setLocale('en_US');

      expect(
        (await service.getGoals()).where((goal) => goal.id == failedGoal.id),
        isEmpty,
      );
      expect(
        await persistence.read(namespace: 'guest'),
        isNot(contains(failedGoal.title)),
      );
      expect(
        Map<String, Object?>.from(
          jsonDecode((await persistence.read(namespace: 'guest'))!)
              as Map<dynamic, dynamic>,
        )['locale'],
        'en_US',
      );
      expect(persistedBefore, isNotNull);
    },
  );

  test(
    'LocalDataService throws parse errors without seeding or mutating raw storage and retries',
    () async {
      final persistence = _ControllableLocalPersistence();
      final corruptRaw = jsonEncode({
        'version': 5,
        'taskEvents': [
          {
            'id': 42,
            'taskId': 'task_invalid',
            'title': 'Invalid event',
            'tag': 'Focus',
            'at': '2026-01-01T08:00:00.000',
            'type': 'start',
          },
        ],
      });
      persistence.seed(corruptRaw);
      final service = LocalDataService.forPersistence(persistence);

      await expectLater(
        service.getTaskEvents(DateTime(2026, 1, 1), DateTime(2026, 1, 2)),
        throwsA(anything),
      );
      final rawAfterFailure = await persistence.read();
      expect(rawAfterFailure, corruptRaw);
      expect(persistence.writeAttempts, 0);

      final repairedEvent = TaskEvent(
        id: 'evt_repaired',
        taskId: 'task_repaired',
        title: 'Repaired event',
        tag: 'Focus',
        at: DateTime(2026, 1, 1, 9),
        type: TaskEventType.start,
      );
      persistence.seed(
        jsonEncode({
          'version': 5,
          'taskEvents': [repairedEvent.toJson()],
        }),
      );

      final events = await service.getTaskEvents(
        DateTime(2026, 1, 1),
        DateTime(2026, 1, 2),
      );
      expect(events.map((event) => event.id), ['evt_repaired']);
      expect(events.map((event) => event.title), ['Repaired event']);
      expect(persistence.readAttempts, 4);
    },
  );

  test(
    'LocalDataService gives blank incoming task events unique ids',
    () async {
      final persistence = InMemoryLocalPersistence();
      final service = LocalDataService.forPersistence(persistence);

      await service.upsertTaskEvents([
        TaskEvent(
          id: '',
          taskId: 'task_blank_1',
          title: 'First blank event',
          tag: 'Focus',
          at: DateTime(2026, 1, 1, 9),
          type: TaskEventType.start,
        ),
        TaskEvent(
          id: '',
          taskId: 'task_blank_2',
          title: 'Second blank event',
          tag: 'Focus',
          at: DateTime(2026, 1, 1, 10),
          type: TaskEventType.complete,
        ),
      ]);

      final events = await service.getTaskEvents(
        DateTime(2026, 1, 1),
        DateTime(2026, 1, 2),
      );
      expect(events, hasLength(2));
      expect(events.map((event) => event.title), [
        'First blank event',
        'Second blank event',
      ]);
      expect(events.every((event) => event.id.isNotEmpty), isTrue);
      expect(events.map((event) => event.id).toSet(), hasLength(2));
      expect(
        _savedTaskEventIds((await persistence.read(namespace: 'guest'))!),
        hasLength(2),
      );
    },
  );

  test(
    'LocalDataService allocates collision-safe ids for every migrated collection',
    () async {
      final persistence = InMemoryLocalPersistence();
      await persistence.write(
        jsonEncode({
          'version': 5,
          'schedule': [
            {
              'id': '',
              'title': 'Schedule one',
              'tag': 'Focus',
              'height': 80.0,
              'color': Colors.teal.toARGB32(),
              'time': const {'hour': 9, 'minute': 0},
            },
            {
              'id': '',
              'title': 'Schedule two',
              'tag': 'Focus',
              'height': 80.0,
              'color': Colors.teal.toARGB32(),
              'time': const {'hour': 10, 'minute': 0},
            },
          ],
          'microTasks': [
            {'id': '', 'title': 'Micro one', 'tag': 'Focus', 'minutes': 5},
            {'id': '', 'title': 'Micro two', 'tag': 'Focus', 'minutes': 10},
          ],
          'emotionCheckIns': [
            {'id': '', 'at': '2026-01-01T08:00:00.000', 'state': 'stable'},
            {'id': '', 'at': '2026-01-02T08:00:00.000', 'state': 'efficient'},
          ],
          'goals': [
            {
              'id': '',
              'title': 'Goal one',
              'due': '2026-01-03T00:00:00.000',
              'priority': 3,
              'tasks': [],
            },
            {
              'id': '',
              'title': 'Goal two',
              'due': '2026-01-04T00:00:00.000',
              'priority': 3,
              'tasks': [],
            },
          ],
        }),
      );
      final service = LocalDataService.forPersistence(persistence);

      final schedules = await service.getScheduleEntries();
      final microTasks = await service.getMicroTasks();
      final emotions = await service.getEmotionCheckIns(DateTime(2026, 1, 1));
      final goals = await service.getGoals();

      expect(schedules, hasLength(2));
      expect(schedules.map((entry) => entry.id).toSet(), hasLength(2));
      expect(microTasks, hasLength(2));
      expect(microTasks.map((task) => task.id).toSet(), hasLength(2));
      expect(emotions, hasLength(1));
      expect(emotions.single.id, isNotEmpty);
      expect(goals, hasLength(2));
      expect(goals.map((goal) => goal.id).toSet(), hasLength(2));
    },
  );

  test(
    'LocalDataService owns Goal task and dependency lists at ingress and egress',
    () async {
      final persistence = InMemoryLocalPersistence();
      final service = LocalDataService.forPersistence(persistence);
      final dependencies = <String>['dependency_1'];
      final tasks = <GoalTask>[
        GoalTask(
          id: 'goal_task_owned',
          title: 'Owned task',
          durationMinutes: 20,
          load: CognitiveLoad.medium,
          tag: 'Focus',
          dependsOn: dependencies,
        ),
      ];
      final goal = Goal(
        id: 'goal_owned',
        title: 'Owned goal',
        due: DateTime(2026, 1, 3),
        priority: 3,
        tasks: tasks,
      );

      await service.upsertGoal(goal);
      dependencies.add('caller_mutation');
      tasks.clear();

      var stored = (await service.getGoals()).single;
      expect(stored.tasks, hasLength(1));
      expect(stored.tasks.single.dependsOn, ['dependency_1']);

      stored.tasks.single.dependsOn.add('result_mutation');
      stored.tasks.clear();
      stored = (await service.getGoals()).single;
      expect(stored.tasks, hasLength(1));
      expect(stored.tasks.single.dependsOn, ['dependency_1']);
    },
  );

  test(
    'LocalDataService owns scheduling tuning maps at ingress and egress',
    () async {
      final persistence = InMemoryLocalPersistence();
      final service = LocalDataService.forPersistence(persistence);
      final multipliers = <String, double>{'Focus': 1.25};

      await service.setSchedulingTuning(
        SchedulingTuning(tagDurationMultiplier: multipliers),
      );
      multipliers['Focus'] = 9.0;
      multipliers['CallerOnly'] = 2.0;

      var tuning = await service.getSchedulingTuning();
      expect(tuning.tagDurationMultiplier, {'Focus': 1.25});

      tuning.tagDurationMultiplier['ReturnedMutation'] = 3.0;
      tuning = await service.getSchedulingTuning();
      expect(tuning.tagDurationMultiplier, {'Focus': 1.25});
    },
  );

  test('LocalDataService clones microtasks at ingress and egress', () async {
    final persistence = InMemoryLocalPersistence();
    final service = LocalDataService.forPersistence(persistence);
    final task = MicroTask(
      id: 'micro_owned',
      title: 'Original',
      tag: 'Focus',
      minutes: 5,
    );

    await service.addMicroTask(task);
    task.title = 'Caller mutation';
    task.minutes = 99;

    var stored = (await service.getMicroTasks()).firstWhere(
      (candidate) => candidate.id == task.id,
    );
    expect(stored.title, 'Original');
    expect(stored.minutes, 5);

    stored.title = 'Returned mutation';
    stored.minutes = 100;
    stored = (await service.getMicroTasks()).firstWhere(
      (candidate) => candidate.id == task.id,
    );
    expect(stored.title, 'Original');
    expect(stored.minutes, 5);
  });

  test(
    'LocalDataService snapshots mutable inputs before queueing mutations',
    () async {
      final persistence = _DelayedFailingLocalPersistence();
      final service = LocalDataService.forPersistence(persistence);
      await service.addMicroTask(
        MicroTask(
          id: 'micro_queued_update',
          title: 'Before update',
          tag: 'Focus',
          minutes: 5,
        ),
      );

      persistence.delayNextWrite();
      final blockingWrite = service.setThemeMode('queued');
      await persistence.delayedWriteStarted;

      final dependencies = <String>['goal_prerequisite'];
      final goalTasks = <GoalTask>[
        GoalTask(
          id: 'goal_queued_task',
          title: 'Queued goal task',
          durationMinutes: 30,
          load: CognitiveLoad.medium,
          tag: 'Focus',
          dependsOn: dependencies,
        ),
      ];
      final goalWrite = service.upsertGoal(
        Goal(
          id: 'goal_queued',
          title: 'Queued goal',
          due: DateTime(2026, 1, 3),
          priority: 3,
          tasks: goalTasks,
        ),
      );
      final addTask = MicroTask(
        id: 'micro_queued_add',
        title: 'Queued add',
        tag: 'Focus',
        minutes: 10,
      );
      final addWrite = service.addMicroTask(addTask);
      final updateTask = MicroTask(
        id: 'micro_queued_update',
        title: 'Queued update',
        tag: 'Plan',
        minutes: 20,
      );
      final updateWrite = service.updateMicroTask(updateTask);
      final multipliers = <String, double>{'Focus': 1.25};
      final tuningWrite = service.setSchedulingTuning(
        SchedulingTuning(tagDurationMultiplier: multipliers),
      );

      dependencies.add('caller_dependency');
      goalTasks.clear();
      addTask
        ..title = 'Caller add mutation'
        ..minutes = 99;
      updateTask
        ..title = 'Caller update mutation'
        ..minutes = 88;
      multipliers
        ..['Focus'] = 9.0
        ..['CallerOnly'] = 2.0;

      persistence.releaseDelayedWrite();
      await Future.wait([
        blockingWrite,
        goalWrite,
        addWrite,
        updateWrite,
        tuningWrite,
      ]);

      final storedGoal = (await service.getGoals()).singleWhere(
        (goal) => goal.id == 'goal_queued',
      );
      expect(storedGoal.tasks, hasLength(1));
      expect(storedGoal.tasks.single.title, 'Queued goal task');
      expect(storedGoal.tasks.single.dependsOn, ['goal_prerequisite']);

      final storedTasks = await service.getMicroTasks();
      final storedAddedTask = storedTasks.singleWhere(
        (task) => task.id == 'micro_queued_add',
      );
      expect(storedAddedTask.title, 'Queued add');
      expect(storedAddedTask.minutes, 10);
      final storedUpdatedTask = storedTasks.singleWhere(
        (task) => task.id == 'micro_queued_update',
      );
      expect(storedUpdatedTask.title, 'Queued update');
      expect(storedUpdatedTask.minutes, 20);
      expect((await service.getSchedulingTuning()).tagDurationMultiplier, {
        'Focus': 1.25,
      });

      final persisted =
          jsonDecode((await persistence.read(namespace: 'guest'))!) as Map;
      final persistedGoal = (persisted['goals'] as List)
          .map((goal) => Map<String, dynamic>.from(goal as Map))
          .singleWhere((goal) => goal['id'] == 'goal_queued');
      final persistedGoalTask = Map<String, dynamic>.from(
        (persistedGoal['tasks'] as List).single as Map,
      );
      expect(persistedGoalTask['title'], 'Queued goal task');
      expect(persistedGoalTask['dependsOn'], ['goal_prerequisite']);

      final persistedTasks = (persisted['microTasks'] as List)
          .map((task) => Map<String, dynamic>.from(task as Map))
          .toList();
      final persistedAddedTask = persistedTasks.singleWhere(
        (task) => task['id'] == 'micro_queued_add',
      );
      expect(persistedAddedTask['title'], 'Queued add');
      expect(persistedAddedTask['minutes'], 10);
      final persistedUpdatedTask = persistedTasks.singleWhere(
        (task) => task['id'] == 'micro_queued_update',
      );
      expect(persistedUpdatedTask['title'], 'Queued update');
      expect(persistedUpdatedTask['minutes'], 20);
      final persistedTuning = Map<String, dynamic>.from(
        persisted['schedulingTuning'] as Map,
      );
      expect(persistedTuning['tagDurationMultiplier'], {'Focus': 1.25});
    },
  );

  test(
    'LocalDataService isolates every stored category for user A user B and guest',
    () async {
      final persistence = InMemoryLocalPersistence();

      var service = LocalDataService.forPersistence(persistence);
      await service.activateAuthenticatedUser(_cachedUser('user-a'));
      await _populateIdentity(service, 'a');

      service = LocalDataService.forPersistence(persistence);
      await service.activateAuthenticatedUser(_cachedUser('user-b'));
      await _expectIdentityValues(service, 'a', present: false);
      await _populateIdentity(service, 'b');

      service = LocalDataService.forPersistence(persistence);
      await service.activateGuest();
      expect(await service.getCurrentUser(), isNull);
      await _expectIdentityValues(service, 'a', present: false);
      await _expectIdentityValues(service, 'b', present: false);
      await _populateIdentity(service, 'guest');

      service = LocalDataService.forPersistence(persistence);
      await service.activateAuthenticatedUser(_cachedUser('user-a'));
      expect((await service.getCurrentUser())?.userId, 'user-a');
      expect(
        (await service.getCurrentUser())?.identityState,
        ClientIdentityState.offlineCached,
      );
      expect((await service.getUserProfile()).displayName, 'Profile user-a');
      await _expectIdentityValues(service, 'a', present: true);
      await _expectIdentityValues(service, 'b', present: false);
      await _expectIdentityValues(service, 'guest', present: false);

      service = LocalDataService.forPersistence(persistence);
      await service.activateAuthenticatedUser(_cachedUser('user-b'));
      expect((await service.getUserProfile()).displayName, 'Profile user-b');
      await _expectIdentityValues(service, 'a', present: false);
      await _expectIdentityValues(service, 'b', present: true);
      await _expectIdentityValues(service, 'guest', present: false);

      service = LocalDataService.forPersistence(persistence);
      await service.activateGuest();
      await _expectIdentityValues(service, 'a', present: false);
      await _expectIdentityValues(service, 'b', present: false);
      await _expectIdentityValues(service, 'guest', present: true);
    },
  );

  test(
    'LocalDataService never authenticates arbitrary local passwords',
    () async {
      final persistence = InMemoryLocalPersistence();
      final service = LocalDataService.forPersistence(persistence);

      expect(await service.login('alice@example.com', 'secret1'), isFalse);
      expect(
        await service.registerAccount(
          username: 'alice@example.com',
          password: 'secret1',
        ),
        isFalse,
      );
      expect(await service.getCurrentUser(), isNull);
    },
  );

  test(
    'logout switches to guest without deleting authenticated data',
    () async {
      final persistence = InMemoryLocalPersistence();
      var service = LocalDataService.forPersistence(persistence);
      await service.activateAuthenticatedUser(_cachedUser('user-a'));
      await _populateIdentity(service, 'a');

      await service.logout();

      expect(await service.getCurrentUser(), isNull);
      await _expectIdentityValues(service, 'a', present: false);
      service = LocalDataService.forPersistence(persistence);
      await service.activateAuthenticatedUser(_cachedUser('user-a'));
      await _expectIdentityValues(service, 'a', present: true);
    },
  );

  test(
    'logout clears cached identity even when user data is malformed',
    () async {
      final persistence = InMemoryLocalPersistence();
      await persistence.write(
        jsonEncode({
          'version': 1,
          'kind': 'authenticated',
          'user': {
            'id': 'user-a',
            'contactAddress': 'alice@example.com',
            'displayName': 'Alice',
          },
        }),
        namespace: 'session',
      );
      await persistence.write('{not-json', namespace: 'user:user-a');
      final service = LocalDataService.forPersistence(persistence);

      await service.logout();

      final session =
          jsonDecode((await persistence.read(namespace: 'session'))!)
              as Map<String, dynamic>;
      expect(session['kind'], 'guest');
      expect(await service.getCurrentUser(), isNull);
      expect(await persistence.read(namespace: 'user:user-a'), '{not-json');
    },
  );

  test(
    'legacy data migrates to guest once and remains rollback safe',
    () async {
      final persistence = InMemoryLocalPersistence();
      final legacy = jsonEncode({
        'version': 5,
        'schedule': [
          {
            'id': 'legacy-schedule',
            'title': 'Legacy schedule',
            'tag': 'Legacy',
            'height': 80.0,
            'color': Colors.teal.toARGB32(),
            'time': const {'hour': 9, 'minute': 0},
          },
        ],
        'currentUser': {
          'id': 'must-not-be-trusted',
          'contactAddress': 'legacy@example.com',
          'displayName': 'Legacy user',
        },
      });
      await persistence.write(legacy);

      var service = LocalDataService.forPersistence(persistence);
      expect(
        (await service.getScheduleEntries()).map((entry) => entry.id),
        contains('legacy-schedule'),
      );
      expect(await service.getCurrentUser(), isNull);
      expect(await persistence.read(), legacy);

      final guestRaw = await persistence.read(namespace: 'guest');
      final guest = jsonDecode(guestRaw!) as Map<String, dynamic>;
      expect(guest['version'], 6);
      expect(guest['legacyMigration'], {
        'sourceVersion': 5,
        'state': 'completed',
      });

      await persistence.write(jsonEncode({'version': 5, 'schedule': const []}));
      service = LocalDataService.forPersistence(persistence);
      expect(
        (await service.getScheduleEntries()).map((entry) => entry.id),
        contains('legacy-schedule'),
      );

      await service.activateAuthenticatedUser(_cachedUser('new-user'));
      expect(
        (await service.getScheduleEntries()).map((entry) => entry.id),
        isNot(contains('legacy-schedule')),
      );
    },
  );

  test(
    'existing guest data is never overwritten by legacy migration',
    () async {
      final persistence = InMemoryLocalPersistence();
      await persistence.write(
        jsonEncode({
          'version': 5,
          'schedule': [
            {
              'id': 'legacy-schedule',
              'title': 'Legacy schedule',
              'tag': 'Legacy',
              'height': 80.0,
              'color': Colors.teal.toARGB32(),
              'time': const {'hour': 9, 'minute': 0},
            },
          ],
        }),
      );
      final guestRaw = jsonEncode({
        'version': 6,
        'schedule': [
          {
            'id': 'guest-schedule',
            'title': 'Guest schedule',
            'tag': 'Guest',
            'height': 80.0,
            'color': Colors.blue.toARGB32(),
            'time': const {'hour': 10, 'minute': 0},
          },
        ],
        'teamCalendars': [
          {
            'memberId': 'guest-member',
            'displayName': 'Guest member',
            'role': 'Guest',
            'energy': 'medium',
            'permission': 'details',
            'busy': const [],
          },
        ],
        'legacyMigration': {'sourceVersion': 5, 'state': 'completed'},
      });
      await persistence.write(guestRaw, namespace: 'guest');

      final service = LocalDataService.forPersistence(persistence);
      final ids = (await service.getScheduleEntries()).map((entry) => entry.id);

      expect(ids, contains('guest-schedule'));
      expect(ids, isNot(contains('legacy-schedule')));
      expect(await persistence.read(namespace: 'guest'), guestRaw);
    },
  );

  test('malformed legacy data remains untouched and is not copied', () async {
    final persistence = InMemoryLocalPersistence();
    const malformed = '{not-json';
    await persistence.write(malformed);
    final service = LocalDataService.forPersistence(persistence);

    await expectLater(service.getScheduleEntries(), throwsFormatException);

    expect(await persistence.read(), malformed);
    expect(await persistence.exists(namespace: 'guest'), isFalse);
  });

  test(
    'LocalDataService persists the cached profile identity across reloads',
    () async {
      final persistence = InMemoryLocalPersistence();
      final service = LocalDataService.forPersistence(persistence);

      final defaultProfile = await service.getUserProfile();
      expect(defaultProfile.displayName, '时序智配用户');
      expect(defaultProfile.status, '本地存储');

      await service.activateAuthenticatedUser(_cachedUser('alice'));
      final loggedInProfile = await service.getUserProfile();
      expect(loggedInProfile.displayName, 'Profile alice');
      expect(loggedInProfile.status, '本地存储');

      final reloadedService = LocalDataService.forPersistence(persistence);
      final reloadedProfile = await reloadedService.getUserProfile();
      expect(reloadedProfile.displayName, loggedInProfile.displayName);
      expect(reloadedProfile.status, loggedInProfile.status);

      await reloadedService.logout();
      final loggedOutService = LocalDataService.forPersistence(persistence);
      final loggedOutProfile = await loggedOutService.getUserProfile();
      expect(loggedOutProfile.displayName, defaultProfile.displayName);
      expect(loggedOutProfile.status, defaultProfile.status);
    },
  );
}
