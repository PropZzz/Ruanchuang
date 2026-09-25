import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'stitch_mobile_bottom_bar.dart';
import 'stitch_mobile_header.dart';

class StitchMobileShellScope extends InheritedWidget {
  const StitchMobileShellScope({super.key, required super.child});

  static bool isHosted(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<StitchMobileShellScope>() !=
      null;

  @override
  bool updateShouldNotify(covariant StitchMobileShellScope oldWidget) => false;
}

class StitchMobileScaffold extends StatelessWidget {
  const StitchMobileScaffold({
    super.key,
    required this.title,
    required this.pageLabel,
    required this.child,
    required this.selectedIndex,
    required this.onSelect,
    this.onAdd,
    this.onNotify,
    this.onProfile,
    this.onBack,
    this.showBack = false,
    this.syncLabel,
    this.energyLabel,
    this.recoveryLabel,
  });

  final String title;
  final String pageLabel;
  final Widget child;
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final VoidCallback? onAdd;
  final VoidCallback? onNotify;
  final VoidCallback? onProfile;
  final VoidCallback? onBack;
  final bool showBack;
  final String? syncLabel;
  final String? energyLabel;
  final String? recoveryLabel;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= AppTheme.compactShellBreakpoint)
          return child;
        final useCupertino = Theme.of(context).platform == TargetPlatform.iOS;
        return Column(
          children: [
            StitchMobileHeader(
              title: title,
              pageLabel: pageLabel,
              onAdd: onAdd,
              onNotify: onNotify,
              onProfile: onProfile,
              onBack: onBack,
              showBack: showBack,
              syncLabel: syncLabel ?? '已同步 · 本地优先',
              energyLabel: energyLabel ?? '能量 86 分',
              recoveryLabel: recoveryLabel ?? '恢复缓冲 25m',
            ),
            Expanded(
              child: StitchMobileShellScope(
                child: ColoredBox(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  child: child,
                ),
              ),
            ),
            StitchMobileBottomBar(
              selectedIndex: selectedIndex,
              onSelect: onSelect,
              useCupertino: useCupertino,
            ),
          ],
        );
      },
    );
  }
}
