// lib/screens/smart_calendar_page.dart
import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/app_services.dart';
import '../services/ics/ics_bridge.dart';
import '../services/ics/ics_codec.dart';
import '../services/ics/ics_file_saver.dart';
import '../services/emotion/emotion_policy.dart';
import '../utils/helpers.dart';
import '../utils/app_strings.dart';
import '../utils/mobile_feedback.dart';
import '../utils/schedule_occurrence.dart';
import '../widgets/emotion_quick_checkin_card.dart';
import 'emotion_page.dart';
import 'goals_page.dart';
import 'integrations_page.dart';

enum _CalendarMode { manual, smart }

enum _CalendarView { day, week, month, gantt }

enum _CalendarField { time, tag, status, reminder, goal }

enum _EntryStatus { notStarted, inProgress, completed, overdue }

class SmartCalendarPage extends StatefulWidget {
  const SmartCalendarPage({super.key});

  @override
  State<SmartCalendarPage> createState() => _SmartCalendarPageState();
}

class _SmartCalendarPageState extends State<SmartCalendarPage> {
  List<ScheduleEntry> _blocks = [];
  bool _isLoading = true;
  Map<String, _EntryStatus> _statusByTaskId = const {};

  _CalendarMode _mode = _CalendarMode.manual;
  _CalendarView _view = _CalendarView.day;
  final Set<_CalendarField> _visibleFields = {
    _CalendarField.time,
    _CalendarField.tag,
    _CalendarField.status,
    _CalendarField.reminder,
  };
  late DateTime _selectedDay;

  final _dataService = AppServices.dataService;

  List<PlanTask> _smartTasks = const [];
  PlanTask? _urgentInserted;

  static const double _hourHeight = 80.0;
  static const int _startHour = 8;
  static const int _endHour = 20;
  static const int _totalHours = _endHour - _startHour;
  static const double _totalHeight = _totalHours * _hourHeight;

  @override
  void initState() {
    super.initState();
    _selectedDay = dateOnly(DateTime.now());
    _loadSchedule();
  }

  Future<void> _loadSchedule() async {
    setState(() {
      _isLoading = true;
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
          _isLoading = false;
        });
        final todayEntries = entriesForDay(day: today, allEntries: entries);
        await AppServices.reminderService.rescheduleDay(
          day: today,
          entries: todayEntries,
        );

        return;
      }

