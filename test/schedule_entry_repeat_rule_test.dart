import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sxzppp/models/models.dart';

void main() {
  test('ScheduleEntry repeat rule serializes and parses', () {
    final entry = ScheduleEntry(
      id: 'sch_1',
      title: 'Run',
      tag: 'Routine',
      height: 80,
      color: Colors.teal,
      time: const TimeOfDay(hour: 9, minute: 0),
      reminderMinutesBefore: 15,
      repeat: RepeatFrequency.weekly,
      repeatUntil: DateTime(2026, 3, 31),
    );

    final json = entry.toJson();
    final parsed = ScheduleEntry.fromJson(Map<String, Object?>.from(json));

    expect(parsed.repeat, RepeatFrequency.weekly);
    expect(parsed.repeatUntil, DateTime(2026, 3, 31));
    expect(parsed.reminderMinutesBefore, 15);
  });

  test('ScheduleEntry repeat defaults to none when missing', () {
    final entry = ScheduleEntry(
      id: 'sch_2',
      title: 'Write',
      tag: 'General',
      height: 80,
      color: Colors.teal,
      time: const TimeOfDay(hour: 10, minute: 0),
      reminderMinutesBefore: 10,
      repeat: RepeatFrequency.daily,
      repeatUntil: DateTime(2026, 4, 1),
    );

    final json = entry.toJson()
      ..remove('repeat')
      ..remove('repeatUntil');
    final parsed = ScheduleEntry.fromJson(Map<String, Object?>.from(json));

    expect(parsed.repeat, RepeatFrequency.none);
    expect(parsed.repeatUntil, isNull);
  });
}

