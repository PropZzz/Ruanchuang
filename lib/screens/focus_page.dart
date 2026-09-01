import 'dart:async';

import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/app_services.dart';
import '../services/microtask_crystals/microtask_crystal_engine.dart';
import '../theme/app_theme.dart';
import '../utils/app_strings.dart';
import '../utils/helpers.dart';
import '../utils/mobile_feedback.dart';
import '../utils/schedule_occurrence.dart';
import '../widgets/energy_status_card.dart';
import '../widgets/focus_task_card.dart';
import '../widgets/mini_timeline.dart';
import '../widgets/responsive_card_grid.dart';
import '../widgets/responsive_page_frame.dart';

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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: AppWindowTones.canvas(context, AppWindowTone.neutral),
      appBar: null,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: ResponsivePageFrame(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(0, 22, 0, 40),
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                AppStrings.of(context, 'focus_today_label'),
                                style: theme.textTheme.bodyMedium,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                AppStrings.of(context, 'focus_today'),
                                style: theme.textTheme.displaySmall,
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: AppStrings.of(context, 'btn_check'),
                          onPressed: _loadTasks,
                          icon: const Icon(Icons.refresh_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    ResponsiveCardGrid(
                      children: [
                        _buildCurrentTaskCard(context),
                        _buildEnergyStatusCard(),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildRhythmPanel(theme),
                    const SizedBox(height: 12),
                    _buildPlanningPanel(theme),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildRhythmPanel(ThemeData theme) {
    // Conflict and team-window APIs are not part of the FocusPage data load;
    // keep the summary truthful until those services provide real values.
    const conflictCount = 0;
    const teamCount = 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MiniTimeline(
          title: AppStrings.of(context, 'focus_next_four_hours'),
          actionLabel: AppStrings.of(context, 'focus_view_calendar'),
          onAction: () {},
          segments: [
            theme.colorScheme.tertiary.withValues(alpha: 0.35),
            theme.colorScheme.secondary.withValues(alpha: 0.55),
            theme.colorScheme.outline.withValues(alpha: 0.65),
            theme.colorScheme.tertiary.withValues(alpha: 0.28),
          ],
        ),
        const SizedBox(height: 12),
        ResponsiveCardGrid(
          children: [
            _buildSummaryTile(
              theme,
              Icons.route_outlined,
              AppStrings.of(context, 'focus_rescue_title'),
              conflictCount > 0
                  ? '${AppStrings.of(context, 'focus_attention')} $conflictCount'
                  : AppStrings.of(context, 'focus_clear'),
              conflictCount > 0
                  ? theme.colorScheme.error
                  : theme.colorScheme.tertiary,
            ),
            _buildSummaryTile(
              theme,
              Icons.people_outline_rounded,
              AppStrings.of(context, 'focus_team_window'),
              teamCount > 0
                  ? '15:00 · $teamCount ${AppStrings.of(context, 'focus_people_free')}'
                  : AppStrings.of(context, 'focus_no_window'),
              theme.colorScheme.primary,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSummaryTile(
    ThemeData theme,
    IconData icon,
    String title,
    String value,
    Color accent,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: accent),
            const SizedBox(height: 8),
            Text(title, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 4),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: accent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlanningPanel(ThemeData theme) {
    return Card(
      elevation: 0,
      color: theme.colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle(
              context,
              AppStrings.of(context, 'focus_header_next'),
            ),
            const SizedBox(height: 8),
            if (_nextTasks.isEmpty)
              _buildHintText(AppStrings.of(context, 'focus_empty_task'))
            else
              ..._nextTasks.map((task) {
                return _buildNextTaskItem(
                  '${task.time.format(context)} ${task.title}',
                  iconForTag(task.tag),
                  task.color,
                );
              }),
            const SizedBox(height: 16),
            _buildSectionTitle(
              context,
              AppStrings.of(context, 'focus_time_crystal_title'),
            ),
            const SizedBox(height: 8),
            if (_isRecsLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_crystalRecs.isEmpty)
              _buildHintText(AppStrings.of(context, 'focus_time_crystal_empty'))
            else
              ..._crystalRecs.map((r) => _buildCrystalItem(r)),
          ],
        ),
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
    return EnergyStatusCard(energy: _energyStatus, emotion: _currentEmotion);
  }

  Widget _buildCurrentTaskCard(BuildContext context) {
    return FocusTaskCard(
      task: _currentTask,
      remainingSeconds: _remainingSeconds,
      isRunning: _isTimerRunning,
      onStart: _startTimer,
      onPause: _pauseTimer,
      onFinish: () {
        _resetTimer();
        _startNextTask();
      },
      onRefresh: () {
        _loadTasks();
      },
    );
  }

  Widget _buildNextTaskItem(String title, IconData icon, Color color) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(title),
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: 0.3,
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
