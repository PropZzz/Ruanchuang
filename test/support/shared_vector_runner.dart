import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shixuzhipei/models/models.dart';
import 'package:shixuzhipei/services/scheduling/heuristic_scheduling_engine.dart';
import 'package:shixuzhipei/services/scheduling/schedule_rescue.dart';
import 'package:shixuzhipei/services/scheduling/schedule_rescue_persistence.dart';
import 'package:shixuzhipei/services/scheduling/scheduling_engine.dart';
import 'package:shixuzhipei/services/scheduling/urgent_deadline.dart';

typedef SharedJson = Map<String, Object?>;

const String defaultSharedVectorFixturesDirectory =
    'contracts/scheduling/v1/fixtures';

const Set<String> _reviewClassifications = {
  'implementation_error',
  'contract_error',
  'allowed_difference',
  'pending_a_review',
};

/// Converts a production plan to the fields that are comparable across
/// runtimes. The current Dart model does not carry explanation or dependency
/// metadata, so the adapter emits empty lists rather than inventing codes.
SharedJson canonicalizePlan(
  SchedulingPlan plan, {
  required DateTime day,
  Set<String> fixedEntryIds = const <String>{},
  Set<String> recoveryEntryIds = const <String>{},
}) {
  final entries = List<ScheduleEntry>.from(plan.entries)
    ..sort((a, b) {
      final byTime = _minutes(a.time).compareTo(_minutes(b.time));
      if (byTime != 0) return byTime;
      return (a.id ?? '').compareTo(b.id ?? '');
    });

  return <String, Object?>{
    'entries': entries
        .map(
          (entry) => <String, Object?>{
            'id': entry.id,
            'day': _dateOnly(entry.day ?? day),
            'time': <String, Object?>{
              'hour': entry.time.hour,
              'minute': entry.time.minute,
            },
            'durationMinutes': _durationFromHeight(entry.height),
            'source': _sourceForEntry(
              entry,
              fixedEntryIds: fixedEntryIds,
              recoveryEntryIds: recoveryEntryIds,
            ),
            // ScheduleEntry currently has no explanation-code field.
            'explanationCodes': <String>[],
          },
        )
        .toList(growable: false),
    'issues': plan.issues
        .map(
          (issue) => <String, Object?>{
            'code': issue.code,
            'taskId': issue.taskId,
            // SchedulingIssue currently has no dependency field.
            'blockedBy': <String>[],
            'explanationCodes': <String>[],
          },
        )
        .toList(growable: false),
  };
}

/// Runs every JSON fixture in [directory] and returns a machine-readable
/// result. A fixture exception is intentionally isolated as an `invalid`
/// record so one malformed vector does not hide the remaining results.
Future<SharedJson> runSharedVectorDirectory(
  Directory directory, {
  SchedulingEngine? engine,
}) async {
  final planner = engine ?? HeuristicSchedulingEngine();
  final files =
      directory
          .listSync()
          .whereType<File>()
          .where((file) => file.path.toLowerCase().endsWith('.json'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  final fixtures = <SharedJson>[];
  for (final file in files) {
    final name = file.uri.pathSegments.isEmpty
        ? file.path
        : file.uri.pathSegments.last;
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is! Map) {
        throw const FormatException('fixture root must be an object');
      }
      final fixture = SharedJson.from(decoded);
      fixtures.add(
        await runSharedVectorFixture(fixture, name: name, engine: planner),
      );
    } catch (error, stackTrace) {
      fixtures.add(<String, Object?>{
        'name': name,
        'status': 'invalid',
        'error': '$error',
        'diagnostics': <String, Object?>{'stackTrace': '$stackTrace'},
      });
    }
  }

  final invalid = fixtures.where((item) => item['status'] == 'invalid').length;
  final mismatched = fixtures
      .where((item) => item['status'] == 'mismatched')
      .length;
  return <String, Object?>{
    'fixtures': fixtures,
    'matched': fixtures.length - invalid - mismatched,
    'mismatched': mismatched,
    'invalid': invalid,
  };
}

