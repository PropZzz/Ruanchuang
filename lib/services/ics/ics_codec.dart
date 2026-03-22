import 'dart:convert';

class IcsEvent {
  final String uid;
  final DateTime start;
  final DateTime end;
  final String summary;
  final String description;

  const IcsEvent({
    required this.uid,
    required this.start,
    required this.end,
    required this.summary,
    required this.description,
  });
}

class IcsCodec {
  static String encodeCalendar({
    required List<IcsEvent> events,
    required DateTime createdAt,
    String prodId = '-//sxzppp//BattleMan//EN',
  }) {
    final lines = <String>[];

    lines.add('BEGIN:VCALENDAR');
    lines.add('VERSION:2.0');
    lines.add('CALSCALE:GREGORIAN');
    lines.add('PRODID:$prodId');

    for (final e in events) {
      lines.add('BEGIN:VEVENT');
      lines.add('UID:${_escapeText(e.uid)}');
      lines.add('DTSTAMP:${_formatUtc(createdAt)}');

      // Timezone strategy (P0): export as local "floating" times without Z.
      // Import treats floating times as local device time.
      lines.add('DTSTART:${_formatLocalFloating(e.start)}');
      lines.add('DTEND:${_formatLocalFloating(e.end)}');

      lines.add('SUMMARY:${_escapeText(e.summary)}');
      if (e.description.trim().isNotEmpty) {
        lines.add('DESCRIPTION:${_escapeText(e.description)}');
      }
      lines.add('END:VEVENT');
    }

    lines.add('END:VCALENDAR');

    return '${_foldLines(lines).join('\r\n')}\r\n';
  }

  /// Minimal ICS parser.
  ///
  /// Supported subset:
  /// - DTSTART / DTEND (local floating or UTC Z)
  /// - SUMMARY
  /// - DESCRIPTION
  /// - UID
  ///
  /// Ignored:
  /// - RRULE and other recurrence (P0). If present, only the base event is read.
  static List<IcsEvent> decodeCalendar(String ics) {
    final unfolded = _unfold(ics);
    final out = <IcsEvent>[];

    Map<String, String> cur = {};
    bool inEvent = false;

    for (final raw in unfolded) {
      final line = raw.trimRight();
      if (line == 'BEGIN:VEVENT') {
        inEvent = true;
        cur = {};
        continue;
      }
      if (line == 'END:VEVENT') {
        inEvent = false;
        final ev = _eventFromMap(cur);
        if (ev != null) out.add(ev);
        cur = {};
        continue;
      }
      if (!inEvent) continue;

      final idx = line.indexOf(':');
      if (idx <= 0) continue;

      final left = line.substring(0, idx);
      final value = line.substring(idx + 1);

      // Strip parameters, e.g. DTSTART;TZID=Asia/Shanghai
      final key = left.split(';').first.toUpperCase();
      cur[key] = value;
    }

    return out;
  }

  static IcsEvent? _eventFromMap(Map<String, String> m) {
    final startRaw = m['DTSTART'];
    final endRaw = m['DTEND'];
    final summaryRaw = m['SUMMARY'];
    final durationRaw = m['DURATION'];

    if (startRaw == null || summaryRaw == null) return null;

    final start = _parseDateTime(startRaw);
    if (start == null) return null;

    DateTime? end;
    if (endRaw != null) {
      end = _parseDateTime(endRaw);
    }
    if (end == null && durationRaw != null) {
      final dur = _parseDuration(durationRaw);
      if (dur != null) {
        end = start.add(dur);
      }
    }
    if (end == null) return null;

    final uid = _unescapeText(m['UID'] ?? _deriveUid(
      start: start,
      end: end,
      summary: summaryRaw,
      description: m['DESCRIPTION'] ?? '',
    ));
    final summary = _unescapeText(summaryRaw);
    final description = _unescapeText(m['DESCRIPTION'] ?? '');

    return IcsEvent(
      uid: uid,
      start: start,
      end: end,
      summary: summary,
      description: description,
    );
  }

  static String _deriveUid({
    required DateTime start,
    required DateTime end,
    required String summary,
    required String description,
  }) {
    final seed =
        '${start.toIso8601String()}|${end.toIso8601String()}|$summary|$description';
    return 'sxzppp-${_fnv1a32(seed)}';
  }

