import '../models/models.dart';

DateTime dateOnly(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

bool sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

int _daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;

DateTime _addMonthsClamped(DateTime day, int months) {
  final monthIndex = day.month - 1 + months;
  final year = day.year + monthIndex ~/ 12;
  final month = (monthIndex % 12) + 1;
  final clampedDay = day.day.clamp(1, _daysInMonth(year, month));
  return DateTime(year, month, clampedDay);
}

DateTime addRepeat(DateTime day, RepeatFrequency repeat) {
  switch (repeat) {
    case RepeatFrequency.none:
      return day;
    case RepeatFrequency.daily:
      return day.add(const Duration(days: 1));
    case RepeatFrequency.weekly:
      return day.add(const Duration(days: 7));
    case RepeatFrequency.monthly:
      return _addMonthsClamped(day, 1);
  }
}

/// Whether [entry] should be visible on [day].
///
/// Notes:
/// - Legacy entries with `entry.day == null` are treated as "floating" and will
///   be visible on any day (keeps backwards compatibility).
/// - For anchored entries, we interpret [repeat] relative to the anchor [day].
bool occursOnDay(ScheduleEntry entry, DateTime day) {
  final target = dateOnly(day);

  final anchorRaw = entry.day;
  if (anchorRaw == null) return true;

  final anchor = dateOnly(anchorRaw);
  if (target.isBefore(anchor)) return false;

  final untilRaw = entry.repeatUntil;
  if (untilRaw != null && target.isAfter(dateOnly(untilRaw))) return false;

  switch (entry.repeat) {
    case RepeatFrequency.none:
      return sameDay(anchor, target);
    case RepeatFrequency.daily:
      return true;
    case RepeatFrequency.weekly:
      return target.difference(anchor).inDays % 7 == 0;
    case RepeatFrequency.monthly:
      var d = anchor;
      var safety = 0;
      while (d.isBefore(target) && safety < 600) {
        d = _addMonthsClamped(d, 1);
        safety++;
      }
      return sameDay(d, target);
  }
}

List<ScheduleEntry> entriesForDay({
  required DateTime day,
  required List<ScheduleEntry> allEntries,
}) {
  final target = dateOnly(day);
  return allEntries.where((e) => occursOnDay(e, target)).toList(growable: false);
}

DateTime startOfWeek(DateTime day, {int weekStartsOn = DateTime.monday}) {
  final d = dateOnly(day);
  final delta = (d.weekday - weekStartsOn) % 7;
  return d.subtract(Duration(days: delta));
}

