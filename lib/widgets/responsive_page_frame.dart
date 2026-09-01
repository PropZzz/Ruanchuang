import 'package:flutter/material.dart';

class ResponsivePageFrame extends StatelessWidget {
  const ResponsivePageFrame({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final inset = constraints.maxWidth < 720
            ? 16.0
            : constraints.maxWidth < 1200
            ? 24.0
            : 32.0;
        return Padding(
          padding: EdgeInsets.symmetric(horizontal: inset),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              key: const Key('responsive-page-frame'),
              constraints: const BoxConstraints(maxWidth: 1320),
              child: child,
            ),
          ),
        );
      },
    );
  }
}
