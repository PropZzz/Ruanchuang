import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/models.dart';
import '../utils/schedule_occurrence.dart';

enum ScheduleTimelineView { day, week, month, gantt }

enum ScheduleTimelineField { time, tag, status, reminder, goal }

/// A service-free schedule presentation component.
class ScheduleTimeline extends StatelessWidget {
  const ScheduleTimeline({
    super.key,
    required this.entries,
    required this.selectedDay,
    required this.view,
    this.visibleFields = const {
      ScheduleTimelineField.time,
      ScheduleTimelineField.tag,
      ScheduleTimelineField.status,
      ScheduleTimelineField.reminder,
      ScheduleTimelineField.goal,
    },
    this.statusByTaskId = const {},
    this.startHour = 8,
    this.endHour = 20,
    this.titleBuilder,
    this.tagBuilder,
    this.statusBuilder,
    this.reminderBuilder,
    this.emptyLabel = 'No events',
    this.goalLabel = 'Goal',
    this.ganttLabel = 'Gantt',
    this.taskLaneLabel = 'Task',
    this.deleteLabel = 'Delete schedule',
    this.onSelectDay,
    this.onDelete,
    this.onEntryTap,
  }) : assert(endHour > startHour);

  final List<ScheduleEntry> entries;
  final DateTime selectedDay;
  final ScheduleTimelineView view;
  final Set<ScheduleTimelineField> visibleFields;
  final Map<String, String> statusByTaskId;
  final int startHour;
  final int endHour;
  final String Function(BuildContext, ScheduleEntry)? titleBuilder;
  final String Function(BuildContext, String)? tagBuilder;
  final String Function(BuildContext, String)? statusBuilder;
  final String Function(BuildContext, int)? reminderBuilder;
  final String emptyLabel;
  final String goalLabel;
  final String ganttLabel;
  final String taskLaneLabel;
  final String deleteLabel;
  final ValueChanged<DateTime>? onSelectDay;
  final ValueChanged<ScheduleEntry>? onDelete;
  final ValueChanged<ScheduleEntry>? onEntryTap;

  static const double _gutterWidth = 68;
  static const double _labelLaneWidth = 160;
  static const double _minTrackWidth = 760;
  static const double _hourHeight = 80;

  @override
  Widget build(BuildContext context) {
    switch (view) {
      case ScheduleTimelineView.day:
        return _buildDay(context);
      case ScheduleTimelineView.week:
        return _buildWeek(context);
      case ScheduleTimelineView.month:
        return _buildMonth(context);
      case ScheduleTimelineView.gantt:
        return _buildGantt(context);
    }
  }

  List<ScheduleEntry> _forDay(DateTime day) {
    final result = entriesForDay(day: day, allEntries: entries).toList();
    result.sort(_compareEntries);
    return result;
  }

  int _compareEntries(ScheduleEntry a, ScheduleEntry b) {
    final aMinutes = a.time.hour * 60 + a.time.minute;
    final bMinutes = b.time.hour * 60 + b.time.minute;
    return aMinutes.compareTo(bMinutes);
  }

