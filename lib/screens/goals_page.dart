import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/app_services.dart';
import '../services/goals/goal_dependency_helper.dart';
import '../utils/app_strings.dart';
import '../utils/schedule_occurrence.dart';

double _heightFromMinutes(int minutes) => (minutes / 60.0) * 80.0;

class GoalsPage extends StatefulWidget {
  const GoalsPage({super.key});

  @override
  State<GoalsPage> createState() => _GoalsPageState();
}

class _GoalsPageState extends State<GoalsPage> {
  final _data = AppServices.dataService;

  bool _loading = true;
  List<Goal> _goals = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final goals = await _data.getGoals();
    if (!mounted) return;
    setState(() {
      _goals = goals;
      _loading = false;
    });
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
    final titleCtrl = TextEditingController();
    DateTime due = DateTime.now().add(const Duration(days: 7));
    int priority = 3;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setInner) => AlertDialog(
          title: Text(AppStrings.of(ctx2, 'goal_add_title')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleCtrl,
                decoration: InputDecoration(
                  labelText: AppStrings.of(ctx2, 'label_title'),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${AppStrings.of(ctx2, 'goal_due')}: ${due.toLocal()}'
                          .split(' ')[0],
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: ctx2,
                        firstDate: DateTime.now().subtract(
                          const Duration(days: 1),
                        ),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                        initialDate: due,
                      );
                      if (picked != null) setInner(() => due = picked);
                    },
                    child: Text(AppStrings.of(ctx2, 'goal_pick_date')),
                  ),
                ],
              ),
              Row(
                children: [
                  Text(AppStrings.of(ctx2, 'goal_priority')),
                  const SizedBox(width: 8),
                  DropdownButton<int>(
                    value: priority,
                    items: const [1, 2, 3, 4, 5]
                        .map(
                          (v) => DropdownMenuItem(value: v, child: Text('$v')),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setInner(() => priority = v);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                AppStrings.of(ctx2, 'goal_hint'),
                style: const TextStyle(color: Colors.grey),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx2).pop(false),
              child: Text(AppStrings.of(ctx2, 'btn_cancel')),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx2).pop(true),
              child: Text(AppStrings.of(ctx2, 'btn_add')),
            ),
          ],
        ),
      ),
    );

    if (ok != true) return;
    final title = titleCtrl.text.trim();
    if (title.isEmpty) return;

    final goal = Goal(
      id: '',
      title: title,
      due: DateTime(due.year, due.month, due.day, 23, 59),
      priority: priority,
      tasks: _generateTasks(title),
    );

    await _data.upsertGoal(goal);
    await _load();
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
    final tasks = g.tasks
        .map((x) => x.id == t.id ? x.copyWith(done: !x.done) : x)
        .toList();
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
    final d = DateTime(day.year, day.month, day.day);
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
      color: Colors.purple,
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
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.82,
        minChildSize: 0.55,
        builder: (ctx2, controller) {
          return Material(
            child: ListView(
              controller: controller,
              padding: const EdgeInsets.all(16),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        g.title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: AppStrings.of(context, 'btn_delete'),
                      onPressed: () async {
                        Navigator.of(ctx).pop();
                        await _deleteGoal(g);
                      },
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
                Text(
                  '${AppStrings.of(context, 'goal_due')}: ${g.due.toLocal()}'
                      .split(' ')[0],
                ),
                Text(
                  '${AppStrings.of(context, 'goal_priority')}: ${g.priority}',
                ),
                const SizedBox(height: 12),
                LinearProgressIndicator(value: g.progress),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: () => _scheduleNext(g),
                  icon: const Icon(Icons.calendar_month_outlined),
                  label: Text(AppStrings.of(context, 'goal_schedule_next')),
                ),
                const SizedBox(height: 12),
                Text(
                  AppStrings.of(context, 'goal_tasks'),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                ...g.tasks.map(
                  (t) => Card(
                    child: CheckboxListTile(
                      value: t.done,
                      onChanged: (_) => _toggleTask(g, t),
                      title: Text(t.title),
                      subtitle: Text(_taskSubtitle(t, g.tasks)),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  String _taskSubtitle(GoalTask task, List<GoalTask> all) {
    final base = '${task.durationMinutes} min | ${task.load.name}';
    if (task.done) return '$base | Done';
    final blockedBy = GoalDependencyHelper.blockedByTitles(task, all);
    if (blockedBy.isEmpty) return '$base | Ready';
    return '$base | Blocked by ${blockedBy.join(', ')}';
  }

  int get _goalTaskCount =>
      _goals.fold<int>(0, (sum, g) => sum + g.tasks.length);

  int get _doneTaskCount => _goals.fold<int>(
    0,
    (sum, g) => sum + g.tasks.where((t) => t.done).length,
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final doneRate = _goalTaskCount == 0
        ? 0.0
        : _doneTaskCount / _goalTaskCount;

    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.of(context, 'goal_title')),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              theme.colorScheme.tertiaryContainer.withValues(alpha: 0.22),
              theme.colorScheme.surface,
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1240),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: _loading
                    ? const _GoalsLoadingState()
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          final isWide = constraints.maxWidth >= 940;
                          return ListView(
                            // 修复：添加列表底部安全距，避免 FAB(悬浮窗) 永远挡住最后一张卡片
                            padding: EdgeInsets.only(
                              bottom: MediaQuery.of(context).padding.bottom + 100,
                            ),
                            children: [
                              _GoalsOverviewCard(
                                goalCount: _goals.length,
                                doneTaskCount: _doneTaskCount,
                                allTaskCount: _goalTaskCount,
                                doneRate: doneRate,
                              ),
                              const SizedBox(height: 14),
                              if (_goals.isEmpty)
                                _GoalsEmptyState(onAdd: _addGoal)
                              else
                                Wrap(
                                  spacing: 12,
                                  runSpacing: 12,
                                  children: _goals.map((g) {
                                    // 使用 floorToDouble 安全防止像素误差导致的换行溢出
                                    final cardWidth = isWide
                                        ? ((constraints.maxWidth - 13) / 2).floorToDouble()
                                        : constraints.maxWidth;
                                    return SizedBox(
                                      width: cardWidth,
                                      child: _GoalSummaryCard(
                                        goal: g,
                                        onTap: () => _openGoalDetail(g),
                                        dueLabel: AppStrings.of(
                                          context,
                                          'goal_due',
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                            ],
                          );
                        },
                      ),
              ),
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'goals-add-fab',
        onPressed: _addGoal,
        icon: const Icon(Icons.add),
        label: Text(AppStrings.of(context, 'goal_add')),
      ),
    );
  }
}

class _GoalsOverviewCard extends StatelessWidget {
  final int goalCount;
  final int doneTaskCount;
  final int allTaskCount;
  final double doneRate;

  const _GoalsOverviewCard({
    required this.goalCount,
    required this.doneTaskCount,
    required this.allTaskCount,
    required this.doneRate,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppStrings.of(context, 'goal_title'),
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _MetricTile(
                    icon: Icons.flag_outlined,
                    label: 'Goals',
                    value: goalCount.toString(),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _MetricTile(
                    icon: Icons.task_alt,
                    label: 'Done',
                    value: '$doneTaskCount/$allTaskCount',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(value: doneRate),
          ],
        ),
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
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.42,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.bodySmall),
                Text(
                  value,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
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
  final Goal goal;
  final VoidCallback onTap;
  final String dueLabel;

  const _GoalSummaryCard({
    required this.goal,
    required this.onTap,
    required this.dueLabel,
  });

  @override
  Widget build(BuildContext context) {
    final percent = (goal.progress * 100).round();
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
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
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Chip(label: Text('P${goal.priority}')),
                ],
              ),
              const SizedBox(height: 8),
              Text('$dueLabel: ${goal.due.toLocal()}'.split(' ')[0]),
              const SizedBox(height: 10),
              LinearProgressIndicator(value: goal.progress),
              const SizedBox(height: 6),
              Text('$percent%'),
            ],
          ),
        ),
      ),
    );
  }
}
