import 'package:flutter_test/flutter_test.dart';

import 'package:sxzppp/services/ics/ics_codec.dart';

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
}