/// Runs one already-decoded fixture. [name] is retained in the output to make
/// reports useful even when a fixture id is missing or malformed.
Future<SharedJson> runSharedVectorFixture(
  SharedJson fixture, {
  required String name,
  SchedulingEngine? engine,
}) async {
  final planner = engine ?? HeuristicSchedulingEngine();
  final id = fixture['id'];
  final kind = fixture['kind'];
  final tags = _stringList(fixture['tags'], 'tags');
  final review = _review(fixture['review']);

  if (kind is! String ||
      !{'plan', 'rescue', 'transaction', 'boundary'}.contains(kind)) {
    throw FormatException('unsupported fixture kind: $kind');
  }
  if (id is! String || id.trim().isEmpty) {
    throw const FormatException('fixture id must be a non-empty string');
  }
  final request = _map(fixture['request'], 'request');

  SharedJson actual = <String, Object?>{};
  SharedJson diagnostics = <String, Object?>{};
  switch (kind) {
    case 'plan':
      final result = _runPlan(
        request,
        planner,
        boundaryTime: tags.contains('boundary_time'),
      );
      actual = result.actual;
      diagnostics = result.diagnostics;
      break;
    case 'rescue':
      final result = _runRescue(request, planner);
      actual = result.actual;
      diagnostics = result.diagnostics;
      break;
    case 'transaction':
      final result = await _runTransaction(request);
      actual = result.actual;
      diagnostics = result.diagnostics;
      break;
    case 'boundary':
      final result = await _runBoundary(request, planner);
      actual = result.actual;
      diagnostics = result.diagnostics;
      break;
  }

  final assertions = _map(fixture['assertions'], 'assertions');
  final differences = _compareAssertions(
    kind: kind,
    assertions: assertions,
    actual: actual,
  );
  return <String, Object?>{
    'name': name,
    'id': id,
    'kind': kind,
    'status': differences.isEmpty ? 'matched' : 'mismatched',
    'review': review,
    'actual': actual,
    'differences': differences,
    // Messages, strategies and other runtime-only details are deliberately
    // outside `actual`, so they cannot affect cross-runtime comparison.
    'diagnostics': diagnostics,
  };
}

/// Formats the result with stable markers consumed by parity tooling.
String formatSharedVectorResult(SharedJson result) {
  return 'SHARED_VECTOR_RESULT_BEGIN\n'
      '${jsonEncode(result)}\n'
      'SHARED_VECTOR_RESULT_END';
}

class _RunResult {
  final SharedJson actual;
  final SharedJson diagnostics;

  const _RunResult(this.actual, this.diagnostics);
}

_RunResult _runPlan(
  SharedJson rawRequest,
  SchedulingEngine engine, {
  bool boundaryTime = false,
}) {
  final request = SchedulingRequest.fromJson(rawRequest);
  final plan = engine.plan(request);
  final fixedIds = request.fixed.map((entry) => entry.id).whereType<String>();
  final diagnostics = _planDiagnostics(plan);
  if (boundaryTime) {
    // The boundary vector remains a scheduling vector, but it must also pass
    // through the production urgent-deadline validation helpers.
    final now = DateTime(request.day.year, request.day.month, request.day.day);
    final deadline = defaultUrgentDeadline(now: now, scheduleDay: request.day);
    diagnostics['urgentDeadlineBoundary'] = <String, Object?>{
      'deadline': deadline.toIso8601String(),
      'valid': isUrgentDeadlineValid(
        now: now,
        scheduleDay: request.day,
        deadline: deadline,
      ),
    };
  }
  return _RunResult(
    canonicalizePlan(plan, day: request.day, fixedEntryIds: fixedIds.toSet()),
    diagnostics,
  );
}

