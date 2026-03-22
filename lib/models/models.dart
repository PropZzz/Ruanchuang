import 'package:flutter/material.dart';

String _two(int v) => v.toString().padLeft(2, '0');

TimeOfDay _timeFromJson(Object? json) {
  if (json is Map) {
    final hour = (json['hour'] as num?)?.toInt() ?? 0;
    final minute = (json['minute'] as num?)?.toInt() ?? 0;
    return TimeOfDay(hour: hour, minute: minute);
  }
  if (json is String) {
    final parts = json.split(':');
    if (parts.length == 2) {
      final hour = int.tryParse(parts[0]) ?? 0;
      final minute = int.tryParse(parts[1]) ?? 0;
      return TimeOfDay(hour: hour, minute: minute);
    }
  }
  return const TimeOfDay(hour: 0, minute: 0);
}

Map<String, Object> _timeToJson(TimeOfDay time) {
  return {'hour': time.hour, 'minute': time.minute};
}

DateTime? _dateFromJson(Object? json) {
  if (json is String && json.trim().isNotEmpty) {
    // Accept both `YYYY-MM-DD` and ISO8601 forms.
    final raw = json.trim();
    final datePart = raw.split('T').first;
    final parsed = DateTime.tryParse(datePart);
    if (parsed == null) return null;
    return DateTime(parsed.year, parsed.month, parsed.day);
  }
  return null;
}

String? _dateToJson(DateTime? date) {
  if (date == null) return null;
  return '${date.year.toString().padLeft(4, '0')}-${_two(date.month)}-${_two(date.day)}';
}

/// Repeating rule for schedule entries.
///
/// P0 supports: none/daily/weekly/monthly + optional until date.
enum RepeatFrequency { none, daily, weekly, monthly }

/// Schedule block model.
class ScheduleEntry {
  /// Optional stable id. Older data may not have it.
  final String? id;

  /// Optional anchor date for this schedule entry.
  ///
  /// - When null, the entry is considered "floating" and can be shown on any day
  ///   (legacy behavior).
  /// - When set, the entry occurs on [day] and may repeat based on [repeat].
  final DateTime? day;

  final String title;
  final String tag;
  final CognitiveLoad? load;

  /// Optional linkage back to goal planning.
  ///
  /// When set, completing this schedule entry can automatically mark the
  /// corresponding goal task as done to close the "goal -> task -> schedule"
  /// loop.
  final String? goalId;
  final String? goalTaskId;

  /// Height in calendar UI (maps to duration; 80.0 ~= 60 minutes).
  final double height;

  final Color color;
  final TimeOfDay time;

  /// Reminder offset in minutes before the start time.
  final int reminderMinutesBefore;

  /// Repeat rule for this schedule entry.
  final RepeatFrequency repeat;

  /// Optional inclusive end date for the repeating rule.
  ///
  /// When set, occurrences after this date will not be scheduled.
  final DateTime? repeatUntil;

  const ScheduleEntry({
    this.id,
    this.day,
    required this.title,
    required this.tag,
    this.load,
    this.goalId,
    this.goalTaskId,
    required this.height,
    required this.color,
    required this.time,
    this.reminderMinutesBefore = 10,
    this.repeat = RepeatFrequency.none,
    this.repeatUntil,
  });

  ScheduleEntry copyWith({
    String? id,
    DateTime? day,
    String? title,
    String? tag,
    CognitiveLoad? load,
    String? goalId,
    String? goalTaskId,
    double? height,
    Color? color,
    TimeOfDay? time,
    int? reminderMinutesBefore,
    RepeatFrequency? repeat,
    DateTime? repeatUntil,
  }) {
    return ScheduleEntry(
      id: id ?? this.id,
      day: day ?? this.day,
      title: title ?? this.title,
      tag: tag ?? this.tag,
      load: load ?? this.load,
      goalId: goalId ?? this.goalId,
      goalTaskId: goalTaskId ?? this.goalTaskId,
      height: height ?? this.height,
      color: color ?? this.color,
      time: time ?? this.time,
      reminderMinutesBefore:
          reminderMinutesBefore ?? this.reminderMinutesBefore,
      repeat: repeat ?? this.repeat,
      repeatUntil: repeatUntil ?? this.repeatUntil,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'day': _dateToJson(day),
      'title': title,
      'tag': tag,
      'load': load?.name,
      'goalId': goalId,
      'goalTaskId': goalTaskId,
      'height': height,
      'color': color.toARGB32(),
      'time': _timeToJson(time),
      'reminderMinutesBefore': reminderMinutesBefore,
      'repeat': repeat.name,
      'repeatUntil': _dateToJson(repeatUntil),
    };
  }

