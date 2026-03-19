import 'dart:async';

import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/app_services.dart';
import '../services/microtask_crystals/microtask_crystal_engine.dart';
import '../utils/app_strings.dart';
import '../utils/helpers.dart';
import '../utils/schedule_occurrence.dart';

class FocusPage extends StatefulWidget {
  const FocusPage({super.key});

  @override
  State<FocusPage> createState() => _FocusPageState();
}

class _FocusPageState extends State<FocusPage> {
  final _dataService = AppServices.dataService;

  EnergyStatus? _energyStatus;
  ScheduleEntry? _currentTask;
  List<ScheduleEntry> _nextTasks = [];

  List<TimeCrystalRecommendation> _crystalRecs = [];
  bool _isRecsLoading = false;

  Timer? _timer;
  int _remainingSeconds = 0;
  bool _isTimerRunning = false;
  bool _isLoading = true;

  String? _activeTaskId;

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

  List<TimeWindow> _defaultWindows() {
    return const [
      TimeWindow(
        start: TimeOfDay(hour: 8, minute: 0),
        end: TimeOfDay(hour: 12, minute: 0),
      ),
      TimeWindow(
        start: TimeOfDay(hour: 13, minute: 30),
        end: TimeOfDay(hour: 18, minute: 30),
      ),
    ];
  }

  EnergyTier _tierFromBattery(int batteryPercent) {
    final p = batteryPercent.clamp(0, 100);
    if (p < 20) return EnergyTier.veryLow;
    if (p < 40) return EnergyTier.low;
    if (p < 60) return EnergyTier.medium;
    if (p < 80) return EnergyTier.high;
    return EnergyTier.veryHigh;
  }

  String _taskIdFor(ScheduleEntry e) {
    final id = e.id;
    if (id != null && id.isNotEmpty) return id;
    return 'focus_${e.title}_${e.time.hour}_${e.time.minute}';
  }

  void _logStart(ScheduleEntry e) {
    final taskId = _taskIdFor(e);
    if (_activeTaskId == taskId) return;
    _activeTaskId = taskId;

    final planned = ((e.height / 80.0) * 60.0).round().clamp(1, 24 * 60);
    unawaited(
      _dataService.logTaskEvent(
        TaskEvent(
          id: 'evt_start_${DateTime.now().microsecondsSinceEpoch}_$taskId',
          taskId: taskId,
          title: e.title,
          tag: e.tag,
          load: e.load,
          at: DateTime.now(),
          type: TaskEventType.start,
          plannedMinutes: planned,
          energy: _energyStatus == null
              ? null
              : _tierFromBattery(_energyStatus!.batteryPercent),
        ),
      ),
    );
  }

  void _logComplete(ScheduleEntry e, {required int actualMinutes}) {
    final taskId = _taskIdFor(e);
    final planned = ((e.height / 80.0) * 60.0).round().clamp(1, 24 * 60);
    unawaited(
      _dataService.logTaskEvent(
        TaskEvent(
          id: 'evt_done_${DateTime.now().microsecondsSinceEpoch}_$taskId',
          taskId: taskId,
          title: e.title,
          tag: e.tag,
          load: e.load,
          at: DateTime.now(),
          type: TaskEventType.complete,
          plannedMinutes: planned,
          actualMinutes: actualMinutes.clamp(1, 24 * 60),
          energy: _energyStatus == null
              ? null
              : _tierFromBattery(_energyStatus!.batteryPercent),
        ),
      ),
    );
    _activeTaskId = null;
  }

  Future<void> _loadCrystalRecommendations(
    List<ScheduleEntry> schedule,
    EnergyStatus energy,
  ) async {
    if (_isRecsLoading) return;

    setState(() {
      _isRecsLoading = true;
    });

    final microTasks = await _dataService.getMicroTasks();
    if (!mounted) return;

    final recs = AppServices.microTaskCrystalEngine.recommend(
      schedule: schedule,
      microTasks: microTasks,
      windows: _defaultWindows(),
      energy: _tierFromBattery(energy.batteryPercent),
      now: TimeOfDay.now(),
      maxRecommendations: 4,
    );

    setState(() {
      _crystalRecs = recs;
      _isRecsLoading = false;
    });
  }

