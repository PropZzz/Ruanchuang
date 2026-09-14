import 'package:flutter/material.dart';

import '../../models/models.dart';

/// Canonical JSON boundary for scheduling requests and plans.
///
/// ScheduleEntry.toJson remains the persistence/CRUD shape and intentionally
/// contains height. This adapter is the only place where the scheduler's
/// durationMinutes shape is produced or consumed.
class SchedulingContract {
  static const schemaVersion = '1';

  static const _taskKeys = {
    'id',
    'title',
    'durationMinutes',
    'priority',
    'due',
    'load',
    'tag',
    'goalId',
    'goalTaskId',
    'hardDeadline',
    'earliestStart',
    'dependsOn',
    'splittable',
    'minimumChunkMinutes',
  };
  static const _requestKeys = {
    'schemaVersion',
    'day',
    'tasks',
    'windows',
    'energy',
    'tuning',
    'fixed',
  };
  static const _entryKeys = {
    'id',
    'day',
    'title',
    'tag',
    'load',
    'goalId',
    'goalTaskId',
    'durationMinutes',
    'time',
    'source',
    'explanationCodes',
  };
  static const _issueKeys = {
    'code',
    'message',
    'taskId',
    'blockedBy',
    'explanationCodes',
  };

  static Map<String, Object?> taskToJson(PlanTask task) {
    _checkRange('durationMinutes', task.durationMinutes, 1, 1440);
    _checkRange('priority', task.priority, 1, 5);
    if (!task.splittable && task.minimumChunkMinutes != null) {
      throw ArgumentError('minimumChunkMinutes requires splittable=true');
    }
    if (task.minimumChunkMinutes != null &&
        task.minimumChunkMinutes! > task.durationMinutes) {
      throw ArgumentError('minimumChunkMinutes cannot exceed durationMinutes');
    }
    return <String, Object?>{
      'id': _requiredText('id', task.id),
      'title': _requiredText('title', task.title),
      'durationMinutes': task.durationMinutes,
      'priority': task.priority,
      'due': _canonicalDateTime(task.due),
      'load': task.load.name,
      'tag': task.tag,
      'goalId': task.goalId,
      'goalTaskId': task.goalTaskId,
      'hardDeadline': task.hardDeadline,
      'earliestStart': _canonicalDateTime(task.earliestStart),
      'dependsOn': _uniqueIds(task.dependsOn),
      'splittable': task.splittable,
      'minimumChunkMinutes': task.minimumChunkMinutes,
    };
  }

  static SchedulingRequest requestFromJson(Map<String, Object?> json) {
    _rejectUnknown(json, _requestKeys, 'request');
    if ((json['schemaVersion'] ?? schemaVersion) != schemaVersion) {
      throw const FormatException('schemaVersion must be "1"');
    }
    final day = _parseDateOnly(json['day'], 'day');
    if (day == null) throw const FormatException('day is required');
    final tasks = _mapList(
      json['tasks'],
      'tasks',
    ).map(taskFromJson).toList(growable: false);
    final windows = _mapList(
      json['windows'],
      'windows',
    ).map(_windowFromJson).toList(growable: false);
    final fixed = _mapList(
      json['fixed'] ?? const [],
      'fixed',
    ).map(fixedEntryFromJson).toList(growable: false);
    return SchedulingRequest(
      schemaVersion: schemaVersion,
      day: day,
      tasks: tasks,
      windows: windows,
      energy: _energy(json['energy'] ?? 'medium'),
      tuning: _tuning(json['tuning'] ?? const {}),
      fixed: fixed,
    );
  }