  static ScheduleEntry fromJson(Map<String, Object?> json) {
    final loadStr = json['load'] as String?;
    final load = (loadStr == null)
        ? null
        : CognitiveLoad.values.firstWhere(
            (e) => e.name == loadStr,
            orElse: () => CognitiveLoad.medium,
          );

    final repeatStr = json['repeat'] as String?;
    final repeat = (repeatStr == null)
        ? RepeatFrequency.none
        : RepeatFrequency.values.firstWhere(
            (e) => e.name == repeatStr,
            orElse: () => RepeatFrequency.none,
          );

    final repeatUntil = repeat == RepeatFrequency.none
        ? null
        : _dateFromJson(json['repeatUntil']);

    return ScheduleEntry(
      id: json['id'] as String?,
      day: _dateFromJson(json['day']),
      title: (json['title'] as String?) ?? '',
      tag: (json['tag'] as String?) ?? '',
      load: load,
      goalId: json['goalId'] as String?,
      goalTaskId: json['goalTaskId'] as String?,
      height: ((json['height'] as num?)?.toDouble()) ?? 60.0,
      color: Color(
        ((json['color'] as num?)?.toInt()) ?? Colors.teal.toARGB32(),
      ),
      time: _timeFromJson(json['time']),
      reminderMinutesBefore:
          (json['reminderMinutesBefore'] as num?)?.toInt() ?? 10,
      repeat: repeat,
      repeatUntil: repeatUntil,
    );
  }
}

/// Energy status snapshot.
class EnergyStatus {
  final String status;
  final String description;
  final int batteryPercent;

  const EnergyStatus({
    required this.status,
    required this.description,
    required this.batteryPercent,
  });

  Map<String, Object?> toJson() => {
    'status': status,
    'description': description,
    'batteryPercent': batteryPercent,
  };

  static EnergyStatus fromJson(Map<String, Object?> json) => EnergyStatus(
    status: (json['status'] as String?) ?? '',
    description: (json['description'] as String?) ?? '',
    batteryPercent: (json['batteryPercent'] as num?)?.toInt() ?? 0,
  );
}

/// Focus task (legacy).
class Task {
  final String title;
  final String description;
  final int remainingMinutes;
  final double progress;

  const Task({
    required this.title,
    required this.description,
    required this.remainingMinutes,
    required this.progress,
  });

  Map<String, Object?> toJson() => {
    'title': title,
    'description': description,
    'remainingMinutes': remainingMinutes,
    'progress': progress,
  };

  static Task fromJson(Map<String, Object?> json) => Task(
    title: (json['title'] as String?) ?? '',
    description: (json['description'] as String?) ?? '',
    remainingMinutes: (json['remainingMinutes'] as num?)?.toInt() ?? 0,
    progress: ((json['progress'] as num?)?.toDouble()) ?? 0.0,
  );
}

/// Micro task model.
class MicroTask {
  /// Optional stable id.
  String? id;

  String title;
  String tag;
  int minutes;
  int priority; // 1..5
  String? requirement;
  bool done;

  MicroTask({
    this.id,
    required this.title,
    required this.tag,
    required this.minutes,
    int priority = 3,
    this.requirement,
    this.done = false,
  }) : priority = priority.clamp(1, 5).toInt();

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'title': title,
      'tag': tag,
      'minutes': minutes,
      'priority': priority,
      'requirement': requirement,
      'done': done,
    };
  }

  static MicroTask fromJson(Map<String, Object?> json) {
    return MicroTask(
      id: json['id'] as String?,
      title: (json['title'] as String?) ?? '',
      tag: (json['tag'] as String?) ?? '',
      minutes: (json['minutes'] as num?)?.toInt() ?? 0,
      priority: (json['priority'] as num?)?.toInt() ?? 3,
      requirement: json['requirement'] as String?,
      done: (json['done'] as bool?) ?? false,
    );
  }

  MicroTask clone() => MicroTask.fromJson(toJson());
}

