// lib/screens/smart_calendar_page.dart
import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/app_services.dart';
import '../services/composite_data_service.dart';
import '../services/remote_data_service.dart';
import '../services/ics/ics_bridge.dart';
import '../services/ics/ics_codec.dart';
import '../services/ics/ics_file_saver.dart';
import '../services/emotion/emotion_policy.dart';
import '../services/scheduling/schedule_rescue.dart';
import '../services/scheduling/schedule_rescue_persistence.dart';
import '../theme/app_theme.dart';
import '../utils/helpers.dart';
import '../utils/app_strings.dart';
import '../utils/service_failure_message.dart';
import '../utils/mobile_feedback.dart';
import '../utils/schedule_occurrence.dart';
import '../widgets/emotion_quick_checkin_card.dart';
import '../widgets/rescue_summary.dart';
import '../widgets/rescue_plan_comparison.dart';
import '../widgets/responsive_page_frame.dart';
import '../widgets/press_scale.dart';
import '../widgets/schedule_timeline.dart';
import '../widgets/calendar/calendar_controls.dart';
import '../widgets/calendar/calendar_ics_import_form.dart';
import '../widgets/calendar/calendar_labels.dart';
import '../widgets/calendar/calendar_status_panels.dart';
import '../widgets/calendar/calendar_navigation.dart';
import '../widgets/stitch_mobile_scaffold.dart';
import '../widgets/urgent_task_dialog.dart';
import '../widgets/add_schedule_entry_dialog.dart';
import '../widgets/workbench_surface.dart';
import 'emotion_page.dart';
import 'goals_page.dart';
import 'integrations_page.dart';
import 'main_screen.dart';

enum _CalendarMode { manual, smart }

enum _EntryStatus { notStarted, inProgress, completed, overdue }

class SmartCalendarPage extends StatefulWidget {
  const SmartCalendarPage({super.key, this.initialDay});

  final DateTime? initialDay;

  @override
  State<SmartCalendarPage> createState() => _SmartCalendarPageState();
}

class _SmartCalendarPageState extends State<SmartCalendarPage> {
  List<ScheduleEntry> _blocks = [];
  bool _isLoading = true;
  bool _hasLoadedOnce = false;
  Object? _loadError;
  Map<String, _EntryStatus> _statusByTaskId = const {};

  _CalendarMode _mode = _CalendarMode.manual;
  ScheduleTimelineView _view = ScheduleTimelineView.day;
  final Set<ScheduleTimelineField> _visibleFields = {
    ScheduleTimelineField.time,
    ScheduleTimelineField.tag,
    ScheduleTimelineField.status,
    ScheduleTimelineField.reminder,
  };
  late DateTime _selectedDay;

  final _dataService = AppServices.dataService;

  ScheduleRescuePersistence get _rescuePersistence => ScheduleRescuePersistence(
    upsert: _dataService.addScheduleEntry,
    remove: _dataService.removeScheduleEntry,
  );

  List<PlanTask> _smartTasks = const [];
  PlanTask? _urgentInserted;
  ScheduleRescueOption? _acceptedRescue;
  List<ScheduleEntry>? _rescueUndoBlocks;

  static const int _startHour = 8;
  static const int _endHour = 20;

  @override
  void initState() {
    super.initState();
    _selectedDay = dateOnly(widget.initialDay ?? DateTime.now());
    _loadSchedule();
  }

