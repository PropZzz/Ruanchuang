import 'dart:ui';
import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/app_services.dart';
import '../services/microtask_crystals/microtask_import_parser.dart';
import '../utils/app_strings.dart';
import '../utils/mobile_feedback.dart';
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
    try {
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
    } catch (e, st) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      MobileFeedback.showError(
        context,
        category: 'microtask',
        message: 'load micro tasks failed',
        zhMessage: '暂时无法加载微任务，请稍后重试。',
        enMessage: 'Unable to load micro tasks right now.',
        error: e,
        stackTrace: st,
      );
    }
  }

  Future<void> _fillQuickTasks() async {
    final toAdd = [
      MicroTask(title: '整理笔记', tag: '低脑力', minutes: 12, priority: 2),
      MicroTask(title: '回复客户短消息', tag: '任意', minutes: 7, priority: 3),
    ];
    try {
      for (final t in toAdd) {
        await _dataService.addMicroTask(t);
      }
      if (mounted) await _loadMicroTasks();
    } catch (e, st) {
      if (!mounted) return;
      MobileFeedback.showError(
        context,
        category: 'microtask',
        message: 'fill quick tasks failed',
        zhMessage: '暂时无法添加推荐任务，请稍后重试。',
        enMessage: 'Unable to add the suggested tasks.',
        error: e,
        stackTrace: st,
      );
    }
  }

  int _pointsFor(MicroTask task) => MicroTaskImportParser.pointsForTask(task);

  int _completedPoints() {
    return _tasks
        .where((t) => t.done)
        .fold<int>(0, (sum, task) => sum + _pointsFor(task));
  }

  int _pendingPoints() {
    return _tasks
        .where((t) => !t.done)
        .fold<int>(0, (sum, task) => sum + _pointsFor(task));
  }

  bool _isEnglish(BuildContext context) {
    return Localizations.localeOf(context).languageCode == 'en';
  }

  String _pointsUnit(BuildContext context) {
    return _isEnglish(context) ? 'pts' : '积分';
  }

  String _taskCompletedMessage(BuildContext context, MicroTask task) {
    final points = _pointsFor(task);
    if (_isEnglish(context)) {
      return 'Completed "${task.title}" · +$points pts';
    }
    return '已完成“${task.title}”，+$points 积分';
  }

  String _batchCompletedMessage(BuildContext context, int points) {
    if (_isEnglish(context)) {
      return 'Batch completed · +$points pts';
    }
    return '批量完成，+$points 积分';
  }

  Future<void> _showImportMicroTasksDialog() async {
    final rawCtrl = TextEditingController();
    MicroTaskImportSummary? preview;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setInner) => AlertDialog(
          title: const Text(
            '导入清单',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          content: ConstrainedBox(
            constraints: MobileFeedback.dialogConstraints(ctx2, maxWidth: 560),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '粘贴清单或场景文本以导入任务。',
                    style: TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: rawCtrl,
                    minLines: 8,
                    maxLines: 14,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      hintText: '1. 回复邮件 10分钟 #收件箱\n- 修复登录 Bug 紧急 45分钟 #开发',
                    ),
                    onChanged: (_) => setInner(() => preview = null),
                  ),
                  const SizedBox(height: 12),
                  if (preview != null) ...[
                    Text(
                      preview!.headline,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        Chip(label: Text('${preview!.suggestions.length} 项')),
                        Chip(label: Text('${preview!.totalMinutes} 分钟')),
                        Chip(
                          label: Text(
                            '+${preview!.totalPoints} 积分',
                            style: const TextStyle(
                              color: Colors.green,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 220,
                      child: ListView.separated(
                        itemCount: preview!.suggestions.length,
                        separatorBuilder: (_, __) => const Divider(height: 8),
                        itemBuilder: (context, index) {
                          final s = preview!.suggestions[index];
                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(child: Text('${s.points}')),
                            title: Text(s.task.title),
                            subtitle: Text(
                              '${s.task.minutes} 分钟 | ${s.task.tag} | P${s.task.priority}',
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx2).pop(false),
              child: const Text('取消'),
            ),
            OutlinedButton.icon(
              onPressed: () {
                final parsed = MicroTaskImportParser.parse(rawCtrl.text);
                setInner(() => preview = parsed);
              },
              icon: const Icon(Icons.preview),
              label: const Text('预览'),
            ),
            ElevatedButton.icon(
              onPressed: preview == null || preview!.suggestions.isEmpty
                  ? null
                  : () => Navigator.of(ctx2).pop(true),
              icon: const Icon(Icons.download_done),
              label: const Text('导入'),
            ),
          ],
        ),
      ),
    );

    rawCtrl.dispose();

    if (ok != true || preview == null || preview!.suggestions.isEmpty) return;

    try {
      for (final suggestion in preview!.suggestions) {
        await _dataService.addMicroTask(suggestion.task);
      }

      if (!mounted) return;
      await _loadMicroTasks();
      MobileFeedback.showInfo(
        context,
        zhMessage: '导入完成。',
        enMessage: 'Micro tasks imported successfully.',
      );
    } catch (e, st) {
      if (!mounted) return;
      MobileFeedback.showError(
        context,
        category: 'microtask',
        message: 'import micro tasks failed',
        zhMessage: '导入失败，请检查内容后重试。',
        enMessage: 'Unable to import the micro tasks.',
        error: e,
        stackTrace: st,
      );
    }
  }

  Future<void> _logMicroTaskCompleted(MicroTask task) async {
    final taskId = _taskKey(task);
    final now = DateTime.now();
    final minutes = task.minutes.clamp(1, 24 * 60);
    final tag = task.tag.trim().isEmpty ? '未分类' : task.tag.trim();
    final title = task.title.trim().isEmpty ? '未命名任务' : task.title.trim();

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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_taskCompletedMessage(context, task))),
        );
      }
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
          title: Text(
            AppStrings.of(context, 'micro_dialog_add'),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleCtrl,
                  decoration: InputDecoration(
                    labelText: AppStrings.of(context, 'label_title'),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: tagCtrl,
                  decoration: InputDecoration(
                    labelText: AppStrings.of(context, 'label_tag'),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(AppStrings.of(context, 'micro_label_min')),
                    DropdownButton<int>(
                      value: minutes,
                      items: const [5, 8, 10, 15, 20, 30, 45, 60]
                          .map(
                            (v) => DropdownMenuItem(
                              value: v,
                              child: Text('$v min'),
                            ),
                          )
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
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(AppStrings.of(context, 'label_priority')),
                    DropdownButton<int>(
                      value: priority,
                      items: const [1, 2, 3, 4, 5]
                          .map(
                            (v) =>
                                DropdownMenuItem(value: v, child: Text('P$v')),
                          )
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
                  tag: tg.isEmpty ? '未分类' : tg,
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
          title: Text(
            AppStrings.of(context, 'micro_dialog_edit'),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleCtrl,
                  decoration: InputDecoration(
                    labelText: AppStrings.of(context, 'label_title'),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: tagCtrl,
                  decoration: InputDecoration(
                    labelText: AppStrings.of(context, 'label_tag'),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(AppStrings.of(context, 'micro_label_min')),
                    DropdownButton<int>(
                      value: minutes,
                      items: const [5, 8, 10, 15, 20, 30, 45, 60]
                          .map(
                            (v) => DropdownMenuItem(
                              value: v,
                              child: Text('$v min'),
                            ),
                          )
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
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(AppStrings.of(context, 'label_priority')),
                    DropdownButton<int>(
                      value: priority,
                      items: const [1, 2, 3, 4, 5]
                          .map(
                            (v) =>
                                DropdownMenuItem(value: v, child: Text('P$v')),
                          )
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
                task.tag = tg.isEmpty ? '未分类' : tg;
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
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
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
    final earnedPoints = toComplete.fold<int>(
      0,
      (sum, task) => sum + _pointsFor(task),
    );

    for (final t in toComplete) {
      t.done = true;
      await _dataService.updateMicroTask(t);
      await _logMicroTaskCompleted(t);
    }

    _selected.clear();
    if (!mounted) return;
    await _loadMicroTasks();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_batchCompletedMessage(context, earnedPoints))),
    );
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
          '${AppStrings.of(context, 'dialog_del_content')} ${selectedTasks.length} 项？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(AppStrings.of(context, 'btn_cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
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

    final tags = undone
        .map((t) => t.tag.trim())
        .where((t) => t.isNotEmpty)
        .toSet();
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
          title: Text(
            AppStrings.of(context, 'micro_schedule_dialog_title'),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleCtrl,
                  decoration: InputDecoration(
                    labelText: AppStrings.of(context, 'label_title'),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('日期'),
                  trailing: const Icon(Icons.calendar_today, size: 18),
                  subtitle: Text(
                    '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  onTap: () async {
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
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('时间'),
                  trailing: const Icon(Icons.access_time, size: 18),
                  subtitle: Text(
                    time.format(context),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  onTap: () async {
                    final picked = await showTimePicker(
                      context: ctx2,
                      initialTime: time,
                      cancelText: AppStrings.of(context, 'btn_cancel'),
                      confirmText: AppStrings.of(context, 'btn_confirm'),
                    );
                    if (picked == null) return;
                    setInner(() => time = picked);
                  },
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: minutesCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: AppStrings.of(context, 'label_duration'),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
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
    final dur = (int.tryParse(minutesCtrl.text.trim()) ?? defaultMinutes).clamp(
      1,
      24 * 60,
    );
    if (title.isEmpty) return;

    final entry = ScheduleEntry(
      day: day,
      title: title,
      tag: tag,
      height: (dur / 60.0) * 80.0,
      color: Theme.of(context).colorScheme.tertiary,
      time: time,
    );

    await _dataService.addScheduleEntry(entry);

    for (final t in undone) {
      await _dataService.removeMicroTask(t);
    }

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
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: tagList.map((tag) {
            final keys = _tasks
                .where((t) => !t.done && t.tag.trim() == tag)
                .map(_taskKey)
                .toSet();
            final allSelected =
                keys.isNotEmpty && keys.every(_selected.contains);
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text('$tag (${tags[tag]})'),
                selected: allSelected,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
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
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildPriorityBadge(MicroTask task) {
    final p = task.priority.clamp(1, 5);
    final colors = [
      Colors.grey,
      Colors.blue,
      Colors.teal,
      Colors.orange,
      Colors.red,
    ];
    final color = colors[p - 1];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'P$p',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }

  Widget _buildHeaderCard(int doneCount, int totalPoints, int completedPoints) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [
                  theme.colorScheme.primaryContainer.withOpacity(0.4),
                  theme.colorScheme.primaryContainer.withOpacity(0.1),
                ]
              : [
                  theme.colorScheme.primaryContainer.withOpacity(0.8),
                  theme.colorScheme.primaryContainer.withOpacity(0.3),
                ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: isDark
            ? []
            : [
                BoxShadow(
                  color: theme.colorScheme.primary.withOpacity(0.15),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
            child: Text(
              AppStrings.of(context, 'micro_ai_suggestion'),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: theme.colorScheme.onSurface,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildHeaderStatItem(
                '已完成',
                '$doneCount/${_tasks.length}',
                Icons.check_circle_rounded,
              ),
              _buildHeaderStatItem(
                '已获积分',
                '$completedPoints',
                Icons.stars_rounded,
              ),
              _buildHeaderStatItem('总计积分', '$totalPoints', Icons.bolt_rounded),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderStatItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Theme.of(context).colorScheme.primary, size: 28),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedCount = _selected.length;
    final selectedPoints = _selectedTasks()
        .where((t) => !t.done)
        .fold<int>(0, (sum, task) => sum + _pointsFor(task));
    final doneCount = _tasks.where((t) => t.done).length;
    final totalPoints = _tasks.fold<int>(
      0,
      (sum, task) => sum + _pointsFor(task),
    );
    final completedPoints = _completedPoints();

    return Scaffold(
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF121212)
          : const Color(0xFFF2F2F7),
      appBar: AppBar(
        title: Text(
          AppStrings.of(context, 'micro_title'),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadMicroTasks,
          ),
          IconButton(
            tooltip: _batchMode ? '退出批量' : '批量模式',
            icon: Icon(
              _batchMode ? Icons.close_rounded : Icons.checklist_rounded,
            ),
            onPressed: () => _setBatchMode(!_batchMode),
          ),
          IconButton(
            tooltip: '导入清单',
            icon: const Icon(Icons.upload_file_rounded),
            onPressed: _showImportMicroTasksDialog,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildHeaderCard(doneCount, totalPoints, completedPoints),
                if (_batchMode) _buildTagQuickSelect(),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 16,
                    ),
                    physics: const BouncingScrollPhysics(),
                    itemCount: _tasks.length,
                    itemBuilder: (context, index) =>
                        _buildMicroTaskBubble(_tasks[index]),
                  ),
                ),
              ],
            ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: _batchMode
          ? _buildBatchActionBar(selectedCount, selectedPoints)
          : FloatingActionButton.extended(
              heroTag: 'micro-task-add-fab',
              onPressed: () => _showAddMicroTaskDialog(context),
              label: Text(
                AppStrings.of(context, 'micro_btn_add'),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              icon: const Icon(Icons.add_rounded),
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
            ),
    );
  }

  Widget _buildBatchActionBar(int count, int points) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface.withOpacity(0.8),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '已选 $count 项',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      Text(
                        '可获 +$points ${_pointsUnit(context)}',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(
                        Icons.delete_outline,
                        color: Colors.redAccent,
                      ),
                      onPressed: count == 0 ? null : _batchDelete,
                      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                    ),
                    const SizedBox(width: 4),
                    ElevatedButton(
                      onPressed: count == 0 ? null : _batchSchedule,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.tertiary,
                        foregroundColor: Theme.of(
                          context,
                        ).colorScheme.onTertiary,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        visualDensity: VisualDensity.compact,
                      ),
                      child: const Text('集中安排', style: TextStyle(fontSize: 13)),
                    ),
                    const SizedBox(width: 6),
                    ElevatedButton(
                      onPressed: count == 0 ? null : _batchMarkComplete,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor: Theme.of(
                          context,
                        ).colorScheme.onPrimary,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        visualDensity: VisualDensity.compact,
                      ),
                      child: const Text('完成', style: TextStyle(fontSize: 13)),
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

  Widget _buildMicroTaskBubble(MicroTask task) {
    final selected = _selected.contains(_taskKey(task));
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: task.done
            ? (isDark
                  ? Colors.white.withOpacity(0.02)
                  : Colors.grey.withOpacity(0.05))
            : (isDark ? const Color(0xFF1E1E1E) : Colors.white),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: selected
              ? theme.colorScheme.primary
              : (isDark ? Colors.white10 : Colors.black12),
          width: selected ? 2 : 1,
        ),
        boxShadow: task.done || isDark
            ? []
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: _batchMode ? () => _toggleSelected(task) : null,
          onLongPress: () {
            if (!_batchMode) _confirmDeleteOne(task);
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                if (_batchMode) ...[
                  Checkbox(
                    value: selected,
                    onChanged: (_) => _toggleSelected(task),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                    activeColor: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                ],

                // 左侧图标区
                GestureDetector(
                  onTap: () {
                    if (!_batchMode) _setDone(task, !task.done);
                  },
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: task.done
                          ? Colors.green.withOpacity(0.1)
                          : theme.colorScheme.primary.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      task.done
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked_rounded,
                      color: task.done
                          ? Colors.green
                          : theme.colorScheme.primary,
                      size: 26,
                    ),
                  ),
                ),
                const SizedBox(width: 16),

                // 中间信息区
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          decoration: task.done
                              ? TextDecoration.lineThrough
                              : null,
                          color: task.done
                              ? theme.colorScheme.onSurfaceVariant
                              : theme.colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _buildPriorityBadge(task),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.white10
                                  : Colors.black.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.access_time_rounded,
                                  size: 12,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${task.minutes} min',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.white10
                                  : Colors.black.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.tag_rounded,
                                  size: 12,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  task.tag.trim().isEmpty ? '未分类' : task.tag,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // 右侧操作区
                if (!_batchMode) ...[
                  SizedBox(
                    width: 80,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '+${_pointsFor(task)} ${_pointsUnit(context)}',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: task.done
                                ? Colors.green
                                : theme.colorScheme.primary,
                            fontSize: 13,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(
                                Icons.edit_rounded,
                                size: 20,
                                color: Colors.grey,
                              ),
                              onPressed: () =>
                                  _showEditMicroTaskDialog(context, task),
                              constraints: const BoxConstraints(
                                minWidth: 32,
                                minHeight: 32,
                              ),
                              padding: EdgeInsets.zero,
                              visualDensity: VisualDensity.compact,
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.delete_outline_rounded,
                                size: 20,
                                color: Colors.redAccent,
                              ),
                              onPressed: () => _confirmDeleteOne(task),
                              constraints: const BoxConstraints(
                                minWidth: 32,
                                minHeight: 32,
                              ),
                              padding: EdgeInsets.zero,
                              visualDensity: VisualDensity.compact,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
