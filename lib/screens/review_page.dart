import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/app_services.dart';
import '../services/review/review_rules.dart';
import '../utils/app_strings.dart';

enum _ReviewRange { week, month }

class ReviewPage extends StatefulWidget {
  const ReviewPage({super.key});

  @override
  State<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends State<ReviewPage> {
  final _dataService = AppServices.dataService;

  ReviewReport? _weeklyReport;
  MonthReviewSummary? _monthSummary;
  bool _loading = false;

  _ReviewRange _range = _ReviewRange.week;
  DateTime _weekStart = _mondayOf(DateTime.now());
  DateTime _monthStart = _firstDayOfMonth(DateTime.now());

  static DateTime _mondayOf(DateTime d) {
    final day = DateTime(d.year, d.month, d.day);
    final delta = (day.weekday + 6) % 7; // Monday=0
    return day.subtract(Duration(days: delta));
  }

  static DateTime _firstDayOfMonth(DateTime d) => DateTime(d.year, d.month, 1);

  String _headerLabel(BuildContext context) {
    final ml = MaterialLocalizations.of(context);
    if (_range == _ReviewRange.week) {
      return '${_weekStart.year}-${_weekStart.month.toString().padLeft(2, '0')}-${_weekStart.day.toString().padLeft(2, '0')}';
    }
    return ml.formatMonthYear(_monthStart);
  }

  Future<void> _generate() async {
    setState(() {
      _loading = true;
    });

    if (_range == _ReviewRange.week) {
      final report = await _dataService.getWeeklyReport(_weekStart);
      if (!mounted) return;
      setState(() {
        _weeklyReport = report;
        _loading = false;
      });
      return;
    }

    final from = _monthStart;
    final to = DateTime(from.year, from.month + 1, 1);
    final events = await _dataService.getTaskEvents(from, to);
    final summary = ReviewRules.monthlySummary(monthStart: from, events: events);
    if (!mounted) return;
    setState(() {
      _monthSummary = summary;
      _loading = false;
    });
  }

  Future<void> _simulateWeek() async {
    setState(() {
      _loading = true;
    });

    final rnd =
        DateTime(_weekStart.year, _weekStart.month, _weekStart.day).microsecondsSinceEpoch;

    int pseudo(int i) => (rnd ~/ (i + 3)) % 100;

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
        final startedAt = DateTime(day.year, day.month, day.day, 9 + i * 2, 0);
        final interrupts = (pseudo(dayOffset * 10 + i) % 5);
        final overrun = (t.tag == 'Deep Work') && (pseudo(dayOffset + i) % 2 == 0);
        final actual = overrun ? (t.durationMinutes * 1.6).round() : t.durationMinutes;
        final completed = pseudo(dayOffset * 7 + i) % 10 != 0;

        await _dataService.logTaskEvent(
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
          await _dataService.logTaskEvent(
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
          await _dataService.logTaskEvent(
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

        await _dataService.logTaskEvent(
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

    await _generate();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppStrings.of(context, 'review_snack_simulated'))),
    );
  }

  Future<void> _shift(int delta) async {
    setState(() {
      if (_range == _ReviewRange.week) {
        _weekStart = _weekStart.add(Duration(days: 7 * delta));
      } else {
        _monthStart = DateTime(_monthStart.year, _monthStart.month + delta, 1);
      }
    });
    await _generate();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.of(context, 'review_title')),
        actions: [
          IconButton(
            tooltip: '上一周',
            onPressed: () => _shift(-1),
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
            onPressed: () => _shift(1),
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
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
                  onSelectionChanged: (next) async {
                    if (next.isEmpty || next.first == _range) return;
                    setState(() => _range = next.first);
                    await _generate();
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _simulateWeek,
                        icon: const Icon(Icons.science_outlined),
                        label: Text(AppStrings.of(context, 'review_btn_simulate_week')),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _generate,
                        icon: const Icon(Icons.refresh),
                        label: Text(AppStrings.of(context, 'review_btn_generate_report')),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (_range == _ReviewRange.week) _buildWeeklySection(context),
                if (_range == _ReviewRange.month) _buildMonthlySection(context),
              ],
            ),
    );
  }

  Widget _buildWeeklySection(BuildContext context) {
    final r = _weeklyReport;
    if (r == null) {
      return Text(AppStrings.of(context, 'review_empty'));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _metricCard(
          title: AppStrings.of(context, 'review_metric_completion'),
          value: '${(r.completionRate * 100).round()}% (${r.completedCount}/${r.startedCount})',
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
        _section(AppStrings.of(context, 'review_section_duration_buckets'), r.actualDurationBuckets),
        const SizedBox(height: 8),
        _section(AppStrings.of(context, 'review_section_delay_attribution'), r.delayAttribution),
        const SizedBox(height: 12),
        Text(
          AppStrings.of(context, 'review_suggestions_title'),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        if (r.suggestions.isEmpty)
          Text(AppStrings.of(context, 'review_suggestions_empty'))
        else
          ...r.suggestions.map(
            (s) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text('- $s'),
            ),
          ),
        const SizedBox(height: 12),
        Text(
          AppStrings.of(context, 'review_tuning_title'),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        Text(
          AppStrings.of(
            context,
            'review_tuning_default_duration_multiplier',
            params: {'value': r.tuning.defaultDurationMultiplier.toStringAsFixed(2)},
          ),
        ),
        Text(
          AppStrings.of(
            context,
            'review_tuning_high_load_penalty_low_energy',
            params: {'value': r.tuning.highLoadPenaltyWhenLowEnergy.toStringAsFixed(2)},
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
    );
  }

  Widget _buildMonthlySection(BuildContext context) {
    final s = _monthSummary;
    if (s == null) {
      return const Text('暂无月度复盘，点击“生成报告”。');
    }

    final trend = s.dailyTrend.where((d) => d.started > 0 || d.completed > 0).toList();
    final topBottlenecks = s.bottleneckAttribution.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _metricCard(
          title: '月度完成率',
          value: '${(s.completionRate * 100).round()}% (${s.completedCount}/${s.startedCount})',
        ),
        _metricCard(
          title: '月度时间',
          value: '计划 ${s.plannedMinutesTotal} 分钟，实际 ${s.actualMinutesTotal} 分钟',
        ),
        _section('实际时长分布', s.actualDurationBuckets),
        const SizedBox(height: 8),
        _section('瓶颈归因', s.bottleneckAttribution),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('周趋势', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
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
        ),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('每日执行概览',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                if (trend.isEmpty)
                  const Text('本月暂无日常执行记录。')
                else
                  ...trend.take(10).map(
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
        ),
        const SizedBox(height: 8),
        if (topBottlenecks.isNotEmpty)
          _metricCard(
            title: '主要瓶颈',
            value:
                '${_reviewMapLabel(topBottlenecks.first.key)}: ${topBottlenecks.first.value}',
          ),
        const SizedBox(height: 8),
        const Text('行动建议', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
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
    );
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
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
            Text(value),
          ],
        ),
      ),
    );
  }

  Widget _section(String title, Map<String, int> data) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ...data.entries.map(
              (e) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('${_reviewMapLabel(e.key)}: ${e.value}'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
