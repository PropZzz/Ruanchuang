import 'dart:async';
import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/mock_data_service.dart';
import '../utils/helpers.dart';
import '../utils/app_strings.dart'; // 引入字典

class FocusPage extends StatefulWidget {
  const FocusPage({super.key});

  @override
  State<FocusPage> createState() => _FocusPageState();
}

class _FocusPageState extends State<FocusPage> {
  final _dataService = MockDataService.instance;

  ScheduleEntry? _currentTask;
  List<ScheduleEntry> _nextTasks = [];

  Timer? _timer;
  int _remainingSeconds = 0;
  bool _isTimerRunning = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTasks();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadTasks() async {
    setState(() {
      _isLoading = true;
    });

    final now = TimeOfDay.now();
    final nowMinutes = now.hour * 60 + now.minute;
    final allEntries = await _dataService.getScheduleEntries();

    if (!mounted) return;

    allEntries.sort((a, b) {
      final aMin = a.time.hour * 60 + a.time.minute;
      final bMin = b.time.hour * 60 + b.time.minute;
      return aMin.compareTo(bMin);
    });

    ScheduleEntry? current;
    final List<ScheduleEntry> upcoming = [];

    for (final e in allEntries) {
      final start = e.time.hour * 60 + e.time.minute;
      final duration = (e.height / 80.0) * 60.0;
      final end = (start + duration).toInt();
      if (start <= nowMinutes && nowMinutes < end) {
        current = e;
      } else if (start > nowMinutes) {
        upcoming.add(e);
      }
    }

    setState(() {
      _currentTask = current;
      if (current != null) {
        final start = current.time.hour * 60 + current.time.minute;
        final duration = (current.height / 80.0) * 60.0;
        final end = (start + duration).toInt();
        _remainingSeconds = (end - nowMinutes) * 60;
        _nextTasks = upcoming;
      } else {
        _remainingSeconds = 0;
        _nextTasks = upcoming;
      }
      _isLoading = false;
    });
  }

  void _startTimer() {
    if (_isTimerRunning) return;

    if (_currentTask == null && _nextTasks.isNotEmpty) {
      final next = _nextTasks.first;
      final now = DateTime.now();
      final taskStart = DateTime(
        now.year,
        now.month,
        now.day,
        next.time.hour,
        next.time.minute,
      );
      final wait = taskStart.isAfter(now)
          ? taskStart.difference(now)
          : Duration.zero;

      final msg = AppStrings.of(
        context,
        'focus_snack_start',
        params: {'min': wait.inMinutes.toString(), 'task': next.title},
      );
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

      Future.delayed(wait, () {
        if (!mounted) return;
        setState(() {
          _currentTask = next;
          _nextTasks = _nextTasks.skip(1).toList();
          final durationInMinutes = (_currentTask!.height / 80.0) * 60.0;
          _remainingSeconds = durationInMinutes.toInt() * 60;
        });
        _startTimer();
      });
      return;
    }

    if (_remainingSeconds == 0) return;

    _isTimerRunning = true;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        if (_remainingSeconds > 0) {
          _remainingSeconds--;
        } else {
          _timer?.cancel();
          _isTimerRunning = false;
          _startNextTask();
        }
      });
    });
  }

  void _pauseTimer() {
    if (!_isTimerRunning) return;
    _timer?.cancel();
    setState(() {
      _isTimerRunning = false;
    });
  }

  void _resetTimer() {
    _timer?.cancel();
    setState(() {
      _isTimerRunning = false;
      if (_currentTask != null) {
        final durationInMinutes = (_currentTask!.height / 80.0) * 60.0;
        _remainingSeconds = durationInMinutes.toInt() * 60;
      } else {
        _remainingSeconds = 0;
      }
    });
  }

  void _startNextTask() {
    if (_nextTasks.isEmpty) {
      setState(() {
        _currentTask = null;
        _remainingSeconds = 0;
      });
      return;
    }

    final nextTask = _nextTasks.first;
    final now = DateTime.now();
    final taskStartTime = DateTime(
      now.year,
      now.month,
      now.day,
      nextTask.time.hour,
      nextTask.time.minute,
    );

    Duration waitDuration = taskStartTime.isAfter(now)
        ? taskStartTime.difference(now)
        : Duration.zero;

    final msg = AppStrings.of(
      context,
      'focus_snack_upcoming',
      params: {
        'min': waitDuration.inMinutes.toString(),
        'task': nextTask.title,
      },
    );
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

    Future.delayed(waitDuration, () {
      if (!mounted) return;
      setState(() {
        _currentTask = nextTask;
        _nextTasks = _nextTasks.skip(1).toList();
        _resetTimer();
        _startTimer();
      });
    });
  }

  String _formatDuration(int totalSeconds) {
    final duration = Duration(seconds: totalSeconds);
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return "${duration.inHours > 0 ? '${duration.inHours}:' : ''}$minutes:$seconds";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.of(context, 'focus_title')),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadTasks),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildEnergyStatusCard(),
                  const SizedBox(height: 24),
                  Text(
                    AppStrings.of(context, 'focus_header_current'),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildCurrentTaskCard(context),
                  const SizedBox(height: 24),
                  Text(
                    AppStrings.of(context, 'focus_header_next'),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      itemCount: _nextTasks.length,
                      itemBuilder: (context, index) {
                        final task = _nextTasks[index];
                        return _buildNextTaskItem(
                          '${task.time.format(context)} ${task.title}',
                          iconForTag(task.tag),
                          task.color,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildEnergyStatusCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFE0F2F1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.teal.shade200),
      ),
      child: Row(
        children: [
          const Icon(Icons.monitor_heart, color: Colors.teal, size: 32),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 修改点：使用字典中的状态文案
              Text(
                "${AppStrings.of(context, 'focus_status_label')}${AppStrings.of(context, 'status_flow_value')}",
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              Text(
                AppStrings.of(context, 'status_flow_desc'),
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
          const Spacer(),
          const Chip(label: Text("🔋 85%"), backgroundColor: Colors.white),
        ],
      ),
    );
  }

  Widget _buildCurrentTaskCard(BuildContext context) {
    if (_currentTask == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Center(
            child: Text(
              AppStrings.of(context, 'focus_empty_task'),
              style: const TextStyle(fontSize: 18, color: Colors.grey),
            ),
          ),
        ),
      );
    }

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      color: _currentTask!.color,
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            Icon(iconForTag(_currentTask!.tag), color: Colors.white, size: 48),
            const SizedBox(height: 16),
            Text(
              _currentTask!.title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              "${AppStrings.of(context, 'focus_time_remaining')}${_formatDuration(_remainingSeconds)}",
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 16,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                if (!_isTimerRunning)
                  ElevatedButton.icon(
                    onPressed: _startTimer,
                    icon: const Icon(Icons.play_arrow),
                    label: Text(AppStrings.of(context, 'btn_start')),
                  )
                else
                  ElevatedButton.icon(
                    onPressed: _pauseTimer,
                    icon: const Icon(Icons.pause),
                    label: Text(AppStrings.of(context, 'btn_pause')),
                  ),
                OutlinedButton.icon(
                  onPressed: () {
                    _resetTimer();
                    _startNextTask();
                  },
                  icon: const Icon(Icons.check, color: Colors.white),
                  label: Text(
                    AppStrings.of(context, 'btn_finish'),
                    style: const TextStyle(color: Colors.white),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.white),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNextTaskItem(String title, IconData icon, Color color) {
    return Card(
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(title),
      ),
    );
  }
}
