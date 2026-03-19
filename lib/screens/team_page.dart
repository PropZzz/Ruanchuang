import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/app_services.dart';
import '../utils/app_strings.dart';

class TeamPage extends StatefulWidget {
  const TeamPage({super.key});

  @override
  State<TeamPage> createState() => _TeamPageState();
}

class _TeamPageState extends State<TeamPage> {
  final _dataService = AppServices.dataService;

  bool _loading = true;

  List<TeamMemberCalendar> _calendars = [];
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

  Future<void> _load() async {
    setState(() {
      _loading = true;
    });

    final sw = Stopwatch()..start();

    final day = DateTime.now();
    final calendars = await _dataService.getTeamCalendars(day);

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
      _golden = result.goldenWindows;
      _conflicts = result.busyOverlaps;
      _loading = false;
    });
  }

  Future<void> _book(GoldenWindow w) async {
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

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          AppStrings.of(
            context,
            'team_snack_booked_meeting',
            params: {'time': w.start.format(context)},
          ),
        ),
      ),
    );

    await _load();
  }

  void _showConflictCheck() {
    TimeOfDay start = const TimeOfDay(hour: 15, minute: 0);
    int minutes = _meetingMinutes;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setInner) => AlertDialog(
          title: Text(AppStrings.of(ctx2, 'team_conflict_check_title')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Text(AppStrings.of(ctx2, 'label_start')),
                  const SizedBox(width: 8),
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
              Row(
                children: [
                  Text(AppStrings.of(ctx2, 'label_minutes')),
                  const SizedBox(width: 8),
                  DropdownButton<int>(
                    value: minutes,
                    items: const [15, 30, 45, 60, 90]
                        .map(
                          (v) => DropdownMenuItem(value: v, child: Text('$v')),
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
    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.of(context, 'team_title')),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: _showConflictCheck,
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  AppStrings.of(context, 'team_rec_title'),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 10),
                Card(
                  color: Theme.of(context).colorScheme.secondaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.stars, color: Theme.of(context).colorScheme.primary),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                AppStrings.of(
                                  context,
                                  'team_golden_windows_header',
                                  params: {
                                    'participants': _minParticipants.toString(),
                                    'energy': _energyTierLabel(context, _minEnergy),
                                  },
                                ),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (_golden.isEmpty)
                          Text(
                            AppStrings.of(context, 'team_golden_windows_empty'),
                            style: const TextStyle(color: Colors.grey),
                          )
                        else
                          ..._golden.map((w) {
                            final endMin =
                                w.start.hour * 60 +
                                w.start.minute +
                                _meetingMinutes;
                            final end = TimeOfDay(
                              hour: (endMin ~/ 60) % 24,
                              minute: endMin % 60,
                            );
                            return ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                '${w.start.format(context)} - ${end.format(context)}',
                              ),
                              subtitle: Text(
                                AppStrings.of(
                                  context,
                                  'team_free_members',
                                  params: {'count': w.participantIds.length.toString()},
                                ),
                              ),
                              trailing: ElevatedButton(
                                onPressed: () => _book(w),
                                child: Text(
                                  AppStrings.of(context, 'team_btn_book'),
                                ),
                              ),
                            );
                          }),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  AppStrings.of(context, 'team_merged_schedule_today'),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: TeamMergedScheduleView(
                      calendars: _calendars,
                      golden: _golden,
                      meetingMinutes: _meetingMinutes,
                      minParticipants: _minParticipants,
                      probeStart: _probeStart,
                      probeMinutes: _probeMinutes,
                      probeConflicts: _probeConflicts,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  AppStrings.of(context, 'team_busy_overlap_title'),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 8),
                if (_conflicts.isEmpty)
                  Text(
                    AppStrings.of(context, 'team_busy_overlap_empty'),
                    style: const TextStyle(color: Colors.grey),
                  )
                else
                  ..._conflicts.map(
                    (c) => Card(
                      child: ListTile(
                        title: Text('${c.memberA} vs ${c.memberB}'),
                        subtitle: Text(
                          '${c.start.format(context)} - ${c.end.format(context)}',
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                Text(
                  AppStrings.of(context, 'team_track_title'),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 8),
                ..._calendars.map((m) {
                  final energyColor = (m.energy.index >= EnergyTier.high.index)
                      ? Colors.green
                      : Colors.grey;
                  final perm = _sharePermissionLabel(context, m.permission);
                  final energy = _energyTierLabel(context, m.energy);
                  return Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        child: Text(
                          m.displayName.isNotEmpty ? m.displayName[0] : '?',
                        ),
                      ),
                      title: Text('${m.displayName} (${m.role})'),
                      subtitle: Text(
                        AppStrings.of(
                          context,
                          'team_member_subtitle',
                          params: {
                            'energy': energy,
                            'perm': perm,
                            'count': m.busy.length.toString(),
                          },
                        ),
                      ),
                      trailing: Icon(Icons.bolt, color: energyColor),
                    ),
                  );
                }),
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
    ((height / 80.0) * 60.0).round().clamp(1, 24 * 60);

class TeamMergedScheduleView extends StatelessWidget {
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
              color: Colors.red.withValues(alpha: 0.12),
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
            thumbVisibility: true,
            child: SingleChildScrollView(
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
                        thumbVisibility: true,
                        child: SingleChildScrollView(
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
                                      color: Colors.red.withValues(
                                        alpha:
                                            (0.05 + (seg.busyCount - 2) * 0.03)
                                                .clamp(0.05, 0.16),
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
                                            AppStrings.of(context, 'team_recommended'),
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
                      params: {'minutes': _durFromHeight(entry.height).toString()},
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
