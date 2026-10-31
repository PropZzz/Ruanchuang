import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/scheduling/urgent_deadline.dart';
import '../theme/app_theme.dart';
import '../utils/app_strings.dart';
import '../utils/mobile_feedback.dart';
import '../utils/schedule_occurrence.dart';
import 'stitch_form_sheet.dart';

String _cognitiveLoadLabel(BuildContext context, CognitiveLoad load) {
  switch (load) {
    case CognitiveLoad.low:
      return AppStrings.of(context, 'cognitive_load_low');
    case CognitiveLoad.medium:
      return AppStrings.of(context, 'cognitive_load_medium');
    case CognitiveLoad.high:
      return AppStrings.of(context, 'cognitive_load_high');
  }
}

/// Mirrors the scheduler's load -> block color mapping so the preview shows
/// the color the placed urgent block will actually use.
Color _urgentBlockColor(CognitiveLoad load) => switch (load) {
  CognitiveLoad.high => Colors.teal,
  CognitiveLoad.medium => Colors.blue,
  CognitiveLoad.low => Colors.orange,
};

const _durationOptions = [10, 15, 25, 30, 45, 60];

/// Collects an urgent task draft (title, duration, priority, load, deadline)
/// and returns it as a [PlanTask], or null when cancelled.
///
/// Pure input collection: no network, database, or global service access.
/// Persisting the task and proposing rescue options is the caller's job.
Future<PlanTask?> showUrgentTaskDialog(
  BuildContext context, {
  required DateTime scheduleDay,
}) {
  if (MediaQuery.sizeOf(context).width < AppTheme.compactShellBreakpoint) {
    return showModalBottomSheet<PlanTask>(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      builder: (ctx) =>
          _UrgentTaskDialog(scheduleDay: scheduleDay, bottomSheet: true),
    );
  }
  return showDialog<PlanTask>(
    context: context,
    builder: (ctx) => _UrgentTaskDialog(scheduleDay: scheduleDay),
  );
}

class _UrgentTaskDialog extends StatefulWidget {
  const _UrgentTaskDialog({
    required this.scheduleDay,
    this.bottomSheet = false,
  });

  final DateTime scheduleDay;
  final bool bottomSheet;

  @override
  State<_UrgentTaskDialog> createState() => _UrgentTaskDialogState();
}

class _UrgentTaskDialogState extends State<_UrgentTaskDialog> {
  late final TextEditingController _titleCtrl;
  late DateTime _deadline;
  String? _deadlineValidationMessage;
  int _minutes = 25;
  int _priority = 5;
  CognitiveLoad _load = CognitiveLoad.medium;
  bool _initialized = false;

  DateTime get _scheduleDay => dateOnly(widget.scheduleDay);

  bool get _hasTitle => _titleCtrl.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController();
    _deadline = defaultUrgentDeadline(
      now: DateTime.now(),
      scheduleDay: _scheduleDay,
    );
    _titleCtrl.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _titleCtrl.text = AppStrings.of(
      context,
      'calendar_insert_urgent_default_title',
    );
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDeadlineDate() async {
    final now = DateTime.now();
    final today = dateOnly(now);
    final firstDate = _scheduleDay.isAfter(today) ? _scheduleDay : today;
    final selected = await showDatePicker(
      context: context,
      initialDate: _deadline.isBefore(firstDate) ? firstDate : _deadline,
      firstDate: firstDate,
      lastDate: urgentDeadlinePickerLastDate(firstDate: firstDate),
    );
    if (selected != null) {
      setState(() {
        _deadline = DateTime(
          selected.year,
          selected.month,
          selected.day,
          _deadline.hour,
          _deadline.minute,
        );
        _deadlineValidationMessage = null;
      });
    }
  }

