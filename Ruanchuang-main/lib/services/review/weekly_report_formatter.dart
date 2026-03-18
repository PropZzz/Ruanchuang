import '../../models/models.dart';

String formatWeeklyReportMarkdown(ReviewReport r) {
  final b = StringBuffer();
  final start = r.weekStart.toLocal().toIso8601String().split('T').first;
  final end = r.weekEnd.toLocal().toIso8601String().split('T').first;

  b.writeln('# Weekly Review ($start to $end)');
  b.writeln();
  b.writeln(
    '- Completion: ${(r.completionRate * 100).round()}% (${r.completedCount}/${r.startedCount})',
  );
  b.writeln(
    '- Time: planned ${r.plannedMinutesTotal}m, actual ${r.actualMinutesTotal}m',
  );
  b.writeln();

  b.writeln('## Actual Duration Buckets');
  for (final k in const ['<=15', '16-30', '31-60', '61-120', '121+']) {
    final v = r.actualDurationBuckets[k] ?? 0;
    b.writeln('- $k: $v');
  }
  b.writeln();

  b.writeln('## Delay Attribution');
  final keys = r.delayAttribution.keys.toList()..sort();
  for (final k in keys) {
    b.writeln('- $k: ${r.delayAttribution[k] ?? 0}');
  }
  b.writeln();

  b.writeln('## Suggestions');
  if (r.suggestions.isEmpty) {
    b.writeln('- (none)');
  } else {
    for (final s in r.suggestions) {
      b.writeln('- $s');
    }
  }
  b.writeln();

  b.writeln('## Scheduling Tuning (Applied Next)');
  b.writeln(
    '- defaultDurationMultiplier: ${r.tuning.defaultDurationMultiplier.toStringAsFixed(2)}',
  );
  b.writeln(
    '- highLoadPenaltyWhenLowEnergy: ${r.tuning.highLoadPenaltyWhenLowEnergy.toStringAsFixed(2)}',
  );
  if (r.tuning.tagDurationMultiplier.isEmpty) {
    b.writeln('- tagDurationMultiplier: (none)');
  } else {
    final entries = r.tuning.tagDurationMultiplier.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    for (final e in entries) {
      b.writeln(
        '- tagDurationMultiplier[${e.key}]: ${e.value.toStringAsFixed(2)}',
      );
    }
  }

  return b.toString();
}