      await _loadSmartSchedule();
    } catch (e, st) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      MobileFeedback.showError(
        context,
        category: 'schedule',
        message: 'load schedule failed',
        zhMessage: '暂时无法加载日程，请稍后重试。',
        enMessage: 'Unable to load the schedule right now.',
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

  String _cognitiveLoadLabel(BuildContext context, CognitiveLoad load) {
    switch (load) {
      case CognitiveLoad.low:
        return AppStrings.of(context, 'cognitive_load_low');
      case CognitiveLoad.medium:
        return AppStrings.of(context, 'cognitive_load_medium');
      case CognitiveLoad.high:
        return AppStrings.of(context, 'cognitive_load_high');
    }
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

  Future<void> _loadSmartSchedule() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final energyStatus = await _dataService.getEnergyStatus();
      final emotion = await _dataService.getEmotionState();
      final day = dateOnly(_selectedDay);

      _smartTasks = _smartTasks.isEmpty ? _seedTasks(day) : _smartTasks;

      final tasks = <PlanTask>[
        ..._smartTasks,
        if (_urgentInserted != null) _urgentInserted!,
      ];

      final tuning = await _dataService.getSchedulingTuning();
      final shapedTasks = EmotionPolicy.adaptTasks(
        tasks: tasks,
        emotion: emotion,
      );
      final tunedTasks = shapedTasks.map((t) {
        final mult = tuning.durationMultiplierForTag(t.tag);
        final tunedMinutes =
            (t.durationMinutes * mult).round().clamp(1, 24 * 60);
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

      final fixed = EmotionPolicy.fixedRestBlocks(day: day, emotion: emotion);

      final req = SchedulingRequest(
        day: day,
        tasks: tunedTasks,
        windows: _defaultWindows(),
        energy: EmotionPolicy.adjustEnergy(
          base: _tierFromBattery(energyStatus.batteryPercent),
          emotion: emotion,
        ),
        tuning: tuning,
        fixed: fixed,
      );

      AppServices.diagnostics.bumpReplan(reason: 'smart_plan');

      final sw = Stopwatch()..start();
      final plan = AppServices.schedulingEngine.plan(req);
      sw.stop();

      AppServices.diagnostics.recordPlan(cost: sw.elapsed, reason: 'smart_plan');
      AppServices.logStore.info(
        'schedule',
        'plan smart schedule',
        data: {
          'ms': sw.elapsedMilliseconds,
          'tasks': tunedTasks.length,
          'windows': req.windows.length,
        },
      );

      if (!mounted) return;

      final planned = plan.entries
          .map((e) => e.copyWith(day: req.day))
          .toList(growable: false);

      setState(() {
        _blocks = planned;
        _isLoading = false;
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
        MobileFeedback.showInfo(
          context,
          zhMessage: msg,
          enMessage: msg,
        );
      }
    } catch (e, st) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      MobileFeedback.showError(
        context,
        category: 'schedule',
        message: 'load smart schedule failed',
        zhMessage: '暂时无法生成智能规划，请稍后重试。',
        enMessage: 'Smart planning is unavailable right now.',
        error: e,
        stackTrace: st,
      );
    }
  }

  double _calculateTopOffset(TimeOfDay time) {
    final double minutesFromStart =
        (time.hour - _startHour) * 60.0 + time.minute;
    return minutesFromStart / 60.0 * _hourHeight;
  }

  String _tagLabel(BuildContext context, String tag) {
    switch (tag) {
      case 'General':
        return AppStrings.of(context, 'tag_general');
      case 'Deep Work':
        return AppStrings.of(context, 'tag_deep_work');
      case 'Micro Task':
        return AppStrings.of(context, 'tag_micro_task');
      case 'Routine':
        return AppStrings.of(context, 'tag_routine');
      case 'Urgent':
        return AppStrings.of(context, 'tag_urgent');
      case 'Goal':
        return AppStrings.of(context, 'tag_goal');
    }
    return tag;
  }

  String _scheduleTitleLabel(BuildContext context, String title) {
    switch (title) {
      case 'Architecture design':
        return AppStrings.of(context, 'calendar_seed_architecture_design');
      case 'Email triage':
        return AppStrings.of(context, 'calendar_seed_email_triage');
      case 'Spec review':
        return AppStrings.of(context, 'calendar_seed_spec_review');
      case 'Implementation sprint':
        return AppStrings.of(context, 'calendar_seed_implementation_sprint');
    }
    return title;
  }

  @override
  Widget build(BuildContext context) {
    final isCompactAppBar = MobileFeedback.isNarrow(
      context,
      breakpoint: 760,
    );
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
      appBar: AppBar(
        title: Text(AppStrings.of(context, 'calendar_title')),
        actions: [
          if (!isCompactAppBar)
            IconButton(
              tooltip: AppStrings.of(context, 'goal_title'),
              icon: const Icon(Icons.flag_outlined),
              onPressed: () {
                Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (_) => const GoalsPage()));
              },
            ),
          IconButton(
            tooltip: _mode == _CalendarMode.manual
                ? AppStrings.of(context, 'calendar_tooltip_switch_to_smart')
                : AppStrings.of(context, 'calendar_tooltip_switch_to_manual'),
            icon: Icon(
              _mode == _CalendarMode.manual ? Icons.bolt : Icons.edit_calendar,
            ),
            onPressed: () async {
              setState(() {
                _mode = _mode == _CalendarMode.manual
                    ? _CalendarMode.smart
                    : _CalendarMode.manual;
              });
              await _loadSchedule();
            },
          ),
          if (!isCompactAppBar && _mode == _CalendarMode.smart)
            IconButton(
              tooltip: AppStrings.of(context, 'calendar_tooltip_insert_urgent'),
              icon: const Icon(Icons.add_alert),
              onPressed: _showInsertUrgentDialog,
            ),
          if (!isCompactAppBar)
            PopupMenuButton<_CalendarField>(
              tooltip: '显示字段',
              icon: const Icon(Icons.tune),
              onSelected: _toggleField,
              itemBuilder: (ctx) => [
                CheckedPopupMenuItem(
                  value: _CalendarField.time,
                  checked: _visibleFields.contains(_CalendarField.time),
                  child: Text(_fieldLabel(ctx, _CalendarField.time)),
                ),
                CheckedPopupMenuItem(
                  value: _CalendarField.tag,
                  checked: _visibleFields.contains(_CalendarField.tag),
                  child: Text(_fieldLabel(ctx, _CalendarField.tag)),
                ),
                CheckedPopupMenuItem(
                  value: _CalendarField.status,
                  checked: _visibleFields.contains(_CalendarField.status),
                  child: Text(_fieldLabel(ctx, _CalendarField.status)),
                ),
                CheckedPopupMenuItem(
                  value: _CalendarField.reminder,
                  checked: _visibleFields.contains(_CalendarField.reminder),
                  child: Text(_fieldLabel(ctx, _CalendarField.reminder)),
                ),
                CheckedPopupMenuItem(
                  value: _CalendarField.goal,
                  checked: _visibleFields.contains(_CalendarField.goal),
                  child: Text(_fieldLabel(ctx, _CalendarField.goal)),
                ),
              ],
            ),
          if (!isCompactAppBar)
            IconButton(
              tooltip: AppStrings.of(context, 'calendar_tooltip_export_ics'),
              icon: const Icon(Icons.upload_file),
              onPressed: _exportIcs,
            ),
          if (!isCompactAppBar)
            IconButton(
              tooltip: AppStrings.of(context, 'calendar_tooltip_import_ics'),
              icon: const Icon(Icons.download),
              onPressed: _importIcs,
            ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadSchedule),
          PopupMenuButton<String>(
            tooltip: AppStrings.of(context, 'tooltip_more'),
            onSelected: (v) async {
              if (v == 'emotion') {
                Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (_) => const EmotionPage()));
              } else if (v == 'goals') {
                Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (_) => const GoalsPage()));
              } else if (v == 'mcp') {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const IntegrationsPage()),
                );
              } else if (v == 'urgent') {
                _showInsertUrgentDialog();
              } else if (v == 'export') {
                await _exportIcs();
              } else if (v == 'import') {
                await _importIcs();
              } else if (v == 'field_time') {
                _toggleField(_CalendarField.time);
              } else if (v == 'field_tag') {
                _toggleField(_CalendarField.tag);
              } else if (v == 'field_status') {
                _toggleField(_CalendarField.status);
              } else if (v == 'field_reminder') {
                _toggleField(_CalendarField.reminder);
              } else if (v == 'field_goal') {
                _toggleField(_CalendarField.goal);
              }
            },
            itemBuilder: (ctx) => [
              if (isCompactAppBar)
                PopupMenuItem(
                  value: 'goals',
                  child: Text(AppStrings.of(ctx, 'goal_title')),
                ),
              if (isCompactAppBar && _mode == _CalendarMode.smart)
                PopupMenuItem(
                  value: 'urgent',
                  child: Text(
                    AppStrings.of(ctx, 'calendar_tooltip_insert_urgent'),
                  ),
                ),
              if (isCompactAppBar)
                CheckedPopupMenuItem(
                  value: 'field_time',
                  checked: _visibleFields.contains(_CalendarField.time),
                  child: Text(_fieldLabel(ctx, _CalendarField.time)),
                ),
              if (isCompactAppBar)
                CheckedPopupMenuItem(
                  value: 'field_tag',
                  checked: _visibleFields.contains(_CalendarField.tag),
                  child: Text(_fieldLabel(ctx, _CalendarField.tag)),
                ),
              if (isCompactAppBar)
                CheckedPopupMenuItem(
                  value: 'field_status',
                  checked: _visibleFields.contains(_CalendarField.status),
                  child: Text(_fieldLabel(ctx, _CalendarField.status)),
                ),
              if (isCompactAppBar)
                CheckedPopupMenuItem(
                  value: 'field_reminder',
                  checked: _visibleFields.contains(_CalendarField.reminder),
                  child: Text(_fieldLabel(ctx, _CalendarField.reminder)),
                ),
              if (isCompactAppBar)
                CheckedPopupMenuItem(
                  value: 'field_goal',
                  checked: _visibleFields.contains(_CalendarField.goal),
                  child: Text(_fieldLabel(ctx, _CalendarField.goal)),
                ),
              if (isCompactAppBar)
                PopupMenuItem(
                  value: 'export',
                  child: Text(
                    AppStrings.of(ctx, 'calendar_tooltip_export_ics'),
                  ),
                ),
              if (isCompactAppBar)
                PopupMenuItem(
                  value: 'import',
                  child: Text(
                    AppStrings.of(ctx, 'calendar_tooltip_import_ics'),
                  ),
                ),
              PopupMenuItem(
                value: 'emotion',
                child: Text(AppStrings.of(ctx, 'emo_title')),
              ),
              if (!isCompactAppBar)
                PopupMenuItem(
                  value: 'goals',
                  child: Text(AppStrings.of(ctx, 'goal_title')),
                ),
              PopupMenuItem(
                value: 'mcp',
                child: Text(AppStrings.of(ctx, 'mcp_title')),
              ),
            ],
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                EmotionQuickCheckInCard(
                  onChanged: () async {
                    if (_mode == _CalendarMode.smart) {
                      await _loadSmartSchedule();
                    }
                  },
                ),
                _buildViewToolbar(context),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    switchInCurve: Curves.easeOut,
                    switchOutCurve: Curves.easeIn,
                    child: KeyedSubtree(
                      key: ValueKey(
                        '${_view.name}-${_selectedDay.toIso8601String()}',
                      ),
                      child: _buildViewBody(context, allEntries, dayEntries),
                    ),
                  ),
                ),
              ],
            ),
      floatingActionButton: _mode == _CalendarMode.manual
          ? FloatingActionButton(
              heroTag: 'smart-calendar-add-fab',
              child: const Icon(Icons.add),
              onPressed: () => _showAddDialog(context),
            )
          : FloatingActionButton.extended(
              heroTag: 'smart-calendar-replan-fab',
              icon: const Icon(Icons.bolt),
              label: Text(AppStrings.of(context, 'calendar_btn_replan')),
              onPressed: _loadSmartSchedule,
            ),
    );
  }

  Widget _buildViewToolbar(BuildContext context) {
    final ml = MaterialLocalizations.of(context);
    final weekStart = startOfWeek(_selectedDay);
    final weekEnd = weekStart.add(const Duration(days: 6));
    final label = switch (_view) {
      _CalendarView.day => ml.formatMediumDate(_selectedDay),
      _CalendarView.week =>
        '${ml.formatMediumDate(weekStart)} - ${ml.formatMediumDate(weekEnd)}',
      _CalendarView.month => ml.formatMonthYear(_selectedDay),
      _CalendarView.gantt =>
        '${ml.formatMediumDate(weekStart)} - ${ml.formatMediumDate(weekEnd)}',
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final showSegmentIcons = constraints.maxWidth >= 600;
          final segmentPadding = showSegmentIcons
              ? const EdgeInsets.symmetric(horizontal: 14, vertical: 10)
              : const EdgeInsets.symmetric(horizontal: 18, vertical: 10);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Align(
                alignment: Alignment.topCenter,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SegmentedButton<_CalendarView>(
                    style: ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: WidgetStatePropertyAll<EdgeInsetsGeometry>(
                        segmentPadding,
                      ),
                    ),
                    segments: [
                      _viewSegment(
                        context,
                        view: _CalendarView.day,
                        icon: Icons.view_day_outlined,
                        showIcon: showSegmentIcons,
                        minLabelWidth: showSegmentIcons ? 28 : 30,
                      ),
                      _viewSegment(
                        context,
                        view: _CalendarView.week,
                        icon: Icons.view_week_outlined,
                        showIcon: showSegmentIcons,
                        minLabelWidth: showSegmentIcons ? 28 : 30,
                      ),
                      _viewSegment(
                        context,
                        view: _CalendarView.month,
                        icon: Icons.calendar_month_outlined,
                        showIcon: showSegmentIcons,
                        minLabelWidth: showSegmentIcons ? 28 : 30,
                      ),
                      _viewSegment(
                        context,
                        view: _CalendarView.gantt,
                        icon: Icons.timeline_outlined,
                        showIcon: showSegmentIcons,
                        minLabelWidth: showSegmentIcons ? 40 : 44,
                      ),
                    ],
                    selected: {_view},
                    showSelectedIcon: false,
                    onSelectionChanged: (s) {
                      if (s.isEmpty) return;
                      setState(() => _view = s.first);
                    },
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  IconButton(
                    onPressed: () => _shiftSelectedPeriod(-1),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  IconButton(
                    onPressed: () => _shiftSelectedPeriod(1),
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  ButtonSegment<_CalendarView> _viewSegment(
    BuildContext context, {
    required _CalendarView view,
    required IconData icon,
    required bool showIcon,
    required double minLabelWidth,
  }) {
    final label = _viewLabel(context, view);
    return ButtonSegment<_CalendarView>(
      value: view,
      icon: showIcon ? Icon(icon, size: 18) : null,
      label: ConstrainedBox(
        constraints: BoxConstraints(minWidth: minLabelWidth),
        child: Text(
          label,
          maxLines: 1,
          softWrap: false,
          textAlign: TextAlign.center,
          overflow: TextOverflow.visible,
        ),
      ),
      tooltip: label,
    );
  }

  Future<void> _shiftSelectedDay(int deltaDays) async {
    setState(() {
      _selectedDay = dateOnly(_selectedDay.add(Duration(days: deltaDays)));
    });
    await _loadSchedule();
  }

  Future<void> _shiftSelectedMonth(int deltaMonths) async {
    final current = dateOnly(_selectedDay);
    final monthIndex = current.month - 1 + deltaMonths;
    final year = current.year + (monthIndex ~/ 12);
    final month = (monthIndex % 12) + 1;
    final lastDay = DateTime(year, month + 1, 0).day;
    final day = current.day.clamp(1, lastDay);

    setState(() {
      _selectedDay = DateTime(year, month, day);
    });
    await _loadSchedule();
  }

  Future<void> _shiftSelectedPeriod(int direction) async {
    switch (_view) {
      case _CalendarView.day:
        await _shiftSelectedDay(direction);
        return;
      case _CalendarView.week:
      case _CalendarView.gantt:
        await _shiftSelectedDay(direction * 7);
        return;
      case _CalendarView.month:
        await _shiftSelectedMonth(direction);
        return;
    }
  }

  Future<void> _jumpToDay(DateTime day) async {
    setState(() {
      _selectedDay = dateOnly(day);
      _view = _CalendarView.day;
    });
    await _loadSchedule();
  }

  void _toggleField(_CalendarField field) {
    setState(() {
      if (_visibleFields.contains(field)) {
        _visibleFields.remove(field);
      } else {
        _visibleFields.add(field);
      }
    });
  }

  Widget _buildViewBody(
    BuildContext context,
    List<ScheduleEntry> allEntries,
    List<ScheduleEntry> dayEntries,
  ) {
    switch (_view) {
      case _CalendarView.day:
        return _buildDayView(context, dayEntries);
      case _CalendarView.week:
        return _buildWeekView(context, allEntries);
      case _CalendarView.month:
        return _buildMonthView(context, allEntries);
      case _CalendarView.gantt:
        return _buildGanttView(context, allEntries);
    }
  }

  Widget _buildDayView(BuildContext context, List<ScheduleEntry> dayEntries) {
    final theme = Theme.of(context);
    final bottomPadding = MediaQuery.of(context).padding.bottom + 100;
    return SingleChildScrollView(
      scrollDirection: Axis.vertical,
      padding: EdgeInsets.only(bottom: bottomPadding),
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
                    child: Center(child: Text('${i + _startHour}:00')),
                  );
                }),
              ),
            ),
            Expanded(
              child: SizedBox(
                height: _totalHeight,
                child: Stack(
                  clipBehavior: Clip.none, 
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
                                color: theme.colorScheme.outlineVariant,
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
                            theme.colorScheme.primary.withAlpha(
                              (0.08 * 255).round(),
                            ),
                            theme.colorScheme.primary.withAlpha(
                              (0.08 * 255).round(),
                            ),
                            theme.colorScheme.tertiary.withAlpha(
                              (0.08 * 255).round(),
                            ),
                            theme.colorScheme.secondary.withAlpha(
                              (0.08 * 255).round(),
                            ),
                          ],
                        ),
                      ),
                    ),
                    ...dayEntries.map((block) {
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
                          status: (block.id == null || block.id!.isEmpty)
                              ? null
                              : _statusByTaskId[block.id!],
                          time: block.time,
                          reminderMinutesBefore: block.reminderMinutesBefore,
                          goalId: block.goalId,
                          goalTaskId: block.goalTaskId,
                          onDelete: _mode == _CalendarMode.manual
                              ? () => _showDeleteDialog(block)
                              : null,
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
    );
  }

  Widget _buildWeekView(BuildContext context, List<ScheduleEntry> allEntries) {
    final weekStart = startOfWeek(_selectedDay);
    final days = List.generate(7, (i) => weekStart.add(Duration(days: i)));
    final bottomPadding = MediaQuery.of(context).padding.bottom + 100;

    return SingleChildScrollView(
      padding: EdgeInsets.only(bottom: bottomPadding),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: days
              .map(
                (d) => _buildWeekDayColumn(
                  context,
                  day: d,
                  allEntries: allEntries,
                ),
              )
              .toList(growable: false),
        ),
      ),
    );
  }

  Widget _buildWeekDayColumn(
    BuildContext context, {
    required DateTime day,
    required List<ScheduleEntry> allEntries,
  }) {
    final ml = MaterialLocalizations.of(context);
    final weekdayLabel = ml.narrowWeekdays[day.weekday % 7];
    final dateLabel = '${day.month}/${day.day}';
    final selected = sameDay(day, _selectedDay);

    final dayEntries = entriesForDay(day: day, allEntries: allEntries).toList()
      ..sort((a, b) {
        final aMinutes = a.time.hour * 60 + a.time.minute;
        final bMinutes = b.time.hour * 60 + b.time.minute;
        return aMinutes.compareTo(bMinutes);
      });

    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: SizedBox(
        width: 160,
        child: Material(
          color: selected ? Colors.teal.withAlpha(20) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _jumpToDay(day),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                border: Border.all(
                  color: selected ? Colors.teal : Colors.grey.shade300,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '$weekdayLabel  $dateLabel',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: selected ? Colors.teal.shade700 : null,
                          ),
                        ),
                      ),
                      if (selected)
                        Icon(
                          Icons.circle,
                          size: 8,
                          color: Colors.teal.shade400,
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (dayEntries.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      child: Text(
                        AppStrings.of(context, 'calendar_week_empty'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 12,
                        ),
                      ),
                    )
                  else
                    ...dayEntries.map(
                      (e) => _buildWeekEntryCard(context, e, day: day),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWeekEntryCard(
    BuildContext context,
    ScheduleEntry e, {
    required DateTime day,
  }) {
    final color = e.color.withAlpha((0.88 * 255).round());
    final status =
        sameDay(day, _selectedDay) && e.id != null && e.id!.isNotEmpty
        ? _statusByTaskId[e.id!]
        : null;
    final chips = _buildEntryMetaChips(e, status: status);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 3, offset: Offset(0, 1)),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(iconForTag(e.tag), size: 16, color: Colors.white70),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _scheduleTitleLabel(context, e.title),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Wrap(spacing: 6, runSpacing: 4, children: chips),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _viewLabel(BuildContext context, _CalendarView view) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    switch (view) {
      case _CalendarView.day:
        return isEn ? 'Day' : '日';
      case _CalendarView.week:
        return isEn ? 'Week' : '周';
      case _CalendarView.month:
        return isEn ? 'Month' : '月';
      case _CalendarView.gantt:
        return isEn ? 'Gantt' : '甘特';
    }
  }

  String _fieldLabel(BuildContext context, _CalendarField field) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    switch (field) {
      case _CalendarField.time:
        return isEn ? 'Time' : '时间';
      case _CalendarField.tag:
        return isEn ? 'Tag' : '标签';
      case _CalendarField.status:
        return isEn ? 'Status' : '状态';
      case _CalendarField.reminder:
        return isEn ? 'Reminder' : '提醒';
      case _CalendarField.goal:
        return isEn ? 'Goal' : '目标';
    }
  }

  int _entryDurationMinutes(ScheduleEntry entry) {
    return ((entry.height / 80.0) * 60.0).round().clamp(1, 24 * 60);
  }

  int _entryStartMinutes(ScheduleEntry entry) {
    return entry.time.hour * 60 + entry.time.minute;
  }

  bool _entryHasGoalLink(ScheduleEntry entry) {
    return (entry.goalId != null && entry.goalId!.isNotEmpty) ||
        (entry.goalTaskId != null && entry.goalTaskId!.isNotEmpty);
  }

  List<ScheduleEntry> _entriesForMonth(
    DateTime monthAnchor,
    List<ScheduleEntry> allEntries,
  ) {
    final start = DateTime(monthAnchor.year, monthAnchor.month, 1);
    final end = DateTime(monthAnchor.year, monthAnchor.month + 1, 1);
    final out = <ScheduleEntry>[];

    for (
      var day = start;
      day.isBefore(end);
      day = day.add(const Duration(days: 1))
    ) {
      out.addAll(entriesForDay(day: day, allEntries: allEntries));
    }

    out.sort((a, b) {
      final aMinutes = a.time.hour * 60 + a.time.minute;
      final bMinutes = b.time.hour * 60 + b.time.minute;
      return aMinutes.compareTo(bMinutes);
    });
    return out;
  }

  List<DateTime> _monthGridDays(DateTime anchor) {
    final first = DateTime(anchor.year, anchor.month, 1);
    final gridStart = startOfWeek(first);
    return List.generate(42, (i) => gridStart.add(Duration(days: i)));
  }

  Widget _buildInfoChip({
    required String label,
    IconData? icon,
    Color background = Colors.white24,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: Colors.white70),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildEntryMetaChips(
    ScheduleEntry entry, {
    _EntryStatus? status,
    bool includeReminder = true,
  }) {
    final chips = <Widget>[];

    if (_visibleFields.contains(_CalendarField.time)) {
      chips.add(
        _buildInfoChip(label: entry.time.format(context), icon: Icons.schedule),
      );
    }

    if (_visibleFields.contains(_CalendarField.tag) && entry.tag.isNotEmpty) {
      chips.add(
        _buildInfoChip(
          label: _tagLabel(context, entry.tag),
          icon: iconForTag(entry.tag),
        ),
      );
    }

    if (_visibleFields.contains(_CalendarField.status) && status != null) {
      chips.add(_statusPill(status));
    }

    if (_visibleFields.contains(_CalendarField.reminder) &&
        includeReminder &&
        entry.reminderMinutesBefore > 0) {
      final isEn = Localizations.localeOf(context).languageCode == 'en';
      chips.add(
        _buildInfoChip(
          label: isEn
              ? '${entry.reminderMinutesBefore}m before'
              : '${entry.reminderMinutesBefore} 分钟前',
          icon: Icons.notifications_none,
        ),
      );
    }

    if (_visibleFields.contains(_CalendarField.goal) &&
        _entryHasGoalLink(entry)) {
      chips.add(
        _buildInfoChip(
          label: _fieldLabel(context, _CalendarField.goal),
          icon: Icons.flag_outlined,
        ),
      );
    }

    return chips;
  }

  Widget _buildMonthOverviewCard(
    BuildContext context,
    List<ScheduleEntry> monthEntries,
  ) {
    final activeDays = <String>{};
    final reminderCount = monthEntries
        .where((e) => e.reminderMinutesBefore > 0)
        .length;
    final goalCount = monthEntries.where(_entryHasGoalLink).length;

    for (final entry in monthEntries) {
      final day = entry.day;
      if (day != null) {
        activeDays.add('${day.year}-${day.month}-${day.day}');
      }
    }

    final totalMinutes = monthEntries.fold<int>(
      0,
      (sum, entry) => sum + _entryDurationMinutes(entry),
    );

    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withAlpha(160),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.calendar_month_outlined,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _viewLabel(context, _CalendarView.month),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                MaterialLocalizations.of(context).formatMonthYear(_selectedDay),
                style: TextStyle(color: theme.colorScheme.outline),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildInfoChip(
                label: '${monthEntries.length}',
                icon: Icons.event_available,
                background: theme.colorScheme.primary.withAlpha(120),
              ),
              _buildInfoChip(
                label: '${activeDays.length}',
                icon: Icons.date_range,
                background: theme.colorScheme.secondary.withAlpha(120),
              ),
              _buildInfoChip(
                label: '${reminderCount}',
                icon: Icons.notifications_active_outlined,
                background: theme.colorScheme.tertiary.withAlpha(120),
              ),
              _buildInfoChip(
                label: '${goalCount}',
                icon: Icons.flag_outlined,
                background: Colors.black26,
              ),
              _buildInfoChip(
                label: '${totalMinutes}m',
                icon: Icons.schedule_outlined,
                background: Colors.black26,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMonthView(BuildContext context, List<ScheduleEntry> allEntries) {
    final monthAnchor = DateTime(_selectedDay.year, _selectedDay.month, 1);
    final monthEntries = _entriesForMonth(monthAnchor, allEntries);
    final gridDays = _monthGridDays(monthAnchor);
    final ml = MaterialLocalizations.of(context);
    final weekdayLabels = [
      ml.narrowWeekdays[1],
      ml.narrowWeekdays[2],
      ml.narrowWeekdays[3],
      ml.narrowWeekdays[4],
      ml.narrowWeekdays[5],
      ml.narrowWeekdays[6],
      ml.narrowWeekdays[0],
    ];

    final bottomPadding = MediaQuery.of(context).padding.bottom + 100;

    return ListView(
      padding: EdgeInsets.fromLTRB(12, 8, 12, bottomPadding),
      children: [
        _buildMonthOverviewCard(context, monthEntries),
        const SizedBox(height: 12),
        Row(
          children: weekdayLabels
              .map(
                (label) => Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  ),
                ),
              )
              .toList(growable: false),
        ),
        const SizedBox(height: 8),
        ...List.generate(6, (weekIndex) {
          final days = gridDays
              .skip(weekIndex * 7)
              .take(7)
              .toList(growable: false);
          return SizedBox(
            height: 116,
            child: Row(
              children: days
                  .map(
                    (day) => Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: _buildMonthDayCell(
                          context,
                          day: day,
                          monthAnchor: monthAnchor,
                          allEntries: allEntries,
                        ),
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildMonthDayCell(
    BuildContext context, {
    required DateTime day,
    required DateTime monthAnchor,
    required List<ScheduleEntry> allEntries,
  }) {
    final inMonth = day.month == monthAnchor.month;
    final selected = sameDay(day, _selectedDay);
    final today = sameDay(day, dateOnly(DateTime.now()));
    final dayEntries = entriesForDay(day: day, allEntries: allEntries).toList()
      ..sort((a, b) {
        final aMinutes = a.time.hour * 60 + a.time.minute;
        final bMinutes = b.time.hour * 60 + b.time.minute;
        return aMinutes.compareTo(bMinutes);
      });

    final theme = Theme.of(context);
    final borderColor = selected
        ? theme.colorScheme.primary
        : today
        ? theme.colorScheme.tertiary
        : theme.colorScheme.outlineVariant;

    return Material(
      color: selected
          ? theme.colorScheme.primaryContainer.withAlpha(150)
          : theme.colorScheme.surfaceContainerLowest.withAlpha(
              inMonth ? 255 : 170,
            ),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _jumpToDay(day),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            border: Border.all(color: borderColor),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Opacity(
            opacity: inMonth ? 1.0 : 0.45,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final showCountChip =
                        dayEntries.isNotEmpty && constraints.maxWidth >= 44;
                    return Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${day.day}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: selected
                                  ? theme.colorScheme.primary
                                  : null,
                            ),
                          ),
                        ),
                        if (showCountChip)
                          _buildInfoChip(
                            label: '${dayEntries.length}',
                            icon: Icons.circle,
                            background: Colors.black26,
                          ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 6),
                if (dayEntries.isEmpty)
                  Expanded(
                    child: Center(
                      child: Text(
                        ' ',
                        style: TextStyle(color: theme.colorScheme.outline),
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.max,
                        children: [
                          ...dayEntries
                              .take(1)
                              .map(
                                (entry) => Padding(
                                  padding: const EdgeInsets.only(bottom: 2),
                                  child: _buildMonthEntryLine(
                                    context,
                                    day: day,
                                    entry: entry,
                                    compact: true,
                                  ),
                                ),
                              ),
                          if (dayEntries.length > 1)
                            Text(
                              '+${dayEntries.length - 1} more',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10,
                                color: theme.colorScheme.outline,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMonthEntryLine(
    BuildContext context, {
    required DateTime day,
    required ScheduleEntry entry,
    bool compact = false,
  }) {
    if (compact) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 5,
            height: 5,
            margin: const EdgeInsets.only(top: 6, right: 5),
            decoration: BoxDecoration(
              color: entry.color,
              shape: BoxShape.circle,
            ),
          ),
          Expanded(
            child: Text(
              '${entry.time.format(context)} ${_scheduleTitleLabel(context, entry.title)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
                height: 1.05,
              ),
            ),
          ),
        ],
      );
    }

    final chips = <Widget>[];
    final status =
        sameDay(day, _selectedDay) && entry.id != null && entry.id!.isNotEmpty
        ? _statusByTaskId[entry.id!]
        : null;
    if (_visibleFields.contains(_CalendarField.time)) {
      chips.add(
        Text(
          entry.time.format(context),
          style: TextStyle(
            fontSize: 10,
            color: Theme.of(context).colorScheme.outline,
          ),
        ),
      );
    }
    if (_visibleFields.contains(_CalendarField.tag) && entry.tag.isNotEmpty) {
      chips.add(
        Text(
          _tagLabel(context, entry.tag),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        ),
      );
    }
    if (_visibleFields.contains(_CalendarField.reminder) &&
        entry.reminderMinutesBefore > 0) {
      chips.add(
        Text(
          '-${entry.reminderMinutesBefore}m',
          style: TextStyle(
            fontSize: 10,
            color: Theme.of(context).colorScheme.outline,
          ),
        ),
      );
    }
    if (_visibleFields.contains(_CalendarField.status) && status != null) {
      chips.add(
        Text(
          _statusLabel(status),
          style: TextStyle(
            fontSize: 10,
            color: Theme.of(context).colorScheme.outline,
          ),
        ),
      );
    }
    if (_visibleFields.contains(_CalendarField.goal) &&
        _entryHasGoalLink(entry)) {
      chips.add(
        Text(
          _fieldLabel(context, _CalendarField.goal),
          style: TextStyle(
            fontSize: 10,
            color: Theme.of(context).colorScheme.outline,
          ),
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 6,
          height: 6,
          margin: const EdgeInsets.only(top: 6, right: 6),
          decoration: BoxDecoration(color: entry.color, shape: BoxShape.circle),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _scheduleTitleLabel(context, entry.title),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (chips.isNotEmpty)
                Wrap(spacing: 6, runSpacing: 2, children: chips),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGanttView(BuildContext context, List<ScheduleEntry> allEntries) {
    final weekStart = startOfWeek(_selectedDay);
    final days = List.generate(7, (i) => weekStart.add(Duration(days: i)));
    final availableWidth = MediaQuery.of(context).size.width - 168;
    final timelineWidth = availableWidth > 720 ? availableWidth : 720.0;
    final bottomPadding = MediaQuery.of(context).padding.bottom + 100;

    return ListView(
      padding: EdgeInsets.fromLTRB(12, 8, 12, bottomPadding),
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: 160 + timelineWidth,
            child: Column(
              children: [
                Row(
                  children: [
                    const SizedBox(width: 160),
                    Expanded(
                      child: _buildTimelineHeader(context, timelineWidth),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ...days.map(
                  (day) => _buildGanttDaySection(
                    context,
                    day: day,
                    entries:
                        entriesForDay(day: day, allEntries: allEntries).toList()
                          ..sort((a, b) {
                            final aMinutes = a.time.hour * 60 + a.time.minute;
                            final bMinutes = b.time.hour * 60 + b.time.minute;
                            return aMinutes.compareTo(bMinutes);
                          }),
                    timelineWidth: timelineWidth,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTimelineHeader(BuildContext context, double timelineWidth) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 24,
      child: Stack(
        children: [
          for (var hour = 0; hour <= 24; hour += 2)
            Positioned(
              left: (hour / 24.0) * timelineWidth,
              top: 0,
              bottom: 0,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 1, color: theme.colorScheme.outlineVariant),
                  const SizedBox(width: 4),
                  Text(
                    hour == 24 ? '24' : hour.toString().padLeft(2, '0'),
                    style: TextStyle(
                      fontSize: 10,
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildGanttDaySection(
    BuildContext context, {
    required DateTime day,
    required List<ScheduleEntry> entries,
    required double timelineWidth,
  }) {
    final theme = Theme.of(context);
    final selected = sameDay(day, _selectedDay);
    final dayLabel = MaterialLocalizations.of(
      context,
    ).narrowWeekdays[day.weekday % 7];
    final dateLabel = '${day.month}/${day.day}';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '$dayLabel  $dateLabel',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: selected ? theme.colorScheme.primary : null,
                    ),
                  ),
                ),
                if (entries.isNotEmpty)
                  _buildInfoChip(
                    label: '${entries.length}',
                    icon: Icons.view_timeline_outlined,
                    background: Colors.black26,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (entries.isEmpty)
              Text('暂无日程条目', style: TextStyle(color: theme.colorScheme.outline))
            else
              ...entries.map(
                (entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _buildGanttEntryRow(
                    context,
                    day: day,
                    entry: entry,
                    timelineWidth: timelineWidth,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildGanttEntryRow(
    BuildContext context, {
    required DateTime day,
    required ScheduleEntry entry,
    required double timelineWidth,
  }) {
    final theme = Theme.of(context);
    final status =
        sameDay(day, _selectedDay) && entry.id != null && entry.id!.isNotEmpty
        ? _statusByTaskId[entry.id!]
        : null;
    final left = (_entryStartMinutes(entry) / (24.0 * 60.0)) * timelineWidth;
    final width =
        (_entryDurationMinutes(entry) / (24.0 * 60.0)) * timelineWidth;
    final barWidth = width < 72 ? 72.0 : width;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 160,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _scheduleTitleLabel(context, entry.title),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Text(
                '${entry.time.format(context)} · ${_entryDurationMinutes(entry)}m',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  color: theme.colorScheme.outline,
                ),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  if (_visibleFields.contains(_CalendarField.tag) &&
                      entry.tag.isNotEmpty)
                    _buildInfoChip(
                      label: _tagLabel(context, entry.tag),
                      icon: iconForTag(entry.tag),
                    ),
                  if (_visibleFields.contains(_CalendarField.reminder) &&
                      entry.reminderMinutesBefore > 0)
                    _buildInfoChip(
                      label: '-${entry.reminderMinutesBefore}m',
                      icon: Icons.notifications_none,
                    ),
                  if (_visibleFields.contains(_CalendarField.goal) &&
                      _entryHasGoalLink(entry))
                    _buildInfoChip(
                      label: _fieldLabel(context, _CalendarField.goal),
                      icon: Icons.flag_outlined,
                    ),
                  if (_visibleFields.contains(_CalendarField.status) &&
                      status != null)
                    _buildInfoChip(
                      label: _statusLabel(status),
                      icon: Icons.check_circle_outline,
                    ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: SizedBox(
            height: 34,
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _TimelineGridPainter(
                      lineColor: theme.colorScheme.outlineVariant,
                    ),
                  ),
                ),
                Positioned(
                  left: left,
                  top: 4,
                  child: Container(
                    width: barWidth,
                    height: 26,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: entry.color.withAlpha(220),
                      borderRadius: BorderRadius.circular(999),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black12,
                          blurRadius: 3,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _scheduleTitleLabel(context, entry.title),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (_visibleFields.contains(_CalendarField.reminder) &&
                            entry.reminderMinutesBefore > 0)
                          Text(
                            '-${entry.reminderMinutesBefore}m',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 10,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _showInsertUrgentDialog() {
    final titleCtrl = TextEditingController(
      text: AppStrings.of(context, 'calendar_insert_urgent_default_title'),
    );
    int minutes = 25;
    int priority = 5;
    CognitiveLoad load = CognitiveLoad.medium;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setInner) => AlertDialog(
          title: Text(AppStrings.of(ctx2, 'calendar_insert_urgent_title')),
          content: ConstrainedBox(
            constraints: MobileFeedback.dialogConstraints(ctx2, maxWidth: 420),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: titleCtrl,
                    decoration: InputDecoration(
                      labelText: AppStrings.of(ctx2, 'label_title'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(AppStrings.of(ctx2, 'label_minutes')),
                      DropdownButton<int>(
                        value: minutes,
                        items: const [10, 15, 25, 30, 45, 60]
                            .map(
                              (v) =>
                                  DropdownMenuItem(value: v, child: Text('$v')),
                            )
                            .toList(),
                        onChanged: (v) {
                          if (v != null) setInner(() => minutes = v);
                        },
                      ),
                      Text(AppStrings.of(ctx2, 'label_priority')),
                      DropdownButton<int>(
                        value: priority,
                        items: const [1, 2, 3, 4, 5]
                            .map(
                              (v) =>
                                  DropdownMenuItem(value: v, child: Text('$v')),
                            )
                            .toList(),
                        onChanged: (v) {
                          if (v != null) setInner(() => priority = v);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(AppStrings.of(ctx2, 'label_cognitive_load')),
                      DropdownButton<CognitiveLoad>(
                        value: load,
                        items: CognitiveLoad.values
                            .map(
                              (v) => DropdownMenuItem(
                                value: v,
                                child: Text(_cognitiveLoadLabel(ctx2, v)),
                              ),
                            )
                            .toList(),
                        onChanged: (v) {
                          if (v != null) setInner(() => load = v);
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(AppStrings.of(ctx2, 'btn_cancel')),
            ),
            ElevatedButton(
              onPressed: () async {
                final title = titleCtrl.text.trim();
                if (title.isEmpty) return;

                final now = DateTime.now();
                final day = dateOnly(_selectedDay);

                final due = now.add(const Duration(hours: 2));

                _urgentInserted = PlanTask(
                  id: 'urgent_${DateTime.now().microsecondsSinceEpoch}',
                  title: title,
                  durationMinutes: minutes,
                  priority: priority,
                  load: load,
                  tag: 'Urgent',
                  due: DateTime(
                    day.year,
                    day.month,
                    day.day,
                    due.hour,
                    due.minute,
                  ),
                );

                Navigator.of(ctx).pop();
                await _loadSmartSchedule();
              },
              child: Text(
                AppStrings.of(ctx2, 'calendar_insert_urgent_confirm'),
              ),
            ),
          ],
        ),
      ),
    );
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
      MobileFeedback.showInfo(
        context,
        zhMessage: msg,
        enMessage: msg,
      );
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
    final ctrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppStrings.of(ctx, 'calendar_ics_import_title')),
        content: ConstrainedBox(
          constraints: MobileFeedback.dialogConstraints(ctx, maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                AppStrings.of(ctx, 'calendar_ics_import_help'),
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: ctrl,
                minLines: 6,
                maxLines: 12,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  hintText: AppStrings.of(ctx, 'calendar_ics_import_hint'),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(AppStrings.of(ctx, 'btn_cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(AppStrings.of(ctx, 'btn_import')),
          ),
        ],
      ),
    );

    if (ok != true) return;

    final text = ctrl.text;
    if (text.trim().isEmpty) return;

    try {
      final events = IcsCodec.decodeCalendar(text);
      final d = dateOnly(_selectedDay);
      final imported = IcsBridge.eventsToSchedule(day: d, events: events);

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

      MobileFeedback.showInfo(
        context,
        zhMessage: msg,
        enMessage: msg,
      );

      await _loadSchedule();
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

  void _showAddDialog(BuildContext context) {
    final titleCtrl = TextEditingController();
    final tagCtrl = TextEditingController();
    double height = 60;
    Color color = Colors.teal;
    TimeOfDay selectedTime = TimeOfDay.now();
    int reminderMinutesBefore = 10;
    RepeatFrequency repeat = RepeatFrequency.none;
    DateTime? repeatUntil;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setInner) => AlertDialog(
          title: Text(AppStrings.of(context, 'dialog_add_title')),
          content: ConstrainedBox(
            constraints: MobileFeedback.dialogConstraints(ctx2, maxWidth: 460),
            child: SingleChildScrollView(
              child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
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
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(AppStrings.of(context, 'label_duration')),
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
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(AppStrings.of(context, 'label_start_time')),
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
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(AppStrings.of(context, 'calendar_reminder_label')),
                    DropdownButton<int>(
                      value: reminderMinutesBefore,
                      items: [
                        DropdownMenuItem(
                          value: 0,
                          child: Text(
                            AppStrings.of(context, 'calendar_reminder_none'),
                          ),
                        ),
                        ...[5, 10, 15, 30, 60].map(
                          (v) => DropdownMenuItem(value: v, child: Text('$v')),
                        ),
                      ],
                      onChanged: (v) {
                        if (v != null) {
                          setInner(() => reminderMinutesBefore = v);
                        }
                      },
                    ),
                    if (reminderMinutesBefore > 0)
                      Text(AppStrings.of(context, 'calendar_reminder_suffix')),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(AppStrings.of(context, 'calendar_repeat_label')),
                    DropdownButton<RepeatFrequency>(
                      value: repeat,
                      items: [
                        DropdownMenuItem(
                          value: RepeatFrequency.none,
                          child: Text(
                            AppStrings.of(context, 'calendar_repeat_none'),
                          ),
                        ),
                        DropdownMenuItem(
                          value: RepeatFrequency.daily,
                          child: Text(
                            AppStrings.of(context, 'calendar_repeat_daily'),
                          ),
                        ),
                        DropdownMenuItem(
                          value: RepeatFrequency.weekly,
                          child: Text(
                            AppStrings.of(context, 'calendar_repeat_weekly'),
                          ),
                        ),
                        DropdownMenuItem(
                          value: RepeatFrequency.monthly,
                          child: Text(
                            AppStrings.of(context, 'calendar_repeat_monthly'),
                          ),
                        ),
                      ],
                      onChanged: (v) {
                        if (v == null) return;
                        setInner(() {
                          repeat = v;
                          if (repeat == RepeatFrequency.none) {
                            repeatUntil = null;
                          }
                        });
                      },
                    ),
                  ],
                ),
                if (repeat != RepeatFrequency.none) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(AppStrings.of(context, 'calendar_repeat_until')),
                      TextButton(
                        onPressed: () async {
                          final now = DateTime.now();
                          final picked = await showDatePicker(
                            context: ctx2,
                            initialDate: repeatUntil ?? now,
                            firstDate: DateTime(now.year, now.month, now.day),
                            lastDate: DateTime(now.year + 10, 12, 31),
                            cancelText: AppStrings.of(context, 'btn_cancel'),
                            confirmText: AppStrings.of(context, 'btn_confirm'),
                          );
                          if (picked == null) return;
                          setInner(() {
                            repeatUntil = DateTime(
                              picked.year,
                              picked.month,
                              picked.day,
                            );
                          });
                        },
                        child: Text(
                          repeatUntil == null
                              ? AppStrings.of(
                                  context,
                                  'calendar_repeat_until_none',
                                )
                              : '${repeatUntil!.year}-${repeatUntil!.month.toString().padLeft(2, '0')}-${repeatUntil!.day.toString().padLeft(2, '0')}',
                        ),
                      ),
                      if (repeatUntil != null)
                        IconButton(
                          tooltip: AppStrings.of(context, 'btn_delete'),
                          onPressed: () => setInner(() => repeatUntil = null),
                          icon: const Icon(Icons.clear),
                        ),
                    ],
                  ),
                ],
              ],
            ),
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

                final newEntry = ScheduleEntry(
                  day: dateOnly(_selectedDay),
                  title: t,
                  tag: tg.isEmpty ? 'General' : tg,
                  height: height,
                  color: color,
                  time: selectedTime,
                  reminderMinutesBefore: reminderMinutesBefore,
                  repeat: repeat,
                  repeatUntil: repeatUntil,
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
    _EntryStatus? status,
    TimeOfDay? time,
    int? reminderMinutesBefore,
    String? goalId,
    String? goalTaskId,
    VoidCallback? onDelete,
  }) {
    final alphaColor = color.withAlpha((0.9 * 255).round());
    final displayTitle = _scheduleTitleLabel(context, title);
    final displayTag = _tagLabel(context, tag);
    final hasGoal =
        (goalId != null && goalId.isNotEmpty) ||
        (goalTaskId != null && goalTaskId.isNotEmpty);
    final chips = <Widget>[
      if (_visibleFields.contains(_CalendarField.time) && time != null)
        _buildInfoChip(
          label: time.format(context),
          icon: Icons.schedule,
          background: Colors.white24,
        ),
      if (_visibleFields.contains(_CalendarField.tag))
        _buildInfoChip(
          label: displayTag,
          icon: iconForTag(tag),
          background: Colors.white24,
        ),
      if (status != null) _statusPill(status),
      if (_visibleFields.contains(_CalendarField.reminder) &&
          reminderMinutesBefore != null &&
          reminderMinutesBefore > 0)
        _buildInfoChip(
          label: '-${reminderMinutesBefore}m',
          icon: Icons.notifications_none,
          background: Colors.white24,
        ),
      if (_visibleFields.contains(_CalendarField.goal) && hasGoal)
        _buildInfoChip(
          label: _fieldLabel(context, _CalendarField.goal),
          icon: Icons.flag_outlined,
          background: Colors.white24,
        ),
    ];
    return Stack(
      clipBehavior: Clip.none, 
      children: [
        Container(
          constraints: BoxConstraints(minHeight: height),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: alphaColor,
            borderRadius: BorderRadius.circular(8),
            boxShadow: const [
              BoxShadow(
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
                                  displayTitle,
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
                    if (chips.isNotEmpty) const SizedBox(height: 6),
                    if (chips.isNotEmpty)
                      Wrap(spacing: 6, runSpacing: 4, children: chips),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (onDelete != null)
          Positioned(
            right: 4,
            top: 4,
            child: SizedBox(
              width: 28,
              height: 28,
              child: IconButton(
                padding: EdgeInsets.zero,
                icon: const Icon(Icons.cancel, size: 20, color: Colors.white70),
                onPressed: onDelete,
              ),
            ),
          ),
      ],
    );
  }

  Widget _statusPill(_EntryStatus s) {
    final label = _statusLabel(s);
    final bg = switch (s) {
      _EntryStatus.notStarted => Colors.white24,
      _EntryStatus.inProgress => Colors.white30,
      _EntryStatus.completed => Colors.white30,
      _EntryStatus.overdue => Colors.red.withAlpha(110),
    };

    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: const TextStyle(color: Colors.white, fontSize: 9),
      ),
    );
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

class _TimelineGridPainter extends CustomPainter {
  final Color lineColor;

  const _TimelineGridPainter({required this.lineColor});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = lineColor
      ..strokeWidth = 1;

    for (var hour = 0; hour <= 24; hour += 2) {
      final x = size.width * (hour / 24.0);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _TimelineGridPainter oldDelegate) {
    return oldDelegate.lineColor != lineColor;
  }
}