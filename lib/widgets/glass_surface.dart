import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Selective translucent material for structural chrome and floating overlays.
///
/// Existing callers retain the historic glass default (`chrome`). Content
/// surfaces should pass `level: AppMaterialLevel.surface` explicitly.
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
    this.level = AppMaterialLevel.chrome,
    this.enabled = true,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final BorderRadius borderRadius;
  final double blur;
  final double opacity;
  final Color? tint;
  final bool showShadow;
  final EdgeInsetsGeometry margin;
  final AppMaterialLevel level;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mediaQuery = MediaQuery.maybeOf(context);
    final useBlur =
        enabled &&
        mediaQuery?.highContrast != true &&
        level.index >= AppMaterialLevel.chrome.index;
    final surface = tint ?? theme.colorScheme.surface;
    final opacity = this.opacity == 0.86
        ? AppMaterialTokens.opacity(theme.brightness, level)
        : this.opacity;
    final resolvedBlur = blur == 12 ? AppMaterialTokens.blur(level) : blur;
    final borderColor = theme.colorScheme.outline.withValues(
      alpha: useBlur ? 0.62 : 0.92,
    );
    final shadowAlpha = showShadow
        ? (this.opacity == 0.86
              ? AppMaterialTokens.shadowAlpha(theme.brightness, level)
              : (theme.brightness == Brightness.dark ? 0.18 : 0.06))
        : 0.0;

    return Padding(
      padding: margin,
      child: ClipRRect(
        borderRadius: borderRadius,
        child: _MaterialLayer(
          useBlur: useBlur,
          blur: resolvedBlur,
          surface: surface,
          opacity: opacity,
          borderRadius: borderRadius,
          borderColor: borderColor,
          shadowAlpha: shadowAlpha,
          padding: padding,
          child: child,
        ),
      ),
    );
  }
}

class _MaterialLayer extends StatelessWidget {
  const _MaterialLayer({
    required this.useBlur,
    required this.blur,
    required this.surface,
    required this.opacity,
    required this.borderRadius,
    required this.borderColor,
    required this.shadowAlpha,
    required this.padding,
    required this.child,
  });

  final bool useBlur;
  final double blur;
  final Color surface;
  final double opacity;
  final BorderRadius borderRadius;
  final Color borderColor;
  final double shadowAlpha;
  final EdgeInsetsGeometry padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final decorated = DecoratedBox(
      decoration: BoxDecoration(
        color: surface.withValues(alpha: opacity),
        borderRadius: borderRadius,
        border: Border.all(color: borderColor),
        boxShadow: shadowAlpha == 0
            ? const []
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: shadowAlpha),
                  blurRadius: 22,
                  offset: const Offset(0, 10),
                ),
              ],
      ),
      child: Padding(padding: padding, child: child),
    );
    if (!useBlur || blur <= 0) return decorated;
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
      child: decorated,
    );
  }
}