  static PlanTask taskFromJson(Map<String, Object?> json) {
    _rejectUnknown(json, _taskKeys, 'task');
    final id = _requiredText('id', json['id']);
    final title = _requiredText('title', json['title']);
    final duration = _intValue(json['durationMinutes'], 'durationMinutes');
    final priority = _intValue(json['priority'], 'priority');
    _checkRange('durationMinutes', duration, 1, 1440);
    _checkRange('priority', priority, 1, 5);
    final load = _load(json['load']);
    final tag = _requiredText('tag', json['tag']);
    final dependsOn = _stringList(json['dependsOn'] ?? const [], 'dependsOn');
    if (dependsOn.toSet().length != dependsOn.length) {
      throw const FormatException('dependsOn must contain unique ids');
    }
    final splittable = json['splittable'] ?? false;
    if (splittable is! bool) {
      throw const FormatException('splittable must be boolean');
    }
    final minimumChunk = json['minimumChunkMinutes'] == null
        ? null
        : _intValue(json['minimumChunkMinutes'], 'minimumChunkMinutes');
    if (!splittable && minimumChunk != null) {
      throw const FormatException(
        'minimumChunkMinutes requires splittable=true',
      );
    }
    if (minimumChunk != null) {
      _checkRange('minimumChunkMinutes', minimumChunk, 1, duration);
    }
    return PlanTask(
      id: id,
      title: title,
      durationMinutes: duration,
      priority: priority,
      due: _parseDateTime(json['due'], 'due'),
      load: load,
      tag: tag,
      goalId: _nullableText(json['goalId'], 'goalId'),
      goalTaskId: _nullableText(json['goalTaskId'], 'goalTaskId'),
      earliestStart: _parseDateTime(json['earliestStart'], 'earliestStart'),
      hardDeadline: _boolValue(json['hardDeadline'] ?? false, 'hardDeadline'),
      dependsOn: dependsOn,
      splittable: splittable,
      minimumChunkMinutes: minimumChunk,
    );
  }

  static Map<String, Object?> fixedEntryToJson(ScheduleEntry entry) {
    final result = _entryToJson(entry, source: 'fixed');
    return result;
  }

  static ScheduleEntry fixedEntryFromJson(Map<String, Object?> json) {
    final entry = _entryFromJson(json);
    if (entry.source != 'fixed') {
      throw const FormatException('fixed entry source must be fixed');
    }
    return entry;
  }

  static Map<String, Object?> planToJson(SchedulingPlan plan) {
    if (plan.schemaVersion != schemaVersion) {
      throw ArgumentError('unsupported schemaVersion: ${plan.schemaVersion}');
    }
    return {
      'schemaVersion': schemaVersion,
      'entries': plan.entries.map((entry) => _entryToJson(entry)).toList(),
      'issues': plan.issues.map(issueToJson).toList(),
      'risk': (plan.risk ?? SchedulingRisk.fromIssues(plan.issues)).toJson(),
    };
  }

  static SchedulingPlan planFromJson(Map<String, Object?> json) {
    _rejectUnknown(json, {
      'schemaVersion',
      'entries',
      'issues',
      'risk',
    }, 'response');
    if (json['schemaVersion'] != schemaVersion) {
      throw const FormatException('schemaVersion must be "1"');
    }
    final entries = _mapList(
      json['entries'],
      'entries',
    ).map(_entryFromJson).toList(growable: false);
    final issues = _mapList(
      json['issues'],
      'issues',
    ).map(issueFromJson).toList(growable: false);
    return SchedulingPlan(
      schemaVersion: schemaVersion,
      entries: entries,
      issues: issues,
      risk: json['risk'] is Map
          ? SchedulingRisk.fromJson(
              Map<String, Object?>.from(json['risk'] as Map),
            )
          : null,
    );
  }

  static Map<String, Object?> issueToJson(SchedulingIssue issue) {
    _issueCode(issue.code);
    final result = <String, Object?>{
      'code': issue.code,
      'message': _requiredText('message', issue.message),
      'taskId': issue.taskId,
      'explanationCodes': _explanationCodes(issue.explanationCodes),
    };
    if (issue.blockedBy != null)
      result['blockedBy'] = _uniqueIds(issue.blockedBy!);
    return result;
  }

  static SchedulingIssue issueFromJson(Map<String, Object?> json) {
    _rejectUnknown(json, _issueKeys, 'issue');
    final code = _requiredText('code', json['code']);
    _issueCode(code);
    return SchedulingIssue(
      code: code,
      message: _requiredText('message', json['message']),
      taskId: _nullableText(json['taskId'], 'taskId'),
      blockedBy: json['blockedBy'] == null
          ? null
          : _uniqueIds(_stringList(json['blockedBy'], 'blockedBy')),
      explanationCodes: _explanationCodes(
        _stringList(json['explanationCodes'] ?? const [], 'explanationCodes'),
      ),
    );
  }

