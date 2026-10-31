import 'package:flutter/material.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_strings.dart';
import '../../utils/helpers.dart';
import '../glass_surface.dart';
import '../workbench_surface.dart';
import '../workspace_status_bar.dart';
import 'calendar_labels.dart';

class CalendarTodayStatus extends StatelessWidget {
  const CalendarTodayStatus({
    super.key,
    required this.entryCount,
    required this.smartMode,
  });
  final int entryCount;
  final bool smartMode;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final modeLabel = smartMode
        ? AppStrings.of(context, 'calendar_mode_smart')
        : AppStrings.of(context, 'calendar_mode_manual');
    return GlassSurface(
      key: const ValueKey('calendar-today-status'),
      level: AppMaterialLevel.surface,
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      tint: AppWindowTones.surface(context, AppWindowTone.schedule),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Icon(
            Icons.wb_sunny_outlined,
            size: 19,
            color: theme.colorScheme.tertiary,
          ),
          Text(
            AppStrings.of(context, 'calendar_today_rhythm'),
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          Chip(
            avatar: const Icon(Icons.event_available_outlined, size: 16),
            label: Text(
              AppStrings.of(
                context,
                'calendar_schedule_count',
                params: {'count': '${entryCount}'},
              ),
            ),
            visualDensity: VisualDensity.compact,
          ),
          Chip(
            avatar: Icon(
              Icons.tune_rounded,
              size: 16,
              color: theme.colorScheme.secondary,
            ),
            label: Text(modeLabel),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

class CalendarDesktopSummary extends StatelessWidget {
  const CalendarDesktopSummary({
    super.key,
    required this.entries,
    required this.smartMode,
    required this.sourceLabel,
    this.acceptedMovedCount,
    this.onUndo,
  });
  final List<ScheduleEntry> entries;
  final bool smartMode;
  final String sourceLabel;
  final int? acceptedMovedCount;
  final VoidCallback? onUndo;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final totalMinutes = entries.fold<int>(
      0,
      (sum, entry) => sum + _entryDurationMinutes(entry),
    );
    final now = TimeOfDay.now();
    final nowMinutes = now.hour * 60 + now.minute;
    ScheduleEntry? nextEntry;
    for (final entry in entries) {
      if (entry.time.hour * 60 + entry.time.minute >= nowMinutes) {
        nextEntry = entry;
        break;
      }
    }

    return SingleChildScrollView(
      key: const ValueKey('calendar-desktop-rescue-panel'),
      padding: const EdgeInsets.fromLTRB(0, 4, 16, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          WorkbenchSurface(
            title: AppStrings.of(context, 'calendar_today_rhythm'),
            trailing: DataSourceBadge(label: sourceLabel),
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                WorkbenchMetric(
                  label: Localizations.localeOf(context).languageCode == 'en'
                      ? 'Schedule items'
                      : '日程项目',
                  value: '${entries.length}',
                  supportingText: AppStrings.of(
                    context,
                    'calendar_schedule_count',
                    params: {'count': '${entries.length}'},
                  ),
                ),
                const Divider(height: 24),
                WorkbenchMetric(
                  label: Localizations.localeOf(context).languageCode == 'en'
                      ? 'Planned time'
                      : '计划时长',
                  value: '$totalMinutes min',
                  supportingText: smartMode
                      ? AppStrings.of(context, 'calendar_mode_smart')
                      : AppStrings.of(context, 'calendar_mode_manual'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          WorkbenchSurface(
            title: Localizations.localeOf(context).languageCode == 'en'
                ? 'Next up'
                : '下一项日程',
            padding: const EdgeInsets.all(14),
            child: nextEntry == null
                ? Text(
                    AppStrings.of(context, 'calendar_week_empty'),
                    style: theme.textTheme.bodyMedium,
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 3,
                        height: 48,
                        decoration: BoxDecoration(
                          color: nextEntry.color,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              nextEntry.time.format(context),
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: theme.colorScheme.secondary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              calendarEntryTitle(context, nextEntry.title),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall,
                            ),
                            Text(
                              tagLabel(context, nextEntry.tag),
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: 12),
          WorkbenchSurface(
            title: Localizations.localeOf(context).languageCode == 'en'
                ? 'Rescue status'
                : '救援状态',
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  acceptedMovedCount == null
                      ? AppStrings.of(context, 'calendar_rescue_clear')
                      : AppStrings.of(
                          context,
                          'calendar_rescue_moved',
                          params: {'count': '${acceptedMovedCount!}'},
                        ),
                  style: theme.textTheme.bodyMedium,
                ),
                if (acceptedMovedCount != null) ...[
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: onUndo,
                    icon: const Icon(Icons.undo, size: 18),
                    label: Text(AppStrings.of(context, 'calendar_rescue_undo')),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  int _entryDurationMinutes(ScheduleEntry entry) {
    return ((entry.height / 80.0) * 60.0).round().clamp(1, 24 * 60);
  }
}
