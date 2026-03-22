import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shixuzhipei/models/models.dart';
import 'package:shixuzhipei/services/reminders/reminder_service.dart';

void main() {
  test('Reminder planner schedules today and next occurrence for repeats', () {
    final entry = ScheduleEntry(
      id: 'sch_1',
      title: 'Daily standup',
      tag: 'Meeting',
      height: 80,
      color: Colors.blue,
      time: const TimeOfDay(hour: 9, minute: 0),
      reminderMinutesBefore: 10,
      repeat: RepeatFrequency.daily,
    );

    final now = DateTime(2026, 3, 16, 8, 0, 0);
    final day = DateTime(2026, 3, 16);

    final planned = ReminderService.planReminders(
      ReminderPlanRequest(
        day: day,
        now: now,
        entry: entry,
        entryKey: entry.id!,
        maxUpcomingOccurrences: 2,
      ),
    );

    expect(planned.length, 2);
    expect(planned[0].startAt, DateTime(2026, 3, 16, 9, 0));
    expect(planned[0].intendedFireAt, DateTime(2026, 3, 16, 8, 50));
    expect(planned[0].scheduledAt, DateTime(2026, 3, 16, 8, 50));
    expect(planned[1].startAt, DateTime(2026, 3, 17, 9, 0));
  });

  test('Reminder planner schedules ASAP when inside reminder window', () {
    final entry = ScheduleEntry(
      id: 'sch_2',
      title: 'Daily standup',
      tag: 'Meeting',
      height: 80,
      color: Colors.blue,
      time: const TimeOfDay(hour: 9, minute: 0),
      reminderMinutesBefore: 10,
      repeat: RepeatFrequency.daily,
    );

    final now = DateTime(2026, 3, 16, 8, 55, 0);
    final day = DateTime(2026, 3, 16);

    final planned = ReminderService.planReminders(
      ReminderPlanRequest(
        day: day,
        now: now,
        entry: entry,
        entryKey: entry.id!,
        maxUpcomingOccurrences: 2,
      ),
    );

    expect(planned.isNotEmpty, true);
    expect(planned[0].intendedFireAt, DateTime(2026, 3, 16, 8, 50));
    expect(planned[0].scheduledAt, DateTime(2026, 3, 16, 8, 55, 1));
  });
}

