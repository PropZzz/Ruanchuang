import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/app_services.dart';
import '../utils/app_strings.dart';
import '../utils/mobile_feedback.dart';

class TeamPage extends StatefulWidget {
  const TeamPage({super.key});

  @override
  State<TeamPage> createState() => _TeamPageState();
}

class _TeamPageState extends State<TeamPage> {
  final _dataService = AppServices.dataService;

  bool _loading = true;

  List<TeamMemberCalendar> _calendars = [];
  List<TeamMember> _members = [];
  List<GoldenWindow> _golden = [];
  List<TeamConflict> _conflicts = [];

  // Conflict probe (manual check) for visual highlight in merged view.
  TimeOfDay? _probeStart;
  int _probeMinutes = 60;
  List<String> _probeConflicts = const [];

  // P0 knobs.
  static const int _meetingMinutes = 60;
  static const int _minParticipants = 2;
  static const EnergyTier _minEnergy = EnergyTier.medium;

  @override
  void initState() {
    super.initState();
    _load();
  }

  List<TimeWindow> _defaultWindows() {
    return const [
      TimeWindow(
        start: TimeOfDay(hour: 9, minute: 0),
        end: TimeOfDay(hour: 12, minute: 0),
      ),
      TimeWindow(
        start: TimeOfDay(hour: 13, minute: 30),
        end: TimeOfDay(hour: 18, minute: 30),
      ),
    ];
  }

  String _energyTierLabel(BuildContext context, EnergyTier tier) {
    switch (tier) {
      case EnergyTier.veryLow:
        return AppStrings.of(context, 'energy_tier_very_low');
      case EnergyTier.low:
        return AppStrings.of(context, 'energy_tier_low');
      case EnergyTier.medium:
        return AppStrings.of(context, 'energy_tier_medium');
      case EnergyTier.high:
        return AppStrings.of(context, 'energy_tier_high');
      case EnergyTier.veryHigh:
        return AppStrings.of(context, 'energy_tier_very_high');
    }
  }

  String _sharePermissionLabel(BuildContext context, TeamSharePermission perm) {
    switch (perm) {
      case TeamSharePermission.none:
        return AppStrings.of(context, 'team_share_permission_none');
      case TeamSharePermission.freeBusy:
        return AppStrings.of(context, 'team_share_permission_free_busy');
      case TeamSharePermission.details:
        return AppStrings.of(context, 'team_share_permission_details');
    }
  }

  TeamMember? _memberForCalendar(TeamMemberCalendar calendar) {
    for (final member in _members) {
      if (member.name == calendar.displayName) return member;
    }
    return null;
  }

