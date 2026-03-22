import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/app_services.dart';
import '../services/mcp/mcp_ingest.dart';
import '../utils/app_strings.dart';

double _heightFromMinutes(int minutes) => (minutes / 60.0) * 80.0;

class _ParsedExternalEvent {
  final String uid;
  final String title;
  final DateTime start;
  final int minutes;
  final String source;

  const _ParsedExternalEvent({
    required this.uid,
    required this.title,
    required this.start,
    required this.minutes,
    required this.source,
  });
}

class IntegrationsPage extends StatefulWidget {
  const IntegrationsPage({super.key});

  @override
  State<IntegrationsPage> createState() => _IntegrationsPageState();
}

class _IntegrationsPageState extends State<IntegrationsPage> {
  final _rawCtrl = TextEditingController();
  _ParsedExternalEvent? _parsed;
  String? _error;

  @override
  void dispose() {
    _rawCtrl.dispose();
    super.dispose();
  }

  _ParsedExternalEvent? _parse(String raw) {
    final ev = McpIngest.parse(raw, source: _detectSource(raw));
    if (ev == null) return null;
    return _ParsedExternalEvent(
      uid: ev.uid,
      title: ev.title,
      start: ev.start,
      minutes: ev.minutes,
      source: ev.source,
    );
  }

  void _doParse() {
    final p = _parse(_rawCtrl.text);
    setState(() {
      _parsed = p;
      _error = (p == null) ? AppStrings.of(context, 'mcp_parse_fail') : null;
    });
  }

  Future<void> _import() async {
    final p = _parsed;
    if (p == null) return;

    final ds = AppServices.dataService;
    final all = await ds.getScheduleEntries();
    final normalizedId = 'mcp_${_normalizeUidForEntryId(p.uid)}';
    final legacyId = 'mcp_${p.uid}';
    final existedEntry = all.cast<ScheduleEntry?>().firstWhere(
      (e) => e?.id == normalizedId || e?.id == legacyId,
      orElse: () => null,
    );
    final id = existedEntry?.id ?? normalizedId;

    final day = DateTime(p.start.year, p.start.month, p.start.day);
    final tod = TimeOfDay(hour: p.start.hour, minute: p.start.minute);
    final entry = existedEntry == null
        ? ScheduleEntry(
            id: id,
            day: day,
            title: p.title,
            tag: p.source,
            height: _heightFromMinutes(p.minutes),
            color: Colors.blue,
            time: tod,
            reminderMinutesBefore: 10,
          )
        : existedEntry.copyWith(
            title: p.title,
            day: day,
            time: tod,
            height: _heightFromMinutes(p.minutes),
            tag: existedEntry.tag.isEmpty ? p.source : existedEntry.tag,
          );

    await ds.addScheduleEntry(entry);

    // Only reschedule this one entry. Full-day reschedule is owned by the
    // calendar screen and would wipe unrelated timers.
    await AppServices.reminderService.scheduleEntry(day: day, entry: entry);

    if (!mounted) return;
    final timeChanged = existedEntry != null &&
        (existedEntry.time.hour != tod.hour || existedEntry.time.minute != tod.minute);
    final msg = existedEntry == null
        ? AppStrings.of(context, 'mcp_imported')
        : timeChanged
            ? AppStrings.of(context, 'mcp_change_synced')
            : AppStrings.of(context, 'mcp_updated');
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _detectSource(String raw) {
    final s = raw.toLowerCase();
    if (s.contains('begin:vcalendar') || s.contains('dtstart') || s.contains('dtend')) {
      return 'ICS';
    }
    if (s.contains('organizer:') ||
        s.contains('required attendees') ||
        s.contains('optional attendees')) {
      return 'Outlook';
    }
    if (s.contains('from:') && s.contains('subject:')) {
      return 'Email';
    }
    return 'MCP';
  }

  String _normalizeUidForEntryId(String uid) {
    final normalized = uid.trim().toLowerCase();
    if (normalized.isEmpty) return 'unknown';
    return normalized.replaceAll(RegExp(r'[^a-z0-9_\-]'), '_');
  }

  @override
  Widget build(BuildContext context) {
    final p = _parsed;
    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.of(context, 'mcp_title')),
        actions: [
          IconButton(onPressed: _doParse, icon: const Icon(Icons.auto_fix_high)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(AppStrings.of(context, 'mcp_hint')),
          const SizedBox(height: 8),
          TextField(
            controller: _rawCtrl,
            minLines: 6,
            maxLines: 12,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              hintText: AppStrings.of(context, 'mcp_placeholder'),
              errorText: _error,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _doParse,
                  icon: const Icon(Icons.search),
                  label: Text(AppStrings.of(context, 'mcp_btn_parse')),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: p == null ? null : _import,
                  icon: const Icon(Icons.download_done),
                  label: Text(AppStrings.of(context, 'mcp_btn_import')),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (p != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppStrings.of(context, 'mcp_preview'),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text('UID: ${p.uid}'),
                    Text('${AppStrings.of(context, 'label_title')}: ${p.title}'),
                    Text('${AppStrings.of(context, 'label_start_time')}: ${p.start}'),
                    Text('${AppStrings.of(context, 'label_duration')}: ${p.minutes} min'),
                    Text('${AppStrings.of(context, 'label_tag')}: ${p.source}'),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
