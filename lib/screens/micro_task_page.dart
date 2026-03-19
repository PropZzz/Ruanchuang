import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/app_services.dart';
import '../utils/app_strings.dart';
import '../utils/schedule_occurrence.dart';

class MicroTaskPage extends StatefulWidget {
  const MicroTaskPage({super.key});

  @override
  State<MicroTaskPage> createState() => _MicroTaskPageState();
}

class _MicroTaskPageState extends State<MicroTaskPage> {
  final _dataService = AppServices.dataService;

  List<MicroTask> _tasks = [];
  bool _isLoading = true;

  bool _batchMode = false;
  final Set<String> _selected = <String>{};

  @override
  void initState() {
    super.initState();
    _loadMicroTasks();
  }

  String _taskKey(MicroTask t) {
    final id = t.id;
    if (id != null && id.isNotEmpty) return id;
    return 'mt_${t.title}_${t.tag}_${t.minutes}';
  }

  void _setBatchMode(bool enabled) {
    setState(() {
      _batchMode = enabled;
      _selected.clear();
    });
  }

  void _toggleSelected(MicroTask t) {
    final key = _taskKey(t);
    setState(() {
      if (_selected.contains(key)) {
        _selected.remove(key);
      } else {
        _selected.add(key);
      }
    });
  }

  List<MicroTask> _selectedTasks() {
    final selected = _selected;
    if (selected.isEmpty) return const [];
    return _tasks.where((t) => selected.contains(_taskKey(t))).toList();
  }

  Future<void> _loadMicroTasks() async {
    setState(() => _isLoading = true);
    final tasks = await _dataService.getMicroTasks();
    if (!mounted) return;

    tasks.sort((a, b) {
      if (a.done != b.done) return a.done ? 1 : -1;
      final p = b.priority.compareTo(a.priority);
      if (p != 0) return p;
      final tag = a.tag.compareTo(b.tag);
      if (tag != 0) return tag;
      final m = a.minutes.compareTo(b.minutes);
      if (m != 0) return m;
      return a.title.compareTo(b.title);
    });

    setState(() {
      _tasks = tasks;
      _isLoading = false;
    });
  }

  Future<void> _fillQuickTasks() async {
    final toAdd = [
      MicroTask(title: '整理笔记', tag: '低脑力', minutes: 12, priority: 2),
      MicroTask(title: '回复客户简短问题', tag: '任意', minutes: 7, priority: 3),
    ];

    for (final t in toAdd) {
      await _dataService.addMicroTask(t);
    }
    if (mounted) await _loadMicroTasks();
  }

  Future<void> _logMicroTaskCompleted(MicroTask task) async {
    final taskId = _taskKey(task);
    final now = DateTime.now();
    final minutes = task.minutes.clamp(1, 24 * 60);
    final tag = task.tag.trim().isEmpty ? 'Micro Task' : task.tag.trim();
    final title = task.title.trim().isEmpty ? 'Micro Task' : task.title.trim();

    await _dataService.logTaskEvent(
      TaskEvent(
        id: 'evt_start_${now.microsecondsSinceEpoch}_$taskId',
        taskId: taskId,
        title: title,
        tag: tag,
        at: now,
        type: TaskEventType.start,
        plannedMinutes: minutes,
      ),
    );

    await _dataService.logTaskEvent(
      TaskEvent(
        id: 'evt_done_${DateTime.now().microsecondsSinceEpoch}_$taskId',
        taskId: taskId,
        title: title,
        tag: tag,
        at: DateTime.now(),
        type: TaskEventType.complete,
        plannedMinutes: minutes,
        actualMinutes: minutes,
      ),
    );
  }

  Future<void> _setDone(MicroTask task, bool done) async {
    if (task.done == done) return;
    final wasDone = task.done;
    setState(() => task.done = done);
    await _dataService.updateMicroTask(task);
    if (!wasDone && done) {
      await _logMicroTaskCompleted(task);
    }
    if (mounted) await _loadMicroTasks();
  }