  double _averageProgress() {
    if (_members.isEmpty) return 0.0;
    final total = _members.fold<double>(0.0, (sum, member) => sum + member.progress);
    return (total / _members.length).clamp(0.0, 1.0).toDouble();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
    });

    try {
      final sw = Stopwatch()..start();

      final day = DateTime.now();
      final calendarsFuture = _dataService.getTeamCalendars(day);
      final membersFuture = _dataService.getTeamMembers();
      final calendars = await calendarsFuture;
      final members = await membersFuture;

      final result = AppServices.teamCollabEngine.compute(
        day: DateTime(day.year, day.month, day.day),
        windows: _defaultWindows(),
        calendars: calendars,
        minParticipants: _minParticipants,
        meetingMinutes: _meetingMinutes,
        minEnergy: _minEnergy,
      );

      sw.stop();
      AppServices.logStore.info(
        'team',
        'compute golden windows',
        data: {
          'ms': sw.elapsedMilliseconds,
          'members': calendars.length,
          'golden': result.goldenWindows.length,
          'conflicts': result.busyOverlaps.length,
        },
      );

      if (!mounted) return;

      setState(() {
        _calendars = calendars;
        _members = members;
        _golden = result.goldenWindows;
        _conflicts = result.busyOverlaps;
        _loading = false;
      });
    } catch (e, st) {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
      MobileFeedback.showError(
        context,
        category: 'team',
        message: 'load team data failed',
        zhMessage: '暂时无法加载团队数据，请稍后重试。',
        enMessage: 'Unable to load team data right now.',
        error: e,
        stackTrace: st,
      );
    }
  }

  Future<void> _updatePermission(
    TeamMemberCalendar member,
    TeamSharePermission permission,
  ) async {
    try {
      await _dataService.updateTeamSharePermission(member.memberId, permission);
      if (!mounted) return;
      await _load();
    } catch (e, st) {
      if (!mounted) return;
      MobileFeedback.showError(
        context,
        category: 'team',
        message: 'update team permission failed',
        zhMessage: '暂时无法更新共享权限，请稍后重试。',
        enMessage: 'Unable to update the sharing permission.',
        error: e,
        stackTrace: st,
      );
    }
  }

  Future<void> _book(GoldenWindow w) async {
    try {
      final sw = Stopwatch()..start();

      final day = DateTime.now();
      await _dataService.bookTeamMeeting(
        DateTime(day.year, day.month, day.day),
        TeamMeetingRequest(
          title: AppStrings.of(context, 'team_meeting_title'),
          start: w.start,
          minutes: _meetingMinutes,
          participantIds: w.participantIds,
        ),
      );

      sw.stop();
      AppServices.logStore.info(
        'team',
        'book meeting',
        data: {
          'ms': sw.elapsedMilliseconds,
          'start': '${w.start.hour}:${w.start.minute}',
          'minutes': _meetingMinutes,
          'participants': w.participantIds.length,
        },
      );

      if (!mounted) return;

      setState(() {
        _probeStart = w.start;
        _probeMinutes = _meetingMinutes;
        _probeConflicts = const [];
      });

      MobileFeedback.showInfo(
        context,
        zhMessage: AppStrings.of(
          context,
          'team_snack_booked_meeting',
          params: {'time': w.start.format(context)},
        ),
        enMessage: AppStrings.of(
          context,
          'team_snack_booked_meeting',
          params: {'time': w.start.format(context)},
        ),
      );

      await _load();
    } catch (e, st) {
      if (!mounted) return;
      MobileFeedback.showError(
        context,
        category: 'team',
        message: 'book meeting failed',
        zhMessage: '暂时无法预约会议，请稍后重试。',
        enMessage: 'Unable to book the meeting right now.',
        error: e,
        stackTrace: st,
      );
    }
  }

  void _showConflictCheck() {
    TimeOfDay start = const TimeOfDay(hour: 15, minute: 0);
    int minutes = _meetingMinutes;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setInner) => AlertDialog(
          title: Text(AppStrings.of(ctx2, 'team_conflict_check_title')),
          content: ConstrainedBox(
            constraints: MobileFeedback.dialogConstraints(ctx2, maxWidth: 380),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(AppStrings.of(ctx2, 'label_start')),
                    TextButton(
                      onPressed: () async {
                        final t = await showTimePicker(
                          context: ctx2,
                          initialTime: start,
                        );
                        if (t != null) setInner(() => start = t);
                      },
                      child: Text(start.format(ctx2)),
                    ),
                  ],
                ),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(AppStrings.of(ctx2, 'label_minutes')),
                    DropdownButton<int>(
                      value: minutes,
                      items: const [15, 30, 45, 60, 90]
                          .map(
                            (v) =>
                                DropdownMenuItem(value: v, child: Text('$v')),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v != null) setInner(() => minutes = v);
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(AppStrings.of(ctx2, 'btn_cancel')),
            ),
            ElevatedButton(
              onPressed: () {
                final day = DateTime.now();
                final conflicts = AppServices.teamCollabEngine.conflictsFor(
                  day: DateTime(day.year, day.month, day.day),
                  start: start,
                  minutes: minutes,
                  calendars: _calendars,
                );
                AppServices.logStore.info(
                  'team',
                  'conflict check',
                  data: {
                    'start': '${start.hour}:${start.minute}',
                    'minutes': minutes,
                    'conflicts': conflicts.length,
                  },
                );

                setState(() {
                  _probeStart = start;
                  _probeMinutes = minutes;
                  _probeConflicts = conflicts;
                });

                Navigator.of(ctx).pop();
                showDialog(
                  context: context,
                  builder: (ctx3) => AlertDialog(
                    title: Text(AppStrings.of(ctx3, 'team_conflicts_title')),
                    content: Text(
                      conflicts.isEmpty
                          ? AppStrings.of(ctx3, 'team_no_conflicts')
                          : AppStrings.of(
                              ctx3,
                              'team_busy_members',
                              params: {'members': conflicts.join(', ')},
                            ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(ctx3).pop(),
                        child: Text(AppStrings.of(ctx3, 'btn_ok')),
                      ),
                    ],
                  ),
                );
              },
              child: Text(AppStrings.of(ctx2, 'btn_check')),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCompactAppBar = MobileFeedback.isNarrow(context, breakpoint: 760);
    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.of(context, 'team_title')),
        actions: [
          if (!isCompactAppBar)
            IconButton(
              icon: const Icon(Icons.search),
              onPressed: _showConflictCheck,
            ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
          if (isCompactAppBar)
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'conflict') {
                  _showConflictCheck();
                }
              },
              itemBuilder: (ctx) => [
                PopupMenuItem(
                  value: 'conflict',
                  child: Text(AppStrings.of(ctx, 'team_conflict_check_title')),
                ),
              ],
            ),
        ],
      ),
      body: _loading
          ? const _TeamLoadingState()
          : Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    theme.colorScheme.secondaryContainer.withValues(
                      alpha: 0.26,
                    ),
                    theme.colorScheme.surface,
                  ],
                ),
              ),
              child: SafeArea(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1400),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final isWide = constraints.maxWidth >= 1100;
                        final bottomPadding = MediaQuery.of(context).padding.bottom + 100;
                        return ListView(
                          padding: EdgeInsets.fromLTRB(16, 16, 16, bottomPadding),
                          children: [
                            Card(
                              elevation: 0,
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Wrap(
                                  spacing: 10,
                                  runSpacing: 10,
                                  children: [
                                    _TeamKpiChip(
                                      icon: Icons.people_outline,
                                      label: 'Members',
                                      value: _calendars.length.toString(),
                                    ),
                                    _TeamKpiChip(
                                      icon: Icons.stars_outlined,
                                      label: 'Golden',
                                      value: _golden.length.toString(),
                                    ),
                                    _TeamKpiChip(
                                      icon: Icons.error_outline,
                                      label: 'Conflicts',
                                      value: _conflicts.length.toString(),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            _buildProgressPanel(context),
                            const SizedBox(height: 12),
                            if (isWide)
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    flex: 5,
                                    child: _buildRecommendationPanel(context),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    flex: 7,
                                    child: _buildMergedSchedulePanel(context),
                                  ),
                                ],
                              )
                            else ...[
                              _buildRecommendationPanel(context),
                              const SizedBox(height: 12),
                              _buildMergedSchedulePanel(context),
                            ],
                            const SizedBox(height: 12),
                            if (isWide)
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(child: _buildConflictPanel(context)),
                                  const SizedBox(width: 12),
                                  Expanded(child: _buildMemberPanel(context)),
                                ],
                              )
                            else ...[
                              _buildConflictPanel(context),
                              const SizedBox(height: 12),
                              _buildMemberPanel(context),
                            ],
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildProgressPanel(BuildContext context) {
    final avgProgress = _averageProgress();

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle(context, AppStrings.of(context, 'team_track_title')),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    AppStrings.of(context, 'team_label_progress'),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Text('${(avgProgress * 100).round()}%'),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: avgProgress),
            const SizedBox(height: 12),
            if (_members.isEmpty)
              Text(AppStrings.of(context, 'team_no_members'))
            else
              ..._members.map((member) {
                final percent = (member.progress * 100).round();
                final taskLabel = member.task.isEmpty
                    ? AppStrings.of(context, 'team_label_task')
                    : member.task;
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                member.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            Chip(label: Text('$percent%')),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(taskLabel),
                        const SizedBox(height: 8),
                        LinearProgressIndicator(value: member.progress),
                      ],
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildRecommendationPanel(BuildContext context) {
    final compact = MobileFeedback.isNarrow(context, breakpoint: 760);
    return Card(
      elevation: 0,
      color: Theme.of(
        context,
      ).colorScheme.secondaryContainer.withValues(alpha: 0.5),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle(context, AppStrings.of(context, 'team_rec_title')),
            const SizedBox(height: 8),
            Text(
              AppStrings.of(
                context,
                'team_golden_windows_header',
                params: {
                  'participants': _minParticipants.toString(),
                  'energy': _energyTierLabel(context, _minEnergy),
                },
              ),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            if (_golden.isEmpty)
              Text(
                AppStrings.of(context, 'team_golden_windows_empty'),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              )
            else
              ..._golden.map((w) {
                final endMin =
                    w.start.hour * 60 + w.start.minute + _meetingMinutes;
                final end = TimeOfDay(
                  hour: (endMin ~/ 60) % 24,
                  minute: endMin % 60,
                );
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: compact
                      ? Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${w.start.format(context)} - ${end.format(context)}',
                              ),
                              const SizedBox(height: 4),
                              Text(
                                AppStrings.of(
                                  context,
                                  'team_free_members',
                                  params: {
                                    'count': w.participantIds.length.toString(),
                                  },
                                ),
                              ),
                              const SizedBox(height: 12),
                              ElevatedButton(
                                onPressed: () => _book(w),
                                child: Text(
                                  AppStrings.of(context, 'team_btn_book'),
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListTile(
                          dense: true,
                          title: Text(
                            '${w.start.format(context)} - ${end.format(context)}',
                          ),
                          subtitle: Text(
                            AppStrings.of(
                              context,
                              'team_free_members',
                              params: {
                                'count': w.participantIds.length.toString(),
                              },
                            ),
                          ),
                          trailing: ElevatedButton(
                            onPressed: () => _book(w),
                            child: Text(AppStrings.of(context, 'team_btn_book')),
                          ),
                        ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildMergedSchedulePanel(BuildContext context) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle(
              context,
              AppStrings.of(context, 'team_merged_schedule_today'),
            ),
            const SizedBox(height: 8),
            TeamMergedScheduleView(
              calendars: _calendars,
              golden: _golden,
              meetingMinutes: _meetingMinutes,
              minParticipants: _minParticipants,
              probeStart: _probeStart,
              probeMinutes: _probeMinutes,
              probeConflicts: _probeConflicts,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConflictPanel(BuildContext context) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle(
              context,
              AppStrings.of(context, 'team_busy_overlap_title'),
            ),
            const SizedBox(height: 8),
            if (_conflicts.isEmpty)
              Text(
                AppStrings.of(context, 'team_busy_overlap_empty'),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              )
            else
              ..._conflicts.map(
                (c) => Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text('${c.memberA} vs ${c.memberB}'),
                    subtitle: Text(
                      '${c.start.format(context)} - ${c.end.format(context)}',
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMemberPanel(BuildContext context) {
    final locale = Localizations.localeOf(context);
    final title = locale.languageCode.startsWith('zh')
        ? '成员权限'
        : 'Members & access';

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle(context, title),
            const SizedBox(height: 8),
            ..._calendars.map((m) {
              final compact = MobileFeedback.isNarrow(context, breakpoint: 760);
              final energyColor = (m.energy.index >= EnergyTier.high.index)
                  ? Colors.green
                  : Colors.grey;
              final perm = _sharePermissionLabel(context, m.permission);
              final energy = _energyTierLabel(context, m.energy);
              final member = _memberForCalendar(m);
              final progress = member == null
                  ? '--'
                  : '${(member.progress * 100).round()}%';
              final theme = Theme.of(context);
              final progressValue =
                  (member?.progress ?? 0.0).clamp(0.0, 1.0).toDouble();
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 12,
                        runSpacing: 10,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          CircleAvatar(
                            child: Text(
                              m.displayName.isNotEmpty ? m.displayName[0] : '?',
                            ),
                          ),
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: compact ? 240 : 420,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${m.displayName} (${m.role})',
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  AppStrings.of(
                                    context,
                                    'team_member_subtitle',
                                    params: {
                                      'energy': energy,
                                      'perm': perm,
                                      'count': '${m.busy.length}',
                                    },
                                  ),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.bolt, color: energyColor, size: 18),
                        ],
                      ),
                      if (member != null) ...[
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Text(
                              '${AppStrings.of(context, 'team_label_progress')}: $progress',
                              style: theme.textTheme.labelMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(999),
                                child: LinearProgressIndicator(
                                  minHeight: 8,
                                  value: progressValue,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerRight,
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<TeamSharePermission>(
                            value: m.permission,
                            isDense: true,
                            iconSize: 18,
                            style: theme.textTheme.bodySmall,
                            items: TeamSharePermission.values
                                .map(
                                  (p) => DropdownMenuItem(
                                    value: p,
                                    child: Text(_sharePermissionLabel(context, p)),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) {
                              if (value == null) return;
                              _updatePermission(m, value);
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String title) {
    return Text(
      title,
      style: Theme.of(
        context,
      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
    );
  }
}

class _TeamLoadingState extends StatelessWidget {
  const _TeamLoadingState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('正在加载团队看板...'),
          ],
        ),
      ),
    );
  }
}

class _TeamKpiChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _TeamKpiChip({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.42),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 6),
          Text('$label: $value'),
        ],
      ),
    );
  }
}

class _TimeSegment {
  final int startMin;
  final int endMin;
  final int busyCount;
  const _TimeSegment({
    required this.startMin,
    required this.endMin,
    required this.busyCount,
  });
}

int _m(TimeOfDay t) => t.hour * 60 + t.minute;

int _durFromHeight(double height) =>
    ((height / 80.0) * 60.0).round().clamp(1, 24 * 60).toInt();

class TeamMergedScheduleView extends StatefulWidget {
  final List<TeamMemberCalendar> calendars;
  final List<GoldenWindow> golden;
  final int meetingMinutes;
  final int minParticipants;
  final TimeOfDay? probeStart;
  final int probeMinutes;
  final List<String> probeConflicts;

  const TeamMergedScheduleView({
    super.key,
    required this.calendars,
    required this.golden,
    required this.meetingMinutes,
    required this.minParticipants,
    required this.probeStart,
    required this.probeMinutes,
    required this.probeConflicts,
  });

  @override
  State<TeamMergedScheduleView> createState() => _TeamMergedScheduleViewState();
}

class _TeamMergedScheduleViewState extends State<TeamMergedScheduleView> {
  late final ScrollController _horizontalController;
  late final ScrollController _verticalController;

  List<TeamMemberCalendar> get calendars => widget.calendars;
  List<GoldenWindow> get golden => widget.golden;
  int get meetingMinutes => widget.meetingMinutes;
  TimeOfDay? get probeStart => widget.probeStart;
  int get probeMinutes => widget.probeMinutes;
  List<String> get probeConflicts => widget.probeConflicts;

  @override
  void initState() {
    super.initState();
    _horizontalController = ScrollController();
    _verticalController = ScrollController();
  }

  @override
  void dispose() {
    _horizontalController.dispose();
    _verticalController.dispose();
    super.dispose();
  }

  static const double _hourHeight = 80.0;
  static const int _startHour = 8;
  static const int _endHour = 20;
  static const double _timeLabelWidth = 54.0;
  static const double _laneWidth = 132.0;
  static const int _stepMinutes = 10;

  int get _rangeStartMin => _startHour * 60;
  int get _rangeEndMin => _endHour * 60;

  double _topForMinute(int minute) =>
      ((minute - _rangeStartMin) / 60.0) * _hourHeight;

  List<_TimeSegment> _busyHeatSegments() {
    if (calendars.isEmpty) return const [];

    final busyCountBySlot = <int, int>{};

    for (final c in calendars) {
      if (c.permission == TeamSharePermission.none) continue;
      for (final b in c.busy) {
        final bs = _m(b.time);
        final be = bs + _durFromHeight(b.height);
        final s = bs < _rangeStartMin ? _rangeStartMin : bs;
        final e = be > _rangeEndMin ? _rangeEndMin : be;
        for (var t = s; t < e; t += _stepMinutes) {
          busyCountBySlot[t] = (busyCountBySlot[t] ?? 0) + 1;
        }
      }
    }

    final segments = <_TimeSegment>[];
    int? segStart;
    int segMax = 0;

    void close(int endMin) {
      if (segStart == null) return;
      segments.add(
        _TimeSegment(startMin: segStart!, endMin: endMin, busyCount: segMax),
      );
      segStart = null;
      segMax = 0;
    }

    for (var t = _rangeStartMin; t <= _rangeEndMin; t += _stepMinutes) {
      final cnt = busyCountBySlot[t] ?? 0;
      final isHot = cnt >= 2;
      if (isHot) {
        segStart ??= t;
        if (cnt > segMax) segMax = cnt;
      } else {
        close(t);
      }
    }
    close(_rangeEndMin);

    return segments;
  }

  @override
  Widget build(BuildContext context) {
    if (calendars.isEmpty) {
      return Text(
        AppStrings.of(context, 'team_no_members'),
        style: const TextStyle(color: Colors.grey),
      );
    }

    final height = (_endHour - _startHour) * _hourHeight;
    final now = TimeOfDay.fromDateTime(DateTime.now());

    final laneCount = calendars.length;
    final contentWidth = _timeLabelWidth + _laneWidth * laneCount;
    final heatSegments = _busyHeatSegments();

    final probeStartMin = probeStart == null ? null : _m(probeStart!);
    final probeEndMin = probeStartMin == null
        ? null
        : probeStartMin + probeMinutes;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _LegendChip(
              color: Colors.green.withValues(alpha: 0.18),
              label: AppStrings.of(context, 'team_legend_golden'),
            ),
            _LegendChip(
              color: const Color(0xFFD68C89).withValues(alpha: 0.12),
              label: AppStrings.of(context, 'team_legend_busy_overlap'),
            ),
            _LegendChip(
              color: Colors.blue.withValues(alpha: 0.14),
              label: AppStrings.of(context, 'team_legend_conflict_probe'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 420,
          child: Scrollbar(
            controller: _horizontalController,
            child: SingleChildScrollView(
              controller: _horizontalController,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: contentWidth,
                child: Column(
                  children: [
                    SizedBox(
                      height: 34,
                      child: Row(
                        children: [
                          const SizedBox(width: _timeLabelWidth),
                          for (final c in calendars)
                            SizedBox(
                              width: _laneWidth,
                              child: Center(
                                child: Text(
                                  c.displayName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: Scrollbar(
                        controller: _verticalController,
                        child: SingleChildScrollView(
                          controller: _verticalController,
                          primary: false,
                          child: SizedBox(
                            height: height,
                            child: Stack(
                              children: [
                                // Hour grid + time labels.
                                for (var h = _startHour; h <= _endHour; h++)
                                  Positioned(
                                    top: (h - _startHour) * _hourHeight,
                                    left: 0,
                                    right: 0,
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        SizedBox(
                                          width: _timeLabelWidth,
                                          child: Padding(
                                            padding: const EdgeInsets.only(
                                              top: 2,
                                            ),
                                            child: Text(
                                              '${h.toString().padLeft(2, '0')}:00',
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey,
                                              ),
                                            ),
                                          ),
                                        ),
                                        Expanded(
                                          child: Container(
                                            height: 1,
                                            color: Colors.grey.withValues(
                                              alpha: 0.2,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                // Busy overlap heat zones (>=2 busy).
                                for (final seg in heatSegments)
                                  Positioned(
                                    top: _topForMinute(seg.startMin),
                                    left: _timeLabelWidth,
                                    width: _laneWidth * laneCount,
                                    height:
                                        _topForMinute(seg.endMin) -
                                        _topForMinute(seg.startMin),
                                    child: Container(
                                      color: const Color(0xFFD68C89).withValues(
                                        alpha:
                                            (0.05 + (seg.busyCount - 2) * 0.03)
                                                .clamp(0.05, 0.16)
                                                .toDouble(),
                                      ),
                                    ),
                                  ),

                                // Golden window highlights (draw meeting-length blocks).
                                for (final w in golden)
                                  Positioned(
                                    top: _topForMinute(_m(w.start)),
                                    left: _timeLabelWidth,
                                    width: _laneWidth * laneCount,
                                    height:
                                        (meetingMinutes / 60.0) * _hourHeight,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: Colors.green.withValues(
                                          alpha: 0.12,
                                        ),
                                        border: Border.all(
                                          color: Colors.green.withValues(
                                            alpha: 0.35,
                                          ),
                                        ),
                                      ),
                                      child: Align(
                                        alignment: Alignment.topLeft,
                                        child: Padding(
                                          padding: const EdgeInsets.all(6),
                                          child: Text(
                                            AppStrings.of(
                                              context,
                                              'team_recommended',
                                            ),
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.green.shade900,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),

                                // Conflict probe highlight (manual check).
                                if (probeStartMin != null &&
                                    probeEndMin != null)
                                  Positioned(
                                    top: _topForMinute(probeStartMin),
                                    left: _timeLabelWidth,
                                    width: _laneWidth * laneCount,
                                    height:
                                        _topForMinute(probeEndMin) -
                                        _topForMinute(probeStartMin),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: probeConflicts.isEmpty
                                            ? Colors.green.withValues(
                                                alpha: 0.10,
                                              )
                                            : Colors.blue.withValues(
                                                alpha: 0.10,
                                              ),
                                        border: Border.all(
                                          color: probeConflicts.isEmpty
                                              ? Colors.green
                                              : Colors.blue,
                                          width: 2,
                                        ),
                                      ),
                                    ),
                                  ),

                                // Member busy blocks.
                                for (var i = 0; i < calendars.length; i++)
                                  for (final b in calendars[i].busy)
                                    if (calendars[i].permission !=
                                        TeamSharePermission.none)
                                      Positioned(
                                        top: _topForMinute(_m(b.time)),
                                        left:
                                            _timeLabelWidth +
                                            i * _laneWidth +
                                            6,
                                        width: _laneWidth - 12,
                                        height: b.height,
                                        child: _BusyBlock(
                                          entry: b,
                                          permission: calendars[i].permission,
                                          memberName: calendars[i].displayName,
                                        ),
                                      ),

                                // Now line.
                                Positioned(
                                  top: _topForMinute(_m(now)),
                                  left: 0,
                                  right: 0,
                                  child: Row(
                                    children: [
                                      const SizedBox(width: _timeLabelWidth),
                                      Expanded(
                                        child: Container(
                                          height: 1.5,
                                          color: Colors.blue.withValues(
                                            alpha: 0.6,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (probeStart != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              probeConflicts.isEmpty
                  ? AppStrings.of(
                      context,
                      'team_probe_ok',
                      params: {
                        'time': probeStart!.format(context),
                        'minutes': probeMinutes.toString(),
                      },
                    )
                  : AppStrings.of(
                      context,
                      'team_probe_conflict',
                      params: {
                        'time': probeStart!.format(context),
                        'minutes': probeMinutes.toString(),
                        'members': probeConflicts.join(', '),
                      },
                    ),
              style: TextStyle(
                color: probeConflicts.isEmpty
                    ? Colors.green.shade800
                    : Colors.blue.shade800,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }
}

class _LegendChip extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendChip({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _BusyBlock extends StatelessWidget {
  final ScheduleEntry entry;
  final TeamSharePermission permission;
  final String memberName;

  const _BusyBlock({
    required this.entry,
    required this.permission,
    required this.memberName,
  });

  @override
  Widget build(BuildContext context) {
    final showDetails = permission == TeamSharePermission.details;
    final busyLabel = AppStrings.of(context, 'team_busy');
    final title = showDetails ? entry.title : busyLabel;
    final subtitle = showDetails ? entry.tag : '';

    final bg = showDetails
        ? entry.color.withValues(alpha: 0.85)
        : Colors.grey.withValues(alpha: 0.75);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text(showDetails ? title : busyLabel),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppStrings.of(
                      ctx,
                      'team_dialog_member',
                      params: {'name': memberName},
                    ),
                  ),
                  Text(
                    AppStrings.of(
                      ctx,
                      'team_dialog_start',
                      params: {'time': entry.time.format(ctx)},
                    ),
                  ),
                  Text(
                    AppStrings.of(
                      ctx,
                      'team_dialog_duration',
                      params: {
                        'minutes': _durFromHeight(entry.height).toString(),
                      },
                    ),
                  ),
                  if (showDetails)
                    Text(
                      AppStrings.of(
                        ctx,
                        'team_dialog_tag',
                        params: {'tag': entry.tag},
                      ),
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text(AppStrings.of(ctx, 'btn_ok')),
                ),
              ],
            ),
          );
        },
        child: Container(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.all(8),
          child: DefaultTextStyle(
            style: const TextStyle(color: Colors.white),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
