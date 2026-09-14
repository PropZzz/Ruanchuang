import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shixuzhipei/models/models.dart';
import 'package:shixuzhipei/services/scheduling/heuristic_scheduling_engine.dart';
import 'package:shixuzhipei/services/scheduling/schedule_rescue.dart';
import 'package:shixuzhipei/services/scheduling/rescue_scoring.dart';

void main() {
  test(
    'split entries count as one task and overdue risk mirrors due misses',
    () {
      final plan = SchedulingPlan(
        entries: [
          ScheduleEntry(
            id: 'split#1',
            title: 'Split',
            tag: 'Task',
            load: CognitiveLoad.medium,
            height: 20,
            color: Colors.blue,
            time: const TimeOfDay(hour: 9, minute: 0),
            source: 'planned',
          ),
          ScheduleEntry(
            id: 'split#2',
            title: 'Split',
            tag: 'Task',
            load: CognitiveLoad.medium,
            height: 20,
            color: Colors.blue,
            time: const TimeOfDay(hour: 10, minute: 0),
            source: 'planned',
          ),
        ],
        issues: const [
          SchedulingIssue(
            code: 'miss_due',
            message: 'late',
            taskId: 'split',
            explanationCodes: ['deadline_proximity'],
          ),
        ],
      );
      final metrics = metricsForRescuePlan(
        plan: plan,
        tasks: [
          PlanTask(
            id: 'split',
            title: 'Split',
            durationMinutes: 30,
            priority: 5,
            due: DateTime(2026, 9, 14, 8),
            load: CognitiveLoad.medium,
            tag: 'Task',
            splittable: true,
          ),
        ],
        movedEntryCount: 0,
        baselineEntryCount: 0,
        energy: EnergyTier.medium,
        recoveryMinutes: 0,
      );

      expect(metrics.priority, closeTo(1.0, 0.000001));
      expect(metrics.urgency, closeTo(0.0, 0.000001));
      expect(metrics.overdueRisk, closeTo(1.0, 0.000001));
    },
  );

  test('local rescue options expose the five weighted score metrics', () {
    final day = DateTime(2026, 9, 14);
    final options =
        ScheduleRescueService(
          engine: const HeuristicSchedulingEngine(),
        ).propose(
          base: SchedulingRequest(
            day: day,
            tasks: const [
              PlanTask(
                id: 'task',
                title: 'Task',
                durationMinutes: 30,
                priority: 3,
                load: CognitiveLoad.medium,
                tag: 'Task',
              ),
            ],
            windows: const [
              TimeWindow(
                start: TimeOfDay(hour: 9, minute: 0),
                end: TimeOfDay(hour: 17, minute: 0),
              ),
            ],
            energy: EnergyTier.medium,
          ),
          baseline: const [],
          urgent: PlanTask(
            id: 'urgent',
            title: 'Urgent',
            durationMinutes: 30,
            priority: 5,
            load: CognitiveLoad.high,
            tag: 'Urgent',
            due: DateTime(2026, 9, 14, 16),
          ),
        );

    for (final option in options) {
      expect(
        option.scoreBreakdown.keys,
        containsAll([
          'urgency',
          'priority',
          'energyFit',
          'stability',
          'recovery',
        ]),
      );
      expect(option.score, inInclusiveRange(0.0, 1.0));
      expect(option.hardIssueCount, greaterThanOrEqualTo(0));
    }
  });
}