  void _showAddMicroTaskDialog(BuildContext context) {
    final titleCtrl = TextEditingController();
    final tagCtrl = TextEditingController();
    int minutes = 10;
    int priority = 3;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setInner) => AlertDialog(
          title: Text(AppStrings.of(context, 'micro_dialog_add')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleCtrl,
                decoration: InputDecoration(
                  labelText: AppStrings.of(context, 'label_title'),
                ),
              ),
              TextField(
                controller: tagCtrl,
                decoration: InputDecoration(
                  labelText: AppStrings.of(context, 'label_tag'),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(AppStrings.of(context, 'micro_label_min')),
                  const SizedBox(width: 8),
                  DropdownButton<int>(
                    value: minutes,
                    items: const [5, 8, 10, 15, 20]
                        .map((v) =>
                            DropdownMenuItem(value: v, child: Text('$v')))
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      setInner(() => minutes = v);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(AppStrings.of(context, 'label_priority')),
                  const SizedBox(width: 8),
                  DropdownButton<int>(
                    value: priority,
                    items: const [1, 2, 3, 4, 5]
                        .map((v) => DropdownMenuItem(
                              value: v,
                              child: Text('P$v'),
                            ))
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      setInner(() => priority = v);
                    },
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(AppStrings.of(context, 'btn_cancel')),
            ),
            ElevatedButton(
              onPressed: () async {
                final t = titleCtrl.text.trim();
                final tg = tagCtrl.text.trim();
                if (t.isEmpty) return;

                final newTask = MicroTask(
                  title: t,
                  tag: tg.isEmpty ? '任意' : tg,
                  minutes: minutes,
                  priority: priority,
                );

                Navigator.of(ctx).pop();
                await _dataService.addMicroTask(newTask);
                if (mounted) await _loadMicroTasks();
              },
              child: Text(AppStrings.of(context, 'btn_add')),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditMicroTaskDialog(BuildContext context, MicroTask task) {
    final titleCtrl = TextEditingController(text: task.title);
    final tagCtrl = TextEditingController(text: task.tag);
    int minutes = task.minutes;
    int priority = task.priority;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setInner) => AlertDialog(
          title: Text(AppStrings.of(context, 'micro_dialog_edit')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleCtrl,
                decoration: InputDecoration(
                  labelText: AppStrings.of(context, 'label_title'),
                ),
              ),
              TextField(
                controller: tagCtrl,
                decoration: InputDecoration(
                  labelText: AppStrings.of(context, 'label_tag'),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(AppStrings.of(context, 'micro_label_min')),
                  const SizedBox(width: 8),
                  DropdownButton<int>(
                    value: minutes,
                    items: const [5, 8, 10, 15, 20, 30, 45, 60]
                        .map((v) =>
                            DropdownMenuItem(value: v, child: Text('$v')))
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      setInner(() => minutes = v);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(AppStrings.of(context, 'label_priority')),
                  const SizedBox(width: 8),
                  DropdownButton<int>(
                    value: priority,
                    items: const [1, 2, 3, 4, 5]
                        .map((v) => DropdownMenuItem(
                              value: v,
                              child: Text('P$v'),
                            ))
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      setInner(() => priority = v);
                    },
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(AppStrings.of(context, 'btn_cancel')),
            ),
            ElevatedButton(
              onPressed: () async {
                final t = titleCtrl.text.trim();
                final tg = tagCtrl.text.trim();
                if (t.isEmpty) return;

                task.title = t;
                task.tag = tg.isEmpty ? '任意' : tg;
                task.minutes = minutes;
                task.priority = priority;

                Navigator.of(ctx).pop();
                await _dataService.updateMicroTask(task);
                if (mounted) await _loadMicroTasks();
              },
              child: Text(AppStrings.of(context, 'btn_save')),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeleteOne(MicroTask task) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppStrings.of(context, 'micro_dialog_del')),
        content: Text(
          '${AppStrings.of(context, 'dialog_del_content')} "${task.title}"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(AppStrings.of(context, 'btn_cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(AppStrings.of(context, 'btn_delete')),
          ),
        ],
      ),
    );

    if (ok != true) return;
    await _dataService.removeMicroTask(task);
    if (mounted) await _loadMicroTasks();
  }

  Future<void> _batchMarkComplete() async {
    final selectedTasks = _selectedTasks();
    if (selectedTasks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppStrings.of(context, 'micro_batch_need_select')),
        ),
      );
      return;
    }

    final toComplete = selectedTasks.where((t) => !t.done).toList();
    if (toComplete.isEmpty) return;

    for (final t in toComplete) {
      t.done = true;
      await _dataService.updateMicroTask(t);
      await _logMicroTaskCompleted(t);
    }

    _selected.clear();
    if (mounted) await _loadMicroTasks();
  }

