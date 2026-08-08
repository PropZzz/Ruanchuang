import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shixuzhipei/models/models.dart';
import 'package:shixuzhipei/services/scheduling/schedule_rescue_persistence.dart';

ScheduleEntry entry(String? id, String title) {
  return ScheduleEntry(
    id: id,
    day: DateTime(2026, 8, 6),
    title: title,
    tag: 'Work',
    height: 60,
    color: Colors.teal,
    time: const TimeOfDay(hour: 9, minute: 0),
  );
}

void main() {
  test(
    'applies a rescue plan by upserting new entries before removals',
    () async {
      final stored = <String, ScheduleEntry>{
        'focus': entry('focus', 'Focus'),
        'removed': entry('removed', 'Removed'),
      };
      final operations = <String>[];
      final persistence = ScheduleRescuePersistence(
        upsert: (item) async {
          operations.add('upsert:${item.id}');
          stored[item.id!] = item;
        },
        remove: (item) async {
          operations.add('remove:${item.id}');
          stored.remove(item.id);
        },
      );

      await persistence.apply(
        before: [entry('focus', 'Focus'), entry('removed', 'Removed')],
        after: [
          entry('focus', 'Moved focus'),
          entry('urgent', 'Urgent'),
          entry('', 'Temporary preview'),
        ],
      );

      expect(operations, ['upsert:focus', 'upsert:urgent', 'remove:removed']);
      expect(stored['focus']!.title, 'Moved focus');
      expect(stored['urgent']!.title, 'Urgent');
      expect(stored.containsKey('removed'), isFalse);
    },
  );

  test('inverse apply restores the previous schedule snapshot', () async {
    final stored = <String, ScheduleEntry>{'focus': entry('focus', 'Focus')};
    final persistence = ScheduleRescuePersistence(
      upsert: (item) async => stored[item.id!] = item,
      remove: (item) async => stored.remove(item.id),
    );
    final before = [entry('focus', 'Focus')];
    final after = [entry('focus', 'Moved focus'), entry('urgent', 'Urgent')];

    await persistence.apply(before: before, after: after);
    await persistence.apply(before: after, after: before);

    expect(stored.keys, unorderedEquals(['focus']));
    expect(stored['focus']!.title, 'Focus');
  });

  test('restores the previous schedule when an apply write fails', () async {
    final stored = <String, ScheduleEntry>{'focus': entry('focus', 'Focus')};
    var failNextUpsert = true;
    final persistence = ScheduleRescuePersistence(
      upsert: (item) async {
        if (item.id == 'urgent' && failNextUpsert) {
          failNextUpsert = false;
          throw StateError('write failed');
        }
        stored[item.id!] = item;
      },
      remove: (item) async => stored.remove(item.id),
    );

    await expectLater(
      persistence.apply(
        before: [entry('focus', 'Focus')],
        after: [entry('focus', 'Moved focus'), entry('urgent', 'Urgent')],
      ),
      throwsA(isA<StateError>()),
    );

    expect(stored.keys, unorderedEquals(['focus']));
    expect(stored['focus']!.title, 'Focus');
  });
}