  static DateTime? _parseDateTime(String s) {
    // Supported:
    // - YYYYMMDDTHHMMSSZ
    // - YYYYMMDDTHHMMSS
    // - YYYYMMDDTHHMM
    // - YYYYMMDD
    final raw = s.trim();
    final isUtc = raw.endsWith('Z');
    final t = isUtc ? raw.substring(0, raw.length - 1) : raw;

    if (t.length == 8) {
      final y = int.tryParse(t.substring(0, 4));
      final mo = int.tryParse(t.substring(4, 6));
      final d = int.tryParse(t.substring(6, 8));
      if (y == null || mo == null || d == null) return null;
      final dt = DateTime(y, mo, d);
      return isUtc ? dt.toUtc().toLocal() : dt;
    }

    if (t.length != 15 || t[8] != 'T') {
      // Try HHMM without seconds.
      if (t.length == 13 && t[8] == 'T') {
        final y = int.tryParse(t.substring(0, 4));
        final mo = int.tryParse(t.substring(4, 6));
        final d = int.tryParse(t.substring(6, 8));
        final hh = int.tryParse(t.substring(9, 11));
        final mm = int.tryParse(t.substring(11, 13));
        if (y == null || mo == null || d == null || hh == null || mm == null) return null;
        final dt = DateTime(y, mo, d, hh, mm);
        return isUtc ? dt.toUtc().toLocal() : dt;
      }
      return null;
    }

    final y = int.tryParse(t.substring(0, 4));
    final mo = int.tryParse(t.substring(4, 6));
    final d = int.tryParse(t.substring(6, 8));
    final hh = int.tryParse(t.substring(9, 11));
    final mm = int.tryParse(t.substring(11, 13));
    final ss = int.tryParse(t.substring(13, 15));

    if (y == null || mo == null || d == null || hh == null || mm == null || ss == null) {
      return null;
    }

    final dt = DateTime(y, mo, d, hh, mm, ss);
    return isUtc ? dt.toUtc().toLocal() : dt;
  }

  static Duration? _parseDuration(String raw) {
    // Supported subset: PnD, PTnH, PTnM, PTnHnM.
    final s = raw.trim().toUpperCase();
    if (!s.startsWith('P')) return null;

    final dayRe = RegExp(r'P(\d+)D');
    final timeRe = RegExp(r'T(\d+H)?(\d+M)?');

    var days = 0;
    var hours = 0;
    var minutes = 0;

    final dm = dayRe.firstMatch(s);
    if (dm != null) {
      days = int.tryParse(dm.group(1) ?? '') ?? 0;
    }

    final tm = timeRe.firstMatch(s);
    if (tm != null) {
      final hRaw = tm.group(1);
      final mRaw = tm.group(2);
      if (hRaw != null) {
        hours = int.tryParse(hRaw.replaceAll('H', '')) ?? 0;
      }
      if (mRaw != null) {
        minutes = int.tryParse(mRaw.replaceAll('M', '')) ?? 0;
      }
    }

    final totalMinutes = days * 24 * 60 + hours * 60 + minutes;
    if (totalMinutes <= 0) return null;
    return Duration(minutes: totalMinutes);
  }

  static String _formatUtc(DateTime dt) {
    final u = dt.toUtc();
    return '${_yyyymmddThhmmss(u)}Z';
  }

  static String _formatLocalFloating(DateTime dt) {
    final l = dt.toLocal();
    return _yyyymmddThhmmss(l);
  }

  static String _yyyymmddThhmmss(DateTime dt) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${dt.year.toString().padLeft(4, '0')}${two(dt.month)}${two(dt.day)}T${two(dt.hour)}${two(dt.minute)}${two(dt.second)}';
  }

  static String _escapeText(String s) {
    return s
        .replaceAll('\\', '\\\\')
        .replaceAll('\n', '\\n')
        .replaceAll(',', '\\,')
        .replaceAll(';', '\\;');
  }

  static String _unescapeText(String s) {
    // Order matters.
    return s
        .replaceAll('\\n', '\n')
        .replaceAll('\\,', ',')
        .replaceAll('\\;', ';')
        .replaceAll('\\\\', '\\');
  }

  static List<String> _foldLines(List<String> lines) {
    // RFC5545: lines longer than 75 octets should be folded with CRLF + space.
    final out = <String>[];
    for (final l in lines) {
      final chunks = _foldUtf8Chunks(l);
      if (chunks.length == 1) {
        out.add(l);
        continue;
      }
      out.add(chunks.first);
      for (final chunk in chunks.skip(1)) {
        out.add(' $chunk');
      }
    }
    return out;
  }

  static List<String> _foldUtf8Chunks(String line) {
    const firstLimit = 75;
    const continuationLimit = 74;

    final chunks = <String>[];
    var buffer = StringBuffer();
    var bytes = 0;
    var limit = firstLimit;

    for (final rune in line.runes) {
      final char = String.fromCharCode(rune);
      final charBytes = utf8.encode(char).length;
      if (buffer.isNotEmpty && bytes + charBytes > limit) {
        chunks.add(buffer.toString());
        buffer = StringBuffer();
        bytes = 0;
        limit = continuationLimit;
      }
      buffer.writeCharCode(rune);
      bytes += charBytes;
    }

    if (buffer.isNotEmpty) {
      chunks.add(buffer.toString());
    }

    return chunks.isEmpty ? [line] : chunks;
  }

  static List<String> _unfold(String ics) {
    final rawLines = ics.replaceAll('\r\n', '\n').split('\n');
    final out = <String>[];

    for (final line in rawLines) {
      if (line.isEmpty) continue;
      if (line.startsWith(' ') || line.startsWith('\t')) {
        if (out.isNotEmpty) {
          out[out.length - 1] = out.last + line.substring(1);
        }
      } else {
        out.add(line);
      }
    }

    return out;
  }

  static String _fnv1a32(String input) {
    var hash = 0x811c9dc5;
    for (final c in input.codeUnits) {
      hash ^= c;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }
}
