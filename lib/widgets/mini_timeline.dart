import 'package:flutter/material.dart';

import 'press_scale.dart';

/// A compact four-hour rhythm strip used by the focus workbench.
class MiniTimeline extends StatelessWidget {
  const MiniTimeline({
    super.key,
    required this.title,
    required this.actionLabel,
    required this.onAction,
    required this.segments,
  });

  final String title;
  final String actionLabel;
  final VoidCallback onAction;
  final List<Color> segments;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(title, style: theme.textTheme.titleMedium),
                ),
                Flexible(
                  child: PressScale(
                    child: TextButton(
                      onPressed: onAction,
                      child: Text(
                        actionLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                for (final color in segments)
                  Expanded(
                    child: Container(
                      height: 10,
                      margin: const EdgeInsets.only(right: 6),
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
