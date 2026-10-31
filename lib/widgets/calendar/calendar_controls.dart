import 'package:flutter/material.dart';
import '../../utils/app_strings.dart';
import '../../utils/schedule_occurrence.dart';
import '../schedule_timeline.dart';
import '../workspace_status_bar.dart';
import 'calendar_labels.dart';

class CalendarViewToolbar extends StatelessWidget {
  const CalendarViewToolbar({
    super.key,
    required this.view,
    required this.selectedDay,
    required this.onViewChanged,
    required this.onShiftPeriod,
    required this.onToday,
  });
  final ScheduleTimelineView view;
  final DateTime selectedDay;
  final ValueChanged<ScheduleTimelineView> onViewChanged;
  final ValueChanged<int> onShiftPeriod;
  final VoidCallback onToday;
  @override
  Widget build(BuildContext context) {
    final ml = MaterialLocalizations.of(context);
    final weekStart = startOfWeek(selectedDay);
    final weekEnd = weekStart.add(const Duration(days: 6));
    final label = switch (view) {
      ScheduleTimelineView.day => ml.formatMediumDate(selectedDay),
      ScheduleTimelineView.week =>
        '${ml.formatMediumDate(weekStart)} - ${ml.formatMediumDate(weekEnd)}',
      ScheduleTimelineView.month => ml.formatMonthYear(selectedDay),
      ScheduleTimelineView.gantt =>
        '${ml.formatMediumDate(weekStart)} - ${ml.formatMediumDate(weekEnd)}',
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final showSegmentIcons = constraints.maxWidth >= 600;
          final segmentPadding = showSegmentIcons
              ? const EdgeInsets.symmetric(horizontal: 14, vertical: 10)
              : const EdgeInsets.symmetric(horizontal: 18, vertical: 10);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Align(
                alignment: Alignment.topCenter,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SegmentedButton<ScheduleTimelineView>(
                    style: ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: WidgetStatePropertyAll<EdgeInsetsGeometry>(
                        segmentPadding,
                      ),
                    ),
                    segments: [
                      _viewSegment(
                        context,
                        view: ScheduleTimelineView.day,
                        icon: Icons.view_day_outlined,
                        showIcon: showSegmentIcons,
                        minLabelWidth: showSegmentIcons ? 28 : 30,
                      ),
                      _viewSegment(
                        context,
                        view: ScheduleTimelineView.week,
                        icon: Icons.view_week_outlined,
                        showIcon: showSegmentIcons,
                        minLabelWidth: showSegmentIcons ? 28 : 30,
                      ),
                      _viewSegment(
                        context,
                        view: ScheduleTimelineView.month,
                        icon: Icons.calendar_month_outlined,
                        showIcon: showSegmentIcons,
                        minLabelWidth: showSegmentIcons ? 28 : 30,
                      ),
                      _viewSegment(
                        context,
                        view: ScheduleTimelineView.gantt,
                        icon: Icons.timeline_outlined,
                        showIcon: showSegmentIcons,
                        minLabelWidth: showSegmentIcons ? 40 : 44,
                      ),
                    ],
                    selected: {view},
                    showSelectedIcon: false,
                    onSelectionChanged: (s) {
                      if (s.isEmpty) return;
                      onViewChanged(s.first);
                    },
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  IconButton(
                    onPressed: () => onShiftPeriod(-1),
                    tooltip: AppStrings.of(context, 'calendar_previous_period'),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  TextButton(
                    onPressed: () => onToday(),
                    child: Text(
                      Localizations.localeOf(context).languageCode == 'en'
                          ? 'Today'
                          : '今天',
                    ),
                  ),
                  IconButton(
                    onPressed: () => onShiftPeriod(1),
                    tooltip: AppStrings.of(context, 'calendar_next_period'),
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  ButtonSegment<ScheduleTimelineView> _viewSegment(
    BuildContext context, {
    required ScheduleTimelineView view,
    required IconData icon,
    required bool showIcon,
    required double minLabelWidth,
  }) {
    final label = calendarViewLabel(context, view);
    return ButtonSegment<ScheduleTimelineView>(
      value: view,
      icon: showIcon ? Icon(icon, size: 18) : null,
      label: ConstrainedBox(
        constraints: BoxConstraints(minWidth: minLabelWidth),
        child: Text(
          label,
          maxLines: 1,
          softWrap: false,
          textAlign: TextAlign.center,
          overflow: TextOverflow.visible,
        ),
      ),
      tooltip: label,
    );
  }
}

class CalendarPageAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  const CalendarPageAppBar({
    super.key,
    required this.sourceLabel,
    required this.smartMode,
    required this.loading,
    required this.compact,
    required this.visibleFields,
    required this.onAction,
  });
  final String sourceLabel;
  final bool smartMode;
  final bool loading;
  final bool compact;
  final Set<ScheduleTimelineField> visibleFields;
  final ValueChanged<String> onAction;
  @override
  Size get preferredSize => AppBar().preferredSize;
  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(AppStrings.of(context, 'calendar_title')),
          DataSourceBadge(
            key: const ValueKey('calendar-source-label'),
            label: sourceLabel,
          ),
        ],
      ),
      actions: [
        IconButton(
          tooltip: !smartMode
              ? AppStrings.of(context, 'calendar_tooltip_switch_to_smart')
              : AppStrings.of(context, 'calendar_tooltip_switch_to_manual'),
          icon: Icon(!smartMode ? Icons.bolt : Icons.edit_calendar),
          onPressed: loading ? null : () => onAction('mode'),
        ),
        if (!compact)
          IconButton(
            tooltip: AppStrings.of(context, 'calendar_tooltip_insert_urgent'),
            icon: const Icon(Icons.add_alert),
            onPressed: loading ? null : () => onAction('urgent'),
          ),
        IconButton(
          tooltip: AppStrings.of(context, 'calendar_refresh'),
          icon: const Icon(Icons.refresh),
          onPressed: loading ? null : () => onAction('refresh'),
        ),
        PopupMenuButton<String>(
          tooltip: AppStrings.of(context, 'tooltip_more'),
          onSelected: onAction,
          itemBuilder: (ctx) => [
            PopupMenuItem(
              value: 'goals',
              child: Text(AppStrings.of(ctx, 'goal_title')),
            ),
            if (compact)
              PopupMenuItem(
                value: 'urgent',
                enabled: !loading,
                child: Text(
                  AppStrings.of(ctx, 'calendar_tooltip_insert_urgent'),
                ),
              ),
            CheckedPopupMenuItem(
              value: 'field_time',
              checked: visibleFields.contains(ScheduleTimelineField.time),
              child: Text(calendarFieldLabel(ctx, ScheduleTimelineField.time)),
            ),
            CheckedPopupMenuItem(
              value: 'field_tag',
              checked: visibleFields.contains(ScheduleTimelineField.tag),
              child: Text(calendarFieldLabel(ctx, ScheduleTimelineField.tag)),
            ),
            CheckedPopupMenuItem(
              value: 'field_status',
              checked: visibleFields.contains(ScheduleTimelineField.status),
              child: Text(
                calendarFieldLabel(ctx, ScheduleTimelineField.status),
              ),
            ),
            CheckedPopupMenuItem(
              value: 'field_reminder',
              checked: visibleFields.contains(ScheduleTimelineField.reminder),
              child: Text(
                calendarFieldLabel(ctx, ScheduleTimelineField.reminder),
              ),
            ),
            CheckedPopupMenuItem(
              value: 'field_goal',
              checked: visibleFields.contains(ScheduleTimelineField.goal),
              child: Text(calendarFieldLabel(ctx, ScheduleTimelineField.goal)),
            ),
            PopupMenuItem(
              value: 'export',
              child: Text(AppStrings.of(ctx, 'calendar_tooltip_export_ics')),
            ),
            PopupMenuItem(
              value: 'import',
              enabled: !loading,
              child: Text(AppStrings.of(ctx, 'calendar_tooltip_import_ics')),
            ),
            PopupMenuItem(
              value: 'emotion',
              child: Text(AppStrings.of(ctx, 'emo_title')),
            ),
            PopupMenuItem(
              value: 'mcp',
              child: Text(AppStrings.of(ctx, 'mcp_title')),
            ),
          ],
        ),
      ],
    );
  }
}
