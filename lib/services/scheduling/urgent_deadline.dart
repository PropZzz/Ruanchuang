DateTime defaultUrgentDeadline({
  required DateTime now,
  required DateTime scheduleDay,
}) {
  final day = _dateOnly(scheduleDay);
  final today = _dateOnly(now);
  if (day.isAfter(today)) {
    return DateTime(day.year, day.month, day.day, 17);
  }
  return now.add(const Duration(hours: 2));
}

bool isUrgentDeadlineValid({
  required DateTime now,
  required DateTime scheduleDay,
  required DateTime deadline,
}) {
  final today = _dateOnly(now);
  final plannedDay = _dateOnly(scheduleDay);
  final deadlineDay = _dateOnly(deadline);
  if (plannedDay.isBefore(today) ||
      deadlineDay.isBefore(plannedDay) ||
      deadlineDay.isBefore(today)) {
    return false;
  }
  return deadline.isAfter(now);
}

DateTime urgentDeadlinePickerLastDate({required DateTime firstDate}) =>
    DateTime(firstDate.year + 5, firstDate.month, firstDate.day);

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);
