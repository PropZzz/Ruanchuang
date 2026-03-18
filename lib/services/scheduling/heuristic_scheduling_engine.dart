import 'package:flutter/material.dart';

import '../../models/models.dart';
import 'scheduling_engine.dart';

class _Interval {
  final int startMin;
  final int endMin;

  const _Interval(this.startMin, this.endMin);

  int get length => endMin - startMin;
}

int _todToMin(TimeOfDay t) => t.hour * 60 + t.minute;

TimeOfDay _minToTod(int minutes) {
  final m = minutes.clamp(0, 24 * 60 - 1);
  return TimeOfDay(hour: m ~/ 60, minute: m % 60);
}

int _durationFromHeight(double height) {
  // 80.0 ~= 60 minutes
  final mins = (height / 80.0) * 60.0;
  return mins.round().clamp(1, 24 * 60);
}

double _heightFromDuration(int minutes) {
  final h = (minutes / 60.0) * 80.0;
  return h.clamp(20.0, 24 * 60 * 80.0);
}

Color _colorForLoad(CognitiveLoad load) {
  switch (load) {
    case CognitiveLoad.high:
      return Colors.teal;
    case CognitiveLoad.medium:
      return Colors.blue;
    case CognitiveLoad.low:
      return Colors.orange;
  }
}

/// P0 heuristic scheduling engine.
///
/// Algorithm overview:
/// - Conflict resolution: represent available windows as free intervals, subtract
///   fixed blocks, then greedily place tasks and split intervals.
/// - Deadline constraints: tasks with nearer deadlines are scheduled first; a
///   task is only placed in slots that end before its due time when possible.
/// - Energy matching: when energy is low, bias low cognitive-load tasks earlier;
///   when energy is high, bias high-load tasks earlier (especially in morning).
class HeuristicSchedulingEngine implements SchedulingEngine {
  @override
  SchedulingPlan plan(SchedulingRequest request) {
    final issues = <SchedulingIssue>[];

    final day = DateTime(request.day.year, request.day.month, request.day.day);
    final energy = request.energy;
    final tuning = request.tuning;

    final fixed = List<ScheduleEntry>.from(request.fixed);
    fixed.sort((a, b) => _todToMin(a.time).compareTo(_todToMin(b.time)));

    // Build free intervals from windows.
    final free = <_Interval>[];
    for (final w in request.windows) {
      final s = _todToMin(w.start);
      final e = _todToMin(w.end);
      if (e <= s) continue;
      free.add(_Interval(s, e));
    }

    // Subtract fixed blocks (hard constraints).
    for (final f in fixed) {
      final s = _todToMin(f.time);
      final d = _durationFromHeight(f.height);
      final e = (s + d).clamp(0, 24 * 60);
      _subtractInterval(free, _Interval(s, e));
    }

    // Sort tasks by urgency/priority.
    final tasks = List<PlanTask>.from(request.tasks);
    tasks.sort((a, b) {
      final aDue = a.due;
      final bDue = b.due;
      final aDueMin = (aDue != null && _isSameDay(aDue, day)) ? aDue.hour * 60 + aDue.minute : null;
      final bDueMin = (bDue != null && _isSameDay(bDue, day)) ? bDue.hour * 60 + bDue.minute : null;

      if (aDueMin != null && bDueMin != null && aDueMin != bDueMin) {
        return aDueMin.compareTo(bDueMin);
      }
      if (aDueMin != null && bDueMin == null) return -1;
      if (aDueMin == null && bDueMin != null) return 1;

      final p = b.priority.compareTo(a.priority);
      if (p != 0) return p;

      // When priorities tie, bias load order based on current energy.
      if (energy == EnergyTier.veryLow || energy == EnergyTier.low) {
        // Low energy: place lighter tasks earlier.
        return a.load.index.compareTo(b.load.index);
      }

      // Medium/high energy: heavier tasks are harder to place, schedule earlier.
      return b.load.index.compareTo(a.load.index);
    });

    final planned = <ScheduleEntry>[];

    for (final t in tasks) {
      final dur = t.durationMinutes.clamp(1, 24 * 60).toInt();
      final dueMin = (t.due != null && _isSameDay(t.due!, day))
          ? (t.due!.hour * 60 + t.due!.minute)
          : null;

      final placement = _pickSlot(
        free: free,
        duration: dur,
        dueMin: dueMin,
        energy: energy,
        load: t.load,
        tuning: tuning,
      );

      if (placement == null) {
        issues.add(
          SchedulingIssue(
            code: 'no_slot',
            message: 'No available slot for task: ${t.title}',
            taskId: t.id,
          ),
        );
        continue;
      }

      // Allocate.
      _subtractInterval(free, _Interval(placement, placement + dur));

      planned.add(
        ScheduleEntry(
          id: t.id,
          title: t.title,
          tag: t.tag,
          load: t.load,
          height: _heightFromDuration(dur),
          color: _colorForLoad(t.load),
          time: _minToTod(placement),
        ),
      );

      // If we missed a due time, record an issue (still scheduled).
      if (dueMin != null && placement + dur > dueMin) {
        issues.add(
          SchedulingIssue(
            code: 'miss_due',
            message: 'Task scheduled past due time: ${t.title}',
            taskId: t.id,
          ),
        );
      }
    }

    // Final output: fixed blocks + planned, sorted.
    final out = <ScheduleEntry>[...fixed, ...planned];
    out.sort((a, b) => _todToMin(a.time).compareTo(_todToMin(b.time)));

    return SchedulingPlan(entries: out, issues: issues);
  }

