import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shixuzhipei/models/models.dart';
import 'package:shixuzhipei/services/scheduling/scheduler_core.dart';

void main() {
  test('SchedulerCore preserves deterministic ordering and dependency issues', () {
    final plan = const SchedulerCore().plan(
      SchedulingRequest(
        day: DateTime(2026, 9, 14),
        tasks: [
          PlanTask(
            id: 'dependent',
            title: 'Dependent',
            durationMinutes: 20,
            priority: 3,
            load: CognitiveLoad.low,
            tag: 'Task',
            dependsOn: ['missing'],
          ),
        ],
        windows: [
          TimeWindow(
            start: TimeOfDay(hour: 9, minute: 0),
            end: TimeOfDay(hour: 11, minute: 0),
          ),
        ],
        energy: EnergyTier.medium,
      ),
    );

    expect(plan.entries, isEmpty);
    expect(plan.issues.single.code, 'dependency_blocked');
    expect(plan.issues.single.blockedBy, ['missing']);
  });
}
