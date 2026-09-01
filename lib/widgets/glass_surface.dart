import 'dart:ui';

import 'package:flutter/material.dart';

/// Compatibility surface used by existing pages.
///
/// The redesign uses opaque surfaces for predictable contrast. The
/// BackdropFilter remains as a zero-cost compatibility node for existing
/// widget tests and callers of this class.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.borderRadius = const BorderRadius.all(Radius.circular(16)),
    this.blur = 12,
    this.opacity = 0.86,
    this.tint,
    this.showShadow = true,
    this.margin = EdgeInsets.zero,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final BorderRadius borderRadius;
  final double blur;
  final double opacity;
  final Color? tint;
  final bool showShadow;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surface = tint ?? theme.colorScheme.surface;
    final borderColor = theme.colorScheme.outline.withValues(alpha: 0.72);

    return Padding(
      padding: margin,
      child: ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: surface.withValues(alpha: opacity),
              borderRadius: borderRadius,
              border: Border.all(color: borderColor),
              boxShadow: showShadow
                  ? [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: theme.brightness == Brightness.dark
                              ? 0.18
                              : 0.06,
                        ),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ]
                  : const [],
            ),
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }
}