/// Team task model (UI-local).
class TeamTask {
  String name;
  String role;
  String task;
  double progress;
  bool isHighEnergy;
  DateTime? due;

  TeamTask({
    required this.name,
    required this.role,
    required this.task,
    this.progress = 0.0,
    this.isHighEnergy = false,
    this.due,
  });

  Map<String, Object?> toJson() => {
    'name': name,
    'role': role,
    'task': task,
    'progress': progress,
    'isHighEnergy': isHighEnergy,
    'due': due?.toIso8601String(),
  };

  static TeamTask fromJson(Map<String, Object?> json) => TeamTask(
    name: (json['name'] as String?) ?? '',
    role: (json['role'] as String?) ?? '',
    task: (json['task'] as String?) ?? '',
    progress: ((json['progress'] as num?)?.toDouble()) ?? 0.0,
    isHighEnergy: (json['isHighEnergy'] as bool?) ?? false,
    due: (json['due'] is String)
        ? DateTime.tryParse(json['due'] as String)
        : null,
  );
}

/// Team member model (API-like response).
class TeamMember {
  final String name;
  final String task;
  final double progress;
  final bool isHighEnergy;
  final List<TimeRange> busyTimes;

  const TeamMember({
    required this.name,
    required this.task,
    required this.progress,
    required this.isHighEnergy,
    this.busyTimes = const [],
  });

  Map<String, Object?> toJson() => {
    'name': name,
    'task': task,
    'progress': progress,
    'isHighEnergy': isHighEnergy,
    'busyTimes': busyTimes.map((t) => t.toJson()).toList(),
  };

  static TeamMember fromJson(Map<String, Object?> json) => TeamMember(
    name: (json['name'] as String?) ?? '',
    task: (json['task'] as String?) ?? '',
    progress: ((json['progress'] as num?)?.toDouble()) ?? 0.0,
    isHighEnergy: (json['isHighEnergy'] as bool?) ?? false,
    busyTimes:
        ((json['busyTimes'] as List?)
            ?.map((t) => TimeRange.fromJson(t as Map<String, Object?>))
            .toList()) ??
        [],
  );
}

/// User profile.
class UserProfile {
  final String displayName;
  final String status;

  const UserProfile({required this.displayName, required this.status});

  Map<String, Object?> toJson() => {
    'displayName': displayName,
    'status': status,
  };

  static UserProfile fromJson(Map<String, Object?> json) => UserProfile(
    displayName: (json['displayName'] as String?) ?? '',
    status: (json['status'] as String?) ?? '',
  );
}

// -----------------------------------------------------------------------------
// Emotion sensing (P0: user self check-in + lightweight heuristics)
// -----------------------------------------------------------------------------

/// User self-reported emotion state.
///
/// This matches the PRD labels: efficient / stable / tired / irritable.
enum EmotionState { efficient, stable, tired, irritable }

class EmotionCheckIn {
  final String id;
  final DateTime at;
  final EmotionState state;
  final String? note;

  const EmotionCheckIn({
    required this.id,
    required this.at,
    required this.state,
    this.note,
  });

  Map<String, Object?> toJson() => {
    'id': id,
    'at': at.toIso8601String(),
    'state': state.name,
    'note': note,
  };

  static EmotionCheckIn fromJson(Map<String, Object?> json) {
    final atStr = (json['at'] as String?) ?? '';
    final at = DateTime.tryParse(atStr) ?? DateTime.now();
    final stateStr = (json['state'] as String?) ?? EmotionState.stable.name;
    final state = EmotionState.values.firstWhere(
      (e) => e.name == stateStr,
      orElse: () => EmotionState.stable,
    );
    return EmotionCheckIn(
      id: (json['id'] as String?) ?? '',
      at: at,
      state: state,
      note: json['note'] as String?,
    );
  }
}

/// Human-readable time string, useful for storage or logs.
String timeToString(TimeOfDay time) =>
    '${_two(time.hour)}:${_two(time.minute)}';
// -----------------------------------------------------------------------------
// Scheduling / Replanning (P0 heuristics)
// -----------------------------------------------------------------------------

