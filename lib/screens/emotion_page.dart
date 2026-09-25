import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/app_services.dart';
import '../services/emotion/emotion_policy.dart';
import '../utils/app_strings.dart';

class EmotionPage extends StatefulWidget {
  const EmotionPage({super.key});

  @override
  State<EmotionPage> createState() => _EmotionPageState();
}

class _EmotionPageState extends State<EmotionPage> {
  final _data = AppServices.dataService;

  bool _loading = true;
  bool _saving = false;
  Object? _loadError;
  EmotionState _state = EmotionState.stable;
  List<EmotionCheckIn> _today = const [];
  List<_EmotionDay> _week = const [];
  String? _careHint;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }

    final now = DateTime.now();
    final days = List<DateTime>.generate(7, (index) {
      final date = now.subtract(Duration(days: 6 - index));
      return DateTime(date.year, date.month, date.day);
    });

    try {
      final stateFuture = _data.getEmotionState();
      final checkInsFuture = Future.wait(
        days.map((day) => _data.getEmotionCheckIns(day)),
      );
      final results = await Future.wait<Object>([stateFuture, checkInsFuture]);
      final state = results[0] as EmotionState;
      final checkIns = results[1] as List<List<EmotionCheckIn>>;
      final today = checkIns.last;
      final yesterday = checkIns[5];

      EmotionState? lastState(List<EmotionCheckIn> records) {
        if (records.isEmpty) return null;
        final sorted = List<EmotionCheckIn>.from(records)
          ..sort((a, b) => a.at.compareTo(b.at));
        return sorted.last.state;
      }

      final shouldCare = EmotionPolicy.shouldShowCareHint(
        today: lastState(today),
        yesterday: lastState(yesterday),
      );
      final week = [
        for (var index = 0; index < days.length; index++)
          _EmotionDay(day: days[index], state: lastState(checkIns[index])),
      ];

      if (!mounted) return;
      setState(() {
        _state = state;
        _today = List<EmotionCheckIn>.from(today)
          ..sort((a, b) => b.at.compareTo(a.at));
        _week = week;
        _careHint = shouldCare ? AppStrings.of(context, 'emo_care_hint') : null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error;
        _loading = false;
      });
    }
  }

  String _label(BuildContext context, EmotionState state) {
    switch (state) {
      case EmotionState.efficient:
        return AppStrings.of(context, 'emo_efficient');
      case EmotionState.stable:
        return AppStrings.of(context, 'emo_stable');
      case EmotionState.tired:
        return AppStrings.of(context, 'emo_tired');
      case EmotionState.irritable:
        return AppStrings.of(context, 'emo_irritable');
    }
  }

  String _shortLabel(BuildContext context, EmotionState state) {
    switch (state) {
      case EmotionState.efficient:
        return AppStrings.of(context, 'emo_efficient');
      case EmotionState.stable:
        return AppStrings.of(context, 'emo_stable');
      case EmotionState.tired:
        return AppStrings.of(context, 'emo_tired');
      case EmotionState.irritable:
        return AppStrings.of(context, 'emo_irritable');
    }
  }

  Color _color(BuildContext context, EmotionState state) {
    final scheme = Theme.of(context).colorScheme;
    switch (state) {
      case EmotionState.efficient:
        return scheme.tertiary;
      case EmotionState.stable:
        return scheme.secondary;
      case EmotionState.tired:
        return const Color(0xFF9A4D00);
      case EmotionState.irritable:
        return scheme.error;
    }
  }

  IconData _icon(EmotionState state) {
    switch (state) {
      case EmotionState.efficient:
        return Icons.bolt_rounded;
      case EmotionState.stable:
        return Icons.spa_outlined;
      case EmotionState.tired:
        return Icons.battery_2_bar_rounded;
      case EmotionState.irritable:
        return Icons.bolt_outlined;
    }
  }

  Future<void> _checkIn(EmotionState state) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await _data.addEmotionCheckIn(
        EmotionCheckIn(id: '', at: DateTime.now(), state: state),
      );
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${AppStrings.of(context, 'emo_checked_in')}: ${_label(context, state)}',
          ),
        ),
      );
      final careHint = _careHint;
      if (careHint != null) await _showCareDialog(careHint);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.of(context, 'common_fail'))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _showCareDialog(String hint) => showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.favorite_outline),
      title: Text(AppStrings.of(ctx, 'emo_title')),
      content: Text(hint),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(AppStrings.of(ctx, 'btn_confirm')),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final guidance = EmotionPolicy.adaptiveSnapshot(
      emotion: _state,
      recentCheckInCount: _today.length,
      careHint: _careHint != null,
    );

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(AppStrings.of(context, 'emo_title')),
            Text(
              'EMOTION & ENERGY',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            key: const ValueKey('emotion-refresh-action'),
            tooltip: AppStrings.of(context, 'calendar_refresh'),
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
          ? _EmotionLoadFailure(onRetry: _load)
          : LayoutBuilder(
              builder: (context, constraints) {
                final wideLayout = constraints.maxWidth >= 940;
                return ListView(
                  padding: EdgeInsets.fromLTRB(
                    24,
                    20,
                    24,
                    MediaQuery.paddingOf(context).bottom + 100,
                  ),
                  children: [
                    if (_careHint != null) ...[
                      _CareHintBanner(message: _careHint!),
                      const SizedBox(height: 16),
                    ],
                    if (wideLayout)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: _buildOverview(context, guidance)),
                          const SizedBox(width: 16),
                          Expanded(child: _buildCheckInPanel(context)),
                        ],
                      )
                    else ...[
                      _buildOverview(context, guidance),
                      const SizedBox(height: 16),
                      _buildCheckInPanel(context),
                    ],
                    const SizedBox(height: 16),
                    if (wideLayout)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: _buildTrendPanel(context)),
                          const SizedBox(width: 16),
                          Expanded(child: _buildTodayPanel(context)),
                        ],
                      )
                    else ...[
                      _buildTrendPanel(context),
                      const SizedBox(height: 16),
                      _buildTodayPanel(context),
                    ],
                  ],
                );
              },
            ),
    );
  }

  Widget _buildOverview(
    BuildContext context,
    EmotionAdaptiveSnapshot guidance,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final color = _color(context, _state);
    return _SurfacePanel(
      key: const ValueKey('emotion-overview'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeading(
            title: '当前状态概览',
            detail: '基于最近一次真实打卡',
            icon: Icons.monitor_heart_outlined,
          ),
          const SizedBox(height: 22),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(_icon(_state), color: color, size: 29),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _label(context, _state),
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _today.isEmpty ? '今天还没有打卡记录' : '今天已记录 ${_today.length} 次',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (_today.isNotEmpty)
                Text(
                  '${_today.length}',
                  key: const ValueKey('emotion-checkin-count'),
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: color,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
          Divider(color: scheme.outlineVariant),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.lightbulb_outline, color: scheme.primary, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      guidance.headline,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      guidance.detail,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (guidance.highlights.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: guidance.highlights
                  .map((highlight) => _InfoTag(label: highlight))
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCheckInPanel(BuildContext context) {
    return _SurfacePanel(
      key: const ValueKey('emotion-checkin-options'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeading(
            title: AppStrings.of(context, 'emo_quick'),
            detail: '选择最贴近此刻的状态',
            icon: Icons.touch_app_outlined,
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 430;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _CheckInOption(
                    key: const ValueKey('emotion-checkin-efficient'),
                    label: _shortLabel(context, EmotionState.efficient),
                    icon: _icon(EmotionState.efficient),
                    color: _color(context, EmotionState.efficient),
                    selected: _state == EmotionState.efficient,
                    busy: _saving,
                    width: compact ? (constraints.maxWidth - 10) / 2 : null,
                    onTap: () => _checkIn(EmotionState.efficient),
                  ),
                  _CheckInOption(
                    key: const ValueKey('emotion-checkin-stable'),
                    label: _shortLabel(context, EmotionState.stable),
                    icon: _icon(EmotionState.stable),
                    color: _color(context, EmotionState.stable),
                    selected: _state == EmotionState.stable,
                    busy: _saving,
                    width: compact ? (constraints.maxWidth - 10) / 2 : null,
                    onTap: () => _checkIn(EmotionState.stable),
                  ),
                  _CheckInOption(
                    key: const ValueKey('emotion-checkin-tired'),
                    label: _shortLabel(context, EmotionState.tired),
                    icon: _icon(EmotionState.tired),
                    color: _color(context, EmotionState.tired),
                    selected: _state == EmotionState.tired,
                    busy: _saving,
                    width: compact ? (constraints.maxWidth - 10) / 2 : null,
                    onTap: () => _checkIn(EmotionState.tired),
                  ),
                  _CheckInOption(
                    key: const ValueKey('emotion-checkin-irritable'),
                    label: _shortLabel(context, EmotionState.irritable),
                    icon: _icon(EmotionState.irritable),
                    color: _color(context, EmotionState.irritable),
                    selected: _state == EmotionState.irritable,
                    busy: _saving,
                    width: compact ? (constraints.maxWidth - 10) / 2 : null,
                    onTap: () => _checkIn(EmotionState.irritable),
                  ),
                ],
              );
            },
          ),
          if (_saving) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(minHeight: 2),
          ],
        ],
      ),
    );
  }

  Widget _buildTrendPanel(BuildContext context) {
    final hasRecords = _week.any((day) => day.state != null);
    final scheme = Theme.of(context).colorScheme;
    return _SurfacePanel(
      key: const ValueKey('emotion-week-trend'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeading(
            title: '近七日状态',
            detail: '来自每天最后一次打卡',
            icon: Icons.show_chart_rounded,
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 156,
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _EmotionTrendPainter(
                      days: _week,
                      lineColor: scheme.primary,
                      gridColor: scheme.outlineVariant,
                      dotColors: [
                        _color(context, EmotionState.efficient),
                        _color(context, EmotionState.stable),
                        _color(context, EmotionState.tired),
                        _color(context, EmotionState.irritable),
                      ],
                    ),
                  ),
                ),
                if (!hasRecords)
                  Center(
                    child: Text(
                      '记录出现后会显示在这里',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final day in _week)
                Text(
                  _weekday(day.day),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              for (final state in EmotionState.values)
                _LegendDot(
                  color: _color(context, state),
                  label: _label(context, state),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTodayPanel(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _SurfacePanel(
      key: const ValueKey('emotion-today-records'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeading(
            title: AppStrings.of(context, 'emo_today'),
            detail: '情绪变化记录',
            icon: Icons.history_rounded,
          ),
          const SizedBox(height: 12),
          if (_today.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 12),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: [
                  Icon(Icons.edit_note_rounded, color: scheme.onSurfaceVariant),
                  const SizedBox(height: 6),
                  Text(
                    AppStrings.of(context, 'emo_today_empty'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '从上方选择状态开始记录',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            )
          else
            ..._today.map((entry) {
              final color = _color(context, entry.state);
              final time = MaterialLocalizations.of(
                context,
              ).formatTimeOfDay(TimeOfDay.fromDateTime(entry.at.toLocal()));
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Icon(_icon(entry.state), color: color, size: 18),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _label(context, entry.state),
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          if (entry.note != null && entry.note!.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(
                              entry.note!,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Text(
                      time,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  String _weekday(DateTime day) {
    final shortDays = ['一', '二', '三', '四', '五', '六', '日'];
    return '${shortDays[day.weekday - 1]}';
  }
}

class _EmotionDay {
  const _EmotionDay({required this.day, required this.state});

  final DateTime day;
  final EmotionState? state;
}

class _SurfacePanel extends StatelessWidget {
  const _SurfacePanel({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: child,
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({
    required this.title,
    required this.detail,
    required this.icon,
  });

  final String title;
  final String detail;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, color: scheme.primary, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text(
                detail,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _InfoTag extends StatelessWidget {
  const _InfoTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelSmall),
    );
  }
}

class _CheckInOption extends StatelessWidget {
  const _CheckInOption({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
    required this.selected,
    required this.busy,
    required this.onTap,
    this.width,
  });

  final String label;
  final IconData icon;
  final Color color;
  final bool selected;
  final bool busy;
  final VoidCallback onTap;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: width,
      child: Material(
        color: selected
            ? color.withValues(alpha: 0.1)
            : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: busy ? null : onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: color, size: 19),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: scheme.onSurface,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
                if (selected) ...[
                  const SizedBox(width: 6),
                  Icon(Icons.check, color: color, size: 16),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}

class _EmotionLoadFailure extends StatelessWidget {
  const _EmotionLoadFailure({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined, color: scheme.error, size: 32),
            const SizedBox(height: 10),
            Text(
              '暂时无法加载情绪记录',
              key: const ValueKey('emotion-load-error'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              '已有记录不会被修改，请重试。',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const ValueKey('emotion-load-retry'),
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: Text(AppStrings.of(context, 'common_retry')),
            ),
          ],
        ),
      ),
    );
  }
}

class _CareHintBanner extends StatelessWidget {
  const _CareHintBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.favorite_outline, color: scheme.error),
          const SizedBox(width: 10),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }
}

class _EmotionTrendPainter extends CustomPainter {
  const _EmotionTrendPainter({
    required this.days,
    required this.lineColor,
    required this.gridColor,
    required this.dotColors,
  });

  final List<_EmotionDay> days;
  final Color lineColor;
  final Color gridColor;
  final List<Color> dotColors;

  @override
  void paint(Canvas canvas, Size size) {
    final top = 10.0;
    final bottom = size.height - 12;
    final left = 8.0;
    final right = size.width - 8;
    final plotHeight = bottom - top;
    final plotWidth = right - left;
    final grid = Paint()
      ..color = gridColor.withValues(alpha: 0.72)
      ..strokeWidth = 1;

    for (var row = 0; row < 4; row++) {
      final y = top + plotHeight * row / 3;
      canvas.drawLine(Offset(left, y), Offset(right, y), grid);
    }

    final values = <Offset?>[];
    for (var index = 0; index < days.length; index++) {
      final state = days[index].state;
      if (state == null) {
        values.add(null);
        continue;
      }
      final value = switch (state) {
        EmotionState.efficient => 0.17,
        EmotionState.stable => 0.4,
        EmotionState.tired => 0.67,
        EmotionState.irritable => 0.88,
      };
      final x = left + plotWidth * index / math.max(days.length - 1, 1);
      values.add(Offset(x, top + plotHeight * value));
    }

    final line = Paint()
      ..color = lineColor
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()
      ..color = lineColor.withValues(alpha: 0.08)
      ..style = PaintingStyle.fill;
    final path = Path();
    var openSegment = false;
    for (final point in values) {
      if (point == null) {
        openSegment = false;
        continue;
      }
      if (openSegment) {
        path.lineTo(point.dx, point.dy);
      } else {
        path.moveTo(point.dx, point.dy);
        openSegment = true;
      }
    }
    canvas.drawPath(path, line);

    for (var index = 0; index < values.length; index++) {
      final point = values[index];
      final state = days[index].state;
      if (point == null || state == null) continue;
      final color = dotColors[state.index];
      canvas.drawCircle(point, 6, fill..color = color.withValues(alpha: 0.18));
      canvas.drawCircle(
        point,
        3.5,
        Paint()
          ..color = color
          ..style = PaintingStyle.fill,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _EmotionTrendPainter oldDelegate) =>
      oldDelegate.days != days ||
      oldDelegate.lineColor != lineColor ||
      oldDelegate.gridColor != gridColor;
}
