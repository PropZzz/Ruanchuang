import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/app_services.dart';
import '../services/emotion/emotion_policy.dart';
import '../utils/app_strings.dart';

class EmotionQuickCheckInCard extends StatefulWidget {
  final VoidCallback? onChanged;

  const EmotionQuickCheckInCard({super.key, this.onChanged});

  @override
  State<EmotionQuickCheckInCard> createState() => _EmotionQuickCheckInCardState();
}

class _EmotionQuickCheckInCardState extends State<EmotionQuickCheckInCard> {
  final _data = AppServices.dataService;

  bool _loading = true;
  EmotionState _current = EmotionState.stable;
  EmotionCheckIn? _today;
  String? _careHint;

  @override
  void initState() {
    super.initState();
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
      final s = List<EmotionCheckIn>.from(xs)..sort((a, b) => a.at.compareTo(b.at));
      return s.last.state;
    }

    final care = EmotionPolicy.shouldShowCareHint(
      today: lastState(today),
      yesterday: lastState(y),
    );

    if (!mounted) return;
    setState(() {
      _current = state;
      _today = today.isEmpty ? null : (List<EmotionCheckIn>.from(today)..sort((a, b) => a.at.compareTo(b.at))).last;
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
        return Colors.green;
      case EmotionState.stable:
        return Colors.blueGrey;
      case EmotionState.tired:
        return Colors.orange;
      case EmotionState.irritable:
        return Colors.redAccent;
    }
  }

  Future<void> _quickCheckIn(EmotionState s) async {
    await _data.addEmotionCheckIn(
      EmotionCheckIn(
        id: '',
        at: DateTime.now(),
        state: s,
        note: null,
      ),
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${AppStrings.of(context, 'emo_checked_in')}: ${_label(context, s)}')),
    );

    await _load();

    // Show care hint proactively when it first becomes true.
    if (_careHint != null && mounted) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(AppStrings.of(ctx, 'emo_title')),
          content: Text(_careHint!),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(AppStrings.of(ctx, 'btn_confirm')),
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
      return const Padding(
        padding: EdgeInsets.all(16),
        child: LinearProgressIndicator(),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_careHint != null) ...[
            Card(
              color: Colors.red.shade50,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Icon(Icons.favorite, color: Colors.redAccent),
                    const SizedBox(width: 10),
                    Expanded(child: Text(_careHint!)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.monitor_heart, color: _color(_current)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${AppStrings.of(context, 'emo_current')}: ${_label(context, _current)}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      if (_today != null)
                        Text(
                          _today!.at.toLocal().toString().substring(11, 16),
                          style: const TextStyle(color: Colors.grey),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    AppStrings.of(context, 'emo_quick'),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _chip(context, EmotionState.efficient),
                      _chip(context, EmotionState.stable),
                      _chip(context, EmotionState.tired),
                      _chip(context, EmotionState.irritable),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, EmotionState s) {
    final selected = _current == s;
    return ChoiceChip(
      selected: selected,
      label: Text(_label(context, s)),
      selectedColor: _color(s).withAlpha(40),
      onSelected: (_) => _quickCheckIn(s),
    );
  }
}

