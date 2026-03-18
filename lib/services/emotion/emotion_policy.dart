import 'package:flutter/material.dart';

import '../../models/models.dart';

/// Emotion-aware adaptation rules for scheduling.
///
/// This is a lightweight P0 policy aligned with the project plan:
/// - efficient: slightly higher energy, higher task density
/// - stable: neutral
/// - tired/irritable: lower energy, lower task density, add rest and prefer low-pressure tasks
class EmotionPolicy {
  static bool isLow(EmotionState s) =>
      s == EmotionState.tired || s == EmotionState.irritable;

  static bool shouldShowCareHint({
    required EmotionState? today,
    required EmotionState? yesterday,
  }) {
    if (today == null || yesterday == null) return false;
    return isLow(today) && isLow(yesterday);
  }

  static EmotionSchedulingPolicy schedulingFor(EmotionState emotion) {
    switch (emotion) {
      case EmotionState.efficient:
        return const EmotionSchedulingPolicy(
          energyDelta: 1,
          durationMultiplier: 0.9,
          maxHighLoadTasks: 3,
          restMinutes: 0,
        );
      case EmotionState.stable:
        return const EmotionSchedulingPolicy(
          energyDelta: 0,
          durationMultiplier: 1.0,
          maxHighLoadTasks: 2,
          restMinutes: 0,
        );
      case EmotionState.tired:
      case EmotionState.irritable:
        return const EmotionSchedulingPolicy(
          energyDelta: -1,
          durationMultiplier: 1.2,
          maxHighLoadTasks: 1,
          restMinutes: 15,
        );
    }
  }

  static EnergyTier adjustEnergy({
    required EnergyTier base,
    required EmotionState emotion,
  }) {
    final policy = schedulingFor(emotion);
    final idx = (base.index + policy.energyDelta)
        .clamp(0, EnergyTier.values.length - 1);
    return EnergyTier.values[idx];
  }

  /// Apply emotion-aware task shaping:
  /// - low emotion: cap number of high-load tasks, boost low-load priority
  /// - efficient: boost high-load priority (keeps density high)
  static List<PlanTask> adaptTasks({
    required List<PlanTask> tasks,
    required EmotionState emotion,
  }) {
    final policy = schedulingFor(emotion);
    final sorted = List<PlanTask>.from(tasks)
      ..sort((a, b) => b.priority.compareTo(a.priority));

    if (!isLow(emotion)) {
      if (emotion == EmotionState.efficient) {
        return sorted
            .map(
              (t) => PlanTask(
                id: t.id,
                title: t.title,
                durationMinutes: t.durationMinutes,
                priority: (t.load == CognitiveLoad.high)
                    ? (t.priority + 1).clamp(1, 5)
                    : t.priority,
                load: t.load,
                tag: t.tag,
                due: t.due,
              ),
            )
            .toList();
      }
      return sorted;
    }

    final high = <PlanTask>[];
    final others = <PlanTask>[];
    for (final t in sorted) {
      if (t.load == CognitiveLoad.high) {
        high.add(t);
      } else {
        others.add(t);
      }
    }

    // Keep only the most important high-load tasks (delay the rest).
    final keptHigh = high.take(policy.maxHighLoadTasks).toList();

    // Prefer low-pressure tasks by boosting low-load priority a bit.
    final tunedOthers = others
        .map(
          (t) => PlanTask(
            id: t.id,
            title: t.title,
            durationMinutes: t.durationMinutes,
            priority: (t.load == CognitiveLoad.low)
                ? (t.priority + 1).clamp(1, 5)
                : t.priority,
            load: t.load,
            tag: t.tag,
            due: t.due,
          ),
        )
        .toList();

    return [...keptHigh, ...tunedOthers];
  }

  static int applyDurationMultiplier({
    required int minutes,
    required EmotionState emotion,
  }) {
    final policy = schedulingFor(emotion);
    return (minutes * policy.durationMultiplier).round().clamp(1, 24 * 60);
  }

  /// Fixed "rest" blocks to reduce task density when emotion is low.
  static List<ScheduleEntry> fixedRestBlocks({
    required DateTime day,
    required EmotionState emotion,
  }) {
    final policy = schedulingFor(emotion);
    if (policy.restMinutes <= 0) return const [];

    // Two short breaks inside the default working windows (08:00-12:00, 13:30-18:30).
    // Times are chosen to be "between" common deep-work blocks.
    return [
      _restBlock(
        minutes: policy.restMinutes,
        time: const TimeOfDay(hour: 10, minute: 30),
      ),
      _restBlock(
        minutes: policy.restMinutes,
        time: const TimeOfDay(hour: 15, minute: 30),
      ),
    ];
  }

  static ScheduleEntry _restBlock({
    required int minutes,
    required TimeOfDay time,
  }) {
    // Keep consistent with the UI mapping: 80.0 ~= 60 minutes.
    final height = ((minutes / 60.0) * 80.0).clamp(20.0, 24 * 60 * 80.0);
    return ScheduleEntry(
      id: 'rest_${time.hour}_${time.minute}',
      title: 'Rest',
      tag: 'Care',
      height: height,
      color: Colors.grey.shade400,
      time: time,
      reminderMinutesBefore: 0,
    );
  }
}

class EmotionSchedulingPolicy {
  final int energyDelta;
  final double durationMultiplier;
  final int maxHighLoadTasks;
  final int restMinutes;

  const EmotionSchedulingPolicy({
    required this.energyDelta,
    required this.durationMultiplier,
    required this.maxHighLoadTasks,
    required this.restMinutes,
  });
}