/// 5-tier energy level input for scheduling.
///
/// This is intentionally simple and stable so we can later swap the scheduling
/// implementation (e.g. Transformer+LSTM) without changing UI/service contracts.
enum EnergyTier { veryLow, low, medium, high, veryHigh }

/// Cognitive load label for a task.
enum CognitiveLoad { low, medium, high }

// -----------------------------------------------------------------------------
// Goals (Goal -> Tasks -> Schedule) - P0 local planning
// -----------------------------------------------------------------------------

class GoalTask {
  final String id;
  final String title;
  final int durationMinutes;
  final CognitiveLoad load;
  final String tag;
  final bool done;
  final List<String> dependsOn;

  const GoalTask({
    required this.id,
    required this.title,
    required this.durationMinutes,
    required this.load,
    required this.tag,
    this.done = false,
    this.dependsOn = const [],
  });

  GoalTask copyWith({
    String? id,
    String? title,
    int? durationMinutes,
    CognitiveLoad? load,
    String? tag,
    bool? done,
    List<String>? dependsOn,
  }) {
    return GoalTask(
      id: id ?? this.id,
      title: title ?? this.title,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      load: load ?? this.load,
      tag: tag ?? this.tag,
      done: done ?? this.done,
      dependsOn: dependsOn ?? this.dependsOn,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'durationMinutes': durationMinutes,
    'load': load.name,
    'tag': tag,
    'done': done,
    'dependsOn': dependsOn,
  };

  static GoalTask fromJson(Map<String, Object?> json) {
    final loadStr = (json['load'] as String?) ?? CognitiveLoad.medium.name;
    final load = CognitiveLoad.values.firstWhere(
      (e) => e.name == loadStr,
      orElse: () => CognitiveLoad.medium,
    );

    final depsRaw = json['dependsOn'];
    final deps = (depsRaw is List)
        ? depsRaw.whereType<String>().where((s) => s.trim().isNotEmpty).toList()
        : const <String>[];

    return GoalTask(
      id: (json['id'] as String?) ?? '',
      title: (json['title'] as String?) ?? '',
      durationMinutes: (json['durationMinutes'] as num?)?.toInt() ?? 30,
      load: load,
      tag: (json['tag'] as String?) ?? 'Goal',
      done: (json['done'] as bool?) ?? false,
      dependsOn: deps,
    );
  }
}

class Goal {
  final String id;
  final String title;
  final DateTime due;
  final int priority; // 1..5
  final List<GoalTask> tasks;

  const Goal({
    required this.id,
    required this.title,
    required this.due,
    required this.priority,
    required this.tasks,
  });

  double get progress {
    if (tasks.isEmpty) return 0.0;
    final doneCount = tasks.where((t) => t.done).length;
    return doneCount / tasks.length;
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'due': due.toIso8601String(),
    'priority': priority,
    'tasks': tasks.map((t) => t.toJson()).toList(),
  };

  static Goal fromJson(Map<String, Object?> json) {
    final dueStr = (json['due'] as String?) ?? '';
    final due =
        DateTime.tryParse(dueStr) ??
        DateTime.now().add(const Duration(days: 7));

    final tasksRaw = json['tasks'];
    final tasks = (tasksRaw is List)
        ? tasksRaw
              .whereType<Map>()
              .map((m) => GoalTask.fromJson(Map<String, Object?>.from(m)))
              .toList()
        : <GoalTask>[];

    return Goal(
      id: (json['id'] as String?) ?? '',
      title: (json['title'] as String?) ?? '',
      due: due,
      priority: (json['priority'] as num?)?.toInt() ?? 3,
      tasks: tasks,
    );
  }
}

/// A scheduling task used by the replanning engine.
///
/// Note: This is separate from legacy [Task] (UI focus card).
class PlanTask {
  final String id;
  final String title;
  final int durationMinutes;

  /// 1..5 (larger means more important)
  final int priority;

  /// Optional deadline. If provided, engine tries to schedule before this time.
  final DateTime? due;

  final CognitiveLoad load;

  /// Free-form tag for UI grouping.
  final String tag;

  const PlanTask({
    required this.id,
    required this.title,
    required this.durationMinutes,
    required this.priority,
    required this.load,
    required this.tag,
    this.due,
  });

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'durationMinutes': durationMinutes,
    'priority': priority,
    'due': due?.toIso8601String(),
    'load': load.name,
    'tag': tag,
  };

