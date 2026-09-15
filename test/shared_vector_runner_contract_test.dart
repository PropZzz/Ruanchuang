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
      everyElement(
        equals({'code', 'taskId', 'blockedBy', 'explanationCodes'}),
      ),
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
    expect(output, contains('pending_a_review'));
    expect(jsonDecode(output.split('\n')[1]), equals(result));
  });
}
