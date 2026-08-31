import 'package:flutter/material.dart';

import '../services/scheduling/schedule_rescue.dart';
import 'glass_surface.dart';

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
    final title = hasAccepted ? '已采用：${accepted!.title}' : '日程救援';
    final subtitle = hasAccepted
        ? '本次调整移动 ${accepted!.movedEntryCount} 项日程'
        : issueCount > 0
        ? '有 $issueCount 项规划提示需要关注'
        : '当前没有待处理冲突，按原计划推进';

    return GlassSurface(
      key: const ValueKey('calendar-rescue-summary'),
      margin: EdgeInsets.fromLTRB(compact ? 12 : 20, 4, compact ? 12 : 20, 8),
      padding: EdgeInsets.zero,
      borderRadius: BorderRadius.circular(16),
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
            ? TextButton.icon(
                onPressed: onUndo,
                icon: const Icon(Icons.undo_rounded, size: 18),
                label: const Text('撤销'),
              )
            : Icon(
                Icons.chevron_right_rounded,
                color: theme.colorScheme.onSurfaceVariant,
              ),
      ),
    );
  }
}
