import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../utils/schedule_occurrence.dart';
import 'scheduling_engine.dart';

class _Interval {
  final int startMin;
  final int endMin;

  const _Interval(this.startMin, this.endMin);

  int get length => endMin - startMin;
}

class _Placement {
  final int startMin;
  final int duration;

  const _Placement(this.startMin, this.duration);
}

int _todToMin(TimeOfDay t) => t.hour * 60 + t.minute;

TimeOfDay _minToTod(int minutes) {
  final m = minutes.clamp(0, 24 * 60 - 1).toInt();
  return TimeOfDay(hour: m ~/ 60, minute: m % 60);
}

int _durationFromHeight(double height) {
  // 80.0 ~= 60 minutes
  final mins = (height / 80.0) * 60.0;
  return mins.round().clamp(1, 24 * 60).toInt();
}

double _heightFromDuration(int minutes) {
  final h = (minutes / 60.0) * 80.0;
  return h.clamp(20.0, 24 * 60 * 80.0).toDouble();
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

int _taskDueRank(PlanTask task, DateTime day) {
  if (task.due == null) return 2;
  return sameDay(task.due!, day) ? 0 : 1;
}

int _taskDueValue(PlanTask task, DateTime day) {
  if (task.due == null) return 1 << 30;
  if (sameDay(task.due!, day)) {
    return task.due!.hour * 60 + task.due!.minute;
  }
  return task.due!.millisecondsSinceEpoch ~/ 60000;
}

int _compareTasks(PlanTask a, PlanTask b, DateTime day) {
  final dueRank = _taskDueRank(a, day).compareTo(_taskDueRank(b, day));
  if (dueRank != 0) return dueRank;
  final due = _taskDueValue(a, day).compareTo(_taskDueValue(b, day));
  if (due != 0) return due;
  final priority = b.priority.compareTo(a.priority);
  if (priority != 0) return priority;
  final duration = b.durationMinutes.compareTo(a.durationMinutes);
  if (duration != 0) return duration;
  return a.id.compareTo(b.id);
}

int? _earliestStartMinutes(PlanTask task, DateTime day) {
  final earliest = task.earliestStart;
  if (earliest == null) return null;
  final startDay = DateTime(earliest.year, earliest.month, earliest.day);
  final requestDay = DateTime(day.year, day.month, day.day);
  if (startDay.isAfter(requestDay)) return 24 * 60;
  if (sameDay(earliest, day)) return earliest.hour * 60 + earliest.minute;
  return null;
}

List<String> _explanationCodes(PlanTask task, EnergyTier energy) {
  final codes = <String>[task.due == null ? 'priority' : 'deadline_proximity'];
  if ((energy == EnergyTier.low || energy == EnergyTier.veryLow) &&
      task.load == CognitiveLoad.low) {
    codes.add('energy_fit');
  }
  return codes;
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
class SchedulerCore implements SchedulingEngine {
  const SchedulerCore();

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

    // Fixed entries are immutable hard constraints. Keep them in the output,
    // but report overlaps and entries that do not belong to any work window.
    for (var index = 0; index < fixed.length; index++) {
      final entry = fixed[index];
      final start = _todToMin(entry.time);
      final end = (start + _durationFromHeight(entry.height))
          .clamp(0, 24 * 60)
          .toInt();
      final overlaps = fixed.take(index).any((other) {
        final otherStart = _todToMin(other.time);
        final otherEnd = (otherStart + _durationFromHeight(other.height))
            .clamp(0, 24 * 60)
            .toInt();
        return start < otherEnd && otherStart < end;
      });
      final inWindow = request.windows.any((window) {
        final windowStart = _todToMin(window.start);
        final windowEnd = _todToMin(window.end);
        return windowEnd > windowStart &&
            start >= windowStart &&
            end <= windowEnd;
      });
      if (overlaps || !inWindow) {
        issues.add(
          SchedulingIssue(
            code: 'fixed_conflict',
            message: overlaps
                ? 'Fixed entries overlap: ${entry.title}'
                : 'Fixed entry is outside all work windows: ${entry.title}',
            taskId: entry.id,
            explanationCodes: const ['fixed_conflict'],
          ),
        );
      }
    }

    // Subtract fixed blocks (hard constraints).
    for (final f in fixed) {
      final s = _todToMin(f.time);
      final d = _durationFromHeight(f.height);
      final e = (s + d).clamp(0, 24 * 60).toInt();
      _subtractInterval(free, _Interval(s, e));
    }

    // Sort tasks by the contract order. Energy affects placement scoring only.
    final tasks = List<PlanTask>.from(request.tasks);
    tasks.sort((a, b) => _compareTasks(a, b, day));

    final planned = <ScheduleEntry>[];
    final fixedIds = fixed
        .map((entry) => entry.id)
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet();
    final taskIds = tasks.map((task) => task.id).toSet();
    final placedIds = <String>{...fixedIds};
    final failedIds = <String>{};
    var pending = List<PlanTask>.from(tasks);

    while (pending.isNotEmpty) {
      var progressed = false;
      final nextPending = <PlanTask>[];

      for (final t in pending) {
        final blockedBy = t.dependsOn
            .where((id) => !placedIds.contains(id))
            .toList(growable: false);
        final hasUnresolvableDependency = blockedBy.any(
          (id) => !taskIds.contains(id) || failedIds.contains(id),
        );
        if (hasUnresolvableDependency) {
          issues.add(
            SchedulingIssue(
              code: 'dependency_blocked',
              message:
                  'Task cannot be scheduled until its dependency is placed',
              taskId: t.id,
              blockedBy: blockedBy,
            ),
          );
          failedIds.add(t.id);
          progressed = true;
          continue;
        }
        if (blockedBy.isNotEmpty) {
          nextPending.add(t);
          continue;
        }

        final dur = t.durationMinutes.clamp(1, 24 * 60).toInt();
        final splittable = t.splittable;
        final minimumChunk = t.minimumChunkMinutes ?? 15;
        final dueMin = t.due == null
            ? null
            : sameDay(t.due!, day)
            ? (t.due!.hour * 60 + t.due!.minute)
            : t.due!.isBefore(day)
            ? -1
            : null;
        final earliestMin = _earliestStartMinutes(t, day);

        final freeBeforeTask = free
            .map((interval) => _Interval(interval.startMin, interval.endMin))
            .toList(growable: false);
        final placements = <_Placement>[];
        var remaining = dur;
        while (remaining > 0) {
          final chunkDuration = splittable
              ? _nextChunkDuration(remaining, minimumChunk, free)
              : remaining;
          if (chunkDuration == null) break;
          final placement = _pickSlot(
            free: free,
            duration: chunkDuration,
            dueMin: dueMin,
            earliestMin: placements.isEmpty ? earliestMin : null,
            hardDeadline: t.hardDeadline,
            energy: energy,
            load: t.load,
            tuning: tuning,
          );
          if (placement == null) break;
          placements.add(_Placement(placement, chunkDuration));
          _subtractInterval(
            free,
            _Interval(placement, placement + chunkDuration),
          );
          remaining -= chunkDuration;
        }

        if (remaining > 0) {
          free
            ..clear()
            ..addAll(freeBeforeTask);
          issues.add(
            SchedulingIssue(
              code: 'no_slot',
              message: 'No available slot for task: ${t.title}',
              taskId: t.id,
              explanationCodes: t.due == null
                  ? const []
                  : const ['deadline_proximity'],
            ),
          );
          failedIds.add(t.id);
          progressed = true;
          continue;
        }

        for (var index = 0; index < placements.length; index++) {
          final placement = placements[index];
          planned.add(
            ScheduleEntry(
              id: splittable ? '${t.id}#${index + 1}' : t.id,
              title: t.title,
              tag: t.tag,
              load: t.load,
              height: _heightFromDuration(placement.duration),
              color: _colorForLoad(t.load),
              time: _minToTod(placement.startMin),
              source: 'planned',
              explanationCodes: _explanationCodes(t, energy),
            ),
          );
        }
        placedIds.add(t.id);
        progressed = true;

        // If we missed a due time, record an issue (still scheduled).
        if (t.due != null && !sameDay(t.due!, day)) {
          if (t.due!.isBefore(day)) {
            issues.add(
              SchedulingIssue(
                code: 'overdue',
                message: 'Task due before the requested day: ${t.title}',
                taskId: t.id,
                explanationCodes: const ['deadline_proximity'],
              ),
            );
          }
        } else if (dueMin != null &&
            placements.last.startMin + placements.last.duration > dueMin) {
          issues.add(
            SchedulingIssue(
              code: 'miss_due',
              message: 'Task scheduled past due time: ${t.title}',
              taskId: t.id,
              explanationCodes: const ['deadline_proximity'],
            ),
          );
        }
      }

      if (!progressed) {
        for (final t in nextPending) {
          final blockedBy = t.dependsOn
              .where((id) => !placedIds.contains(id))
              .toList(growable: false);
          issues.add(
            SchedulingIssue(
              code: 'dependency_blocked',
              message:
                  'Task cannot be scheduled until its dependency is placed',
              taskId: t.id,
              blockedBy: blockedBy,
            ),
          );
          failedIds.add(t.id);
        }
        break;
      }
      pending = nextPending;
    }

    // Final output: fixed blocks + planned, sorted.
    final fixedOutput = fixed
        .map(
          (entry) =>
              entry.copyWith(source: 'fixed', explanationCodes: const []),
        )
        .toList(growable: false);
    final out = <ScheduleEntry>[...fixedOutput, ...planned];
    out.sort((a, b) {
      final time = _todToMin(a.time).compareTo(_todToMin(b.time));
      if (time != 0) return time;
      final source = (a.source == 'fixed' ? 0 : 1).compareTo(
        b.source == 'fixed' ? 0 : 1,
      );
      if (source != 0) return source;
      return (a.id ?? '').compareTo(b.id ?? '');
    });

    return SchedulingPlan(entries: out, issues: issues);
  }

  int? _nextChunkDuration(
    int remaining,
    int minimumChunk,
    List<_Interval> intervals,
  ) {
    if (intervals.any((interval) => interval.length >= remaining)) {
      return remaining;
    }
    final largest = intervals.fold<int>(
      0,
      (maxLength, interval) =>
          interval.length > maxLength ? interval.length : maxLength,
    );
    if (largest < minimumChunk) return null;
    var candidate = remaining < largest ? remaining : largest;
    final remainder = remaining - candidate;
    if (remainder > 0 && remainder < minimumChunk) {
      candidate = remaining - minimumChunk;
    }
    if (candidate < minimumChunk || candidate > largest) return null;
    return candidate;
  }

  int? _pickSlot({
    required List<_Interval> free,
    required int duration,
    required int? dueMin,
    required int? earliestMin,
    required bool hardDeadline,
    required EnergyTier energy,
    required CognitiveLoad load,
    required SchedulingTuning tuning,
  }) {
    int? bestStart;
    double bestScore = double.negativeInfinity;

    for (final it in free) {
      final start = earliestMin == null
          ? it.startMin
          : (it.startMin > earliestMin ? it.startMin : earliestMin);
      final end = start + duration;

      if (start < it.startMin || end > it.endMin) continue;

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

    if (hardDeadline && dueMin != null) return null;

    // Fallback: if dueMin blocks everything, schedule at earliest available.
    for (final it in free) {
      final start = earliestMin == null
          ? it.startMin
          : (it.startMin > earliestMin ? it.startMin : earliestMin);
      if (start >= it.startMin && start + duration <= it.endMin) {
        return start;
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
        final p = tuning.highLoadPenaltyWhenLowEnergy
            .clamp(1.0, 3.0)
            .toDouble();
        final extra = (p - 1.0).clamp(0.0, 10.0).toDouble();
        if (load == CognitiveLoad.high) {
          score -= 5 * p;
          if (isMorning) score -= 2.0 * (1.0 + extra);
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
