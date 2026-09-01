import 'dart:convert';
import 'package:flutter/material.dart';

import '../models/models.dart';
import '../utils/schedule_occurrence.dart';
import 'data_service.dart';
import 'local_persistence/local_persistence.dart';
import 'local_persistence/local_persistence_io.dart'
    if (dart.library.html) 'local_persistence/local_persistence_web.dart';
import 'review/review_rules.dart';
import 'debug/storage_info.dart';

class _LocalDataSnapshot {
  final List<ScheduleEntry> schedule;
  final List<MicroTask> microTasks;
  final List<TaskEvent> events;
  final List<TeamMemberCalendar> teamCalendars;
  final List<EmotionCheckIn> emotion;
  final List<Goal> goals;
  final String? favoriteDeviceId;
  final String themeMode;
  final String locale;
  final UserAccount? currentUser;
  final SchedulingTuning tuning;

  const _LocalDataSnapshot({
    required this.schedule,
    required this.microTasks,
    required this.events,
    required this.teamCalendars,
    required this.emotion,
    required this.goals,
    required this.favoriteDeviceId,
    required this.themeMode,
    required this.locale,
    required this.currentUser,
    required this.tuning,
  });
}

class LocalDataService implements DataService {
  LocalDataService._({LocalPersistence? persistence})
    : _persistence = persistence ?? createLocalPersistence();

  static final LocalDataService instance = LocalDataService._();

  @visibleForTesting
  factory LocalDataService.forPersistence(LocalPersistence persistence) {
    return LocalDataService._(persistence: persistence);
  }

  static const int _schemaVersion = 5;

  final LocalPersistence _persistence;

  bool _loaded = false;

  final List<ScheduleEntry> _schedule = [];
  final List<MicroTask> _microTasks = [];
  final List<TaskEvent> _events = [];
  final List<TeamMemberCalendar> _teamCalendars = [];
  final List<EmotionCheckIn> _emotion = [];
  final List<Goal> _goals = [];
  String? _favoriteDeviceId;
  String _themeMode = 'system';
  String _locale = 'zh_CN';
  Future<void> _mutationQueue = Future<void>.value();
  Future<void>? _loadFuture;

  // 新增：用于存储当前登录用户
  UserAccount? _currentUser;

  SchedulingTuning _tuning = const SchedulingTuning();

  String _newId(String prefix) {
    final ts = DateTime.now().microsecondsSinceEpoch;
    return '$prefix$ts';
  }

  String _newUniqueId(String prefix, Set<String> seenIds) {
    while (true) {
      final id = _newId(prefix);
      if (seenIds.add(id)) return id;
    }
  }

  String _normalizeJsonText(String raw) {
    if (raw.isEmpty) return raw;
    if (raw.codeUnitAt(0) == 0xFEFF) {
      return raw.substring(1);
    }
    return raw;
  }

  Map<String, Object?>? _decodeRootObject(String? raw) {
    if (raw == null) return null;
    final normalized = _normalizeJsonText(raw).trim();
    if (normalized.isEmpty) {
      throw const FormatException('Persisted data is empty');
    }
    final decoded = jsonDecode(normalized);
    if (decoded is! Map) {
      throw const FormatException('Persisted data must be a JSON object');
    }
    return Map<String, Object?>.from(decoded);
  }

  dynamic _firstPresent(Map<String, Object?> root, List<String> keys) {
    for (final k in keys) {
      if (root.containsKey(k)) return root[k];
    }
    return null;
  }

  bool _hasLegacyAlias(Map<String, Object?> root, List<String> keys) {
    if (keys.isEmpty) return false;
    for (var i = 1; i < keys.length; i++) {
      if (root.containsKey(keys[i])) return true;
    }
    return false;
  }

  List<Map<String, Object?>> _asMapList(dynamic raw) {
    if (raw == null) return const [];
    if (raw is! List) {
      throw const FormatException('Persisted collection must be a JSON list');
    }
    return raw.map((item) {
      if (item is! Map) {
        throw const FormatException(
          'Persisted collection item must be an object',
        );
      }
      return Map<String, Object?>.from(item);
    }).toList();
  }

  Map<String, Object?>? _asMap(dynamic raw) {
    if (raw == null) return null;
    if (raw is! Map) {
      throw const FormatException('Persisted value must be a JSON object');
    }
    return Map<String, Object?>.from(raw);
  }

  String? _asTrimmedString(dynamic raw) {
    if (raw == null) return null;
    if (raw is! String) {
      throw const FormatException('Persisted value must be a string');
    }
    final out = raw.trim();
    return out.isEmpty ? null : out;
  }

