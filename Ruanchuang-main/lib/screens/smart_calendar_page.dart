import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/app_services.dart';
import '../services/ics/ics_bridge.dart';
import '../services/ics/ics_codec.dart';
import '../services/ics/ics_file_saver.dart';
import '../services/emotion/emotion_policy.dart';
import '../utils/helpers.dart';
import '../utils/app_strings.dart';
import '../utils/schedule_occurrence.dart';
import '../widgets/emotion_quick_checkin_card.dart';
import 'emotion_page.dart';
import 'goals_page.dart';
import 'integrations_page.dart';

enum _CalendarMode {
  manual,
  smart,
}

enum _CalendarView {
  day,
  week,
}

enum _EntryStatus {
  notStarted,
  inProgress,
  completed,
  overdue,
}

/// 智能日程页面
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
  late DateTime _selectedDay;

  final _dataService = AppServices.dataService;

  // For demo: keep an in-memory task list for the smart planner.
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
      final status =
          isToday ? _computeStatus(entries: visible, events: events, now: now) : const <String, _EntryStatus>{};
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
    // Simple working windows: 08:00-12:00 and 13:30-18:30.
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
    // 3+ reproducible tasks for demo.
    final d = DateTime(day.year, day.month, day.day);
    return [
      PlanTask(
        id: 't_design',
        title: 'Architecture design',
        durationMinutes: 90,
        priority: 4,
        load: CognitiveLoad.high,
        tag: 'Deep Work',
        due: d.add(const Duration(hours: 12)), // 12:00
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

    final energyStatus = await _dataService.getEnergyStatus();
    final emotion = await _dataService.getEmotionState();
    final day = dateOnly(_selectedDay);

    _smartTasks = _smartTasks.isEmpty ? _seedTasks(day) : _smartTasks;

    final tasks = <PlanTask>[
      ..._smartTasks,
      if (_urgentInserted != null) _urgentInserted!,
    ];

    final tuning = await _dataService.getSchedulingTuning();
    final shapedTasks = EmotionPolicy.adaptTasks(tasks: tasks, emotion: emotion);
    final tunedTasks = shapedTasks
        .map((t) {
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
        })
        .toList();

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

    final planned =
        plan.entries.map((e) => e.copyWith(day: req.day)).toList(growable: false);

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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  double _calculateTopOffset(TimeOfDay time) {
    final double minutesFromStart = (time.hour - _startHour) * 60.0 + time.minute;
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
          IconButton(
            tooltip: AppStrings.of(context, 'goal_title'),
            icon: const Icon(Icons.flag_outlined),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const GoalsPage()),
              );
            },
          ),
          IconButton(
            tooltip: _mode == _CalendarMode.manual
                ? AppStrings.of(context, 'calendar_tooltip_switch_to_smart')
                : AppStrings.of(context, 'calendar_tooltip_switch_to_manual'),
            icon: Icon(_mode == _CalendarMode.manual ? Icons.bolt : Icons.edit_calendar),
            onPressed: () async {
              setState(() {
                _mode = _mode == _CalendarMode.manual ? _CalendarMode.smart : _CalendarMode.manual;
              });
              await _loadSchedule();
            },
          ),
          if (_mode == _CalendarMode.smart)
            IconButton(
              tooltip: AppStrings.of(context, 'calendar_tooltip_insert_urgent'),
              icon: const Icon(Icons.add_alert),
              onPressed: _showInsertUrgentDialog,
            ),
          IconButton(
            tooltip: AppStrings.of(context, 'calendar_tooltip_export_ics'),
            icon: const Icon(Icons.upload_file),
            onPressed: _exportIcs,
          ),
          IconButton(
            tooltip: AppStrings.of(context, 'calendar_tooltip_import_ics'),
            icon: const Icon(Icons.download),
            onPressed: _importIcs,
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadSchedule),
          PopupMenuButton<String>(
            tooltip: AppStrings.of(context, 'tooltip_more'),
            onSelected: (v) {
              if (v == 'emotion') {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const EmotionPage()),
                );
              } else if (v == 'goals') {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const GoalsPage()),
                );
              } else if (v == 'mcp') {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const IntegrationsPage()),
                );
              }
            },
            itemBuilder: (ctx) => [
              PopupMenuItem(
                value: 'emotion',
                child: Text(AppStrings.of(ctx, 'emo_title')),
              ),
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
                    // In smart mode, emotion is a direct scheduling input, so replan.
                    if (_mode == _CalendarMode.smart) {
                      await _loadSmartSchedule();
                    }
                  },
                ),
                _buildViewToolbar(context),
                Expanded(
                  child: _view == _CalendarView.day
                      ? _buildDayView(context, dayEntries)
                      : _buildWeekView(context, allEntries),
                ),
              ],
            ),
      floatingActionButton: _mode == _CalendarMode.manual
          ? FloatingActionButton(
              child: const Icon(Icons.add),
              onPressed: () => _showAddDialog(context),
            )
          : FloatingActionButton.extended(
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

    final label = _view == _CalendarView.week
        ? '${ml.formatMediumDate(weekStart)} - ${ml.formatMediumDate(weekEnd)}'
        : ml.formatMediumDate(_selectedDay);

    final stepDays = _view == _CalendarView.week ? 7 : 1;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SegmentedButton<_CalendarView>(
            segments: [
              ButtonSegment<_CalendarView>(
                value: _CalendarView.day,
                icon: const Icon(Icons.view_day_outlined),
                label: Text(AppStrings.of(context, 'calendar_view_day')),
              ),
              ButtonSegment<_CalendarView>(
                value: _CalendarView.week,
                icon: const Icon(Icons.view_week_outlined),
                label: Text(AppStrings.of(context, 'calendar_view_week')),
              ),
            ],
            selected: {_view},
            onSelectionChanged: (s) {
              setState(() => _view = s.first);
            },
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: () => _shiftSelectedDay(-stepDays),
                icon: const Icon(Icons.chevron_left),
              ),
              Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
              IconButton(
                onPressed: () => _shiftSelectedDay(stepDays),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _shiftSelectedDay(int deltaDays) async {
    setState(() {
      _selectedDay = dateOnly(_selectedDay.add(Duration(days: deltaDays)));
    });
    await _loadSchedule();
  }

  Future<void> _jumpToDay(DateTime day) async {
    setState(() {
      _selectedDay = dateOnly(day);
      _view = _CalendarView.day;
    });
    await _loadSchedule();
  }

  Widget _buildDayView(BuildContext context, List<ScheduleEntry> dayEntries) {
    return SingleChildScrollView(
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
                    child: Center(child: Text('${i + _startHour}:00')),
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
                            Colors.teal.withAlpha((0.08 * 255).round()),
                            Colors.teal.withAlpha((0.08 * 255).round()),
                            Colors.orange.withAlpha((0.08 * 255).round()),
                            Colors.blue.withAlpha((0.08 * 255).round()),
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

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: days
              .map((d) => _buildWeekDayColumn(context, day: d, allEntries: allEntries))
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
                    ...dayEntries.map((e) => _buildWeekEntryCard(context, e)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWeekEntryCard(BuildContext context, ScheduleEntry e) {
    final color = e.color.withAlpha((0.88 * 255).round());

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 3,
            offset: Offset(0, 1),
          ),
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
                  e.time.format(context),
                  style: const TextStyle(color: Colors.white70, fontSize: 10),
                ),
                const SizedBox(height: 2),
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
              ],
            ),
          ),
        ],
      ),
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
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleCtrl,
                decoration: InputDecoration(
                  labelText: AppStrings.of(ctx2, 'label_title'),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(AppStrings.of(ctx2, 'label_minutes')),
                  const SizedBox(width: 8),
                  DropdownButton<int>(
                    value: minutes,
                    items: const [10, 15, 25, 30, 45, 60]
                        .map((v) => DropdownMenuItem(value: v, child: Text('$v')))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setInner(() => minutes = v);
                    },
                  ),
                  const Spacer(),
                  Text(AppStrings.of(ctx2, 'label_priority')),
                  const SizedBox(width: 6),
                  DropdownButton<int>(
                    value: priority,
                    items: const [1, 2, 3, 4, 5]
                        .map((v) => DropdownMenuItem(value: v, child: Text('$v')))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setInner(() => priority = v);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(AppStrings.of(ctx2, 'label_cognitive_load')),
                  const SizedBox(width: 8),
                  DropdownButton<CognitiveLoad>(
                    value: load,
                    items: CognitiveLoad.values
                        .map((v) => DropdownMenuItem(
                              value: v,
                              child: Text(_cognitiveLoadLabel(ctx2, v)),
                            ))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setInner(() => load = v);
                    },
                  ),
                ],
              ),
            ],
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

                // Due in 2 hours: encourages queue-jump.
                final due = now.add(const Duration(hours: 2));

                _urgentInserted = PlanTask(
                  id: 'urgent_${DateTime.now().microsecondsSinceEpoch}',
                  title: title,
                  durationMinutes: minutes,
                  priority: priority,
                  load: load,
                  tag: 'Urgent',
                  due: DateTime(day.year, day.month, day.day, due.hour, due.minute),
                );

                Navigator.of(ctx).pop();
                await _loadSmartSchedule();
              },
              child: Text(AppStrings.of(ctx2, 'calendar_insert_urgent_confirm')),
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

      final msg = res.path != null
          ? AppStrings.of(
              context,
              'calendar_ics_exported_path',
              params: {'path': res.path ?? ''},
            )
          : AppStrings.of(
              context,
              'calendar_ics_exported_download',
              params: {'fileName': fileName},
            );
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppStrings.of(
              context,
              'calendar_ics_export_failed',
              params: {'error': e.toString()},
            ),
          ),
        ),
      );
    }
  }


  Future<void> _importIcs() async {
    final ctrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppStrings.of(ctx, 'calendar_ics_import_title')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              AppStrings.of(ctx, 'calendar_ics_import_help'),
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: 520,
              child: TextField(
                controller: ctrl,
                minLines: 6,
                maxLines: 12,
                decoration: InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: AppStrings.of(ctx, 'calendar_ics_import_hint'),
                ),
              ),
            ),
          ],
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

      // Sync strategy:
      // - Each imported event has a stable id: `ics_<UID>` (see IcsBridge.eventsToSchedule).
      // - LocalDataService.addScheduleEntry performs an upsert by id.
      // - We count "updated" when the same id already exists but title/start/duration changed.
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
          // Shouldn't happen for ICS import, but keep it safe.
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
        final changed = prev.title != e.title ||
            !sameTime(prev.time, e.time) ||
            !sameHeight(prev.height, e.height) ||
            !sameDay(prev.day, e.day);

        if (!changed) continue;

        // Preserve user-controlled fields that ICS doesn't carry (tag, color, reminders, etc.)
        // while syncing the fields we consider authoritative from ICS.
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
        data: {'added': added, 'updated': updated, 'totalParsed': imported.length},
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

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            msg,
          ),
        ),
      );

      await _loadSchedule();
    } catch (e, st) {
      AppServices.diagnostics.recordIcsImport(
        ok: false,
        count: 0,
        error: e.toString(),
      );
      AppServices.logStore.error('ics', 'import failed', error: e, stackTrace: st);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppStrings.of(
              context,
              'calendar_ics_import_failed',
              params: {'error': e.toString()},
            ),
          ),
        ),
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
          content: SingleChildScrollView(
            child: Column(
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
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(AppStrings.of(context, 'calendar_reminder_label')),
                    const SizedBox(width: 8),
                    DropdownButton<int>(
                      value: reminderMinutesBefore,
                      items: [
                        DropdownMenuItem(
                          value: 0,
                          child: Text(
                            AppStrings.of(context, 'calendar_reminder_none'),
                          ),
                        ),
                        ...[5, 10, 15, 30, 60]
                            .map(
                              (v) => DropdownMenuItem(
                                value: v,
                                child: Text('$v'),
                              ),
                            ),
                      ],
                      onChanged: (v) {
                        if (v != null) {
                          setInner(() => reminderMinutesBefore = v);
                        }
                      },
                    ),
                    const SizedBox(width: 6),
                    if (reminderMinutesBefore > 0)
                      Text(AppStrings.of(context, 'calendar_reminder_suffix')),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(AppStrings.of(context, 'calendar_repeat_label')),
                    const SizedBox(width: 8),
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
                  Row(
                    children: [
                      Text(AppStrings.of(context, 'calendar_repeat_until')),
                      const SizedBox(width: 8),
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
                            repeatUntil =
                                DateTime(picked.year, picked.month, picked.day);
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
    VoidCallback? onDelete,
  }) {
    final alphaColor = color.withAlpha((0.9 * 255).round());
    final displayTitle = _scheduleTitleLabel(context, title);
    final displayTag = _tagLabel(context, tag);
    return Stack(
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
                            displayTag,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                            ),
                          ),
                        ),
                        if (status != null) _statusPill(status),
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

  Widget _statusPill(_EntryStatus s) {
    String label;
    Color bg;

    switch (s) {
      case _EntryStatus.notStarted:
        label = AppStrings.of(context, 'calendar_status_not_started');
        bg = Colors.white24;
        break;
      case _EntryStatus.inProgress:
        label = AppStrings.of(context, 'calendar_status_in_progress');
        bg = Colors.white30;
        break;
      case _EntryStatus.completed:
        label = AppStrings.of(context, 'calendar_status_done');
        bg = Colors.white30;
        break;
      case _EntryStatus.overdue:
        label = AppStrings.of(context, 'calendar_status_overdue');
        bg = Colors.red.withAlpha(110);
        break;
    }

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
}





