import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Keeps visited tabs alive without starting every page's requests at launch.
/// Only the selected page paints and ticks; the transition reuses its subtree.
class LazyTabStack extends StatefulWidget {
  const LazyTabStack({super.key, required this.index, required this.children})
    : assert(index >= 0 && index < children.length);

  final int index;

  /// A fixed, ordered set of destinations for this shell's lifetime.
  final List<Widget> children;

  @override
  State<LazyTabStack> createState() => _LazyTabStackState();
}

class _LazyTabStackState extends State<LazyTabStack>
    with SingleTickerProviderStateMixin {
  final Set<int> _visited = {};
  late final AnimationController _controller;
  late final CurvedAnimation _progress;
  late final Animation<double> _opacity;
  double _direction = 1;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _visited.add(widget.index);
    _controller = AnimationController(
      vsync: this,
      duration: AppMotion.tabSwitch,
      value: 1,
    );
    _progress = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    // Keep content visible throughout; fading from zero flashes the canvas.
    _opacity = Tween<double>(begin: 0.8, end: 1).animate(_progress);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion) _controller.value = 1;
  }

  @override
  void didUpdateWidget(covariant LazyTabStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    assert(oldWidget.children.length == widget.children.length);
    if (oldWidget.index == widget.index) return;
    _visited.add(widget.index);
    _direction = widget.index > oldWidget.index ? 1 : -1;
    if (_reduceMotion) {
      _controller.value = 1;
    } else {
      // Retarget immediately. No outgoing page queue or blocked navigation.
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _progress.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textDirection = Directionality.of(context);
    return ClipRect(
      child: FadeTransition(
        opacity: _opacity,
        child: AnimatedBuilder(
          animation: _progress,
          builder: (context, child) => Transform.translate(
            offset: Offset(
              12 *
                  _direction *
                  (textDirection == TextDirection.rtl ? -1 : 1) *
                  (1 - _progress.value),
              0,
            ),
            child: child,
          ),
          // Animation frames update paint properties, never rebuild the pages.
          child: IndexedStack(
            index: widget.index,
            sizing: StackFit.expand,
            children: [
              for (var i = 0; i < widget.children.length; i++)
                if (_visited.contains(i))
                  TickerMode(
                    enabled: i == widget.index,
                    child: ExcludeFocus(
                      excluding: i != widget.index,
                      child: RepaintBoundary(child: widget.children[i]),
                    ),
                  )
                else
                  const SizedBox.shrink(),
            ],
          ),
        ),
      ),
    );
  }
}
