import '../../models/models.dart';
import 'rescue_strategy_weights.dart';

class RescuePlanMetrics {
  final double urgency;
  final double priority;
  final double energyFit;
  final double stability;
  final double recovery;
  final double overdueRisk;

  const RescuePlanMetrics({
    required this.urgency,
    required this.priority,
    required this.energyFit,
    required this.stability,
    required this.recovery,
    this.overdueRisk = 0.0,
  });

  Map<String, double> toJson() => {
    'urgency': urgency,
    'priority': priority,
    'energyFit': energyFit,
    'stability': stability,
    'recovery': recovery,
  };
}

RescuePlanMetrics metricsForRescuePlan({
  required SchedulingPlan plan,
  required List<PlanTask> tasks,
  required int movedEntryCount,
  required int baselineEntryCount,
  required EnergyTier energy,
  required int recoveryMinutes,
}) {
  final taskById = <String, PlanTask>{for (final task in tasks) task.id: task};
  final placed = plan.entries
      .where((entry) {
        if (entry.source != 'planned') return false;
        final id = _baseTaskId(entry.id, taskById);
        return id != null;
      })
      .toList(growable: false);
  final missedTaskIds = <String>{};
  for (final issue in plan.issues) {
    final taskId = _baseTaskId(issue.taskId, taskById);
    if (taskId == null) continue;
    final task = taskById[taskId];
    if (task == null) continue;
    if (issue.code == 'miss_due' ||
        issue.code == 'overdue' ||
        (issue.code == 'no_slot' && task.due != null)) {
      missedTaskIds.add(taskId);
    }
  }
  final missedCount = missedTaskIds.length;
  final placedTaskIds = <String>{};
  for (final entry in placed) {
    final id = _baseTaskId(entry.id, taskById);
    if (id != null) placedTaskIds.add(id);
  }
  final evaluatedTaskIds = <String>{...placedTaskIds};
  for (final issue in plan.issues) {
    final id = _baseTaskId(issue.taskId, taskById);
    if (id != null) evaluatedTaskIds.add(id);
  }
  final evaluatedTaskCount = evaluatedTaskIds.length;
  final dueCount = evaluatedTaskIds
      .map((id) => taskById[id])
      .whereType<PlanTask>()
      .where((task) => task.due != null)
      .length;
  final urgency = _clamp(1.0 - missedCount / (dueCount > 0 ? dueCount : 1));
  final prioritySum = placedTaskIds.fold<int>(
    0,
    (sum, id) => sum + (taskById[id]?.priority ?? 0),
  );
  final priority = _clamp(
    prioritySum / (5 * (evaluatedTaskCount > 0 ? evaluatedTaskCount : 1)),
  );

  final targetLoad = switch (energy) {
    EnergyTier.veryLow || EnergyTier.low => 0,
    EnergyTier.medium => 1,
    EnergyTier.high || EnergyTier.veryHigh => 2,
  };
  var mismatch = 0.0;
  for (final entry in placed) {
    final taskId = _baseTaskId(entry.id, taskById);
    final load = taskId == null ? targetLoad : taskById[taskId]!.load.index;
    mismatch += (load - targetLoad).abs() / 2.0;
  }
  final energyFit = _clamp(
    1.0 - mismatch / (placed.isEmpty ? 1 : placed.length),
  );
  final stability = _clamp(
    1.0 - movedEntryCount / (baselineEntryCount > 0 ? baselineEntryCount : 1),
  );
  final recovery = _clamp(
    recoveryMinutes / RescueStrategyWeights.recoveryBufferMinutes,
  );
  final overdueRisk = _clamp(missedCount / (dueCount > 0 ? dueCount : 1));
  return RescuePlanMetrics(
    urgency: urgency,
    priority: priority,
    energyFit: energyFit,
    stability: stability,
    recovery: recovery,
    overdueRisk: overdueRisk,
  );
}

double scoreRescuePlan(String strategy, RescuePlanMetrics metrics) {
  final weights = RescueStrategyWeights.strategies[strategy];
  if (weights == null)
    throw ArgumentError('unknown rescue strategy: $strategy');
  final values = metrics.toJson();
  final score = values.entries.fold<double>(
    0,
    (sum, entry) => sum + (weights[entry.key] ?? 0) * _clamp(entry.value),
  );
  return (score * 1000000).roundToDouble() / 1000000;
}

int rescueHardIssueCount(SchedulingPlan plan) => plan.issues
    .where(
      (issue) =>
          issue.code == 'no_slot' ||
          issue.code == 'dependency_blocked' ||
          issue.code == 'fixed_conflict',
    )
    .length;

String? _baseTaskId(String? entryId, Map<String, PlanTask> taskById) {
  if (entryId == null || entryId.isEmpty) return null;
  if (taskById.containsKey(entryId)) return entryId;
  final separator = entryId.lastIndexOf('#');
  if (separator <= 0) return null;
  final base = entryId.substring(0, separator);
  return taskById.containsKey(base) ? base : null;
}

double _clamp(double value) => value.clamp(0.0, 1.0).toDouble();
