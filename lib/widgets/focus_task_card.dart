import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme/app_theme.dart';
import '../utils/app_strings.dart';
import '../utils/helpers.dart';
import 'glass_surface.dart';
import 'press_scale.dart';

class FocusTaskCard extends StatelessWidget {
  const FocusTaskCard({
    super.key,
    required this.task,
    required this.remainingSeconds,
    required this.isRunning,
    required this.onStart,
    required this.onPause,
    required this.onFinish,
    required this.onRefresh,
    this.isNextTask = false,
  });

  final ScheduleEntry? task;

  /// For the active task this is the remaining time; for a not-yet-started
  /// task it is the planned block length shown as the initial countdown.
  final int remainingSeconds;
  final bool isRunning;

  /// True when [task] is the upcoming (not yet started) task rather than the
  /// task currently inside its scheduled window.
  final bool isNextTask;
  final VoidCallback onStart;
  final VoidCallback onPause;
  final VoidCallback onFinish;
  final VoidCallback onRefresh;

  String _formatDuration(int totalSeconds) {
    final duration = Duration(seconds: math.max(0, totalSeconds));
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '${duration.inHours > 0 ? '${duration.inHours}:' : ''}$minutes:$seconds';
  }

  String _timeRange(BuildContext context, ScheduleEntry entry) {
    final minutes = (entry.height / 80 * 60).round().clamp(1, 24 * 60);
    final end = entry.time.hour * 60 + entry.time.minute + minutes;
    final endTime = TimeOfDay(hour: (end ~/ 60) % 24, minute: end % 60);
    return '${entry.time.format(context)} - ${endTime.format(context)}';
  }

  String _statusLabel(BuildContext context) {
    if (isNextTask) return AppStrings.of(context, 'focus_next_status');
    return AppStrings.of(
      context,
      isRunning ? 'calendar_status_in_progress' : 'calendar_status_not_started',
    );
  }

  Widget _loadChip(BuildContext context, ScheduleEntry entry, ThemeData theme) {
    final scheme = theme.colorScheme;
    final load = effectiveCognitiveLoad(entry);
    final (Color background, Color foreground) = switch (load) {
      CognitiveLoad.high => (scheme.errorContainer, scheme.onErrorContainer),
      CognitiveLoad.medium => (
        scheme.secondaryContainer,
        scheme.onSecondaryContainer,
      ),
      CognitiveLoad.low => (scheme.tertiaryContainer, scheme.onTertiaryContainer),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        AppStrings.of(
          context,
          'focus_load_label',
          params: {'load': AppStrings.of(context, switch (load) {
            CognitiveLoad.low => 'cognitive_load_low',
            CognitiveLoad.medium => 'cognitive_load_medium',
            CognitiveLoad.high => 'cognitive_load_high',
          })},
        ),
        style: theme.textTheme.labelSmall?.copyWith(
          color: foreground,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _tagChip(BuildContext context, ScheduleEntry entry, ThemeData theme) {
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(iconForTag(entry.tag), size: 11, color: scheme.onSurfaceVariant),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              tagLabel(context, entry.tag),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = task;
    if (current == null) {
      return GlassSurface(
        key: const ValueKey('focus-task-empty'),
        level: AppMaterialLevel.surface,
        padding: const EdgeInsets.all(24),
        tint: AppWindowTones.surface(context, AppWindowTone.focus),
        child: Column(
          children: [
            Icon(
              Icons.check_circle_outline_rounded,
              size: 30,
              color: theme.colorScheme.tertiary,
            ),
            const SizedBox(height: 10),
            Text(
              AppStrings.of(context, 'focus_empty_task'),
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            PressScale(
              child: OutlinedButton.icon(
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(AppStrings.of(context, 'btn_check')),
              ),
            ),
          ],
        ),
      );
    }

    if (MediaQuery.sizeOf(context).width < 480) {
      return _buildMobileCard(context, current, theme);
    }

    final accent = current.color;
    return GlassSurface(
      key: const ValueKey('focus-current-task'),
      level: AppMaterialLevel.surface,
      padding: EdgeInsets.zero,
      borderRadius: BorderRadius.circular(14),
      tint: AppWindowTones.surface(context, AppWindowTone.focus),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 5,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(14),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _timeRange(context, current),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      current.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        _loadChip(context, current, theme),
                        const SizedBox(width: 6),
                        Flexible(child: _tagChip(context, current, theme)),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            _statusLabel(context),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        SizedBox(
                          width: 124,
                          child: Text(
                            _formatDuration(remainingSeconds),
                            style: theme.textTheme.displaySmall?.copyWith(
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Text(
                              AppStrings.of(context, 'focus_time_remaining'),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      children: [
                        PressScale(
                          child: FilledButton.icon(
                            onPressed: isRunning ? onPause : onStart,
                            icon: Icon(
                              isRunning
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                            ),
                            label: Text(
                              AppStrings.of(
                                context,
                                isRunning ? 'btn_pause' : 'btn_start',
                              ),
                            ),
                          ),
                        ),
                        if (!isNextTask)
                          PressScale(
                            child: OutlinedButton.icon(
                              onPressed: onFinish,
                              icon: const Icon(Icons.check_rounded),
                              label: Text(AppStrings.of(context, 'btn_finish')),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileCard(
    BuildContext context,
    ScheduleEntry current,
    ThemeData theme,
  ) {
    final scheme = theme.colorScheme;
    final totalSeconds = math.max(60, ((current.height / 80) * 3600).round());
    final progress = (1 - remainingSeconds / totalSeconds).clamp(0.0, 1.0);
    return GlassSurface(
      key: const ValueKey('focus-current-task'),
      level: AppMaterialLevel.surface,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      borderRadius: BorderRadius.circular(14),
      tint: AppWindowTones.surface(context, AppWindowTone.focus),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _loadChip(context, current, theme),
                        const SizedBox(width: 6),
                        Flexible(child: _tagChip(context, current, theme)),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            _timeRange(context, current),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      current.title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontFamily: 'NotoSerifSC',
                        fontWeight: FontWeight.w700,
                        color: scheme.primary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${tagLabel(context, current.tag)} · ${isRunning ? '专注状态中' : '等待开始'}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                key: const ValueKey('focus-mobile-timer'),
                width: 112,
                height: 112,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      key: const ValueKey('focus-mobile-progress'),
                      value: progress,
                      strokeWidth: 5,
                      backgroundColor: scheme.surfaceContainerHighest,
                      color: scheme.secondary,
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _formatDuration(remainingSeconds),
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontFeatures: const [FontFeature.tabularFigures()],
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          isNextTask
                              ? AppStrings.of(context, 'focus_next_status')
                              : (isRunning ? '专注状态中' : '准备开始'),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: isRunning ? onPause : onStart,
                  icon: Icon(
                    isRunning
                        ? Icons.pause_circle_outline
                        : Icons.play_circle_outline,
                  ),
                  label: Text(isRunning ? '暂停专注' : '开始专注'),
                ),
              ),
              if (!isNextTask) ...[
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: onFinish,
                  icon: const Icon(Icons.fact_check_outlined),
                  label: const Text('结算'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
