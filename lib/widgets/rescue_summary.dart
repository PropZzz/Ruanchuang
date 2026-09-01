import 'package:flutter/material.dart';

import '../services/scheduling/schedule_rescue.dart';
import '../theme/app_theme.dart';
import '../utils/app_strings.dart';
import 'glass_surface.dart';
import 'press_scale.dart';

class RescueSummary extends StatelessWidget {
  const RescueSummary({
    super.key,
    required this.accepted,
    required this.issueCount,
    this.onUndo,
    this.compact = false,
  });

  final ScheduleRescueOption? accepted;
  final int issueCount;
  final VoidCallback? onUndo;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasAccepted = accepted != null;
    final accent = hasAccepted
        ? theme.colorScheme.tertiary
        : theme.colorScheme.secondary;
    final title = hasAccepted
        ? AppStrings.of(
            context,
            'calendar_rescue_applied',
            params: {'title': _strategyLabel(context, accepted!.strategy)},
          )
        : AppStrings.of(context, 'calendar_rescue_title');
    final subtitle = hasAccepted
        ? AppStrings.of(
            context,
            'calendar_rescue_moved',
            params: {'count': '${accepted!.movedEntryCount}'},
          )
        : issueCount > 0
        ? AppStrings.of(
            context,
            'calendar_rescue_attention',
            params: {'count': '$issueCount'},
          )
        : AppStrings.of(context, 'calendar_rescue_clear');

    return GlassSurface(
      key: const ValueKey('calendar-rescue-summary'),
      margin: EdgeInsets.fromLTRB(compact ? 12 : 20, 4, compact ? 12 : 20, 8),
      padding: EdgeInsets.zero,
      borderRadius: BorderRadius.circular(16),
      tint: AppWindowTones.surface(context, AppWindowTone.schedule),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            hasAccepted ? Icons.check_rounded : Icons.route_outlined,
            color: accent,
            size: 21,
          ),
        ),
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: hasAccepted && onUndo != null
            ? PressScale(
                child: TextButton.icon(
                  onPressed: onUndo,
                  icon: const Icon(Icons.undo_rounded, size: 18),
                  label: Text(AppStrings.of(context, 'calendar_rescue_undo')),
                ),
              )
            : Icon(
                Icons.chevron_right_rounded,
                color: theme.colorScheme.onSurfaceVariant,
              ),
      ),
    );
  }

  String _strategyLabel(BuildContext context, RescueStrategy strategy) {
    switch (strategy) {
      case RescueStrategy.protectDeadline:
        return AppStrings.of(context, 'review_rescue_protect_deadline');
      case RescueStrategy.protectRecovery:
        return AppStrings.of(context, 'review_rescue_protect_recovery');
      case RescueStrategy.minimizeChanges:
        return AppStrings.of(context, 'review_rescue_minimize_changes');
    }
  }
}
