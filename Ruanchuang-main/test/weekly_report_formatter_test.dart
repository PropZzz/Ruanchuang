import 'package:flutter_test/flutter_test.dart';
import 'package:sxzppp/models/models.dart';
import 'package:sxzppp/services/review/weekly_report_formatter.dart';

void main() {
  test('formatWeeklyReportMarkdown includes key sections and tuning', () {
    final report = ReviewReport(
      weekStart: DateTime(2026, 1, 5),
      weekEnd: DateTime(2026, 1, 12),
      startedCount: 10,
      completedCount: 7,
      completionRate: 0.7,
      plannedMinutesTotal: 600,
      actualMinutesTotal: 720,
      actualDurationBuckets: const {
        '<=15': 1,
        '16-30': 2,
        '31-60': 3,
        '61-120': 1,
        '121+': 0,
      },
      delayAttribution: const {
        'underestimated': 2,
        'interruptions': 1,
        'context_switch': 1,
        'unknown': 0,
      },
      suggestions: const ['Increase duration estimate for "Deep Work" tasks (+15%).'],
      tuning: const SchedulingTuning(
        defaultDurationMultiplier: 1.0,
        tagDurationMultiplier: {'Deep Work': 1.15},
        highLoadPenaltyWhenLowEnergy: 1.2,
      ),
    );

    final md = formatWeeklyReportMarkdown(report);
    expect(md, contains('Weekly Review'));
    expect(md, contains('Completion: 70% (7/10)'));
    expect(md, contains('planned 600m, actual 720m'));
    expect(md, contains('## Suggestions'));
    expect(md, contains('Deep Work'));
    expect(md, contains('highLoadPenaltyWhenLowEnergy: 1.20'));
  });
}

