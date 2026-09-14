import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shixuzhipei/models/models.dart';
import 'package:shixuzhipei/services/scheduling/heuristic_scheduling_engine.dart';
import 'package:shixuzhipei/services/scheduling/schedule_rescue.dart';

int _startMinute(ScheduleEntry entry) =>
    entry.time.hour * 60 + entry.time.minute;

void main() {
  test(
    'minimizeChanges locks baseline while other strategies can reflow it',
    () {
      final day = DateTime(2026, 9, 14);
      final baseline = [
        ScheduleEntry(
          id: 'baseline',
          day: day,
          title: 'Baseline',
          tag: 'Task',
          load: CognitiveLoad.medium,
          height: 80,
          color: Colors.blue,
          time: const TimeOfDay(hour: 9, minute: 0),
        ),
      ];
      final options =
          ScheduleRescueService(
            engine: const HeuristicSchedulingEngine(),
          ).propose(
            base: SchedulingRequest(
              day: day,
              tasks: const [
                PlanTask(
                  id: 'baseline',
                  title: 'Baseline',
                  durationMinutes: 60,
                  priority: 1,
                  load: CognitiveLoad.medium,
                  tag: 'Task',
                ),
              ],
              windows: const [
                TimeWindow(
                  start: TimeOfDay(hour: 9, minute: 0),
                  end: TimeOfDay(hour: 11, minute: 0),
                ),
              ],
              energy: EnergyTier.medium,
            ),
            baseline: baseline,
            urgent: const PlanTask(
              id: 'urgent',
              title: 'Urgent',
              durationMinutes: 60,
              priority: 5,
              load: CognitiveLoad.high,
              tag: 'Urgent',
            ),
          );

      final minimal = options[2];
      expect(
        minimal.plan.entries
            .where((entry) => entry.id == 'baseline')
            .single
            .time,
        const TimeOfDay(hour: 9, minute: 0),
      );
      expect(minimal.movedEntryCount, 0);
      expect(options.first.movedEntryCount, greaterThanOrEqualTo(1));
      expect(
        minimal.plan.entries
            .where((entry) => entry.id == 'baseline')
            .single
            .explanationCodes,
        ['kept_baseline'],
      );
    },
  );

  test(
    'recovery is counted only when the first plan leaves a legal interval',
    () {
      final day = DateTime(2026, 9, 14);
      final options =
          ScheduleRescueService(
            engine: const HeuristicSchedulingEngine(),
          ).propose(
            base: SchedulingRequest(
              day: day,
              tasks: const [
                PlanTask(
                  id: 'long',
                  title: 'Long',
                  durationMinutes: 165,
                  priority: 1,
                  load: CognitiveLoad.medium,
                  tag: 'Task',
                ),
              ],
              windows: const [
                TimeWindow(
                  start: TimeOfDay(hour: 9, minute: 0),
                  end: TimeOfDay(hour: 12, minute: 0),
                ),
              ],
              energy: EnergyTier.medium,
            ),
            baseline: const [],
            urgent: const PlanTask(
              id: 'urgent',
              title: 'Urgent',
              durationMinutes: 15,
              priority: 5,
              load: CognitiveLoad.low,
              tag: 'Urgent',
            ),
          );

      expect(options[1].recoveryMinutes, 0);
      expect(
        options[1].plan.entries.where((entry) => entry.tag == 'Recovery'),
        isEmpty,
      );
    },
  );

  test('proposes three explainable rescue strategies', () {
    final day = DateTime(2026, 8, 6);
    const windows = [
      TimeWindow(
        start: TimeOfDay(hour: 8, minute: 0),
        end: TimeOfDay(hour: 12, minute: 0),
      ),
      TimeWindow(
        start: TimeOfDay(hour: 13, minute: 30),
        end: TimeOfDay(hour: 18, minute: 0),
      ),
    ];
    final baseline = [
      ScheduleEntry(
        id: 'deep',
        day: day,
        title: '深度工作',
        tag: 'Deep Work',
        load: CognitiveLoad.high,
        height: 120,
        color: Colors.teal,
        time: const TimeOfDay(hour: 9, minute: 0),
      ),
      ScheduleEntry(
        id: 'review',
        day: day,
        title: '方案评审',
        tag: 'Review',
        load: CognitiveLoad.medium,
        height: 80,
        color: Colors.blue,
        time: const TimeOfDay(hour: 14, minute: 0),
      ),
    ];
    final baseRequest = SchedulingRequest(
      day: day,
      windows: windows,
      energy: EnergyTier.medium,
      fixed: const [],
      tasks: const [
        PlanTask(
          id: 'deep',
          title: '深度工作',
          durationMinutes: 90,
          priority: 3,
          load: CognitiveLoad.high,
          tag: 'Deep Work',
        ),
        PlanTask(
          id: 'review',
          title: '方案评审',
          durationMinutes: 60,
          priority: 2,
          load: CognitiveLoad.medium,
          tag: 'Review',
        ),
      ],
    );
    final urgent = PlanTask(
      id: 'urgent',
      title: '客户紧急问题',
      durationMinutes: 30,
      priority: 5,
      due: DateTime(2026, 8, 6, 11, 0),
      load: CognitiveLoad.medium,
      tag: 'Urgent',
    );

    final options = ScheduleRescueService(
      engine: HeuristicSchedulingEngine(),
    ).propose(base: baseRequest, baseline: baseline, urgent: urgent);

    expect(options.map((option) => option.strategy), [
      RescueStrategy.protectDeadline,
      RescueStrategy.protectRecovery,
      RescueStrategy.minimizeChanges,
    ]);
    for (final option in options) {
      expect(option.rationale.trim(), isNotEmpty);
      expect(option.tradeoff.trim(), isNotEmpty);
      expect(option.plan.entries.any((entry) => entry.id == 'urgent'), isTrue);
    }

    final deadline = options.first.plan.entries.firstWhere(
      (entry) => entry.id == 'urgent',
    );
    expect(_startMinute(deadline) + 30, lessThanOrEqualTo(11 * 60));

    final recovery = options[1];
    expect(
      recovery.plan.entries.any((entry) => entry.tag == 'Recovery'),
      isTrue,
    );

    final minimal = options[2];
    expect(
      minimal.movedEntryCount,
      lessThanOrEqualTo(options.first.movedEntryCount),
    );
  });
}
