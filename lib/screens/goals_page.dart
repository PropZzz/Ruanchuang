// lib/screens/goals_page.dart
import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/app_services.dart';
import '../services/goals/goal_dependency_helper.dart';
import '../theme/app_theme.dart';
import '../utils/app_strings.dart';
import '../utils/schedule_occurrence.dart';
import '../widgets/responsive_page_frame.dart';

double _heightFromMinutes(int minutes) => (minutes / 60.0) * 80.0;

class GoalsPage extends StatefulWidget {
  const GoalsPage({super.key});

  @override
  State<GoalsPage> createState() => _GoalsPageState();
}

class _GoalsPageState extends State<GoalsPage> {
  final _data = AppServices.dataService;

  bool _loading = true;
  Object? _loadError;
  List<Goal> _goals = const [];
  String? _selectedGoalId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }
    try {
      final goals = await _data.getGoals();
      if (!mounted) return;
      setState(() {
        _goals = goals;
        _selectedGoalId = goals.any((goal) => goal.id == _selectedGoalId)
            ? _selectedGoalId
            : MediaQuery.sizeOf(context).width >= 1280 && goals.isNotEmpty
            ? goals.first.id
            : null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error;
        _loading = false;
      });
    }
  }

  List<GoalTask> _generateTasks(String goalTitle) {
    final ts = DateTime.now().microsecondsSinceEpoch;
    return [
      GoalTask(
        id: 'gt_${ts}_1',
        title: '$goalTitle - 范围梳理',
        durationMinutes: 45,
        load: CognitiveLoad.medium,
        tag: 'Goal',
      ),
      GoalTask(
        id: 'gt_${ts}_2',
        title: '$goalTitle - 资料调研',
        durationMinutes: 60,
        load: CognitiveLoad.high,
        tag: 'Goal',
        dependsOn: ['gt_${ts}_1'],
      ),
      GoalTask(
        id: 'gt_${ts}_3',
        title: '$goalTitle - 初稿产出',
        durationMinutes: 90,
        load: CognitiveLoad.high,
        tag: 'Goal',
        dependsOn: ['gt_${ts}_2'],
      ),
      GoalTask(
        id: 'gt_${ts}_4',
        title: '$goalTitle - 审阅修改',
        durationMinutes: 60,
        load: CognitiveLoad.medium,
        tag: 'Goal',
        dependsOn: ['gt_${ts}_3'],
      ),
      GoalTask(
        id: 'gt_${ts}_5',
        title: '$goalTitle - 最终交付',
        durationMinutes: 30,
        load: CognitiveLoad.low,
        tag: 'Goal',
        dependsOn: ['gt_${ts}_4'],
      ),
    ];
  }

  Future<void> _addGoal() async {
    final narrow = MediaQuery.sizeOf(context).width < 720;
    final draft = narrow
        ? await showModalBottomSheet<_GoalDraft>(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            showDragHandle: true,
            builder: (ctx) => FractionallySizedBox(
              key: const ValueKey('goal-add-form'),
              heightFactor: 0.88,
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.viewInsetsOf(ctx).bottom,
                ),
                child: _GoalEditorForm(
                  onCancel: () => Navigator.of(ctx).pop(),
                  onSave: (draft) => Navigator.of(ctx).pop(draft),
                ),
              ),
            ),
          )
        : await showDialog<_GoalDraft>(
            context: context,
            builder: (ctx) => Dialog(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: _GoalEditorForm(
                  onCancel: () => Navigator.of(ctx).pop(),
                  onSave: (draft) => Navigator.of(ctx).pop(draft),
                ),
              ),
            ),
          );
    if (draft == null) return;

    final goal = Goal(
      id: '',
      title: draft.title,
      due: DateTime(draft.due.year, draft.due.month, draft.due.day, 23, 59),
      priority: draft.priority,
      tasks: _generateTasks(draft.title),
    );

    try {
      await _data.upsertGoal(goal);
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('目标未能保存，请重试。')));
    }
  }

  Future<void> _deleteGoal(Goal g) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppStrings.of(ctx, 'goal_delete_title')),
        content: Text(
          '${AppStrings.of(ctx, 'dialog_del_content')} "${g.title}"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(AppStrings.of(ctx, 'btn_cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(AppStrings.of(ctx, 'btn_delete')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _data.deleteGoal(g.id);
    await _load();
  }

  Future<void> _toggleTask(Goal g, GoalTask t) async {
    if (!t.done && !GoalDependencyHelper.isReady(t, g.tasks)) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先完成前置任务。')));
      return;
    }
    final tasks = g.tasks
        .map((x) => x.id == t.id ? x.copyWith(done: !x.done) : x)
        .toList();
    try {
      await _data.upsertGoal(
        Goal(
          id: g.id,
          title: g.title,
          due: g.due,
          priority: g.priority,
          tasks: tasks,
        ),
      );
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('任务状态未能保存。')));
    }
  }

  List<TimeWindow> _defaultWindows() {
    return const [
      TimeWindow(
        start: TimeOfDay(hour: 9, minute: 0),
        end: TimeOfDay(hour: 12, minute: 0),
      ),
      TimeWindow(
        start: TimeOfDay(hour: 13, minute: 30),
        end: TimeOfDay(hour: 18, minute: 30),
      ),
    ];
  }

  Future<void> _scheduleNext(Goal g) async {
    final next = GoalDependencyHelper.firstReady(g.tasks);
    if (next == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            g.tasks.every((t) => t.done)
                ? AppStrings.of(context, 'goal_all_done')
                : '剩余任务都被依赖关系阻塞了。',
          ),
        ),
      );
      return;
    }

    final day = DateTime.now();
    final d = dateOnly(day);
    final schedule = entriesForDay(
      day: d,
      allEntries: await _data.getScheduleEntries(),
    );

    TimeOfDay? pickStart() {
      final windows = _defaultWindows();
      final blocks = List<ScheduleEntry>.from(schedule)
        ..sort(
          (a, b) => (a.time.hour * 60 + a.time.minute).compareTo(
            b.time.hour * 60 + b.time.minute,
          ),
        );

      for (final w in windows) {
        var cursor = w.start.hour * 60 + w.start.minute;
        final wEnd = w.end.hour * 60 + w.end.minute;

        for (final b in blocks) {
          final bStart = b.time.hour * 60 + b.time.minute;
          final bDur = ((b.height / 80.0) * 60.0).round();
          final bEnd = bStart + bDur;

          if (bEnd <= cursor) continue;
          if (bStart >= wEnd) break;

          final gap = (bStart - cursor).clamp(0, 24 * 60);
          if (gap >= next.durationMinutes &&
              cursor + next.durationMinutes <= wEnd) {
            return TimeOfDay(hour: cursor ~/ 60, minute: cursor % 60);
          }
          cursor = bEnd.clamp(cursor, wEnd);
        }

        if (wEnd - cursor >= next.durationMinutes) {
          return TimeOfDay(hour: cursor ~/ 60, minute: cursor % 60);
        }
      }
      return null;
    }

    final start = pickStart();
    if (start == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.of(context, 'goal_no_slot'))),
      );
      return;
    }

    final entry = ScheduleEntry(
      id: 'goal_${g.id}_${next.id}',
      day: d,
      title: next.title,
      tag: 'Goal',
      load: next.load,
      goalId: g.id,
      goalTaskId: next.id,
      height: _heightFromMinutes(next.durationMinutes),
      color: Theme.of(context).colorScheme.primary,
      time: start,
      reminderMinutesBefore: 10,
    );

    await _data.addScheduleEntry(entry);
    await AppServices.reminderService.rescheduleDay(
      day: d,
      entries: entriesForDay(
        day: d,
        allEntries: await _data.getScheduleEntries(),
      ),
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${AppStrings.of(context, 'goal_scheduled')}: ${start.format(context)}',
        ),
      ),
    );
  }

  void _openGoalDetail(Goal g) {
    if (MediaQuery.sizeOf(context).width >= 1280) {
      setState(() => _selectedGoalId = g.id);
      return;
    }

    var detailGoal = g;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => FractionallySizedBox(
          heightFactor: 0.92,
          child: DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.9,
            minChildSize: 0.55,
            builder: (ctx2, controller) => _buildGoalDetailList(
              ctx2,
              detailGoal,
              controller: controller,
              detailKey: const ValueKey('goal-detail-sheet'),
              onClose: () => Navigator.of(sheetContext).pop(),
              onDelete: () async {
                Navigator.of(sheetContext).pop();
                await _deleteGoal(detailGoal);
              },
              onToggleTask: (task) async {
                await _toggleTask(detailGoal, task);
                if (!mounted) return;
                final updated = _goals.firstWhere(
                  (goal) => goal.id == detailGoal.id,
                  orElse: () => detailGoal,
                );
                setSheetState(() => detailGoal = updated);
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGoalDetailList(
    BuildContext context,
    Goal goal, {
    ScrollController? controller,
    Key? detailKey,
    VoidCallback? onClose,
    required Future<void> Function() onDelete,
    required Future<void> Function(GoalTask task) onToggleTask,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final complete = goal.tasks.every((task) => task.done);

    return Container(
      key: detailKey,
      color: scheme.surface,
      child: ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '目标详情',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (onClose != null)
                IconButton(
                  tooltip: AppStrings.of(context, 'btn_close'),
                  onPressed: onClose,
                  icon: const Icon(Icons.close),
                ),
              IconButton(
                key: const ValueKey('goal-detail-delete'),
                tooltip: AppStrings.of(context, 'btn_delete'),
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          Text(
            goal.title,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _GoalStatusTag(
                label: complete ? '已完成' : '进行中',
                color: complete ? scheme.tertiary : scheme.primary,
              ),
              _GoalStatusTag(label: 'P${goal.priority}', color: scheme.error),
              _GoalStatusTag(
                label:
                    '${AppStrings.of(context, 'goal_due')} ${_formatDate(goal.due)}',
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: LinearProgressIndicator(
                  value: goal.progress,
                  minHeight: 6,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${(goal.progress * 100).round()}%',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            key: const ValueKey('goal-schedule-next'),
            onPressed: complete ? null : () => _scheduleNext(goal),
            icon: const Icon(Icons.event_available_outlined),
            label: Text(AppStrings.of(context, 'goal_schedule_next')),
          ),
          const SizedBox(height: 24),
          Text(
            AppStrings.of(context, 'goal_tasks'),
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          for (final task in goal.tasks) ...[
            _GoalTaskRow(
              task: task,
              subtitle: _taskSubtitle(task, goal.tasks),
              blocked:
                  !task.done && !GoalDependencyHelper.isReady(task, goal.tasks),
              onChanged: () => onToggleTask(task),
            ),
            Divider(height: 1, color: scheme.outlineVariant),
          ],
        ],
      ),
    );
  }

  String _taskSubtitle(GoalTask task, List<GoalTask> all) {
    final load = switch (task.load) {
      CognitiveLoad.low => '低负荷',
      CognitiveLoad.medium => '中负荷',
      CognitiveLoad.high => '高负荷',
    };
    final base = '${task.durationMinutes} 分钟 · $load';
    if (task.done) return '$base · 已完成';
    final blockedBy = GoalDependencyHelper.blockedByTitles(task, all);
    if (blockedBy.isEmpty) return '$base · 可安排';
    return '$base · 依赖：${blockedBy.join('、')}';
  }

  String _formatDate(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  int get _goalTaskCount =>
      _goals.fold<int>(0, (sum, g) => sum + g.tasks.length);

  int get _doneTaskCount => _goals.fold<int>(
    0,
    (sum, g) => sum + g.tasks.where((t) => t.done).length,
  );

  @override
  Widget build(BuildContext context) {
    final doneRate = _goalTaskCount == 0
        ? 0.0
        : _doneTaskCount / _goalTaskCount;
    final showAddLabel = MediaQuery.sizeOf(context).width >= 520;

    return Scaffold(
      backgroundColor: AppWindowTones.canvas(context, AppWindowTone.neutral),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(AppStrings.of(context, 'goal_title')),
            Text(
              'GOALS & MILESTONES',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          if (showAddLabel)
            FilledButton.icon(
              key: const ValueKey('goals-add-action'),
              onPressed: _loading ? null : _addGoal,
              icon: const Icon(Icons.add),
              label: Text(AppStrings.of(context, 'goal_add')),
            )
          else
            IconButton(
              key: const ValueKey('goals-add-action'),
              tooltip: AppStrings.of(context, 'goal_add'),
              onPressed: _loading ? null : _addGoal,
              icon: const Icon(Icons.add),
            ),
          IconButton(
            key: const ValueKey('goals-refresh-action'),
            tooltip: AppStrings.of(context, 'calendar_refresh'),
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: ResponsivePageFrame(
          maxWidth: 1320,
          child: _loading
              ? const _GoalsLoadingState()
              : _loadError != null
              ? _GoalsLoadFailure(onRetry: _load)
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final selectedGoal = _goals
                        .where((goal) => goal.id == _selectedGoalId)
                        .firstOrNull;
                    final showDetail =
                        constraints.maxWidth >= 1020 && selectedGoal != null;
                    final bottomPadding =
                        MediaQuery.paddingOf(context).bottom +
                        (constraints.maxWidth < 720 ? 100 : 28);

                    final goalContent = ListView(
                      padding: EdgeInsets.fromLTRB(16, 16, 16, bottomPadding),
                      children: [
                        _GoalsOverviewCard(
                          key: const ValueKey('goals-overview'),
                          goalCount: _goals.length,
                          doneTaskCount: _doneTaskCount,
                          allTaskCount: _goalTaskCount,
                          dueSoonCount: _dueSoonGoalCount,
                          doneRate: doneRate,
                        ),
                        const SizedBox(height: 12),
                        _buildFocusBanner(context),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '目标执行分解',
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                            ),
                            Text(
                              '${_goals.length} 个目标',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        if (_goals.isEmpty)
                          _GoalsEmptyState(onAdd: _addGoal)
                        else
                          for (final goal in _sortedGoals()) ...[
                            _GoalSummaryCard(
                              key: ValueKey('goal-card-${goal.id}'),
                              goal: goal,
                              selected:
                                  showDetail && goal.id == _selectedGoalId,
                              dueLabel: AppStrings.of(context, 'goal_due'),
                              onTap: () => _openGoalDetail(goal),
                            ),
                            const SizedBox(height: 10),
                          ],
                      ],
                    );

                    if (!showDetail) return goalContent;

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: goalContent),
                        const SizedBox(width: 14),
                        SizedBox(
                          width: 344,
                          child: Padding(
                            padding: const EdgeInsets.only(top: 16, right: 16),
                            child: _buildGoalDetailList(
                              context,
                              selectedGoal,
                              detailKey: const ValueKey('goal-detail-panel'),
                              onClose: () =>
                                  setState(() => _selectedGoalId = null),
                              onDelete: () => _deleteGoal(selectedGoal),
                              onToggleTask: (task) =>
                                  _toggleTask(selectedGoal, task),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
        ),
      ),
    );
  }

  List<Goal> _sortedGoals() => List<Goal>.from(_goals)
    ..sort((a, b) {
      final aComplete = a.progress >= 1;
      final bComplete = b.progress >= 1;
      if (aComplete != bComplete) return aComplete ? 1 : -1;
      final priority = a.priority.compareTo(b.priority);
      if (priority != 0) return priority;
      return a.due.compareTo(b.due);
    });

  int get _dueSoonGoalCount {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final end = today.add(const Duration(days: 7));
    return _goals
        .where(
          (goal) =>
              goal.progress < 1 &&
              !goal.due.isBefore(today) &&
              goal.due.isBefore(end),
        )
        .length;
  }

  Goal? _nextReadyGoal() {
    for (final goal in _goals) {
      if (GoalDependencyHelper.firstReady(goal.tasks) != null) return goal;
    }
    return null;
  }

  Widget _buildFocusBanner(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final nextGoal = _nextReadyGoal();
    return Container(
      key: const ValueKey('goals-focus-banner'),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
      decoration: BoxDecoration(
        color: scheme.primary,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.route_outlined, color: scheme.onPrimary, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '保持目标推进',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: scheme.onPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '$_doneTaskCount / $_goalTaskCount 项拆解任务已完成',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onPrimary.withValues(alpha: 0.78),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.tonalIcon(
            key: const ValueKey('goals-schedule-next-action'),
            onPressed: nextGoal == null ? null : () => _scheduleNext(nextGoal),
            icon: const Icon(Icons.calendar_month_outlined),
            label: Text(AppStrings.of(context, 'goal_schedule_next')),
          ),
        ],
      ),
    );
  }
}

class _GoalsOverviewCard extends StatelessWidget {
  const _GoalsOverviewCard({
    super.key,
    required this.goalCount,
    required this.doneTaskCount,
    required this.allTaskCount,
    required this.dueSoonCount,
    required this.doneRate,
  });

  final int goalCount;
  final int doneTaskCount;
  final int allTaskCount;
  final int dueSoonCount;
  final double doneRate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppWindowTones.surface(context, AppWindowTone.schedule),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '目标概览',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '${(doneRate * 100).round()}% 完成',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth < 460 ? 2 : 3;
              final width =
                  (constraints.maxWidth - 16 * (columns - 1)) / columns;
              return Wrap(
                spacing: 16,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: width,
                    child: _MetricTile(
                      icon: Icons.flag_outlined,
                      label: '目标数量',
                      value: goalCount.toString(),
                    ),
                  ),
                  SizedBox(
                    key: const ValueKey('goals-done-count'),
                    width: width,
                    child: _MetricTile(
                      icon: Icons.task_alt_outlined,
                      label: '已完成任务',
                      value: '$doneTaskCount/$allTaskCount',
                    ),
                  ),
                  SizedBox(
                    key: const ValueKey('goals-upcoming-count'),
                    width: width,
                    child: _MetricTile(
                      icon: Icons.event_busy_outlined,
                      label: '临近截止',
                      value: dueSoonCount.toString(),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          LinearProgressIndicator(
            value: doneRate,
            minHeight: 5,
            borderRadius: BorderRadius.circular(4),
          ),
        ],
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _MetricTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GoalsLoadingState extends StatelessWidget {
  const _GoalsLoadingState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('正在加载目标...'),
          ],
        ),
      ),
    );
  }
}

class _GoalsEmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _GoalsEmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(
              Icons.flag_outlined,
              size: 40,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 10),
            Text(
              AppStrings.of(context, 'goal_empty'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: Text(AppStrings.of(context, 'goal_add')),
            ),
          ],
        ),
      ),
    );
  }
}

class _GoalSummaryCard extends StatelessWidget {
  const _GoalSummaryCard({
    super.key,
    required this.goal,
    required this.onTap,
    required this.dueLabel,
    this.selected = false,
  });

  final Goal goal;
  final VoidCallback onTap;
  final String dueLabel;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final nextTask = GoalDependencyHelper.firstReady(goal.tasks);
    return LayoutBuilder(
      builder: (context, constraints) => Material(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected ? scheme.primary : scheme.outlineVariant,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        goal.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    _GoalStatusTag(
                      label: 'P${goal.priority}',
                      color: scheme.error,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(
                      Icons.event_outlined,
                      size: 16,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '$dueLabel · ${_dateLabel(goal.due)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Text(
                      '${(goal.progress * 100).round()}%',
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: goal.progress,
                  minHeight: 5,
                  borderRadius: BorderRadius.circular(4),
                ),
                const SizedBox(height: 13),
                if (constraints.maxWidth >= 620)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final task in goal.tasks) _GoalTaskStep(task: task),
                    ],
                  )
                else
                  Row(
                    children: [
                      Icon(
                        Icons.account_tree_outlined,
                        size: 16,
                        color: scheme.primary,
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          nextTask == null
                              ? '全部拆解任务已完成'
                              : '下一步：${nextTask.title}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      Text(
                        '${goal.tasks.where((task) => task.done).length}/${goal.tasks.length} 项',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _dateLabel(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

class _GoalTaskStep extends StatelessWidget {
  const _GoalTaskStep({required this.task});

  final GoalTask task;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = task.done ? scheme.tertiary : scheme.primary;
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 132, maxWidth: 190),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: task.done
              ? scheme.tertiaryContainer
              : scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(
              task.done ? Icons.check_circle : Icons.circle_outlined,
              size: 16,
              color: color,
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                task.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GoalStatusTag extends StatelessWidget {
  const _GoalStatusTag({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _GoalTaskRow extends StatelessWidget {
  const _GoalTaskRow({
    required this.task,
    required this.subtitle,
    required this.blocked,
    required this.onChanged,
  });

  final GoalTask task;
  final String subtitle;
  final bool blocked;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Checkbox(
            value: task.done,
            onChanged: blocked ? null : (_) => onChanged(),
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: 5),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: blocked ? scheme.onSurfaceVariant : scheme.onSurface,
                    decoration: task.done ? TextDecoration.lineThrough : null,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Icon(
            blocked
                ? Icons.lock_outline
                : task.done
                ? Icons.check_circle_outline
                : Icons.drag_handle,
            size: 18,
            color: scheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}

class _GoalDraft {
  const _GoalDraft({
    required this.title,
    required this.due,
    required this.priority,
  });

  final String title;
  final DateTime due;
  final int priority;
}

class _GoalEditorForm extends StatefulWidget {
  const _GoalEditorForm({required this.onCancel, required this.onSave});

  final VoidCallback onCancel;
  final ValueChanged<_GoalDraft> onSave;

  @override
  State<_GoalEditorForm> createState() => _GoalEditorFormState();
}

class _GoalEditorFormState extends State<_GoalEditorForm> {
  final _titleController = TextEditingController();
  DateTime _due = DateTime.now().add(const Duration(days: 7));
  int _priority = 3;
  String? _error;

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
      initialDate: _due,
    );
    if (picked != null) setState(() => _due = picked);
  }

  void _submit() {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      setState(() => _error = '请输入目标名称');
      return;
    }
    widget.onSave(_GoalDraft(title: title, due: _due, priority: _priority));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppStrings.of(context, 'goal_add_title'),
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 18),
          TextField(
            key: const ValueKey('goal-add-title-input'),
            controller: _titleController,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: AppStrings.of(context, 'label_title'),
              errorText: _error,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppStrings.of(context, 'goal_due'),
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(_dateLabel(_due)),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.calendar_today_outlined, size: 18),
                label: Text(AppStrings.of(context, 'goal_pick_date')),
              ),
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            initialValue: _priority,
            decoration: InputDecoration(
              labelText: AppStrings.of(context, 'goal_priority'),
            ),
            items: [
              for (var priority = 1; priority <= 5; priority++)
                DropdownMenuItem(value: priority, child: Text('P$priority')),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _priority = value);
            },
          ),
          const SizedBox(height: 12),
          Text(
            AppStrings.of(context, 'goal_hint'),
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: widget.onCancel,
                child: Text(AppStrings.of(context, 'btn_cancel')),
              ),
              const SizedBox(width: 8),
              FilledButton(
                key: const ValueKey('goal-add-submit'),
                onPressed: _submit,
                child: Text(AppStrings.of(context, 'btn_add')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GoalsLoadFailure extends StatelessWidget {
  const _GoalsLoadFailure({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined, color: scheme.error, size: 32),
            const SizedBox(height: 10),
            const Text('暂时无法加载目标'),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const ValueKey('goals-load-retry'),
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: Text(AppStrings.of(context, 'common_retry')),
            ),
          ],
        ),
      ),
    );
  }
}
