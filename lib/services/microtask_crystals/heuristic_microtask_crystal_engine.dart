import 'package:flutter/material.dart';

import '../../models/models.dart';
import 'microtask_crystal_engine.dart';

class _Interval {
  final int start;
  final int end;

  const _Interval(this.start, this.end);

  int get minutes => end - start;
}

int _todToMin(TimeOfDay t) => t.hour * 60 + t.minute;

TimeOfDay _minToTod(int minutes) {
  final m = minutes.clamp(0, 24 * 60 - 1).toInt();
  return TimeOfDay(hour: m ~/ 60, minute: m % 60);
}

int _durationFromHeight(double height) {
  final mins = (height / 80.0) * 60.0;
  return mins.round().clamp(1, 24 * 60).toInt();
}

List<_Interval> _mergeBusy(List<_Interval> busy) {
  if (busy.isEmpty) return const [];
  busy.sort((a, b) => a.start.compareTo(b.start));
  final out = <_Interval>[];
  var curS = busy.first.start;
  var curE = busy.first.end;
  for (var i = 1; i < busy.length; i++) {
    final it = busy[i];
    if (it.start <= curE) {
      curE = it.end > curE ? it.end : curE;
      continue;
    }
    out.add(_Interval(curS, curE));
    curS = it.start;
    curE = it.end;
  }
  out.add(_Interval(curS, curE));
  return out;
}

List<_Interval> _subtractAll(_Interval window, List<_Interval> busy) {
  // busy must be merged.
  final out = <_Interval>[];
  var cursor = window.start;
  for (final b in busy) {
    if (b.end <= cursor) continue;
    if (b.start >= window.end) break;

    final s = b.start < window.start ? window.start : b.start;
    final e = b.end > window.end ? window.end : b.end;

    if (s > cursor) {
      out.add(_Interval(cursor, s));
    }
    if (e > cursor) {
      cursor = e;
    }
  }
  if (cursor < window.end) {
    out.add(_Interval(cursor, window.end));
  }
  return out.where((i) => i.minutes > 0).toList();
}

List<TimeCrystal> computeTimeCrystals({
  required List<ScheduleEntry> schedule,
  required List<TimeWindow> windows,
  required TimeOfDay now,
}) {
  final busy = <_Interval>[];
  for (final e in schedule) {
    final s = _todToMin(e.time);
    final d = _durationFromHeight(e.height);
    final end = (s + d).clamp(0, 24 * 60).toInt();
    busy.add(_Interval(s, end));
  }

  final merged = _mergeBusy(busy);

  final nowMin = _todToMin(now);
  final crystals = <TimeCrystal>[];

  for (final w in windows) {
    final ws = _todToMin(w.start);
    final we = _todToMin(w.end);
    if (we <= ws) continue;

    final window = _Interval(ws, we);
    final free = _subtractAll(window, merged);
    for (final f in free) {
      final start = f.start < nowMin ? nowMin : f.start;
      if (start >= f.end) continue;
      crystals.add(
        TimeCrystal(
          start: _minToTod(start),
          minutes: f.end - start,
        ),
      );
    }
  }

  crystals.sort((a, b) => _todToMin(a.start).compareTo(_todToMin(b.start)));
  return crystals;
}

class HeuristicMicroTaskCrystalEngine implements MicroTaskCrystalEngine {
  @override
  List<TimeCrystalRecommendation> recommend({
    required List<ScheduleEntry> schedule,
    required List<MicroTask> microTasks,
    required List<TimeWindow> windows,
    required EnergyTier energy,
    required TimeOfDay now,
    int maxRecommendations = 5,
  }) {
    final crystals = computeTimeCrystals(
      schedule: schedule,
      windows: windows,
      now: now,
    );

    final candidates = microTasks.where((t) => !t.done).toList();

    // Greedy near-optimal: fill small gaps first.
    crystals.sort((a, b) => a.minutes.compareTo(b.minutes));

    final recs = <TimeCrystalRecommendation>[];

    for (final c in crystals) {
      if (recs.length >= maxRecommendations) break;

      double bestScore = double.negativeInfinity;
      MicroTask? best;

      for (final t in candidates) {
        final score = _score(t, c, energy);
        if (score > bestScore) {
          bestScore = score;
          best = t;
        }
      }

      if (best == null || bestScore.isInfinite && bestScore.isNegative) {
        continue;
      }

      // Consume the task so we don't recommend it twice.
      candidates.remove(best);
      recs.add(TimeCrystalRecommendation(crystal: c, task: best, score: bestScore));
    }

    // Present in time order.
    recs.sort((a, b) => _todToMin(a.crystal.start).compareTo(_todToMin(b.crystal.start)));
    return recs;
  }

  double _score(MicroTask t, TimeCrystal c, EnergyTier energy) {
    if (t.minutes <= 0) return double.negativeInfinity;
    if (t.minutes > c.minutes) return double.negativeInfinity;

    final waste = c.minutes - t.minutes;
    final fit = 1.0 - (waste / c.minutes);

    var score = fit * 10.0 - waste * 0.05;

    // Priority: keep it a soft preference so "fit" still dominates.
    score += (t.priority.clamp(1, 5).toInt() - 3) * 0.6;

    if (energy == EnergyTier.veryLow || energy == EnergyTier.low) {
      if (t.minutes <= 15) score += 2.0;
      if ((t.tag).toLowerCase().contains('low')) score += 1.0;
    }

    // Prefer finishing a gap cleanly.
    if (waste == 0) score += 1.0;

    return score;
  }
}
