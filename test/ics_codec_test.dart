import 'package:flutter_test/flutter_test.dart';

import 'package:shixuzhipei/services/ics/ics_codec.dart';

void main() {
  test('ICS encode/decode roundtrip keeps core fields', () {
    final created = DateTime(2026, 1, 1, 0, 0);

    final events = [
      IcsEvent(
        uid: 'u1',
        start: DateTime(2026, 1, 1, 9, 0),
        end: DateTime(2026, 1, 1, 10, 0),
        summary: 'Meeting, A;B',
        description: 'Line1\nLine2',
      ),
    ];

    final ics = IcsCodec.encodeCalendar(events: events, createdAt: created);
    final parsed = IcsCodec.decodeCalendar(ics);

    expect(parsed.length, 1);
    expect(parsed[0].uid, 'u1');
    expect(parsed[0].summary, 'Meeting, A;B');
    expect(parsed[0].description, 'Line1\nLine2');
    expect(parsed[0].start.year, 2026);
    expect(parsed[0].start.month, 1);
    expect(parsed[0].start.day, 1);
    expect(parsed[0].start.hour, 9);
    expect(parsed[0].end.hour, 10);
  });

  test('ICS encode folds long unicode lines and roundtrips them', () {
    final created = DateTime(2026, 1, 1, 0, 0);
    final summary = List.filled(30, '计划评审').join();

    final events = [
      IcsEvent(
        uid: 'u2',
        start: DateTime(2026, 1, 1, 9, 0),
        end: DateTime(2026, 1, 1, 10, 0),
        summary: summary,
        description: '中文描述',
      ),
    ];

    final ics = IcsCodec.encodeCalendar(events: events, createdAt: created);

    expect(ics.contains('\r\n '), true);

    final parsed = IcsCodec.decodeCalendar(ics);
    expect(parsed.length, 1);
    expect(parsed.single.summary, summary);
    expect(parsed.single.description, '中文描述');
  });

  test('ICS decode supports duration-only events', () {
    final ics = [
      'BEGIN:VCALENDAR',
      'VERSION:2.0',
      'CALSCALE:GREGORIAN',
      'PRODID:-//sxzppp//BattleMan//EN',
      'BEGIN:VEVENT',
      'UID:duration-1',
      'DTSTART:20260316T090000',
      'DURATION:PT90M',
      'SUMMARY:Duration test',
      'END:VEVENT',
      'END:VCALENDAR',
      '',
    ].join('\r\n');

    final parsed = IcsCodec.decodeCalendar(ics);
    expect(parsed.length, 1);
    expect(
      parsed.single.end.difference(parsed.single.start),
      const Duration(minutes: 90),
    );
  });
}
