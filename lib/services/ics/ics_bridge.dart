import 'package:flutter/material.dart';

import '../../models/models.dart';
import 'ics_codec.dart';

int _durationFromHeight(double height) {
  final mins = (height / 80.0) * 60.0;
  return mins.round().clamp(1, 24 * 60);
}

double _heightFromMinutes(int minutes) {
  return (minutes / 60.0) * 80.0;
}

DateTime _atDay(DateTime day, TimeOfDay tod) {
  return DateTime(day.year, day.month, day.day, tod.hour, tod.minute);
}

class IcsBridge {
  /// Export schedule entries on [day] to ICS events.
  static List<IcsEvent> scheduleToEvents({
    required DateTime day,
    required List<ScheduleEntry> entries,
  }) {
    final out = <IcsEvent>[];
    for (final e in entries) {
      final start = _atDay(day, e.time);
      final minutes = _durationFromHeight(e.height);
      final end = start.add(Duration(minutes: minutes));
      final uid = (e.id != null && e.id!.isNotEmpty)
          ? 'sxzppp-${e.id}'
          : 'sxzppp-${day.microsecondsSinceEpoch}-${start.microsecondsSinceEpoch}';

      final desc = e.tag.isEmpty ? '' : 'tag: ${e.tag}';
      out.add(
        IcsEvent(
          uid: uid,
          start: start,
          end: end,
          summary: e.title,
          description: desc,
        ),
      );
    }
    return out;
  }

  /// Import ICS events to schedule entries.
  ///
  /// P0 boundary:
  /// - Recurrence (RRULE) ignored.
  /// - All imported times are interpreted as local device time.
  static List<ScheduleEntry> eventsToSchedule({
    required DateTime day,
    required List<IcsEvent> events,
  }) {
    final d = DateTime(day.year, day.month, day.day);
    final out = <ScheduleEntry>[];

    for (final ev in events) {
      // Only import events that fall on the target day.
      final s = ev.start.toLocal();
      if (s.year != d.year || s.month != d.month || s.day != d.day) {
        continue;
      }

      final minutes = ev.end.difference(ev.start).inMinutes.clamp(1, 24 * 60);

      out.add(
        ScheduleEntry(
          id: 'ics_${ev.uid}',
          day: d,
          title: ev.summary,
          tag: 'Imported',
          height: _heightFromMinutes(minutes),
          color: Colors.purple,
          time: TimeOfDay(hour: s.hour, minute: s.minute),
        ),
      );
    }

    return out;
  }
}
