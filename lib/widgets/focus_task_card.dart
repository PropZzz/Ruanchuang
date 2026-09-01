import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme/app_theme.dart';
import '../utils/app_strings.dart';
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
  });

  final ScheduleEntry? task;
  final int remainingSeconds;
  final bool isRunning;
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
                    Text(
                      '${current.tag} · ${isRunning ? AppStrings.of(context, 'calendar_status_in_progress') : AppStrings.of(context, 'calendar_status_not_started')}',
                      style: theme.textTheme.bodyMedium,
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
}
