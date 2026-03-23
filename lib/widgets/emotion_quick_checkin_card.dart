import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/app_services.dart';
import '../services/emotion/emotion_policy.dart';
import '../utils/app_strings.dart';

class EmotionQuickCheckInCard extends StatefulWidget {
  final VoidCallback? onChanged;
  final bool initiallyExpanded;

  const EmotionQuickCheckInCard({super.key, this.onChanged, this.initiallyExpanded = false});

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
    final stateF = _data.getEmotionState();
    final todayF = _data.getEmotionCheckIns(now);
    final yF = _data.getEmotionCheckIns(now.subtract(const Duration(days: 1)));

    final state = await stateF;
    final today = await todayF;
    final y = await yF;

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

  Color _color(EmotionState s) {
    switch (s) {
      case EmotionState.efficient:
        return const Color(0xFF81B29A);
      case EmotionState.stable:
        return const Color(0xFF8D99AE);
      case EmotionState.tired:
        return const Color(0xFFE07A5F);
      case EmotionState.irritable:
        return const Color(0xFFD68C89);
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
            style: const TextStyle(height: 1.6, color: Color(0xFF8E8E93)),
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
      return const SizedBox(
        height: 48,
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Color(0xFFE5E5EA),
            ),
          ),
        ),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnimatedCrossFade(
      duration: const Duration(milliseconds: 250),
      crossFadeState: _isExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
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
            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.12),
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _color(_current).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.monitor_heart_outlined,
                color: _color(_current),
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
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (_today != null)
                    Text(
                      '${AppStrings.of(context, 'emo_current')} · ${_today!.at.toLocal().toString().substring(11, 16)}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF8E8E93),
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
                color: isDark
                    ? const Color(0xFF3A3A3C)
                    : const Color(0xFFF7F7F6),
                borderRadius: BorderRadius.circular(16),
              ),
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(
                    Icons.favorite_rounded,
                    color: Color(0xFFD68C89),
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
                color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.12),
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
                        color: _color(_current).withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.monitor_heart_outlined,
                        color: _color(_current),
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
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF8E8E93),
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _label(context, _current),
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
                        style: const TextStyle(
                          color: Color(0xFFC7C7CC),
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
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF8E8E93),
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
    final baseColor = _color(s);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return GestureDetector(
      onTap: () => _quickCheckIn(s),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? baseColor.withOpacity(0.12)
              : (isDark ? const Color(0xFF3A3A3C) : const Color(0xFFF7F7F6)),
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
    );
  }
}