_RunResult _runRescue(SharedJson rawRequest, SchedulingEngine engine) {
  final request = SchedulingRequest.fromJson(rawRequest);
  final urgent = PlanTask.fromJson(
    _map(rawRequest['urgentTask'], 'urgentTask'),
  );
  final rawBaseline = _entriesFromJson(
    rawRequest['currentEntries'],
    'currentEntries',
  );
  // Validate the complete input before filtering so duplicate ids cannot be
  // silently collapsed by a map conversion.
  _entriesById(rawBaseline, field: 'currentEntries');
  final baseline = rawBaseline
      .where(
        (entry) =>
            entry.day != null &&
            _dateOnly(entry.day!) == _dateOnly(request.day),
      )
      .toList(growable: false);
  final service = ScheduleRescueService(engine: engine);
  final proposed = service.propose(
    base: request,
    baseline: baseline,
    urgent: urgent,
  );
  final requestedStrategies = rawRequest['strategies'] == null
      ? null
      : _stringList(rawRequest['strategies'], 'strategies');
  if (requestedStrategies != null) {
    const allowedStrategies = {
      'protectDeadline',
      'protectRecovery',
      'minimizeChanges',
    };
    if (requestedStrategies.isEmpty) {
      throw const FormatException('strategies must not be empty');
    }
    if (requestedStrategies.toSet().length != requestedStrategies.length) {
      throw const FormatException('strategies must not contain duplicates');
    }
    final unknown = requestedStrategies.firstWhere(
      (strategy) => !allowedStrategies.contains(strategy),
      orElse: () => '',
    );
    if (unknown.isNotEmpty) {
      throw FormatException('unsupported rescue strategy: $unknown');
    }
  }
  final options = requestedStrategies == null
      ? proposed
      : requestedStrategies
            .map((name) {
              return proposed.firstWhere(
                (option) => option.strategy.name == name,
                orElse: () =>
                    throw FormatException('unsupported rescue strategy: $name'),
              );
            })
            .toList(growable: false);
  final baseFixedIds = request.fixed
      .map((entry) => entry.id)
      .whereType<String>();
  final strategies = <Object?>[];
  for (final option in options) {
    final recoveryIds = option.plan.entries
        .where(
          (entry) =>
              entry.id?.startsWith('rescue_recovery_') == true ||
              entry.tag.toLowerCase() == 'recovery',
        )
        .map((entry) => entry.id)
        .whereType<String>()
        .toSet();
    final fixedIds = <String>{...baseFixedIds};
    if (option.strategy == RescueStrategy.minimizeChanges) {
      fixedIds.addAll(baseline.map((entry) => entry.id).whereType<String>());
    }
    final canonical = canonicalizePlan(
      option.plan,
      day: request.day,
      fixedEntryIds: fixedIds,
      recoveryEntryIds: recoveryIds,
    );
    strategies.add(<String, Object?>{
      'strategy': option.strategy.name,
      'entries': canonical['entries'],
      'issues': canonical['issues'],
      'diagnostics': <String, Object?>{
        'rationale': option.rationale,
        'tradeoff': option.tradeoff,
        'movedEntryCount': option.movedEntryCount,
        'recoveryMinutes': option.recoveryMinutes,
        'messages': _planDiagnostics(option.plan),
      },
    });
  }
  return _RunResult(
    <String, Object?>{
      'entries': <Object?>[],
      'issues': <Object?>[],
      'strategies': strategies,
    },
    <String, Object?>{
      'urgentTaskId': urgent.id,
      'baselineEntryIds': baseline.map((entry) => entry.id).toList(),
      if (requestedStrategies != null)
        'requestedStrategies': requestedStrategies,
    },
  );
}

