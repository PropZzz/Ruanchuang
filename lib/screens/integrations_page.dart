import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/app_services.dart';
import '../services/mcp/mcp_ingest.dart';
import '../utils/app_strings.dart';
import '../utils/schedule_occurrence.dart';
import '../theme/app_theme.dart';
import '../widgets/press_scale.dart';

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
  String? _importError;
  bool _importing = false;

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
      _importError = null;
    });
  }

  Future<void> _import() async {
    final p = _parsed;
    if (p == null || _importing) return;

    setState(() {
      _importing = true;
      _importError = null;
    });

    try {
      final ds = AppServices.dataService;
      final all = await ds.getScheduleEntries();
      final normalizedId = 'mcp_${_normalizeUidForEntryId(p.uid)}';
      final legacyId = 'mcp_${p.uid}';
      final existedEntry = all.cast<ScheduleEntry?>().firstWhere(
        (e) => e?.id == normalizedId || e?.id == legacyId,
        orElse: () => null,
      );
      final id = existedEntry?.id ?? normalizedId;

      final day = dateOnly(p.start);
      final tod = TimeOfDay(hour: p.start.hour, minute: p.start.minute);
      final entry = existedEntry == null
          ? ScheduleEntry(
              id: id,
              day: day,
              title: p.title,
              tag: p.source,
              height: _heightFromMinutes(p.minutes),
              color: Theme.of(context).colorScheme.primary,
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
      await AppServices.reminderService.scheduleEntry(day: day, entry: entry);

      if (!mounted) return;
      final timeChanged =
          existedEntry != null &&
          (existedEntry.time.hour != tod.hour ||
              existedEntry.time.minute != tod.minute);
      final msg = existedEntry == null
          ? _copy('已导入 1 条 ${p.source} 日程。', 'Imported 1 ${p.source} event.')
          : timeChanged
          ? _copy(
              '变更已同步 1 条 ${p.source} 日程。',
              'Synced changes to 1 ${p.source} event.',
            )
          : _copy('已更新 1 条 ${p.source} 日程。', 'Updated 1 ${p.source} event.');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (error, stackTrace) {
      AppServices.logStore.error(
        'mcp',
        'import failed',
        error: error,
        stackTrace: stackTrace,
        data: {'uid': p.uid},
      );
      if (!mounted) return;
      setState(() {
        _importError = _copy(
          '导入失败，请检查日程服务后重试。',
          'Import failed. Check the schedule service and retry.',
        );
      });
    } finally {
      if (mounted) {
        setState(() => _importing = false);
      }
    }
  }

  String _detectSource(String raw) {
    final s = raw.toLowerCase();
    if (s.contains('begin:vcalendar') ||
        s.contains('dtstart') ||
        s.contains('dtend')) {
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

  String _copy(String chinese, String english) =>
      Localizations.localeOf(context).languageCode == 'en' ? english : chinese;

  String _normalizeUidForEntryId(String uid) {
    final normalized = uid.trim().toLowerCase();
    if (normalized.isEmpty) return 'unknown';
    return normalized.replaceAll(RegExp(r'[^a-z0-9_\-]'), '_');
  }

  @override
  Widget build(BuildContext context) {
    final p = _parsed;
    return Scaffold(
      backgroundColor: AppWindowTones.canvas(context, AppWindowTone.neutral),
      appBar: AppBar(
        title: Text(AppStrings.of(context, 'mcp_title')),
        actions: [
          IconButton(
            tooltip: '解析外部文本',
            onPressed: _doParse,
            icon: const Icon(Icons.auto_fix_high),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 960;
          final inputPanel = _buildInputPanel(wide: wide);
          final previewPanel = _buildPreviewPanel(p);
          return SingleChildScrollView(
            padding: EdgeInsets.all(wide ? 28 : 16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1320),
                child: wide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 11, child: inputPanel),
                          const SizedBox(width: 20),
                          Expanded(flex: 9, child: previewPanel),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          inputPanel,
                          const SizedBox(height: 16),
                          previewPanel,
                        ],
                      ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildInputPanel({required bool wide}) {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(wide ? 22 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.text_snippet_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _copy('外部文本', 'External text'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Text('MCP', style: Theme.of(context).textTheme.labelMedium),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              _copy(
                '粘贴外部消息并生成日程条目。',
                'Paste external messages to create a schedule entry.',
              ),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            Text(
              _copy('支持格式', 'Supported formats'),
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: const [
                _SourceBadge(icon: Icons.calendar_month_outlined, label: 'ICS'),
                _SourceBadge(icon: Icons.event_outlined, label: 'Outlook'),
                _SourceBadge(icon: Icons.mail_outline, label: 'Email'),
                _SourceBadge(icon: Icons.hub_outlined, label: 'MCP'),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('integrations-raw-input'),
              controller: _rawCtrl,
              minLines: wide ? 11 : 7,
              maxLines: 14,
              keyboardType: TextInputType.multiline,
              textAlignVertical: TextAlignVertical.top,
              decoration: InputDecoration(
                labelText: _copy('粘贴会议或日程文本', 'Paste meeting or schedule text'),
                hintText: AppStrings.of(context, 'mcp_placeholder'),
                errorText: _error,
                alignLabelWithHint: true,
                helperText: _copy(
                  '解析仅识别时间、标题、时长与来源，不会自动写入日程。',
                  'Parsing identifies time, title, duration and source; it never imports automatically.',
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: PressScale(
                    child: FilledButton.icon(
                      key: const Key('integrations-parse'),
                      onPressed: _doParse,
                      icon: const Icon(Icons.auto_fix_high),
                      label: Text(AppStrings.of(context, 'mcp_btn_parse')),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: PressScale(
                    child: FilledButton.tonalIcon(
                      key: const Key('integrations-import'),
                      onPressed: _parsed == null || _importing ? null : _import,
                      icon: _importing
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.event_available_outlined),
                      label: Text(AppStrings.of(context, 'mcp_btn_import')),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewPanel(_ParsedExternalEvent? event) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      key: const Key('integrations-preview'),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.fact_check_outlined, color: colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _copy('解析预览', 'Parsed event preview'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                _PreviewStatus(hasEvent: event != null),
              ],
            ),
            const SizedBox(height: 18),
            if (event == null)
              SizedBox(
                height: 224,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.event_note_outlined,
                        size: 36,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        Localizations.localeOf(context).languageCode == 'en'
                            ? 'Waiting for input'
                            : '等待解析',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        Localizations.localeOf(context).languageCode == 'en'
                            ? 'Parsed fields will appear here.'
                            : '解析成功后，日程字段会显示在这里。',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              )
            else ...[
              _PreviewField(
                icon: Icons.title,
                label: AppStrings.of(context, 'label_title'),
                value: event.title,
                prominent: true,
              ),
              const Divider(height: 22),
              _PreviewField(
                icon: Icons.schedule_outlined,
                label: '开始时间',
                value:
                    '${_dateLabel(event.start)} · ${_timeLabel(event.start)}',
              ),
              const SizedBox(height: 14),
              _PreviewField(
                icon: Icons.timelapse_outlined,
                label: AppStrings.of(context, 'label_duration'),
                value: '${event.minutes} min',
              ),
              const SizedBox(height: 14),
              _PreviewField(
                icon: Icons.sell_outlined,
                label: AppStrings.of(context, 'label_tag'),
                value: event.source,
              ),
              const SizedBox(height: 14),
              _PreviewField(
                icon: Icons.fingerprint,
                label: 'UID',
                value: event.uid,
              ),
            ],
            if (_importError != null) ...[
              const SizedBox(height: 12),
              Text(_importError!, style: TextStyle(color: colorScheme.error)),
            ],
          ],
        ),
      ),
    );
  }

  String _dateLabel(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  String _timeLabel(DateTime date) =>
      '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}

class _SourceBadge extends StatelessWidget {
  const _SourceBadge({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: '支持来源 $label',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: scheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Text(label, style: Theme.of(context).textTheme.labelMedium),
          ],
        ),
      ),
    );
  }
}

class _PreviewStatus extends StatelessWidget {
  const _PreviewStatus({required this.hasEvent});

  final bool hasEvent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = hasEvent ? scheme.tertiary : scheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            hasEvent ? Icons.check_circle_outline : Icons.pending_outlined,
            size: 15,
            color: color,
          ),
          const SizedBox(width: 5),
          Text(
            hasEvent
                ? (Localizations.localeOf(context).languageCode == 'en'
                      ? 'Parsed'
                      : '已识别')
                : (Localizations.localeOf(context).languageCode == 'en'
                      ? 'Not parsed'
                      : '未解析'),
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewField extends StatelessWidget {
  const _PreviewField({
    required this.icon,
    required this.label,
    required this.value,
    this.prominent = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool prominent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: scheme.onSurfaceVariant),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: 3),
              SelectableText(
                value,
                style: prominent
                    ? Theme.of(context).textTheme.titleMedium
                    : Theme.of(context).textTheme.bodyLarge,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
