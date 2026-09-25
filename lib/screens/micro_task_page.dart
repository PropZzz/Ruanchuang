import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/app_services.dart';
import '../services/microtask_crystals/microtask_import_parser.dart';
import '../theme/app_theme.dart';
import '../utils/app_strings.dart';
import '../utils/mobile_feedback.dart';
import '../utils/schedule_occurrence.dart';
import '../widgets/press_scale.dart';
import '../widgets/responsive_page_frame.dart';
import '../widgets/stitch_mobile_scaffold.dart';

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
  final TextEditingController _quickEntryController = TextEditingController();
  String _taskFilter = 'all';

  @override
  void dispose() {
    _quickEntryController.dispose();
    super.dispose();
  }

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

  bool _isMobileViewport(BuildContext context) =>
      MediaQuery.sizeOf(context).width < 720;

  Future<T?> _showResponsiveForm<T>({required WidgetBuilder builder}) {
    if (_isMobileViewport(context)) {
      return showModalBottomSheet<T>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        builder: builder,
      );
    }
    return showDialog<T>(context: context, builder: builder);
  }

  Widget _formSurface(
    BuildContext context, {
    required Widget title,
    required Widget content,
    required List<Widget> actions,
  }) {
    if (!_isMobileViewport(context)) {
      return AlertDialog(
        title: title,
        content: content,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        actions: actions,
      );
    }

    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Material(
          color: scheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.9,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(top: 10, bottom: 14),
                  decoration: BoxDecoration(
                    color: scheme.outlineVariant,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: Align(alignment: Alignment.centerLeft, child: title),
                ),
                Flexible(
                  fit: FlexFit.loose,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: content,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    runSpacing: 8,
                    children: actions,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showImportMicroTasksDialog() async {
    final rawCtrl = TextEditingController();
    MicroTaskImportSummary? preview;

    final ok = await _showResponsiveForm<bool>(
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setInner) => _formSurface(
          ctx2,
          title: const Text(
            '导入清单',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: ConstrainedBox(
            constraints: MobileFeedback.dialogConstraints(ctx2, maxWidth: 560),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '粘贴清单或场景文本以导入任务。',
                    style: TextStyle(
                      color: Theme.of(ctx2).colorScheme.onSurfaceVariant,
                    ),
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
                            style: TextStyle(
                              color: Theme.of(ctx2).colorScheme.secondary,
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

    _showResponsiveForm<void>(
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setInner) => _formSurface(
          ctx2,
          title: Text(
            AppStrings.of(context, 'micro_dialog_add'),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          content: Column(
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
                          (v) =>
                              DropdownMenuItem(value: v, child: Text('$v min')),
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
                          (v) => DropdownMenuItem(value: v, child: Text('P$v')),
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

    _showResponsiveForm<void>(
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setInner) => _formSurface(
          ctx2,
          title: Text(
            AppStrings.of(context, 'micro_dialog_edit'),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          content: Column(
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
                          (v) =>
                              DropdownMenuItem(value: v, child: Text('$v min')),
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
                          (v) => DropdownMenuItem(value: v, child: Text('P$v')),
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
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
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
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
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

    final ok = await _showResponsiveForm<bool>(
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setInner) => _formSurface(
          ctx2,
          title: Text(
            AppStrings.of(context, 'micro_schedule_dialog_title'),
            style: const TextStyle(fontWeight: FontWeight.bold),
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
    final scheme = Theme.of(context).colorScheme;
    final colors = [
      scheme.onSurfaceVariant,
      scheme.primary,
      scheme.secondary,
      scheme.tertiary,
      scheme.error,
    ];
    final color = colors[p - 1];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
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

  Future<void> _addQuickTask() async {
    final title = _quickEntryController.text.trim();
    if (title.isEmpty) return;

    try {
      await _dataService.addMicroTask(
        MicroTask(title: title, tag: '任意', minutes: 15, priority: 3),
      );
      _quickEntryController.clear();
      if (mounted) await _loadMicroTasks();
    } catch (e, st) {
      if (!mounted) return;
      MobileFeedback.showError(
        context,
        category: 'microtask',
        message: 'quick add micro task failed',
        zhMessage: '暂时无法添加微任务，请稍后重试。',
        enMessage: 'Unable to add the micro task right now.',
        error: e,
        stackTrace: st,
      );
    }
  }

  Widget _buildPageHeading({required bool mobile}) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SANDBOX DISPATCH',
                  style: TextStyle(
                    color: scheme.secondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '微任务沙盒与心流调度',
                  style: TextStyle(
                    color: scheme.primary,
                    fontSize: mobile ? 21 : 28,
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '把零散事务拆成可完成的短任务，按优先级安排下一步。',
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          if (!mobile) ...[
            const SizedBox(width: 16),
            FilledButton.icon(
              onPressed: () => _showAddMicroTaskDialog(context),
              icon: const Icon(Icons.add_rounded),
              label: const Text('添加微任务'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMetrics() {
    final pending = _tasks.where((task) => !task.done).toList();
    final doneCount = _tasks.length - pending.length;
    final pendingMinutes = pending.fold<int>(
      0,
      (sum, task) => sum + task.minutes,
    );
    final metrics = [
      (
        label: '待处理',
        value: '${pending.length}',
        detail: '约 ${(pendingMinutes / 60).toStringAsFixed(1)}h 负荷',
        icon: Icons.bubble_chart_outlined,
        color: Theme.of(context).colorScheme.secondary,
      ),
      (
        label: '已完成',
        value: '$doneCount',
        detail: '今日完成任务',
        icon: Icons.check_circle_outline_rounded,
        color: Theme.of(context).colorScheme.tertiary,
      ),
      (
        label: '已获得积分',
        value: '$_completedPointsValue',
        detail: '按已完成任务累计',
        icon: Icons.bolt_rounded,
        color: Theme.of(context).colorScheme.primary,
      ),
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          for (var index = 0; index < metrics.length; index++) ...[
            if (index > 0) const SizedBox(width: 10),
            Expanded(
              child: Container(
                constraints: const BoxConstraints(minHeight: 96),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          metrics[index].icon,
                          size: 16,
                          color: metrics[index].color,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            metrics[index].label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      metrics[index].value,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    Text(
                      metrics[index].detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  int get _completedPointsValue => _completedPoints();

  Widget _buildQuickEntryCard() {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.playlist_add_rounded,
                color: scheme.secondary,
                size: 18,
              ),
              const SizedBox(width: 7),
              const Text(
                '快速录入',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              ),
              const Spacer(),
              Text(
                '默认 15 分钟 · 任意标签',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _quickEntryController,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _addQuickTask(),
                  decoration: InputDecoration(
                    hintText: '快速输入一项待办',
                    prefixIcon: const Icon(Icons.edit_note_rounded),
                    isDense: true,
                    filled: true,
                    fillColor: scheme.surfaceContainerLow,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(9),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _addQuickTask,
                icon: const Icon(Icons.arrow_forward_rounded, size: 17),
                label: const Text('添加'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSprintBanner() {
    final scheme = Theme.of(context).colorScheme;
    final quickCount = _tasks
        .where((task) => !task.done && task.minutes <= 15)
        .length;
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: scheme.tertiaryFixed.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.bolt_rounded, color: scheme.tertiaryFixed),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '聚焦沙盒 · 闪电防线',
                  style: TextStyle(
                    color: scheme.tertiaryFixed,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  quickCount == 0 ? '当前没有短时待办' : '有 $quickCount 项短时待办可优先清理',
                  style: TextStyle(
                    color: scheme.onPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '利用会前空隙完成一项，减少任务积压。',
                  style: TextStyle(
                    color: scheme.onPrimary.withValues(alpha: 0.8),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: _fillQuickTasks,
            style: FilledButton.styleFrom(
              backgroundColor: scheme.tertiaryFixed,
              foregroundColor: scheme.onTertiaryFixed,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            icon: const Icon(Icons.auto_awesome_rounded, size: 16),
            label: const Text('AI 填充'),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskListColumn() {
    final scheme = Theme.of(context).colorScheme;
    final visibleTasks = _tasks.where((task) {
      if (_taskFilter == 'pending') return !task.done;
      if (_taskFilter == 'done') return task.done;
      return true;
    }).toList();
    final groups = [
      _MicroTaskGroup(
        title: '紧急且今日必做',
        icon: Icons.priority_high_rounded,
        color: scheme.error,
        tasks: visibleTasks.where((task) => task.priority == 1).toList(),
      ),
      _MicroTaskGroup(
        title: '随手快速处理（≤5m）',
        icon: Icons.flash_on_rounded,
        color: scheme.secondary,
        tasks: visibleTasks
            .where((task) => task.priority != 1 && task.minutes <= 5)
            .toList(),
      ),
      _MicroTaskGroup(
        title: '排队中（待流转）',
        icon: Icons.queue_rounded,
        color: scheme.primary,
        tasks: visibleTasks
            .where(
              (task) =>
                  task.priority != 1 && task.minutes > 5 && task.priority <= 3,
            )
            .toList(),
      ),
      _MicroTaskGroup(
        title: '稍后处理（低认知负荷）',
        icon: Icons.hourglass_bottom_rounded,
        color: scheme.onSurfaceVariant,
        tasks: visibleTasks
            .where((task) => task.priority > 3 && task.minutes > 5)
            .toList(),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '任务队列',
                style: TextStyle(
                  color: scheme.onSurface,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Text(
              '${visibleTasks.length} 项',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SegmentedButton<String>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(value: 'all', label: Text('全部 ${_tasks.length}')),
            ButtonSegment(
              value: 'pending',
              label: Text('待处理 ${_tasks.where((task) => !task.done).length}'),
            ),
            ButtonSegment(
              value: 'done',
              label: Text('已完成 ${_tasks.where((task) => task.done).length}'),
            ),
          ],
          selected: {_taskFilter},
          onSelectionChanged: (selection) {
            setState(() => _taskFilter = selection.first);
          },
        ),
        if (_batchMode) _buildTagQuickSelect(),
        const SizedBox(height: 12),
        if (_tasks.isEmpty)
          _buildEmptyTasks()
        else if (visibleTasks.isEmpty)
          _buildFilteredEmpty()
        else
          for (final group in groups) _buildTaskSection(group),
      ],
    );
  }

  Widget _buildTaskSection(_MicroTaskGroup group) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: group.color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  group.title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '${group.tasks.length} 项待清',
                style: TextStyle(
                  color: group.color,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (group.tasks.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                '当前分组暂无任务',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
              ),
            )
          else
            for (final task in group.tasks) _buildMicroTaskBubble(task),
        ],
      ),
    );
  }

  Widget _buildEmptyTasks() {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        children: [
          Icon(
            Icons.check_circle_outline_rounded,
            color: scheme.tertiary,
            size: 30,
          ),
          const SizedBox(height: 8),
          const Text('暂无微任务', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            '添加一项任务，或导入现有清单。',
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => _showAddMicroTaskDialog(context),
            icon: const Icon(Icons.add_rounded),
            label: const Text('添加微任务'),
          ),
        ],
      ),
    );
  }

  Widget _buildFilteredEmpty() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: Text(
          '此筛选条件下暂无任务',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Widget _buildInsightsPanel() {
    final scheme = Theme.of(context).colorScheme;
    final completed = _tasks.where((task) => task.done).length;
    final ratio = _tasks.isEmpty ? 0.0 : completed / _tasks.length;
    final quickCount = _tasks
        .where((task) => !task.done && task.minutes <= 15)
        .length;
    final pendingCount = _tasks.length - completed;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: scheme.primaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.bolt_rounded,
                    color: scheme.tertiaryFixed,
                    size: 18,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      '聚焦沙盒 · 闪电防线',
                      style: TextStyle(
                        color: scheme.tertiaryFixed,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                quickCount == 0 ? '当前没有短时待办' : '发现 $quickCount 项短时待办',
                style: TextStyle(
                  color: scheme.onPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '选一项在下一段空档里完成。',
                style: TextStyle(
                  color: scheme.onPrimary.withValues(alpha: 0.8),
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _fillQuickTasks,
                  style: FilledButton.styleFrom(
                    backgroundColor: scheme.tertiaryFixed,
                    foregroundColor: scheme.onTertiaryFixed,
                  ),
                  icon: const Icon(Icons.auto_awesome_rounded, size: 17),
                  label: const Text('AI 填充'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '清零成就与节奏审计',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${(ratio * 100).round()}%',
                    style: TextStyle(
                      color: scheme.primary,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '$completed / ${_tasks.length} 已完成',
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: ratio,
                  minHeight: 7,
                  backgroundColor: scheme.surfaceContainerHigh,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '已获得 ${_completedPoints()} 积分',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '积压防线预警机制',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                pendingCount == 0
                    ? '待办已清空，节奏保持稳定。'
                    : '还有 $pendingCount 项待处理微任务。',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => _setBatchMode(!_batchMode),
                icon: Icon(
                  _batchMode ? Icons.close_rounded : Icons.checklist_rounded,
                ),
                label: Text(_batchMode ? '退出批量' : '批量处理'),
              ),
            ],
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
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final isMobile = viewportWidth < 720;
    final isDesktop = viewportWidth >= 1200;
    final layout = isMobile
        ? 'mobile'
        : viewportWidth < 1200
        ? 'tablet'
        : 'desktop';

    return Scaffold(
      key: ValueKey(isMobile ? 'stitch-microtasks-mobile' : 'microtasks-page'),
      backgroundColor: AppWindowTones.canvas(context, AppWindowTone.neutral),
      appBar: isMobile && StitchMobileShellScope.isHosted(context)
          ? null
          : AppBar(
              title: Text(
                AppStrings.of(context, 'micro_title'),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              backgroundColor: Colors.transparent,
              elevation: 0,
              actions: [
                IconButton(
                  tooltip: AppStrings.of(context, 'common_refresh'),
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
          : LayoutBuilder(
              builder: (context, constraints) => ResponsivePageFrame(
                child: SingleChildScrollView(
                  key: ValueKey('microtasks-layout-$layout'),
                  padding: EdgeInsets.only(
                    top: 18,
                    bottom: _batchMode ? 148 : (isMobile ? 104 : 28),
                  ),
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildPageHeading(mobile: isMobile),
                      _buildMetrics(),
                      _buildQuickEntryCard(),
                      _buildSprintBanner(),
                      if (isDesktop)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 7, child: _buildTaskListColumn()),
                            const SizedBox(width: 16),
                            Expanded(flex: 3, child: _buildInsightsPanel()),
                          ],
                        )
                      else ...[
                        _buildTaskListColumn(),
                        const SizedBox(height: 8),
                        _buildInsightsPanel(),
                      ],
                    ],
                  ),
                ),
              ),
            ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: _batchMode
          ? _buildBatchActionBar(selectedCount, selectedPoints)
          : isMobile
          ? PressScale(
              child: FloatingActionButton.extended(
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
            )
          : null,
    );
  }

  Widget _buildBatchActionBar(int count, int points) {
    final scheme = Theme.of(context).colorScheme;
    final summary = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '已选 $count 项',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        Text(
          '可获 +$points ${_pointsUnit(context)}',
          style: TextStyle(
            color: scheme.primary,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
    final deleteButton = IconButton(
      tooltip: '删除所选',
      icon: Icon(Icons.delete_outline, color: scheme.error),
      onPressed: count == 0 ? null : _batchDelete,
    );
    final scheduleButton = OutlinedButton.icon(
      onPressed: count == 0 ? null : _batchSchedule,
      icon: const Icon(Icons.event_available_rounded, size: 17),
      label: const Text('集中安排'),
    );
    final completeButton = FilledButton.icon(
      onPressed: count == 0 ? null : _batchMarkComplete,
      icon: const Icon(Icons.check_rounded, size: 17),
      label: const Text('完成'),
    );

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.12),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: _isMobileViewport(context)
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Align(alignment: Alignment.centerLeft, child: summary),
                const SizedBox(height: 6),
                Row(
                  children: [
                    deleteButton,
                    const SizedBox(width: 4),
                    Expanded(child: scheduleButton),
                    const SizedBox(width: 8),
                    Expanded(child: completeButton),
                  ],
                ),
              ],
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                summary,
                const SizedBox(width: 20),
                deleteButton,
                const SizedBox(width: 4),
                scheduleButton,
                const SizedBox(width: 8),
                completeButton,
              ],
            ),
    );
  }

  Widget _buildMicroTaskBubble(MicroTask task) {
    final selected = _selected.contains(_taskKey(task));
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final scheme = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: task.done
            ? (isDark
                  ? scheme.onSurface.withValues(alpha: 0.04)
                  : scheme.onSurface.withValues(alpha: 0.03))
            : scheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: selected ? theme.colorScheme.primary : scheme.outline,
          width: selected ? 2 : 1,
        ),
        boxShadow: task.done || isDark
            ? []
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
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
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < 640) {
                  return _buildCompactMicroTaskBubble(task, selected, scheme);
                }
                return Row(
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
                              ? scheme.secondary.withValues(alpha: 0.12)
                              : theme.colorScheme.primary.withValues(
                                  alpha: 0.1,
                                ),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          task.done
                              ? Icons.check_circle_rounded
                              : Icons.radio_button_unchecked_rounded,
                          color: task.done
                              ? scheme.secondary
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
                                  color: scheme.onSurface.withValues(
                                    alpha: isDark ? 0.1 : 0.05,
                                  ),
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
                                        color:
                                            theme.colorScheme.onSurfaceVariant,
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
                                  color: scheme.onSurface.withValues(
                                    alpha: isDark ? 0.1 : 0.05,
                                  ),
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
                                      task.tag.trim().isEmpty
                                          ? '未分类'
                                          : task.tag,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color:
                                            theme.colorScheme.onSurfaceVariant,
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
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '+${_pointsFor(task)} ${_pointsUnit(context)}',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              color: task.done
                                  ? scheme.secondary
                                  : theme.colorScheme.primary,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              IconButton(
                                icon: Icon(
                                  Icons.edit_rounded,
                                  size: 20,
                                  color: scheme.onSurfaceVariant,
                                ),
                                onPressed: () =>
                                    _showEditMicroTaskDialog(context, task),
                                constraints: const BoxConstraints(),
                                padding: EdgeInsets.zero,
                              ),
                              const SizedBox(width: 12),
                              IconButton(
                                icon: Icon(
                                  Icons.delete_outline_rounded,
                                  size: 20,
                                  color: scheme.error,
                                ),
                                onPressed: () => _confirmDeleteOne(task),
                                constraints: const BoxConstraints(),
                                padding: EdgeInsets.zero,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCompactMicroTaskBubble(
    MicroTask task,
    bool selected,
    ColorScheme scheme,
  ) {
    final titleColor = task.done ? scheme.onSurfaceVariant : scheme.onSurface;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_batchMode)
              SizedBox(
                width: 44,
                height: 44,
                child: Checkbox(
                  value: selected,
                  onChanged: (_) => _toggleSelected(task),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
              )
            else
              IconButton(
                tooltip: task.done ? '标记未完成' : '标记完成',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 44,
                  height: 44,
                ),
                onPressed: () => _setDone(task, !task.done),
                icon: Icon(
                  task.done
                      ? Icons.check_circle_rounded
                      : Icons.circle_outlined,
                  color: task.done ? scheme.tertiary : scheme.onSurfaceVariant,
                  size: 21,
                ),
              ),
            const SizedBox(width: 6),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: titleColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        decoration: task.done
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 5,
                      runSpacing: 5,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _buildPriorityBadge(task),
                        _taskMetaChip(
                          Icons.access_time_rounded,
                          '${task.minutes} min',
                        ),
                        _taskMetaChip(
                          Icons.tag_rounded,
                          task.tag.trim().isEmpty ? '未分类' : task.tag,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (!_batchMode)
              PopupMenuButton<String>(
                tooltip: '任务操作',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 44,
                  height: 44,
                ),
                onSelected: (value) {
                  if (value == 'edit') _showEditMicroTaskDialog(context, task);
                  if (value == 'delete') _confirmDeleteOne(task);
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'edit', child: Text('编辑')),
                  PopupMenuItem(value: 'delete', child: Text('删除')),
                ],
                icon: const Icon(Icons.more_horiz_rounded),
              ),
          ],
        ),
        if (!_batchMode)
          Padding(
            padding: const EdgeInsets.only(left: 42, top: 4),
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                '+${_pointsFor(task)} ${_pointsUnit(context)}',
                style: TextStyle(
                  color: task.done ? scheme.tertiary : scheme.primary,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _taskMetaChip(IconData icon, String label) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(maxWidth: 150),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: scheme.onSurfaceVariant),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 10),
            ),
          ),
        ],
      ),
    );
  }
}

class _MicroTaskGroup {
  const _MicroTaskGroup({
    required this.title,
    required this.icon,
    required this.color,
    required this.tasks,
  });

  final String title;
  final IconData icon;
  final Color color;
  final List<MicroTask> tasks;
}
