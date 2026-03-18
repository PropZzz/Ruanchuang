import 'dart:math';

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

    if (startRaw == null || endRaw == null || summaryRaw == null) return null;

    final start = _parseDateTime(startRaw);
    final end = _parseDateTime(endRaw);
    if (start == null || end == null) return null;

    final uid = _unescapeText(m['UID'] ?? _newUid());
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

  static String _newUid() {
    final r = Random();
    final ts = DateTime.now().microsecondsSinceEpoch;
    return 'sxzppp-$ts-${r.nextInt(1 << 32)}';
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
    // P0: fold at 75 chars (ASCII-only in our content).
    final out = <String>[];
    for (final l in lines) {
      if (l.length <= 75) {
        out.add(l);
        continue;
      }
      var i = 0;
      out.add(l.substring(0, 75));
      i = 75;
      while (i < l.length) {
        final end = (i + 74 < l.length) ? i + 74 : l.length;
        out.add(' ');
        i = end;
      }
    }
    return out;
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
}
