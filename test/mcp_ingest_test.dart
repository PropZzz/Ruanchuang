import 'package:flutter_test/flutter_test.dart';

import 'package:sxzppp/services/mcp/mcp_ingest.dart';

void main() {
  test('parses structured fields (UID/主题/时间/时长)', () {
    final now = DateTime(2026, 3, 15, 10, 0);
    final ev = McpIngest.parse(
      'UID: zoom-123\n主题: 客户会议\n时间: 2026-03-16 15:00\n时长: 60 分钟',
      now: now,
    );
    expect(ev, isNotNull);
    expect(ev!.uid, 'zoom-123');
    expect(ev.title, '客户会议');
    expect(ev.start, DateTime(2026, 3, 16, 15, 0));
    expect(ev.minutes, 60);
  });

  test('parses natural Chinese time + minutes', () {
    final now = DateTime(2026, 3, 15, 10, 0);
    final ev = McpIngest.parse('明天下午3点 客户会议 90分钟', now: now);
    expect(ev, isNotNull);
    expect(ev!.start, DateTime(2026, 3, 16, 15, 0));
    expect(ev.minutes, 90);
  });

  test('parses time range and infers duration', () {
    final now = DateTime(2026, 3, 15, 10, 0);
    final ev = McpIngest.parse(
      'UID: flight-77\n标题: 登机\n时间: 2026-03-18 09:30-11:00',
      now: now,
    );
    expect(ev, isNotNull);
    expect(ev!.uid, 'flight-77');
    expect(ev.title, '登机');
    expect(ev.start, DateTime(2026, 3, 18, 9, 30));
    expect(ev.minutes, 90);
  });

  test('parses hours (1.5小时) as minutes', () {
    final now = DateTime(2026, 3, 15, 10, 0);
    final ev = McpIngest.parse('后天 10:00 复盘 1.5小时', now: now);
    expect(ev, isNotNull);
    expect(ev!.start, DateTime(2026, 3, 17, 10, 0));
    expect(ev.minutes, 90);
  });
}

