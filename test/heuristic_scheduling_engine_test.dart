import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shixuzhipei/models/models.dart';
import 'package:shixuzhipei/services/scheduling/heuristic_scheduling_engine.dart';

int _startMin(ScheduleEntry e) => e.time.hour * 60 + e.time.minute;
int _durMin(ScheduleEntry e) => ((e.height / 80.0) * 60.0).round();

bool _withinWindows(ScheduleEntry e, List<TimeWindow> windows) {
  final s = _startMin(e);
  final eEnd = s + _durMin(e);
  for (final w in windows) {
    final ws = w.start.hour * 60 + w.start.minute;
    final we = w.end.hour * 60 + w.end.minute;
    if (s >= ws && eEnd <= we) return true;
  }
  return false;
}

void main() {
  group('HeuristicSchedulingEngine', () {
    test('produces non-overlapping blocks within windows', () {
      final engine = HeuristicSchedulingEngine();
      final day = DateTime(2026, 1, 1);

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

      final tasks = [
        PlanTask(
          id: 'a',
          title: 'Deep design',
          durationMinutes: 90,
          priority: 4,
          load: CognitiveLoad.high,
          tag: 'Deep Work',
          due: DateTime(2026, 1, 1, 12, 0),
        ),
        PlanTask(
          id: 'b',
          title: 'Email',
          durationMinutes: 30,
          priority: 2,
          load: CognitiveLoad.low,
          tag: 'Micro',
        ),
        PlanTask(
          id: 'c',
          title: 'Spec review',
          durationMinutes: 60,
          priority: 3,
          load: CognitiveLoad.medium,
          tag: 'Routine',
          due: DateTime(2026, 1, 1, 17, 0),
        ),
        PlanTask(
          id: 'd',
          title: 'Implementation sprint',
          durationMinutes: 120,
          priority: 5,
          load: CognitiveLoad.high,
          tag: 'Deep Work',
        ),
      ];

      final plan = engine.plan(
        SchedulingRequest(
          day: day,
          tasks: tasks,
          windows: windows,
          energy: EnergyTier.high,
        ),
      );

      final entries = List<ScheduleEntry>.from(plan.entries)
        ..sort((x, y) => _startMin(x).compareTo(_startMin(y)));

      for (var i = 0; i < entries.length; i++) {
        expect(_withinWindows(entries[i], windows), isTrue);
        if (i == 0) continue;
        final prev = entries[i - 1];
        final prevEnd = _startMin(prev) + _durMin(prev);
        expect(prevEnd <= _startMin(entries[i]), isTrue);
      }
    });

    test('urgent task tends to be scheduled before its due time', () {
      final engine = HeuristicSchedulingEngine();
      final day = DateTime(2026, 1, 1);

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

      final baselineTasks = [
        PlanTask(
          id: 'a',
          title: 'Deep design',
          durationMinutes: 90,
          priority: 4,
          load: CognitiveLoad.high,
          tag: 'Deep Work',
        ),
        PlanTask(
          id: 'b',
          title: 'Spec review',
          durationMinutes: 60,
          priority: 3,
          load: CognitiveLoad.medium,
          tag: 'Routine',
        ),
        PlanTask(
          id: 'c',
          title: 'Email',
          durationMinutes: 30,
          priority: 2,
          load: CognitiveLoad.low,
          tag: 'Micro',
        ),
      ];

      final urgent = PlanTask(
        id: 'u',
        title: 'URGENT',
        durationMinutes: 25,
        priority: 5,
        load: CognitiveLoad.medium,
        tag: 'Urgent',
        due: DateTime(2026, 1, 1, 11, 0),
      );

      final plan = engine.plan(
        SchedulingRequest(
          day: day,
          tasks: [...baselineTasks, urgent],
          windows: windows,
          energy: EnergyTier.high,
        ),
      );

      final urgentEntry = plan.entries.firstWhere((e) => e.id == 'u');
      final urgentEnd = _startMin(urgentEntry) + _durMin(urgentEntry);
      expect(urgentEnd <= 11 * 60, isTrue);
    });

    test('low energy penalizes high-load tasks (tends to schedule them later)', () {
      final engine = HeuristicSchedulingEngine();
      final day = DateTime(2026, 1, 1);

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

      final tasks = [
        PlanTask(
          id: 'h',
          title: 'High load',
          durationMinutes: 60,
          priority: 3,
          load: CognitiveLoad.high,
          tag: 'Deep Work',
        ),
        PlanTask(
          id: 'l',
          title: 'Low load',
          durationMinutes: 60,
          priority: 3,
          load: CognitiveLoad.low,
          tag: 'Micro',
        ),
      ];

      final plan = engine.plan(
        SchedulingRequest(
          day: day,
          tasks: tasks,
          windows: windows,
          energy: EnergyTier.veryLow,
        ),
      );

      final low = plan.entries.firstWhere((e) => e.id == 'l');
      final high = plan.entries.firstWhere((e) => e.id == 'h');
      expect(_startMin(low) <= _startMin(high), isTrue);
    });

    test('tuning highLoadPenaltyWhenLowEnergy can push high-load work out of mornings', () {
      final engine = HeuristicSchedulingEngine();
      final day = DateTime(2026, 1, 1);

      const windows = [
        TimeWindow(
          start: TimeOfDay(hour: 8, minute: 0),
          end: TimeOfDay(hour: 10, minute: 0),
        ),
        TimeWindow(
          start: TimeOfDay(hour: 14, minute: 0),
          end: TimeOfDay(hour: 16, minute: 0),
        ),
      ];

      final tasks = [
        PlanTask(
          id: 'h',
          title: 'High load',
          durationMinutes: 60,
          priority: 3,
          load: CognitiveLoad.high,
          tag: 'Deep Work',
        ),
      ];

      final plan = engine.plan(
        SchedulingRequest(
          day: day,
          tasks: tasks,
          windows: windows,
          energy: EnergyTier.veryLow,
          tuning: const SchedulingTuning(highLoadPenaltyWhenLowEnergy: 2.0),
        ),
      );

      final high = plan.entries.firstWhere((e) => e.id == 'h');
      expect(_startMin(high) >= 14 * 60, isTrue);
    });

    test('uses contract order for due priority duration and id', () {
      final engine = HeuristicSchedulingEngine();
      final day = DateTime(2026, 6, 14);
      final tasks = [
        const PlanTask(id: 'no-due-short', title: 'Short', durationMinutes: 20, priority: 3, load: CognitiveLoad.low, tag: 'Task'),
        PlanTask(id: 'due-late', title: 'Late due', durationMinutes: 20, priority: 1, due: DateTime(2026, 6, 14, 12), load: CognitiveLoad.low, tag: 'Task'),
        const PlanTask(id: 'no-due-long', title: 'Long', durationMinutes: 30, priority: 3, load: CognitiveLoad.low, tag: 'Task'),
        PlanTask(id: 'due-early', title: 'Early due', durationMinutes: 20, priority: 1, due: DateTime(2026, 6, 14, 10), load: CognitiveLoad.low, tag: 'Task'),
        const PlanTask(id: 'no-due-high', title: 'High', durationMinutes: 20, priority: 5, load: CognitiveLoad.low, tag: 'Task'),
        const PlanTask(id: 'no-due-a', title: 'A', durationMinutes: 20, priority: 3, load: CognitiveLoad.low, tag: 'Task'),
      ];

      final plan = engine.plan(SchedulingRequest(
        day: day,
        tasks: tasks,
        windows: const [TimeWindow(start: TimeOfDay(hour: 8, minute: 0), end: TimeOfDay(hour: 18, minute: 0))],
        energy: EnergyTier.medium,
      ));

      expect(plan.entries.map((entry) => entry.id), [
        'due-early',
        'due-late',
        'no-due-high',
        'no-due-long',
        'no-due-a',
        'no-due-short',
      ]);
      expect(plan.entries.first.explanationCodes, ['deadline_proximity']);
      expect(plan.entries[2].explanationCodes, ['priority']);
      expect(plan.entries.every((entry) => entry.source == 'planned'), isTrue);
    });

    test('blocks missing dependencies and reports blocked ids', () {
      final plan = HeuristicSchedulingEngine().plan(SchedulingRequest(
        day: DateTime(2026, 6, 14),
        tasks: const [
          PlanTask(id: 'dependent', title: 'Dependent', durationMinutes: 30, priority: 5, load: CognitiveLoad.high, tag: 'Task', dependsOn: ['missing']),
        ],
        windows: const [TimeWindow(start: TimeOfDay(hour: 8, minute: 0), end: TimeOfDay(hour: 12, minute: 0))],
        energy: EnergyTier.high,
      ));

      expect(plan.entries, isEmpty);
      expect(plan.issues.single.code, 'dependency_blocked');
      expect(plan.issues.single.blockedBy, ['missing']);
      expect(plan.issues.single.explanationCodes, isEmpty);
    });

    test('honors earliest start and does not fallback hard deadlines past due', () {
      final plan = HeuristicSchedulingEngine().plan(SchedulingRequest(
        day: DateTime(2026, 6, 14),
        tasks: [
          PlanTask(id: 'late', title: 'Late', durationMinutes: 30, priority: 2, load: CognitiveLoad.low, tag: 'Task', earliestStart: DateTime(2026, 6, 14, 9)),
          PlanTask(id: 'hard', title: 'Hard', durationMinutes: 90, priority: 5, load: CognitiveLoad.high, tag: 'Task', due: DateTime(2026, 6, 14, 9), hardDeadline: true),
        ],
        windows: const [TimeWindow(start: TimeOfDay(hour: 8, minute: 0), end: TimeOfDay(hour: 10, minute: 0))],
        energy: EnergyTier.medium,
      ));

      expect(plan.entries.single.id, 'late');
      expect(plan.entries.single.time, const TimeOfDay(hour: 9, minute: 0));
      final issue = plan.issues.singleWhere((issue) => issue.taskId == 'hard');
      expect(issue.code, 'no_slot');
    });
  });
}

