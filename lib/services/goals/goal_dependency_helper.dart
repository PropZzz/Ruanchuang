import '../../models/models.dart';

class GoalDependencyHelper {
  static GoalTask? _firstById(List<GoalTask> all, String id) {
    for (final task in all) {
      if (task.id == id) return task;
    }
    return null;
  }

  static bool isReady(GoalTask task, List<GoalTask> all) {
    if (task.done) return false;
    if (task.dependsOn.isEmpty) return true;
    for (final depId in task.dependsOn) {
      final dependency = _firstById(all, depId);
      if (dependency == null || !dependency.done) return false;
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
      final dependency = _firstById(all, depId);
      if (dependency == null || !dependency.done) {
        blockers.add(byId[depId] ?? depId);
      }
    }
    return blockers;
  }
}