  Future<void> _loadTasks() async {
    setState(() {
      _isLoading = true;
    });

    final energyFuture = _dataService.getEnergyStatus();
    final now = TimeOfDay.now();
    final nowMinutes = now.hour * 60 + now.minute;
    final entriesFuture = _dataService.getScheduleEntries();

    final energy = await energyFuture;
    final allEntries = await entriesFuture;

    if (!mounted) return;

    final today = dateOnly(DateTime.now());
    final entries = entriesForDay(day: today, allEntries: allEntries);

    entries.sort((a, b) {
      final aMin = a.time.hour * 60 + a.time.minute;
      final bMin = b.time.hour * 60 + b.time.minute;
      return aMin.compareTo(bMin);
    });

    ScheduleEntry? current;
    final List<ScheduleEntry> upcoming = [];

    for (final e in entries) {
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
      _energyStatus = energy;
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

    unawaited(_loadCrystalRecommendations(entries, energy));
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
      final wait = taskStart.isAfter(now) ? taskStart.difference(now) : Duration.zero;

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

    if (_currentTask != null) {
      _logStart(_currentTask!);
    }

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
    final current = _currentTask;
    if (current != null) {
      final planned = ((current.height / 80.0) * 60.0).round().clamp(1, 24 * 60);
      final remainingMinutes = (_remainingSeconds / 60.0).round().clamp(0, planned);
      final actual = (planned - remainingMinutes).clamp(1, planned);
      _logComplete(current, actualMinutes: actual);
    }

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

    final waitDuration = taskStartTime.isAfter(now) ? taskStartTime.difference(now) : Duration.zero;

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
    final theme = Theme.of(context);
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
                  Expanded(
                    child: ListView(
                      children: [
                        Text(
                          AppStrings.of(context, 'focus_header_next'),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (_nextTasks.isEmpty)
                          Text(
                            AppStrings.of(context, 'focus_empty_task'),
                            style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                          )
                        else
                          ..._nextTasks.map((task) {
                            return _buildNextTaskItem(
                              '${task.time.format(context)} ${task.title}',
                              iconForTag(task.tag),
                              task.color,
                            );
                          }),
                        const SizedBox(height: 16),
                        Text(
                          AppStrings.of(context, 'focus_time_crystal_title'),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (_isRecsLoading)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Center(child: CircularProgressIndicator()),
                          )
                        else if (_crystalRecs.isEmpty)
                          Text(
                            AppStrings.of(context, 'focus_time_crystal_empty'),
                            style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                          )
                        else
                          ..._crystalRecs.map((r) {
                            return Card(
                              child: ListTile(
                                leading: const Icon(Icons.bubble_chart_outlined),
                                title: Text(r.task.title),
                                subtitle: Text(
                                  AppStrings.of(
                                    context,
                                    'focus_time_crystal_subtitle',
                                    params: {
                                      'start': r.crystal.start.format(context),
                                      'minutes': r.crystal.minutes.toString(),
                                      'bucket': r.crystal.bucket,
                                      'taskMinutes': r.task.minutes.toString(),
                                    },
                                  ),
                                ),
                                trailing: ElevatedButton(
                                  onPressed: () async {
                                    final entry = ScheduleEntry(
                                      day: dateOnly(DateTime.now()),
                                      title: r.task.title,
                                      tag: r.task.tag.isEmpty
                                          ? 'Micro Task'
                                          : r.task.tag,
                                      height: (r.task.minutes / 60.0) * 80.0,
                                      color: theme.colorScheme.tertiary,
                                      time: r.crystal.start,
                                    );
                                    await _dataService.addScheduleEntry(entry);
                                    await _dataService.removeMicroTask(r.task);
                                    if (mounted) {
                                      await _loadTasks();
                                    }
                                  },
                                  child: Text(
                                    AppStrings.of(
                                      context,
                                      'focus_btn_one_click_insert',
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildEnergyStatusCard() {
    final theme = Theme.of(context);
    final energy = _energyStatus;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.primary),
      ),
      child: Row(
        children: [
          Icon(Icons.monitor_heart, color: theme.colorScheme.primary, size: 32),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "${AppStrings.of(context, 'focus_status_label')}${energy?.status ?? AppStrings.of(context, 'status_flow_value')}",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
              Text(
                energy?.description ?? AppStrings.of(context, 'status_flow_desc'),
                style: TextStyle(fontSize: 12, color: theme.colorScheme.onPrimaryContainer.withOpacity(0.7)),
              ),
            ],
          ),
          const Spacer(),
          Chip(
            backgroundColor: theme.colorScheme.surface,
            label: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.battery_full, size: 16, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Text("${energy?.batteryPercent ?? 85}%"),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentTaskCard(BuildContext context) {
    final theme = Theme.of(context);
    if (_currentTask == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Center(
            child: Text(
              AppStrings.of(context, 'focus_empty_task'),
              style: TextStyle(fontSize: 18, color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ),
      );
    }

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      color: theme.colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            Icon(iconForTag(_currentTask!.tag), color: theme.colorScheme.onSecondaryContainer, size: 48),
            const SizedBox(height: 16),
            Text(
              _currentTask!.title,
              style: TextStyle(
                color: theme.colorScheme.onSecondaryContainer,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              "${AppStrings.of(context, 'focus_time_remaining')}${_formatDuration(_remainingSeconds)}",
              style: TextStyle(
                color: theme.colorScheme.onSecondaryContainer.withOpacity(0.7),
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
                  icon: Icon(Icons.check, color: theme.colorScheme.onSecondaryContainer),
                  label: Text(
                    AppStrings.of(context, 'btn_finish'),
                    style: TextStyle(color: theme.colorScheme.onSecondaryContainer),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: theme.colorScheme.onSecondaryContainer),
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