  Future<void> _loadSchedule({bool preserveLoading = false}) async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });

    try {
      if (_mode == _CalendarMode.manual) {
        final entries = await _dataService.getScheduleEntries();
        final now = DateTime.now();
        final viewDay = dateOnly(_selectedDay);
        final events = await _dataService.getTaskEvents(
          viewDay,
          viewDay.add(const Duration(days: 1)),
        );

        final visible = entriesForDay(day: viewDay, allEntries: entries);

        final today = dateOnly(now);
        final isToday = sameDay(viewDay, today);
        final status = isToday
            ? _computeStatus(entries: visible, events: events, now: now)
            : const <String, _EntryStatus>{};
        if (!mounted) return;
        setState(() {
          _blocks = entries;
          _statusByTaskId = status;
          _hasLoadedOnce = true;
          _isLoading = preserveLoading;
        });
        final todayEntries = entriesForDay(day: today, allEntries: entries);
        await AppServices.reminderService.rescheduleDay(
          day: today,
          entries: todayEntries,
        );

        return;
      }

      await _loadSmartSchedule(preserveLoading: preserveLoading);
    } catch (e, st) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = e;
      });
      AppServices.logStore.error(
        'schedule',
        'load schedule failed',
        error: e,
        stackTrace: st,
      );
    }
  }

  EnergyTier _tierFromBattery(int batteryPercent) {
    final p = batteryPercent.clamp(0, 100);
    if (p < 20) return EnergyTier.veryLow;
    if (p < 40) return EnergyTier.low;
    if (p < 60) return EnergyTier.medium;
    if (p < 80) return EnergyTier.high;
    return EnergyTier.veryHigh;
  }

  Map<String, _EntryStatus> _computeStatus({
    required List<ScheduleEntry> entries,
    required List<TaskEvent> events,
    required DateTime now,
  }) {
    final completed = <String>{};

    for (final e in events) {
      if (e.type == TaskEventType.complete) completed.add(e.taskId);
    }

    final out = <String, _EntryStatus>{};
    final nowMin = now.hour * 60 + now.minute;

    for (final e in entries) {
      final id = e.id;
      if (id == null || id.isEmpty) continue;

      if (completed.contains(id)) {
        out[id] = _EntryStatus.completed;
        continue;
      }

      final startMin = e.time.hour * 60 + e.time.minute;
      final dur = ((e.height / 80.0) * 60.0).round().clamp(1, 24 * 60);
      final endMin = startMin + dur;

      if (startMin <= nowMin && nowMin < endMin) {
        out[id] = _EntryStatus.inProgress;
      } else if (nowMin >= endMin) {
        out[id] = _EntryStatus.overdue;
      } else {
        out[id] = _EntryStatus.notStarted;
      }
    }

    return out;
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

  List<PlanTask> _seedTasks(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    return [
      PlanTask(
        id: 't_design',
        title: 'Architecture design',
        durationMinutes: 90,
        priority: 4,
        load: CognitiveLoad.high,
        tag: 'Deep Work',
        due: d.add(const Duration(hours: 12)),
      ),
      PlanTask(
        id: 't_email',
        title: 'Email triage',
        durationMinutes: 30,
        priority: 2,
        load: CognitiveLoad.low,
        tag: 'Micro Task',
        due: d.add(const Duration(hours: 18)),
      ),
      PlanTask(
        id: 't_review',
        title: 'Spec review',
        durationMinutes: 60,
        priority: 3,
        load: CognitiveLoad.medium,
        tag: 'Routine',
        due: d.add(const Duration(hours: 17)),
      ),
      PlanTask(
        id: 't_code',
        title: 'Implementation sprint',
        durationMinutes: 120,
        priority: 5,
        load: CognitiveLoad.high,
        tag: 'Deep Work',
        due: d.add(const Duration(hours: 18)),
      ),
    ];
  }

  Future<SchedulingRequest> _buildSmartRequest({
    bool includeUrgent = true,
  }) async {
    final energyStatus = await _dataService.getEnergyStatus();
    final emotion = await _dataService.getEmotionState();
    final day = dateOnly(_selectedDay);

    _smartTasks = _smartTasks.isEmpty ? _seedTasks(day) : _smartTasks;

    final tasks = <PlanTask>[
      ..._smartTasks,
      if (includeUrgent && _urgentInserted != null) _urgentInserted!,
    ];

    final tuning = await _dataService.getSchedulingTuning();
    final shapedTasks = EmotionPolicy.adaptTasks(
      tasks: tasks,
      emotion: emotion,
    );
    final tunedTasks = shapedTasks.map((t) {
      final mult = tuning.durationMultiplierForTag(t.tag);
      final tunedMinutes = (t.durationMinutes * mult).round().clamp(1, 24 * 60);
      final emotionMinutes = EmotionPolicy.applyDurationMultiplier(
        minutes: tunedMinutes,
        emotion: emotion,
      );
      return PlanTask(
        id: t.id,
        title: t.title,
        durationMinutes: emotionMinutes,
        priority: t.priority,
        load: t.load,
        tag: t.tag,
        due: t.due,
      );
    }).toList();

    return SchedulingRequest(
      day: day,
      tasks: tunedTasks,
      windows: _defaultWindows(),
      energy: EmotionPolicy.adjustEnergy(
        base: _tierFromBattery(energyStatus.batteryPercent),
        emotion: emotion,
      ),
      tuning: tuning,
      fixed: EmotionPolicy.fixedRestBlocks(day: day, emotion: emotion),
    );
  }

  Future<void> _loadSmartSchedule({bool preserveLoading = false}) async {
    setState(() {
      _isLoading = true;
    });

    try {
      final req = await _buildSmartRequest();

      AppServices.diagnostics.bumpReplan(reason: 'smart_plan');

      final sw = Stopwatch()..start();
      final plan = AppServices.schedulingEngine.plan(req);
      sw.stop();

      AppServices.diagnostics.recordPlan(
        cost: sw.elapsed,
        reason: 'smart_plan',
      );
      AppServices.logStore.info(
        'schedule',
        'plan smart schedule',
        data: {
          'ms': sw.elapsedMilliseconds,
          'tasks': req.tasks.length,
          'windows': req.windows.length,
        },
      );

      if (!mounted) return;

      final planned = plan.entries
          .map((e) => e.copyWith(day: req.day))
          .toList(growable: false);

      setState(() {
        _blocks = planned;
        _hasLoadedOnce = true;
        _isLoading = preserveLoading;
      });

      final today = dateOnly(DateTime.now());
      if (sameDay(req.day, today)) {
        await AppServices.reminderService.rescheduleDay(
          day: req.day,
          entries: planned,
        );
      }

      if (!mounted) return;

      if (plan.issues.isNotEmpty) {
        final msg = AppStrings.of(
          context,
          'calendar_planner_issues',
          params: {'count': plan.issues.length.toString()},
        );
        MobileFeedback.showInfo(context, zhMessage: msg, enMessage: msg);
      }
    } catch (e, st) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = e;
      });
      AppServices.logStore.error(
        'schedule',
        'load smart schedule failed',
        error: e,
        stackTrace: st,
      );
    }
  }

  Future<void> _showRescueOptions(PlanTask urgent) async {
    setState(() => _isLoading = true);

    try {
      final base = await _buildSmartRequest(includeUrgent: false);
      final options =
          ScheduleRescueService(engine: AppServices.schedulingEngine).propose(
            base: base,
            baseline: List<ScheduleEntry>.from(_blocks),
            urgent: urgent,
          );

      if (!mounted) return;
      setState(() => _isLoading = false);

      //  MASTER §3.1/§4.2: phones use a ModalBottomSheet; tablets and
      // desktops keep the fullscreen dialog.
      Widget buildPanel(BuildContext ctx) => RescuePlanComparison(
        options: options,
        baseline: _blocks,
        title: AppStrings.of(ctx, 'calendar_rescue_title'),
        cancelLabel: AppStrings.of(ctx, 'calendar_rescue_cancel'),
        onCancel: () => Navigator.of(ctx).pop(),
        onSelect: (option) => Navigator.of(ctx).pop(option),
      );

      final isNarrow =
          MediaQuery.sizeOf(context).width < AppTheme.compactShellBreakpoint;
      final ScheduleRescueOption? selected;
      if (isNarrow) {
        selected = await showModalBottomSheet<ScheduleRescueOption>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: buildPanel,
        );
      } else {
        selected = await showDialog<ScheduleRescueOption>(
          context: context,
          builder: (ctx) => Dialog.fullscreen(child: buildPanel(ctx)),
        );
      }

      if (selected == null || !mounted) return;

      final previous = List<ScheduleEntry>.from(_blocks);
      final planned = selected.plan.entries
          .map((entry) => entry.copyWith(day: base.day))
          .toList(growable: false);

      setState(() => _isLoading = true);
      try {
        await _rescuePersistence.apply(before: previous, after: planned);
      } catch (e, st) {
        if (!mounted) return;
        final message = AppStrings.of(context, 'calendar_rescue_save_failed');
        setState(() => _isLoading = false);
        MobileFeedback.showError(
          context,
          category: 'schedule',
          message: 'save rescue plan failed',
          zhMessage: message,
          enMessage: message,
          error: e,
          stackTrace: st,
        );
        return;
      }

      if (!mounted) return;
      await _rescheduleRescueReminders(day: base.day, entries: planned);

      await _recordRescueEvent(
        task: urgent,
        energy: base.energy,
        reason: 'rescue_accept:${selected.strategy.name}',
      );

      if (!mounted) return;
      setState(() {
        _urgentInserted = urgent;
        _acceptedRescue = selected;
        _rescueUndoBlocks = previous;
        _blocks = planned;
        _isLoading = false;
      });

      if (!mounted || selected.plan.issues.isEmpty) return;
      final msg = AppStrings.of(
        context,
        'calendar_rescue_issues',
        params: {'count': selected.plan.issues.length.toString()},
      );
      MobileFeedback.showInfo(context, zhMessage: msg, enMessage: msg);
    } catch (e, st) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      MobileFeedback.showError(
        context,
        category: 'schedule',
        message: 'rescue planning failed',
        zhMessage: '暂时无法生成救援方案，请稍后重试。',
        enMessage: 'Unable to generate rescue plans right now.',
        error: e,
        stackTrace: st,
      );
    }
  }

  Future<void> _recordRescueEvent({
    required PlanTask task,
    required EnergyTier energy,
    required String reason,
  }) async {
    try {
      await _dataService.logTaskEvent(
        TaskEvent(
          id: 'rescue_${DateTime.now().microsecondsSinceEpoch}',
          taskId: task.id,
          title: task.title,
          tag: task.tag,
          load: task.load,
          at: DateTime.now(),
          type: TaskEventType.interrupt,
          plannedMinutes: task.durationMinutes,
          energy: energy,
          reason: reason,
        ),
      );
    } catch (e, st) {
      AppServices.logStore.error(
        'schedule',
        'rescue event logging failed',
        error: e,
        stackTrace: st,
        data: {'taskId': task.id, 'reason': reason},
      );
    }
  }

  Future<void> _rescheduleRescueReminders({
    required DateTime day,
    required List<ScheduleEntry> entries,
  }) async {
    if (!sameDay(day, dateOnly(DateTime.now()))) return;

    try {
      await AppServices.reminderService.rescheduleDay(
        day: day,
        entries: entries,
      );
    } catch (e, st) {
      AppServices.logStore.error(
        'schedule',
        'rescue reminder reschedule failed',
        error: e,
        stackTrace: st,
      );
    }
  }

  Future<void> _undoRescue() async {
    if (_isLoading) return;
    final previous = _rescueUndoBlocks;
    final accepted = _acceptedRescue;
    final urgent = _urgentInserted;
    if (previous == null || accepted == null || urgent == null) return;

    final current = List<ScheduleEntry>.from(_blocks);
    final rescueDay = previous
        .map((entry) => entry.day)
        .firstWhere((day) => day != null, orElse: () => _selectedDay)!;
    setState(() => _isLoading = true);
    try {
      await _rescuePersistence.apply(before: current, after: previous);
    } catch (e, st) {
      if (!mounted) return;
      final message = AppStrings.of(context, 'calendar_rescue_save_failed');
      setState(() => _isLoading = false);
      MobileFeedback.showError(
        context,
        category: 'schedule',
        message: 'restore rescue plan failed',
        zhMessage: message,
        enMessage: message,
        error: e,
        stackTrace: st,
      );
      return;
    }

    if (!mounted) return;
    await _rescheduleRescueReminders(day: rescueDay, entries: previous);

    await _recordRescueEvent(
      task: urgent,
      energy: EnergyTier.medium,
      reason: 'rescue_undo:${accepted.strategy.name}',
    );

    if (!mounted) return;
    setState(() {
      _blocks = previous;
      _urgentInserted = null;
      _acceptedRescue = null;
      _rescueUndoBlocks = null;
      _isLoading = false;
    });
  }

  String _dataSourceLabel(BuildContext context) {
    final service = AppServices.dataService;
    if (service is CompositeDataService) {
      return AppStrings.of(
        context,
        service.preferRemoteReads
            ? 'source_remote_first'
            : 'workspace_local_ready',
      );
    }
    if (service is RemoteDataService) {
      return AppStrings.of(context, 'source_remote');
    }
    return AppStrings.of(context, 'source_local');
  }

  Future<void> _handleCalendarAction(String v) async {
    if (v == 'mode') {
      setState(
        () => _mode = _mode == _CalendarMode.manual
            ? _CalendarMode.smart
            : _CalendarMode.manual,
      );
      await _loadSchedule();
      return;
    }
    if (v == 'refresh') {
      await _loadSchedule();
      return;
    }
    if (v == 'emotion') {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const MainScreen(
            secondaryPage: EmotionPage(),
            secondaryTabIndex: 1,
          ),
        ),
      );
    } else if (v == 'goals') {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const MainScreen(
            secondaryPage: GoalsPage(),
            secondaryTabIndex: 1,
          ),
        ),
      );
    } else if (v == 'mcp') {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const MainScreen(
            secondaryPage: IntegrationsPage(),
            secondaryTabIndex: 1,
          ),
        ),
      );
    } else if (v == 'urgent') {
      if (!_isLoading) _showInsertUrgentDialog();
    } else if (v == 'export') {
      await _exportIcs();
    } else if (v == 'import') {
      await _importIcs();
    } else if (v == 'field_time') {
      _toggleField(ScheduleTimelineField.time);
    } else if (v == 'field_tag') {
      _toggleField(ScheduleTimelineField.tag);
    } else if (v == 'field_status') {
      _toggleField(ScheduleTimelineField.status);
    } else if (v == 'field_reminder') {
      _toggleField(ScheduleTimelineField.reminder);
    } else if (v == 'field_goal') {
      _toggleField(ScheduleTimelineField.goal);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isCompactAppBar = MobileFeedback.isNarrow(context, breakpoint: 760);
    final allEntries = List<ScheduleEntry>.from(_blocks)
      ..sort((a, b) {
        final aMinutes = a.time.hour * 60 + a.time.minute;
        final bMinutes = b.time.hour * 60 + b.time.minute;
        return aMinutes.compareTo(bMinutes);
      });

    final dayEntries =
        entriesForDay(day: _selectedDay, allEntries: allEntries).toList()
          ..sort((a, b) {
            final aMinutes = a.time.hour * 60 + a.time.minute;
            final bMinutes = b.time.hour * 60 + b.time.minute;
            return aMinutes.compareTo(bMinutes);
          });

    return Scaffold(
      key: ValueKey(
        isCompactAppBar ? 'stitch-schedule-mobile' : 'schedule-page',
      ),
      backgroundColor: AppWindowTones.canvas(context, AppWindowTone.neutral),
      appBar: isCompactAppBar && StitchMobileShellScope.isHosted(context)
          ? null
          : CalendarPageAppBar(
              sourceLabel: _dataSourceLabel(context),
              smartMode: _mode == _CalendarMode.smart,
              loading: _isLoading,
              compact: isCompactAppBar,
              visibleFields: _visibleFields,
              onAction: _handleCalendarAction,
            ),
      body: !_hasLoadedOnce && _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (_isLoading) const LinearProgressIndicator(minHeight: 2),
                if (_loadError != null)
                  WorkbenchStatusBanner(
                    key: const ValueKey('calendar-load-error'),
                    message: serviceFailureMessage(
                      context,
                      _loadError,
                      fallback: AppStrings.of(context, 'calendar_load_error'),
                    ),
                    actionLabel: AppStrings.of(context, 'common_retry'),
                    actionKey: const ValueKey('calendar-load-retry'),
                    onAction: _loadSchedule,
                  ),
                if (isCompactAppBar && StitchMobileShellScope.isHosted(context))
                  Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: AppStrings.of(context, 'calendar_refresh'),
                            onPressed: _isLoading ? null : _loadSchedule,
                            icon: const Icon(Icons.refresh),
                          ),
                          IconButton(
                            tooltip: AppStrings.of(
                              context,
                              'calendar_tooltip_insert_urgent',
                            ),
                            onPressed: _isLoading
                                ? null
                                : _showInsertUrgentDialog,
                            icon: const Icon(Icons.add_alert),
                          ),
                        ],
                      ),
                    ),
                  ),
                EmotionQuickCheckInCard(
                  onChanged: () async {
                    if (_mode == _CalendarMode.smart) {
                      await _loadSmartSchedule();
                    }
                  },
                ),
                ResponsivePageFrame(
                  child: Column(
                    children: [
                      CalendarTodayStatus(
                        entryCount: dayEntries.length,
                        smartMode: _mode == _CalendarMode.smart,
                      ),
                      RescueSummary(
                        accepted: _acceptedRescue,
                        issueCount: _acceptedRescue?.plan.issues.length ?? 0,
                        onUndo: _isLoading ? null : _undoRescue,
                        compact: isCompactAppBar,
                      ),
                      CalendarViewToolbar(
                        view: _view,
                        selectedDay: _selectedDay,
                        onViewChanged: (value) => setState(() => _view = value),
                        onShiftPeriod: _shiftSelectedPeriod,
                        onToday: () => _jumpToDay(DateTime.now()),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final timeMap = KeyedSubtree(
                        key: const ValueKey('calendar-time-map'),
                        child: AnimatedSwitcher(
                          duration: AppMotion.resolve(
                            context,
                            const Duration(milliseconds: 220),
                          ),
                          reverseDuration: AppMotion.resolve(
                            context,
                            AppMotion.exit,
                          ),
                          switchInCurve: Curves.easeOut,
                          switchOutCurve: Curves.easeIn,
                          child: KeyedSubtree(
                            key: ValueKey(
                              '${_view.name}-${_selectedDay.toIso8601String()}',
                            ),
                            child: _buildViewBody(context, allEntries),
                          ),
                        ),
                      );
                      if (MediaQuery.sizeOf(context).width <
                          AppTheme.shellBreakpoint) {
                        return timeMap;
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: timeMap),
                          const SizedBox(width: 12),
                          SizedBox(
                            width: 288,
                            child: CalendarDesktopSummary(
                              entries: dayEntries,
                              smartMode: _mode == _CalendarMode.smart,
                              sourceLabel: _dataSourceLabel(context),
                              acceptedMovedCount:
                                  _acceptedRescue?.movedEntryCount,
                              onUndo: _isLoading ? null : _undoRescue,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
      floatingActionButton: PressScale(
        child: _mode == _CalendarMode.manual
            ? FloatingActionButton(
                heroTag: 'smart-calendar-add-fab',
                child: const Icon(Icons.add),
                onPressed: () => _showAddDialog(context),
              )
            : FloatingActionButton.extended(
                heroTag: 'smart-calendar-replan-fab',
                icon: const Icon(Icons.bolt),
                label: Text(AppStrings.of(context, 'calendar_btn_replan')),
                onPressed: _isLoading ? null : _loadSmartSchedule,
              ),
      ),
    );
  }

  Future<void> _shiftSelectedPeriod(int direction) async {
    setState(
      () => _selectedDay = shiftCalendarPeriod(_selectedDay, _view, direction),
    );
    await _loadSchedule();
  }

  Future<void> _jumpToDay(DateTime day) async {
    setState(() {
      _selectedDay = dateOnly(day);
      _view = ScheduleTimelineView.day;
    });
    await _loadSchedule();
  }

  void _toggleField(ScheduleTimelineField field) {
    setState(() {
      if (_visibleFields.contains(field)) {
        _visibleFields.remove(field);
      } else {
        _visibleFields.add(field);
      }
    });
  }

  Widget _buildViewBody(BuildContext context, List<ScheduleEntry> allEntries) {
    final statusByTaskId = <String, String>{};
    for (final entry in allEntries) {
      final id = entry.id;
      if (id == null || id.isEmpty) continue;
      final status = _statusByTaskId[id];
      if (status != null) statusByTaskId[id] = _statusLabel(status);
    }

    return ScheduleTimeline(
      view: _view,
      selectedDay: _selectedDay,
      entries: allEntries,
      visibleFields: _visibleFields,
      statusByTaskId: statusByTaskId,
      startHour: _startHour,
      endHour: _endHour,
      titleBuilder: (context, entry) =>
          calendarEntryTitle(context, entry.title),
      tagBuilder: tagLabel,
      statusBuilder: (context, status) => status,
      reminderBuilder: (context, minutes) {
        final isEn = Localizations.localeOf(context).languageCode == 'en';
        return isEn ? '$minutes min before' : '-${minutes}m';
      },
      emptyLabel: AppStrings.of(context, 'calendar_week_empty'),
      goalLabel: calendarFieldLabel(context, ScheduleTimelineField.goal),
      ganttLabel: calendarViewLabel(context, ScheduleTimelineView.gantt),
      taskLaneLabel: AppStrings.of(context, 'team_label_task'),
      deleteLabel: AppStrings.of(context, 'btn_delete'),
      onSelectDay: _jumpToDay,
      onDelete:
          _mode == _CalendarMode.manual && _view == ScheduleTimelineView.day
          ? _showDeleteDialog
          : null,
    );
  }

  Future<void> _showInsertUrgentDialog() async {
    if (_isLoading) return;
    final urgent = await showUrgentTaskDialog(
      context,
      scheduleDay: dateOnly(_selectedDay),
    );
    if (urgent == null || !mounted) return;
    await _showRescueOptions(urgent);
  }

  Future<void> _exportIcs() async {
    final d = dateOnly(_selectedDay);

    final entries = _mode == _CalendarMode.manual
        ? entriesForDay(
            day: d,
            allEntries: await _dataService.getScheduleEntries(),
          )
        : entriesForDay(day: d, allEntries: _blocks);

    final events = IcsBridge.scheduleToEvents(day: d, entries: entries);

    final ics = IcsCodec.encodeCalendar(
      events: events,
      createdAt: DateTime.now(),
    );

    final ts = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '')
        .replaceAll('-', '')
        .replaceAll('.', '');
    final fileName = 'sxzppp_$ts.ics';

    final sw = Stopwatch()..start();
    try {
      final res = await IcsFileSaver.save(ics, fileName: fileName);
      sw.stop();

      AppServices.diagnostics.recordIcsExport(
        ok: true,
        count: events.length,
        path: res.path,
      );
      AppServices.logStore.info(
        'ics',
        'export',
        data: {
          'ms': sw.elapsedMilliseconds,
          'count': events.length,
          'label': res.label,
          'path': res.path ?? '',
          'fileName': fileName,
        },
      );

      if (!mounted) return;

      final msg = MobileFeedback.isMobilePhone(context)
          ? MobileFeedback.localized(
              context,
              zh: 'ICS 文件已保存到应用目录。',
              en: 'The ICS file was saved to app storage.',
            )
          : (res.path != null
                ? AppStrings.of(
                    context,
                    'calendar_ics_exported_path',
                    params: {'path': res.path ?? ''},
                  )
                : AppStrings.of(
                    context,
                    'calendar_ics_exported_download',
                    params: {'fileName': fileName},
                  ));
      MobileFeedback.showInfo(context, zhMessage: msg, enMessage: msg);
    } catch (e, st) {
      sw.stop();
      AppServices.diagnostics.recordIcsExport(
        ok: false,
        count: 0,
        error: e.toString(),
      );
      AppServices.logStore.error(
        'ics',
        'export failed',
        error: e,
        stackTrace: st,
        data: {'ms': sw.elapsedMilliseconds},
      );
      if (!mounted) return;
      MobileFeedback.showError(
        context,
        category: 'ics',
        message: 'export failed',
        zhMessage: '暂时无法导出 ICS，请稍后重试。',
        enMessage: 'Unable to export ICS right now.',
        error: e,
        stackTrace: st,
      );
    }
  }

  Future<void> _importIcs() async {
    if (_isLoading) return;
    final bool isNarrow =
        MediaQuery.sizeOf(context).width < AppTheme.compactShellBreakpoint;
    final DateTime selectedDay = dateOnly(_selectedDay);
    final List<ScheduleEntry>? imported;
    if (isNarrow) {
      imported = await showModalBottomSheet<List<ScheduleEntry>>(
        context: context,
        isScrollControlled: true,
        showDragHandle: false,
        builder: (_) =>
            CalendarIcsImportForm(day: selectedDay, bottomSheet: true),
      );
    } else {
      imported = await showDialog<List<ScheduleEntry>>(
        context: context,
        builder: (_) => CalendarIcsImportForm(day: selectedDay),
      );
    }

    if (imported == null || imported.isEmpty) return;
    if (!mounted) return;

    setState(() => _isLoading = true);

    try {
      final existing = await _dataService.getScheduleEntries();
      final existingById = <String, ScheduleEntry>{
        for (final e in existing)
          if (e.id != null && e.id!.isNotEmpty) e.id!: e,
      };

      var added = 0;
      var updated = 0;
      for (final e in imported) {
        final id = e.id;
        if (id == null || id.isEmpty) {
          await _dataService.addScheduleEntry(e);
          added++;
          continue;
        }

        final prev = existingById[id];
        if (prev == null) {
          await _dataService.addScheduleEntry(e);
          existingById[id] = e;
          added++;
          continue;
        }

        bool sameTime(TimeOfDay a, TimeOfDay b) =>
            a.hour == b.hour && a.minute == b.minute;
        bool sameDay(DateTime? a, DateTime? b) {
          if (a == null && b == null) return true;
          if (a == null || b == null) return false;
          return a.year == b.year && a.month == b.month && a.day == b.day;
        }

        bool sameHeight(double a, double b) => (a - b).abs() <= 0.01;
        final changed =
            prev.title != e.title ||
            !sameTime(prev.time, e.time) ||
            !sameHeight(prev.height, e.height) ||
            !sameDay(prev.day, e.day);

        if (!changed) continue;

        final merged = prev.copyWith(
          title: e.title,
          day: e.day,
          time: e.time,
          height: e.height,
        );
        await _dataService.addScheduleEntry(merged);
        existingById[id] = merged;
        updated++;
      }

      AppServices.diagnostics.recordIcsImport(ok: true, count: added + updated);
      AppServices.logStore.info(
        'ics',
        'import',
        data: {
          'added': added,
          'updated': updated,
          'totalParsed': imported.length,
        },
      );

      if (!mounted) return;

      final msg = (updated > 0 && added > 0)
          ? '${AppStrings.of(context, 'calendar_ics_import_success', params: {'added': added.toString()})} ${AppStrings.of(context, 'calendar_ics_import_updated', params: {'updated': updated.toString()})}'
          : (updated > 0)
          ? AppStrings.of(
              context,
              'calendar_ics_import_updated',
              params: {'updated': updated.toString()},
            )
          : AppStrings.of(
              context,
              'calendar_ics_import_success',
              params: {'added': added.toString()},
            );

      MobileFeedback.showInfo(context, zhMessage: msg, enMessage: msg);

      await _loadSchedule(preserveLoading: true);
    } catch (e, st) {
      AppServices.diagnostics.recordIcsImport(
        ok: false,
        count: 0,
        error: e.toString(),
      );
      AppServices.logStore.error(
        'ics',
        'import failed',
        error: e,
        stackTrace: st,
      );

      if (!mounted) return;
      MobileFeedback.showError(
        context,
        category: 'ics',
        message: 'import failed',
        zhMessage: '暂时无法导入 ICS 内容，请检查后重试。',
        enMessage: 'Unable to import the ICS content.',
        error: e,
        stackTrace: st,
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
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

  Future<void> _showAddDialog(BuildContext context) async {
    final entry = await showAddScheduleEntryDialog(
      context,
      day: dateOnly(_selectedDay),
    );
    if (entry == null || !mounted) return;
    await _dataService.addScheduleEntry(entry);
    if (mounted) await _loadSchedule();
  }

  String _statusLabel(_EntryStatus s) {
    switch (s) {
      case _EntryStatus.notStarted:
        return AppStrings.of(context, 'calendar_status_not_started');
      case _EntryStatus.inProgress:
        return AppStrings.of(context, 'calendar_status_in_progress');
      case _EntryStatus.completed:
        return AppStrings.of(context, 'calendar_status_done');
      case _EntryStatus.overdue:
        return AppStrings.of(context, 'calendar_status_overdue');
    }
  }
}
