import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/scheduling/schedule_rescue.dart';
import '../ui/app_theme.dart';
import 'workbench_surface.dart';

/// 日程救援三方案比较面板。
///
/// 桌面宽度（>= [AppTheme.comparisonBreakpoint]）三列并列，窄屏纵向堆叠。
/// 每个方案固定展示理由、代价、移动任务数、恢复缓冲、受影响任务与问题数；
/// 推荐方案仅以徽章突出，须先「选择此方案」再点「采用此方案」显式确认，
/// 不会自动采用。确认通过 [onSelect] 回调，取消通过 [onCancel]。
class RescuePlanComparison extends StatefulWidget {
  const RescuePlanComparison({
    super.key,
    required this.options,
    required this.onSelect,
    required this.onCancel,
    this.baseline = const [],
    this.title = '选择日程救援方案',
    this.cancelLabel = '暂不调整',
  });

  final List<ScheduleRescueOption> options;
  final ValueChanged<ScheduleRescueOption> onSelect;
  final VoidCallback onCancel;

  /// 重排前的日程，用于推导每个方案移动了哪些任务。
  final List<ScheduleEntry> baseline;

  final String title;
  final String cancelLabel;

  @override
  State<RescuePlanComparison> createState() => _RescuePlanComparisonState();
}

class _RescuePlanComparisonState extends State<RescuePlanComparison> {
  int? _selectedIndex;

  int get _recommendedIndex {
    var best = 0;
    var bestScore = 1 << 30;
    for (var i = 0; i < widget.options.length; i++) {
      final option = widget.options[i];
      final score = option.plan.issues.length * 1000 + option.movedEntryCount;
      if (score < bestScore) {
        bestScore = score;
        best = i;
      }
    }
    return best;
  }

  List<String> _affectedTitles(ScheduleRescueOption option) {
    final titles = <String>[];
    final byId = <String, ScheduleEntry>{
      for (final entry in option.plan.entries)
        if (entry.id != null && entry.id!.isNotEmpty) entry.id!: entry,
    };
    for (final entry in widget.baseline) {
      final id = entry.id;
      if (id == null || id.isEmpty) continue;
      final next = byId[id];
      if (next == null ||
          next.time != entry.time ||
          (next.height - entry.height).abs() > 0.1) {
        titles.add(entry.title);
      }
    }
    for (final entry in option.plan.entries) {
      final id = entry.id;
      if (id != null && id.startsWith('urgent_') && !titles.contains(entry.title)) {
        titles.add(entry.title);
      }
    }
    return titles;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Dialog.fullscreen(
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.title, style: theme.textTheme.headlineMedium),
              const SizedBox(height: 4),
              Text(
                '比较三个方案的影响后，显式选择一个并确认采用。',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide =
                        constraints.maxWidth >= AppTheme.comparisonBreakpoint;
                    if (isWide) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (var i = 0; i < widget.options.length; i++) ...[
                            if (i > 0) const SizedBox(width: 16),
                            Expanded(
                              child: SingleChildScrollView(
                                child: _buildOptionCard(
                                  context,
                                  widget.options[i],
                                  index: i,
                                ),
                              ),
                            ),
                          ],
                        ],
                      );
                    }
                    return ListView.separated(
                      itemCount: widget.options.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 16),
                      itemBuilder: (context, i) => _buildOptionCard(
                        context,
                        widget.options[i],
                        index: i,
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: widget.onCancel,
                  child: Text(
                    widget.cancelLabel,
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOptionCard(
    BuildContext context,
    ScheduleRescueOption option, {
    required int index,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isSelected = _selectedIndex == index;
    final isRecommended = _recommendedIndex == index;
    final issues = option.plan.issues;
    final affected = _affectedTitles(option);

    final borderColor = isSelected
        ? scheme.secondary
        : isRecommended
        ? scheme.secondary.withValues(alpha: 0.5)
        : scheme.outline;

    final icon = switch (option.strategy) {
      RescueStrategy.protectDeadline => Icons.flag_outlined,
      RescueStrategy.protectRecovery => Icons.self_improvement_outlined,
      RescueStrategy.minimizeChanges => Icons.tune_outlined,
    };

    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => setState(() => _selectedIndex = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: borderColor,
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(icon, size: 20, color: scheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      option.title,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  if (isRecommended)
                    const WorkbenchStatusBadge(
                      status: WorkbenchStatus.success,
                      label: '推荐',
                      tooltip: '根据问题数与移动任务数评估，仅供参考，不会自动采用',
                    ),
                ],
              ),
              const SizedBox(height: 12),
              _InfoBlock(label: '理由', text: option.rationale),
              const SizedBox(height: 8),
              _InfoBlock(label: '代价', text: option.tradeoff),
              const SizedBox(height: 12),
              WorkbenchMetric(
                label: '移动任务数',
                value: '${option.movedEntryCount} 项',
              ),
              const SizedBox(height: 8),
              WorkbenchMetric(
                label: '恢复缓冲',
                value: option.recoveryMinutes > 0
                    ? '${option.recoveryMinutes} 分钟'
                    : '无',
              ),
              const SizedBox(height: 8),
              WorkbenchMetric(
                label: '问题数',
                value: '${issues.length} 项',
                status: issues.isEmpty
                    ? WorkbenchStatus.success
                    : WorkbenchStatus.risk,
                supportingText: issues.isEmpty ? '无遗留问题' : '仍有任务无法妥善安排',
              ),
              const SizedBox(height: 12),
              Text(
                '受影响任务',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              if (affected.isEmpty)
                Text('无原有日程被移动', style: theme.textTheme.bodyMedium)
              else ...[
                for (final title in affected.take(3))
                  Text('· $title', style: theme.textTheme.bodyMedium),
                if (affected.length > 3)
                  Text(
                    '等 ${affected.length} 项',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: isSelected
                    ? FilledButton.icon(
                        onPressed: () => widget.onSelect(option),
                        icon: const Icon(Icons.check, size: 18),
                        label: const Text('采用此方案'),
                      )
                    : OutlinedButton(
                        onPressed: () =>
                            setState(() => _selectedIndex = index),
                        child: const Text('选择此方案'),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoBlock extends StatelessWidget {
  const _InfoBlock({required this.label, required this.text});

  final String label;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
        Text(text, style: theme.textTheme.bodyMedium),
      ],
    );
  }
}
