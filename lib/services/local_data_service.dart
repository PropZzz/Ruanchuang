import 'dart:convert';

import 'package:flutter/material.dart';

import '../models/models.dart';
import 'data_service.dart';
import 'local_persistence/local_persistence.dart';
import 'local_persistence/local_persistence_io.dart'
    if (dart.library.html) 'local_persistence/local_persistence_web.dart';
import 'review/review_rules.dart';
import 'debug/storage_info.dart';

/// Local-first persistent data service.
///
/// Storage:
/// - IO: JSON file under user roaming data directory.
/// - Web: localStorage.
///
/// Privacy boundary: no HRV/sleep/device data is collected. This stores only
/// user-entered schedule, micro-task data, and local execution logs.
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

  SchedulingTuning _tuning = const SchedulingTuning();

  String _newId(String prefix) {
    final ts = DateTime.now().microsecondsSinceEpoch;
    return '$prefix$ts';
  }

  String _normalizeJsonText(String raw) {
    if (raw.isEmpty) return raw;
    // Defensively strip UTF-8 BOM so jsonDecode stays stable across platforms.
    if (raw.codeUnitAt(0) == 0xFEFF) {
      return raw.substring(1);
    }
    return raw;
  }

  Map<String, Object?>? _decodeRootObject(String? raw) {
    if (raw == null) return null;
    final normalized = _normalizeJsonText(raw).trim();
    if (normalized.isEmpty) return null;
    final decoded = jsonDecode(normalized);
    if (decoded is! Map) return null;
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
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((m) => Map<String, Object?>.from(m))
        .toList();
  }

  Map<String, Object?>? _asMap(dynamic raw) {
    if (raw is! Map) return null;
    return Map<String, Object?>.from(raw);
  }

  String? _asTrimmedString(dynamic raw) {
    if (raw is! String) return null;
    final out = raw.trim();
    return out.isEmpty ? null : out;
  }

  Future<void> _ensureLoaded() async {
    if (_loaded) return;

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
        final favoriteDeviceIdJson = _firstPresent(decoded, favoriteDeviceKeys);

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
        if (themeModeJson is String && themeModeJson.isNotEmpty) {
          _themeMode = themeModeJson;
        }

        final localeJson = decoded['locale'];
        if (localeJson is String && localeJson.isNotEmpty) {
          _locale = localeJson;
        }
      }
    } catch (_) {
      // Ignore corrupted storage and fall back to seed.
    }

    // Migration strategy:
    // - Missing ids: generate stable ids.
    // - Missing fields: handled by model defaults in fromJson.
    final scheduleSeenIds = <String>{};
    for (var i = 0; i < _schedule.length; i++) {
      final e = _schedule[i];
      final id = e.id?.trim();
      if (id == null || id.isEmpty || scheduleSeenIds.contains(id)) {
        _schedule[i] = e.copyWith(id: _newId('sch_'));
        shouldSave = true;
      } else {
        scheduleSeenIds.add(id);
      }
    }

    final microSeenIds = <String>{};
    for (final t in _microTasks) {
      final id = t.id?.trim();
      if (id == null || id.isEmpty || microSeenIds.contains(id)) {
        t.id = _newId('mt_');
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
          id: _newId('emo_'),
          at: e.at,
          state: e.state,
          note: e.note,
        );
        shouldSave = true;
      } else {
        emotionSeenIds.add(id);
      }
    }

    // Daily quick check-in migration: keep only the latest record per day.
    if (_emotion.length > 1) {
      final oldLength = _emotion.length;
      final sorted = List<EmotionCheckIn>.from(_emotion)
        ..sort((a, b) => a.at.compareTo(b.at));
      final byDay = <String, EmotionCheckIn>{};
      for (final e in sorted) {
        final k =
            '${e.at.year.toString().padLeft(4, '0')}-${e.at.month.toString().padLeft(2, '0')}-${e.at.day.toString().padLeft(2, '0')}';
        byDay[k] = e; // last write wins due to sorted order
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
          id: _newId('goal_'),
          title: g.title,
          due: g.due,
          priority: g.priority,
          tasks: g.tasks,
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

    _loaded = true;
    if (shouldSave) {
      await _save();
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
        const TeamMemberCalendar(
          memberId: 'm_song',
          displayName: '宋杰',
          role: '开发',
          energy: EnergyTier.medium,
          permission: TeamSharePermission.freeBusy,
          busy: [
            ScheduleEntry(
              id: 'song_1',
              title: '深度工作',
              tag: 'Core',
              height: 120.0,
              color: Colors.teal,
              time: TimeOfDay(hour: 9, minute: 0),
            ),
          ],
        ),
        const TeamMemberCalendar(
          memberId: 'm_yang',
          displayName: '杨帆',
          role: '开发',
          energy: EnergyTier.low,
          permission: TeamSharePermission.freeBusy,
          busy: [
            ScheduleEntry(
              id: 'yang_1',
              title: '接口对齐',
              tag: 'Meeting',
              height: 80.0,
              color: Colors.blue,
              time: TimeOfDay(hour: 15, minute: 0),
            ),
          ],
        ),
      ]);
  }

  Future<void> _save() async {
    final obj = {
      'version': _schemaVersion,
      'savedAt': DateTime.now().toIso8601String(),
      'schedule': _schedule.map((e) => e.toJson()).toList(),
      'microTasks': _microTasks.map((t) => t.toJson()).toList(),
      'taskEvents': _events.map((e) => e.toJson()).toList(),
      'teamCalendars': _teamCalendars.map((c) => c.toJson()).toList(),
      'schedulingTuning': _tuning.toJson(),
      'emotionCheckIns': _emotion.map((e) => e.toJson()).toList(),
      'goals': _goals.map((g) => g.toJson()).toList(),
      'favoriteDeviceId': _favoriteDeviceId,
      'themeMode': _themeMode,
      'locale': _locale,
    };

    final jsonText = const JsonEncoder.withIndent('  ').convert(obj);
    await _persistence.write(jsonText);
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
      status: '心流',
      description: '仅本地模拟，不采集生理数据。',
      batteryPercent: 85,
    );
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Future<EmotionState> getEmotionState() async {
    await _ensureLoaded();
    final now = DateTime.now();
    final today = _emotion.where((e) => _sameDay(e.at, now)).toList()
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
  Future<void> addEmotionCheckIn(EmotionCheckIn checkIn) async {
    await _ensureLoaded();
    final id = checkIn.id.isEmpty ? _newId('emo_') : checkIn.id;
    // Daily quick check-in: keep at most one record per day (overwrite).
    final day = DateTime(checkIn.at.year, checkIn.at.month, checkIn.at.day);
    _emotion.removeWhere((e) => _sameDay(e.at, day));
    final c = EmotionCheckIn(
      id: id,
      at: checkIn.at,
      state: checkIn.state,
      note: checkIn.note,
    );
    _emotion.add(c);
    await _save();
  }

  @override
  Future<List<EmotionCheckIn>> getEmotionCheckIns(DateTime day) async {
    await _ensureLoaded();
    final d = DateTime(day.year, day.month, day.day);
    final out = _emotion.where((e) => _sameDay(e.at, d)).toList()
      ..sort((a, b) => a.at.compareTo(b.at));
    return out;
  }

  @override
  Future<List<Goal>> getGoals() async {
    await _ensureLoaded();
    final out = List<Goal>.from(_goals)
      ..sort((a, b) {
        // Higher priority first, then due sooner.
        final p = b.priority.compareTo(a.priority);
        if (p != 0) return p;
        return a.due.compareTo(b.due);
      });
    return out;
  }

  @override
  Future<void> upsertGoal(Goal goal) async {
    await _ensureLoaded();
    final id = goal.id.isEmpty ? _newId('goal_') : goal.id;
    final g = Goal(
      id: id,
      title: goal.title,
      due: goal.due,
      priority: goal.priority.clamp(1, 5).toInt(),
      tasks: goal.tasks,
    );
    final idx = _goals.indexWhere((x) => x.id == id);
    if (idx == -1) {
      _goals.add(g);
    } else {
      _goals[idx] = g;
    }
    await _save();
  }

  @override
  Future<void> deleteGoal(String goalId) async {
    await _ensureLoaded();
    _goals.removeWhere((g) => g.id == goalId);
    await _save();
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
  Future<void> addScheduleEntry(ScheduleEntry entry) async {
    await _ensureLoaded();
    final withId = (entry.id == null || entry.id!.isEmpty)
        ? entry.copyWith(id: _newId('sch_'))
        : entry;
    // Upsert by id to support external sync/import flows.
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
  }

  @override
  Future<void> removeScheduleEntry(ScheduleEntry entry) async {
    await _ensureLoaded();
    if (entry.id != null && entry.id!.isNotEmpty) {
      _schedule.removeWhere((e) => e.id == entry.id);
    } else {
      _schedule.removeWhere(
        (e) => e.title == entry.title && e.time == entry.time,
      );
    }
    await _save();
  }

  @override
  Future<List<MicroTask>> getMicroTasks() async {
    await _ensureLoaded();
    return _microTasks.map((t) => t.clone()).toList();
  }

  @override
  Future<void> addMicroTask(MicroTask task) async {
    await _ensureLoaded();
    final t = task.clone();
    t.id ??= _newId('mt_');
    _microTasks.add(t);
    await _save();
  }

  @override
  Future<void> removeMicroTask(MicroTask task) async {
    await _ensureLoaded();
    if (task.id != null && task.id!.isNotEmpty) {
      _microTasks.removeWhere((t) => t.id == task.id);
    } else {
      _microTasks.removeWhere(
        (t) => t.title == task.title && t.tag == task.tag,
      );
    }
    await _save();
  }

  @override
  Future<void> updateMicroTask(MicroTask task) async {
    await _ensureLoaded();
    if (task.id == null || task.id!.isEmpty) {
      await addMicroTask(task);
      return;
    }

    final idx = _microTasks.indexWhere((t) => t.id == task.id);
    if (idx == -1) {
      await addMicroTask(task);
      return;
    }

    _microTasks[idx] = task.clone();
    await _save();
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
    return const UserProfile(displayName: '时序智配用户', status: '本地存储');
  }

  @override
  Future<void> setFavoriteDevice(String deviceId) async {
    await _ensureLoaded();
    _favoriteDeviceId = deviceId;
    await _save();
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
  Future<void> setThemeMode(String themeMode) async {
    await _ensureLoaded();
    _themeMode = themeMode;
    await _save();
  }

  @override
  Future<String> getLocale() async {
    await _ensureLoaded();
    return _locale;
  }

  @override
  Future<void> setLocale(String locale) async {
    await _ensureLoaded();
    _locale = locale;
    await _save();
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

  void _markGoalTaskDoneFromScheduleCompletion(String scheduleTaskId) {
    if (scheduleTaskId.isEmpty) return;

    // Prefer explicit linkage from ScheduleEntry.
    final schIdx = _schedule.indexWhere((e) => e.id == scheduleTaskId);
    if (schIdx != -1) {
      final e = _schedule[schIdx];
      final gid = e.goalId;
      final tid = e.goalTaskId;
      if (gid != null && gid.isNotEmpty && tid != null && tid.isNotEmpty) {
        final gIdx = _goals.indexWhere((g) => g.id == gid);
        if (gIdx == -1) return;
        final g = _goals[gIdx];
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
        _goals[gIdx] = Goal(
          id: g.id,
          title: g.title,
          due: g.due,
          priority: g.priority,
          tasks: tasks,
        );
        return;
      }
    }

    // Fallback: older goal schedule entries encoded ids as `goal_<goalId>_<goalTaskId>`.
    for (var gIdx = 0; gIdx < _goals.length; gIdx++) {
      final g = _goals[gIdx];
      var changed = false;
      final tasks = g.tasks
          .map((t) {
            final expected = 'goal_${g.id}_${t.id}';
            if (scheduleTaskId != expected) return t;
            if (t.done) return t;
            changed = true;
            return t.copyWith(done: true);
          })
          .toList(growable: false);
      if (!changed) continue;
      _goals[gIdx] = Goal(
        id: g.id,
        title: g.title,
        due: g.due,
        priority: g.priority,
        tasks: tasks,
      );
      return;
    }
  }

  @override
  Future<void> logTaskEvent(TaskEvent event) async {
    await _ensureLoaded();
    _events.add(event);
    if (event.type == TaskEventType.complete) {
      _markGoalTaskDoneFromScheduleCompletion(event.taskId);
    }
    await _save();
  }

  @override
  Future<List<TaskEvent>> getTaskEvents(DateTime from, DateTime to) async {
    await _ensureLoaded();
    return _events
        .where((e) => !e.at.isBefore(from) && e.at.isBefore(to))
        .toList(growable: false);
  }

  @override
  Future<ReviewReport> getWeeklyReport(DateTime weekStart) async {
    await _ensureLoaded();

    final report = ReviewRules.weeklyReport(
      weekStart: weekStart,
      events: _events,
      currentTuning: _tuning,
    );

    _tuning = report.tuning;
    await _save();

    return report;
  }

  @override
  Future<SchedulingTuning> getSchedulingTuning() async {
    await _ensureLoaded();
    return _tuning;
  }

  @override
  Future<void> setSchedulingTuning(SchedulingTuning tuning) async {
    await _ensureLoaded();
    _tuning = tuning;
    await _save();
  }

  @override
  Future<List<TeamMemberCalendar>> getTeamCalendars(DateTime day) async {
    await _ensureLoaded();
    return _teamCalendars
        .map(
          (c) => TeamMemberCalendar(
            memberId: c.memberId,
            displayName: c.displayName,
            role: c.role,
            energy: c.energy,
            permission: c.permission,
            busy: List<ScheduleEntry>.from(c.busy),
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<void> updateTeamSharePermission(
    String memberId,
    TeamSharePermission permission,
  ) async {
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
  }

  @override
  Future<void> bookTeamMeeting(DateTime day, TeamMeetingRequest request) async {
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

    // Write to local user's schedule.
    _schedule.add(entry);

    // Simulate shared meeting by adding it to each participant's busy list.
    for (var i = 0; i < _teamCalendars.length; i++) {
      final c = _teamCalendars[i];
      if (!request.participantIds.contains(c.memberId)) continue;

      final updatedBusy = List<ScheduleEntry>.from(c.busy)..add(entry);
      _teamCalendars[i] = TeamMemberCalendar(
        memberId: c.memberId,
        displayName: c.displayName,
        role: c.role,
        energy: c.energy,
        permission: c.permission,
        busy: updatedBusy,
      );
    }

    await _save();
  }
}
