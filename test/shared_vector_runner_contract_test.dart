import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shixuzhipei/models/models.dart';

import 'support/shared_vector_runner.dart';

void main() {
  test('canonical plan keeps only the shared comparison fields', () {
    final day = DateTime(2026, 9, 16);
    final plan = SchedulingPlan(
      entries: [
        ScheduleEntry(
          id: 'fixed',
          day: day,
          title: 'Fixed',
          tag: 'Fixed',
          load: CognitiveLoad.medium,
          height: 80,
          color: Colors.blue,
          time: const TimeOfDay(hour: 9, minute: 0),
        ),
        ScheduleEntry(
          id: 'planned',
          day: day,
          title: 'Planned',
          tag: 'Work',
          load: CognitiveLoad.low,
          height: 40,
          color: Colors.orange,
          time: const TimeOfDay(hour: 10, minute: 0),
        ),
      ],
      issues: const [
        SchedulingIssue(
          code: 'no_slot',
          message: 'not part of the canonical comparison',
          taskId: 'blocked',
        ),
      ],
    );

    final canonical = canonicalizePlan(
      plan,
      day: day,
      fixedEntryIds: const {'fixed'},
    );

    expect(canonical.keys, containsAll(<String>['entries', 'issues']));
    expect(canonical['entries'], isA<List<dynamic>>());
    expect(canonical['issues'], isA<List<dynamic>>());
    expect(
      (canonical['entries'] as List).map((entry) => entry.keys.toSet()),
      everyElement(
        equals({
          'id',
          'day',
          'time',
          'durationMinutes',
          'source',
          'explanationCodes',
        }),
      ),
    );
    expect(
      (canonical['issues'] as List).map((issue) => issue.keys.toSet()),
      everyElement(equals({'code', 'taskId', 'blockedBy', 'explanationCodes'})),
    );
    expect((canonical['entries'] as List).first['source'], 'fixed');
    expect((canonical['entries'] as List).last['source'], 'planned');
    expect((canonical['entries'] as List).last['durationMinutes'], 30);
    expect((canonical['issues'] as List).single['blockedBy'], isEmpty);
    expect((canonical['issues'] as List).single['explanationCodes'], isEmpty);
  });

  test('result formatter emits machine markers and review classification', () {
    final result = <String, Object?>{
      'fixtures': <Object?>[
        <String, Object?>{
          'name': 'sample.json',
          'status': 'mismatched',
          'review': <String, Object?>{
            'classification': 'pending_a_review',
            'reason': '双端结果尚未由 A 归类',
          },
        },
      ],
      'matched': 0,
      'mismatched': 1,
      'invalid': 0,
    };

    final output = formatSharedVectorResult(result);

    expect(output, startsWith('SHARED_VECTOR_RESULT_BEGIN\n'));
    expect(output, contains('SHARED_VECTOR_RESULT_END'));
    expect('SHARED_VECTOR_RESULT_BEGIN'.allMatches(output).length, 1);
    expect('SHARED_VECTOR_RESULT_END'.allMatches(output).length, 1);
    expect(output, contains('pending_a_review'));
    expect(jsonDecode(output.split('\n')[1]), equals(result));
  });

  test('transaction vector records persistence writer compensation', () async {
    final fixture = <String, Object?>{
      'schemaVersion': 'scheduling/v1',
      'id': 'transaction-test',
      'kind': 'transaction',
      'tags': ['apply_rollback'],
      'request': <String, Object?>{
        'operation': 'apply',
        'before': [_entry('focus', hour: 9)],
        'after': [
          _entry('focus', hour: 10),
          _entry('urgent', hour: 9, height: 40),
        ],
        'failAt': 'urgent',
        'failureCode': 'apply_failed',
      },
      'assertions': <String, Object?>{
        'finalState': <String, Object?>{
          'status': 'rolled_back',
          'originalPlanPreserved': true,
          'exact': true,
          'errorCode': 'apply_failed',
          'entryIds': ['focus'],
          'timeBlocks': <String, Object?>{
            'focus': {'hour': 9, 'minute': 0, 'durationMinutes': 60},
          },
        },
      },
      'review': <String, Object?>{
        'classification': 'pending_a_review',
        'reason': '测试 persistence writer 补偿顺序',
      },
    };

    final result = await runSharedVectorFixture(
      fixture,
      name: 'transaction-test.json',
    );

    expect(result['status'], 'matched');
    final diagnostics = Map<String, Object?>.from(
      result['diagnostics']! as Map,
    );
    expect(diagnostics['writerEvents'], [
      {'operation': 'upsert', 'id': 'focus', 'phase': 'apply'},
      {'operation': 'upsert', 'id': 'urgent', 'phase': 'apply'},
      {'operation': 'upsert', 'id': 'focus', 'phase': 'rollback'},
      {'operation': 'remove', 'id': 'urgent', 'phase': 'rollback'},
    ]);
  });

  test('boundary vector calls the urgent deadline validation branch', () async {
    final result = await runSharedVectorFixture(<String, Object?>{
      'schemaVersion': 'scheduling/v1',
      'id': 'boundary-test',
      'kind': 'boundary',
      'tags': ['boundary_time'],
      'request': <String, Object?>{
        'operation': 'urgent_deadline',
        'now': '2026-09-15T10:00:00',
        'scheduleDay': '2026-09-16',
      },
      'assertions': <String, Object?>{
        'finalState': <String, Object?>{'status': 'evaluated', 'valid': true},
      },
      'review': <String, Object?>{
        'classification': 'pending_a_review',
        'reason': '测试截止时间边界校验',
      },
    }, name: 'boundary-test.json');

    expect(result['status'], 'matched');
    final actual = Map<String, Object?>.from(
      (result['actual'] as Map)['finalState'] as Map,
    );
    expect(actual['status'], 'evaluated');
    expect(actual['valid'], isTrue);
    expect(actual['deadline'], startsWith('2026-09-16T17:00:00'));
  });

  test('transaction adapter rejects duplicate before or after ids', () async {
    final duplicate = _entry('duplicate', hour: 9);
    await expectLater(
      runSharedVectorFixture(<String, Object?>{
        'schemaVersion': 'scheduling/v1',
        'id': 'duplicate-transaction-test',
        'kind': 'transaction',
        'tags': ['apply_rollback'],
        'request': <String, Object?>{
          'operation': 'apply',
          'before': [duplicate, duplicate],
          'after': <Object?>[],
        },
        'assertions': <String, Object?>{'finalState': <String, Object?>{}},
        'review': <String, Object?>{
          'classification': 'pending_a_review',
          'reason': '重复 id 必须使向量无效',
        },
      }, name: 'duplicate-transaction-test.json'),
      throwsA(isA<FormatException>()),
    );
  });
}

Map<String, Object?> _entry(
  String id, {
  required int hour,
  double height = 80,
}) {
  return <String, Object?>{
    'id': id,
    'day': '2026-09-16',
    'title': id,
    'tag': 'Work',
    'load': 'medium',
    'height': height,
    'color': 4278255360,
    'time': {'hour': hour, 'minute': 0},
  };
}
