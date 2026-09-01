import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'glass_surface.dart';

/// 工作台状态语义：映射到 AppTheme 语义色槽位。
///
/// success/warning use dedicated semantic text colors; risk -> colorScheme.error,
/// neutral -> colorScheme.onSurfaceVariant.
enum WorkbenchStatus { neutral, success, warning, risk }

extension WorkbenchStatusStyle on WorkbenchStatus {
  Color colorOf(ColorScheme scheme) => switch (this) {
    WorkbenchStatus.neutral => scheme.onSurfaceVariant,
    WorkbenchStatus.success =>
      scheme.brightness == Brightness.dark
          ? AppThemeTokens.successDark
          : AppThemeTokens.successLight,
    WorkbenchStatus.warning =>
      scheme.brightness == Brightness.dark
          ? AppThemeTokens.warningDark
          : AppThemeTokens.warningLight,
    WorkbenchStatus.risk => scheme.error,
  };

  IconData get icon => switch (this) {
    WorkbenchStatus.neutral => Icons.info_outline,
    WorkbenchStatus.success => Icons.check_circle_outline,
    WorkbenchStatus.warning => Icons.warning_amber_rounded,
    WorkbenchStatus.risk => Icons.error_outline,
  };
}

/// 带 1px 低对比度边框与 8px 圆角的通用表面容器，可选节标题。
///
/// 纯展示组件：数据与回调全部通过构造参数传入。
class WorkbenchSurface extends StatelessWidget {
  const WorkbenchSurface({
    super.key,
    this.title,
    this.trailing,
    this.padding = const EdgeInsets.all(16),
    this.materialLevel = AppMaterialLevel.surface,
    required this.child,
  });

  final String? title;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;
  final AppMaterialLevel materialLevel;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final content = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: materialLevel == AppMaterialLevel.surface
            ? scheme.surface
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: materialLevel == AppMaterialLevel.surface
            ? Border.all(color: scheme.outline)
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title != null) ...[
            WorkbenchSectionHeader(title: title!, trailing: trailing),
            const SizedBox(height: 8),
          ],
          child,
        ],
      ),
    );
    if (materialLevel == AppMaterialLevel.surface) return content;
    return GlassSurface(
      level: materialLevel,
      padding: EdgeInsets.zero,
      borderRadius: BorderRadius.circular(12),
      showShadow: materialLevel == AppMaterialLevel.overlay,
      child: content,
    );
  }
}

/// 节标题行：标题 + 可选副标题 + 可选尾部操作。
class WorkbenchSectionHeader extends StatelessWidget {
  const WorkbenchSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: theme.textTheme.titleMedium),
              if (subtitle != null)
                Text(
                  subtitle!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

/// 决策指标：标签 + 数值 + 可选辅助说明，辅助说明按状态着色。
class WorkbenchMetric extends StatelessWidget {
  const WorkbenchMetric({
    super.key,
    required this.label,
    required this.value,
    this.supportingText,
    this.status = WorkbenchStatus.neutral,
    this.tooltip,
  });

  final String label;
  final String value;
  final String? supportingText;
  final WorkbenchStatus status;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Text(value, style: theme.textTheme.headlineMedium),
        if (supportingText != null) ...[
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (status != WorkbenchStatus.neutral) ...[
                Icon(status.icon, size: 14, color: status.colorOf(scheme)),
                const SizedBox(width: 4),
              ],
              Flexible(
                child: Text(
                  supportingText!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: status == WorkbenchStatus.neutral
                        ? scheme.onSurfaceVariant
                        : status.colorOf(scheme),
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
    if (tooltip == null) return content;
    return Tooltip(message: tooltip!, child: content);
  }
}

/// 空状态：图标 + 标题 + 说明 + 可选操作按钮。
class WorkbenchEmptyState extends StatelessWidget {
  const WorkbenchEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.actionTooltip,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final String? actionTooltip;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: scheme.onSurfaceVariant),
            const SizedBox(height: 8),
            Text(title, style: theme.textTheme.titleMedium),
            if (message != null) ...[
              const SizedBox(height: 4),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
            ],
            if (actionLabel != null) ...[
              const SizedBox(height: 16),
              Tooltip(
                message: actionTooltip ?? actionLabel!,
                child: OutlinedButton.icon(
                  onPressed: onAction,
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(actionLabel!),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Inline status feedback that keeps the surrounding workbench visible.
class WorkbenchStatusBanner extends StatelessWidget {
  const WorkbenchStatusBanner({
    super.key,
    required this.message,
    required this.actionLabel,
    required this.onAction,
    this.status = WorkbenchStatus.risk,
    this.actionKey,
  });

  final String message;
  final String actionLabel;
  final VoidCallback onAction;
  final WorkbenchStatus status;
  final Key? actionKey;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = status.colorOf(scheme);
    return Semantics(
      container: true,
      liveRegion: true,
      child: Card(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        color: color.withValues(alpha: 0.08),
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          child: Row(
            children: [
              Icon(status.icon, size: 20, color: color),
              const SizedBox(width: 8),
              Expanded(child: Text(message)),
              TextButton.icon(
                key: actionKey,
                onPressed: onAction,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text(actionLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 状态标签：图标 + 文字 + 状态色，不只靠颜色表达语义。
class WorkbenchStatusBadge extends StatelessWidget {
  const WorkbenchStatusBadge({
    super.key,
    required this.status,
    required this.label,
    this.tooltip,
  });

  final WorkbenchStatus status;
  final String label;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = status.colorOf(scheme);
    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(status.icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
    if (tooltip == null) return badge;
    return Tooltip(message: tooltip!, child: badge);
  }
}