  static PlanTask fromJson(Map<String, Object?> json) {
    final loadStr = (json['load'] as String?) ?? CognitiveLoad.medium.name;
    final load = CognitiveLoad.values.firstWhere(
      (e) => e.name == loadStr,
      orElse: () => CognitiveLoad.medium,
    );

    final dueRaw = json['due'];
    DateTime? due;
    if (dueRaw is String && dueRaw.isNotEmpty) {
      due = DateTime.tryParse(dueRaw);
    }

    return PlanTask(
      id: (json['id'] as String?) ?? '',
      title: (json['title'] as String?) ?? '',
      durationMinutes: (json['durationMinutes'] as num?)?.toInt() ?? 0,
      priority: (json['priority'] as num?)?.toInt() ?? 1,
      load: load,
      tag: (json['tag'] as String?) ?? '',
      due: due,
    );
  }
}

/// An available time window for scheduling on a specific day.
class TimeWindow {
  final TimeOfDay start;
  final TimeOfDay end;

  const TimeWindow({required this.start, required this.end});

  Map<String, Object?> toJson() => {
    'start': _timeToJson(start),
    'end': _timeToJson(end),
  };

  static TimeWindow fromJson(Map<String, Object?> json) => TimeWindow(
    start: _timeFromJson(json['start']),
    end: _timeFromJson(json['end']),
  );
}

class SchedulingRequest {
  final DateTime day;
  final List<PlanTask> tasks;
  final List<TimeWindow> windows;
  final EnergyTier energy;
  final SchedulingTuning tuning;

  /// Optional fixed blocks (hard constraints), scheduled as-is.
  final List<ScheduleEntry> fixed;

  const SchedulingRequest({
    required this.day,
    required this.tasks,
    required this.windows,
    required this.energy,
    this.tuning = const SchedulingTuning(),
    this.fixed = const [],
  });

  Map<String, Object?> toJson() => {
    'day': day.toIso8601String(),
    'tasks': tasks.map((t) => t.toJson()).toList(),
    'windows': windows.map((w) => w.toJson()).toList(),
    'energy': energy.name,
    'tuning': tuning.toJson(),
    'fixed': fixed.map((e) => e.toJson()).toList(),
  };

  static SchedulingRequest fromJson(Map<String, Object?> json) {
    final dayStr = (json['day'] as String?) ?? DateTime.now().toIso8601String();
    final day = DateTime.tryParse(dayStr) ?? DateTime.now();

    final energyStr = (json['energy'] as String?) ?? EnergyTier.medium.name;
    final energy = EnergyTier.values.firstWhere(
      (e) => e.name == energyStr,
      orElse: () => EnergyTier.medium,
    );

    final tasksRaw = json['tasks'];
    final windowsRaw = json['windows'];
    final fixedRaw = json['fixed'];
    final tuningRaw = json['tuning'];

    final tasks = (tasksRaw is List)
        ? tasksRaw
              .whereType<Map>()
              .map((m) => PlanTask.fromJson(Map<String, Object?>.from(m)))
              .toList()
        : <PlanTask>[];

    final windows = (windowsRaw is List)
        ? windowsRaw
              .whereType<Map>()
              .map((m) => TimeWindow.fromJson(Map<String, Object?>.from(m)))
              .toList()
        : <TimeWindow>[];

    final fixed = (fixedRaw is List)
        ? fixedRaw
              .whereType<Map>()
              .map((m) => ScheduleEntry.fromJson(Map<String, Object?>.from(m)))
              .toList()
        : <ScheduleEntry>[];

    final tuning = (tuningRaw is Map)
        ? SchedulingTuning.fromJson(Map<String, Object?>.from(tuningRaw))
        : const SchedulingTuning();

    return SchedulingRequest(
      day: day,
      tasks: tasks,
      windows: windows,
      energy: energy,
      tuning: tuning,
      fixed: fixed,
    );
  }
}

class SchedulingIssue {
  final String code;
  final String message;
  final String? taskId;

  const SchedulingIssue({
    required this.code,
    required this.message,
    this.taskId,
  });

  Map<String, Object?> toJson() => {
    'code': code,
    'message': message,
    'taskId': taskId,
  };

