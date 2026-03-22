import '../../models/models.dart';

class GoalDependencyHelper {
  static bool isReady(GoalTask task, List<GoalTask> all) {
    if (task.done) return false;
    if (task.dependsOn.isEmpty) return true;
    for (final depId in task.dependsOn) {
      final dep = all.where((t) => t.id == depId).toList();
      if (dep.isEmpty) return false;
      if (!dep.first.done) return false;
    }
    return true;
  }

  static GoalTask? firstReady(List<GoalTask> all) {
    for (final t in all) {
      if (isReady(t, all)) return t;
    }
    return null;
  }

  static List<String> blockedByTitles(GoalTask task, List<GoalTask> all) {
    if (task.dependsOn.isEmpty) return const [];
    final byId = {for (final t in all) t.id: t.title};
    final blockers = <String>[];
    for (final depId in task.dependsOn) {
      final dep = all.where((t) => t.id == depId).toList();
      if (dep.isEmpty || !dep.first.done) {
        blockers.add(byId[depId] ?? depId);
      }
    }
    return blockers;
  }
}
