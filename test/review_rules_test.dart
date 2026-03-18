import 'package:flutter_test/flutter_test.dart';
import 'package:sxzppp/models/models.dart';
import 'package:sxzppp/services/review/review_rules.dart';

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
      report.suggestions.any((s) => s.contains('high-load penalty')),
      isTrue,
    );
  });
}
