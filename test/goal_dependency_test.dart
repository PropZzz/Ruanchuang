import 'package:flutter_test/flutter_test.dart';

import 'package:shixuzhipei/models/models.dart';
import 'package:shixuzhipei/services/goals/goal_dependency_helper.dart';

void main() {
  group('GoalTask dependency serialization', () {
    test('round-trips dependency ids', () {
      const task = GoalTask(
        id: 'a',
        title: 'A',
        durationMinutes: 30,
        load: CognitiveLoad.medium,
        tag: 'Goal',
        dependsOn: ['b', 'c'],
      );

      final json = task.toJson();
      final decoded = GoalTask.fromJson(json);
      expect(decoded.dependsOn, ['b', 'c']);
    });

    test('missing dependsOn defaults to empty list', () {
      final decoded = GoalTask.fromJson({
        'id': 'x',
        'title': 'X',
        'durationMinutes': 20,
        'load': CognitiveLoad.low.name,
        'tag': 'Goal',
        'done': false,
      });
      expect(decoded.dependsOn, isEmpty);
    });
  });

  group('GoalTask dependency readiness', () {
    test('firstReady returns first task with deps satisfied', () {
      const a = GoalTask(
        id: 'a',
        title: 'A',
        durationMinutes: 20,
        load: CognitiveLoad.low,
        tag: 'Goal',
      );
      const b = GoalTask(
        id: 'b',
        title: 'B',
        durationMinutes: 20,
        load: CognitiveLoad.low,
        tag: 'Goal',
        dependsOn: ['a'],
      );
      const c = GoalTask(
        id: 'c',
        title: 'C',
        durationMinutes: 20,
        load: CognitiveLoad.low,
        tag: 'Goal',
        dependsOn: ['b'],
      );

      final tasks = [a, b, c];
      expect(GoalDependencyHelper.firstReady(tasks)?.id, 'a');

      final doneA = a.copyWith(done: true);
      final tasks2 = [doneA, b, c];
      expect(GoalDependencyHelper.firstReady(tasks2)?.id, 'b');
    });
  });
}
