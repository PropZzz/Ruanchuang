import 'package:flutter_test/flutter_test.dart';
import 'package:shixuzhipei/widgets/calendar/calendar_navigation.dart';
import 'package:shixuzhipei/widgets/schedule_timeline.dart';

void main() {
  final cases = [
    (
      DateTime(2026, 1, 31),
      ScheduleTimelineView.month,
      -1,
      DateTime(2025, 12, 31),
    ),
    (
      DateTime(2026, 12, 31),
      ScheduleTimelineView.month,
      1,
      DateTime(2027, 1, 31),
    ),
    (
      DateTime(2026, 1, 31),
      ScheduleTimelineView.month,
      1,
      DateTime(2026, 2, 28),
    ),
    (
      DateTime(2024, 1, 31),
      ScheduleTimelineView.month,
      1,
      DateTime(2024, 2, 29),
    ),
    (
      DateTime(2026, 1, 1),
      ScheduleTimelineView.day,
      -1,
      DateTime(2025, 12, 31),
    ),
    (
      DateTime(2026, 1, 3),
      ScheduleTimelineView.week,
      -1,
      DateTime(2025, 12, 27),
    ),
    (
      DateTime(2026, 12, 28),
      ScheduleTimelineView.gantt,
      1,
      DateTime(2027, 1, 4),
    ),
  ];
  for (final entry in cases) {
    test('${entry.$2.name} navigation ${entry.$1} by ${entry.$3}', () {
      expect(shiftCalendarPeriod(entry.$1, entry.$2, entry.$3), entry.$4);
    });
  }
}
