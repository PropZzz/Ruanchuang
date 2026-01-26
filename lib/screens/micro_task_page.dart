import 'package:flutter/material.dart';
import '../models/models.dart';
import '../utils/app_strings.dart'; // 引入字典

class MicroTaskPage extends StatefulWidget {
  const MicroTaskPage({super.key});

  @override
  State<MicroTaskPage> createState() => _MicroTaskPageState();
}

class _MicroTaskPageState extends State<MicroTaskPage> {
  final List<MicroTask> _tasks = [
    MicroTask(title: '回复 HR 邮件', tag: '需电脑', minutes: 5),
    MicroTask(title: '电话确认需求', tag: '移动场景', minutes: 10),
    MicroTask(title: '整理桌面文件', tag: '低脑力', minutes: 15),
    MicroTask(title: '查看行业新闻', tag: '任意', minutes: 8),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppStrings.of(context, 'micro_title'))),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            color: Colors.orange.shade50,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    AppStrings.of(context, 'micro_ai_suggestion'),
                    style: const TextStyle(color: Colors.brown),
                  ),
                ),
                ElevatedButton(
                  onPressed: _fillQuickTasks,
                  child: Text(AppStrings.of(context, 'micro_btn_fill')),
                ),
              ],
            ),
          ),
          Expanded(
            child: GridView.count(
              crossAxisCount: 2,
              padding: const EdgeInsets.all(16),
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              children: _tasks.map((t) => _buildMicroTaskBubble(t)).toList(),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddMicroTaskDialog(context),
        label: Text(AppStrings.of(context, 'micro_btn_add')),
        icon: const Icon(Icons.add),
        backgroundColor: Colors.orange,
      ),
    );
  }

  void _fillQuickTasks() {
    setState(() {
      _tasks.addAll([
        MicroTask(title: '整理笔记', tag: '低脑力', minutes: 12),
        MicroTask(title: '回复客户简短问题', tag: '任意', minutes: 7),
      ]);
    });
  }

  void _showAddMicroTaskDialog(BuildContext context) {
    final titleCtrl = TextEditingController();
    final tagCtrl = TextEditingController();
    int minutes = 10;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
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
                      .map((v) => DropdownMenuItem(value: v, child: Text('$v')))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) minutes = v;
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
            onPressed: () {
              final t = titleCtrl.text.trim();
              final tg = tagCtrl.text.trim();
              if (t.isEmpty) return;
              setState(
                () => _tasks.add(
                  MicroTask(
                    title: t,
                    tag: tg.isEmpty ? '任意' : tg,
                    minutes: minutes,
                  ),
                ),
              );
              Navigator.of(ctx).pop();
            },
            child: Text(AppStrings.of(context, 'btn_add')),
          ),
        ],
      ),
    );
  }

  Widget _buildMicroTaskBubble(MicroTask task) {
    return GestureDetector(
      onLongPress: () {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(AppStrings.of(context, 'micro_dialog_del')),
            content: Text(
              '${AppStrings.of(context, 'dialog_del_content')} "${task.title}"?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(AppStrings.of(context, 'btn_cancel')),
              ),
              ElevatedButton(
                onPressed: () {
                  setState(() => _tasks.remove(task));
                  Navigator.of(ctx).pop();
                },
                child: Text(AppStrings.of(context, 'btn_delete')),
              ),
            ],
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: task.done ? Colors.grey.shade200 : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.orange.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.orange.withAlpha((0.1 * 255).round()),
              blurRadius: 10,
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              task.done ? Icons.check_circle : Icons.task_alt,
              color: Colors.orange,
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
                const Icon(Icons.access_time, size: 12, color: Colors.grey),
                Text(
                  ' ${task.minutes} ${AppStrings.of(context, 'micro_card_min')} | ${task.tag}',
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(
                  onPressed: () {
                    setState(() => task.done = !task.done);
                  },
                  child: Text(
                    task.done
                        ? AppStrings.of(context, 'btn_incomplete')
                        : AppStrings.of(context, 'btn_finish'),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () {
                    setState(() => _tasks.remove(task));
                  },
                  icon: const Icon(Icons.delete, size: 18),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
