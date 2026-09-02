import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/app_strings.dart';
import 'glass_surface.dart';

/// Shared title bar for desktop and mobile workspaces.
class WorkspaceStatusBar extends StatelessWidget {
  const WorkspaceStatusBar({
    super.key,
    required this.brand,
    required this.title,
    this.compact = false,
    this.onSettings,
    this.onSearch,
  });

  final String brand;
  final String title;
  final bool compact;
  final VoidCallback? onSettings;
  final VoidCallback? onSearch;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = theme.colorScheme.onSurfaceVariant;
    final date = MaterialLocalizations.of(
      context,
    ).formatMediumDate(DateTime.now());

    return GlassSurface(
      key: const ValueKey('workspace-status-bar'),
      level: AppMaterialLevel.chrome,
      borderRadius: BorderRadius.zero,
      padding: EdgeInsets.fromLTRB(
        compact ? 20 : 28,
        compact ? 14 : 18,
        compact ? 16 : 28,
        compact ? 12 : 16,
      ),
      showShadow: false,
      child: Row(
        children: [
          if (compact) ...[
            Expanded(
              child: Text(
                AppStrings.of(context, 'workspace_my_schedule'),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Icon(
              Icons.cloud_done_outlined,
              size: 17,
              color: theme.colorScheme.tertiary,
            ),
            const SizedBox(width: 6),
            Text(
              AppStrings.of(context, 'workspace_synced'),
              style: theme.textTheme.labelMedium?.copyWith(color: secondary),
            ),
          ] else ...[
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.schedule_rounded,
                size: 17,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              brand,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 20),
            Container(width: 1, height: 22, color: theme.colorScheme.outline),
            const SizedBox(width: 20),
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(color: secondary),
            ),
            const Spacer(),
            Icon(
              Icons.cloud_done_outlined,
              size: 17,
              color: theme.colorScheme.tertiary,
            ),
            const SizedBox(width: 6),
            Text(
              AppStrings.of(context, 'workspace_local_ready'),
              style: theme.textTheme.labelMedium?.copyWith(color: secondary),
            ),
            const SizedBox(width: 20),
            Text(
              date,
              style: theme.textTheme.labelMedium?.copyWith(color: secondary),
            ),
            const SizedBox(width: 8),
            if (onSearch != null)
              Tooltip(
                message: AppStrings.of(context, 'workspace_search'),
                child: IconButton(
                  tooltip: AppStrings.of(context, 'workspace_search'),
                  constraints: const BoxConstraints(
                    minWidth: 44,
                    minHeight: 44,
                  ),
                  onPressed: onSearch,
                  icon: const Icon(Icons.search_rounded),
                ),
              ),
          ],
          if (onSettings != null && !compact)
            Tooltip(
              message: AppStrings.of(context, 'workspace_settings'),
              child: IconButton(
                tooltip: AppStrings.of(context, 'workspace_settings'),
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                onPressed: onSettings,
                icon: Icon(
                  compact ? Icons.tune_rounded : Icons.account_circle_outlined,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
