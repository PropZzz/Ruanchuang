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
  LocalDataService._();
  static final LocalDataService instance = LocalDataService._();

  static const int _schemaVersion = 4;

  final LocalPersistence _persistence = createLocalPersistence();

  bool _loaded = false;

  final List<ScheduleEntry> _schedule = [];
  final List<MicroTask> _microTasks = [];
  final List<TaskEvent> _events = [];
  final List<TeamMemberCalendar> _teamCalendars = [];
  final List<EmotionCheckIn> _emotion = [];
  final List<Goal> _goals = [];
  String? _favoriteDeviceId;

  SchedulingTuning _tuning = const SchedulingTuning();

  String _newId(String prefix) {
    final ts = DateTime.now().microsecondsSinceEpoch;
    return '$prefix$ts';
  }

  Future<void> _ensureLoaded() async {
    if (_loaded) return;

    final raw = await _persistence.read();
    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          final scheduleJson = decoded['schedule'];
          final microJson = decoded['microTasks'];
          final eventsJson = decoded['taskEvents'];
          final teamJson = decoded['teamCalendars'];
          final tuningJson = decoded['schedulingTuning'];
          final emotionJson = decoded['emotionCheckIns'];
          final goalsJson = decoded['goals'];
          final favoriteDeviceIdJson = decoded['favoriteDeviceId'];

          if (scheduleJson is List) {
            _schedule
              ..clear()
              ..addAll(scheduleJson
                  .whereType<Map>()
                  .map((m) => ScheduleEntry.fromJson(
                        Map<String, Object?>.from(m),
                      )));
          }

          if (microJson is List) {
            _microTasks
              ..clear()
              ..addAll(microJson
                  .whereType<Map>()
                  .map((m) => MicroTask.fromJson(
                        Map<String, Object?>.from(m),
                      )));
          }

          if (eventsJson is List) {
            _events
              ..clear()
              ..addAll(eventsJson
                  .whereType<Map>()
                  .map((m) => TaskEvent.fromJson(
                        Map<String, Object?>.from(m),
                      )));
          }

          if (teamJson is List) {
            _teamCalendars
              ..clear()
              ..addAll(teamJson
                  .whereType<Map>()
                  .map((m) => TeamMemberCalendar.fromJson(
                        Map<String, Object?>.from(m),
                      )));
          }

          if (tuningJson is Map) {
            _tuning = SchedulingTuning.fromJson(
              Map<String, Object?>.from(tuningJson),
            );
          }

          if (emotionJson is List) {
            _emotion
              ..clear()
              ..addAll(emotionJson
                  .whereType<Map>()
                  .map((m) => EmotionCheckIn.fromJson(
                        Map<String, Object?>.from(m),
                      )));
          }

          if (goalsJson is List) {
            _goals
              ..clear()
              ..addAll(goalsJson
                  .whereType<Map>()
                  .map((m) => Goal.fromJson(
                        Map<String, Object?>.from(m),
                      )));
          }
          if (favoriteDeviceIdJson is String) {
            _favoriteDeviceId = favoriteDeviceIdJson;
          }
        }
      } catch (_) {
        // Ignore corrupted storage and fall back to seed.
      }
    }

    // Migration strategy:
    // - Missing ids: generate stable ids.
    // - Missing fields: handled by model defaults in fromJson.
    for (var i = 0; i < _schedule.length; i++) {
      final e = _schedule[i];
      if (e.id == null || e.id!.isEmpty) {
        _schedule[i] = e.copyWith(id: _newId('sch_'));
      }
    }

    for (final t in _microTasks) {
      if (t.id == null || t.id!.isEmpty) {
        t.id = _newId('mt_');
      }
    }

    for (var i = 0; i < _emotion.length; i++) {
      final e = _emotion[i];
      if (e.id.isEmpty) {
        _emotion[i] = EmotionCheckIn(
          id: _newId('emo_'),
          at: e.at,
          state: e.state,
          note: e.note,
        );
      }
    }

    // Daily quick check-in migration: keep only the latest record per day.
    if (_emotion.length > 1) {
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
        ..addAll(byDay.values.toList()
          ..sort((a, b) => a.at.compareTo(b.at)));
    }

    for (var i = 0; i < _goals.length; i++) {
      final g = _goals[i];
      if (g.id.isEmpty) {
        _goals[i] = Goal(
          id: _newId('goal_'),
          title: g.title,
          due: g.due,
          priority: g.priority,
          tasks: g.tasks,
        );
      }
    }

    if (_schedule.isEmpty && _microTasks.isEmpty) {
      _seed();
    }

    if (_teamCalendars.isEmpty) {
      _seedTeam();
    }

    _loaded = true;
    await _save();
  }

  void _seed() {
    _schedule
      ..clear()
      ..addAll([
        ScheduleEntry(
          id: _newId('sch_'),
          title: 'Deep work: architecture',
          tag: 'Deep Work',
          height: 120,
          color: Colors.teal,
          time: const TimeOfDay(hour: 9, minute: 0),
        ),
        ScheduleEntry(
          id: _newId('sch_'),
          title: 'Email triage (micro)',
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
          title: 'Reply to HR email',
          tag: 'Micro Task',
          minutes: 5,
          requirement: 'Laptop',
        ),
      ]);
  }

  void _seedTeam() {
    _teamCalendars
      ..clear()
      ..addAll([
        const TeamMemberCalendar(
          memberId: 'm_li',
          displayName: 'Li',
          role: 'PM',
          energy: EnergyTier.high,
          permission: TeamSharePermission.details,
          busy: [
            ScheduleEntry(
              id: 'li_1',
              title: 'Product sync',
              tag: 'Meeting',
              height: 80.0,
              color: Colors.blue,
              time: TimeOfDay(hour: 14, minute: 0),
            ),
          ],
        ),
        const TeamMemberCalendar(
          memberId: 'm_song',
          displayName: 'Song',
          role: 'Dev',
          energy: EnergyTier.medium,
          permission: TeamSharePermission.freeBusy,
          busy: [
            ScheduleEntry(
              id: 'song_1',
              title: 'Deep work',
              tag: 'Core',
              height: 120.0,
              color: Colors.teal,
              time: TimeOfDay(hour: 9, minute: 0),
            ),
          ],
        ),
        const TeamMemberCalendar(
          memberId: 'm_yang',
          displayName: 'Yang',
          role: 'Dev',
          energy: EnergyTier.low,
          permission: TeamSharePermission.freeBusy,
          busy: [
            ScheduleEntry(
              id: 'yang_1',
              title: 'API alignment',
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
      status: 'Flow',
      description: 'Local-only mock. No biometrics collected.',
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
      priority: goal.priority.clamp(1, 5),
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
      title: 'Build scheduling MVP',
      description: 'Local-first scheduling with extensible data layer.',
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
      _schedule.removeWhere((e) => e.title == entry.title && e.time == entry.time);
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
      _microTasks.removeWhere((t) => t.title == task.title && t.tag == task.tag);
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
    // Legacy API not used by TeamPage anymore.
    return const [];
  }

  @override
  Future<UserProfile> getUserProfile() async {
    await _ensureLoaded();
    return const UserProfile(
      displayName: 'BattleMan User',
      status: 'Local storage',
    );
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
        .map((c) => TeamMemberCalendar(
              memberId: c.memberId,
              displayName: c.displayName,
              role: c.role,
              energy: c.energy,
              permission: c.permission,
              busy: List<ScheduleEntry>.from(c.busy),
            ))
        .toList(growable: false);
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
