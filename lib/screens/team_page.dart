import 'package:flutter/material.dart';
import '../models/models.dart';
import '../utils/app_strings.dart'; // 引入字典

class TeamPage extends StatefulWidget {
  const TeamPage({super.key});

  @override
  State<TeamPage> createState() => _TeamPageState();
}

class _TeamPageState extends State<TeamPage> {
  final List<TeamTask> _teamTasks = [
    TeamTask(
      name: '李一诺',
      role: 'PM',
      task: '0.5.1 文档修订',
      progress: 0.9,
      isHighEnergy: true,
    ),
    TeamTask(
      name: '宋子谦',
      role: 'Dev',
      task: 'Transformer 模型调试',
      progress: 0.6,
      isHighEnergy: true,
    ),
    TeamTask(
      name: '杨子翔',
      role: 'Dev',
      task: '后端 API 联调',
      progress: 0.4,
      isHighEnergy: false,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.of(context, 'team_title')),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showAddTaskDialog(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            AppStrings.of(context, 'team_rec_title'),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue.shade100),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(Icons.stars, color: Colors.amber),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(AppStrings.of(context, 'team_best_time')),
                    ),
                    ElevatedButton(
                      onPressed: () {},
                      child: Text(AppStrings.of(context, 'team_btn_book')),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  AppStrings.of(context, 'team_reason'),
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: Text(
                  AppStrings.of(context, 'team_track_title'),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ),
              ElevatedButton.icon(
                onPressed: () => _showAddTaskDialog(context),
                icon: const Icon(Icons.add),
                label: Text(AppStrings.of(context, 'team_btn_add_task')),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ..._teamTasks.map((t) => _buildTeamMemberStatus(t)),
        ],
      ),
    );
  }

  void _showAddTaskDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    final roleCtrl = TextEditingController();
    final taskCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    double progress = 0.0;
    bool isHigh = false;
    DateTime? due;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setInner) => AlertDialog(
          title: Text(AppStrings.of(context, 'team_dialog_add')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: InputDecoration(
                    labelText: AppStrings.of(context, 'team_label_name'),
                  ),
                ),
                TextField(
                  controller: roleCtrl,
                  decoration: InputDecoration(
                    labelText: AppStrings.of(context, 'team_label_role'),
                  ),
                ),
                TextField(
                  controller: taskCtrl,
                  decoration: InputDecoration(
                    labelText: AppStrings.of(context, 'team_label_task'),
                  ),
                ),
                TextField(
                  controller: descCtrl,
                  decoration: InputDecoration(
                    labelText: AppStrings.of(context, 'label_desc'),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(AppStrings.of(context, 'team_label_progress')),
                    Expanded(
                      child: Slider(
                        value: progress,
                        onChanged: (v) => setInner(() => progress = v),
                        divisions: 10,
                      ),
                    ),
                    Text('${(progress * 100).round()}%'),
                  ],
                ),
                Row(
                  children: [
                    Text(AppStrings.of(context, 'team_label_high_energy')),
                    Checkbox(
                      value: isHigh,
                      onChanged: (v) => setInner(() => isHigh = v ?? false),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Text(AppStrings.of(context, 'team_label_due')),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () async {
                        final d = await showDatePicker(
                          context: ctx2,
                          initialDate: DateTime.now(),
                          firstDate: DateTime.now().subtract(
                            const Duration(days: 365),
                          ),
                          lastDate: DateTime.now().add(
                            const Duration(days: 365),
                          ),
                          // 日期选择器的按钮已经在 main.dart 全局配置，无需在此重复配置
                        );
                        if (d != null) setInner(() => due = d);
                      },
                      child: Text(
                        due == null
                            ? AppStrings.of(context, 'btn_add')
                            : '${due!.toLocal()}'.split(' ')[0],
                      ),
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
              onPressed: () {
                final name = nameCtrl.text.trim();
                final task = taskCtrl.text.trim();
                if (name.isEmpty || task.isEmpty) return;
                setState(() {
                  _teamTasks.add(
                    TeamTask(
                      name: name,
                      role: roleCtrl.text,
                      task: task,
                      progress: progress,
                      isHighEnergy: isHigh,
                      due: due,
                    ),
                  );
                });
                Navigator.of(ctx).pop();
              },
              child: Text(AppStrings.of(context, 'btn_add')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTeamMemberStatus(TeamTask t) {
    final displayName = t.role.isNotEmpty ? '${t.name} (${t.role})' : t.name;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          child: Text(t.name.isNotEmpty ? t.name.substring(0, 1) : '?'),
        ),
        title: Text(displayName),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${AppStrings.of(context, 'team_card_ongoing')} ${t.task}'),
            if (t.due != null)
              Text(
                '${AppStrings.of(context, 'team_card_due')} ${t.due!.toLocal()}'
                    .split(' ')[0],
              ),
            const SizedBox(height: 4),
            LinearProgressIndicator(value: t.progress),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.bolt,
              color: t.isHighEnergy ? Colors.green : Colors.grey,
            ),
            IconButton(
              onPressed: () => setState(() => _teamTasks.remove(t)),
              icon: const Icon(Icons.delete),
            ),
          ],
        ),
      ),
    );
  }
}