  static SchedulingIssue fromJson(Map<String, Object?> json) => SchedulingIssue(
    code: (json['code'] as String?) ?? '',
    message: (json['message'] as String?) ?? '',
    taskId: json['taskId'] as String?,
  );
}

class SchedulingPlan {
  final List<ScheduleEntry> entries;
  final List<SchedulingIssue> issues;

  const SchedulingPlan({required this.entries, this.issues = const []});

  Map<String, Object?> toJson() => {
    'entries': entries.map((e) => e.toJson()).toList(),
    'issues': issues.map((i) => i.toJson()).toList(),
  };

  static SchedulingPlan fromJson(Map<String, Object?> json) {
    final entriesRaw = json['entries'];
    final issuesRaw = json['issues'];

    final entries = (entriesRaw is List)
        ? entriesRaw
              .whereType<Map>()
              .map((m) => ScheduleEntry.fromJson(Map<String, Object?>.from(m)))
              .toList()
        : <ScheduleEntry>[];

    final issues = (issuesRaw is List)
        ? issuesRaw
              .whereType<Map>()
              .map(
                (m) => SchedulingIssue.fromJson(Map<String, Object?>.from(m)),
              )
              .toList()
        : <SchedulingIssue>[];

    return SchedulingPlan(entries: entries, issues: issues);
  }
}

// -----------------------------------------------------------------------------
// Review Loop (Execution -> Analysis -> Optimization)
// -----------------------------------------------------------------------------

enum TaskEventType { start, complete, postpone, interrupt }

class TaskEvent {
  final String id;
  final String taskId;
  final String title;
  final String tag;
  final CognitiveLoad? load;

  final DateTime at;
  final TaskEventType type;

  // Planning context
  final int? plannedMinutes;
  final EnergyTier? energy;

  // Outcome data
  final int? actualMinutes;
  final int? interruptions;
  final String? reason;

  const TaskEvent({
    required this.id,
    required this.taskId,
    required this.title,
    required this.tag,
    this.load,
    required this.at,
    required this.type,
    this.plannedMinutes,
    this.energy,
    this.actualMinutes,
    this.interruptions,
    this.reason,
  });

  Map<String, Object?> toJson() => {
    'id': id,
    'taskId': taskId,
    'title': title,
    'tag': tag,
    'load': load?.name,
    'at': at.toIso8601String(),
    'type': type.name,
    'plannedMinutes': plannedMinutes,
    'energy': energy?.name,
    'actualMinutes': actualMinutes,
    'interruptions': interruptions,
    'reason': reason,
  };

  static TaskEvent fromJson(Map<String, Object?> json) {
    final typeStr = (json['type'] as String?) ?? TaskEventType.start.name;
    final type = TaskEventType.values.firstWhere(
      (e) => e.name == typeStr,
      orElse: () => TaskEventType.start,
    );

    final loadStr = json['load'] as String?;
    final load = (loadStr == null)
        ? null
        : CognitiveLoad.values.firstWhere(
            (e) => e.name == loadStr,
            orElse: () => CognitiveLoad.medium,
          );

    final energyStr = json['energy'] as String?;
    final energy = (energyStr == null)
        ? null
        : EnergyTier.values.firstWhere(
            (e) => e.name == energyStr,
            orElse: () => EnergyTier.medium,
          );

    final atStr = (json['at'] as String?) ?? DateTime.now().toIso8601String();
    final at = DateTime.tryParse(atStr) ?? DateTime.now();

    return TaskEvent(
      id: (json['id'] as String?) ?? '',
      taskId: (json['taskId'] as String?) ?? '',
      title: (json['title'] as String?) ?? '',
      tag: (json['tag'] as String?) ?? '',
      load: load,
      at: at,
      type: type,
      plannedMinutes: (json['plannedMinutes'] as num?)?.toInt(),
      energy: energy,
      actualMinutes: (json['actualMinutes'] as num?)?.toInt(),
      interruptions: (json['interruptions'] as num?)?.toInt(),
      reason: json['reason'] as String?,
    );
  }
}

/// Parameters that tune scheduling behavior based on review insights.
class SchedulingTuning {
  final double defaultDurationMultiplier;
  final Map<String, double> tagDurationMultiplier;
  final double highLoadPenaltyWhenLowEnergy;

