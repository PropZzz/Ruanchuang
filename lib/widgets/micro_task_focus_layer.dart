import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/models.dart';
import '../theme/app_theme.dart';
import '../utils/app_strings.dart';

enum MicroFocusOutcome { completed, abandoned }

enum _EarlyCloseAction { keepGoing, abandon, markDone }

/// Opens the full-screen focus layer for a single micro task.
///
/// The layer owns the countdown and calls [onComplete] as soon as the timer
/// reaches zero. Closing the layer afterwards only dismisses the surface; the
/// task is already persisted as done.
Future<MicroFocusOutcome?> showMicroTaskFocusLayer(
  BuildContext context, {
  required MicroTask task,
  required int totalMinutes,
  required int points,
  required Future<void> Function(int activeSeconds) onComplete,
  Future<void> Function(int activeSeconds)? onAbandon,
  DateTime Function()? now,
}) {
  return showGeneralDialog<MicroFocusOutcome>(
    context: context,
    barrierDismissible: false,
    barrierLabel: AppStrings.of(context, 'micro_start_focus'),
    barrierColor: Colors.black.withValues(alpha: 0.42),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (context, animation, secondaryAnimation) {
      return MicroTaskFocusLayer(
        task: task,
        totalMinutes: totalMinutes,
        points: points,
        onComplete: onComplete,
        onAbandon: onAbandon,
        now: now,
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.97, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class MicroTaskFocusLayer extends StatefulWidget {
  const MicroTaskFocusLayer({
    super.key,
    required this.task,
    required this.totalMinutes,
    required this.points,
    required this.onComplete,
    this.onAbandon,
    this.now,
  });

  final MicroTask task;
  final int totalMinutes;
  final int points;
  final Future<void> Function(int activeSeconds) onComplete;
  final Future<void> Function(int activeSeconds)? onAbandon;
  final DateTime Function()? now;

  @override
  State<MicroTaskFocusLayer> createState() => _MicroTaskFocusLayerState();
}

class _MicroTaskFocusLayerState extends State<MicroTaskFocusLayer> {
  late final int _totalSeconds;
  late int _remainingSeconds;

  Timer? _ticker;
  DateTime? _deadline;
  bool _running = false;
  bool _completed = false;
  bool _saving = false;
  bool _saveFailed = false;
  bool _completionSaved = false;
  bool _completionRequested = false;
  bool _closeDialogOpen = false;

  int get _activeSeconds => _totalSeconds - _remainingSeconds;

  DateTime _now() => widget.now?.call() ?? DateTime.now();

  double get _progress {
    if (_totalSeconds <= 0) return 1;
    return (1 - _remainingSeconds / _totalSeconds).clamp(0.0, 1.0);
  }

  @override
  void initState() {
    super.initState();
    final minutes = widget.totalMinutes.clamp(1, 24 * 60);
    _totalSeconds = minutes * 60;
    _remainingSeconds = _totalSeconds;
    _startTicker();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _startTicker() {
    _ticker?.cancel();
    _running = true;
    _deadline = _now().add(Duration(seconds: _remainingSeconds));
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    if (!_running || _completed) return;
    final deadline = _deadline;
    if (deadline == null) return;
    final remaining = math.max(
      0,
      (deadline.difference(_now()).inMilliseconds / 1000).ceil(),
    );
    if (remaining <= 0) {
      _handleTimerFinished();
      return;
    }
    if (remaining != _remainingSeconds) {
      setState(() => _remainingSeconds = remaining);
    }
  }

  void _pause() {
    if (!_running || _completed) return;
    _ticker?.cancel();
    _ticker = null;
    final deadline = _deadline;
    if (deadline != null) {
      _remainingSeconds = math.max(
        0,
        (deadline.difference(_now()).inMilliseconds / 1000).ceil(),
      );
    }
    setState(() => _running = false);
  }

  void _resume() {
    if (_running || _completed) return;
    setState(_startTicker);
  }

  void _handleTimerFinished() {
    if (_completionRequested) return;
    _completionRequested = true;
    _ticker?.cancel();
    _ticker = null;
    setState(() {
      _running = false;
      _remainingSeconds = 0;
      _completed = true;
    });
    unawaited(_saveCompletion());
  }

  Future<bool> _saveCompletion() async {
    if (_completionSaved) return true;
    if (_saving) return false;
    setState(() {
      _saving = true;
      _saveFailed = false;
    });
    try {
      await widget.onComplete(_activeSeconds);
      if (!mounted) return true;
      setState(() {
        _saving = false;
        _completionSaved = true;
      });
      unawaited(HapticFeedback.mediumImpact());
      return true;
    } catch (_) {
      if (!mounted) return false;
      setState(() {
        _saving = false;
        _saveFailed = true;
      });
      return false;
    }
  }

  Future<void> _requestClose() async {
    if (_saving || _closeDialogOpen) return;
    if (_completed) {
      Navigator.of(context).pop(MicroFocusOutcome.completed);
      return;
    }

    _closeDialogOpen = true;
    final action = await showDialog<_EarlyCloseAction>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(AppStrings.of(dialogContext, 'micro_focus_early_title')),
        content: Text(
          AppStrings.of(
            dialogContext,
            'micro_focus_early_body',
            params: {'title': widget.task.title},
          ),
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(_EarlyCloseAction.keepGoing),
            child: Text(AppStrings.of(dialogContext, 'micro_focus_keep_going')),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(_EarlyCloseAction.abandon),
            child: Text(AppStrings.of(dialogContext, 'micro_focus_abandon')),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(_EarlyCloseAction.markDone),
            child: Text(AppStrings.of(dialogContext, 'micro_focus_mark_done')),
          ),
        ],
      ),
    );
    _closeDialogOpen = false;

    if (!mounted || action == null || action == _EarlyCloseAction.keepGoing) {
      return;
    }

    _ticker?.cancel();
    _ticker = null;

    if (action == _EarlyCloseAction.abandon) {
      try {
        await widget.onAbandon?.call(_activeSeconds);
      } catch (_) {
        // Abandon logging must never trap the user inside the focus layer.
      }
      if (mounted) {
        Navigator.of(context).pop(MicroFocusOutcome.abandoned);
      }
      return;
    }

    _completionRequested = true;
    setState(() {
      _completed = true;
      _running = false;
    });
    final saved = await _saveCompletion();
    if (saved && mounted) {
      Navigator.of(context).pop(MicroFocusOutcome.completed);
    }
  }

  String _formatDuration(int totalSeconds) {
    final duration = Duration(seconds: math.max(0, totalSeconds));
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final task = widget.task;
    final tag = task.tag.trim().isEmpty
        ? AppStrings.of(context, 'micro_group_empty')
        : task.tag.trim();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _requestClose();
      },
      child: Material(
        color: AppWindowTones.canvas(context, AppWindowTone.neutral),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                scheme.surface,
                AppWindowTones.canvas(context, AppWindowTone.neutral),
              ],
            ),
          ),
          child: SafeArea(
            child: Stack(
              children: [
                Positioned(
                  top: 8,
                  right: 8,
                  child: IconButton(
                    key: const ValueKey('micro-focus-close-icon'),
                    tooltip: AppStrings.of(context, 'btn_close'),
                    onPressed: _requestClose,
                    icon: const Icon(Icons.close_rounded),
                  ),
                ),
                Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 56, 24, 32),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 460),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.timer_outlined,
                                size: 16,
                                color: scheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                AppStrings.of(context, 'nav_focus'),
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          Text(
                            task.title,
                            key: const ValueKey('micro-focus-task-title'),
                            textAlign: TextAlign.center,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              height: 1.3,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'P${task.priority.clamp(1, 5)} · ${widget.totalMinutes} ${AppStrings.of(context, 'micro_card_min')} · $tag',
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 28),
                          Center(
                            child: SizedBox(
                              width: 248,
                              height: 248,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  SizedBox.expand(
                                    child: CircularProgressIndicator(
                                      key: const ValueKey(
                                        'micro-focus-progress',
                                      ),
                                      value: _progress,
                                      strokeWidth: 7,
                                      strokeCap: StrokeCap.round,
                                      backgroundColor:
                                          scheme.surfaceContainerHighest,
                                      color: _completed
                                          ? scheme.tertiary
                                          : scheme.primary,
                                    ),
                                  ),
                                  Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        _completed
                                            ? AppStrings.of(
                                                context,
                                                'micro_focus_completed',
                                              )
                                            : _formatDuration(
                                                _remainingSeconds,
                                              ),
                                        key: const ValueKey(
                                          'micro-focus-timer',
                                        ),
                                        style: theme.textTheme.displaySmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                              fontFeatures: const [
                                                FontFeature.tabularFigures(),
                                              ],
                                              letterSpacing: -0.5,
                                            ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        _completed
                                            ? '+${widget.points} ${AppStrings.of(context, 'micro_metric_points')}'
                                            : _running
                                            ? AppStrings.of(
                                                context,
                                                'micro_focus_estimated',
                                                params: {
                                                  'minutes': widget.totalMinutes
                                                      .toString(),
                                                },
                                              )
                                            : AppStrings.of(
                                                context,
                                                'micro_focus_paused',
                                              ),
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                              color: scheme.onSurfaceVariant,
                                            ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 30),
                          if (_completed) ...[
                            if (_saving)
                              FilledButton.icon(
                                onPressed: null,
                                icon: const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                                label: Text(
                                  AppStrings.of(context, 'micro_focus_saving'),
                                ),
                              )
                            else if (_saveFailed)
                              FilledButton.icon(
                                key: const ValueKey('micro-focus-retry'),
                                onPressed: _saveCompletion,
                                icon: const Icon(Icons.sync_rounded),
                                label: Text(
                                  AppStrings.of(context, 'micro_focus_retry'),
                                ),
                              )
                            else
                              FilledButton.icon(
                                key: const ValueKey('micro-focus-close'),
                                onPressed: _requestClose,
                                icon: const Icon(Icons.check_rounded),
                                label: Text(
                                  AppStrings.of(context, 'btn_close'),
                                ),
                              ),
                            if (_saveFailed) ...[
                              const SizedBox(height: 8),
                              Text(
                                AppStrings.of(
                                  context,
                                  'micro_focus_sync_failed',
                                ),
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: scheme.error,
                                ),
                              ),
                            ],
                          ] else
                            Row(
                              children: [
                                Expanded(
                                  child: FilledButton.icon(
                                    key: const ValueKey('micro-focus-pause'),
                                    onPressed: _running ? _pause : _resume,
                                    icon: Icon(
                                      _running
                                          ? Icons.pause_rounded
                                          : Icons.play_arrow_rounded,
                                    ),
                                    label: Text(
                                      AppStrings.of(
                                        context,
                                        _running
                                            ? 'micro_focus_pause'
                                            : 'micro_focus_resume',
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    key: const ValueKey('micro-focus-close'),
                                    onPressed: _requestClose,
                                    icon: const Icon(Icons.close_rounded),
                                    label: Text(
                                      AppStrings.of(context, 'btn_close'),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          if (!_completed) ...[
                            const SizedBox(height: 18),
                            Text(
                              '${AppStrings.of(context, 'micro_focus_remaining')} ${_formatDuration(_remainingSeconds)}',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
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
}
