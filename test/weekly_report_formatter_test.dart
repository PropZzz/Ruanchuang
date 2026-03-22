import 'package:flutter_test/flutter_test.dart';
import 'package:shixuzhipei/models/models.dart';
import 'package:shixuzhipei/services/review/weekly_report_formatter.dart';

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
      suggestions: const ['建议为“Deep Work”类任务上调时长预估（+15%）。'],
      tuning: const SchedulingTuning(
        defaultDurationMultiplier: 1.0,
        tagDurationMultiplier: {'Deep Work': 1.15},
        highLoadPenaltyWhenLowEnergy: 1.2,
      ),
    );

    final md = formatWeeklyReportMarkdown(report);
    expect(md, contains('周复盘'));
    expect(md, contains('完成率：70%（7/10）'));
    expect(md, contains('计划 600 分钟，实际 720 分钟'));
    expect(md, contains('## 建议'));
    expect(md, contains('Deep Work'));
    expect(md, contains('低能量时高负荷惩罚：1.20'));
  });
}