  Widget _buildDay(BuildContext context) {
    final dayEntries = _forDay(selectedDay);
    final totalHeight = (endHour - startHour) * _hourHeight;
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : _minTrackWidth + _gutterWidth;
        final trackWidth = math.max(
          _minTrackWidth,
          viewportWidth - _gutterWidth,
        );
        return SingleChildScrollView(
          padding: EdgeInsets.only(
            left: 12,
            right: 12,
            bottom: MediaQuery.of(context).padding.bottom + 100,
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: _gutterWidth + trackWidth,
              height: totalHeight,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHourGutter(context, totalHeight),
                  ConstrainedBox(
                    key: const ValueKey('schedule-timeline-track'),
                    constraints: const BoxConstraints(minWidth: _minTrackWidth),
                    child: SizedBox(
                      width: trackWidth,
                      height: totalHeight,
                      child: _buildTrack(
                        context,
                        entries: dayEntries,
                        totalHeight: totalHeight,
                        trackWidth: trackWidth,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHourGutter(BuildContext context, double totalHeight) {
    return SizedBox(
      width: _gutterWidth,
      height: totalHeight,
      child: Column(
        children: List.generate(
          endHour - startHour,
          (index) => SizedBox(
            height: _hourHeight,
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('${startHour + index}:00'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTrack(
    BuildContext context, {
    required List<ScheduleEntry> entries,
    required double totalHeight,
    required double trackWidth,
  }) {
    final theme = Theme.of(context);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        ColoredBox(
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: .18,
          ),
          child: SizedBox.expand(),
        ),
        ...List.generate(
          endHour - startHour,
          (index) => Positioned(
            top: index * _hourHeight,
            left: 0,
            right: 0,
            child: Container(
              height: _hourHeight,
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: theme.colorScheme.outlineVariant),
                ),
              ),
            ),
          ),
        ),
        if (entries.isEmpty)
          Center(
            child: Text(
              emptyLabel,
              style: TextStyle(color: theme.colorScheme.outline),
            ),
          ),
        ...entries.map((entry) {
          final top = _topFor(entry);
          final height = math.max(48.0, entry.height);
          return Positioned(
            top: top,
            left: 8,
            right: 8,
            height: math.min(height, totalHeight - top),
            child: _buildEvent(context, entry),
          );
        }),
      ],
    );
  }

  double _topFor(ScheduleEntry entry) {
    final minutes = entry.time.hour * 60 + entry.time.minute;
    final startMinutes = startHour * 60;
    return ((minutes - startMinutes) / 60 * _hourHeight)
        .clamp(0.0, (endHour - startHour) * _hourHeight - 48.0)
        .toDouble();
  }

  Widget _buildEvent(BuildContext context, ScheduleEntry entry) {
    final theme = Theme.of(context);
    final accent = entry.color;
    final surface = Color.alphaBlend(
      accent.withValues(alpha: .12),
      theme.colorScheme.surface,
    );
    final status = entry.id == null ? null : statusByTaskId[entry.id!];
    final title = titleBuilder?.call(context, entry) ?? entry.title;
    return Semantics(
      container: true,
      label: title,
      button: onEntryTap != null,
      child: Material(
        color: surface,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onEntryTap == null ? null : () => onEntryTap!(entry),
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: theme.colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.fromLTRB(10, 8, 4, 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 4,
                  height: 44,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                if (onDelete != null)
                  Tooltip(
                    message: deleteLabel,
                    child: IconButton(
                      key: const ValueKey('schedule-entry-delete'),
                      onPressed: () => onDelete!(entry),
                      icon: const Icon(Icons.delete_outline),
                      constraints: const BoxConstraints(
                        minWidth: 44,
                        minHeight: 44,
                      ),
                      padding: EdgeInsets.zero,
                    ),
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 3),
                      Wrap(
                        spacing: 8,
                        runSpacing: 2,
                        children: _metadata(context, entry, status),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _metadata(
    BuildContext context,
    ScheduleEntry entry,
    String? status,
  ) {
    final result = <Widget>[];
    if (visibleFields.contains(ScheduleTimelineField.time)) {
      result.add(_metaText(entry.time.format(context)));
    }
    if (visibleFields.contains(ScheduleTimelineField.tag) &&
        entry.tag.isNotEmpty) {
      result.add(_metaText(tagBuilder?.call(context, entry.tag) ?? entry.tag));
    }
    if (visibleFields.contains(ScheduleTimelineField.status) &&
        status != null) {
      result.add(_metaText(statusBuilder?.call(context, status) ?? status));
    }
    if (visibleFields.contains(ScheduleTimelineField.reminder) &&
        entry.reminderMinutesBefore > 0) {
      result.add(
        _metaText(
          reminderBuilder?.call(context, entry.reminderMinutesBefore) ??
              '${entry.reminderMinutesBefore}m',
        ),
      );
    }
    if (visibleFields.contains(ScheduleTimelineField.goal) &&
        ((entry.goalId?.isNotEmpty ?? false) ||
            (entry.goalTaskId?.isNotEmpty ?? false))) {
      result.add(_metaText(goalLabel));
    }
    return result;
  }

  Widget _metaText(String value) => Text(
    value,
    style: const TextStyle(fontSize: 12),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
  );

  String _durationLabel(ScheduleEntry entry) {
    final minutes = math.max(1, (entry.height / 80.0 * 60.0).round());
    if (minutes >= 60 && minutes % 60 == 0) return '${minutes ~/ 60}h';
    return '${minutes}m';
  }

  Widget _buildWeek(BuildContext context) {
    final weekStart = startOfWeek(selectedDay);
    final days = List.generate(
      7,
      (index) => weekStart.add(Duration(days: index)),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.max(7 * 148.0, constraints.maxWidth);
        return SingleChildScrollView(
          padding: EdgeInsets.only(
            left: 12,
            right: 12,
            bottom: MediaQuery.of(context).padding.bottom + 100,
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: width,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: days
                    .map(
                      (day) => Expanded(child: _buildWeekColumn(context, day)),
                    )
                    .toList(growable: false),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildWeekColumn(BuildContext context, DateTime day) {
    final theme = Theme.of(context);
    final selected = sameDay(day, selectedDay);
    final localizations = MaterialLocalizations.of(context);
    final label =
        '${localizations.narrowWeekdays[day.weekday % 7]} ${day.month}/${day.day}';
    final dayEntries = _forDay(day);
    return InkWell(
      onTap: onSelectDay == null ? null : () => onSelectDay!(day),
      child: Container(
        constraints: const BoxConstraints(minHeight: 180),
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primaryContainer.withValues(alpha: .35)
              : theme.colorScheme.surface,
          border: Border.all(
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            if (dayEntries.isEmpty)
              Text(
                emptyLabel,
                textAlign: TextAlign.center,
                style: TextStyle(color: theme.colorScheme.outline),
              )
            else
              ...dayEntries.map(
                (entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: _buildEvent(context, entry),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMonth(BuildContext context) {
    final first = DateTime(selectedDay.year, selectedDay.month, 1);
    final gridStart = startOfWeek(first);
    final days = List.generate(
      42,
      (index) => gridStart.add(Duration(days: index)),
    );
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final cellWidth = math.max(96.0, (constraints.maxWidth - 24) / 7);
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            12,
            8,
            12,
            MediaQuery.of(context).padding.bottom + 100,
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: cellWidth * 7,
              child: Column(
                children: [
                  Row(
                    children: List.generate(
                      7,
                      (index) => Expanded(
                        child: Text(
                          MaterialLocalizations.of(
                            context,
                          ).narrowWeekdays[(index + 1) % 7],
                          textAlign: TextAlign.center,
                          style: TextStyle(color: theme.colorScheme.outline),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  ...List.generate(
                    6,
                    (week) => SizedBox(
                      height: 112,
                      child: Row(
                        children: days
                            .skip(week * 7)
                            .take(7)
                            .map(
                              (day) => Expanded(
                                child: _buildMonthCell(context, day, first),
                              ),
                            )
                            .toList(growable: false),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMonthCell(BuildContext context, DateTime day, DateTime month) {
    final theme = Theme.of(context);
    final selected = sameDay(day, selectedDay);
    final inMonth = day.month == month.month;
    final dayEntries = _forDay(day);
    final firstEntry = dayEntries.isEmpty ? null : dayEntries.first;
    final firstStatus = firstEntry?.id == null
        ? null
        : statusByTaskId[firstEntry!.id!];
    return InkWell(
      onTap: onSelectDay == null ? null : () => onSelectDay!(day),
      child: Container(
        margin: const EdgeInsets.all(3),
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primaryContainer.withValues(alpha: .45)
              : theme.colorScheme.surface,
          border: Border.all(
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
          ),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Opacity(
          opacity: inMonth ? 1 : .45,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${day.day}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              if (firstEntry != null) ...[
                const SizedBox(height: 4),
                Text(
                  titleBuilder?.call(context, firstEntry) ?? firstEntry.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11),
                ),
                ..._metadata(context, firstEntry, firstStatus).map(
                  (meta) => DefaultTextStyle.merge(
                    style: const TextStyle(fontSize: 10),
                    child: meta,
                  ),
                ),
                if (dayEntries.length > 1)
                  Text(
                    '+${dayEntries.length - 1}',
                    style: TextStyle(
                      color: theme.colorScheme.outline,
                      fontSize: 11,
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGantt(BuildContext context) {
    final weekStart = startOfWeek(selectedDay);
    final days = List.generate(
      7,
      (index) => weekStart.add(Duration(days: index)),
    );
    const ganttStartHour = 0;
    const ganttEndHour = 24;
    const ganttHours = ganttEndHour - ganttStartHour;
    final totalMinutes = ganttHours * 60.0;
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        12,
        8,
        12,
        MediaQuery.of(context).padding.bottom + 100,
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: _gutterWidth + _labelLaneWidth + _minTrackWidth,
          child: Column(
            children: [
              Row(
                children: [
                  SizedBox(width: _gutterWidth, child: Text(ganttLabel)),
                  SizedBox(width: _labelLaneWidth, child: Text(taskLaneLabel)),
                  ConstrainedBox(
                    key: const ValueKey('schedule-timeline-gantt-track'),
                    constraints: const BoxConstraints(minWidth: _minTrackWidth),
                    child: SizedBox(
                      width: _minTrackWidth,
                      height: 32,
                      child: Stack(
                        children: [
                          for (var hour = 0; hour <= ganttHours; hour++)
                            Positioned(
                              left: hour / ganttHours * _minTrackWidth,
                              top: 0,
                              child: Text(
                                '${ganttStartHour + hour}:00',
                                style: const TextStyle(fontSize: 10),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              ...days.asMap().entries.map((item) {
                final index = item.key;
                final day = item.value;
                final dayEntries = _forDay(day);
                final rowHeight = math.max(
                  128.0,
                  24.0 + dayEntries.length * 100.0,
                );
                return SizedBox(
                  height: rowHeight,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        key: ValueKey('schedule-timeline-gantt-day-$index'),
                        width: _gutterWidth,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            '${MaterialLocalizations.of(context).narrowWeekdays[day.weekday % 7]} ${day.month}/${day.day}',
                          ),
                        ),
                      ),
                      SizedBox(
                        key: ValueKey(
                          'schedule-timeline-gantt-label-lane-$index',
                        ),
                        width: _labelLaneWidth,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              height: 24,
                              child: Text(
                                '${MaterialLocalizations.of(context).narrowWeekdays[day.weekday % 7]} ${day.month}/${day.day}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: theme.colorScheme.outline,
                                ),
                              ),
                            ),
                            ...dayEntries.map(
                              (entry) => SizedBox(
                                height: 100,
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    8,
                                    4,
                                    8,
                                    4,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        titleBuilder?.call(context, entry) ??
                                            entry.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 12,
                                        ),
                                      ),
                                      Text(
                                        '${entry.time.format(context)} / ${_durationLabel(entry)}',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: theme.colorScheme.outline,
                                        ),
                                      ),
                                      Wrap(
                                        spacing: 5,
                                        runSpacing: 1,
                                        children: _metadata(
                                          context,
                                          entry,
                                          entry.id == null
                                              ? null
                                              : statusByTaskId[entry.id!],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: _minTrackWidth,
                        child: Stack(
                          children: [
                            for (var hour = 0; hour <= ganttHours; hour++)
                              Positioned(
                                left: hour / ganttHours * _minTrackWidth,
                                top: 0,
                                bottom: 0,
                                child: Container(
                                  width: 1,
                                  color: theme.colorScheme.outlineVariant,
                                ),
                              ),
                            if (dayEntries.isEmpty)
                              Center(
                                child: Text(
                                  emptyLabel,
                                  style: TextStyle(
                                    color: theme.colorScheme.outline,
                                  ),
                                ),
                              ),
                            ...dayEntries.asMap().entries.expand((entryItem) {
                              final entryIndex = entryItem.key;
                              final entry = entryItem.value;
                              final start =
                                  ((entry.time.hour * 60 + entry.time.minute) -
                                          ganttStartHour * 60)
                                      .clamp(0, totalMinutes.toInt())
                                      .toDouble();
                              final duration = math.max(
                                30.0,
                                (entry.height / 80.0) * 60.0,
                              );
                              final left =
                                  start / totalMinutes * _minTrackWidth;
                              final remaining = math.max(
                                0.0,
                                _minTrackWidth - left,
                              );
                              if (remaining <= 0) return <Widget>[];
                              final desiredWidth =
                                  duration / totalMinutes * _minTrackWidth;
                              final width = math.min(
                                remaining,
                                math.max(48.0, desiredWidth),
                              );
                              return <Widget>[
                                Positioned(
                                  key: ValueKey(
                                    'schedule-timeline-gantt-bar-${entry.id ?? entry.title}',
                                  ),
                                  left: left,
                                  top: 24.0 + entryIndex * 100.0,
                                  width: width,
                                  child: _buildEvent(context, entry),
                                ),
                              ];
                            }),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}
