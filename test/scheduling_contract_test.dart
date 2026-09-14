import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shixuzhipei/models/models.dart';
import 'package:shixuzhipei/services/scheduling/scheduling_contract.dart';

void main() {
  test('request uses canonical date and version fields', () {
    final request = SchedulingRequest(
      day: DateTime(2026, 9, 14, 10, 30),
      tasks: const [],
      windows: const [],
      energy: EnergyTier.medium,
    );

    final json = request.toJson();

    expect(json['schemaVersion'], '1');
    expect(json['day'], '2026-09-14');
  });

  test('fixed schedule persistence keeps height shape', () {
    final entry = ScheduleEntry(
      id: 'fixed-1',
      title: 'Meeting',
      tag: 'Meeting',
      height: 80,
      color: Colors.teal,
      time: const TimeOfDay(hour: 9, minute: 0),
    );

    final json = entry.toJson();

    expect(json['height'], 80);
    expect(json.containsKey('durationMinutes'), isFalse);
  });

  test(
    'task dates are canonical UTC strings and scheduling fields round trip',
    () {
      final task = PlanTask(
        id: 'task-1',
        title: 'Write',
        durationMinutes: 30,
        priority: 4,
        load: CognitiveLoad.medium,
        tag: 'Writing',
        goalId: 'goal-1',
        goalTaskId: 'goal-task-1',
        due: DateTime.parse('2026-09-14T13:30:00+08:00'),
        earliestStart: DateTime.parse('2026-09-14T08:00:00+08:00'),
        hardDeadline: true,
        dependsOn: const ['dependency'],
      );

      final json = SchedulingContract.taskToJson(task);

      expect(json['due'], '2026-09-14T05:30:00Z');
      expect(json['earliestStart'], '2026-09-14T00:00:00Z');
      expect(json['hardDeadline'], isTrue);
      expect(json['dependsOn'], ['dependency']);
      expect(SchedulingContract.taskFromJson(json).goalTaskId, 'goal-task-1');
    },
  );

  test(
    'fixed adapter converts height to canonical duration without height',
    () {
      final entry = ScheduleEntry(
        id: 'fixed-1',
        day: DateTime(2026, 9, 14),
        title: 'Meeting',
        tag: 'Meeting',
        load: CognitiveLoad.medium,
        height: 80,
        color: Colors.teal,
        time: const TimeOfDay(hour: 9, minute: 0),
      );

      final json = SchedulingContract.fixedEntryToJson(entry);

      expect(json['durationMinutes'], 60);
      expect(json.containsKey('height'), isFalse);
      expect(json['source'], 'fixed');
    },
  );

  test('plan adapter round trips response metadata', () {
    final plan = SchedulingPlan(
      entries: [
        ScheduleEntry(
          id: 'task-1',
          day: DateTime(2026, 9, 14),
          title: 'Write',
          tag: 'Writing',
          load: CognitiveLoad.high,
          height: 40,
          color: Colors.teal,
          time: const TimeOfDay(hour: 9, minute: 0),
          source: 'planned',
          explanationCodes: const ['priority'],
        ),
      ],
      issues: const [
        SchedulingIssue(
          code: 'dependency_blocked',
          message: 'Dependency is not scheduled',
          taskId: 'task-2',
          blockedBy: ['task-1'],
          explanationCodes: ['fixed_conflict'],
        ),
      ],
    );

    final json = SchedulingContract.planToJson(plan);
    final parsed = SchedulingContract.planFromJson(json);

    expect(json['schemaVersion'], '1');
    expect((json['entries'] as List).single['durationMinutes'], 30);
    expect((json['entries'] as List).single.containsKey('height'), isFalse);
    expect(parsed.entries.single.source, 'planned');
    expect(parsed.entries.single.explanationCodes, ['priority']);
    expect(parsed.issues.single.blockedBy, ['task-1']);
    expect(parsed.issues.single.explanationCodes, ['fixed_conflict']);
  });

  test('adapter rejects invalid canonical enum, range, and unknown values', () {
    expect(
      () => SchedulingContract.taskFromJson({
        'id': 'task',
        'title': 'Task',
        'durationMinutes': 0,
        'priority': 3,
        'load': 'medium',
        'tag': 'Task',
      }),
      throwsA(anyOf(isA<FormatException>(), isA<ArgumentError>())),
    );
    expect(
      () => SchedulingContract.taskFromJson({
        'id': 'task',
        'title': 'Task',
        'durationMinutes': 30,
        'priority': 3,
        'load': 'invalid',
        'tag': 'Task',
      }),
      throwsA(anyOf(isA<FormatException>(), isA<ArgumentError>())),
    );
    expect(
      () => SchedulingContract.taskFromJson({
        'id': 'task',
        'title': 'Task',
        'durationMinutes': 30,
        'priority': 3,
        'load': 'medium',
        'tag': 'Task',
        'unknown': true,
      }),
      throwsA(anyOf(isA<FormatException>(), isA<ArgumentError>())),
    );
  });

  test('fixed conflict is accepted as a hard canonical issue', () {
    final plan = SchedulingPlan(
      entries: const [],
      issues: const [
        SchedulingIssue(
          code: 'fixed_conflict',
          message: 'Fixed entry conflict',
          taskId: 'fixed-a',
          explanationCodes: ['fixed_conflict'],
        ),
      ],
    );

    final json = SchedulingContract.planToJson(plan);
    expect(json['issues'], isNotEmpty);
    expect(json['risk'], {
      'level': 'high',
      'issueCount': 1,
      'hardIssueCount': 1,
    });
    expect(
      SchedulingContract.planFromJson(
        Map<String, Object?>.from(json),
      ).issues.single.code,
      'fixed_conflict',
    );
  });

  test('adapter rejects non-minute datetime values', () {
    expect(
      () => SchedulingContract.taskFromJson({
        'id': 'task',
        'title': 'Task',
        'durationMinutes': 30,
        'priority': 3,
        'load': 'medium',
        'tag': 'Task',
        'due': '2026-09-14T13:30:30+08:00',
      }),
      throwsA(anyOf(isA<FormatException>(), isA<ArgumentError>())),
    );
  });
}