  static Map<String, Object?> _entryToJson(
    ScheduleEntry entry, {
    String? source,
  }) {
    final resolvedSource = source ?? entry.source;
    if (!{'fixed', 'planned', 'recovery'}.contains(resolvedSource)) {
      throw ArgumentError('invalid entry source: $resolvedSource');
    }
    final result = <String, Object?>{
      'id': _requiredText('id', entry.id),
      'title': _requiredText('title', entry.title),
      'tag': _requiredText('tag', entry.tag),
      'load': entry.load?.name,
      'durationMinutes': _durationFromHeight(entry.height),
      'time': {'hour': entry.time.hour, 'minute': entry.time.minute},
      'source': resolvedSource,
      'explanationCodes': _explanationCodes(entry.explanationCodes),
    };
    if (entry.day != null) result['day'] = _dateOnly(entry.day!);
    if (entry.goalId != null) result['goalId'] = entry.goalId;
    if (entry.goalTaskId != null) result['goalTaskId'] = entry.goalTaskId;
    return result;
  }

  static ScheduleEntry _entryFromJson(Map<String, Object?> json) {
    _rejectUnknown(json, _entryKeys, 'entry');
    final id = _requiredText('id', json['id']);
    final title = _requiredText('title', json['title']);
    final tag = _requiredText('tag', json['tag']);
    final duration = _intValue(json['durationMinutes'], 'durationMinutes');
    _checkRange('durationMinutes', duration, 1, 1440);
    final time = _time(json['time']);
    final source = _requiredText('source', json['source']);
    if (!{'fixed', 'planned', 'recovery'}.contains(source)) {
      throw FormatException('invalid entry source: $source');
    }
    return ScheduleEntry(
      id: id,
      day: _parseDateOnly(json['day'], 'day'),
      title: title,
      tag: tag,
      load: json['load'] == null ? null : _load(json['load']),
      goalId: _nullableText(json['goalId'], 'goalId'),
      goalTaskId: _nullableText(json['goalTaskId'], 'goalTaskId'),
      height: _heightFromDuration(duration),
      color: Colors.teal,
      time: time,
      source: source,
      explanationCodes: _explanationCodes(
        _stringList(json['explanationCodes'] ?? const [], 'explanationCodes'),
      ),
    );
  }

  static List<Map<String, Object?>> _mapList(Object? value, String field) {
    if (value is! List) throw FormatException('$field must be an array');
    return value
        .map((item) {
          if (item is! Map)
            throw FormatException('$field items must be objects');
          return Map<String, Object?>.from(item);
        })
        .toList(growable: false);
  }

  static List<String> _stringList(Object? value, String field) {
    if (value is! List || value.any((item) => item is! String)) {
      throw FormatException('$field must be an array of strings');
    }
    return value.cast<String>().toList(growable: false);
  }

  static List<String> _uniqueIds(List<String> ids) {
    if (ids.any((id) => id.trim().isEmpty) ||
        ids.toSet().length != ids.length) {
      throw const FormatException('ids must be unique and non-empty');
    }
    return List<String>.unmodifiable(ids);
  }

  static List<String> _explanationCodes(List<String> codes) {
    const allowed = {
      'deadline_proximity',
      'priority',
      'energy_fit',
      'kept_baseline',
      'fixed_conflict',
    };
    if (codes.any((code) => !allowed.contains(code)) ||
        codes.toSet().length != codes.length) {
      throw const FormatException('invalid explanation code');
    }
    return List<String>.unmodifiable(codes);
  }

  static CognitiveLoad _load(Object? value) {
    if (value is! String) throw const FormatException('load is required');
    return CognitiveLoad.values.firstWhere(
      (load) => load.name == value,
      orElse: () => throw FormatException('invalid load: $value'),
    );
  }

  static void _issueCode(String code) {
    const allowed = {'no_slot', 'miss_due', 'overdue', 'dependency_blocked'};
    if (!allowed.contains(code))
      throw FormatException('invalid issue code: $code');
  }

  static EnergyTier _energy(Object? value) {
    if (value is! String)
      throw const FormatException('energy must be a string');
    return EnergyTier.values.firstWhere(
      (energy) => energy.name == value,
      orElse: () => throw FormatException('invalid energy: $value'),
    );
  }

  static TimeWindow _windowFromJson(Map<String, Object?> json) {
    _rejectUnknown(json, {'start', 'end'}, 'window');
    final start = _time(json['start']);
    final end = _time(json['end']);
    final startMinute = start.hour * 60 + start.minute;
    final endMinute = end.hour * 60 + end.minute;
    if (endMinute <= startMinute) {
      throw const FormatException('window end must be after start');
    }
    return TimeWindow(start: start, end: end);
  }