  Future<void> _ensureLoaded() {
    if (_loaded) return Future<void>.value();
    final inFlight = _loadFuture;
    if (inFlight != null) return inFlight;

    final load = _loadAndMigrate();
    _loadFuture = load.whenComplete(() {
      _loadFuture = null;
    });
    return _loadFuture!;
  }

  Future<void> _loadAndMigrate() async {
    final beforeLoad = _captureState();
    try {
      _schedule.clear();
      _microTasks.clear();
      _events.clear();
      _teamCalendars.clear();
      _emotion.clear();
      _goals.clear();
      _favoriteDeviceId = null;
      _themeMode = 'system';
      _locale = 'zh_CN';
      _currentUser = null;
      _tuning = const SchedulingTuning();

      var shouldSave = false;
      final raw = await _persistence.read();
      try {
        final decoded = _decodeRootObject(raw);
        if (decoded != null) {
          final version = (decoded['version'] as num?)?.toInt();
          if (version == null || version < _schemaVersion) {
            shouldSave = true;
          }

          final scheduleKeys = ['schedule', 'scheduleEntries'];
          final microKeys = ['microTasks', 'microtasks'];
          final eventsKeys = ['taskEvents', 'events'];
          final teamKeys = ['teamCalendars', 'teamMemberCalendars'];
          final tuningKeys = ['schedulingTuning', 'tuning'];
          final emotionKeys = ['emotionCheckIns', 'emotion'];
          final goalsKeys = ['goals', 'goalList'];
          final favoriteDeviceKeys = ['favoriteDeviceId', 'preferredDeviceId'];

          if (_hasLegacyAlias(decoded, scheduleKeys) ||
              _hasLegacyAlias(decoded, microKeys) ||
              _hasLegacyAlias(decoded, eventsKeys) ||
              _hasLegacyAlias(decoded, teamKeys) ||
              _hasLegacyAlias(decoded, tuningKeys) ||
              _hasLegacyAlias(decoded, emotionKeys) ||
              _hasLegacyAlias(decoded, goalsKeys) ||
              _hasLegacyAlias(decoded, favoriteDeviceKeys)) {
            shouldSave = true;
          }

          final scheduleJson = _firstPresent(decoded, scheduleKeys);
          final microJson = _firstPresent(decoded, microKeys);
          final eventsJson = _firstPresent(decoded, eventsKeys);
          final teamJson = _firstPresent(decoded, teamKeys);
          final tuningJson = _firstPresent(decoded, tuningKeys);
          final emotionJson = _firstPresent(decoded, emotionKeys);
          final goalsJson = _firstPresent(decoded, goalsKeys);
          final favoriteDeviceIdJson = _firstPresent(
            decoded,
            favoriteDeviceKeys,
          );

          // 新增解析当前用户
          final currentUserJson = decoded['currentUser'];
          if (currentUserJson != null) {
            final currentUserMap = _asMap(currentUserJson);
            if (currentUserMap != null) {
              _currentUser = UserAccount.fromJson(currentUserMap);
            }
          }

          final scheduleMapList = _asMapList(scheduleJson);
          if (scheduleMapList.isNotEmpty) {
            _schedule
              ..clear()
              ..addAll(scheduleMapList.map(ScheduleEntry.fromJson));
          }

          final microMapList = _asMapList(microJson);
          if (microMapList.isNotEmpty) {
            _microTasks
              ..clear()
              ..addAll(microMapList.map(MicroTask.fromJson));
          }

          final eventsMapList = _asMapList(eventsJson);
          if (eventsMapList.isNotEmpty) {
            _events
              ..clear()
              ..addAll(eventsMapList.map(TaskEvent.fromJson));
          }

          final teamMapList = _asMapList(teamJson);
          if (teamMapList.isNotEmpty) {
            _teamCalendars
              ..clear()
              ..addAll(teamMapList.map(TeamMemberCalendar.fromJson));
          }

          final tuningMap = _asMap(tuningJson);
          if (tuningMap != null) {
            _tuning = SchedulingTuning.fromJson(tuningMap);
          }

          final emotionMapList = _asMapList(emotionJson);
          if (emotionMapList.isNotEmpty) {
            _emotion
              ..clear()
              ..addAll(emotionMapList.map(EmotionCheckIn.fromJson));
          }

          final goalsMapList = _asMapList(goalsJson);
          if (goalsMapList.isNotEmpty) {
            _goals
              ..clear()
              ..addAll(goalsMapList.map(Goal.fromJson));
          }

          _favoriteDeviceId = _asTrimmedString(favoriteDeviceIdJson);

          final themeModeJson = decoded['themeMode'];
          if (themeModeJson != null && themeModeJson is! String) {
            throw const FormatException(
              'Persisted theme mode must be a string',
            );
          }
          if (themeModeJson is String && themeModeJson.isNotEmpty) {
            _themeMode = themeModeJson;
          }

          final localeJson = decoded['locale'];
          if (localeJson != null && localeJson is! String) {
            throw const FormatException('Persisted locale must be a string');
          }
          if (localeJson is String && localeJson.isNotEmpty) {
            _locale = localeJson;
          }
        }
      } catch (_) {
        _restoreState(beforeLoad);
        rethrow;
      }

      final scheduleSeenIds = <String>{};
      for (var i = 0; i < _schedule.length; i++) {
        final e = _schedule[i];
        final id = e.id?.trim();
        if (id == null || id.isEmpty || scheduleSeenIds.contains(id)) {
          _schedule[i] = e.copyWith(id: _newUniqueId('sch_', scheduleSeenIds));
          shouldSave = true;
        } else {
          scheduleSeenIds.add(id);
        }
      }

      final microSeenIds = <String>{};
      for (final t in _microTasks) {
        final id = t.id?.trim();
        if (id == null || id.isEmpty || microSeenIds.contains(id)) {
          t.id = _newUniqueId('mt_', microSeenIds);
          shouldSave = true;
        } else {
          microSeenIds.add(id);
        }
      }

      final emotionSeenIds = <String>{};
      for (var i = 0; i < _emotion.length; i++) {
        final e = _emotion[i];
        final id = e.id.trim();
        if (id.isEmpty || emotionSeenIds.contains(id)) {
          _emotion[i] = EmotionCheckIn(
            id: _newUniqueId('emo_', emotionSeenIds),
            at: e.at,
            state: e.state,
            note: e.note,
          );
          shouldSave = true;
        } else {
          emotionSeenIds.add(id);
        }
      }

      final taskEventSeenIds = <String>{};
      for (var i = 0; i < _events.length; i++) {
        final event = _events[i];
        if (event.id.trim().isEmpty || !taskEventSeenIds.add(event.id)) {
          _events[i] = _withTaskEventId(
            event,
            _newUniqueTaskEventId(taskEventSeenIds),
          );
          shouldSave = true;
        }
      }

      if (_emotion.length > 1) {
        final oldLength = _emotion.length;
        final sorted = List<EmotionCheckIn>.from(_emotion)
          ..sort((a, b) => a.at.compareTo(b.at));
        final byDay = <String, EmotionCheckIn>{};
        for (final e in sorted) {
          final k =
              '${e.at.year.toString().padLeft(4, '0')}-${e.at.month.toString().padLeft(2, '0')}-${e.at.day.toString().padLeft(2, '0')}';
          byDay[k] = e;
        }
        _emotion
          ..clear()
          ..addAll(byDay.values.toList()..sort((a, b) => a.at.compareTo(b.at)));
        if (_emotion.length != oldLength) {
          shouldSave = true;
        }
      }

      final goalSeenIds = <String>{};
      for (var i = 0; i < _goals.length; i++) {
        final g = _goals[i];
        final id = g.id.trim();
        if (id.isEmpty || goalSeenIds.contains(id)) {
          _goals[i] = Goal(
            id: _newUniqueId('goal_', goalSeenIds),
            title: g.title,
            due: g.due,
            priority: g.priority,
            tasks: _cloneGoalTasks(g.tasks),
          );
          shouldSave = true;
        } else {
          goalSeenIds.add(id);
        }
      }

      if (_schedule.isEmpty && _microTasks.isEmpty) {
        _seed();
        shouldSave = true;
      }

      if (_teamCalendars.isEmpty) {
        _seedTeam();
        shouldSave = true;
      }

      if (shouldSave) {
        await _save();
      }
      _loaded = true;
    } catch (_) {
      _restoreState(beforeLoad);
      rethrow;
    }
  }

