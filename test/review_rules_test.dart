import 'package:flutter_test/flutter_test.dart';
import 'package:shixuzhipei/models/models.dart';
import 'package:shixuzhipei/services/review/review_rules.dart';

void main() {
  test('weekly report bumps duration multiplier for underestimated tags', () {
    final weekStart = DateTime(2026, 1, 5); // Monday

    final events = <TaskEvent>[];

    for (var i = 0; i < 5; i++) {
      final id = 't_$i';
      final at = weekStart.add(Duration(days: i, hours: 9));
      events.add(
        TaskEvent(
          id: 's_$id',
          taskId: id,
          title: 'Deep task',
          tag: 'Deep Work',
          at: at,
          type: TaskEventType.start,
          plannedMinutes: 60,
          energy: EnergyTier.medium,
        ),
      );
      events.add(
        TaskEvent(
          id: 'c_$id',
          taskId: id,
          title: 'Deep task',
          tag: 'Deep Work',
          at: at.add(const Duration(minutes: 96)),
          type: TaskEventType.complete,
          plannedMinutes: 60,
          actualMinutes: 96,
          interruptions: 0,
        ),
      );
    }

    final report = ReviewRules.weeklyReport(
      weekStart: weekStart,
      events: events,
      currentTuning: const SchedulingTuning(),
    );

    expect(report.tuning.tagDurationMultiplier['Deep Work'], isNotNull);
    expect(report.tuning.tagDurationMultiplier['Deep Work']!, greaterThan(1.0));
    expect(report.suggestions.isNotEmpty, isTrue);
  });

  test('weekly report bumps high-load penalty when low-energy high-load strain is frequent', () {
    final weekStart = DateTime(2026, 1, 5); // Monday

    final events = <TaskEvent>[];

    for (var i = 0; i < 4; i++) {
      final id = 'h_$i';
      final at = weekStart.add(Duration(days: i, hours: 9));
      events.add(
        TaskEvent(
          id: 's_$id',
          taskId: id,
          title: 'High load task',
          tag: 'Deep Work',
          load: CognitiveLoad.high,
          at: at,
          type: TaskEventType.start,
          plannedMinutes: 60,
          energy: EnergyTier.veryLow,
        ),
      );
      events.add(
        TaskEvent(
          id: 'c_$id',
          taskId: id,
          title: 'High load task',
          tag: 'Deep Work',
          load: CognitiveLoad.high,
          at: at.add(const Duration(minutes: 100)),
          type: TaskEventType.complete,
          plannedMinutes: 60,
          actualMinutes: 100,
          interruptions: 3,
        ),
      );
    }

    final report = ReviewRules.weeklyReport(
      weekStart: weekStart,
      events: events,
      currentTuning: const SchedulingTuning(highLoadPenaltyWhenLowEnergy: 1.0),
    );

    expect(report.tuning.highLoadPenaltyWhenLowEnergy, greaterThan(1.0));
    expect(
      report.suggestions.any((s) => s.contains('低能量') || s.contains('高负荷')),
      isTrue,
    );
  });

  test('monthly summary computes daily and weekly completion trends', () {
    final monthStart = DateTime(2026, 2, 1);
    final events = <TaskEvent>[];

    for (var i = 0; i < 6; i++) {
      final day = DateTime(2026, 2, i + 1, 9);
      events.add(
        TaskEvent(
          id: 's_$i',
          taskId: 'm_$i',
          title: 'Task $i',
          tag: 'Routine',
          at: day,
          type: TaskEventType.start,
          plannedMinutes: 40,
          energy: EnergyTier.medium,
        ),
      );
      if (i.isEven) {
        events.add(
          TaskEvent(
            id: 'c_$i',
            taskId: 'm_$i',
            title: 'Task $i',
            tag: 'Routine',
            at: day.add(const Duration(minutes: 35)),
            type: TaskEventType.complete,
            plannedMinutes: 40,
            actualMinutes: 35,
          ),
        );
      }
    }

    final summary = ReviewRules.monthlySummary(
      monthStart: monthStart,
      events: events,
    );

    expect(summary.startedCount, 6);
    expect(summary.completedCount, 3);
    expect(summary.completionRate, closeTo(0.5, 0.0001));
    expect(summary.dailyTrend.length, 28);
    expect(summary.weeklyCompletionRate.isNotEmpty, isTrue);
  });

  test('monthly summary identifies bottlenecks and emits actionable suggestions', () {
    final monthStart = DateTime(2026, 3, 1);
    final events = <TaskEvent>[];

    for (var i = 0; i < 5; i++) {
      final startAt = DateTime(2026, 3, i + 1, 10);
      events.add(
        TaskEvent(
          id: 's_int_$i',
          taskId: 'int_$i',
          title: 'Interrupted Task',
          tag: 'Deep Work',
          at: startAt,
          type: TaskEventType.start,
          plannedMinutes: 60,
          load: CognitiveLoad.high,
          energy: EnergyTier.medium,
        ),
      );
      events.add(
        TaskEvent(
          id: 'c_int_$i',
          taskId: 'int_$i',
          title: 'Interrupted Task',
          tag: 'Deep Work',
          at: startAt.add(const Duration(minutes: 70)),
          type: TaskEventType.complete,
          plannedMinutes: 60,
          actualMinutes: 70,
          interruptions: 4,
        ),
      );
    }

    final summary = ReviewRules.monthlySummary(
      monthStart: monthStart,
      events: events,
    );

    expect(summary.bottleneckAttribution['interruptions'], 5);
    expect(
      summary.suggestions.any((s) => s.contains('打断')),
      isTrue,
    );
  });
}