  bool _isSameDay(DateTime a, DateTime day) {
    return a.year == day.year && a.month == day.month && a.day == day.day;
  }

  int? _pickSlot({
    required List<_Interval> free,
    required int duration,
    required int? dueMin,
    required EnergyTier energy,
    required CognitiveLoad load,
    required SchedulingTuning tuning,
  }) {
    int? bestStart;
    double bestScore = double.negativeInfinity;

    for (final it in free) {
      if (it.length < duration) continue;

      final start = it.startMin;
      final end = start + duration;

      if (dueMin != null && end > dueMin) {
        // For P0 we only try interval starts; if that misses due, skip.
        continue;
      }

      final score = _scorePlacement(
        startMin: start,
        energy: energy,
        load: load,
        tuning: tuning,
      );

      if (score > bestScore) {
        bestScore = score;
        bestStart = start;
      }
    }

    if (bestStart != null) return bestStart;

    // Fallback: if dueMin blocks everything, schedule at earliest available.
    for (final it in free) {
      if (it.length >= duration) {
        return it.startMin;
      }
    }

    return null;
  }

  double _scorePlacement({
    required int startMin,
    required EnergyTier energy,
    required CognitiveLoad load,
    required SchedulingTuning tuning,
  }) {
    final hour = startMin ~/ 60;
    final isMorning = hour < 12;
    final isAfternoon = hour >= 12 && hour < 17;

    // Base preference: earlier is slightly better (keeps tail room).
    var score = -startMin / 1000.0;

    switch (energy) {
      case EnergyTier.veryHigh:
      case EnergyTier.high:
        if (load == CognitiveLoad.high && isMorning) score += 5;
        if (load == CognitiveLoad.medium && isAfternoon) score += 2;
        if (load == CognitiveLoad.low) score += 0.5;
        break;
      case EnergyTier.medium:
        if (load == CognitiveLoad.high && isMorning) score += 2;
        if (load == CognitiveLoad.medium) score += 2;
        if (load == CognitiveLoad.low) score += 1;
        break;
      case EnergyTier.low:
      case EnergyTier.veryLow:
        // Tuning: when a user consistently struggles with high-load tasks while
        // low-energy, we amplify the penalty and bias away from mornings.
        final p = tuning.highLoadPenaltyWhenLowEnergy.clamp(1.0, 3.0);
        final extra = (p - 1.0).clamp(0.0, 10.0);
        if (load == CognitiveLoad.high) {
          score -= 5 * p;
          if (isMorning) score -= 2.0 * extra;
        }
        if (load == CognitiveLoad.medium) score -= 1;
        if (load == CognitiveLoad.low) score += 3;
        break;
    }

    return score;
  }

  void _subtractInterval(List<_Interval> free, _Interval used) {
    // Remove any overlap with [used] by splitting.
    for (var i = 0; i < free.length; i++) {
      final it = free[i];

      final s = it.startMin;
      final e = it.endMin;

      final os = used.startMin;
      final oe = used.endMin;

      if (oe <= s || os >= e) continue;

      final left = (os > s) ? _Interval(s, os) : null;
      final right = (oe < e) ? _Interval(oe, e) : null;

      free.removeAt(i);
      if (right != null) {
        free.insert(i, right);
      }
      if (left != null) {
        free.insert(i, left);
        i++;
      }
      i--;
    }

    free.sort((a, b) => a.startMin.compareTo(b.startMin));

    // Merge adjacent/overlapping intervals.
    for (var i = 0; i < free.length - 1; i++) {
      final a = free[i];
      final b = free[i + 1];
      if (a.endMin >= b.startMin) {
        final end = a.endMin > b.endMin ? a.endMin : b.endMin;
        free[i] = _Interval(a.startMin, end);
        free.removeAt(i + 1);
        i--;
      }
    }
  }
}
