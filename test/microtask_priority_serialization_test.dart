import 'package:flutter_test/flutter_test.dart';

import 'package:sxzppp/models/models.dart';

void main() {
  test('MicroTask serializes priority with defaults and clamping', () {
    final task = MicroTask(
      id: 'mt_1',
      title: 'Email reply',
      tag: 'Email',
      minutes: 10,
      priority: 5,
    );

    final json = task.toJson();
    expect(json['priority'], 5);

    final decoded = MicroTask.fromJson(Map<String, Object?>.from(json));
    expect(decoded.priority, 5);

    final missing = MicroTask.fromJson(const <String, Object?>{
      'id': 'mt_2',
      'title': 'Missing priority',
      'tag': 'General',
      'minutes': 5,
    });
    expect(missing.priority, 3);

    final clampedHigh = MicroTask.fromJson(const <String, Object?>{
      'id': 'mt_3',
      'title': 'Too high',
      'tag': 'General',
      'minutes': 5,
      'priority': 99,
    });
    expect(clampedHigh.priority, 5);

    final clampedLow = MicroTask(
      id: 'mt_4',
      title: 'Too low',
      tag: 'General',
      minutes: 5,
      priority: -2,
    );
    expect(clampedLow.priority, 1);

    final clone = task.clone();
    expect(clone.priority, 5);
  });
}

