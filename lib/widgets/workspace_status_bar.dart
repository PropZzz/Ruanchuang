import 'package:flutter/material.dart';

import 'glass_surface.dart';

class WorkspaceStatusBar extends StatelessWidget {
  const WorkspaceStatusBar({
    super.key,
    required this.brand,
    required this.title,
    this.compact = false,
    this.onSettings,
  });

  final String brand;
  final String title;
  final bool compact;
  final VoidCallback? onSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final date = MaterialLocalizations.of(context).formatMediumDate(
      DateTime.now(),
    );
    final horizontal = compact ? 12.0 : 24.0;

    return GlassSurface(
      key: const ValueKey('workspace-status-bar'),
      margin: EdgeInsets.fromLTRB(horizontal, compact ? 10 : 18, horizontal, 4),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 12 : 16,
        vertical: compact ? 8 : 12,
      ),
      borderRadius: BorderRadius.circular(compact ? 14 : 16),
      opacity: theme.brightness == Brightness.dark ? 0.62 : 0.72,
      child: Row(
        children: [
          Container(
            width: compact ? 8 : 10,
            height: compact ? 8 : 10,
            decoration: BoxDecoration(
              color: theme.colorScheme.tertiary,
              shape: BoxShape.circle,
            ),
          ),
          SizedBox(width: compact ? 10 : 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  compact ? title : brand,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (!compact)
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          if (!compact) ...[
            Icon(Icons.cloud_done_outlined, size: 17, color: theme.colorScheme.tertiary),
            const SizedBox(width: 6),
            Text(
              date,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (onSettings != null)
            IconButton(
              tooltip: '打开设置',
              icon: const Icon(Icons.tune_rounded),
              onPressed: onSettings,
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            ),
        ],
      ),
    );
  }
}
