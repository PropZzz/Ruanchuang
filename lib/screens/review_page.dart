import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/app_services.dart';
import '../theme/app_theme.dart';
import '../services/review/review_rules.dart';
import '../utils/app_strings.dart';
import '../utils/mobile_feedback.dart';
import '../utils/schedule_occurrence.dart';
import '../widgets/press_scale.dart';

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
    final day = dateOnly(d);
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
      backgroundColor: AppWindowTones.canvas(context, AppWindowTone.neutral),
      appBar: AppBar(title: Text(AppStrings.of(context, 'review_title'))),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 960;
          return Stack(
            children: [
              ListView(
                padding: EdgeInsets.all(wide ? 28 : 16),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1280),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildControls(context, wide: wide),
                          const SizedBox(height: 18),
                          KeyedSubtree(
                            key: const Key('review-metrics'),
                            child: _range == _ReviewRange.week
                                ? _buildWeeklySection(context)
                                : _buildMonthlySection(context),
                          ),
                          const SizedBox(height: 16),
                          _buildRescueHistory(context),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              if (_loading) const Center(child: CircularProgressIndicator()),
            ],
          );
        },
      ),
    );
  }

  Widget _buildControls(BuildContext context, {required bool wide}) {
    final rangeControl = SegmentedButton<_ReviewRange>(
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
    );
    final periodNavigation = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: _range == _ReviewRange.week ? '上一周' : '上个月',
          onPressed: _loading ? null : () => _shift(-1),
          icon: const Icon(Icons.chevron_left),
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 108),
          child: Text(
            _headerLabel(context),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ),
        IconButton(
          tooltip: _range == _ReviewRange.week ? '下一周' : '下个月',
          onPressed: _loading ? null : () => _shift(1),
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
    final actions = Row(
      children: [
        Expanded(
          child: PressScale(
            child: FilledButton.icon(
              onPressed: _loading ? null : _simulateWeek,
              icon: const Icon(Icons.science_outlined),
              label: Text(AppStrings.of(context, 'review_btn_simulate_week')),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: PressScale(
            child: OutlinedButton.icon(
              onPressed: _loading ? null : _generate,
              icon: const Icon(Icons.refresh),
              label: Text(AppStrings.of(context, 'review_btn_generate_report')),
            ),
          ),
        ),
      ],
    );

    if (wide) {
      return Card(
        key: const Key('review-period-controls'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          child: Row(
            children: [
              rangeControl,
              const SizedBox(width: 18),
              periodNavigation,
              const Spacer(),
              SizedBox(width: 390, child: actions),
            ],
          ),
        ),
      );
    }

    return Card(
      key: const Key('review-period-controls'),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(alignment: Alignment.centerLeft, child: rangeControl),
            const SizedBox(height: 8),
            Center(child: periodNavigation),
            const SizedBox(height: 8),
            actions,
          ],
        ),
      ),
    );
  }

  Widget _buildWeeklySection(BuildContext context) {
    final r = _weeklyReport;
    if (r == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Row(
            children: [
              Icon(
                Icons.insights_outlined,
                size: 26,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  AppStrings.of(context, 'review_empty'),
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _metricGrid([
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
        ]),
        const SizedBox(height: 12),
        _responsivePanels(
          _section(
            AppStrings.of(context, 'review_section_duration_buckets'),
            r.actualDurationBuckets,
          ),
          _section(
            AppStrings.of(context, 'review_section_delay_attribution'),
            r.delayAttribution,
          ),
        ),
        const SizedBox(height: 12),
        _buildSuggestionPanel(
          AppStrings.of(context, 'review_suggestions_title'),
          r.suggestions,
          AppStrings.of(context, 'review_suggestions_empty'),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionHeading(
                  context,
                  AppStrings.of(context, 'review_tuning_title'),
                  Icons.tune,
                ),
                const SizedBox(height: 10),
                _tuningValue(
                  AppStrings.of(
                    context,
                    'review_tuning_default_duration_multiplier',
                    params: {
                      'value': r.tuning.defaultDurationMultiplier
                          .toStringAsFixed(2),
                    },
                  ),
                ),
                _tuningValue(
                  AppStrings.of(
                    context,
                    'review_tuning_high_load_penalty_low_energy',
                    params: {
                      'value': r.tuning.highLoadPenaltyWhenLowEnergy
                          .toStringAsFixed(2),
                    },
                  ),
                ),
                const SizedBox(height: 4),
                if (r.tuning.tagDurationMultiplier.isEmpty)
                  Text(
                    AppStrings.of(context, 'review_tuning_tag_multiplier_none'),
                  )
                else
                  ...r.tuning.tagDurationMultiplier.entries.map(
                    (entry) => _tuningValue(
                      AppStrings.of(
                        context,
                        'review_tuning_tag_multiplier_entry',
                        params: {
                          'tag': _tagLabel(context, entry.key),
                          'value': entry.value.toStringAsFixed(2),
                        },
                      ),
                    ),
                  ),
                const SizedBox(height: 10),
                Text(
                  AppStrings.of(context, 'review_tip_replan'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMonthlySection(BuildContext context) {
    final s = _monthSummary;
    if (s == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('暂无月度复盘，点击“生成报告”。'),
        ),
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
        _metricGrid([
          _metricCard(
            title: '月度完成率',
            value:
                '${(s.completionRate * 100).round()}% (${s.completedCount}/${s.startedCount})',
          ),
          _metricCard(
            title: '月度时间',
            value:
                '计划 ${s.plannedMinutesTotal} 分钟，实际 ${s.actualMinutesTotal} 分钟',
          ),
          if (topBottlenecks.isNotEmpty)
            _metricCard(
              title: '主要瓶颈',
              value:
                  '${_reviewMapLabel(topBottlenecks.first.key)}: ${topBottlenecks.first.value}',
            ),
        ]),
        const SizedBox(height: 12),
        _responsivePanels(
          _section('实际时长分布', s.actualDurationBuckets),
          _section('瓶颈归因', s.bottleneckAttribution),
        ),
        const SizedBox(height: 12),
        _responsivePanels(
          _buildTrendPanel('周趋势', s.weeklyCompletionRate),
          _buildDailyTrendPanel(trend),
        ),
        const SizedBox(height: 12),
        _buildSuggestionPanel('行动建议', s.suggestions, '本月暂无具体行动建议。'),
      ],
    );
  }

  Widget _buildTrendPanel(String title, Map<String, double> values) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeading(context, title, Icons.show_chart),
            const SizedBox(height: 14),
            if (values.isEmpty)
              const Text('暂无周趋势。')
            else
              ...values.entries.map(
                (entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      SizedBox(width: 72, child: Text(entry.key)),
                      Expanded(
                        child: LinearProgressIndicator(
                          value: entry.value.clamp(0.0, 1.0),
                          minHeight: 8,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text('${(entry.value * 100).round()}%'),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDailyTrendPanel(List<DailyReviewPoint> trend) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeading(
              context,
              '每日执行概览',
              Icons.calendar_view_week_outlined,
            ),
            const SizedBox(height: 14),
            if (trend.isEmpty)
              const Text('本月暂无日常执行记录。')
            else
              ...trend.take(10).map((day) {
                final percent = day.completionRate.clamp(0.0, 1.0);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 54,
                        child: Text('${day.day.month}/${day.day.day}'),
                      ),
                      Expanded(
                        child: LinearProgressIndicator(
                          value: percent,
                          minHeight: 8,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text('${day.completed}/${day.started}'),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildSuggestionPanel(
    String title,
    List<String> suggestions,
    String emptyMessage,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeading(context, title, Icons.lightbulb_outline),
            const SizedBox(height: 10),
            if (suggestions.isEmpty)
              Text(emptyMessage)
            else
              ...suggestions.map(
                (suggestion) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.arrow_right_alt,
                        size: 18,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 6),
                      Expanded(child: Text(suggestion)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _tuningValue(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Text(text),
    );
  }

  Widget _sectionHeading(BuildContext context, String text, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 19, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.titleMedium),
        ),
      ],
    );
  }

  Widget _metricGrid(List<Widget> metrics) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 820 ? 2 : 1;
        final gap = 12.0;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: metrics
              .map((metric) => SizedBox(width: width, child: metric))
              .toList(),
        );
      },
    );
  }

  Widget _responsivePanels(Widget first, Widget second) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 820) {
          return Column(children: [first, const SizedBox(height: 12), second]);
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: first),
            const SizedBox(width: 12),
            Expanded(child: second),
          ],
        );
      },
    );
  }

  Widget _buildRescueHistory(BuildContext context) {
    final material = MaterialLocalizations.of(context);
    final statusColor = Theme.of(context).colorScheme;
    return Card(
      key: const Key('review-rescue-history'),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeading(
              context,
              AppStrings.of(context, 'review_rescue_history'),
              Icons.route_outlined,
            ),
            const SizedBox(height: 8),
            if (_rescueEvents.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(AppStrings.of(context, 'review_rescue_empty')),
              )
            else
              ..._rescueEvents.map((event) {
                final undone = event.reason!.startsWith('rescue_undo:');
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    undone ? Icons.undo : Icons.check_circle_outline,
                    color: undone
                        ? statusColor.onSurfaceVariant
                        : statusColor.tertiary,
                  ),
                  title: Text(event.title),
                  subtitle: Text(
                    '${material.formatTimeOfDay(TimeOfDay.fromDateTime(event.at))} - '
                    '${_rescueStrategyLabel(context, event.reason!)}',
                  ),
                  trailing: Text(
                    _rescueStatusLabel(context, event.reason!),
                    style: TextStyle(
                      color: undone
                          ? statusColor.onSurfaceVariant
                          : statusColor.tertiary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                );
              }),
          ],
        ),
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(String title, Map<String, int> data) {
    final maximum = data.values.fold<int>(
      0,
      (current, value) => value > current ? value : current,
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeading(context, title, Icons.bar_chart_outlined),
            const SizedBox(height: 14),
            if (data.isEmpty)
              const Text('当前周期暂无统计数据。')
            else
              ...data.entries.map(
                (entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(child: Text(_reviewMapLabel(entry.key))),
                          Text(
                            entry.value.toString(),
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      LinearProgressIndicator(
                        value: maximum == 0 ? 0.0 : entry.value / maximum,
                        minHeight: 7,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
