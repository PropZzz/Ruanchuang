import '../../models/models.dart';

class ReviewRules {
  static ReviewReport weeklyReport({
    required DateTime weekStart,
    required List<TaskEvent> events,
    required SchedulingTuning currentTuning,
  }) {
    final start = DateTime(weekStart.year, weekStart.month, weekStart.day);
    final end = start.add(const Duration(days: 7));

    final inRange = events.where((e) => !e.at.isBefore(start) && e.at.isBefore(end)).toList();

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

      // Duration distribution buckets.
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

    // Build tuning adjustments.
    final nextMap = Map<String, double>.from(currentTuning.tagDurationMultiplier);
    final suggestions = <String>[];

    var nextHighLoadPenalty = currentTuning.highLoadPenaltyWhenLowEnergy;

    for (final entry in tagTotal.entries) {
      final tag = entry.key;
      final total = entry.value;
      final under = tagUnder[tag] ?? 0;

      if (total >= 2 && under / total >= 0.4) {
        final cur = nextMap[tag] ?? currentTuning.defaultDurationMultiplier;
        final bumped = (cur + 0.15).clamp(1.0, 1.8);
        nextMap[tag] = bumped;
        suggestions.add('Increase duration estimate for "$tag" tasks (+15%).');
      }
    }

    // High-load penalty tuning: if high-load tasks started under low energy
    // frequently overrun / get interrupted / fail to complete, make the planner
    // more conservative next week (push high-load work later / reduce load).
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
        nextHighLoadPenalty = (nextHighLoadPenalty + 0.2).clamp(1.0, 3.0);
        suggestions.add(
          'Low-energy high-load strain detected: strengthen high-load penalty (+0.2) for low energy days.',
        );
      } else if (strainRate <= 0.2 && nextHighLoadPenalty > 1.0) {
        nextHighLoadPenalty = (nextHighLoadPenalty - 0.1).clamp(1.0, 3.0);
      }
    }

    if ((attribution['interruptions'] ?? 0) >= 3) {
      suggestions.add('High interruption week: consider batching notifications and using shorter blocks.');
    }

    if (completionRate < 0.6 && startedCount >= 5) {
      suggestions.add('Low completion rate: reduce daily load or reserve buffer windows for interrupts.');
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
}
