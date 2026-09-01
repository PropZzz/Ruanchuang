// lib/widgets/emotion_quick_checkin_card.dart
import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/app_services.dart';
import '../services/emotion/emotion_policy.dart';
import '../theme/app_theme.dart';
import '../utils/app_strings.dart';
import 'press_scale.dart';

class EmotionQuickCheckInCard extends StatefulWidget {
  final VoidCallback? onChanged;
  final bool initiallyExpanded;

  const EmotionQuickCheckInCard({
    super.key,
    this.onChanged,
    this.initiallyExpanded = false,
  });

  @override
  State<EmotionQuickCheckInCard> createState() =>
      _EmotionQuickCheckInCardState();
}

class _EmotionQuickCheckInCardState extends State<EmotionQuickCheckInCard> {
  final _data = AppServices.dataService;

  bool _loading = true;
  EmotionState _current = EmotionState.stable;
  EmotionCheckIn? _today;
  String? _careHint;
  late bool _isExpanded;

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.initiallyExpanded;
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final now = DateTime.now();
    try {
      // Consume every request together. If one request fails (for example a
      // normal unauthenticated 401), the other concurrent failures must not
      // escape as unhandled futures.
      final values = await Future.wait<dynamic>([
        _data.getEmotionState(),
        _data.getEmotionCheckIns(now),
        _data.getEmotionCheckIns(now.subtract(const Duration(days: 1))),
      ]);
      final state = values[0] as EmotionState;
      final today = values[1] as List<EmotionCheckIn>;
      final y = values[2] as List<EmotionCheckIn>;

      EmotionState? lastState(List<EmotionCheckIn> xs) {
        if (xs.isEmpty) return null;
        final s = List<EmotionCheckIn>.from(xs)
          ..sort((a, b) => a.at.compareTo(b.at));
        return s.last.state;
      }

      final care = EmotionPolicy.shouldShowCareHint(
        today: lastState(today),
        yesterday: lastState(y),
      );

      if (!mounted) return;
      setState(() {
        _current = state;
        _today = today.isEmpty
            ? null
            : (List<EmotionCheckIn>.from(
                today,
              )..sort((a, b) => a.at.compareTo(b.at))).last;
        _careHint = care ? AppStrings.of(context, 'emo_care_hint') : null;
        _loading = false;
      });
    } catch (e, st) {
      if (!mounted) return;
      AppServices.logStore.error(
        'emotion',
        'load quick check-in failed',
        error: e,
        stackTrace: st,
      );
      setState(() {
        _today = null;
        _careHint = null;
        _loading = false;
      });
    }
  }

  String _label(BuildContext context, EmotionState s) {
    switch (s) {
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

  Color _color(BuildContext context, EmotionState s) {
    final scheme = Theme.of(context).colorScheme;
    switch (s) {
      case EmotionState.efficient:
        return scheme.secondary;
      case EmotionState.stable:
        return scheme.primary;
      case EmotionState.tired:
        return scheme.tertiary;
      case EmotionState.irritable:
        return scheme.error;
    }
  }

  Future<void> _quickCheckIn(EmotionState s) async {
    await _data.addEmotionCheckIn(
      EmotionCheckIn(id: '', at: DateTime.now(), state: s, note: null),
    );

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${AppStrings.of(context, 'emo_checked_in')} · ${_label(context, s)}',
          style: const TextStyle(
            fontWeight: FontWeight.w400,
            letterSpacing: 0.5,
          ),
        ),
        duration: const Duration(seconds: 2),
      ),
    );

    await _load();

    if (_careHint != null && mounted) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(
            AppStrings.of(ctx, 'emo_title'),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          content: Text(
            _careHint!,
            style: TextStyle(
              height: 1.6,
              color: Theme.of(ctx).colorScheme.onSurfaceVariant,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(
                AppStrings.of(ctx, 'btn_confirm'),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ),
      );
    }

    widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return SizedBox(
        height: 48,
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
        ),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnimatedCrossFade(
      duration: AppMotion.resolve(context, const Duration(milliseconds: 250)),
      firstCurve: Curves.easeOut,
      secondCurve: Curves.easeOut,
      crossFadeState: _isExpanded
          ? CrossFadeState.showSecond
          : CrossFadeState.showFirst,
      firstChild: _buildCollapsedCard(context, isDark),
      secondChild: _buildExpandedCard(context, isDark),
    );
  }

  Widget _buildCollapsedCard(BuildContext context, bool isDark) {
    return GestureDetector(
      onTap: () => setState(() => _isExpanded = true),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Theme.of(
              context,
            ).colorScheme.outline.withValues(alpha: 0.12),
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _color(context, _current).withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.monitor_heart_outlined,
                color: _color(context, _current),
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _label(context, _current),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (_today != null)
                    Text(
                      '${AppStrings.of(context, 'emo_current')} · ${_today!.at.toLocal().toString().substring(11, 16)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            Icon(
              Icons.keyboard_arrow_down,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpandedCard(BuildContext context, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_careHint != null) ...[
            Container(
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.surface.withValues(alpha: isDark ? 0.86 : 0.72),
                borderRadius: BorderRadius.circular(16),
              ),
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    Icons.favorite_rounded,
                    color: Theme.of(context).colorScheme.error,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _careHint!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Theme.of(
                  context,
                ).colorScheme.outline.withValues(alpha: 0.12),
              ),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _color(context, _current).withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.monitor_heart_outlined,
                        color: _color(context, _current),
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppStrings.of(context, 'emo_current'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _label(context, _current),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_today != null)
                      Text(
                        _today!.at.toLocal().toString().substring(11, 16),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.outline,
                          fontSize: 12,
                        ),
                      ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => setState(() => _isExpanded = false),
                      child: Icon(
                        Icons.keyboard_arrow_up,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        size: 20,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                Text(
                  AppStrings.of(context, 'emo_quick'),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 12),

                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _minimalButton(context, EmotionState.efficient),
                    _minimalButton(context, EmotionState.stable),
                    _minimalButton(context, EmotionState.tired),
                    _minimalButton(context, EmotionState.irritable),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _minimalButton(BuildContext context, EmotionState s) {
    final isSelected = _current == s;
    final baseColor = _color(context, s);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return PressScale(
      child: GestureDetector(
        onTap: () => _quickCheckIn(s),
        child: AnimatedContainer(
          duration: AppMotion.resolve(
            context,
            const Duration(milliseconds: 200),
          ),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? baseColor.withValues(alpha: 0.12)
                : theme.colorScheme.surface.withValues(
                    alpha: isDark ? 0.86 : 0.72,
                  ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            _label(context, s),
            style: TextStyle(
              color: isSelected ? baseColor : theme.colorScheme.onSurface,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              fontSize: 13,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
    );
  }
}