  void _seed() {
    _schedule
      ..clear()
      ..addAll([
        ScheduleEntry(
          id: _newId('sch_'),
          title: '深度工作：架构设计',
          tag: 'Deep Work',
          height: 120,
          color: Colors.teal,
          time: const TimeOfDay(hour: 9, minute: 0),
        ),
        ScheduleEntry(
          id: _newId('sch_'),
          title: '邮件清理（微任务）',
          tag: 'Micro Task',
          height: 40,
          color: Colors.orange,
          time: const TimeOfDay(hour: 11, minute: 30),
        ),
      ]);

    _microTasks
      ..clear()
      ..addAll([
        MicroTask(
          id: _newId('mt_'),
          title: '回复人事邮件',
          tag: 'Micro Task',
          minutes: 5,
          requirement: '笔记本电脑',
        ),
      ]);
  }

  void _seedTeam() {
    _teamCalendars
      ..clear()
      ..addAll([
        const TeamMemberCalendar(
          memberId: 'm_li',
          displayName: '李明',
          role: '项目经理',
          energy: EnergyTier.high,
          permission: TeamSharePermission.details,
          busy: [
            ScheduleEntry(
              id: 'li_1',
              title: '产品同步',
              tag: 'Meeting',
              height: 80.0,
              color: Colors.blue,
              time: TimeOfDay(hour: 14, minute: 0),
            ),
          ],
        ),
      ]);
  }