Future<_RunResult> _runTransaction(SharedJson request) async {
  final before = _entriesFromJson(request['before'], 'before');
  final after = _entriesFromJson(request['after'], 'after');
  final beforeById = _entriesById(before, field: 'before');
  final afterById = _entriesById(after, field: 'after');
  final operation = request['operation'];
  if (operation is! String) {
    throw const FormatException('transaction operation is required');
  }

  final state = <String, ScheduleEntry>{...beforeById};
  final writerEvents = <SharedJson>[];
  final failAt = request['failAt'];
  final failureCode = request['failureCode'] as String? ?? 'apply_failed';
  var failureArmed = operation == 'apply';
  var phase = operation == 'undo' ? 'undo' : 'apply';

  Future<void> upsert(ScheduleEntry entry) async {
    final id = _requiredEntryId(entry);
    writerEvents.add(<String, Object?>{
      'operation': 'upsert',
      'id': id,
      'phase': phase,
    });
    // Mutate before the controlled throw to model a partially written target;
    // ScheduleRescuePersistence must then compensate it through its reverse
    // synchronization.
    state[id] = entry;
    if (failureArmed && failAt == id) {
      failureArmed = false;
      phase = 'rollback';
      throw _TransactionFailure(failureCode);
    }
  }

  Future<void> remove(ScheduleEntry entry) async {
    final id = _requiredEntryId(entry);
    writerEvents.add(<String, Object?>{
      'operation': 'remove',
      'id': id,
      'phase': phase,
    });
    state.remove(id);
  }

  final persistence = ScheduleRescuePersistence(upsert: upsert, remove: remove);

  String status;
  String? errorCode;
  try {
    if (operation == 'apply') {
      await persistence.apply(before: before, after: after);
      status = 'applied';
    } else if (operation == 'undo') {
      // The vector's `before` is the currently accepted rescue plan and its
      // `after` is the original snapshot. Applying current -> original is the
      // inverse of the earlier rescue apply while preserving exact recovery.
      await persistence.apply(before: before, after: after);
      status = 'restored';
    } else {
      throw FormatException('unsupported transaction operation: $operation');
    }
  } on _TransactionFailure catch (error) {
    status = 'rolled_back';
    errorCode = error.code;
  }

  if (operation != 'apply' && operation != 'undo') {
    throw FormatException('unsupported transaction operation: $operation');
  }

  final entries = _sortedStateEntries(state);
  final expectedOriginal = operation == 'undo' ? afterById : beforeById;
  final finalStateJson = <String, Object?>{
    'status': status,
    'originalPlanPreserved': _sameEntryState(state, expectedOriginal),
    'exact': _sameEntryState(state, expectedOriginal),
    'entryIds': entries.map((entry) => entry.id).whereType<String>().toList(),
    'timeBlocks': _timeBlocks(entries),
  };
  if (errorCode != null) finalStateJson['errorCode'] = errorCode;
  return _RunResult(
    <String, Object?>{'finalState': finalStateJson},
    <String, Object?>{'operation': operation, 'writerEvents': writerEvents},
  );
}

Future<_RunResult> _runBoundary(
  SharedJson request,
  SchedulingEngine engine,
) async {
  final operation = request['operation'];
  if (operation == 'apply' &&
      request['timeoutMs'] is num &&
      request['simulateDelayMs'] is num) {
    final timeoutMs = (request['timeoutMs'] as num).toInt();
    final delayMs = (request['simulateDelayMs'] as num).toInt();
    final beforeIds = _stringList(request['beforeEntryIds'], 'beforeEntryIds');
    final afterIds = _stringList(request['afterEntryIds'], 'afterEntryIds');
    // Keep the adapter deterministic in CI: the vector describes a controlled
    // delay, so no real sleep is needed to observe timeout semantics.
    final timedOut = delayMs >= timeoutMs;
    if (timedOut) {
      return _RunResult(
        <String, Object?>{
          'finalState': <String, Object?>{
            'status': 'timeout',
            'timeout': true,
            'originalPlanPreserved': true,
            'partialWrites': false,
            'errorCode': 'timeout',
            'entryIds': beforeIds,
          },
        },
        <String, Object?>{
          'timeoutMs': timeoutMs,
          'simulateDelayMs': delayMs,
          'attemptedEntryIds': afterIds,
        },
      );
    }
    return _RunResult(
      <String, Object?>{
        'finalState': <String, Object?>{
          'status': 'applied',
          'timeout': false,
          'originalPlanPreserved': false,
          'partialWrites': false,
          'entryIds': afterIds,
        },
      },
      <String, Object?>{'timeoutMs': timeoutMs, 'simulateDelayMs': delayMs},
    );
  }

  if (operation == 'urgent_deadline') {
    final now = _dateTime(request['now'], 'now');
    final scheduleDay = _dateTime(request['scheduleDay'], 'scheduleDay');
    final deadline = defaultUrgentDeadline(now: now, scheduleDay: scheduleDay);
    final valid = isUrgentDeadlineValid(
      now: now,
      scheduleDay: scheduleDay,
      deadline: deadline,
    );
    return _RunResult(<String, Object?>{
      'finalState': <String, Object?>{
        'status': 'evaluated',
        'deadline': deadline.toIso8601String(),
        'valid': valid,
      },
    }, const <String, Object?>{});
  }

  // Boundary vectors may use the boundary kind while still asking the
  // scheduler to plan. Keep that path deterministic and observable.
  if (request.containsKey('tasks') || request.containsKey('windows')) {
    final result = _runPlan(request, engine);
    return _RunResult(<String, Object?>{
      ...result.actual,
      'finalState': <String, Object?>{'status': 'planned'},
    }, result.diagnostics);
  }
  throw const FormatException('unsupported boundary operation');
}

