import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme/app_theme.dart';
import '../utils/app_strings.dart';
import '../utils/helpers.dart';
import '../utils/mobile_feedback.dart';
import '../utils/schedule_occurrence.dart';
import 'stitch_form_sheet.dart';

const _tagPresets = ['General', 'Deep Work', 'Micro Task', 'Routine', 'Goal'];
const _durationOptions = <int, double>{30: 40, 45: 60, 60: 80, 90: 120};

String _presetTagLabel(BuildContext context, String tag) =>
    tagLabel(context, tag);

/// Collects a new schedule entry (title, tag, duration, color, start time,
/// reminder, repeat rule) and returns it, or null when cancelled.
///
/// Pure input collection: no network, database, or global service access.
/// Persisting the entry and reloading the schedule is the caller's job.
Future<ScheduleEntry?> showAddScheduleEntryDialog(
  BuildContext context, {
  required DateTime day,
}) {
  if (MediaQuery.sizeOf(context).width < AppTheme.compactShellBreakpoint) {
    return showModalBottomSheet<ScheduleEntry>(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      builder: (ctx) =>
          _AddScheduleEntryDialog(day: dateOnly(day), bottomSheet: true),
    );
  }
  return showDialog<ScheduleEntry>(
    context: context,
    builder: (ctx) => _AddScheduleEntryDialog(day: dateOnly(day)),
  );
}

class _AddScheduleEntryDialog extends StatefulWidget {
  const _AddScheduleEntryDialog({required this.day, this.bottomSheet = false});

  final DateTime day;
  final bool bottomSheet;

  @override
  State<_AddScheduleEntryDialog> createState() =>
      _AddScheduleEntryDialogState();
}

class _AddScheduleEntryDialogState extends State<_AddScheduleEntryDialog> {
  final _titleCtrl = TextEditingController();
  double _height = 60;
  String _tag = 'General';
  Color? _colorOverride;
  TimeOfDay _selectedTime = TimeOfDay.now();
  int _reminderMinutesBefore = 10;
  RepeatFrequency _repeat = RepeatFrequency.none;
  DateTime? _repeatUntil;

  Color _selectedColor(BuildContext context) =>
      _colorOverride ?? Theme.of(context).colorScheme.tertiary;

  bool get _hasTitle => _titleCtrl.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _titleCtrl.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
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
    if (title.isEmpty) return;

