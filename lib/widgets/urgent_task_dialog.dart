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

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController();
    _deadline = defaultUrgentDeadline(
      now: DateTime.now(),
      scheduleDay: _scheduleDay,
    );
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

  @override
  Widget build(BuildContext context) {
    final title = AppStrings.of(context, 'calendar_insert_urgent_title');
    final form = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _titleCtrl,
          decoration: InputDecoration(
            labelText: AppStrings.of(context, 'label_title'),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(AppStrings.of(context, 'label_minutes')),
            DropdownButton<int>(
              value: _minutes,
              items: const [10, 15, 25, 30, 45, 60]
                  .map((v) => DropdownMenuItem(value: v, child: Text('$v')))
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => _minutes = v);
              },
            ),
            Text(AppStrings.of(context, 'label_priority')),
            DropdownButton<int>(
              value: _priority,
              items: const [1, 2, 3, 4, 5]
                  .map((v) => DropdownMenuItem(value: v, child: Text('$v')))
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => _priority = v);
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(AppStrings.of(context, 'label_cognitive_load')),
            DropdownButton<CognitiveLoad>(
              value: _load,
              items: CognitiveLoad.values
                  .map(
                    (v) => DropdownMenuItem(
                      value: v,
                      child: Text(_cognitiveLoadLabel(context, v)),
                    ),
                  )
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => _load = v);
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        Column(
          key: const ValueKey('calendar-urgent-deadline'),
          children: [
            ListTile(
              key: const ValueKey('calendar-urgent-deadline-date'),
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: const Icon(Icons.calendar_today_outlined),
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
            child: Text(
              _deadlineValidationMessage!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
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
          onPressed: _confirm,
          child: Text(AppStrings.of(context, 'calendar_insert_urgent_confirm')),
        ),
      ],
    );
  }
}
