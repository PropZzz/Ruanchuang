import 'package:flutter/material.dart';

import '../../models/models.dart';
import 'ics_codec.dart';

int _durationFromHeight(double height) {
  final mins = (height / 80.0) * 60.0;
  return mins.round().clamp(1, 24 * 60).toInt();
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
      final uid = _uidForEntry(e: e, day: day, start: start);

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

      var minutes = ev.end.difference(ev.start).inMinutes;
      if (minutes <= 0) minutes = 60;
      minutes = minutes.clamp(1, 24 * 60).toInt();
      final tag = _tagFromDescription(ev.description) ?? 'Imported';
      final id = _entryIdFromUid(ev.uid);

      out.add(
        ScheduleEntry(
          id: id,
          day: d,
          title: ev.summary,
          tag: tag,
          height: _heightFromMinutes(minutes),
          color: Colors.purple,
          time: TimeOfDay(hour: s.hour, minute: s.minute),
        ),
      );
    }

    return out;
  }

  static String _uidForEntry({
    required ScheduleEntry e,
    required DateTime day,
    required DateTime start,
  }) {
    final id = e.id;
    if (id != null && id.isNotEmpty) {
      if (id.startsWith('ics_')) return id.substring(4);
      if (id.startsWith('sxzppp-')) return id;
      return 'sxzppp-$id';
    }
    return 'sxzppp-${day.microsecondsSinceEpoch}-${start.microsecondsSinceEpoch}';
  }

  static String? _entryIdFromUid(String uid) {
    final trimmed = uid.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.startsWith('sxzppp-')) {
      return trimmed.substring('sxzppp-'.length);
    }
    return 'ics_$trimmed';
  }

  static String? _tagFromDescription(String description) {
    final re = RegExp(
      r'\btag\s*[:=]\s*([^\n\r]+)',
      caseSensitive: false,
    );
    final m = re.firstMatch(description);
    if (m == null) return null;
    final tag = (m.group(1) ?? '').trim();
    return tag.isEmpty ? null : tag;
  }
}
