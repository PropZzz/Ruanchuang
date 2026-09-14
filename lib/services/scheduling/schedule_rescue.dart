import 'package:flutter/material.dart';

import '../../models/models.dart';
import 'rescue_scoring.dart';
import 'rescue_strategy_weights.dart';
import 'scheduling_engine.dart';

enum RescueStrategy { protectDeadline, protectRecovery, minimizeChanges }

class ScheduleRescueOption {
  final RescueStrategy strategy;
  final SchedulingPlan plan;
  final String rationale;
  final String tradeoff;
  final int movedEntryCount;
  final int recoveryMinutes;
  final double score;
  final Map<String, double> scoreBreakdown;
  final int hardIssueCount;
  final double overdueRisk;
  final List<String> movedEntryIds;

  const ScheduleRescueOption({
    required this.strategy,
    required this.plan,
    required this.rationale,
    required this.tradeoff,
    required this.movedEntryCount,
    this.recoveryMinutes = 0,
    this.score = 0.0,
    this.scoreBreakdown = const {},
    this.hardIssueCount = 0,
    this.overdueRisk = 0.0,
    this.movedEntryIds = const [],
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
    RescueStrategyWeights.validate();
    final allTasks = [
      ...base.tasks,
      ..._baselineTasks(baseline, base.tasks),
      urgent,
    ];

    final deadlinePlan = _annotateKeptBaseline(
      engine.plan(_request(base, tasks: allTasks)),
      baseline,
    );

    final recoveryInitialPlan = engine.plan(
      _request(base, tasks: allTasks, energy: _lowerEnergy(base.energy)),
    );
    final recoveryBuffer = _recoveryBuffer(base, recoveryInitialPlan);
    final recoveryPlan = recoveryBuffer == null
        ? _annotateKeptBaseline(recoveryInitialPlan, baseline)
        : _annotateKeptBaseline(
            _appendRecovery(recoveryInitialPlan, recoveryBuffer),
            baseline,
          );
    final recoveryMinutes =
        recoveryBuffer != null &&
            recoveryPlan.entries.any((entry) => entry.id == recoveryBuffer.id)
        ? RescueStrategyWeights.recoveryBufferMinutes
        : 0;

    final minimalPlan = _annotateKeptBaseline(
      engine.plan(
        _request(base, tasks: allTasks, fixed: [...base.fixed, ...baseline]),
      ),
      baseline,
    );

    final deadlineScore = _score(
      strategy: RescueStrategy.protectDeadline,
      plan: deadlinePlan,
      tasks: allTasks,
      baseline: baseline,
      energy: base.energy,
      recoveryMinutes: 0,
    );
    final recoveryScore = _score(
      strategy: RescueStrategy.protectRecovery,
      plan: recoveryPlan,
      tasks: allTasks,
      baseline: baseline,
      energy: _lowerEnergy(base.energy),
      recoveryMinutes: recoveryMinutes,
    );
    final minimalScore = _score(
      strategy: RescueStrategy.minimizeChanges,
      plan: minimalPlan,
      tasks: allTasks,
      baseline: baseline,
      energy: base.energy,
      recoveryMinutes: 0,
    );

    return [
      ScheduleRescueOption(
        strategy: RescueStrategy.protectDeadline,
        plan: deadlinePlan,
        rationale: '先安排紧急事项，再重新分配其余任务，优先降低逾期风险。',
        tradeoff: '可能移动更多原有任务，恢复时间取决于当前能量状态。',
        movedEntryCount: _movedEntryIds(baseline, deadlinePlan.entries).length,
        movedEntryIds: _movedEntryIds(baseline, deadlinePlan.entries),
        score: deadlineScore.score,
        scoreBreakdown: deadlineScore.breakdown,
        hardIssueCount: deadlineScore.hardIssues,
        overdueRisk: deadlineScore.overdueRisk,
      ),
      ScheduleRescueOption(
        strategy: RescueStrategy.protectRecovery,
        plan: recoveryPlan,
        rationale: '降低高负荷任务的安排倾向，并预留 15 分钟恢复缓冲。',
        tradeoff: '部分低优先级任务可能顺延，适合疲劳或连续被打断的场景。',
        movedEntryCount: _movedEntryIds(baseline, recoveryPlan.entries).length,
        movedEntryIds: _movedEntryIds(baseline, recoveryPlan.entries),
        recoveryMinutes: recoveryMinutes,
        score: recoveryScore.score,
        scoreBreakdown: recoveryScore.breakdown,
        hardIssueCount: recoveryScore.hardIssues,
        overdueRisk: recoveryScore.overdueRisk,
      ),
      ScheduleRescueOption(
        strategy: RescueStrategy.minimizeChanges,
        plan: minimalPlan,
        rationale: '锁定当前已排日程，只在现有空档中放入紧急事项。',
        tradeoff: '如果空档不足，紧急事项可能无法在截止时间前安排。',
        movedEntryCount: _movedEntryIds(baseline, minimalPlan.entries).length,
        movedEntryIds: _movedEntryIds(baseline, minimalPlan.entries),
        score: minimalScore.score,
        scoreBreakdown: minimalScore.breakdown,
        hardIssueCount: minimalScore.hardIssues,
        overdueRisk: minimalScore.overdueRisk,
      ),
    ];
  }

  _RescueScore _score({
    required RescueStrategy strategy,
    required SchedulingPlan plan,
    required List<PlanTask> tasks,
    required List<ScheduleEntry> baseline,
    required EnergyTier energy,
    required int recoveryMinutes,
  }) {
    final moved = _movedEntryCount(baseline, plan.entries);
    final metrics = metricsForRescuePlan(
      plan: plan,
      tasks: tasks,
      movedEntryCount: moved,
      baselineEntryCount: baseline.length,
      energy: energy,
      recoveryMinutes: recoveryMinutes,
    );
    final name = switch (strategy) {
      RescueStrategy.protectDeadline => 'protectDeadline',
      RescueStrategy.protectRecovery => 'protectRecovery',
      RescueStrategy.minimizeChanges => 'minimizeChanges',
    };
    return _RescueScore(
      score: scoreRescuePlan(name, metrics),
      breakdown: metrics.toJson(),
      hardIssues: rescueHardIssueCount(plan),
      overdueRisk: metrics.overdueRisk,
    );
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

  List<PlanTask> _baselineTasks(
    List<ScheduleEntry> baseline,
    List<PlanTask> existing,
  ) {
    final knownIds = existing.map((task) => task.id).toSet();
    return baseline
        .where((entry) {
          final id = entry.id;
          return id != null && id.isNotEmpty && !knownIds.contains(id);
        })
        .map(
          (entry) => PlanTask(
            id: entry.id!,
            title: entry.title,
            durationMinutes: _durationFromHeight(entry.height),
            priority: 3,
            load: entry.load ?? CognitiveLoad.medium,
            tag: entry.tag,
          ),
        )
        .toList(growable: false);
  }

  SchedulingPlan _annotateKeptBaseline(
    SchedulingPlan plan,
    List<ScheduleEntry> baseline,
  ) {
    final baselineById = <String, ScheduleEntry>{
      for (final entry in baseline)
        if (entry.id != null && entry.id!.isNotEmpty) entry.id!: entry,
    };
    if (baselineById.isEmpty) return plan;
    return SchedulingPlan(
      schemaVersion: plan.schemaVersion,
      risk: plan.risk,
      issues: plan.issues,
      entries: plan.entries
          .map((entry) {
            final original = baselineById[entry.id];
            if (original == null) return entry;
            final unchanged =
                entry.time == original.time &&
                (entry.height - original.height).abs() <= 0.1;
            if (!unchanged) return entry;
            return entry.copyWith(
              explanationCodes: _orderedExplanationCodes([
                ...entry.explanationCodes,
                'kept_baseline',
              ]),
            );
          })
          .toList(growable: false),
    );
  }

  SchedulingPlan _appendRecovery(SchedulingPlan plan, ScheduleEntry recovery) {
    final entries = [...plan.entries, recovery.copyWith(source: 'recovery')]
      ..sort((a, b) {
        final timeA = _todToMin(a.time);
        final timeB = _todToMin(b.time);
        if (timeA != timeB) return timeA.compareTo(timeB);
        final sourceA = a.source == 'fixed' ? 0 : 1;
        final sourceB = b.source == 'fixed' ? 0 : 1;
        if (sourceA != sourceB) return sourceA.compareTo(sourceB);
        return (a.id ?? '').compareTo(b.id ?? '');
      });
    return SchedulingPlan(
      schemaVersion: plan.schemaVersion,
      entries: entries,
      issues: plan.issues,
      risk: plan.risk,
    );
  }

  ScheduleEntry? _recoveryBuffer(
    SchedulingRequest base,
    SchedulingPlan planned,
  ) {
    final free = <_RecoveryInterval>[];
    final blocks = <ScheduleEntry>[];
    final seenIds = <String>{};
    for (final entry in [...base.fixed, ...planned.entries]) {
      final id = entry.id;
      if (id != null && id.isNotEmpty && !seenIds.add(id)) continue;
      blocks.add(entry);
    }
    for (final window in base.windows) {
      final start = _todToMin(window.start);
      final end = _todToMin(window.end);
      if (end <= start) continue;
      final cuts =
          blocks
              .map((entry) {
                final fixedStart = _todToMin(entry.time);
                final fixedEnd = fixedStart + _durationFromHeight(entry.height);
                if (fixedEnd <= start || fixedStart >= end) return null;
                return _RecoveryInterval(
                  fixedStart.clamp(start, end).toInt(),
                  fixedEnd.clamp(start, end).toInt(),
                );
              })
              .whereType<_RecoveryInterval>()
              .toList()
            ..sort((a, b) => a.start.compareTo(b.start));
      var cursor = start;
      for (final cut in cuts) {
        if (cut.start > cursor) free.add(_RecoveryInterval(cursor, cut.start));
        if (cut.end > cursor) cursor = cut.end;
      }
      if (cursor < end) free.add(_RecoveryInterval(cursor, end));
    }
    final afternoon = free
        .map(
          (slot) => _RecoveryInterval(
            slot.start < 12 * 60 ? 12 * 60 : slot.start,
            slot.end,
          ),
        )
        .where((slot) => slot.end - slot.start >= 15)
        .toList();
    final legal = afternoon.isNotEmpty
        ? afternoon.first
        : free.firstWhere(
            (slot) => slot.end - slot.start >= 15,
            orElse: () => const _RecoveryInterval(0, 0),
          );
    if (legal.end - legal.start < 15) return null;
    return ScheduleEntry(
      id: 'rescue_recovery_${base.day.toIso8601String().split('T').first}',
      day: base.day,
      title: '恢复缓冲',
      tag: 'Recovery',
      load: CognitiveLoad.low,
      height: 20,
      color: const Color(0xFF80CBC4),
      time: _minToTod(legal.start),
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
    return _movedEntryIds(baseline, candidate).length;
  }

  List<String> _movedEntryIds(
    List<ScheduleEntry> baseline,
    List<ScheduleEntry> candidate,
  ) {
    final candidateById = <String, ScheduleEntry>{
      for (final entry in candidate)
        if (entry.id != null && entry.id!.isNotEmpty) entry.id!: entry,
    };
    final moved = <String>[];
    for (final entry in baseline) {
      final id = entry.id;
      if (id == null || id.isEmpty) continue;
      final next = candidateById[id];
      if (next == null ||
          next.time != entry.time ||
          (next.height - entry.height).abs() > 0.1) {
        moved.add(id);
      }
    }
    return moved;
  }
}

class _RescueScore {
  final double score;
  final Map<String, double> breakdown;
  final int hardIssues;
  final double overdueRisk;

  const _RescueScore({
    required this.score,
    required this.breakdown,
    required this.hardIssues,
    required this.overdueRisk,
  });
}

class _RecoveryInterval {
  final int start;
  final int end;

  const _RecoveryInterval(this.start, this.end);
}

int _todToMin(TimeOfDay time) => time.hour * 60 + time.minute;

TimeOfDay _minToTod(int minutes) {
  final value = minutes.clamp(0, 24 * 60 - 1).toInt();
  return TimeOfDay(hour: value ~/ 60, minute: value % 60);
}

int _durationFromHeight(double height) =>
    (height / 80.0 * 60.0).round().clamp(1, 24 * 60).toInt();

List<String> _orderedExplanationCodes(Iterable<String> codes) {
  const order = [
    'deadline_proximity',
    'priority',
    'energy_fit',
    'kept_baseline',
    'fixed_conflict',
  ];
  final unique = codes.toSet();
  return [
    for (final code in order)
      if (unique.contains(code)) code,
  ];
}