  List<GoalTask> _cloneGoalTasks(List<GoalTask> tasks) {
    return tasks
        .map(
          (task) => task.copyWith(dependsOn: List<String>.from(task.dependsOn)),
        )
        .toList();
  }

  Goal _cloneGoal(Goal goal) {
    return Goal(
      id: goal.id,
      title: goal.title,
      due: goal.due,
      priority: goal.priority,
      tasks: _cloneGoalTasks(goal.tasks),
    );
  }

  SchedulingTuning _cloneTuning(SchedulingTuning tuning) {
    return SchedulingTuning(
      defaultDurationMultiplier: tuning.defaultDurationMultiplier,
      tagDurationMultiplier: Map<String, double>.from(
        tuning.tagDurationMultiplier,
      ),
      highLoadPenaltyWhenLowEnergy: tuning.highLoadPenaltyWhenLowEnergy,
    );
  }

  TeamMemberCalendar _cloneTeamCalendar(TeamMemberCalendar calendar) {
    return TeamMemberCalendar(
      memberId: calendar.memberId,
      displayName: calendar.displayName,
      role: calendar.role,
      energy: calendar.energy,
      permission: calendar.permission,
      busy: List<ScheduleEntry>.from(calendar.busy),
    );
  }

  _LocalDataSnapshot _captureState() {
    return _LocalDataSnapshot(
      schedule: List<ScheduleEntry>.from(_schedule),
      microTasks: _microTasks.map((task) => task.clone()).toList(),
      events: List<TaskEvent>.from(_events),
      teamCalendars: _teamCalendars.map(_cloneTeamCalendar).toList(),
      emotion: List<EmotionCheckIn>.from(_emotion),
      goals: _goals.map(_cloneGoal).toList(),
      favoriteDeviceId: _favoriteDeviceId,
      themeMode: _themeMode,
      locale: _locale,
      currentUser: _currentUser,
      tuning: _cloneTuning(_tuning),
    );
  }

  void _restoreState(_LocalDataSnapshot state) {
    _schedule
      ..clear()
      ..addAll(state.schedule);
    _microTasks
      ..clear()
      ..addAll(state.microTasks.map((task) => task.clone()));
    _events
      ..clear()
      ..addAll(state.events);
    _teamCalendars
      ..clear()
      ..addAll(state.teamCalendars.map(_cloneTeamCalendar));
    _emotion
      ..clear()
      ..addAll(state.emotion);
    _goals
      ..clear()
      ..addAll(state.goals.map(_cloneGoal));
    _favoriteDeviceId = state.favoriteDeviceId;
    _themeMode = state.themeMode;
    _locale = state.locale;
    _currentUser = state.currentUser;
    _tuning = _cloneTuning(state.tuning);
  }

  Future<void> _saveState(_LocalDataSnapshot state) async {
    final obj = {
      'version': _schemaVersion,
      'savedAt': DateTime.now().toIso8601String(),
      'schedule': state.schedule.map((e) => e.toJson()).toList(),
      'microTasks': state.microTasks.map((t) => t.toJson()).toList(),
      'taskEvents': state.events.map((e) => e.toJson()).toList(),
      'teamCalendars': state.teamCalendars.map((c) => c.toJson()).toList(),
      'schedulingTuning': state.tuning.toJson(),
      'emotionCheckIns': state.emotion.map((e) => e.toJson()).toList(),
      'goals': state.goals.map((g) => g.toJson()).toList(),
      'favoriteDeviceId': state.favoriteDeviceId,
      'themeMode': state.themeMode,
      'locale': state.locale,
      'currentUser': state.currentUser?.toJson(),
    };

    final jsonText = const JsonEncoder.withIndent('  ').convert(obj);
    await _persistence.write(jsonText);
  }

  Future<void> _save({List<TaskEvent>? events, List<Goal>? goals}) async {
    final state = _captureState();
    await _saveState(
      _LocalDataSnapshot(
        schedule: state.schedule,
        microTasks: state.microTasks,
        events: events == null ? state.events : List<TaskEvent>.from(events),
        teamCalendars: state.teamCalendars,
        emotion: state.emotion,
        goals: goals == null ? state.goals : goals.map(_cloneGoal).toList(),
        favoriteDeviceId: state.favoriteDeviceId,
        themeMode: state.themeMode,
        locale: state.locale,
        currentUser: state.currentUser,
        tuning: state.tuning,
      ),
    );
  }

