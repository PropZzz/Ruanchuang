import 'package:flutter/material.dart';

class ResponsiveCardGrid extends StatelessWidget {
  const ResponsiveCardGrid({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 720) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: _mobileChildren(),
          );
        }

        final rows = <Widget>[];
        for (var index = 0; index < children.length; index += 2) {
          final secondIndex = index + 1;
          rows.add(
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _item(index)),
                  const SizedBox(width: 16),
                  Expanded(
                    child: secondIndex < children.length
                        ? _item(secondIndex)
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          );
          if (secondIndex < children.length)
            rows.add(const SizedBox(height: 16));
        }
        if (rows.isNotEmpty && rows.last is SizedBox) rows.removeLast();
        return Column(children: rows);
      },
    );
  }

  List<Widget> _mobileChildren() => [
    for (var index = 0; index < children.length; index++) ...[
      if (index > 0) const SizedBox(height: 16),
      _item(index),
    ],
  ];

  Widget _item(int index) => KeyedSubtree(
    key: Key('responsive-card-grid-item-$index'),
    child: children[index],
  );
}
