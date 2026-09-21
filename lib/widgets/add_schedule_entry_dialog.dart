import 'package:flutter/material.dart';

import '../models/models.dart';
import '../utils/app_strings.dart';
import '../utils/mobile_feedback.dart';
import '../utils/schedule_occurrence.dart';

/// Collects a new schedule entry (title, tag, duration, color, start time,
/// reminder, repeat rule) and returns it, or null when cancelled.
///
/// Pure input collection: no network, database, or global service access.
/// Persisting the entry and reloading the schedule is the caller's job.
Future<ScheduleEntry?> showAddScheduleEntryDialog(
  BuildContext context, {
  required DateTime day,
}) {
  return showDialog<ScheduleEntry>(
    context: context,
    builder: (ctx) => _AddScheduleEntryDialog(day: dateOnly(day)),
  );
}

class _AddScheduleEntryDialog extends StatefulWidget {
  const _AddScheduleEntryDialog({required this.day});

  final DateTime day;

  @override
  State<_AddScheduleEntryDialog> createState() =>
      _AddScheduleEntryDialogState();
}

class _AddScheduleEntryDialogState extends State<_AddScheduleEntryDialog> {
  final _titleCtrl = TextEditingController();
  final _tagCtrl = TextEditingController();
  double _height = 60;
  Color? _colorOverride;
  TimeOfDay _selectedTime = TimeOfDay.now();
  int _reminderMinutesBefore = 10;
  RepeatFrequency _repeat = RepeatFrequency.none;
  DateTime? _repeatUntil;

  Color _selectedColor(BuildContext context) =>
      _colorOverride ?? Theme.of(context).colorScheme.primary;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _tagCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickStartTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
      cancelText: AppStrings.of(context, 'btn_cancel'),
      confirmText: AppStrings.of(context, 'btn_confirm'),
    );
    if (t != null) setState(() => _selectedTime = t);
  }

  Future<void> _pickRepeatUntil() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _repeatUntil ?? now,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 10, 12, 31),
      cancelText: AppStrings.of(context, 'btn_cancel'),
      confirmText: AppStrings.of(context, 'btn_confirm'),
    );
    if (picked == null) return;
    setState(() {
      _repeatUntil = DateTime(picked.year, picked.month, picked.day);
    });
  }

  void _confirm() {
    final title = _titleCtrl.text.trim();
    final tag = _tagCtrl.text.trim();
    if (title.isEmpty) return;

    Navigator.of(context).pop(
      ScheduleEntry(
        day: widget.day,
        title: title,
        tag: tag.isEmpty ? 'General' : tag,
        height: _height,
        color: _selectedColor(context),
        time: _selectedTime,
        reminderMinutesBefore: _reminderMinutesBefore,
        repeat: _repeat,
        repeatUntil: _repeatUntil,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(AppStrings.of(context, 'dialog_add_title')),
      content: ConstrainedBox(
        constraints: MobileFeedback.dialogConstraints(context, maxWidth: 460),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _titleCtrl,
                decoration: InputDecoration(
                  labelText: AppStrings.of(context, 'label_title'),
                ),
              ),
              TextField(
                controller: _tagCtrl,
                decoration: InputDecoration(
                  labelText: AppStrings.of(context, 'label_tag'),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(AppStrings.of(context, 'label_duration')),
                  DropdownButton<double>(
                    value: _height,
                    items: const [
                      DropdownMenuItem(value: 40, child: Text('30')),
                      DropdownMenuItem(value: 60, child: Text('45')),
                      DropdownMenuItem(value: 80, child: Text('60')),
                      DropdownMenuItem(value: 120, child: Text('90')),
                    ],
                    onChanged: (v) {
                      if (v != null) setState(() => _height = v);
                    },
                  ),
                  DropdownButton<Color>(
                    value: _selectedColor(context),
                    items: [
                      DropdownMenuItem(
                        value: scheme.primary,
                        child: Text(AppStrings.of(context, 'color_green')),
                      ),
                      DropdownMenuItem(
                        value: scheme.secondary,
                        child: Text(AppStrings.of(context, 'color_blue')),
                      ),
                      DropdownMenuItem(
                        value: scheme.tertiary,
                        child: Text(AppStrings.of(context, 'color_orange')),
                      ),
                    ],
                    onChanged: (c) {
                      if (c != null) setState(() => _colorOverride = c);
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
                  Text(AppStrings.of(context, 'label_start_time')),
                  TextButton(
                    onPressed: _pickStartTime,
                    child: Text(_selectedTime.format(context)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(AppStrings.of(context, 'calendar_reminder_label')),
                  DropdownButton<int>(
                    value: _reminderMinutesBefore,
                    items: [
                      DropdownMenuItem(
                        value: 0,
                        child: Text(
                          AppStrings.of(context, 'calendar_reminder_none'),
                        ),
                      ),
                      ...[5, 10, 15, 30, 60].map(
                        (v) => DropdownMenuItem(value: v, child: Text('$v')),
                      ),
                    ],
                    onChanged: (v) {
                      if (v != null) {
                        setState(() => _reminderMinutesBefore = v);
                      }
                    },
                  ),
                  if (_reminderMinutesBefore > 0)
                    Text(AppStrings.of(context, 'calendar_reminder_suffix')),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(AppStrings.of(context, 'calendar_repeat_label')),
                  DropdownButton<RepeatFrequency>(
                    value: _repeat,
                    items: [
                      DropdownMenuItem(
                        value: RepeatFrequency.none,
                        child: Text(
                          AppStrings.of(context, 'calendar_repeat_none'),
                        ),
                      ),
                      DropdownMenuItem(
                        value: RepeatFrequency.daily,
                        child: Text(
                          AppStrings.of(context, 'calendar_repeat_daily'),
                        ),
                      ),
                      DropdownMenuItem(
                        value: RepeatFrequency.weekly,
                        child: Text(
                          AppStrings.of(context, 'calendar_repeat_weekly'),
                        ),
                      ),
                      DropdownMenuItem(
                        value: RepeatFrequency.monthly,
                        child: Text(
                          AppStrings.of(context, 'calendar_repeat_monthly'),
                        ),
                      ),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() {
                        _repeat = v;
                        if (_repeat == RepeatFrequency.none) {
                          _repeatUntil = null;
                        }
                      });
                    },
                  ),
                ],
              ),
              if (_repeat != RepeatFrequency.none) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(AppStrings.of(context, 'calendar_repeat_until')),
                    TextButton(
                      onPressed: _pickRepeatUntil,
                      child: Text(
                        _repeatUntil == null
                            ? AppStrings.of(
                                context,
                                'calendar_repeat_until_none',
                              )
                            : '${_repeatUntil!.year}-${_repeatUntil!.month.toString().padLeft(2, '0')}-${_repeatUntil!.day.toString().padLeft(2, '0')}',
                      ),
                    ),
                    if (_repeatUntil != null)
                      IconButton(
                        tooltip: AppStrings.of(context, 'btn_delete'),
                        onPressed: () => setState(() => _repeatUntil = null),
                        icon: const Icon(Icons.clear),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(AppStrings.of(context, 'btn_cancel')),
        ),
        ElevatedButton(
          onPressed: _confirm,
          child: Text(AppStrings.of(context, 'btn_add')),
        ),
      ],
    );
  }
}
