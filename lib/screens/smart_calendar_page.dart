import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/mock_data_service.dart';
import '../utils/helpers.dart';
import '../utils/app_strings.dart';

/// 智能日程页面
class SmartCalendarPage extends StatefulWidget {
  const SmartCalendarPage({super.key});

  @override
  State<SmartCalendarPage> createState() => _SmartCalendarPageState();
}

class _SmartCalendarPageState extends State<SmartCalendarPage> {
  List<ScheduleEntry> _blocks = [];
  bool _isLoading = true;
  final _dataService = MockDataService.instance;

  static const double _hourHeight = 80.0;
  static const int _startHour = 8;
  static const int _endHour = 20;
  static const int _totalHours = _endHour - _startHour;
  static const double _totalHeight = _totalHours * _hourHeight;

  @override
  void initState() {
    super.initState();
    _loadSchedule();
  }

  Future<void> _loadSchedule() async {
    setState(() {
      _isLoading = true;
    });
    final entries = await _dataService.getScheduleEntries();
    if (!mounted) return;
    setState(() {
      _blocks = entries;
      _isLoading = false;
    });
  }

  double _calculateTopOffset(TimeOfDay time) {
    final double minutesFromStart =
        (time.hour - _startHour) * 60.0 + time.minute;
    return minutesFromStart / 60.0 * _hourHeight;
  }

  @override
  Widget build(BuildContext context) {
    final sortedBlocks = List<ScheduleEntry>.from(_blocks)
      ..sort((a, b) {
        final aMinutes = a.time.hour * 60 + a.time.minute;
        final bMinutes = b.time.hour * 60 + b.time.minute;
        return aMinutes.compareTo(bMinutes);
      });

    return Scaffold(
      appBar: AppBar(
        // 使用字典 Title
        title: Text(AppStrings.of(context, 'calendar_title')),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadSchedule),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              scrollDirection: Axis.vertical,
              child: SizedBox(
                width: MediaQuery.of(context).size.width,
                height: _totalHeight,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 60,
                      height: _totalHeight,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: List.generate(_totalHours, (i) {
                          return SizedBox(
                            height: _hourHeight,
                            child: Center(child: Text("${i + _startHour}:00")),
                          );
                        }),
                      ),
                    ),
                    Expanded(
                      child: SizedBox(
                        height: _totalHeight,
                        child: Stack(
                          children: [
                            ...List.generate(
                              _totalHours,
                              (i) => Positioned(
                                top: i * _hourHeight,
                                left: 0,
                                right: 0,
                                child: Container(
                                  height: _hourHeight,
                                  decoration: BoxDecoration(
                                    border: Border(
                                      top: BorderSide(
                                        color: Colors.grey.shade200,
                                        width: 1,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.teal.withAlpha((0.1 * 255).round()),
                                    Colors.teal.withAlpha((0.1 * 255).round()),
                                    Colors.orange.withAlpha(
                                      (0.1 * 255).round(),
                                    ),
                                    Colors.blue.withAlpha((0.1 * 255).round()),
                                  ],
                                ),
                              ),
                            ),
                            ...sortedBlocks.map((block) {
                              final top = _calculateTopOffset(block.time);
                              return Positioned(
                                top: top,
                                left: 8,
                                right: 8,
                                child: _buildScheduleBlock(
                                  block.title,
                                  block.height,
                                  block.color,
                                  block.tag,
                                  time: block.time,
                                  onDelete: () => _showDeleteDialog(block),
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.add),
        onPressed: () => _showAddDialog(context),
      ),
    );
  }

  void _showDeleteDialog(ScheduleEntry block) {
    showDialog(
      context: context,
      builder: (ctx2) => AlertDialog(
        title: Text(AppStrings.of(context, 'dialog_del_title')),
        content: Text(
          '${AppStrings.of(context, 'dialog_del_content')} "${block.title}"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx2).pop(),
            child: Text(AppStrings.of(context, 'btn_cancel')),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(ctx2).pop();
              await _dataService.removeScheduleEntry(block);
              if (mounted) {
                await _loadSchedule();
              }
            },
            child: Text(AppStrings.of(context, 'btn_delete')),
          ),
        ],
      ),
    );
  }

  void _showAddDialog(BuildContext context) {
    final titleCtrl = TextEditingController();
    final tagCtrl = TextEditingController();
    double height = 60;
    Color color = Colors.teal;
    TimeOfDay selectedTime = TimeOfDay.now();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setInner) => AlertDialog(
          // 使用统一的 Key: dialog_add_title
          title: Text(AppStrings.of(context, 'dialog_add_title')),
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
                  Text(AppStrings.of(context, 'label_duration')),
                  const SizedBox(width: 8),
                  DropdownButton<double>(
                    value: height,
                    items: const [
                      DropdownMenuItem(value: 40, child: Text('30')),
                      DropdownMenuItem(value: 60, child: Text('45')),
                      DropdownMenuItem(value: 80, child: Text('60')),
                      DropdownMenuItem(value: 120, child: Text('90')),
                    ],
                    onChanged: (v) {
                      if (v != null) setInner(() => height = v);
                    },
                  ),
                  const Spacer(),
                  DropdownButton<Color>(
                    value: color,
                    items: [
                      DropdownMenuItem(
                        value: Colors.teal,
                        child: Text(AppStrings.of(context, 'color_green')),
                      ),
                      DropdownMenuItem(
                        value: Colors.blue,
                        child: Text(AppStrings.of(context, 'color_blue')),
                      ),
                      DropdownMenuItem(
                        value: Colors.orange,
                        child: Text(AppStrings.of(context, 'color_orange')),
                      ),
                    ],
                    onChanged: (c) {
                      if (c != null) setInner(() => color = c);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(AppStrings.of(context, 'label_start_time')),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () async {
                      final t = await showTimePicker(
                        context: ctx2,
                        initialTime: selectedTime,
                        cancelText: AppStrings.of(context, 'btn_cancel'),
                        confirmText: AppStrings.of(context, 'btn_confirm'),
                      );
                      if (t != null) setInner(() => selectedTime = t);
                    },
                    child: Text(selectedTime.format(ctx2)),
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

                final newEntry = ScheduleEntry(
                  title: t,
                  tag: tg.isEmpty ? '一般' : tg,
                  height: height,
                  color: color,
                  time: selectedTime,
                );
                Navigator.of(ctx).pop();
                await _dataService.addScheduleEntry(newEntry);
                if (mounted) await _loadSchedule();
              },
              child: Text(AppStrings.of(context, 'btn_add')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScheduleBlock(
    String title,
    double height,
    Color color,
    String tag, {
    TimeOfDay? time,
    VoidCallback? onDelete,
  }) {
    final alphaColor = color.withAlpha((0.9 * 255).round());
    return Stack(
      children: [
        Container(
          constraints: BoxConstraints(minHeight: height),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: alphaColor,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              const BoxShadow(
                color: Colors.black12,
                blurRadius: 4,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.max,
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Icon(iconForTag(tag), color: Colors.white70),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  title,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            tag,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                            ),
                          ),
                        ),
                        if (time != null)
                          Text(
                            time.format(context),
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (onDelete != null)
          Positioned(
            right: -8,
            top: -8,
            child: SizedBox(
              width: 32,
              height: 32,
              child: IconButton(
                padding: EdgeInsets.zero,
                icon: const Icon(Icons.close, size: 16, color: Colors.white70),
                onPressed: onDelete,
              ),
            ),
          ),
      ],
    );
  }
}
