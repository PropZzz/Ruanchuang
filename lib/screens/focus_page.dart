import 'dart:async';

import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/app_services.dart';
import '../services/microtask_crystals/microtask_crystal_engine.dart';
import '../ui/app_theme.dart';
import '../utils/app_strings.dart';
import '../utils/helpers.dart';
import '../utils/mobile_feedback.dart';
import '../utils/schedule_occurrence.dart';
import '../widgets/workbench_surface.dart';

class FocusPage extends StatefulWidget {
  const FocusPage({super.key});

  @override
  State<FocusPage> createState() => _FocusPageState();
}

class _FocusPageState extends State<FocusPage> {
  EmotionType? _currentEmotion;
  EnergyStatus? _energyStatus;
  final _dataService = AppServices.dataService;

  ScheduleEntry? _currentTask;
  List<ScheduleEntry> _nextTasks = [];

  List<TimeCrystalRecommendation> _crystalRecs = [];
  bool _isRecsLoading = false;

  Timer? _timer;
  int _remainingSeconds = 0;
  bool _isTimerRunning = false;
  bool _isLoading = true;
  bool _careNoticeShown = false;

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

    try {
      final energyFuture = _dataService.getEnergyStatus();
      final now = TimeOfDay.now();
      final nowMinutes = now.hour * 60 + now.minute;
      final entriesFuture = _dataService.getScheduleEntries();

      final energy = await energyFuture;
      final emotion = await _dataService.getCurrentEmotion();
      _currentEmotion = emotion;
      final shouldShowCareNotice =
          emotion == EmotionType.fatigue || emotion == EmotionType.irritable;
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

      if (shouldShowCareNotice) {
        _showCareNotice();
      }

      unawaited(_loadCrystalRecommendations(entries, energy));
    } catch (e, st) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      MobileFeedback.showError(
        context,
        category: 'focus',
        message: 'load focus tasks failed',
        zhMessage: '暂时无法加载专注面板，请稍后重试。',
        enMessage: 'Unable to load the focus dashboard right now.',
        error: e,
        stackTrace: st,
      );
    }
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
      final planned = ((current.height / 80.0) * 60.0).round().clamp(
        1,
        24 * 60,
      );
      final remainingMinutes = (_remainingSeconds / 60.0).round().clamp(
        0,
        planned,
      );
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

    final waitDuration = taskStartTime.isAfter(now)
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
    final isWide = MediaQuery.of(context).size.width >= AppTheme.shellBreakpoint;
    final horizontalPadding = isWide ? 28.0 : 16.0;
    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.of(context, 'focus_title')),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadTasks),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1320),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      horizontalPadding,
                      12,
                      horizontalPadding,
                      16,
                    ),
                    child: isWide
                        // 修复：添加 crossAxisAlignment.stretch 给双列表提供安全边界高度，防止 Web 抛出无限高度异常
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                flex: 7,
                                child: ListView(
                                  padding: EdgeInsets.only(
                                    bottom:
                                        MediaQuery.of(
                                          context,
                                        ).padding.bottom +
                                        100,
                                  ),
                                  children: [
                                    _buildEnergyStatusCard(),
                                    const SizedBox(height: 18),
                                    _buildCurrentTaskCard(context),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 18),
                              Expanded(
                                flex: 5,
                                child: ListView(
                                  padding: EdgeInsets.only(
                                    bottom:
                                        MediaQuery.of(
                                          context,
                                        ).padding.bottom +
                                        100,
                                  ),
                                  children: [
                                    _buildNextTasksSection(),
                                    const SizedBox(height: 18),
                                    _buildCrystalSection(),
                                  ],
                                ),
                              ),
                            ],
                          )
                        : ListView(
                            padding: EdgeInsets.only(
                              bottom:
                                  MediaQuery.of(context).padding.bottom + 100,
                            ),
                            children: [
                              _buildEnergyStatusCard(),
                              const SizedBox(height: 18),
                              _buildCurrentTaskCard(context),
                              const SizedBox(height: 18),
                              _buildNextTasksSection(),
                              const SizedBox(height: 18),
                              _buildCrystalSection(),
                            ],
                          ),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildNextTasksSection() {
    return WorkbenchSurface(
      title: AppStrings.of(context, 'focus_header_next'),
      child: _nextTasks.isEmpty
          ? _buildHintText(AppStrings.of(context, 'focus_empty_task'))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: _nextTasks.map((task) {
                return _buildNextTaskItem(
                  '${task.time.format(context)} ${task.title}',
                  iconForTag(task.tag),
                  task.color,
                );
              }).toList(),
            ),
    );
  }

  Widget _buildCrystalSection() {
    return WorkbenchSurface(
      title: AppStrings.of(context, 'focus_time_crystal_title'),
      child: _isRecsLoading
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            )
          : _crystalRecs.isEmpty
          ? _buildHintText(AppStrings.of(context, 'focus_time_crystal_empty'))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: _crystalRecs.map((r) => _buildCrystalItem(r)).toList(),
            ),
    );
  }

  Widget _buildCrystalItem(TimeCrystalRecommendation r) {
    final theme = Theme.of(context);
    final compact = MobileFeedback.isNarrow(context, breakpoint: 680);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: compact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(children: [Icon(Icons.bubble_chart_outlined)]),
                  const SizedBox(height: 8),
                  Text(r.task.title),
                  const SizedBox(height: 4),
                  Text(
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
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: ElevatedButton(
                      onPressed: () async {
                        final entry = ScheduleEntry(
                          day: dateOnly(DateTime.now()),
                          title: r.task.title,
                          tag: r.task.tag.isEmpty ? 'micro' : r.task.tag,
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
                        AppStrings.of(context, 'focus_btn_one_click_insert'),
                      ),
                    ),
                  ),
                ],
              )
            : ListTile(
                leading: const Icon(Icons.bubble_chart_outlined),
                contentPadding: EdgeInsets.zero,
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
                      tag: r.task.tag.isEmpty ? 'micro' : r.task.tag,
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
                    AppStrings.of(context, 'focus_btn_one_click_insert'),
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildEnergyStatusCard() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final energy = _energyStatus;
    final emotion = _currentEmotion;
    return WorkbenchSurface(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(Icons.monitor_heart, color: scheme.primary, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "${AppStrings.of(context, 'focus_status_label')}${energy?.status ?? AppStrings.of(context, 'status_flow_value')}",
                  style: theme.textTheme.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (emotion != null)
                  Text(
                    '当前情绪：${emotion.label}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: emotion.color,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                Text(
                  energy?.description ??
                      AppStrings.of(context, 'status_flow_desc'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          WorkbenchMetric(
            label: '精力电量',
            value: "${energy?.batteryPercent ?? 85}%",
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentTaskCard(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final current = _currentTask;
    final hasUpcoming = _nextTasks.isNotEmpty;
    final canStart = current != null || hasUpcoming;

    final IconData displayIcon;
    final String displayTitle;
    if (current != null) {
      displayIcon = iconForTag(current.tag);
      displayTitle = current.title;
    } else if (hasUpcoming) {
      final next = _nextTasks.first;
      displayIcon = iconForTag(next.tag);
      displayTitle = '${next.time.format(context)} ${next.title}';
    } else {
      displayIcon = Icons.hourglass_empty;
      displayTitle = AppStrings.of(context, 'focus_empty_task');
    }

    return WorkbenchSurface(
      title: AppStrings.of(context, 'focus_header_current'),
      child: Column(
        children: [
          const SizedBox(height: 8),
          Icon(displayIcon, color: scheme.primary, size: 40),
          const SizedBox(height: 12),
          Text(
            displayTitle,
            style: theme.textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          if (current != null) ...[
            const SizedBox(height: 8),
            Text(
              "${AppStrings.of(context, 'focus_time_remaining')}${_formatDuration(_remainingSeconds)}",
              style: theme.textTheme.bodyLarge?.copyWith(
                color: scheme.onSurfaceVariant,
                fontFamily: 'monospace',
              ),
            ),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            alignment: WrapAlignment.center,
            children: [
              if (!_isTimerRunning)
                ElevatedButton.icon(
                  onPressed: canStart ? _startTimer : null,
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
                onPressed: current == null
                    ? null
                    : () {
                        _resetTimer();
                        _startNextTask();
                      },
                icon: const Icon(Icons.check),
                label: Text(AppStrings.of(context, 'btn_finish')),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNextTaskItem(String title, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(title)),
        ],
      ),
    );
  }

  Widget _buildHintText(String text) {
    return Text(
      text,
      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
    );
  }

  void _showCareNotice() {
    if (_careNoticeShown || !mounted) return;
    _careNoticeShown = true;

    final emotionLabel = _currentEmotion?.label ?? '未知';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 104),
          showCloseIcon: true,
          duration: const Duration(seconds: 5),
          content: Text('检测到当前$emotionLabel状态，建议先安排低压任务或休息 5 分钟。'),
          action: SnackBarAction(
            label: '查看建议',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  behavior: SnackBarBehavior.floating,
                  margin: EdgeInsets.fromLTRB(16, 0, 16, 104),
                  content: Text('可优先选择 5-10 分钟微任务，降低切换成本。'),
                ),
              );
            },
          ),
        ),
      );
  }
}
