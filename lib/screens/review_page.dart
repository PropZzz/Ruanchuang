import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/app_services.dart';
import '../services/review/review_rules.dart';
import '../utils/app_strings.dart';
import '../utils/mobile_feedback.dart';
import '../widgets/workbench_surface.dart';

enum _ReviewRange { week, month }

class ReviewPage extends StatefulWidget {
  const ReviewPage({super.key, this.clock});

  final DateTime Function()? clock;

  @override
  State<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends State<ReviewPage> {
  final _dataService = AppServices.dataService;

  ReviewReport? _weeklyReport;
  MonthReviewSummary? _monthSummary;
  List<TaskEvent> _rescueEvents = const [];
  bool _loading = false;

  _ReviewRange _range = _ReviewRange.week;
  late DateTime _weekStart;
  late DateTime _monthStart;

  @override
  void initState() {
    super.initState();
    final now = widget.clock?.call() ?? DateTime.now();
    _weekStart = _mondayOf(now);
    _monthStart = _firstDayOfMonth(now);
  }

  static DateTime _mondayOf(DateTime d) {
    final day = DateTime(d.year, d.month, d.day);
    final delta = (day.weekday + 6) % 7; // Monday=0
    return day.subtract(Duration(days: delta));
  }

  static DateTime _firstDayOfMonth(DateTime d) => DateTime(d.year, d.month, 1);

  ({DateTime from, DateTime to}) _rangeBounds({
    required _ReviewRange range,
    required DateTime weekStart,
    required DateTime monthStart,
  }) {
    if (range == _ReviewRange.week) {
      return (from: weekStart, to: weekStart.add(const Duration(days: 7)));
    }
    return (
      from: monthStart,
      to: DateTime(monthStart.year, monthStart.month + 1, 1),
    );
  }

  String _headerLabel(BuildContext context) {
    final ml = MaterialLocalizations.of(context);
    if (_range == _ReviewRange.week) {
      return '${_weekStart.year}-${_weekStart.month.toString().padLeft(2, '0')}-${_weekStart.day.toString().padLeft(2, '0')}';
    }
    return ml.formatMonthYear(_monthStart);
  }

  Future<bool> _generate({bool alreadyLoading = false}) async {
    if (_loading && !alreadyLoading) return false;

    final selectedRange = _range;
    final selectedWeek = _weekStart;
    final selectedMonth = _monthStart;
    final range = _rangeBounds(
      range: selectedRange,
      weekStart: selectedWeek,
      monthStart: selectedMonth,
    );
    if (!alreadyLoading) {
      setState(() {
        _loading = true;
      });
    }

    try {
      final events = await _dataService.getTaskEvents(range.from, range.to);
      final rescueEvents = events.where((event) {
        final reason = event.reason;
        return reason != null &&
            (reason.startsWith('rescue_accept:') ||
                reason.startsWith('rescue_undo:'));
      }).toList()..sort((a, b) => b.at.compareTo(a.at));

      if (selectedRange == _ReviewRange.week) {
        final report = await _dataService.getWeeklyReport(selectedWeek);
        if (!mounted) return false;
        setState(() {
          _weeklyReport = report;
          _rescueEvents = rescueEvents;
        });
        return true;
      }

      final summary = ReviewRules.monthlySummary(
        monthStart: range.from,
        events: events,
      );
      if (!mounted) return false;
      setState(() {
        _monthSummary = summary;
        _rescueEvents = rescueEvents;
      });
      return true;
    } catch (error, stackTrace) {
      if (mounted) {
        MobileFeedback.showError(
          context,
          category: 'review',
          message: 'generate failed',
          zhMessage: AppStrings.of(context, 'review_load_failed'),
          enMessage: AppStrings.of(context, 'review_load_failed'),
          error: error,
          stackTrace: stackTrace,
          data: {
            'range': selectedRange.name,
            'from': range.from.toIso8601String(),
            'to': range.to.toIso8601String(),
          },
        );
      }
      return false;
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _simulateWeek() async {
    if (_loading) return;
    setState(() {
      _loading = true;
    });

    try {
      final rnd = DateTime(
        _weekStart.year,
        _weekStart.month,
        _weekStart.day,
      ).microsecondsSinceEpoch;

      int pseudo(int i) => (rnd ~/ (i + 3)) % 100;
      final events = <TaskEvent>[];

      for (var dayOffset = 0; dayOffset < 7; dayOffset++) {
        final day = _weekStart.add(Duration(days: dayOffset));

        final tasks = <PlanTask>[
          PlanTask(
            id: 'sim_design_$dayOffset',
            title: '设计评审',
            durationMinutes: 60,
            priority: 4,
            load: CognitiveLoad.high,
            tag: 'Deep Work',
          ),
          PlanTask(
            id: 'sim_email_$dayOffset',
            title: '邮件集中处理',
            durationMinutes: 20,
            priority: 2,
            load: CognitiveLoad.low,
            tag: 'Micro Task',
          ),
          PlanTask(
            id: 'sim_review_$dayOffset',
            title: '需求复盘',
            durationMinutes: 45,
            priority: 3,
            load: CognitiveLoad.medium,
            tag: 'Routine',
          ),
        ];

        for (var i = 0; i < tasks.length; i++) {
          final t = tasks[i];
          final startedAt = DateTime(
            day.year,
            day.month,
            day.day,
            9 + i * 2,
            0,
          );
          final interrupts = (pseudo(dayOffset * 10 + i) % 5);
          final overrun =
              (t.tag == 'Deep Work') && (pseudo(dayOffset + i) % 2 == 0);
          final actual = overrun
              ? (t.durationMinutes * 1.6).round()
              : t.durationMinutes;
          final completed = pseudo(dayOffset * 7 + i) % 10 != 0;

          events.add(
            TaskEvent(
              id: 'e_start_${t.id}',
              taskId: t.id,
              title: t.title,
              tag: t.tag,
              load: t.load,
              at: startedAt,
              type: TaskEventType.start,
              plannedMinutes: t.durationMinutes,
              energy: EnergyTier.medium,
            ),
          );

          if (interrupts >= 3) {
            events.add(
              TaskEvent(
                id: 'e_int_${t.id}',
                taskId: t.id,
                title: t.title,
                tag: t.tag,
                at: startedAt.add(const Duration(minutes: 10)),
                type: TaskEventType.interrupt,
                interruptions: interrupts,
                reason: 'notifications',
              ),
            );
          }

          if (!completed) {
            events.add(
              TaskEvent(
                id: 'e_post_${t.id}',
                taskId: t.id,
                title: t.title,
                tag: t.tag,
                at: startedAt.add(const Duration(minutes: 30)),
                type: TaskEventType.postpone,
                reason: 'context_switch',
              ),
            );
            continue;
          }

          events.add(
            TaskEvent(
              id: 'e_done_${t.id}',
              taskId: t.id,
              title: t.title,
              tag: t.tag,
              load: t.load,
              at: startedAt.add(Duration(minutes: actual)),
              type: TaskEventType.complete,
              plannedMinutes: t.durationMinutes,
              actualMinutes: actual,
              interruptions: interrupts,
            ),
          );
        }
      }

      await _dataService.upsertTaskEvents(events);
      final generated = await _generate(alreadyLoading: true);
      if (!mounted || !generated) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppStrings.of(context, 'review_snack_simulated')),
        ),
      );
    } catch (error, stackTrace) {
      if (mounted) {
        MobileFeedback.showError(
          context,
          category: 'review',
          message: 'simulate failed',
          zhMessage: AppStrings.of(context, 'review_simulate_failed'),
          enMessage: AppStrings.of(context, 'review_simulate_failed'),
          error: error,
          stackTrace: stackTrace,
        );
      }
    } finally {
      if (mounted && _loading) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _shift(int delta) async {
    if (_loading) return;
    final previousRange = _range;
    final previousWeekStart = _weekStart;
    final previousMonthStart = _monthStart;
    setState(() {
      if (_range == _ReviewRange.week) {
        _weekStart = _weekStart.add(Duration(days: 7 * delta));
      } else {
        _monthStart = DateTime(_monthStart.year, _monthStart.month + delta, 1);
      }
    });
    final generated = await _generate();
    if (!mounted || generated) return;
    setState(() {
      _range = previousRange;
      _weekStart = previousWeekStart;
      _monthStart = previousMonthStart;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.of(context, 'review_title')),
        actions: [
          IconButton(
            tooltip: '上一周',
            onPressed: _loading ? null : () => _shift(-1),
            icon: const Icon(Icons.chevron_left),
          ),
          Center(
            child: Text(
              _headerLabel(context),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
          IconButton(
            tooltip: '下一周',
            onPressed: _loading ? null : () => _shift(1),
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SegmentedButton<_ReviewRange>(
                segments: const [
                  ButtonSegment(
                    value: _ReviewRange.week,
                    icon: Icon(Icons.view_week_outlined),
                    label: Text('周'),
                  ),
                  ButtonSegment(
                    value: _ReviewRange.month,
                    icon: Icon(Icons.calendar_month_outlined),
                    label: Text('月'),
                  ),
                ],
                selected: {_range},
                onSelectionChanged: _loading
                    ? null
                    : (next) async {
                        if (_loading) return;
                        if (next.isEmpty || next.first == _range) return;
                        final previousRange = _range;
                        final previousWeekStart = _weekStart;
                        final previousMonthStart = _monthStart;
                        setState(() => _range = next.first);
                        final generated = await _generate();
                        if (!mounted || generated) return;
                        setState(() {
                          _range = previousRange;
                          _weekStart = previousWeekStart;
                          _monthStart = previousMonthStart;
                        });
                      },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _loading ? null : _simulateWeek,
                      icon: const Icon(Icons.science_outlined),
                      label: Text(
                        AppStrings.of(context, 'review_btn_simulate_week'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _loading ? null : _generate,
                      icon: const Icon(Icons.refresh),
                      label: Text(
                        AppStrings.of(context, 'review_btn_generate_report'),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (_range == _ReviewRange.week) _buildWeeklySection(context),
              if (_range == _ReviewRange.month) _buildMonthlySection(context),
              const SizedBox(height: 12),
              _buildRescueHistory(context),
            ],
          ),
          if (_loading) const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }

  Widget _buildWeeklySection(BuildContext context) {
    final r = _weeklyReport;
    if (r == null) {
      return WorkbenchEmptyState(
        icon: Icons.insights_outlined,
        title: AppStrings.of(context, 'review_empty'),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _metricCard(
          title: AppStrings.of(context, 'review_metric_completion'),
          value:
              '${(r.completionRate * 100).round()}% (${r.completedCount}/${r.startedCount})',
        ),
        _metricCard(
          title: AppStrings.of(context, 'review_metric_time'),
          value: AppStrings.of(
            context,
            'review_metric_time_value',
            params: {
              'planned': r.plannedMinutesTotal.toString(),
              'actual': r.actualMinutesTotal.toString(),
            },
          ),
        ),
        const SizedBox(height: 8),
        _section(
          AppStrings.of(context, 'review_section_duration_buckets'),
          r.actualDurationBuckets,
        ),
        const SizedBox(height: 8),
        _section(
          AppStrings.of(context, 'review_section_delay_attribution'),
          r.delayAttribution,
        ),
        const SizedBox(height: 12),
        WorkbenchSurface(
          title: AppStrings.of(context, 'review_suggestions_title'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (r.suggestions.isEmpty)
                Text(AppStrings.of(context, 'review_suggestions_empty'))
              else
                ...r.suggestions.map(
                  (s) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text('- $s'),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        WorkbenchSurface(
          title: AppStrings.of(context, 'review_tuning_title'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppStrings.of(
                  context,
                  'review_tuning_default_duration_multiplier',
                  params: {
                    'value': r.tuning.defaultDurationMultiplier
                        .toStringAsFixed(2),
                  },
                ),
              ),
              Text(
                AppStrings.of(
                  context,
                  'review_tuning_high_load_penalty_low_energy',
                  params: {
                    'value': r.tuning.highLoadPenaltyWhenLowEnergy
                        .toStringAsFixed(2),
                  },
                ),
              ),
              const SizedBox(height: 6),
              if (r.tuning.tagDurationMultiplier.isEmpty)
                Text(AppStrings.of(context, 'review_tuning_tag_multiplier_none'))
              else
                ...r.tuning.tagDurationMultiplier.entries.map(
                  (e) => Text(
                    AppStrings.of(
                      context,
                      'review_tuning_tag_multiplier_entry',
                      params: {
                        'tag': _tagLabel(context, e.key),
                        'value': e.value.toStringAsFixed(2),
                      },
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMonthlySection(BuildContext context) {
    final s = _monthSummary;
    if (s == null) {
      return const WorkbenchEmptyState(
        icon: Icons.calendar_month_outlined,
        title: '暂无月度复盘，点击“生成报告”。',
      );
    }

    final trend = s.dailyTrend
        .where((d) => d.started > 0 || d.completed > 0)
        .toList();
    final topBottlenecks = s.bottleneckAttribution.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _metricCard(
          title: '月度完成率',
          value:
              '${(s.completionRate * 100).round()}% (${s.completedCount}/${s.startedCount})',
        ),
        _metricCard(
          title: '月度时间',
          value: '计划 ${s.plannedMinutesTotal} 分钟，实际 ${s.actualMinutesTotal} 分钟',
        ),
        _section('实际时长分布', s.actualDurationBuckets),
        const SizedBox(height: 8),
        _section('瓶颈归因', s.bottleneckAttribution),
        const SizedBox(height: 8),
        WorkbenchSurface(
          title: '周趋势',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (s.weeklyCompletionRate.isEmpty)
                const Text('暂无周趋势。')
              else
                ...s.weeklyCompletionRate.entries.map(
                  (e) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text('${e.key}: ${(e.value * 100).round()}%'),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        WorkbenchSurface(
          title: '每日执行概览',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (trend.isEmpty)
                const Text('本月暂无日常执行记录。')
              else
                ...trend
                    .take(10)
                    .map(
                      (d) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          '${d.day.month}/${d.day.day}: ${d.completed}/${d.started} '
                          '(${(d.completionRate * 100).round()}%)',
                        ),
                      ),
                    ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        if (topBottlenecks.isNotEmpty)
          _metricCard(
            title: '主要瓶颈',
            value:
                '${_reviewMapLabel(topBottlenecks.first.key)}: ${topBottlenecks.first.value}',
          ),
        const SizedBox(height: 8),
        WorkbenchSurface(
          title: '行动建议',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (s.suggestions.isEmpty)
                const Text('本月暂无具体行动建议。')
              else
                ...s.suggestions.map(
                  (line) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text('- $line'),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRescueHistory(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final material = MaterialLocalizations.of(context);
    return WorkbenchSurface(
      title: AppStrings.of(context, 'review_rescue_history'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_rescueEvents.isEmpty)
            Text(
              AppStrings.of(context, 'review_rescue_empty'),
              style: TextStyle(color: scheme.onSurfaceVariant),
            )
          else
            ..._rescueEvents.map((event) {
              final undone = event.reason!.startsWith('rescue_undo:');
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  undone
                      ? Icons.undo_rounded
                      : Icons.check_circle_outline_rounded,
                  color: undone ? scheme.tertiary : scheme.secondary,
                ),
                title: Text(event.title),
                subtitle: Text(
                  '${material.formatTimeOfDay(TimeOfDay.fromDateTime(event.at))} - '
                  '${_rescueStrategyLabel(context, event.reason!)}',
                ),
                trailing: Text(
                  _rescueStatusLabel(context, event.reason!),
                  style: TextStyle(
                    color: undone ? scheme.tertiary : scheme.secondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  String _rescueStrategyLabel(BuildContext context, String reason) {
    if (reason.endsWith('protectDeadline')) {
      return AppStrings.of(context, 'review_rescue_protect_deadline');
    }
    if (reason.endsWith('protectRecovery')) {
      return AppStrings.of(context, 'review_rescue_protect_recovery');
    }
    if (reason.endsWith('minimizeChanges')) {
      return AppStrings.of(context, 'review_rescue_minimize_changes');
    }
    return reason;
  }

  String _rescueStatusLabel(BuildContext context, String reason) {
    if (reason.startsWith('rescue_undo:')) {
      return AppStrings.of(context, 'review_rescue_undone');
    }
    return AppStrings.of(context, 'review_rescue_accepted');
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

  String _reviewMapLabel(String key) {
    switch (key) {
      case '<=15':
        return '0 - 15 分钟';
      case '16-30':
        return '16 - 30 分钟';
      case '31-60':
        return '31 - 60 分钟';
      case '61-120':
        return '61 - 120 分钟';
      case '121+':
        return '121 分钟以上';
      case 'underestimated':
        return '预估偏低';
      case 'interruptions':
        return '打断';
      case 'context_switch':
        return '上下文切换';
      case 'carry_over':
        return '顺延';
      case 'unknown':
        return '未知';
    }
    return key;
  }

  Widget _metricCard({required String title, required String value}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: WorkbenchSurface(
        child: WorkbenchMetric(label: title, value: value),
      ),
    );
  }

  Widget _section(String title, Map<String, int> data) {
    final scheme = Theme.of(context).colorScheme;
    return WorkbenchSurface(
      title: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (data.isEmpty)
            Text('暂无数据。', style: TextStyle(color: scheme.onSurfaceVariant))
          else
            ...data.entries.map(
              (e) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('${_reviewMapLabel(e.key)}: ${e.value}'),
              ),
            ),
        ],
      ),
    );
  }
}