  const SchedulingTuning({
    this.defaultDurationMultiplier = 1.0,
    this.tagDurationMultiplier = const {},
    this.highLoadPenaltyWhenLowEnergy = 1.0,
  });

  double durationMultiplierForTag(String tag) {
    final v = tagDurationMultiplier[tag];
    return (v == null) ? defaultDurationMultiplier : v;
  }

  Map<String, Object?> toJson() => {
    'defaultDurationMultiplier': defaultDurationMultiplier,
    'tagDurationMultiplier': tagDurationMultiplier,
    'highLoadPenaltyWhenLowEnergy': highLoadPenaltyWhenLowEnergy,
  };

  static SchedulingTuning fromJson(Map<String, Object?> json) {
    final raw = json['tagDurationMultiplier'];
    final map = <String, double>{};
    if (raw is Map) {
      for (final e in raw.entries) {
        final k = e.key;
        final v = e.value;
        if (k is String && v is num) {
          map[k] = v.toDouble();
        }
      }
    }

    return SchedulingTuning(
      defaultDurationMultiplier:
          (json['defaultDurationMultiplier'] as num?)?.toDouble() ?? 1.0,
      tagDurationMultiplier: map,
      highLoadPenaltyWhenLowEnergy:
          (json['highLoadPenaltyWhenLowEnergy'] as num?)?.toDouble() ?? 1.0,
    );
  }
}

class ReviewReport {
  final DateTime weekStart;
  final DateTime weekEnd;

  final int startedCount;
  final int completedCount;
  final double completionRate;

  final int plannedMinutesTotal;
  final int actualMinutesTotal;

  /// Buckets: <=15, 16-30, 31-60, 61-120, 121+
  final Map<String, int> actualDurationBuckets;

  /// Rule-based attribution counts.
  final Map<String, int> delayAttribution;

  final List<String> suggestions;

  /// The tuning that should be applied for next planning.
  final SchedulingTuning tuning;

  const ReviewReport({
    required this.weekStart,
    required this.weekEnd,
    required this.startedCount,
    required this.completedCount,
    required this.completionRate,
    required this.plannedMinutesTotal,
    required this.actualMinutesTotal,
    required this.actualDurationBuckets,
    required this.delayAttribution,
    required this.suggestions,
    required this.tuning,
  });

  Map<String, Object?> toJson() => {
    'weekStart': weekStart.toIso8601String(),
    'weekEnd': weekEnd.toIso8601String(),
    'startedCount': startedCount,
    'completedCount': completedCount,
    'completionRate': completionRate,
    'plannedMinutesTotal': plannedMinutesTotal,
    'actualMinutesTotal': actualMinutesTotal,
    'actualDurationBuckets': actualDurationBuckets,
    'delayAttribution': delayAttribution,
    'suggestions': suggestions,
    'tuning': tuning.toJson(),
  };

  static ReviewReport fromJson(Map<String, Object?> json) {
    final ws =
        DateTime.tryParse((json['weekStart'] as String?) ?? '') ??
        DateTime.now();
    final we =
        DateTime.tryParse((json['weekEnd'] as String?) ?? '') ?? DateTime.now();

    Map<String, int> mapInt(Object? raw) {
      final out = <String, int>{};
      if (raw is Map) {
        for (final e in raw.entries) {
          if (e.key is String && e.value is num) {
            out[e.key as String] = (e.value as num).toInt();
          }
        }
      }
      return out;
    }

    final suggRaw = json['suggestions'];
    final suggestions = (suggRaw is List)
        ? suggRaw.whereType<String>().toList()
        : <String>[];

    final tuningRaw = json['tuning'];
    final tuning = (tuningRaw is Map)
        ? SchedulingTuning.fromJson(Map<String, Object?>.from(tuningRaw))
        : const SchedulingTuning();

    return ReviewReport(
      weekStart: ws,
      weekEnd: we,
      startedCount: (json['startedCount'] as num?)?.toInt() ?? 0,
      completedCount: (json['completedCount'] as num?)?.toInt() ?? 0,
      completionRate: (json['completionRate'] as num?)?.toDouble() ?? 0.0,
      plannedMinutesTotal: (json['plannedMinutesTotal'] as num?)?.toInt() ?? 0,
      actualMinutesTotal: (json['actualMinutesTotal'] as num?)?.toInt() ?? 0,
      actualDurationBuckets: mapInt(json['actualDurationBuckets']),
      delayAttribution: mapInt(json['delayAttribution']),
      suggestions: suggestions,
      tuning: tuning,
    );
  }
}

