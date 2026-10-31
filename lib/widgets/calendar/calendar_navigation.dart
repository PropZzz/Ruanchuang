import '../schedule_timeline.dart';

/// Shift the visible calendar period, clamping month-end days across years.
DateTime shiftCalendarPeriod(
  DateTime selected,
  ScheduleTimelineView view,
  int direction,
) {
  final day = DateTime(selected.year, selected.month, selected.day);
  if (view == ScheduleTimelineView.month) {
    final target = DateTime(day.year, day.month + direction, 1);
    final lastDay = DateTime(target.year, target.month + 1, 0).day;
    return DateTime(target.year, target.month, day.day.clamp(1, lastDay));
  }
  final days = view == ScheduleTimelineView.day ? direction : direction * 7;
  return DateTime(day.year, day.month, day.day + days);
}
