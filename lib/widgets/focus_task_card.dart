import 'package:flutter/material.dart';

import '../models/models.dart';
import '../utils/app_strings.dart';
import '../utils/helpers.dart';
import 'glass_surface.dart';

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
    final duration = Duration(seconds: totalSeconds);
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '${duration.inHours > 0 ? '${duration.inHours}:' : ''}$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = task;
    if (current == null) {
      return GlassSurface(
        key: const ValueKey('focus-task-empty'),
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(
              Icons.wb_sunny_outlined,
              size: 28,
              color: theme.colorScheme.tertiary,
            ),
            const SizedBox(height: 10),
            Text(
              AppStrings.of(context, 'focus_empty_task'),
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(AppStrings.of(context, 'btn_check')),
            ),
          ],
        ),
      );
    }

    return GlassSurface(
      key: const ValueKey('focus-current-task'),
      borderRadius: BorderRadius.circular(20),
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondary.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  iconForTag(current.tag),
                  color: theme.colorScheme.secondary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  current.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            '${AppStrings.of(context, 'focus_time_remaining')}${_formatDuration(remainingSeconds)}',
            style: theme.textTheme.displaySmall?.copyWith(
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: isRunning ? onPause : onStart,
                icon: Icon(
                  isRunning ? Icons.pause_rounded : Icons.play_arrow_rounded,
                ),
                label: Text(
                  AppStrings.of(context, isRunning ? 'btn_pause' : 'btn_start'),
                ),
              ),
              OutlinedButton.icon(
                onPressed: onFinish,
                icon: const Icon(Icons.check_rounded),
                label: Text(AppStrings.of(context, 'btn_finish')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
