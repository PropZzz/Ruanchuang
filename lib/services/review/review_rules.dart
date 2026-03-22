import '../../models/models.dart';

class DailyReviewPoint {
  final DateTime day;
  final int started;
  final int completed;
  final int plannedMinutes;
  final int actualMinutes;

  const DailyReviewPoint({
    required this.day,
    required this.started,
    required this.completed,
    required this.plannedMinutes,
    required this.actualMinutes,
  });

  double get completionRate => started == 0 ? 0.0 : completed / started;
}

class MonthReviewSummary {
  final DateTime monthStart;
  final DateTime monthEnd;
  final int startedCount;
  final int completedCount;
  final double completionRate;
  final int plannedMinutesTotal;
  final int actualMinutesTotal;
  final Map<String, int> actualDurationBuckets;
  final Map<String, int> bottleneckAttribution;
  final Map<String, double> weeklyCompletionRate;
  final List<DailyReviewPoint> dailyTrend;
  final List<String> suggestions;

  const MonthReviewSummary({
    required this.monthStart,
    required this.monthEnd,
    required this.startedCount,
    required this.completedCount,
    required this.completionRate,
    required this.plannedMinutesTotal,
    required this.actualMinutesTotal,
    required this.actualDurationBuckets,
    required this.bottleneckAttribution,
    required this.weeklyCompletionRate,
    required this.dailyTrend,
    required this.suggestions,
  });
}

class ReviewRules {
  static ReviewReport weeklyReport({
    required DateTime weekStart,
    required List<TaskEvent> events,
    required SchedulingTuning currentTuning,
  }) {
    final start = DateTime(weekStart.year, weekStart.month, weekStart.day);
    final end = start.add(const Duration(days: 7));

    final inRange =
        events.where((e) => !e.at.isBefore(start) && e.at.isBefore(end)).toList();

    final started = <String, TaskEvent>{};
    final completed = <String, TaskEvent>{};
    final postpones = <String, List<TaskEvent>>{};

    for (final e in inRange) {
      if (e.type == TaskEventType.start) {
        started[e.taskId] = e;
      } else if (e.type == TaskEventType.complete) {
        completed[e.taskId] = e;
      } else if (e.type == TaskEventType.postpone) {
        (postpones[e.taskId] ??= []).add(e);
      }
    }

    int plannedTotal = 0;
    int actualTotal = 0;

    final buckets = <String, int>{
      '<=15': 0,
      '16-30': 0,
      '31-60': 0,
      '61-120': 0,
      '121+': 0,
    };

    final attribution = <String, int>{
      'underestimated': 0,
      'interruptions': 0,
      'context_switch': 0,
      'unknown': 0,
    };

    final tagUnder = <String, int>{};
    final tagTotal = <String, int>{};

    for (final taskId in started.keys) {
      final s = started[taskId]!;
      final c = completed[taskId];

      final planned = s.plannedMinutes ?? 0;
      plannedTotal += planned;

      if (c == null) continue;

      final actual = c.actualMinutes ?? planned;
      actualTotal += actual;

      final tag = s.tag;
      tagTotal[tag] = (tagTotal[tag] ?? 0) + 1;

      if (actual <= 15) {
        buckets['<=15'] = buckets['<=15']! + 1;
      } else if (actual <= 30) {
        buckets['16-30'] = buckets['16-30']! + 1;
      } else if (actual <= 60) {
        buckets['31-60'] = buckets['31-60']! + 1;
      } else if (actual <= 120) {
        buckets['61-120'] = buckets['61-120']! + 1;
      } else {
        buckets['121+'] = buckets['121+']! + 1;
      }

      final interrupts = c.interruptions ?? 0;
      final postCount = postpones[taskId]?.length ?? 0;

      final underestimated = (planned > 0) && (actual > (planned * 1.3));

      if (interrupts >= 3) {
        attribution['interruptions'] = attribution['interruptions']! + 1;
      } else if (underestimated) {
        attribution['underestimated'] = attribution['underestimated']! + 1;
        tagUnder[tag] = (tagUnder[tag] ?? 0) + 1;
      } else if (postCount >= 2) {
        attribution['context_switch'] = attribution['context_switch']! + 1;
      } else {
        attribution['unknown'] = attribution['unknown']! + 1;
      }
    }

    final startedCount = started.length;
    final completedCount = completed.length;
    final completionRate = startedCount == 0 ? 0.0 : (completedCount / startedCount);

    final nextMap = Map<String, double>.from(currentTuning.tagDurationMultiplier);
    final suggestions = <String>[];

    var nextHighLoadPenalty = currentTuning.highLoadPenaltyWhenLowEnergy;

    for (final entry in tagTotal.entries) {
      final tag = entry.key;
      final total = entry.value;
      final under = tagUnder[tag] ?? 0;

      if (total >= 2 && under / total >= 0.4) {
        final cur = nextMap[tag] ?? currentTuning.defaultDurationMultiplier;
        final bumped = (cur + 0.15).clamp(1.0, 1.8).toDouble();
        nextMap[tag] = bumped;
        suggestions.add('建议为“$tag”类任务上调时长预估（+15%）。');
      }
    }

    var lowEnergyHighLoadTotal = 0;
    var lowEnergyHighLoadStrained = 0;

    bool isLowEnergy(EnergyTier? e) =>
        e == EnergyTier.low || e == EnergyTier.veryLow;

    for (final taskId in started.keys) {
      final s = started[taskId]!;
      if (!isLowEnergy(s.energy)) continue;
      if (s.load != CognitiveLoad.high) continue;

      lowEnergyHighLoadTotal++;

      final c = completed[taskId];
      if (c == null) {
        lowEnergyHighLoadStrained++;
        continue;
      }

      final planned = s.plannedMinutes ?? 0;
      final actual = c.actualMinutes ?? planned;
      final interrupts = c.interruptions ?? 0;
      final postCount = postpones[taskId]?.length ?? 0;

      final overrun = planned > 0 && actual > (planned * 1.3);
      final strained = overrun || interrupts >= 3 || postCount >= 2;
      if (strained) lowEnergyHighLoadStrained++;
    }

    if (lowEnergyHighLoadTotal >= 3) {
      final strainRate = lowEnergyHighLoadStrained / lowEnergyHighLoadTotal;
      if (strainRate >= 0.5) {
        nextHighLoadPenalty =
            (nextHighLoadPenalty + 0.2).clamp(1.0, 3.0).toDouble();
        suggestions.add(
          '检测到低能量状态下的高负荷压力，建议将低能量时的高负荷惩罚提高 0.2。',
        );
      } else if (strainRate <= 0.2 && nextHighLoadPenalty > 1.0) {
        nextHighLoadPenalty =
            (nextHighLoadPenalty - 0.1).clamp(1.0, 3.0).toDouble();
      }
    }

    if ((attribution['interruptions'] ?? 0) >= 3) {
      suggestions.add(
        '本周打断较多，建议批量处理通知，并将任务切分为更短的块。',
      );
    }

    if (completionRate < 0.6 && startedCount >= 5) {
      suggestions.add(
        '完成率偏低，建议降低每日负荷，或预留缓冲时间应对打断。',
      );
    }

    final tuning = SchedulingTuning(
      defaultDurationMultiplier: currentTuning.defaultDurationMultiplier,
      tagDurationMultiplier: nextMap,
      highLoadPenaltyWhenLowEnergy: nextHighLoadPenalty,
    );

    return ReviewReport(
      weekStart: start,
      weekEnd: end,
      startedCount: startedCount,
      completedCount: completedCount,
      completionRate: completionRate,
      plannedMinutesTotal: plannedTotal,
      actualMinutesTotal: actualTotal,
      actualDurationBuckets: buckets,
      delayAttribution: attribution,
      suggestions: suggestions,
      tuning: tuning,
    );
  }

