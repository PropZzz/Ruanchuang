import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/app_services.dart';
import '../utils/app_strings.dart';

class ReviewPage extends StatefulWidget {
  const ReviewPage({super.key});

  @override
  State<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends State<ReviewPage> {
  final _dataService = AppServices.dataService;

  ReviewReport? _report;
  bool _loading = false;

  DateTime _weekStart = _mondayOf(DateTime.now());

  static DateTime _mondayOf(DateTime d) {
    final day = DateTime(d.year, d.month, d.day);
    final delta = (day.weekday + 6) % 7; // Monday=0
    return day.subtract(Duration(days: delta));
  }

  Future<void> _generate() async {
    setState(() {
      _loading = true;
    });
    final report = await _dataService.getWeeklyReport(_weekStart);
    if (!mounted) return;
    setState(() {
      _report = report;
      _loading = false;
    });
  }

  Future<void> _simulateWeek() async {
    setState(() {
      _loading = true;
    });

    // Create a reproducible 7-day simulation.
    final rnd = DateTime(_weekStart.year, _weekStart.month, _weekStart.day)
        .microsecondsSinceEpoch;

    int pseudo(int i) => (rnd ~/ (i + 3)) % 100;

    for (var dayOffset = 0; dayOffset < 7; dayOffset++) {
      final day = _weekStart.add(Duration(days: dayOffset));

      final tasks = <PlanTask>[
        PlanTask(
          id: 'sim_design_$dayOffset',
          title: 'Design session',
          durationMinutes: 60,
          priority: 4,
          load: CognitiveLoad.high,
          tag: 'Deep Work',
        ),
        PlanTask(
          id: 'sim_email_$dayOffset',
          title: 'Email batch',
          durationMinutes: 20,
          priority: 2,
          load: CognitiveLoad.low,
          tag: 'Micro Task',
        ),
        PlanTask(
          id: 'sim_review_$dayOffset',
          title: 'Spec review',
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
        final completed = pseudo(dayOffset * 7 + i) % 10 != 0; // ~10% incomplete

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

    final report = await _dataService.getWeeklyReport(_weekStart);

    if (!mounted) return;
    setState(() {
      _report = report;
      _loading = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppStrings.of(context, 'review_snack_simulated')),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = _report;

    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.of(context, 'review_title')),
        actions: [
          IconButton(
            tooltip: AppStrings.of(context, 'review_tooltip_prev_week'),
            onPressed: () {
              setState(() {
                _weekStart = _weekStart.subtract(const Duration(days: 7));
              });
            },
            icon: const Icon(Icons.chevron_left),
          ),
          Center(
            child: Text(
              '${_weekStart.toLocal()}'.split(' ')[0],
              style: const TextStyle(fontSize: 12),
            ),
          ),
          IconButton(
            tooltip: AppStrings.of(context, 'review_tooltip_next_week'),
            onPressed: () {
              setState(() {
                _weekStart = _weekStart.add(const Duration(days: 7));
              });
            },
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _simulateWeek,
                        icon: const Icon(Icons.science_outlined),
                        label: Text(
                          AppStrings.of(context, 'review_btn_simulate_week'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _generate,
                        icon: const Icon(Icons.refresh),
                        label: Text(
                          AppStrings.of(context, 'review_btn_generate_report'),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (r == null)
                  Text(AppStrings.of(context, 'review_empty'))
                else ...[
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
                  Text(
                    AppStrings.of(context, 'review_suggestions_title'),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  if (r.suggestions.isEmpty)
                    Text(AppStrings.of(context, 'review_suggestions_empty'))
                  else
                    ...r.suggestions.map((s) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text('• $s'),
                        )),
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
                    ...r.tuning.tagDurationMultiplier.entries
                        .map(
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
                  const SizedBox(height: 8),
                  Text(
                    AppStrings.of(context, 'review_tip_replan'),
                    style: const TextStyle(color: Colors.grey),
                  ),
                ],
              ],
            ),
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

  Widget _metricCard({required String title, required String value}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
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
            ...data.entries.map((e) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('${e.key}: ${e.value}'),
                )),
          ],
        ),
      ),
    );
  }
}
