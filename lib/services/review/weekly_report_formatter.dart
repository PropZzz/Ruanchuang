import '../../models/models.dart';

String formatWeeklyReportMarkdown(ReviewReport r) {
  final b = StringBuffer();
  final start = r.weekStart.toLocal().toIso8601String().split('T').first;
  final end = r.weekEnd.toLocal().toIso8601String().split('T').first;

  b.writeln('# 周复盘（$start 至 $end）');
  b.writeln();
  b.writeln(
    '- 完成率：${(r.completionRate * 100).round()}%（${r.completedCount}/${r.startedCount}）',
  );
  b.writeln(
    '- 时间：计划 ${r.plannedMinutesTotal} 分钟，实际 ${r.actualMinutesTotal} 分钟',
  );
  b.writeln();

  b.writeln('## 实际时长分布');
  for (final k in const ['<=15', '16-30', '31-60', '61-120', '121+']) {
    final v = r.actualDurationBuckets[k] ?? 0;
    b.writeln('- $k: $v');
  }
  b.writeln();

  b.writeln('## 延误归因');
  final keys = r.delayAttribution.keys.toList()..sort();
  for (final k in keys) {
    b.writeln('- $k: ${r.delayAttribution[k] ?? 0}');
  }
  b.writeln();

  b.writeln('## 建议');
  if (r.suggestions.isEmpty) {
    b.writeln('- （无）');
  } else {
    for (final s in r.suggestions) {
      b.writeln('- $s');
    }
  }
  b.writeln();

  b.writeln('## 调度参数（下次生效）');
  b.writeln(
    '- 默认时长倍率：${r.tuning.defaultDurationMultiplier.toStringAsFixed(2)}',
  );
  b.writeln(
    '- 低能量时高负荷惩罚：${r.tuning.highLoadPenaltyWhenLowEnergy.toStringAsFixed(2)}',
  );
  if (r.tuning.tagDurationMultiplier.isEmpty) {
    b.writeln('- 标签时长倍率：（无）');
  } else {
    final entries = r.tuning.tagDurationMultiplier.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    for (final e in entries) {
      b.writeln(
        '- 标签时长倍率[${e.key}]：${e.value.toStringAsFixed(2)}',
      );
    }
  }

  return b.toString();
}

