// lib/screens/emotion_page.dart
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
  EmotionState _state = EmotionState.stable;
  List<EmotionCheckIn> _today = const [];
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
      _state = state;
      _today = today;
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

  Future<void> _checkIn(EmotionState s) async {
    await _data.addEmotionCheckIn(
      EmotionCheckIn(id: '', at: DateTime.now(), state: s, note: null),
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${AppStrings.of(context, 'emo_checked_in')}: ${_label(context, s)}',
        ),
      ),
    );
    await _load();

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
  }

  @override
  Widget build(BuildContext context) {
    final guidance = EmotionPolicy.adaptiveSnapshot(
      emotion: _state,
      recentCheckInCount: _today.length,
      careHint: _careHint != null,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.of(context, 'emo_title')),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_careHint != null) ...[
                  Card(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? const Color(0xFF3A3A3C)
                        : const Color(0xFFF7F7F6),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.favorite_rounded,
                            color: Color(0xFFD68C89),
                          ),
                          const SizedBox(width: 10),
                          Expanded(child: Text(_careHint!)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Icon(
                          Icons.monitor_heart,
                          color: _color(_state),
                          size: 28,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '${AppStrings.of(context, 'emo_current')}: ${_label(context, _state)}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  color: Theme.of(
                    context,
                  ).colorScheme.secondaryContainer.withValues(alpha: 0.45),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.tips_and_updates, color: _color(_state)),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                '自适应建议',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          guidance.headline,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(guidance.detail),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: guidance.highlights
                              .map(
                                (text) => Chip(
                                  visualDensity: VisualDensity.compact,
                                  label: Text(text),
                                ),
                              )
                              .toList(),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
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
                const SizedBox(height: 16),
                Text(
                  AppStrings.of(context, 'emo_today'),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                if (_today.isEmpty)
                  Text(
                    AppStrings.of(context, 'emo_today_empty'),
                    style: const TextStyle(color: Colors.grey),
                  )
                else
                  ..._today.map(
                    (e) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        Icons.circle,
                        size: 12,
                        color: _color(e.state),
                      ),
                      title: Text(_label(context, e.state)),
                      subtitle: Text(
                        e.note == null
                            ? e.at.toLocal().toString()
                            : '${e.at.toLocal()}\n${e.note}',
                      ),
                      isThreeLine: e.note != null,
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _chip(BuildContext context, EmotionState s) {
    return ActionChip(
      backgroundColor: _color(s).withAlpha(26),
      label: Text(_label(context, s)),
      onPressed: () => _checkIn(s),
    );
  }
}