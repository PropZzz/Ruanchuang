// MCP (multi-app fusion) ingest: parse pasted external messages into
// normalized event fields for schedule upsert.
//
// Design goals:
// - Robust to common "key: value" formats and short natural-language Chinese.
// - No dependencies; pure Dart so it's easy to unit test.

class McpParsedEvent {
  final String uid;
  final String title;
  final DateTime start;
  final int minutes;
  final String source;

  const McpParsedEvent({
    required this.uid,
    required this.title,
    required this.start,
    required this.minutes,
    required this.source,
  });
}

class McpIngest {
  static McpParsedEvent? parse(
    String raw, {
    DateTime? now,
    String source = 'MCP',
  }) {
    final text = raw.trim();
    if (text.isEmpty) return null;

    final anchorNow = now ?? DateTime.now();

    String? pickUid() {
      final uidRe = RegExp(
        r'^(uid|id|event\s*id|meeting\s*id|会议id|会议ID|航班号|航班编号)\s*[:=：]\s*([^\s]+)\s*$',
        multiLine: true,
        caseSensitive: false,
      );
      final m = uidRe.firstMatch(text);
      return m?.group(2)?.trim();
    }

    String pickTitle() {
      final titleRe = RegExp(
        r'^(主题|标题|title|summary|subject)\s*[:=：]\s*(.+?)\s*$',
        multiLine: true,
        caseSensitive: false,
      );
      final m = titleRe.firstMatch(text);
      if (m != null) return (m.group(2) ?? '').trim();

      // Fallback: first non-empty line that doesn't look like a field header.
      final lines = text.split(RegExp(r'\r?\n')).map((e) => e.trim()).toList();
      for (final line in lines) {
        if (line.isEmpty) continue;
        if (_looksLikeFieldLine(line)) continue;
        return line;
      }
      // Last resort.
      return lines.firstWhere((e) => e.isNotEmpty, orElse: () => 'External Event');
    }

    DateTime? pickStartAndMaybeDuration(_MutableInt minutesOut) {
      final baseDay = _pickBaseDay(text, anchorNow);

      // 0) Fast path: date + time range with ASCII separators, e.g.
      // "2026-03-18 09:30-11:00".
      //
      // This avoids an ordering pitfall where a single-datetime matcher can
      // consume the prefix "2026-03-18 09:30" and we lose the inferred duration.
      final rangeAscii = RegExp(
        r'(\d{4})[\/\-.](\d{1,2})[\/\-.](\d{1,2}).{0,20}?(\d{1,2}):(\d{2})\s*[-~]\s*(\d{1,2}):(\d{2})',
      );
      final m0 = rangeAscii.firstMatch(text);
      if (m0 != null) {
        final y = int.tryParse(m0.group(1) ?? '');
        final mo = int.tryParse(m0.group(2) ?? '');
        final d = int.tryParse(m0.group(3) ?? '');
        final sh = int.tryParse(m0.group(4) ?? '');
        final sm = int.tryParse(m0.group(5) ?? '');
        final eh = int.tryParse(m0.group(6) ?? '');
        final em = int.tryParse(m0.group(7) ?? '');
        if (y != null &&
            mo != null &&
            d != null &&
            sh != null &&
            sm != null &&
            eh != null &&
            em != null) {
          final start = DateTime(y, mo, d, sh, sm);
          final end = DateTime(y, mo, d, eh, em);
          final diff = end.difference(start).inMinutes;
          if (diff > 0) minutesOut.value = diff.clamp(1, 24 * 60);
          return start;
        }
      }

      // 1) Full datetime: 2026-03-16 15:00
      final dtRe = RegExp(
        r'(\d{4})[\/\-.](\d{1,2})[\/\-.](\d{1,2})\s+(\d{1,2})[:：](\d{2})',
      );
      final m1 = dtRe.firstMatch(text);
      if (m1 != null) {
        final y = int.tryParse(m1.group(1) ?? '');
        final mo = int.tryParse(m1.group(2) ?? '');
        final d = int.tryParse(m1.group(3) ?? '');
        final hh = int.tryParse(m1.group(4) ?? '');
        final mm = int.tryParse(m1.group(5) ?? '');
        if (y != null && mo != null && d != null && hh != null && mm != null) {
          return DateTime(y, mo, d, hh, mm);
        }
      }

      // 2) Chinese date: 2026年3月16日 15:00
      final cnDtRe = RegExp(
        r'(\d{4})\s*年\s*(\d{1,2})\s*月\s*(\d{1,2})\s*日?.{0,10}?(\d{1,2})[:：](\d{2})',
      );
      final m2 = cnDtRe.firstMatch(text);
      if (m2 != null) {
        final y = int.tryParse(m2.group(1) ?? '');
        final mo = int.tryParse(m2.group(2) ?? '');
        final d = int.tryParse(m2.group(3) ?? '');
        final hh = int.tryParse(m2.group(4) ?? '');
        final mm = int.tryParse(m2.group(5) ?? '');
        if (y != null && mo != null && d != null && hh != null && mm != null) {
          return DateTime(y, mo, d, hh, mm);
        }
      }

      // 3) Date + time range: 2026-03-16 15:00-16:30
      final rangeWithDate = RegExp(
        r'(\d{4})[\/\-.](\d{1,2})[\/\-.](\d{1,2}).{0,20}?(\d{1,2})[:：](\d{2})\s*[-~到至]\s*(\d{1,2})[:：](\d{2})',
      );
      final m3 = rangeWithDate.firstMatch(text);
      if (m3 != null) {
        final y = int.tryParse(m3.group(1) ?? '');
        final mo = int.tryParse(m3.group(2) ?? '');
        final d = int.tryParse(m3.group(3) ?? '');
        final sh = int.tryParse(m3.group(4) ?? '');
        final sm = int.tryParse(m3.group(5) ?? '');
        final eh = int.tryParse(m3.group(6) ?? '');
        final em = int.tryParse(m3.group(7) ?? '');
        if (y != null &&
            mo != null &&
            d != null &&
            sh != null &&
            sm != null &&
            eh != null &&
            em != null) {
          final start = DateTime(y, mo, d, sh, sm);
          final end = DateTime(y, mo, d, eh, em);
          final diff = end.difference(start).inMinutes;
          if (diff > 0) minutesOut.value = diff.clamp(1, 24 * 60);
          return start;
        }
      }

      // 4) Time range (no date): 15:00-16:30
      final rangeRe = RegExp(
        r'\b(\d{1,2})[:：](\d{2})\s*[-~到至]\s*(\d{1,2})[:：](\d{2})\b',
      );
      final m4 = rangeRe.firstMatch(text);
      if (m4 != null) {
        final sh = int.tryParse(m4.group(1) ?? '');
        final sm = int.tryParse(m4.group(2) ?? '');
        final eh = int.tryParse(m4.group(3) ?? '');
        final em = int.tryParse(m4.group(4) ?? '');
        if (sh != null && sm != null && eh != null && em != null) {
          final start = DateTime(baseDay.year, baseDay.month, baseDay.day, sh, sm);
          final end = DateTime(baseDay.year, baseDay.month, baseDay.day, eh, em);
          final diff = end.difference(start).inMinutes;
          if (diff > 0) minutesOut.value = diff.clamp(1, 24 * 60);
          return start;
        }
      }

      // 5) HH:MM (uses base day)
      final hmRe = RegExp(r'\b(\d{1,2})[:：](\d{2})\b');
      final m5 = hmRe.firstMatch(text);
      if (m5 != null) {
        final h = int.tryParse(m5.group(1) ?? '');
        final mi = int.tryParse(m5.group(2) ?? '');
        if (h != null && mi != null && _validHm(h, mi)) {
          return DateTime(baseDay.year, baseDay.month, baseDay.day, h, mi);
        }
      }

      // 6) Chinese hour formats: 明天下午3点 / 3点半 / 3点15
      final cnTimeRe = RegExp(
        r'(上午|中午|下午|晚上|早上|傍晚|凌晨)?\s*(\d{1,2})\s*点(?:(\d{1,2})\s*分?)?(半)?',
      );
      final m6 = cnTimeRe.firstMatch(text);
      if (m6 != null) {
        final prefix = (m6.group(1) ?? '').trim();
        var hour = int.tryParse(m6.group(2) ?? '');
        var minute = int.tryParse(m6.group(3) ?? '');
        final half = m6.group(4) != null;
        if (hour != null) {
          minute ??= half ? 30 : 0;
          hour = _applyMeridiem(prefix, hour);
          if (_validHm(hour, minute)) {
            return DateTime(baseDay.year, baseDay.month, baseDay.day, hour, minute);
          }
        }
      }

      return null;
    }

    int pickMinutes({required int defaultMinutes}) {
      // Prefer an explicit "duration" line if present.
      final durLineRe = RegExp(
        r'^(时长|持续|duration)\s*[:=：]\s*(.+?)\s*$',
        multiLine: true,
        caseSensitive: false,
      );
      final durLine = durLineRe.firstMatch(text)?.group(2)?.trim();

      int? parseFrom(String s) {
        // Hours: 1.5小时 / 2h / 2 hours
        final hRe = RegExp(
          // Note: avoid `\b` here; it doesn't work well with CJK units like "小时".
          r'(\d+(?:\.\d+)?)\s*(小时|h|hr|hrs|hour|hours)',
          caseSensitive: false,
        );
        final hm = hRe.firstMatch(s);
        if (hm != null) {
          final v = double.tryParse(hm.group(1) ?? '');
          if (v != null && v > 0) {
            return (v * 60).round().clamp(1, 24 * 60);
          }
        }

        // Minutes: 60分钟 / 45 min
        final mRe = RegExp(
          // Same as above: no `\b` for better CJK compatibility.
          r'(\d{1,3})\s*(分钟|min|mins|minute|minutes)',
          caseSensitive: false,
        );
        final mm = mRe.firstMatch(s);
        if (mm != null) {
          final v = int.tryParse(mm.group(1) ?? '');
          if (v != null && v > 0) return v.clamp(1, 24 * 60);
        }
        return null;
      }

      final parsed = parseFrom(durLine ?? text);
      return parsed ?? defaultMinutes.clamp(1, 24 * 60);
    }

    final minutesFromRange = _MutableInt(null);
    final start = pickStartAndMaybeDuration(minutesFromRange);
    if (start == null) return null;

    final uid = pickUid() ?? _fnv1a32(text);
    final title = pickTitle();
    final minutes = minutesFromRange.value ?? pickMinutes(defaultMinutes: 60);

    return McpParsedEvent(
      uid: uid,
      title: title,
      start: start,
      minutes: minutes,
      source: source,
    );
  }
}

