import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shixuzhipei/models/models.dart';
import 'package:shixuzhipei/services/scheduling/schedule_rescue.dart';
import 'package:shixuzhipei/services/scheduling/scheduler_core.dart';

void main() {
  test('empty work windows do not create a default slot', () {
    final plan = const SchedulerCore().plan(
      SchedulingRequest(
        day: DateTime(2026, 9, 14),
        tasks: [
          PlanTask(
            id: 'task',
            title: 'Task',
            durationMinutes: 30,
            priority: 3,
            load: CognitiveLoad.medium,
            tag: 'Task',
          ),
        ],
        windows: [],
        energy: EnergyTier.medium,
      ),
    );

    expect(plan.entries, isEmpty);
    expect(plan.issues.single.code, 'no_slot');
  });

  test('earliestStart shift must still fit inside the interval', () {
    final plan = const SchedulerCore().plan(
      SchedulingRequest(
        day: DateTime(2026, 9, 14),
        tasks: [
          PlanTask(
            id: 'task',
            title: 'Task',
            durationMinutes: 30,
            priority: 3,
            load: CognitiveLoad.medium,
            tag: 'Task',
            earliestStart: DateTime(2026, 9, 14, 10, 50),
          ),
        ],
        windows: [
          TimeWindow(
            start: TimeOfDay(hour: 10, minute: 0),
            end: TimeOfDay(hour: 11, minute: 0),
          ),
        ],
        energy: EnergyTier.medium,
      ),
    );

    expect(plan.entries, isEmpty);
    expect(plan.issues.single.code, 'no_slot');
  });

  test('split task applies earliestStart to every chunk', () {
    final plan = const SchedulerCore().plan(
      SchedulingRequest(
        day: DateTime(2026, 9, 14),
        tasks: [
          PlanTask(
            id: 'split',
            title: 'Split',
            durationMinutes: 30,
            priority: 3,
            load: CognitiveLoad.medium,
            tag: 'Task',
            splittable: true,
            minimumChunkMinutes: 15,
            earliestStart: DateTime(2026, 9, 14, 10),
          ),
        ],
        windows: [
          TimeWindow(
            start: TimeOfDay(hour: 9, minute: 0),
            end: TimeOfDay(hour: 9, minute: 30),
          ),
          TimeWindow(
            start: TimeOfDay(hour: 10, minute: 0),
            end: TimeOfDay(hour: 10, minute: 15),
          ),
          TimeWindow(
            start: TimeOfDay(hour: 10, minute: 30),
            end: TimeOfDay(hour: 10, minute: 45),
          ),
        ],
        energy: EnergyTier.medium,
      ),
    );

    expect(plan.entries, hasLength(2));
    expect(plan.entries.map((entry) => entry.time), [
      const TimeOfDay(hour: 10, minute: 0),
      const TimeOfDay(hour: 10, minute: 30),
    ]);
  });

  test('fixed blocks outside windows do not consume a valid window', () {
    final day = DateTime(2026, 9, 14);
    final plan = const SchedulerCore().plan(
      SchedulingRequest(
        day: day,
        tasks: [
          PlanTask(
            id: 'task',
            title: 'Task',
            durationMinutes: 30,
            priority: 3,
            load: CognitiveLoad.medium,
            tag: 'Task',
          ),
        ],
        windows: [
          TimeWindow(
            start: TimeOfDay(hour: 9, minute: 0),
            end: TimeOfDay(hour: 10, minute: 0),
          ),
        ],
        energy: EnergyTier.medium,
        fixed: [
          ScheduleEntry(
            id: 'out',
            day: day,
            title: 'Out',
            tag: 'Fixed',
            height: 80,
            color: Colors.blue,
            time: const TimeOfDay(hour: 12, minute: 0),
            explanationCodes: ['priority'],
          ),
        ],
      ),
    );

    expect(plan.entries.any((entry) => entry.id == 'task'), isTrue);
    final fixed = plan.entries.singleWhere((entry) => entry.id == 'out');
    expect(fixed.explanationCodes, ['priority', 'fixed_conflict']);
  });

  test(
    'partially overlapping fixed blocks still occupy the intersecting window',
    () {
      final day = DateTime(2026, 9, 14);
      final plan = const SchedulerCore().plan(
        SchedulingRequest(
          day: day,
          tasks: [
            PlanTask(
              id: 'task',
              title: 'Task',
              durationMinutes: 15,
              priority: 3,
              load: CognitiveLoad.medium,
              tag: 'Task',
            ),
          ],
          windows: [
            TimeWindow(
              start: TimeOfDay(hour: 9, minute: 0),
              end: TimeOfDay(hour: 10, minute: 0),
            ),
          ],
          energy: EnergyTier.medium,
          fixed: [
            ScheduleEntry(
              id: 'partial',
              day: day,
              title: 'Partial',
              tag: 'Fixed',
              height: 160,
              color: Colors.blue,
              time: const TimeOfDay(hour: 8, minute: 30),
            ),
          ],
        ),
      );

      expect(plan.entries.where((entry) => entry.id == 'task'), isEmpty);
      expect(
        plan.issues.any((issue) => issue.code == 'fixed_conflict'),
        isTrue,
      );
    },
  );

  test('planned explanation codes are ordered and include energy fit', () {
    final plan = const SchedulerCore().plan(
      SchedulingRequest(
        day: DateTime(2026, 9, 14),
        tasks: [
          PlanTask(
            id: 'task',
            title: 'Task',
            durationMinutes: 15,
            priority: 3,
            load: CognitiveLoad.low,
            tag: 'Task',
            due: DateTime(2026, 9, 14, 12),
          ),
        ],
        windows: [
          TimeWindow(
            start: TimeOfDay(hour: 9, minute: 0),
            end: TimeOfDay(hour: 10, minute: 0),
          ),
        ],
        energy: EnergyTier.low,
      ),
    );

    expect(plan.entries.single.explanationCodes, [
      'deadline_proximity',
      'priority',
      'energy_fit',
    ]);
  });

  test(
    'fixed entries remain and report overlap and out-of-window conflicts',
    () {
      final day = DateTime(2026, 9, 14);
      final fixed = [
        ScheduleEntry(
          id: 'fixed-a',
          day: day,
          title: 'A',
          tag: 'Fixed',
          height: 40,
          color: Colors.blue,
          time: const TimeOfDay(hour: 9, minute: 0),
        ),
        ScheduleEntry(
          id: 'fixed-b',
          day: day,
          title: 'B',
          tag: 'Fixed',
          height: 40,
          color: Colors.blue,
          time: const TimeOfDay(hour: 9, minute: 15),
        ),
        ScheduleEntry(
          id: 'fixed-out',
          day: day,
          title: 'Out',
          tag: 'Fixed',
          height: 40,
          color: Colors.blue,
          time: const TimeOfDay(hour: 12, minute: 0),
        ),
      ];
      final plan = const SchedulerCore().plan(
        SchedulingRequest(
          day: day,
          tasks: [],
          windows: [
            TimeWindow(
              start: TimeOfDay(hour: 9, minute: 0),
              end: TimeOfDay(hour: 10, minute: 0),
            ),
          ],
          energy: EnergyTier.medium,
          fixed: fixed,
        ),
      );

      expect(
        plan.entries.map((entry) => entry.id),
        containsAll(['fixed-a', 'fixed-b', 'fixed-out']),
      );
      expect(
        plan.issues.where((issue) => issue.code == 'fixed_conflict'),
        hasLength(3),
      );
    },
  );

  test(
    'hard deadline does not fall back to a late slot while soft due emits miss_due',
    () {
      final day = DateTime(2026, 9, 14);
      final hard = const SchedulerCore().plan(
        SchedulingRequest(
          day: day,
          tasks: [
            PlanTask(
              id: 'hard',
              title: 'Hard',
              durationMinutes: 30,
              priority: 3,
              load: CognitiveLoad.medium,
              tag: 'Task',
              due: DateTime(2026, 9, 14, 9, 30),
              hardDeadline: true,
            ),
          ],
          windows: [
            TimeWindow(
              start: TimeOfDay(hour: 10, minute: 0),
              end: TimeOfDay(hour: 11, minute: 0),
            ),
          ],
          energy: EnergyTier.medium,
        ),
      );
      expect(hard.entries, isEmpty);
      expect(hard.issues.single.code, 'no_slot');
      expect(hard.issues.single.explanationCodes, ['deadline_proximity']);

      final soft = const SchedulerCore().plan(
        SchedulingRequest(
          day: day,
          tasks: [
            PlanTask(
              id: 'soft',
              title: 'Soft',
              durationMinutes: 30,
              priority: 3,
              load: CognitiveLoad.medium,
              tag: 'Task',
              due: DateTime(2026, 9, 14, 9, 30),
            ),
          ],
          windows: [
            TimeWindow(
              start: TimeOfDay(hour: 10, minute: 0),
              end: TimeOfDay(hour: 11, minute: 0),
            ),
          ],
          energy: EnergyTier.medium,
        ),
      );
      expect(soft.entries, hasLength(1));
      expect(soft.issues.single.code, 'miss_due');
    },
  );

  test('soft deadline fallback still uses low-energy slot score', () {
    final plan = const SchedulerCore().plan(
      SchedulingRequest(
        day: DateTime(2026, 9, 14),
        tasks: [
          PlanTask(
            id: 'high',
            title: 'High',
            durationMinutes: 60,
            priority: 3,
            load: CognitiveLoad.high,
            tag: 'Task',
            due: DateTime(2026, 9, 14, 7),
          ),
        ],
        windows: [
          TimeWindow(
            start: TimeOfDay(hour: 8, minute: 0),
            end: TimeOfDay(hour: 10, minute: 0),
          ),
          TimeWindow(
            start: TimeOfDay(hour: 14, minute: 0),
            end: TimeOfDay(hour: 16, minute: 0),
          ),
        ],
        energy: EnergyTier.veryLow,
        tuning: SchedulingTuning(highLoadPenaltyWhenLowEnergy: 2.0),
      ),
    );

    expect(plan.entries.single.time, const TimeOfDay(hour: 14, minute: 0));
    expect(plan.entries.single.height, 160.0);
    expect(plan.issues.single.code, 'miss_due');
  });

  test('hard overdue tasks report overdue risk in addition to no_slot', () {
    final plan = const SchedulerCore().plan(
      SchedulingRequest(
        day: DateTime(2026, 9, 14),
        tasks: [
          PlanTask(
            id: 'overdue',
            title: 'Overdue',
            durationMinutes: 15,
            priority: 3,
            load: CognitiveLoad.medium,
            tag: 'Task',
            due: DateTime(2026, 9, 13, 9),
            hardDeadline: true,
          ),
        ],
        windows: [
          TimeWindow(
            start: TimeOfDay(hour: 9, minute: 0),
            end: TimeOfDay(hour: 10, minute: 0),
          ),
        ],
        energy: EnergyTier.medium,
      ),
    );

    expect(plan.entries, isEmpty);
    expect(plan.issues.map((issue) => issue.code), ['no_slot', 'overdue']);
  });

  test('recovery buffer is only inserted into a legal free interval', () {
    final day = DateTime(2026, 9, 14);
    final options = ScheduleRescueService(engine: const SchedulerCore())
        .propose(
          base: SchedulingRequest(
            day: day,
            tasks: const [],
            windows: const [
              TimeWindow(
                start: TimeOfDay(hour: 9, minute: 0),
                end: TimeOfDay(hour: 12, minute: 0),
              ),
            ],
            energy: EnergyTier.medium,
            fixed: [
              ScheduleEntry(
                id: 'busy',
                day: day,
                title: 'Busy',
                tag: 'Fixed',
                height: 240,
                color: Colors.blue,
                time: TimeOfDay(hour: 9, minute: 0),
              ),
            ],
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

    final recovery = options[1];
    expect(recovery.recoveryMinutes, 0);
    expect(
      recovery.plan.entries.where((entry) => entry.tag == 'Recovery'),
      isEmpty,
    );
  });

  test(
    'SchedulerCore preserves deterministic ordering and dependency issues',
    () {
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
    },
  );
}
