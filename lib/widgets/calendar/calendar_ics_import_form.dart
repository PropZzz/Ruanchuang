import 'package:flutter/material.dart';
import '../../models/models.dart';
import '../../services/ics/ics_bridge.dart';
import '../../services/ics/ics_codec.dart';
import '../../utils/app_strings.dart';
import '../../utils/mobile_feedback.dart';
import '../stitch_form_sheet.dart';

class CalendarIcsImportForm extends StatefulWidget {
  const CalendarIcsImportForm({
    super.key,
    required this.day,
    this.bottomSheet = false,
  });

  final DateTime day;
  final bool bottomSheet;

  @override
  State<CalendarIcsImportForm> createState() => _CalendarIcsImportFormState();
}

class _CalendarIcsImportFormState extends State<CalendarIcsImportForm> {
  final TextEditingController _controller = TextEditingController();
  List<ScheduleEntry>? _preview;
  String? _validationMessage;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _previewOrImport() {
    final preview = _preview;
    if (preview != null) {
      Navigator.of(context).pop(preview);
      return;
    }

    try {
      final events = IcsCodec.decodeCalendar(_controller.text);
      if (events.isEmpty) {
        setState(() {
          _validationMessage = AppStrings.of(context, 'calendar_ics_invalid');
        });
        return;
      }
      final entries = IcsBridge.eventsToSchedule(
        day: widget.day,
        events: events,
      );
      if (entries.isEmpty) {
        setState(() {
          _validationMessage = AppStrings.of(context, 'calendar_ics_wrong_day');
        });
        return;
      }
      setState(() {
        _preview = entries;
        _validationMessage = null;
      });
    } catch (_) {
      setState(() {
        _validationMessage = AppStrings.of(context, 'calendar_ics_invalid');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = AppStrings.of(context, 'calendar_ics_import_title');
    final confirmLabel = _preview == null
        ? AppStrings.of(context, 'calendar_ics_preview')
        : AppStrings.of(
            context,
            'calendar_ics_import_count',
            params: {'count': '${_preview!.length}'},
          );
    final help = AppStrings.of(context, 'calendar_ics_import_help');
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(help, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 10),
        TextField(
          controller: _controller,
          minLines: 5,
          maxLines: 10,
          onChanged: (_) {
            if (_preview != null || _validationMessage != null) {
              setState(() {
                _preview = null;
                _validationMessage = null;
              });
            }
          },
          decoration: InputDecoration(
            labelText: AppStrings.of(context, 'calendar_ics_input_label'),
            hintText: AppStrings.of(context, 'calendar_ics_import_hint'),
            alignLabelWithHint: true,
          ),
        ),
        if (_validationMessage != null) ...[
          const SizedBox(height: 8),
          Semantics(
            liveRegion: true,
            child: Text(
              _validationMessage!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
        if (_preview != null) ...[
          const SizedBox(height: 14),
          Text(
            AppStrings.of(
              context,
              'calendar_ics_preview_title',
              params: {
                'date': MaterialLocalizations.of(
                  context,
                ).formatMediumDate(widget.day),
              },
            ),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 6),
          for (final entry in _preview!)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_outlined),
              title: Text(
                entry.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                '${entry.time.format(context)} · ${(entry.height / 80 * 60).round()} 分钟 · ${entry.tag}',
              ),
            ),
        ],
      ],
    );

    if (widget.bottomSheet) {
      return StitchFormSheet(
        title: title,
        content: content,
        onCancel: () => Navigator.of(context).pop(),
        onConfirm: _previewOrImport,
        confirmLabel: confirmLabel,
      );
    }
    return AlertDialog(
      title: Text(title),
      content: ConstrainedBox(
        constraints: MobileFeedback.dialogConstraints(context, maxWidth: 520),
        child: SingleChildScrollView(child: content),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(AppStrings.of(context, 'btn_cancel')),
        ),
        FilledButton(onPressed: _previewOrImport, child: Text(confirmLabel)),
      ],
    );
  }
}
