import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shixuzhipei/models/models.dart';
import 'package:shixuzhipei/services/scheduling/scheduler_core.dart';

void main() {
  test('splittable task spans windows with deterministic chunk ids', () {
    final plan = const SchedulerCore().plan(
      SchedulingRequest(
        day: DateTime(2026, 9, 14),
        tasks: [
          PlanTask(
            id: 'split-task',
            title: 'Split task',
            durationMinutes: 90,
            priority: 3,
            load: CognitiveLoad.medium,
            tag: 'Task',
            splittable: true,
            minimumChunkMinutes: 30,
          ),
        ],
        windows: [
          TimeWindow(
            start: TimeOfDay(hour: 9, minute: 0),
            end: TimeOfDay(hour: 10, minute: 0),
          ),
          TimeWindow(
            start: TimeOfDay(hour: 11, minute: 0),
            end: TimeOfDay(hour: 12, minute: 0),
          ),
        ],
        energy: EnergyTier.medium,
      ),
    );

    expect(plan.entries.map((entry) => entry.id), [
      'split-task#1',
      'split-task#2',
    ]);
    expect(plan.entries.map((entry) => ((entry.height / 80) * 60).round()), [
      60,
      30,
    ]);
  });

  test('risk object reports hard scheduling issues', () {
    final plan = const SchedulingPlan(
      entries: [],
      issues: [
        SchedulingIssue(code: 'no_slot', message: 'No slot', taskId: 'task'),
      ],
    );
    expect(plan.toJson()['risk'], {
      'level': 'high',
      'issueCount': 1,
      'hardIssueCount': 1,
    });
  });
}
