import 'package:flutter/material.dart';

import '../../models/models.dart';
import 'scheduling_engine.dart';

enum RescueStrategy {
  protectDeadline,
  protectRecovery,
  minimizeChanges,
}

class ScheduleRescueOption {
  final RescueStrategy strategy;
  final SchedulingPlan plan;
  final String rationale;
  final String tradeoff;
  final int movedEntryCount;
  final int recoveryMinutes;

  const ScheduleRescueOption({
    required this.strategy,
    required this.plan,
    required this.rationale,
    required this.tradeoff,
    required this.movedEntryCount,
    this.recoveryMinutes = 0,
  });

  String get title => switch (strategy) {
    RescueStrategy.protectDeadline => '优先保住截止时间',
    RescueStrategy.protectRecovery => '优先保留恢复时间',
    RescueStrategy.minimizeChanges => '尽量少动原计划',
  };
}

/// Turns an urgent task into explicit, user-selectable recovery strategies.
///
/// The planner remains replaceable: this service only shapes requests and
/// explains the result produced by [SchedulingEngine].
class ScheduleRescueService {
  final SchedulingEngine engine;

  const ScheduleRescueService({required this.engine});

  List<ScheduleRescueOption> propose({
    required SchedulingRequest base,
    required List<ScheduleEntry> baseline,
    required PlanTask urgent,
  }) {
    final allTasks = [...base.tasks, urgent];

    final deadlinePlan = engine.plan(
      _request(
        base,
        tasks: allTasks,
      ),
    );

    final recoveryPlan = engine.plan(
      _request(
        base,
        tasks: allTasks,
        energy: _lowerEnergy(base.energy),
        fixed: [
          ...base.fixed,
          _recoveryBuffer(base),
        ],
      ),
    );

    final minimalPlan = engine.plan(
      _request(
        base,
        tasks: [urgent],
        fixed: [
          ...base.fixed,
          ...baseline,
        ],
      ),
    );

    return [
      ScheduleRescueOption(
        strategy: RescueStrategy.protectDeadline,
        plan: deadlinePlan,
        rationale: '先安排紧急事项，再重新分配其余任务，优先降低逾期风险。',
        tradeoff: '可能移动更多原有任务，恢复时间取决于当前能量状态。',
        movedEntryCount: _movedEntryCount(baseline, deadlinePlan.entries),
      ),
      ScheduleRescueOption(
        strategy: RescueStrategy.protectRecovery,
        plan: recoveryPlan,
        rationale: '降低高负荷任务的安排倾向，并预留 15 分钟恢复缓冲。',
        tradeoff: '部分低优先级任务可能顺延，适合疲劳或连续被打断的场景。',
        movedEntryCount: _movedEntryCount(baseline, recoveryPlan.entries),
        recoveryMinutes: 15,
      ),
      ScheduleRescueOption(
        strategy: RescueStrategy.minimizeChanges,
        plan: minimalPlan,
        rationale: '锁定当前已排日程，只在现有空档中放入紧急事项。',
        tradeoff: '如果空档不足，紧急事项可能无法在截止时间前安排。',
        movedEntryCount: _movedEntryCount(baseline, minimalPlan.entries),
      ),
    ];
  }

  SchedulingRequest _request(
    SchedulingRequest base, {
    required List<PlanTask> tasks,
    EnergyTier? energy,
    List<ScheduleEntry>? fixed,
  }) {
    return SchedulingRequest(
      day: base.day,
      tasks: tasks,
      windows: base.windows,
      energy: energy ?? base.energy,
      tuning: base.tuning,
      fixed: fixed ?? base.fixed,
    );
  }

  ScheduleEntry _recoveryBuffer(SchedulingRequest base) {
    final preferred = base.windows.firstWhere(
      (window) => window.start.hour >= 12,
      orElse: () => base.windows.isNotEmpty
          ? base.windows.first
          : const TimeWindow(
              start: TimeOfDay(hour: 15, minute: 0),
              end: TimeOfDay(hour: 15, minute: 15),
            ),
    );
    return ScheduleEntry(
      id: 'rescue_recovery_${base.day.toIso8601String().split('T').first}',
      day: base.day,
      title: '恢复缓冲',
      tag: 'Recovery',
      load: CognitiveLoad.low,
      height: 20,
      color: const Color(0xFF80CBC4),
      time: preferred.start,
    );
  }

  EnergyTier _lowerEnergy(EnergyTier energy) {
    final index = (energy.index - 1).clamp(0, EnergyTier.values.length - 1);
    return EnergyTier.values[index];
  }

  int _movedEntryCount(
    List<ScheduleEntry> baseline,
    List<ScheduleEntry> candidate,
  ) {
    final candidateById = <String, ScheduleEntry>{
      for (final entry in candidate)
        if (entry.id != null && entry.id!.isNotEmpty) entry.id!: entry,
    };
    var moved = 0;
    for (final entry in baseline) {
      final id = entry.id;
      if (id == null || id.isEmpty) continue;
      final next = candidateById[id];
      if (next == null ||
          next.time != entry.time ||
          (next.height - entry.height).abs() > 0.1) {
        moved++;
      }
    }
    return moved;
  }
}
