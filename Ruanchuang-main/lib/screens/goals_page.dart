import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/app_services.dart';
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
    // P0 heuristic decomposition; replace with LLM later.
    final ts = DateTime.now().microsecondsSinceEpoch;
    return [
      GoalTask(
        id: 'gt_${ts}_1',
        title: '$goalTitle - 需求梳理',
        durationMinutes: 45,
        load: CognitiveLoad.medium,
        tag: 'Goal',
      ),
      GoalTask(
        id: 'gt_${ts}_2',
        title: '$goalTitle - 资料收集',
        durationMinutes: 60,
        load: CognitiveLoad.high,
        tag: 'Goal',
      ),
      GoalTask(
        id: 'gt_${ts}_3',
        title: '$goalTitle - 初稿产出',
        durationMinutes: 90,
        load: CognitiveLoad.high,
        tag: 'Goal',
      ),
      GoalTask(
        id: 'gt_${ts}_4',
        title: '$goalTitle - 复审修改',
        durationMinutes: 60,
        load: CognitiveLoad.medium,
        tag: 'Goal',
      ),
      GoalTask(
        id: 'gt_${ts}_5',
        title: '$goalTitle - 收尾交付',
        durationMinutes: 30,
        load: CognitiveLoad.low,
        tag: 'Goal',
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
                decoration: InputDecoration(labelText: AppStrings.of(ctx2, 'label_title')),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: Text('${AppStrings.of(ctx2, 'goal_due')}: ${due.toLocal()}'.split(' ')[0])),
                  TextButton(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: ctx2,
                        firstDate: DateTime.now().subtract(const Duration(days: 1)),
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
                        .map((v) => DropdownMenuItem(value: v, child: Text('$v')))
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
        content: Text('${AppStrings.of(ctx, 'dialog_del_content')} "${g.title}"?'),
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
    final tasks = g.tasks.map((x) => x.id == t.id ? x.copyWith(done: !x.done) : x).toList();
    await _data.upsertGoal(
      Goal(id: g.id, title: g.title, due: g.due, priority: g.priority, tasks: tasks),
    );
    await _load();
  }

  List<TimeWindow> _defaultWindows() {
    return const [
      TimeWindow(start: TimeOfDay(hour: 9, minute: 0), end: TimeOfDay(hour: 12, minute: 0)),
      TimeWindow(start: TimeOfDay(hour: 13, minute: 30), end: TimeOfDay(hour: 18, minute: 30)),
    ];
  }

  Future<void> _scheduleNext(Goal g) async {
    final next = g.tasks.firstWhere((t) => !t.done, orElse: () => const GoalTask(id: '', title: '', durationMinutes: 0, load: CognitiveLoad.low, tag: 'Goal'));
    if (next.id.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppStrings.of(context, 'goal_all_done'))));
      return;
    }

    final day = DateTime.now();
    final d = DateTime(day.year, day.month, day.day);
    final schedule =
        entriesForDay(day: d, allEntries: await _data.getScheduleEntries());

    TimeOfDay? pickStart() {
      final windows = _defaultWindows();
      final blocks = List<ScheduleEntry>.from(schedule)
        ..sort((a, b) => (a.time.hour * 60 + a.time.minute).compareTo(b.time.hour * 60 + b.time.minute));

      for (final w in windows) {
        var cursor = w.start.hour * 60 + w.start.minute;
        final wEnd = w.end.hour * 60 + w.end.minute;

        for (final b in blocks) {
          final bStart = b.time.hour * 60 + b.time.minute;
          final bDur = ((b.height / 80.0) * 60.0).round();
          final bEnd = bStart + bDur;

          if (bEnd <= cursor) continue;
          if (bStart >= wEnd) break;

          // If there is a gap between cursor and next busy block.
          final gap = (bStart - cursor).clamp(0, 24 * 60);
          if (gap >= next.durationMinutes && cursor + next.durationMinutes <= wEnd) {
            return TimeOfDay(hour: cursor ~/ 60, minute: cursor % 60);
          }
          // Advance cursor after this busy block.
          cursor = bEnd.clamp(cursor, wEnd);
        }

        // End of window.
        if (wEnd - cursor >= next.durationMinutes) {
          return TimeOfDay(hour: cursor ~/ 60, minute: cursor % 60);
        }
      }
      return null;
    }

    final start = pickStart();
    if (start == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppStrings.of(context, 'goal_no_slot'))));
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
      SnackBar(content: Text('${AppStrings.of(context, 'goal_scheduled')}: ${start.format(context)}')),
    );
  }

  void _openGoalDetail(Goal g) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        minChildSize: 0.5,
        builder: (ctx2, controller) {
          return Material(
            child: ListView(
              controller: controller,
              padding: const EdgeInsets.all(16),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(g.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
                Text('${AppStrings.of(context, 'goal_due')}: ${g.due.toLocal()}'.split(' ')[0]),
                Text('${AppStrings.of(context, 'goal_priority')}: ${g.priority}'),
                const SizedBox(height: 12),
                LinearProgressIndicator(value: g.progress),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _scheduleNext(g),
                        icon: const Icon(Icons.calendar_month_outlined),
                        label: Text(AppStrings.of(context, 'goal_schedule_next')),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(AppStrings.of(context, 'goal_tasks'), style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ...g.tasks.map(
                  (t) => CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: t.done,
                    onChanged: (_) => _toggleTask(g, t),
                    title: Text(t.title),
                    subtitle: Text('${t.durationMinutes} min | ${t.load.name}'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.of(context, 'goal_title')),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _goals.isEmpty
              ? Center(child: Text(AppStrings.of(context, 'goal_empty')))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: _goals.map((g) {
                    return Card(
                      child: ListTile(
                        onTap: () => _openGoalDetail(g),
                        title: Text(g.title),
                        subtitle: Text('${AppStrings.of(context, 'goal_due')}: ${g.due.toLocal()}'.split(' ')[0]),
                        trailing: SizedBox(
                          width: 90,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text('${(g.progress * 100).round()}%'),
                              const SizedBox(height: 6),
                              LinearProgressIndicator(value: g.progress),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addGoal,
        icon: const Icon(Icons.add),
        label: Text(AppStrings.of(context, 'goal_add')),
      ),
    );
  }
}