  static SchedulingTuning _tuning(Object? value) {
    if (value is! Map) throw const FormatException('tuning must be an object');
    final json = Map<String, Object?>.from(value);
    _rejectUnknown(json, {
      'defaultDurationMultiplier',
      'tagDurationMultiplier',
      'highLoadPenaltyWhenLowEnergy',
    }, 'tuning');
    double number(Object? raw, String field) {
      if (raw is! num || raw <= 0) {
        throw FormatException('$field must be greater than zero');
      }
      return raw.toDouble();
    }

    final rawTags = json['tagDurationMultiplier'] ?? const {};
    if (rawTags is! Map) {
      throw const FormatException('tagDurationMultiplier must be an object');
    }
    final tags = <String, double>{};
    for (final entry in rawTags.entries) {
      if (entry.key is! String)
        throw const FormatException('tag must be a string');
      tags[entry.key as String] = number(entry.value, 'tagDurationMultiplier');
    }
    return SchedulingTuning(
      defaultDurationMultiplier: number(
        json['defaultDurationMultiplier'] ?? 1.0,
        'defaultDurationMultiplier',
      ),
      tagDurationMultiplier: tags,
      highLoadPenaltyWhenLowEnergy: number(
        json['highLoadPenaltyWhenLowEnergy'] ?? 1.0,
        'highLoadPenaltyWhenLowEnergy',
      ),
    );
  }

  static int _intValue(Object? value, String field) {
    if (value is! int) throw FormatException('$field must be an integer');
    return value;
  }

  static bool _boolValue(Object? value, String field) {
    if (value is! bool) throw FormatException('$field must be boolean');
    return value;
  }

  static String _requiredText(String field, Object? value) {
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('$field must be a non-empty string');
    }
    return value;
  }

  static String? _nullableText(Object? value, String field) {
    if (value == null) return null;
    return _requiredText(field, value);
  }

  static void _checkRange(String field, int value, int min, int max) {
    if (value < min || value > max) {
      throw FormatException('$field must be between $min and $max');
    }
  }

  static String? _canonicalDateTime(DateTime? value) {
    if (value == null) return null;
    final text = value.toUtc().toIso8601String();
    return text.replaceFirst(RegExp(r'\.\d+(?=Z$)'), '');
  }

  static DateTime? _parseDateTime(Object? value, String field) {
    if (value == null) return null;
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('$field must be an ISO date-time');
    }
    final parsed = DateTime.tryParse(value);
    if (parsed == null || !value.contains('T')) {
      throw FormatException('$field must be an ISO date-time');
    }
    if (parsed.second != 0 ||
        parsed.millisecond != 0 ||
        parsed.microsecond != 0) {
      throw FormatException('$field must use minute precision');
    }
    return parsed.toUtc();
  }

  static String _dateOnly(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  static DateTime? _parseDateOnly(Object? value, String field) {
    if (value == null) return null;
    if (value is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
      throw FormatException('$field must be YYYY-MM-DD');
    }
    final parsed = DateTime.tryParse(value);
    if (parsed == null || _dateOnly(parsed) != value) {
      throw FormatException('$field must be a valid date');
    }
    return DateTime(parsed.year, parsed.month, parsed.day);
  }

  static TimeOfDay _time(Object? value) {
    if (value is! Map) throw const FormatException('time must be an object');
    final hour = _intValue(value['hour'], 'time.hour');
    final minute = _intValue(value['minute'], 'time.minute');
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
      throw const FormatException('time is outside valid clock range');
    }
    return TimeOfDay(hour: hour, minute: minute);
  }

  static int _durationFromHeight(double height) =>
      (height / 80.0 * 60.0).round().clamp(1, 1440).toInt();

  static double _heightFromDuration(int minutes) => minutes / 60.0 * 80.0;

  static void _rejectUnknown(
    Map<String, Object?> json,
    Set<String> allowed,
    String objectName,
  ) {
    final unknown = json.keys.where((key) => !allowed.contains(key));
    if (unknown.isNotEmpty) {
      throw FormatException(
        '$objectName contains unknown field: ${unknown.first}',
      );
    }
  }
}
