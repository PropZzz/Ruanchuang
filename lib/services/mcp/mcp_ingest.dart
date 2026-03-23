// MCP (multi-app fusion) ingest: parse pasted external messages into
// normalized event fields for schedule upsert.
//
// Design goals:
// - Robust to common "key: value" formats and short natural-language Chinese.
// - Deterministic parsing for Outlook/Email/ICS-like pasted text.
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
      final uidLine = _pickFieldValue(
        text,
        aliases: const [
          'uid',
          'id',
          'event id',
          'meeting id',
          '会议id',
          '会议ID',
          '会议信息id',
        ],
      );
      if (uidLine != null && uidLine.isNotEmpty) return uidLine;

      // ICS lines may look like: UID:abc-123@domain
      final icsUid = RegExp(r'^\s*UID\s*:\s*(.+)\s*$', multiLine: true, caseSensitive: false)
          .firstMatch(text)
          ?.group(1)
          ?.trim();
      if (icsUid != null && icsUid.isNotEmpty) return icsUid;
      return null;
    }

    String pickTitle() {
      final fieldTitle = _pickFieldValue(
        text,
        aliases: const [
          '主题',
          '标题',
          'title',
          'summary',
          'subject',
          '会议主题',
        ],
      );
      if (fieldTitle != null && fieldTitle.isNotEmpty) return fieldTitle;

      // ICS summary.
      final icsSummary = RegExp(
        r'^\s*SUMMARY\s*:\s*(.+)\s*$',
        multiLine: true,
        caseSensitive: false,
      ).firstMatch(text)?.group(1)?.trim();
      if (icsSummary != null && icsSummary.isNotEmpty) return icsSummary;

      // Fallback: first non-empty line that doesn't look like a field header.
      final lines = text.split(RegExp(r'\r?\n')).map((e) => e.trim()).toList();
      for (final line in lines) {
        if (line.isEmpty) continue;
        if (_looksLikeFieldLine(line)) continue;
        return line;
      }
      return lines.firstWhere((e) => e.isNotEmpty, orElse: () => 'External Event');
    }

    DateTime? pickStartAndMaybeDuration(_MutableInt minutesOut) {
      final baseDay = _pickBaseDay(text, anchorNow);

      // 0) ICS-like DTSTART / DTEND (most deterministic).
      final icsStartRaw = _pickIcsDateValue(text, key: 'DTSTART');
      if (icsStartRaw != null) {
        final icsStart = _parseIcsDateTime(icsStartRaw);
        if (icsStart != null) {
          final icsEndRaw = _pickIcsDateValue(text, key: 'DTEND');
          final icsEnd = (icsEndRaw == null) ? null : _parseIcsDateTime(icsEndRaw);
          if (icsEnd != null) {
            final diff = icsEnd.difference(icsStart).inMinutes;
            if (diff > 0) minutesOut.value = diff.clamp(1, 24 * 60);
          } else {
            final icsDurationRaw = _pickIcsDateValue(text, key: 'DURATION');
            final icsDuration = (icsDurationRaw == null) ? null : _parseIsoDurationMinutes(icsDurationRaw);
            if (icsDuration != null && icsDuration > 0) {
              minutesOut.value = icsDuration.clamp(1, 24 * 60);
            }
          }
          return icsStart;
        }
      }

      // 1) Outlook / email structured start/end lines.
      final startField = _pickFieldValue(
        text,
        aliases: const ['start', '开始', '开始时间', 'when', 'time', '时间'],
      );
      final endField = _pickFieldValue(
        text,
        aliases: const ['end', '结束', '结束时间'],
      );
      final startFromField = (startField == null)
          ? null
          : _parseFlexibleDateTime(startField, baseDay: baseDay, minutesOut: minutesOut);
      final endFromField = (endField == null)
          ? null
          : _parseFlexibleDateTime(endField, baseDay: baseDay);
      if (startFromField != null) {
        if (endFromField != null) {
          final diff = endFromField.difference(startFromField).inMinutes;
          if (diff > 0) minutesOut.value = diff.clamp(1, 24 * 60);
        }
        return startFromField;
      }

      // 2) Date + time range with ASCII separators, e.g. 2026-03-18 09:30-11:00.
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
        if (y != null && mo != null && d != null && sh != null && sm != null && eh != null && em != null) {
          final start = DateTime(y, mo, d, sh, sm);
          final end = DateTime(y, mo, d, eh, em);
          final diff = end.difference(start).inMinutes;
          if (diff > 0) minutesOut.value = diff.clamp(1, 24 * 60);
          return start;
        }
      }

      // 3) Full datetime: 2026-03-16 15:00.
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

      // 4) Chinese date: 2026年3月16日 15:00.
      final cnDtRe = RegExp(
        r'(\d{4})\s*年\s*(\d{1,2})\s*月\s*(\d{1,2})\s*日.{0,10}?(\d{1,2})[:：](\d{2})',
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

      // 5) Date + time range: 2026-03-16 15:00-16:30 or ... to 16:30.
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
        if (y != null && mo != null && d != null && sh != null && sm != null && eh != null && em != null) {
          final start = DateTime(y, mo, d, sh, sm);
          final end = DateTime(y, mo, d, eh, em);
          final diff = end.difference(start).inMinutes;
          if (diff > 0) minutesOut.value = diff.clamp(1, 24 * 60);
          return start;
        }
      }
      final rangeWithDateAlt = RegExp(
        r'(\d{4})[\/\-.](\d{1,2})[\/\-.](\d{1,2}).{0,20}?(\d{1,2}):(\d{2})\s*(?:to|until)\s*(\d{1,2}):(\d{2})',
        caseSensitive: false,
      );
      final m3b = rangeWithDateAlt.firstMatch(text);
      if (m3b != null) {
        final y = int.tryParse(m3b.group(1) ?? '');
        final mo = int.tryParse(m3b.group(2) ?? '');
        final d = int.tryParse(m3b.group(3) ?? '');
        final sh = int.tryParse(m3b.group(4) ?? '');
        final sm = int.tryParse(m3b.group(5) ?? '');
        final eh = int.tryParse(m3b.group(6) ?? '');
        final em = int.tryParse(m3b.group(7) ?? '');
        if (y != null && mo != null && d != null && sh != null && sm != null && eh != null && em != null) {
          final start = DateTime(y, mo, d, sh, sm);
          final end = DateTime(y, mo, d, eh, em);
          final diff = end.difference(start).inMinutes;
          if (diff > 0) minutesOut.value = diff.clamp(1, 24 * 60);
          return start;
        }
      }

      // 6) Date + time with loose separator: 2026-03-16 at 15:00.
      final dtLooseRe = RegExp(
        r'(\d{4})[\/\-.](\d{1,2})[\/\-.](\d{1,2})\D+(\d{1,2}):(\d{2})',
      );
      final m3c = dtLooseRe.firstMatch(text);
      if (m3c != null) {
        final y = int.tryParse(m3c.group(1) ?? '');
        final mo = int.tryParse(m3c.group(2) ?? '');
        final d = int.tryParse(m3c.group(3) ?? '');
        final hh = int.tryParse(m3c.group(4) ?? '');
        final mm = int.tryParse(m3c.group(5) ?? '');
        if (y != null && mo != null && d != null && hh != null && mm != null) {
          return DateTime(y, mo, d, hh, mm);
        }
      }

      // 7) Time range without date: 15:00-16:30 or 15:00 to 16:30.
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
      final rangeToRe = RegExp(
        r'\b(\d{1,2}):(\d{2})\s*(?:to|until)\s*(\d{1,2}):(\d{2})\b',
        caseSensitive: false,
      );
      final m4b = rangeToRe.firstMatch(text);
      if (m4b != null) {
        final sh = int.tryParse(m4b.group(1) ?? '');
        final sm = int.tryParse(m4b.group(2) ?? '');
        final eh = int.tryParse(m4b.group(3) ?? '');
        final em = int.tryParse(m4b.group(4) ?? '');
        if (sh != null && sm != null && eh != null && em != null) {
          final start = DateTime(baseDay.year, baseDay.month, baseDay.day, sh, sm);
          final end = DateTime(baseDay.year, baseDay.month, baseDay.day, eh, em);
          final diff = end.difference(start).inMinutes;
          if (diff > 0) minutesOut.value = diff.clamp(1, 24 * 60);
          return start;
        }
      }

      // 8) AM/PM: 3pm / 3:15 PM.
      final ampmRe = RegExp(
        r'\b(\d{1,2})(?::(\d{2}))?\s*(am|pm)\b',
        caseSensitive: false,
      );
      final m5b = ampmRe.firstMatch(text);
      if (m5b != null) {
        var hour = int.tryParse(m5b.group(1) ?? '');
        final minute = int.tryParse(m5b.group(2) ?? '') ?? 0;
        final meridiem = (m5b.group(3) ?? '').toLowerCase();
        if (hour != null) {
          if (meridiem == 'pm' && hour < 12) hour += 12;
          if (meridiem == 'am' && hour == 12) hour = 0;
          if (_validHm(hour, minute)) {
            return DateTime(baseDay.year, baseDay.month, baseDay.day, hour, minute);
          }
        }
      }

      // 9) HH:MM (uses base day).
      final hmRe = RegExp(r'\b(\d{1,2})[:：](\d{2})\b');
      final m5 = hmRe.firstMatch(text);
      if (m5 != null) {
        final h = int.tryParse(m5.group(1) ?? '');
        final mi = int.tryParse(m5.group(2) ?? '');
        if (h != null && mi != null && _validHm(h, mi)) {
          return DateTime(baseDay.year, baseDay.month, baseDay.day, h, mi);
        }
      }

      // 10) Chinese hour formats: 明天下午3点 / 3点半 / 3点15.
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

      // 11) Date only: 2026-03-16 (default 09:00).
      final dateOnlyRe = RegExp(
        r'^\s*(\d{4})[\/\-.](\d{1,2})[\/\-.](\d{1,2})\s*$',
        multiLine: true,
      );
      final m7 = dateOnlyRe.firstMatch(text);
      if (m7 != null) {
        final y = int.tryParse(m7.group(1) ?? '');
        final mo = int.tryParse(m7.group(2) ?? '');
        final d = int.tryParse(m7.group(3) ?? '');
        if (y != null && mo != null && d != null) {
          return DateTime(y, mo, d, 9, 0);
        }
      }
      return null;
    }

    int pickMinutes({required int defaultMinutes}) {
      final durLine = _pickFieldValue(
        text,
        aliases: const ['时长', '持续', 'duration'],
      );

      int? parseFrom(String s) {
        final hRe = RegExp(
          r'(\d+(?:\.\d+)?)\s*(小时|h|hr|hrs|hour|hours)',
          caseSensitive: false,
        );
        final hm = hRe.firstMatch(s);
        if (hm != null) {
          final v = double.tryParse(hm.group(1) ?? '');
          if (v != null && v > 0) return (v * 60).round().clamp(1, 24 * 60);
        }

        final mRe = RegExp(
          r'(\d{1,3})\s*(分钟|min|mins|minute|minutes)',
          caseSensitive: false,
        );
        final mm = mRe.firstMatch(s);
        if (mm != null) {
          final v = int.tryParse(mm.group(1) ?? '');
          if (v != null && v > 0) return v.clamp(1, 24 * 60);
        }

        final iso = _parseIsoDurationMinutes(s);
        if (iso != null && iso > 0) return iso.clamp(1, 24 * 60);
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

String? _pickFieldValue(
  String text, {
  required List<String> aliases,
}) {
  for (final alias in aliases) {
    final re = RegExp(
      '^\\s*${RegExp.escape(alias)}\\s*[:=：]\\s*(.+?)\\s*\$',
      multiLine: true,
      caseSensitive: false,
    );
    final m = re.firstMatch(text);
    final v = m?.group(1)?.trim();
    if (v != null && v.isNotEmpty) return v;
  }
  return null;
}

String? _pickIcsDateValue(String text, {required String key}) {
  // Accept:
  // - DTSTART:20260316T150000
  // - DTSTART;TZID=Asia/Shanghai:20260316T150000
  // - DTSTART;VALUE=DATE:20260316
  final re = RegExp(
    '^\\s*${RegExp.escape(key)}(?:;[^:\\r\\n]*)?\\s*:\\s*(.+?)\\s*\$',
    multiLine: true,
    caseSensitive: false,
  );
  return re.firstMatch(text)?.group(1)?.trim();
}

DateTime? _parseIcsDateTime(String value) {
  final v = value.trim();
  if (v.isEmpty) return null;

  // YYYYMMDDTHHMMSS(Z)?
  final dt = RegExp(r'^(\d{8})T(\d{6})(Z)?$', caseSensitive: false).firstMatch(v);
  if (dt != null) {
    final date = dt.group(1)!;
    final time = dt.group(2)!;
    final year = int.tryParse(date.substring(0, 4));
    final month = int.tryParse(date.substring(4, 6));
    final day = int.tryParse(date.substring(6, 8));
    final hour = int.tryParse(time.substring(0, 2));
    final minute = int.tryParse(time.substring(2, 4));
    final second = int.tryParse(time.substring(4, 6));
    if (year != null &&
        month != null &&
        day != null &&
        hour != null &&
        minute != null &&
        second != null) {
      final isUtc = dt.group(3) != null;
      if (isUtc) {
        return DateTime.utc(year, month, day, hour, minute, second).toLocal();
      }
      return DateTime(year, month, day, hour, minute, second);
    }
  }

  // YYYYMMDD (all-day)
  final d = RegExp(r'^(\d{8})$').firstMatch(v);
  if (d != null) {
    final date = d.group(1)!;
    final year = int.tryParse(date.substring(0, 4));
    final month = int.tryParse(date.substring(4, 6));
    final day = int.tryParse(date.substring(6, 8));
    if (year != null && month != null && day != null) {
      return DateTime(year, month, day, 9, 0);
    }
  }
  return null;
}

int? _parseIsoDurationMinutes(String text) {
  // PT1H30M / PT45M / PT2H
  final m = RegExp(r'P(?:\d+D)?T(?:(\d+)H)?(?:(\d+)M)?', caseSensitive: false).firstMatch(text);
  if (m == null) return null;
  final hours = int.tryParse(m.group(1) ?? '') ?? 0;
  final minutes = int.tryParse(m.group(2) ?? '') ?? 0;
  final total = hours * 60 + minutes;
  return total > 0 ? total : null;
}

DateTime? _parseFlexibleDateTime(String text, {required DateTime baseDay, _MutableInt? minutesOut}) {
  final s = text.trim();
  if (s.isEmpty) return null;

  // Handle time range format first: "2026-03-18 09:30-11:00"
  // This prevents the range from being misinterpreted as timezone offset
  final rangeMatch = RegExp(
    r'(\d{4})[\/\-.](\d{1,2})[\/\-.](\d{1,2}).{0,10}(\d{1,2}):(\d{2})\s*[-~]\s*(\d{1,2}):(\d{2})',
  ).firstMatch(s);
  if (rangeMatch != null) {
    final y = int.tryParse(rangeMatch.group(1) ?? '');
    final mo = int.tryParse(rangeMatch.group(2) ?? '');
    final d = int.tryParse(rangeMatch.group(3) ?? '');
    final sh = int.tryParse(rangeMatch.group(4) ?? '');
    final sm = int.tryParse(rangeMatch.group(5) ?? '');
    final eh = int.tryParse(rangeMatch.group(6) ?? '');
    final em = int.tryParse(rangeMatch.group(7) ?? '');
    if (y != null && mo != null && d != null && sh != null && sm != null && eh != null && em != null) {
      final start = DateTime(y, mo, d, sh, sm);
      final end = DateTime(y, mo, d, eh, em);
      final diff = end.difference(start).inMinutes;
      if (diff > 0 && minutesOut != null) {
        minutesOut.value = diff.clamp(1, 24 * 60);
      }
      return start;
    }
  }

  // ISO-like "2026-03-16 15:00", "2026/03/16 15:00", "2026-03-16T15:00:00"
  final normalizedIso = s.replaceAll('/', '-');
  final iso = DateTime.tryParse(normalizedIso);
  if (iso != null) return iso.toLocal();

  // US numeric "3/16/2026 3:15 PM"
  final usNumeric = RegExp(
    r'(\d{1,2})\/(\d{1,2})\/(\d{4}).*?(\d{1,2})(?::(\d{2}))?\s*(AM|PM)',
    caseSensitive: false,
  ).firstMatch(s);
  if (usNumeric != null) {
    final month = int.tryParse(usNumeric.group(1) ?? '');
    final day = int.tryParse(usNumeric.group(2) ?? '');
    final year = int.tryParse(usNumeric.group(3) ?? '');
    var hour = int.tryParse(usNumeric.group(4) ?? '');
    final minute = int.tryParse(usNumeric.group(5) ?? '') ?? 0;
    final ap = (usNumeric.group(6) ?? '').toUpperCase();
    if (month != null && day != null && year != null && hour != null) {
      if (ap == 'PM' && hour < 12) hour += 12;
      if (ap == 'AM' && hour == 12) hour = 0;
      return DateTime(year, month, day, hour, minute);
    }
  }

  // Outlook style "Monday, March 16, 2026 3:00 PM"
  final monthNameMatch = RegExp(
    r'(?:(?:Mon|Tue|Wed|Thu|Fri|Sat|Sun)\w*,\s*)?([A-Za-z]+)\s+(\d{1,2}),\s*(\d{4}).*?(\d{1,2})(?::(\d{2}))?\s*(AM|PM)',
    caseSensitive: false,
  ).firstMatch(s);
  if (monthNameMatch != null) {
    final month = _monthFromEnglishName(monthNameMatch.group(1) ?? '');
    final day = int.tryParse(monthNameMatch.group(2) ?? '');
    final year = int.tryParse(monthNameMatch.group(3) ?? '');
    var hour = int.tryParse(monthNameMatch.group(4) ?? '');
    final minute = int.tryParse(monthNameMatch.group(5) ?? '') ?? 0;
    final ap = (monthNameMatch.group(6) ?? '').toUpperCase();
    if (month != null && day != null && year != null && hour != null) {
      if (ap == 'PM' && hour < 12) hour += 12;
      if (ap == 'AM' && hour == 12) hour = 0;
      return DateTime(year, month, day, hour, minute);
    }
  }

  // Time-only forms in structured lines.
  final ampmOnly = RegExp(
    r'\b(\d{1,2})(?::(\d{2}))?\s*(AM|PM)\b',
    caseSensitive: false,
  ).firstMatch(s);
  if (ampmOnly != null) {
    var hour = int.tryParse(ampmOnly.group(1) ?? '');
    final minute = int.tryParse(ampmOnly.group(2) ?? '') ?? 0;
    final ap = (ampmOnly.group(3) ?? '').toUpperCase();
    if (hour != null) {
      if (ap == 'PM' && hour < 12) hour += 12;
      if (ap == 'AM' && hour == 12) hour = 0;
      if (_validHm(hour, minute)) {
        return DateTime(baseDay.year, baseDay.month, baseDay.day, hour, minute);
      }
    }
  }

  final hmOnly = RegExp(r'\b(\d{1,2}):(\d{2})\b').firstMatch(s);
  if (hmOnly != null) {
    final hour = int.tryParse(hmOnly.group(1) ?? '');
    final minute = int.tryParse(hmOnly.group(2) ?? '');
    if (hour != null && minute != null && _validHm(hour, minute)) {
      return DateTime(baseDay.year, baseDay.month, baseDay.day, hour, minute);
    }
  }
  return null;
}

int? _monthFromEnglishName(String name) {
  final m = name.trim().toLowerCase();
  const map = {
    'jan': 1,
    'january': 1,
    'feb': 2,
    'february': 2,
    'mar': 3,
    'march': 3,
    'apr': 4,
    'april': 4,
    'may': 5,
    'jun': 6,
    'june': 6,
    'jul': 7,
    'july': 7,
    'aug': 8,
    'august': 8,
    'sep': 9,
    'sept': 9,
    'september': 9,
    'oct': 10,
    'october': 10,
    'nov': 11,
    'november': 11,
    'dec': 12,
    'december': 12,
  };
  return map[m];
}

bool _looksLikeFieldLine(String line) {
  final re = RegExp(
    r'^(uid|id|event\s*id|meeting\s*id|主题|标题|title|summary|subject|时间|time|when|start|end|开始|结束|时长|持续|duration|dtstart|dtend|summary)\s*[:=：]',
    caseSensitive: false,
  );
  return re.hasMatch(line.trim());
}

DateTime _pickBaseDay(String text, DateTime now) {
  final d0 = DateTime(now.year, now.month, now.day);
  final lower = text.toLowerCase();

  if (text.contains('后天')) return d0.add(const Duration(days: 2));
  if (text.contains('明天') || lower.contains('tomorrow')) return d0.add(const Duration(days: 1));
  if (text.contains('今天') || lower.contains('today')) return d0;
  return d0;
}

bool _validHm(int hour, int minute) {
  return hour >= 0 && hour <= 23 && minute >= 0 && minute <= 59;
}

int _applyMeridiem(String prefix, int hour) {
  if (hour < 0 || hour > 23) return hour;

  final isPm = prefix.contains('下午') || prefix.contains('晚上') || prefix.contains('傍晚');
  if (isPm && hour < 12) return hour + 12;
  if (prefix.contains('中午') && hour < 11) return hour + 12;
  return hour;
}

String _fnv1a32(String input) {
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
