import 'dart:async';
import 'dart:math';

import '../models/models.dart';
import 'data_service.dart';

/// In-memory mock implementation of [DataService].
class MockDataService implements DataService {
  MockDataService._();

  static final MockDataService instance = MockDataService._();

  final _rand = Random();
  final List<ScheduleEntry> _schedule = [];
  final List<MicroTask> _microTasks = [];
  final List<TaskEvent> _events = [];
  final List<TeamMemberCalendar> _team = [];
  final List<EmotionCheckIn> _emotion = [];
  final List<Goal> _goals = [];
  String? _favoriteDeviceId;
  SchedulingTuning _tuning = const SchedulingTuning();

  String _newId(String prefix) {
    final ts = DateTime.now().microsecondsSinceEpoch;
    final r = _rand.nextInt(1 << 32);
    return '$prefix$ts-$r';
  }

  Future<void> _delay([int ms = 20]) =>
      Future.delayed(Duration(milliseconds: ms));

  @override
  Future<EnergyStatus> getEnergyStatus() async {
    await _delay();
    return const EnergyStatus(
      status: '心流',
      description: '模拟数据',
      batteryPercent: 85,
    );
  }

  @override
  Future<EmotionState> getEmotionState() async {
    await _delay();
    if (_emotion.isEmpty) return EmotionState.stable;
    final all = List<EmotionCheckIn>.from(_emotion)
      ..sort((a, b) => a.at.compareTo(b.at));
    return all.last.state;
  }

  @override
  Future<void> addEmotionCheckIn(EmotionCheckIn checkIn) async {
    await _delay();
    final id = checkIn.id.isEmpty ? _newId('emo_') : checkIn.id;
    bool sameDay(DateTime a, DateTime b) =>
        a.year == b.year && a.month == b.month && a.day == b.day;
    final day = DateTime(checkIn.at.year, checkIn.at.month, checkIn.at.day);
    _emotion.removeWhere((e) => sameDay(e.at, day));
    _emotion.add(
      EmotionCheckIn(
        id: id,
        at: checkIn.at,
        state: checkIn.state,
        note: checkIn.note,
      ),
    );
  }

  @override
  Future<List<EmotionCheckIn>> getEmotionCheckIns(DateTime day) async {
    await _delay();
    bool sameDay(DateTime a, DateTime b) =>
        a.year == b.year && a.month == b.month && a.day == b.day;
    final d = DateTime(day.year, day.month, day.day);
    final out = _emotion.where((e) => sameDay(e.at, d)).toList()
      ..sort((a, b) => a.at.compareTo(b.at));
    return out;
  }

  @override
  Future<List<Goal>> getGoals() async {
    await _delay();
    return List<Goal>.from(_goals);
  }

  @override
  Future<void> upsertGoal(Goal goal) async {
    await _delay();
    final id = goal.id.isEmpty ? _newId('goal_') : goal.id;
    final g = Goal(
      id: id,
      title: goal.title,
      due: goal.due,
      priority: goal.priority,
      tasks: goal.tasks,
    );
    final idx = _goals.indexWhere((x) => x.id == id);
    if (idx == -1) {
      _goals.add(g);
    } else {
      _goals[idx] = g;
    }
  }

  @override
  Future<void> deleteGoal(String goalId) async {
    await _delay();
    _goals.removeWhere((g) => g.id == goalId);
  }

  @override
  Future<Task> getCurrentTask() async {
    await _delay();
    return const Task(
      title: '模拟任务',
      description: '模拟数据',
      remainingMinutes: 10,
      progress: 0.5,
    );
  }

  @override
  Future<List<Task>> getNextTasks() async {
    await _delay();
    return const [];
  }

  @override
  Future<List<ScheduleEntry>> getScheduleEntries() async {
    await _delay();
    return List<ScheduleEntry>.from(_schedule);
  }