  static MonthReviewSummary monthlySummary({
    required DateTime monthStart,
    required List<TaskEvent> events,
  }) {
    final start = DateTime(monthStart.year, monthStart.month, 1);
    final end = DateTime(start.year, start.month + 1, 1);

    final inRange =
        events.where((e) => !e.at.isBefore(start) && e.at.isBefore(end)).toList();

    final started = <String, TaskEvent>{};
    final completed = <String, TaskEvent>{};
    final postpones = <String, List<TaskEvent>>{};

    for (final e in inRange) {
      if (e.type == TaskEventType.start) {
        started[e.taskId] = e;
      } else if (e.type == TaskEventType.complete) {
        completed[e.taskId] = e;
      } else if (e.type == TaskEventType.postpone) {
        (postpones[e.taskId] ??= []).add(e);
      }
    }

    int plannedTotal = 0;
    int actualTotal = 0;

    final buckets = <String, int>{
      '<=15': 0,
      '16-30': 0,
      '31-60': 0,
      '61-120': 0,
      '121+': 0,
    };

    final bottlenecks = <String, int>{
      'underestimated': 0,
      'interruptions': 0,
      'context_switch': 0,
      'carry_over': 0,
    };

    final byDayStarted = <DateTime, int>{};
    final byDayCompleted = <DateTime, int>{};
    final byDayPlanned = <DateTime, int>{};
    final byDayActual = <DateTime, int>{};
    final byWeekStarted = <DateTime, int>{};
    final byWeekCompleted = <DateTime, int>{};

    DateTime dayOf(DateTime dt) => DateTime(dt.year, dt.month, dt.day);
    DateTime weekOf(DateTime dt) {
      final d = dayOf(dt);
      final delta = (d.weekday + 6) % 7;
      return d.subtract(Duration(days: delta));
    }

    for (final taskId in started.keys) {
      final s = started[taskId]!;
      final c = completed[taskId];

      final day = dayOf(s.at);
      final week = weekOf(s.at);

      byDayStarted[day] = (byDayStarted[day] ?? 0) + 1;
      byWeekStarted[week] = (byWeekStarted[week] ?? 0) + 1;

      final planned = s.plannedMinutes ?? 0;
      plannedTotal += planned;
      byDayPlanned[day] = (byDayPlanned[day] ?? 0) + planned;

      if (c == null) {
        bottlenecks['carry_over'] = bottlenecks['carry_over']! + 1;
        continue;
      }

      final actual = c.actualMinutes ?? planned;
      actualTotal += actual;
      byDayActual[day] = (byDayActual[day] ?? 0) + actual;
      byDayCompleted[day] = (byDayCompleted[day] ?? 0) + 1;
      byWeekCompleted[week] = (byWeekCompleted[week] ?? 0) + 1;

      if (actual <= 15) {
        buckets['<=15'] = buckets['<=15']! + 1;
      } else if (actual <= 30) {
        buckets['16-30'] = buckets['16-30']! + 1;
      } else if (actual <= 60) {
        buckets['31-60'] = buckets['31-60']! + 1;
      } else if (actual <= 120) {
        buckets['61-120'] = buckets['61-120']! + 1;
      } else {
        buckets['121+'] = buckets['121+']! + 1;
      }

      final interrupts = c.interruptions ?? 0;
      final postCount = postpones[taskId]?.length ?? 0;
      final underestimated = (planned > 0) && (actual > (planned * 1.3));

      if (interrupts >= 3) {
        bottlenecks['interruptions'] = bottlenecks['interruptions']! + 1;
      } else if (underestimated) {
        bottlenecks['underestimated'] = bottlenecks['underestimated']! + 1;
      } else if (postCount >= 2) {
        bottlenecks['context_switch'] = bottlenecks['context_switch']! + 1;
      }
    }

    final startedCount = started.length;
    final completedCount = completed.length;
    final completionRate = startedCount == 0 ? 0.0 : completedCount / startedCount;

    final dailyTrend = <DailyReviewPoint>[];
    for (var day = start; day.isBefore(end); day = day.add(const Duration(days: 1))) {
      final d = DateTime(day.year, day.month, day.day);
      dailyTrend.add(
        DailyReviewPoint(
          day: d,
          started: byDayStarted[d] ?? 0,
          completed: byDayCompleted[d] ?? 0,
          plannedMinutes: byDayPlanned[d] ?? 0,
          actualMinutes: byDayActual[d] ?? 0,
        ),
      );
    }

    final weekStarts = byWeekStarted.keys.toList()..sort();
    final weeklyCompletionRate = <String, double>{};
    for (final w in weekStarts) {
      final ws = byWeekStarted[w] ?? 0;
      final wc = byWeekCompleted[w] ?? 0;
      weeklyCompletionRate['${w.month}/${w.day}'] = ws == 0 ? 0.0 : wc / ws;
    }

    final suggestions = <String>[];
    final interruptionCount = bottlenecks['interruptions'] ?? 0;
    final underCount = bottlenecks['underestimated'] ?? 0;
    final contextCount = bottlenecks['context_switch'] ?? 0;
    final carryOverCount = bottlenecks['carry_over'] ?? 0;

    if (interruptionCount >= 4) {
      suggestions.add(
        '打断是本月最主要的瓶颈，建议批量处理通知并预留专注窗口。',
      );
    }
    if (underCount >= 4) {
      suggestions.add(
        '检测到多次低估时长，建议将同类任务的默认预估上调 15% - 20%。',
      );
    }
    if (contextCount >= 4) {
      suggestions.add(
        '上下文切换偏多，建议将相似任务归类到专门的执行窗口中。',
      );
    }
    if (carryOverCount >= 4) {
      suggestions.add(
        '有较多任务被顺延，建议降低每日在制任务量，并增加一个保护性缓冲槽。',
      );
    }
    if (completionRate < 0.65 && startedCount >= 12) {
      suggestions.add(
        '月度完成率偏低，建议先收缩每周承诺，再新增任务。',
      );
    }

    return MonthReviewSummary(
      monthStart: start,
      monthEnd: end,
      startedCount: startedCount,
      completedCount: completedCount,
      completionRate: completionRate,
      plannedMinutesTotal: plannedTotal,
      actualMinutesTotal: actualTotal,
      actualDurationBuckets: buckets,
      bottleneckAttribution: bottlenecks,
      weeklyCompletionRate: weeklyCompletionRate,
      dailyTrend: dailyTrend,
      suggestions: suggestions,
    );
  }
}