// -----------------------------------------------------------------------------
// Team Collaboration (Golden Window)
// -----------------------------------------------------------------------------

enum TeamSharePermission { none, freeBusy, details }

class TeamMemberCalendar {
  final String memberId;
  final String displayName;
  final String role;

  final EnergyTier energy;
  final TeamSharePermission permission;

  /// Busy blocks for the day (local simulation).
  final List<ScheduleEntry> busy;

  const TeamMemberCalendar({
    required this.memberId,
    required this.displayName,
    required this.role,
    required this.energy,
    required this.permission,
    required this.busy,
  });

  Map<String, Object?> toJson() => {
    'memberId': memberId,
    'displayName': displayName,
    'role': role,
    'energy': energy.name,
    'permission': permission.name,
    'busy': busy.map((e) => e.toJson()).toList(),
  };

  static TeamMemberCalendar fromJson(Map<String, Object?> json) {
    final energyStr = (json['energy'] as String?) ?? EnergyTier.medium.name;
    final energy = EnergyTier.values.firstWhere(
      (e) => e.name == energyStr,
      orElse: () => EnergyTier.medium,
    );

    final permStr =
        (json['permission'] as String?) ?? TeamSharePermission.freeBusy.name;
    final permission = TeamSharePermission.values.firstWhere(
      (e) => e.name == permStr,
      orElse: () => TeamSharePermission.freeBusy,
    );

    final busyRaw = json['busy'];
    final busy = (busyRaw is List)
        ? busyRaw
              .whereType<Map>()
              .map((m) => ScheduleEntry.fromJson(Map<String, Object?>.from(m)))
              .toList()
        : <ScheduleEntry>[];

    return TeamMemberCalendar(
      memberId: (json['memberId'] as String?) ?? '',
      displayName: (json['displayName'] as String?) ?? '',
      role: (json['role'] as String?) ?? '',
      energy: energy,
      permission: permission,
      busy: busy,
    );
  }
}

class GoldenWindow {
  final TimeOfDay start;
  final int minutes;
  final List<String> participantIds;
  final double score;

  const GoldenWindow({
    required this.start,
    required this.minutes,
    required this.participantIds,
    required this.score,
  });
}

class TeamConflict {
  final String memberA;
  final String memberB;
  final TimeOfDay start;
  final TimeOfDay end;

  const TeamConflict({
    required this.memberA,
    required this.memberB,
    required this.start,
    required this.end,
  });
}

class TeamMeetingRequest {
  final String title;
  final TimeOfDay start;
  final int minutes;
  final List<String> participantIds;

  const TeamMeetingRequest({
    required this.title,
    required this.start,
    required this.minutes,
    required this.participantIds,
  });
}

class TimeRange {
  final TimeOfDay start;
  final TimeOfDay end;

  const TimeRange({required this.start, required this.end});

  Map<String, Object?> toJson() => {
    'start': {'hour': start.hour, 'minute': start.minute},
    'end': {'hour': end.hour, 'minute': end.minute},
  };

  static TimeRange fromJson(Map<String, Object?> json) => TimeRange(
    start: TimeOfDay(
      hour: ((json['start'] as Map?)?['hour'] as int?) ?? 0,
      minute: ((json['start'] as Map?)?['minute'] as int?) ?? 0,
    ),
    end: TimeOfDay(
      hour: ((json['end'] as Map?)?['hour'] as int?) ?? 0,
      minute: ((json['end'] as Map?)?['minute'] as int?) ?? 0,
    ),
  );

  int get durationMinutes =>
      (end.hour * 60 + end.minute) - (start.hour * 60 + start.minute);

  bool contains(TimeOfDay time) {
    final timeMinutes = time.hour * 60 + time.minute;
    final startMinutes = start.hour * 60 + start.minute;
    final endMinutes = end.hour * 60 + end.minute;
    return timeMinutes >= startMinutes && timeMinutes <= endMinutes;
  }
}