  Future<void> _batchDelete() async {
    final selectedTasks = _selectedTasks();
    if (selectedTasks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppStrings.of(context, 'micro_batch_need_select')),
        ),
      );
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppStrings.of(context, 'dialog_del_title')),
        content: Text(
          '${AppStrings.of(context, 'dialog_del_content')} ${selectedTasks.length}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(AppStrings.of(context, 'btn_cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(AppStrings.of(context, 'btn_delete')),
          ),
        ],
      ),
    );
    if (ok != true) return;

    for (final t in selectedTasks) {
      await _dataService.removeMicroTask(t);
    }

    _selected.clear();
    if (mounted) await _loadMicroTasks();
  }

  Future<void> _batchSchedule() async {
    final selectedTasks = _selectedTasks();
    if (selectedTasks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppStrings.of(context, 'micro_batch_need_select')),
        ),
      );
      return;
    }

    final undone = selectedTasks.where((t) => !t.done).toList();
    if (undone.isEmpty) return;

    final tags =
        undone.map((t) => t.tag.trim()).where((t) => t.isNotEmpty).toSet();
    final tag = tags.length == 1 ? tags.first : null;
    if (tag == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppStrings.of(context, 'micro_batch_need_same_tag')),
        ),
      );
      return;
    }

    final totalMinutes = undone.fold<int>(0, (sum, t) => sum + t.minutes);
    final defaultMinutes = totalMinutes > 0 ? totalMinutes : 30;

    final titleCtrl = TextEditingController(
      text: AppStrings.of(
        context,
        'micro_batch_default_title',
        params: {'minutes': defaultMinutes.toString(), 'tag': tag},
      ),
    );
    final minutesCtrl = TextEditingController(text: defaultMinutes.toString());

    DateTime day = dateOnly(DateTime.now());
    TimeOfDay time = TimeOfDay.now();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setInner) => AlertDialog(
          title: Text(AppStrings.of(context, 'micro_schedule_dialog_title')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleCtrl,
                  decoration: InputDecoration(
                    labelText: AppStrings.of(context, 'label_title'),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(AppStrings.of(context, 'label_date')),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () async {
                        final now = DateTime.now();
                        final picked = await showDatePicker(
                          context: ctx2,
                          initialDate: day,
                          firstDate: DateTime(now.year - 1, 1, 1),
                          lastDate: DateTime(now.year + 2, 12, 31),
                          cancelText: AppStrings.of(context, 'btn_cancel'),
                          confirmText: AppStrings.of(context, 'btn_confirm'),
                        );
                        if (picked == null) return;
                        setInner(() => day = dateOnly(picked));
                      },
                      child: Text(
                        '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}',
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Text(AppStrings.of(context, 'label_start_time')),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () async {
                        final picked = await showTimePicker(
                          context: ctx2,
                          initialTime: time,
                          cancelText: AppStrings.of(context, 'btn_cancel'),
                          confirmText: AppStrings.of(context, 'btn_confirm'),
                        );
                        if (picked == null) return;
                        setInner(() => time = picked);
                      },
                      child: Text(time.format(context)),
                    ),
                  ],
                ),
                TextField(
                  controller: minutesCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: AppStrings.of(context, 'label_duration'),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(AppStrings.of(context, 'btn_cancel')),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(AppStrings.of(context, 'btn_confirm')),
            ),
          ],
        ),
      ),
    );

    if (ok != true) return;

    final title = titleCtrl.text.trim();
    final dur =
        (int.tryParse(minutesCtrl.text.trim()) ?? defaultMinutes).clamp(1, 24 * 60);
    if (title.isEmpty) return;

    final entry = ScheduleEntry(
      day: day,
      title: title,
      tag: tag,
      height: (dur / 60.0) * 80.0,
      color: Colors.orange,
      time: time,
    );

    await _dataService.addScheduleEntry(entry);

    for (final t in undone) {
      await _dataService.removeMicroTask(t);
    }

    // Review loop linkage: record at least a "complete" event.
    final batchId = 'mt_batch_${DateTime.now().microsecondsSinceEpoch}';
    final now = DateTime.now();
    await _dataService.logTaskEvent(
      TaskEvent(
        id: 'evt_start_${now.microsecondsSinceEpoch}_$batchId',
        taskId: batchId,
        title: title,
        tag: tag,
        at: now,
        type: TaskEventType.start,
        plannedMinutes: dur,
      ),
    );
    await _dataService.logTaskEvent(
      TaskEvent(
        id: 'evt_done_${DateTime.now().microsecondsSinceEpoch}_$batchId',
        taskId: batchId,
        title: title,
        tag: tag,
        at: DateTime.now(),
        type: TaskEventType.complete,
        plannedMinutes: dur,
        actualMinutes: dur,
      ),
    );

    if (!mounted) return;
    _setBatchMode(false);
    await _loadMicroTasks();
  }

  Widget _buildTagQuickSelect() {
    final tags = <String, int>{};
    for (final t in _tasks) {
      if (t.done) continue;
      final tag = t.tag.trim();
      if (tag.isEmpty) continue;
      tags[tag] = (tags[tag] ?? 0) + 1;
    }

    final tagList = tags.keys.toList()
      ..sort((a, b) => (tags[b] ?? 0).compareTo(tags[a] ?? 0));
    if (tagList.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: tagList.map((tag) {
          final keys = _tasks
              .where((t) => !t.done && t.tag.trim() == tag)
              .map(_taskKey)
              .toSet();
          final allSelected = keys.isNotEmpty && keys.every(_selected.contains);
          return FilterChip(
            label: Text('$tag (${tags[tag]})'),
            selected: allSelected,
            onSelected: (_) {
              final shouldSelect = keys.any((k) => !_selected.contains(k));
              setState(() {
                if (shouldSelect) {
                  _selected.addAll(keys);
                } else {
                  _selected.removeAll(keys);
                }
              });
            },
          );
        }).toList(growable: false),
      ),
    );
  }

  Widget _buildPriorityBadge(MicroTask task) {
    final theme = Theme.of(context);
    final p = task.priority.clamp(1, 5);

    final Color color;
    if (p >= 5) {
      color = theme.colorScheme.error;
    } else if (p >= 4) {
      color = theme.colorScheme.errorContainer;
    } else if (p >= 3) {
      color = theme.colorScheme.tertiary;
    } else if (p >= 2) {
      color = theme.colorScheme.secondary;
    } else {
      color = theme.colorScheme.outline;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha((0.12 * 255).round()),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withAlpha((0.35 * 255).round())),
      ),
      child: Text(
        'P$p',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedCount = _selected.length;

    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.of(context, 'micro_title')),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadMicroTasks,
          ),
          IconButton(
            tooltip: AppStrings.of(
              context,
              _batchMode ? 'micro_batch_exit' : 'micro_batch_enter',
            ),
            icon: Icon(_batchMode ? Icons.close : Icons.checklist),
            onPressed: () => _setBatchMode(!_batchMode),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  color: Theme.of(context).colorScheme.tertiaryContainer,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          AppStrings.of(context, 'micro_ai_suggestion'),
                          style: TextStyle(color: Theme.of(context).colorScheme.onTertiaryContainer),
                        ),
                      ),
                      ElevatedButton(
                        onPressed: _fillQuickTasks,
                        child: Text(AppStrings.of(context, 'micro_btn_fill')),
                      ),
                    ],
                  ),
                ),
                if (_batchMode) _buildTagQuickSelect(),
                Expanded(
                  child: GridView.count(
                    crossAxisCount: 2,
                    padding: const EdgeInsets.all(16),
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                    children: _tasks.map(_buildMicroTaskBubble).toList(),
                  ),
                ),
              ],
            ),
      bottomNavigationBar: _batchMode
          ? BottomAppBar(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        AppStrings.of(
                          context,
                          'micro_batch_selected',
                          params: {'count': selectedCount.toString()},
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: selectedCount == 0 ? null : _batchMarkComplete,
                      child: Text(AppStrings.of(context, 'btn_finish')),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: selectedCount == 0 ? null : _batchDelete,
                      child: Text(AppStrings.of(context, 'btn_delete')),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: selectedCount == 0 ? null : _batchSchedule,
                      child:
                          Text(AppStrings.of(context, 'micro_batch_schedule')),
                    ),
                  ],
                ),
              ),
            )
          : null,
      floatingActionButton: _batchMode
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _showAddMicroTaskDialog(context),
              label: Text(AppStrings.of(context, 'micro_btn_add')),
              icon: const Icon(Icons.add),
              backgroundColor: Theme.of(context).colorScheme.tertiary,
            ),
    );
  }

  Widget _buildMicroTaskBubble(MicroTask task) {
    final selected = _selected.contains(_taskKey(task));
    final safeTag = task.tag.trim().isEmpty ? '-' : task.tag.trim();

    final card = Container(
      decoration: BoxDecoration(
        color: task.done 
          ? Theme.of(context).colorScheme.surfaceVariant 
          : Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.shadow.withAlpha((0.1 * 255).round()),
            blurRadius: 10,
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            task.done ? Icons.check_circle : Icons.task_alt,
            color: task.done 
              ? Theme.of(context).colorScheme.primary 
              : Theme.of(context).colorScheme.tertiary,
            size: 32,
          ),
          const SizedBox(height: 8),
          Text(
            task.title,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              decoration: task.done ? TextDecoration.lineThrough : null,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.access_time, size: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
              Text(
                ' ${task.minutes} ${AppStrings.of(context, 'micro_card_min')} | $safeTag',
                style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ],
          ),
          if (!_batchMode) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(
                  onPressed: () async {
                    if (task.done) {
                      await _setDone(task, false);
                    } else {
                      await _setDone(task, true);
                    }
                  },
                  child: Text(
                    task.done
                        ? AppStrings.of(context, 'btn_incomplete')
                        : AppStrings.of(context, 'btn_finish'),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () => _showEditMicroTaskDialog(context, task),
                  icon: const Icon(Icons.edit, size: 18),
                ),
                IconButton(
                  onPressed: () => _confirmDeleteOne(task),
                  icon: const Icon(Icons.delete, size: 18),
                ),
              ],
            ),
          ],
        ],
      ),
    );

    if (_batchMode) {
      return InkWell(
        onTap: () => _toggleSelected(task),
        child: Stack(
          children: [
            Positioned.fill(child: card),
            Positioned(
              top: 8,
              left: 8,
              child: _buildPriorityBadge(task),
            ),
            Positioned(
              top: 6,
              right: 6,
              child: Checkbox(
                value: selected,
                onChanged: (_) => _toggleSelected(task),
              ),
            ),
          ],
        ),
      );
    }

    return GestureDetector(
      onLongPress: () => _confirmDeleteOne(task),
      child: Stack(
        children: [
          Positioned.fill(child: card),
          Positioned(
            top: 8,
            left: 8,
            child: _buildPriorityBadge(task),
          ),
        ],
      ),
    );
  }
}