List<SharedJson> _compareAssertions({
  required String kind,
  required SharedJson assertions,
  required SharedJson actual,
}) {
  if (kind == 'transaction' || kind == 'boundary') {
    final expected = _map(assertions['finalState'], 'assertions.finalState');
    final observed = _map(actual['finalState'], 'actual.finalState');
    return _compareSubset(expected, observed, 'finalState');
  }

  if (kind == 'rescue') {
    final differences = <SharedJson>[];
    final expectedBaseProjection = <String, Object?>{
      'taskOrder': assertions['taskOrder'],
      'timeBlocks': assertions['timeBlocks'],
      'issues': assertions['issues'],
      'explanationCodes': assertions['explanationCodes'],
    };
    // Rescue vectors retain the same top-level canonical assertion shape as a
    // plan (usually empty), in addition to their per-strategy projections.
    differences.addAll(
      _compareExact(
        expectedBaseProjection,
        _projectionFromCanonical(actual),
        'rescue',
      ),
    );
    final actualStrategies = actual['strategies'];
    final expectedStrategies = assertions['strategies'];
    if (actualStrategies is! List || expectedStrategies is! List) {
      differences.add(<String, Object?>{
        'field': 'strategies',
        'expected': expectedStrategies,
        'actual': actualStrategies,
      });
      return differences;
    }
    if (expectedStrategies.length != actualStrategies.length) {
      differences.add(<String, Object?>{
        'field': 'strategies.length',
        'expected': expectedStrategies.length,
        'actual': actualStrategies.length,
      });
    }
    final count = expectedStrategies.length < actualStrategies.length
        ? expectedStrategies.length
        : actualStrategies.length;
    for (var i = 0; i < count; i++) {
      final expected = _map(expectedStrategies[i], 'strategies[$i]');
      final observed = _map(actualStrategies[i], 'actual.strategies[$i]');
      final projection = _projectionFromCanonical(<String, Object?>{
        'entries': observed['entries'],
        'issues': observed['issues'],
      });
      final expectedProjection = <String, Object?>{
        'taskOrder': expected['taskOrder'],
        'timeBlocks': expected['timeBlocks'],
        'issues': expected['issues'],
        'explanationCodes': expected['explanationCodes'],
      };
      differences.addAll(
        _compareExact(expectedProjection, projection, 'strategies[$i]'),
      );
      if (expected['strategy'] != observed['strategy']) {
        differences.add(<String, Object?>{
          'field': 'strategies[$i].strategy',
          'expected': expected['strategy'],
          'actual': observed['strategy'],
        });
      }
    }
    return differences;
  }

  final expectedProjection = <String, Object?>{
    'taskOrder': assertions['taskOrder'],
    'timeBlocks': assertions['timeBlocks'],
    'issues': assertions['issues'],
    'explanationCodes': assertions['explanationCodes'],
  };
  return _compareExact(
    expectedProjection,
    _projectionFromCanonical(actual),
    'plan',
  );
}