    Navigator.of(context).pop(
      ScheduleEntry(
        day: widget.day,
        title: title,
        tag: _tag,
        height: _height,
        color: _selectedColor(context),
        time: _selectedTime,
        reminderMinutesBefore: _reminderMinutesBefore,
        repeat: _repeat,
        repeatUntil: _repeatUntil,
      ),
    );
  }

  String _formatRepeatUntil() =>
      '${_repeatUntil!.year}-${_repeatUntil!.month.toString().padLeft(2, '0')}-${_repeatUntil!.day.toString().padLeft(2, '0')}';

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
  /// `_buildScheduleBlock` in the calendar page) so the entry can be
  /// previewed before it lands on the schedule.
  Widget _buildPreview(BuildContext context) {
    final tagIcon = iconForTag(_tag);
    final title = _titleCtrl.text.trim();
    return AnimatedContainer(
      key: const ValueKey('calendar-add-preview'),
      duration: const Duration(milliseconds: 180),
      constraints: const BoxConstraints(minHeight: 64),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _selectedColor(context).withAlpha((0.9 * 255).round()),
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
              Icon(tagIcon, size: 18, color: Colors.white70),
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
                Icons.schedule,
                _selectedTime.format(context),
              ),
              _previewChip(tagIcon, _presetTagLabel(context, _tag)),
              if (_reminderMinutesBefore > 0)
                _previewChip(
                  Icons.notifications_none,
                  '-$_reminderMinutesBefore m',
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

  Widget _buildTagPicker(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final tag in _tagPresets)
          ChoiceChip(
            avatar: Icon(iconForTag(tag), size: 16),
            label: Text(_presetTagLabel(context, tag)),
            selected: _tag == tag,
            onSelected: (_) => setState(() => _tag = tag),
          ),
      ],
    );
  }

  Widget _buildDurationPicker() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final minutes in _durationOptions.keys)
          ChoiceChip(
            label: Text('$minutes'),
            selected: _durationOptions[minutes] == _height,
            onSelected: (_) =>
                setState(() => _height = _durationOptions[minutes]!),
          ),
      ],
    );
  }

  Widget _buildColorPicker(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pressureColor = scheme.brightness == Brightness.dark
        ? AppThemeTokens.pressureDark
        : AppThemeTokens.pressureLight;
    final options = [
      (scheme.tertiary, AppStrings.of(context, 'color_green')),
      (scheme.secondary, AppStrings.of(context, 'color_blue')),
      (pressureColor, AppStrings.of(context, 'color_orange')),
    ];
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: [
        for (final (color, label) in options)
          Tooltip(
            message: label,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => setState(() => _colorOverride = color),
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _selectedColor(context) == color
                        ? scheme.onSurface
                        : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: color),
                  child: _selectedColor(context) == color
                      ? const Icon(Icons.check, size: 16, color: Colors.white)
                      : null,
                ),
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = AppStrings.of(context, 'dialog_add_title');
    final form = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.calendar_today_outlined,
              size: 14,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              MaterialLocalizations.of(context).formatMediumDate(widget.day),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        const SizedBox(height: 12),
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
        _sectionLabel(context, AppStrings.of(context, 'label_tag')),
        const SizedBox(height: 8),
        _buildTagPicker(context),
        const SizedBox(height: 16),
        _sectionLabel(context, AppStrings.of(context, 'label_duration')),
        const SizedBox(height: 8),
        _buildDurationPicker(),
        const SizedBox(height: 16),
        _sectionLabel(context, AppStrings.of(context, 'label_color')),
        const SizedBox(height: 8),
        _buildColorPicker(context),
        const SizedBox(height: 8),
        ListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          leading: const Icon(Icons.schedule_outlined),
          title: Text(AppStrings.of(context, 'label_start_time')),
          trailing: Text(_selectedTime.format(context)),
          onTap: _pickStartTime,
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          leading: const Icon(Icons.notifications_none),
          title: Text(AppStrings.of(context, 'calendar_reminder_label')),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  value: _reminderMinutesBefore,
                  isDense: true,
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
              ),
              if (_reminderMinutesBefore > 0)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(AppStrings.of(context, 'calendar_reminder_suffix')),
                ),
            ],
          ),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          leading: const Icon(Icons.repeat),
          title: Text(AppStrings.of(context, 'calendar_repeat_label')),
          trailing: DropdownButtonHideUnderline(
            child: DropdownButton<RepeatFrequency>(
              value: _repeat,
              isDense: true,
              items: [
                DropdownMenuItem(
                  value: RepeatFrequency.none,
                  child: Text(AppStrings.of(context, 'calendar_repeat_none')),
                ),
                DropdownMenuItem(
                  value: RepeatFrequency.daily,
                  child: Text(AppStrings.of(context, 'calendar_repeat_daily')),
                ),
                DropdownMenuItem(
                  value: RepeatFrequency.weekly,
                  child: Text(AppStrings.of(context, 'calendar_repeat_weekly')),
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
          ),
        ),
        if (_repeat != RepeatFrequency.none)
          ListTile(
            key: const ValueKey('calendar-add-repeat-until'),
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: const Icon(Icons.event_outlined),
            title: Text(AppStrings.of(context, 'calendar_repeat_until')),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _repeatUntil == null
                      ? AppStrings.of(context, 'calendar_repeat_until_none')
                      : _formatRepeatUntil(),
                ),
                if (_repeatUntil != null)
                  IconButton(
                    tooltip: AppStrings.of(context, 'btn_delete'),
                    onPressed: () => setState(() => _repeatUntil = null),
                    icon: const Icon(Icons.clear, size: 18),
                  ),
              ],
            ),
            onTap: _pickRepeatUntil,
          ),
      ],
    );
    if (widget.bottomSheet) {
      return StitchFormSheet(
        title: title,
        content: form,
        onCancel: () => Navigator.of(context).pop(),
        onConfirm: _confirm,
        confirmLabel: AppStrings.of(context, 'btn_add'),
        confirmEnabled: _hasTitle,
      );
    }
    return AlertDialog(
      title: Text(title),
      content: ConstrainedBox(
        constraints: MobileFeedback.dialogConstraints(context, maxWidth: 460),
        child: SingleChildScrollView(child: form),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(AppStrings.of(context, 'btn_cancel')),
        ),
        ElevatedButton(
          onPressed: _hasTitle ? _confirm : null,
          child: Text(AppStrings.of(context, 'btn_add')),
        ),
      ],
    );
  }
}