  @override
  Future<void> addScheduleEntry(ScheduleEntry entry) async {
    await _delay();
    final withId = (entry.id == null || entry.id!.isEmpty)
        ? entry.copyWith(id: _newId('sch_'))
        : entry;
    _schedule.add(withId);
  }

  @override
  Future<void> removeScheduleEntry(ScheduleEntry entry) async {
    await _delay();
    _schedule.removeWhere(
      (e) =>
          (entry.id != null && e.id == entry.id) ||
          (e.title == entry.title && e.time == entry.time),
    );
  }

  @override
  Future<List<MicroTask>> getMicroTasks() async {
    await _delay();
    return _microTasks.map((t) => t.clone()).toList();
  }

  @override
  Future<void> addMicroTask(MicroTask task) async {
    await _delay();
    final t = task.clone();
    t.id ??= _newId('mt_');
    _microTasks.add(t);
  }

  @override
  Future<void> removeMicroTask(MicroTask task) async {
    await _delay();
    _microTasks.removeWhere(
      (t) =>
          (task.id != null && t.id == task.id) ||
          (t.title == task.title && t.tag == task.tag),
    );
  }

  @override
  Future<void> updateMicroTask(MicroTask task) async {
    await _delay();
  }

  @override
  Future<List<TeamMember>> getTeamMembers() async {
    await _delay();
    return const [];
  }

  @override
  Future<UserProfile> getUserProfile() async {
    await _delay();
    return const UserProfile(displayName: '模拟用户', status: '模拟数据');
  }

  @override
  Future<void> logTaskEvent(TaskEvent event) async {
    await _delay();
    _events.add(event);
  }

  @override
  Future<List<TaskEvent>> getTaskEvents(DateTime from, DateTime to) async {
    await _delay();
    return _events
        .where((e) => !e.at.isBefore(from) && e.at.isBefore(to))
        .toList();
  }

  @override
  Future<ReviewReport> getWeeklyReport(DateTime weekStart) async {
    await _delay();
    return ReviewReport(
      weekStart: weekStart,
      weekEnd: weekStart.add(const Duration(days: 7)),
      startedCount: 0,
      completedCount: 0,
      completionRate: 0,
      plannedMinutesTotal: 0,
      actualMinutesTotal: 0,
      actualDurationBuckets: const {
        '<=15': 0,
        '16-30': 0,
        '31-60': 0,
        '61-120': 0,
        '121+': 0,
      },
      delayAttribution: const {
        'underestimated': 0,
        'interruption': 0,
        'context_switch': 0,
        'other': 0,
      },
      suggestions: const [],
      tuning: _tuning,
    );
  }

  @override
  Future<String?> getFavoriteDevice() async {
    await _delay();
    return _favoriteDeviceId;
  }

  @override
  Future<void> setFavoriteDevice(String deviceId) async {
    await _delay();
    _favoriteDeviceId = deviceId;
  }

  @override
  Future<SchedulingTuning> getSchedulingTuning() async {
    await _delay();
    return _tuning;
  }

  @override
  Future<void> setSchedulingTuning(SchedulingTuning tuning) async {
    await _delay();
    _tuning = tuning;
  }

  @override
  Future<List<TeamMemberCalendar>> getTeamCalendars(DateTime day) async {
    await _delay();
    return _team;
  }

  @override
  Future<void> updateTeamSharePermission(
    String memberId,
    TeamSharePermission permission,
  ) async {
    await _delay();
    final idx = _team.indexWhere((c) => c.memberId == memberId);
    if (idx == -1) return;
    final current = _team[idx];
    _team[idx] = TeamMemberCalendar(
      memberId: current.memberId,
      displayName: current.displayName,
      role: current.role,
      energy: current.energy,
      permission: permission,
      busy: List<ScheduleEntry>.from(current.busy),
    );
  }

  @override
  Future<void> bookTeamMeeting(DateTime day, TeamMeetingRequest request) async {
    await _delay();
    // Mock implementation - do nothing
  }
}