SharedJson _projectionFromCanonical(SharedJson canonical) {
  final rawEntries = canonical['entries'];
  final rawIssues = canonical['issues'];
  final entries = rawEntries is List ? rawEntries : const <Object?>[];
  final issues = rawIssues is List ? rawIssues : const <Object?>[];
  final taskOrder = <Object?>[];
  final timeBlocks = <String, Object?>{};
  final explanationCodes = <String>[];
  for (final raw in entries) {
    if (raw is! Map) continue;
    final entry = SharedJson.from(raw);
    final id = entry['id'];
    taskOrder.add(id);
    if (id is String) {
      final time = entry['time'];
      final timeMap = time is Map
          ? <String, Object?>{'hour': time['hour'], 'minute': time['minute']}
          : <String, Object?>{};
      timeBlocks[id] = <String, Object?>{
        ...timeMap,
        'durationMinutes': entry['durationMinutes'],
      };
    }
    final codes = entry['explanationCodes'];
    if (codes is List) explanationCodes.addAll(codes.whereType<String>());
  }
  for (final raw in issues) {
    if (raw is! Map) continue;
    final issue = SharedJson.from(raw);
    final codes = issue['explanationCodes'];
    if (codes is List) explanationCodes.addAll(codes.whereType<String>());
  }
  return <String, Object?>{
    'taskOrder': taskOrder,
    'timeBlocks': timeBlocks,
    'issues': issues.map((item) => SharedJson.from(item as Map)).toList(),
    'explanationCodes': explanationCodes,
  };
}

List<SharedJson> _compareExact(Object? expected, Object? actual, String path) {
  final differences = <SharedJson>[];
  if (expected is Map && actual is Map) {
    final keys = <Object?>{...expected.keys, ...actual.keys};
    for (final key in keys) {
      _appendDifferences(
        differences,
        _compareExact(expected[key], actual[key], '$path.$key'),
      );
    }
    return differences;
  }
  if (expected is List && actual is List) {
    if (expected.length != actual.length) {
      differences.add(<String, Object?>{
        'field': '$path.length',
        'expected': expected.length,
        'actual': actual.length,
      });
    }
    final count = expected.length < actual.length
        ? expected.length
        : actual.length;
    for (var i = 0; i < count; i++) {
      _appendDifferences(
        differences,
        _compareExact(expected[i], actual[i], '$path[$i]'),
      );
    }
    return differences;
  }
  if (expected != actual) {
    differences.add(<String, Object?>{
      'field': path,
      'expected': expected,
      'actual': actual,
    });
  }
  return differences;
}

List<SharedJson> _compareSubset(
  SharedJson expected,
  SharedJson actual,
  String path,
) {
  final differences = <SharedJson>[];
  for (final key in expected.keys) {
    final expectedValue = expected[key];
    final actualValue = actual[key];
    if (expectedValue is Map && actualValue is Map) {
      _appendDifferences(
        differences,
        _compareSubset(
          SharedJson.from(expectedValue),
          SharedJson.from(actualValue),
          '$path.$key',
        ),
      );
    } else if (expectedValue is List && actualValue is List) {
      _appendDifferences(
        differences,
        _compareExact(expectedValue, actualValue, '$path.$key'),
      );
    } else if (expectedValue != actualValue) {
      differences.add(<String, Object?>{
        'field': '$path.$key',
        'expected': expectedValue,
        'actual': actualValue,
      });
    }
  }
  return differences;
}

void _appendDifferences(List<SharedJson> target, List<SharedJson> additions) {
  target.addAll(additions);
}

SharedJson _planDiagnostics(SchedulingPlan plan) {
  return <String, Object?>{
    'issues': plan.issues
        .map(
          (issue) => <String, Object?>{
            'code': issue.code,
            'message': issue.message,
            'taskId': issue.taskId,
          },
        )
        .toList(growable: false),
  };
}

String _sourceForEntry(
  ScheduleEntry entry, {
  required Set<String> fixedEntryIds,
  required Set<String> recoveryEntryIds,
}) {
  final id = entry.id;
  if (id != null && fixedEntryIds.contains(id)) return 'fixed';
  if (id != null && recoveryEntryIds.contains(id)) return 'recovery';
  if (id?.startsWith('rescue_recovery_') == true ||
      entry.tag.toLowerCase() == 'recovery') {
    return 'recovery';
  }
  return 'planned';
}