bool _looksLikeFieldLine(String line) {
  final re = RegExp(
    r'^(uid|id|event\s*id|meeting\s*id|主题|标题|title|summary|subject|时间|time|when|时长|持续|duration)\s*[:=：]',
    caseSensitive: false,
  );
  return re.hasMatch(line);
}

DateTime _pickBaseDay(String text, DateTime now) {
  final d0 = DateTime(now.year, now.month, now.day);
  final lower = text.toLowerCase();

  if (text.contains('后天')) return d0.add(const Duration(days: 2));
  if (text.contains('明天') || lower.contains('tomorrow')) return d0.add(const Duration(days: 1));
  if (text.contains('今天') || lower.contains('today')) return d0;

  // Default: today.
  return d0;
}

bool _validHm(int hour, int minute) {
  return hour >= 0 && hour <= 23 && minute >= 0 && minute <= 59;
}

int _applyMeridiem(String prefix, int hour) {
  if (hour < 0 || hour > 23) return hour;

  final isPm = prefix.contains('下午') || prefix.contains('晚上') || prefix.contains('傍晚');
  if (isPm && hour < 12) return hour + 12;

  // "中午1点" typically means 13:00.
  if (prefix.contains('中午') && hour < 11) return hour + 12;

  return hour;
}

String _fnv1a32(String input) {
  // Stable, simple hash for IDs.
  var hash = 0x811c9dc5;
  for (final c in input.codeUnits) {
    hash ^= c;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

class _MutableInt {
  int? value;
  _MutableInt(this.value);
}
