import 'package:flutter_test/flutter_test.dart';
import 'package:shixuzhipei/services/mcp/mcp_ingest.dart';

void main() {
  test('parses structured fields with explicit date and duration', () {
    final now = DateTime(2026, 3, 15, 10, 0);
    final ev = McpIngest.parse(
      'UID: zoom-123\nTitle: Customer Meeting\nTime: 2026-03-16 15:00\nDuration: 60 min',
      now: now,
    );
    expect(ev, isNotNull);
    expect(ev!.uid, 'zoom-123');
    expect(ev.title, 'Customer Meeting');
    expect(ev.start, DateTime(2026, 3, 16, 15, 0));
    expect(ev.minutes, 60);
  });

  test('parses natural Chinese time and minutes', () {
    final now = DateTime(2026, 3, 15, 10, 0);
    final ev = McpIngest.parse('明天下午3点 客户会议 90分钟', now: now);
    expect(ev, isNotNull);
    expect(ev!.start, DateTime(2026, 3, 16, 15, 0));
    expect(ev.minutes, 90);
  });

  test('parses date range and infers duration', () {
    final now = DateTime(2026, 3, 15, 10, 0);
    final ev = McpIngest.parse(
      'UID: flight-77\nTitle: Boarding\nTime: 2026-03-18 09:30-11:00',
      now: now,
    );
    expect(ev, isNotNull);
    expect(ev!.uid, 'flight-77');
    expect(ev.title, 'Boarding');
    expect(ev.start, DateTime(2026, 3, 18, 9, 30));
    expect(ev.minutes, 90);
  });

  test('parses ICS DTSTART and DTEND', () {
    final ev = McpIngest.parse(
      'BEGIN:VCALENDAR\nBEGIN:VEVENT\nUID:ics-001\nSUMMARY:Sprint Review\nDTSTART:20260320T070000\nDTEND:20260320T083000\nEND:VEVENT\nEND:VCALENDAR',
      now: DateTime(2026, 3, 19, 12, 0),
    );
    expect(ev, isNotNull);
    expect(ev!.uid, 'ics-001');
    expect(ev.title, 'Sprint Review');
    expect(ev.start, DateTime(2026, 3, 20, 7, 0));
    expect(ev.minutes, 90);
  });

  test('parses ICS DTSTART with TZID and ISO duration', () {
    final ev = McpIngest.parse(
      'BEGIN:VEVENT\nUID:ics-002\nSUMMARY:Demo Sync\nDTSTART;TZID=Asia/Shanghai:20260321T140000\nDURATION:PT45M\nEND:VEVENT',
    );
    expect(ev, isNotNull);
    expect(ev!.uid, 'ics-002');
    expect(ev.title, 'Demo Sync');
    expect(ev.start, DateTime(2026, 3, 21, 14, 0));
    expect(ev.minutes, 45);
  });

  test('parses Outlook-style start and end lines', () {
    final ev = McpIngest.parse(
      'Subject: Product Planning\nStart: Monday, March 23, 2026 3:00 PM\nEnd: Monday, March 23, 2026 4:15 PM',
      now: DateTime(2026, 3, 20, 9, 0),
    );
    expect(ev, isNotNull);
    expect(ev!.title, 'Product Planning');
    expect(ev.start, DateTime(2026, 3, 23, 15, 0));
    expect(ev.minutes, 75);
  });

  test('falls back to deterministic uid hash when uid missing', () {
    const raw = 'Title: Quick sync\nTime: 2026-03-16 10:00\nDuration: 30 min';
    final first = McpIngest.parse(raw);
    final second = McpIngest.parse(raw);
    expect(first, isNotNull);
    expect(second, isNotNull);
    expect(first!.uid, second!.uid);
    expect(first.uid, isNotEmpty);
  });
}
