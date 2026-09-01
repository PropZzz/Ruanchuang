import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Adds a small, interruptible 0.96x press response without taking ownership
/// of the child's tap callback or semantics.
class PressScale extends StatefulWidget {
  const PressScale({super.key, required this.child, this.static = false});

  final Widget child;
  final bool static;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (widget.static || _pressed == value || !mounted) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      child: AnimatedScale(
        key: const ValueKey('press-scale-animation'),
        scale: _pressed && !widget.static ? 0.96 : 1,
        duration: reduceMotion ? Duration.zero : AppMotion.press,
        curve: Curves.easeOut,
        alignment: Alignment.center,
        child: widget.child,
      ),
    );
  }
}
