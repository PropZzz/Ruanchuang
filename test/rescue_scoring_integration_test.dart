import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shixuzhipei/models/models.dart';
import 'package:shixuzhipei/services/scheduling/heuristic_scheduling_engine.dart';
import 'package:shixuzhipei/services/scheduling/schedule_rescue.dart';

void main() {
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