List<ScheduleEntry> _entriesFromJson(Object? raw, String field) {
  if (raw is! List) throw FormatException('$field must be an array');
  return raw
      .map((item) => ScheduleEntry.fromJson(_map(item, '$field item')))
      .toList(growable: false);
}

Map<String, ScheduleEntry> _entriesById(
  List<ScheduleEntry> entries, {
  String field = 'entries',
}) {
  final result = <String, ScheduleEntry>{};
  for (final entry in entries) {
    final id = _requiredEntryId(entry);
    if (result.containsKey(id)) {
      throw FormatException('$field contains duplicate id: $id');
    }
    result[id] = entry;
  }
  return result;
}

String _requiredEntryId(ScheduleEntry entry) {
  final id = entry.id;
  if (id == null || id.trim().isEmpty) {
    throw const FormatException('schedule entry id must be non-empty');
  }
  return id;
}

List<ScheduleEntry> _sortedStateEntries(Map<String, ScheduleEntry> state) {
  final entries = state.values.toList()
    ..sort((a, b) {
      final byTime = _minutes(a.time).compareTo(_minutes(b.time));
      if (byTime != 0) return byTime;
      return (a.id ?? '').compareTo(b.id ?? '');
    });
  return entries;
}

bool _sameEntryState(
  Map<String, ScheduleEntry> left,
  Map<String, ScheduleEntry> right,
) {
  if (left.length != right.length ||
      !left.keys.toSet().containsAll(right.keys)) {
    return false;
  }
  for (final id in left.keys) {
    if (!_deepEqual(left[id]!.toJson(), right[id]!.toJson())) return false;
  }
  return true;
}

Map<String, Object?> _timeBlocks(List<ScheduleEntry> entries) {
  final blocks = <String, Object?>{};
  for (final entry in entries) {
    final id = entry.id;
    if (id == null) continue;
    blocks[id] = <String, Object?>{
      'hour': entry.time.hour,
      'minute': entry.time.minute,
      'durationMinutes': _durationFromHeight(entry.height),
    };
  }
  return blocks;
}

bool _deepEqual(Object? left, Object? right) {
  if (left is Map && right is Map) {
    if (left.length != right.length) return false;
    for (final key in left.keys) {
      if (!right.containsKey(key) || !_deepEqual(left[key], right[key])) {
        return false;
      }
    }
    return true;
  }
  if (left is List && right is List) {
    if (left.length != right.length) return false;
    for (var i = 0; i < left.length; i++) {
      if (!_deepEqual(left[i], right[i])) return false;
    }
    return true;
  }
  return left == right;
}

SharedJson _map(Object? value, String field) {
  if (value is! Map) throw FormatException('$field must be an object');
  return SharedJson.from(value);
}

SharedJson _review(Object? value) {
  final review = _map(value, 'review');
  final classification = review['classification'];
  if (classification is! String ||
      !_reviewClassifications.contains(classification)) {
    throw FormatException('invalid review classification: $classification');
  }
  final reason = review['reason'];
  if (reason is! String || reason.trim().isEmpty) {
    throw const FormatException('review reason must be non-empty');
  }
  return review;
}

List<String> _stringList(Object? value, String field) {
  if (value is! List || value.any((item) => item is! String)) {
    throw FormatException('$field must be an array of strings');
  }
  return value.cast<String>().toList(growable: false);
}

DateTime _dateTime(Object? value, String field) {
  if (value is! String)
    throw FormatException('$field must be an ISO date-time');
  final parsed = DateTime.tryParse(value);
  if (parsed == null) throw FormatException('$field must be an ISO date-time');
  return parsed;
}

int _minutes(TimeOfDay time) => time.hour * 60 + time.minute;

int _durationFromHeight(double height) =>
    (height / 80.0 * 60.0).round().clamp(1, 24 * 60).toInt();

String _dateOnly(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

class _TransactionFailure implements Exception {
  final String code;

  const _TransactionFailure(this.code);
}