  Future<T> _enqueueMutation<T>(Future<T> Function() operation) {
    final result = _mutationQueue.then((_) async {
      await _ensureLoaded();
      final before = _captureState();
      try {
        return await operation();
      } catch (_) {
        _restoreState(before);
        rethrow;
      }
    });
    _mutationQueue = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  Future<StorageInfo> debugStorageInfo() async {
    final exists = await _persistence.exists();
    final raw = await _persistence.read();
    final bytes = raw == null ? 0 : utf8.encode(raw).length;
    return StorageInfo(
      exists: exists,
      bytes: bytes,
      backend: _persistence.runtimeType.toString(),
    );
  }

  @override
  Future<EnergyStatus> getEnergyStatus() async {
    await _ensureLoaded();
    return const EnergyStatus(
      level: "medium",
      status: '心流',
      description: '仅本地模拟',
      batteryPercent: 85,
    );
  }

  @override
  Future<EmotionState> getEmotionState() async {
    await _ensureLoaded();
    final now = DateTime.now();
    final today = _emotion.where((e) => sameDay(e.at, now)).toList()
      ..sort((a, b) => a.at.compareTo(b.at));
    if (today.isNotEmpty) {
      return today.last.state;
    }
    if (_emotion.isEmpty) return EmotionState.stable;
    final all = List<EmotionCheckIn>.from(_emotion)
      ..sort((a, b) => a.at.compareTo(b.at));
    return all.last.state;
  }

  @override
  Future<void> addEmotionCheckIn(EmotionCheckIn checkIn) {
    return _enqueueMutation(() async {
      await _ensureLoaded();
      final id = checkIn.id.isEmpty ? _newId('emo_') : checkIn.id;
      final day = DateTime(checkIn.at.year, checkIn.at.month, checkIn.at.day);
      _emotion.removeWhere((e) => sameDay(e.at, day));
      final c = EmotionCheckIn(
        id: id,
        at: checkIn.at,
        state: checkIn.state,
        note: checkIn.note,
      );
      _emotion.add(c);
      await _save();
    });
  }

  @override
  Future<List<EmotionCheckIn>> getEmotionCheckIns(DateTime day) async {
    await _ensureLoaded();
    final d = DateTime(day.year, day.month, day.day);
    final out = _emotion.where((e) => sameDay(e.at, d)).toList()
      ..sort((a, b) => a.at.compareTo(b.at));
    return out;
  }

  @override
  Future<List<Goal>> getGoals() async {
    await _ensureLoaded();
    final out = _goals.map(_cloneGoal).toList()
      ..sort((a, b) {
        final p = b.priority.compareTo(a.priority);
        if (p != 0) return p;
        return a.due.compareTo(b.due);
      });
    return out;
  }

  @override
  Future<void> upsertGoal(Goal goal) {
    final queuedGoal = _cloneGoal(goal);
    return _enqueueMutation(() async {
      await _ensureLoaded();
      final id = queuedGoal.id.isEmpty ? _newId('goal_') : queuedGoal.id;
      final g = Goal(
        id: id,
        title: queuedGoal.title,
        due: queuedGoal.due,
        priority: queuedGoal.priority.clamp(1, 5).toInt(),
        tasks: _cloneGoalTasks(queuedGoal.tasks),
      );
      final idx = _goals.indexWhere((x) => x.id == id);
      if (idx == -1) {
        _goals.add(g);
      } else {
        _goals[idx] = g;
      }
      await _save();
    });
  }

  @override
  Future<void> deleteGoal(String goalId) {
    return _enqueueMutation(() async {
      await _ensureLoaded();
      _goals.removeWhere((g) => g.id == goalId);
      await _save();
    });
  }

  @override
  Future<Task> getCurrentTask() async {
    await _ensureLoaded();
    return const Task(
      title: '构建调度 MVP',
      description: '本地优先的调度能力，支持可扩展数据层。',
      remainingMinutes: 45,
      progress: 0.3,
    );
  }

  @override
  Future<List<Task>> getNextTasks() async {
    await _ensureLoaded();
    return const [];
  }

  @override
  Future<List<ScheduleEntry>> getScheduleEntries() async {
    await _ensureLoaded();
    _schedule.sort((a, b) {
      final aMinutes = a.time.hour * 60 + a.time.minute;
      final bMinutes = b.time.hour * 60 + b.time.minute;
      return aMinutes.compareTo(bMinutes);
    });
    return List<ScheduleEntry>.from(_schedule);
  }

  @override
  Future<void> addScheduleEntry(ScheduleEntry entry) {
    return _enqueueMutation(() async {
      await _ensureLoaded();
      final withId = (entry.id == null || entry.id!.isEmpty)
          ? entry.copyWith(id: _newId('sch_'))
          : entry;
      final id = withId.id;
      if (id != null && id.isNotEmpty) {
        final idx = _schedule.indexWhere((e) => e.id == id);
        if (idx != -1) {
          _schedule[idx] = withId;
          await _save();
          return;
        }
      }
      _schedule.add(withId);
      await _save();
    });
  }

  @override
  Future<void> removeScheduleEntry(ScheduleEntry entry) {
    return _enqueueMutation(() async {
      await _ensureLoaded();
      if (entry.id != null && entry.id!.isNotEmpty) {
        _schedule.removeWhere((e) => e.id == entry.id);
      } else {
        _schedule.removeWhere(
          (e) => e.title == entry.title && e.time == entry.time,
        );
      }
      await _save();
    });
  }

  @override
  Future<List<MicroTask>> getMicroTasks() async {
    await _ensureLoaded();
    return _microTasks.map((t) => t.clone()).toList();
  }

  @override
  Future<void> addMicroTask(MicroTask task) {
    final queuedTask = task.clone();
    return _enqueueMutation(() async {
      await _ensureLoaded();
      await _addMicroTask(queuedTask);
    });
  }

  Future<void> _addMicroTask(MicroTask task) async {
    final t = task.clone();
    t.id ??= _newId('mt_');
    _microTasks.add(t);
    await _save();
  }

  @override
  Future<void> removeMicroTask(MicroTask task) {
    return _enqueueMutation(() async {
      await _ensureLoaded();
      if (task.id != null && task.id!.isNotEmpty) {
        _microTasks.removeWhere((t) => t.id == task.id);
      } else {
        _microTasks.removeWhere(
          (t) => t.title == task.title && t.tag == task.tag,
        );
      }
      await _save();
    });
  }

  @override
  Future<void> updateMicroTask(MicroTask task) {
    final queuedTask = task.clone();
    return _enqueueMutation(() async {
      await _ensureLoaded();
      if (queuedTask.id == null || queuedTask.id!.isEmpty) {
        await _addMicroTask(queuedTask);
        return;
      }

      final idx = _microTasks.indexWhere((t) => t.id == queuedTask.id);
      if (idx == -1) {
        await _addMicroTask(queuedTask);
        return;
      }

      _microTasks[idx] = queuedTask.clone();
      await _save();
    });
  }

  @override
  Future<List<TeamMember>> getTeamMembers() async {
    await _ensureLoaded();
    return _teamCalendars
        .map((c) {
          final busyMinutes = c.busy.fold<int>(
            0,
            (sum, entry) => sum + _durationFromHeight(entry.height),
          );
          final progress = (busyMinutes / 240.0).clamp(0.0, 1.0).toDouble();
          final task = c.busy.isEmpty ? '${c.role}规划中' : c.busy.first.title;
          return TeamMember(
            name: c.displayName,
            task: task,
            progress: progress,
            isHighEnergy: c.energy.index >= EnergyTier.high.index,
            busyTimes: c.busy
                .map(
                  (entry) => TimeRange(start: entry.time, end: _endTime(entry)),
                )
                .toList(growable: false),
          );
        })
        .toList(growable: false);
  }

  @override
  Future<UserProfile> getUserProfile() async {
    await _ensureLoaded();
    final user = _currentUser;
    if (user == null) {
      return const UserProfile(displayName: '时序智配用户', status: '本地存储');
    }
    return UserProfile(displayName: user.displayName, status: '本地存储');
  }

  @override
  Future<void> setFavoriteDevice(String deviceId) {
    return _enqueueMutation(() async {
      await _ensureLoaded();
      _favoriteDeviceId = deviceId;
      await _save();
    });
  }

  @override
  Future<String?> getFavoriteDevice() async {
    await _ensureLoaded();
    return _favoriteDeviceId;
  }

  @override
  Future<String> getThemeMode() async {
    await _ensureLoaded();
    return _themeMode;
  }

  @override
  Future<void> setThemeMode(String themeMode) {
    return _enqueueMutation(() async {
      await _ensureLoaded();
      _themeMode = themeMode;
      await _save();
    });
  }

  @override
  Future<String> getLocale() async {
    await _ensureLoaded();
    return _locale;
  }

  @override
  Future<void> setLocale(String locale) {
    return _enqueueMutation(() async {
      await _ensureLoaded();
      _locale = locale;
      await _save();
    });
  }

  int _durationFromHeight(double height) {
    return ((height / 80.0) * 60.0).round().clamp(1, 24 * 60).toInt();
  }

  TimeOfDay _endTime(ScheduleEntry entry) {
    final totalMinutes =
        entry.time.hour * 60 +
        entry.time.minute +
        _durationFromHeight(entry.height);
    return TimeOfDay(
      hour: (totalMinutes ~/ 60) % 24,
      minute: totalMinutes % 60,
    );
  }

  void _markGoalTaskDoneFromScheduleCompletion(
    String scheduleTaskId, {
    List<Goal>? goals,
  }) {
    if (scheduleTaskId.isEmpty) return;
    final targetGoals = goals ?? _goals;

    final schIdx = _schedule.indexWhere((e) => e.id == scheduleTaskId);
    if (schIdx != -1) {
      final e = _schedule[schIdx];
      final gid = e.goalId;
      final tid = e.goalTaskId;
      if (gid != null && gid.isNotEmpty && tid != null && tid.isNotEmpty) {
        final gIdx = targetGoals.indexWhere((g) => g.id == gid);
        if (gIdx == -1) return;
        final g = targetGoals[gIdx];
        var changed = false;
        final tasks = g.tasks
            .map((t) {
              if (t.id != tid) return t;
              if (t.done) return t;
              changed = true;
              return t.copyWith(done: true);
            })
            .toList(growable: false);
        if (!changed) return;
        targetGoals[gIdx] = Goal(
          id: g.id,
          title: g.title,
          due: g.due,
          priority: g.priority,
          tasks: tasks,
        );
        return;
      }
    }
  }

  List<TaskEvent> _taskEventCandidate(List<TaskEvent> events) {
    final replacements = <String, TaskEvent>{
      for (final event in events) event.id: event,
    };
    final seenIds = <String>{};
    final candidate = <TaskEvent>[];

    for (final event in _events) {
      if (!seenIds.add(event.id)) continue;
      candidate.add(replacements[event.id] ?? event);
    }
    for (final event in events) {
      if (seenIds.add(event.id)) {
        candidate.add(replacements[event.id]!);
      }
    }

    return candidate;
  }

  TaskEvent _withTaskEventId(TaskEvent event, String id) {
    return TaskEvent(
      id: id,
      taskId: event.taskId,
      title: event.title,
      tag: event.tag,
      load: event.load,
      at: event.at,
      type: event.type,
      plannedMinutes: event.plannedMinutes,
      energy: event.energy,
      actualMinutes: event.actualMinutes,
      interruptions: event.interruptions,
      reason: event.reason,
    );
  }

  String _newUniqueTaskEventId(Set<String> seenIds) {
    var suffix = 0;
    while (true) {
      final id = '${_newId('evt_')}${suffix == 0 ? '' : '_$suffix'}';
      if (seenIds.add(id)) return id;
      suffix++;
    }
  }

  @override
  Future<void> logTaskEvent(TaskEvent event) async {
    await upsertTaskEvents([event]);
  }

  List<TaskEvent> _normalizeIncomingTaskEvents(List<TaskEvent> events) {
    final seenIds = <String>{
      ..._events.map((event) => event.id.trim()).where((id) => id.isNotEmpty),
      ...events.map((event) => event.id.trim()).where((id) => id.isNotEmpty),
    };
    return events
        .map((event) {
          if (event.id.trim().isNotEmpty) return event;
          return _withTaskEventId(event, _newUniqueTaskEventId(seenIds));
        })
        .toList(growable: false);
  }

  @override
  Future<void> upsertTaskEvents(List<TaskEvent> events) {
    if (events.isEmpty) return Future<void>.value();
    final queuedEvents = List<TaskEvent>.from(events);
    return _enqueueMutation(() async {
      await _ensureLoaded();
      final normalizedEvents = _normalizeIncomingTaskEvents(queuedEvents);
      final candidateEvents = _taskEventCandidate(normalizedEvents);
      final candidateGoals = _goals.map(_cloneGoal).toList();
      final updatedEventIds = normalizedEvents.map((event) => event.id).toSet();

      for (final event in candidateEvents) {
        if (updatedEventIds.contains(event.id) &&
            event.type == TaskEventType.complete) {
          _markGoalTaskDoneFromScheduleCompletion(
            event.taskId,
            goals: candidateGoals,
          );
        }
      }

      await _save(events: candidateEvents, goals: candidateGoals);

      _events
        ..clear()
        ..addAll(candidateEvents);
      _goals
        ..clear()
        ..addAll(candidateGoals);
    });
  }

  @override
  Future<List<TaskEvent>> getTaskEvents(DateTime from, DateTime to) async {
    await _ensureLoaded();
    return _events
        .where((e) => !e.at.isBefore(from) && e.at.isBefore(to))
        .toList(growable: false);
  }

  @override
  Future<ReviewReport> getWeeklyReport(DateTime weekStart) {
    return _enqueueMutation(() async {
      await _ensureLoaded();
      final report = ReviewRules.weeklyReport(
        weekStart: weekStart,
        events: _events,
        currentTuning: _tuning,
      );
      _tuning = report.tuning;
      await _save();
      return report;
    });
  }

  @override
  Future<SchedulingTuning> getSchedulingTuning() async {
    await _ensureLoaded();
    return _cloneTuning(_tuning);
  }

  @override
  Future<void> setSchedulingTuning(SchedulingTuning tuning) {
    final queuedTuning = _cloneTuning(tuning);
    return _enqueueMutation(() async {
      await _ensureLoaded();
      _tuning = _cloneTuning(queuedTuning);
      await _save();
    });
  }

  @override
  Future<List<TeamMemberCalendar>> getTeamCalendars(DateTime day) async {
    await _ensureLoaded();
    return _teamCalendars.map(_cloneTeamCalendar).toList(growable: false);
  }

  @override
  Future<void> upsertTeamMember(TeamMemberCalendar member) {
    final queued = _cloneTeamCalendar(member);
    return _enqueueMutation(() async {
      await _ensureLoaded();
      final id = queued.memberId.isEmpty ? _newId('member_') : queued.memberId;
      final saved = TeamMemberCalendar(
        memberId: id,
        displayName: queued.displayName,
        role: queued.role,
        energy: queued.energy,
        permission: queued.permission,
        busy: List<ScheduleEntry>.from(queued.busy),
      );
      final idx = _teamCalendars.indexWhere((c) => c.memberId == id);
      if (idx == -1) {
        _teamCalendars.add(saved);
      } else {
        _teamCalendars[idx] = saved;
      }
      await _save();
    });
  }

  @override
  Future<void> deleteTeamMember(String memberId) {
    return _enqueueMutation(() async {
      await _ensureLoaded();
      _teamCalendars.removeWhere((c) => c.memberId == memberId);
      await _save();
    });
  }

  @override
  Future<void> updateTeamSharePermission(
    String memberId,
    TeamSharePermission permission,
  ) {
    return _enqueueMutation(() async {
      await _ensureLoaded();
      final idx = _teamCalendars.indexWhere((c) => c.memberId == memberId);
      if (idx == -1) return;
      final current = _teamCalendars[idx];
      if (current.permission == permission) return;
      _teamCalendars[idx] = TeamMemberCalendar(
        memberId: current.memberId,
        displayName: current.displayName,
        role: current.role,
        energy: current.energy,
        permission: permission,
        busy: List<ScheduleEntry>.from(current.busy),
      );
      await _save();
    });
  }

  @override
  Future<void> bookTeamMeeting(DateTime day, TeamMeetingRequest request) {
    return _enqueueMutation(() async {
      await _ensureLoaded();
      final entry = ScheduleEntry(
        id: _newId('meet_'),
        day: DateTime(day.year, day.month, day.day),
        title: request.title,
        tag: 'Collaboration',
        height: (request.minutes / 60.0) * 80.0,
        color: Colors.blue,
        time: request.start,
      );
      _schedule.add(entry);
      await _save();
    });
  }

  @override
  Future<EmotionType> getCurrentEmotion() async {
    final rand = DateTime.now().millisecond % 4;
    return EmotionType.values[rand];
  }

  // --- 重点：新增的认证相关实现 ---

  @override
  Future<UserAccount?> getCurrentUser() async {
    await _ensureLoaded();
    return _currentUser;
  }

  @override
  Future<bool> login(String account, String password) {
    return _enqueueMutation(() async {
      await _ensureLoaded();
      // 本地存储简单校验，只要账号密码有效就准入（因为没有服务器）
      if (account.isNotEmpty && password.length >= 6) {
        _currentUser = UserAccount(
          contactAddress: account,
          displayName:
              '用户_${account.substring(0, account.length > 4 ? 4 : account.length)}',
        );
        await _save();
        return true;
      }
      return false;
    });
  }

  @override
  Future<bool> registerAccount({
    required String username,
    required String password,
  }) {
    return _enqueueMutation(() async {
      await _ensureLoaded();
      if (username.isNotEmpty && password.length >= 6) {
        // 注册完毕直接成为当前用户
        _currentUser = UserAccount(
          contactAddress: username,
          displayName: '新用户_$username',
        );
        await _save();
        return true;
      }
      return false;
    });
  }

  @override
  Future<void> logout() {
    return _enqueueMutation(() async {
      await _ensureLoaded();
      _currentUser = null;
      await _save();
    });
  }
}