  Future<void> _pickDeadlineTime() async {
    final selected = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_deadline),
    );
    if (selected != null) {
      setState(() {
        _deadline = DateTime(
          _deadline.year,
          _deadline.month,
          _deadline.day,
          selected.hour,
          selected.minute,
        );
        _deadlineValidationMessage = null;
      });
    }
  }

  void _confirm() {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) return;

    final confirmationNow = DateTime.now();
    if (!isUrgentDeadlineValid(
      now: confirmationNow,
      scheduleDay: _scheduleDay,
      deadline: _deadline,
    )) {
      setState(() {
        _deadlineValidationMessage = AppStrings.of(
          context,
          'calendar_urgent_deadline_invalid',
        );
      });
      return;
    }

    Navigator.of(context).pop(
      PlanTask(
        id: 'urgent_${confirmationNow.microsecondsSinceEpoch}',
        title: title,
        durationMinutes: _minutes,
        priority: _priority,
        load: _load,
        tag: 'Urgent',
        due: _deadline,
      ),
    );
  }

  Widget _sectionLabel(BuildContext context, String text) {
    final scheme = Theme.of(context).colorScheme;
    return Text(
      text,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: scheme.onSurfaceVariant,
      ),
    );
  }

  /// Miniature of the calendar block (same radius, alpha and shadow as
  /// `_buildScheduleBlock` in the calendar page) colored the way the
  /// scheduler will color the placed urgent entry.
  Widget _buildPreview(BuildContext context) {
    final title = _titleCtrl.text.trim();
    return AnimatedContainer(
      key: const ValueKey('calendar-urgent-preview'),
      duration: const Duration(milliseconds: 180),
      constraints: const BoxConstraints(minHeight: 64),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _urgentBlockColor(_load).withAlpha((0.9 * 255).round()),
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.warning_amber_outlined,
                size: 18,
                color: Colors.white70,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title.isEmpty ? AppStrings.of(context, 'label_title') : title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              _previewChip(
                Icons.timelapse,
                '${_minutes.toString()} ${AppStrings.of(context, 'label_minutes')}',
              ),
              _previewChip(
                Icons.event_outlined,
                MaterialLocalizations.of(context).formatShortDate(_deadline),
              ),
              _previewChip(
                Icons.schedule_outlined,
                MaterialLocalizations.of(
                  context,
                ).formatTimeOfDay(TimeOfDay.fromDateTime(_deadline)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _previewChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white24,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.white70),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildDurationPicker() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final minutes in _durationOptions)
          ChoiceChip(
            label: Text('$minutes'),
            selected: _minutes == minutes,
            onSelected: (_) => setState(() => _minutes = minutes),
          ),
      ],
    );
  }

  Widget _buildPriorityPicker() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final priority in const [1, 2, 3, 4, 5])
          ChoiceChip(
            label: Text('$priority'),
            selected: _priority == priority,
            onSelected: (_) => setState(() => _priority = priority),
          ),
      ],
    );
  }

  Widget _buildLoadPicker(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final load in CognitiveLoad.values)
          ChoiceChip(
            label: Text(_cognitiveLoadLabel(context, load)),
            selected: _load == load,
            onSelected: (_) => setState(() => _load = load),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final title = AppStrings.of(context, 'calendar_insert_urgent_title');
    final form = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildPreview(context),
        const SizedBox(height: 16),
        TextField(
          controller: _titleCtrl,
          decoration: InputDecoration(
            labelText: AppStrings.of(context, 'label_title'),
          ),
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _confirm(),
        ),
        const SizedBox(height: 16),
        _sectionLabel(context, AppStrings.of(context, 'label_minutes')),
        const SizedBox(height: 8),
        _buildDurationPicker(),
        const SizedBox(height: 16),
        _sectionLabel(context, AppStrings.of(context, 'label_priority')),
        const SizedBox(height: 8),
        _buildPriorityPicker(),
        const SizedBox(height: 16),
        _sectionLabel(context, AppStrings.of(context, 'label_cognitive_load')),
        const SizedBox(height: 8),
        _buildLoadPicker(context),
        const SizedBox(height: 8),
        Column(
          key: const ValueKey('calendar-urgent-deadline'),
          children: [
            ListTile(
              key: const ValueKey('calendar-urgent-deadline-date'),
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: const Icon(Icons.event_outlined),
              title: Text(
                AppStrings.of(context, 'calendar_urgent_deadline_date'),
              ),
              trailing: Text(
                MaterialLocalizations.of(context).formatMediumDate(_deadline),
              ),
              onTap: _pickDeadlineDate,
            ),
            ListTile(
              key: const ValueKey('calendar-urgent-deadline-time'),
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: const Icon(Icons.schedule_outlined),
              title: Text(
                AppStrings.of(context, 'calendar_urgent_deadline_time'),
              ),
              trailing: Text(
                MaterialLocalizations.of(
                  context,
                ).formatTimeOfDay(TimeOfDay.fromDateTime(_deadline)),
              ),
              onTap: _pickDeadlineTime,
            ),
          ],
        ),
        if (_deadlineValidationMessage != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                Icon(Icons.error_outline, size: 16, color: scheme.error),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _deadlineValidationMessage!,
                    style: TextStyle(color: scheme.error, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
    if (widget.bottomSheet) {
      return StitchFormSheet(
        title: title,
        content: form,
        onCancel: () => Navigator.of(context).pop(),
        onConfirm: _confirm,
        confirmLabel: AppStrings.of(context, 'calendar_insert_urgent_confirm'),
        confirmEnabled: _hasTitle,
      );
    }
    return AlertDialog(
      title: Text(title),
      content: ConstrainedBox(
        constraints: MobileFeedback.dialogConstraints(context, maxWidth: 420),
        child: SingleChildScrollView(child: form),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(AppStrings.of(context, 'btn_cancel')),
        ),
        ElevatedButton(
          onPressed: _hasTitle ? _confirm : null,
          child: Text(AppStrings.of(context, 'calendar_insert_urgent_confirm')),
        ),
      ],
    );
  }
}
