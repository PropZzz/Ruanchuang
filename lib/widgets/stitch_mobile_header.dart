import 'package:flutter/material.dart';

import '../ui/stitch_mobile_tokens.dart';

class StitchMobileHeader extends StatelessWidget {
  const StitchMobileHeader({
    super.key,
    required this.title,
    required this.pageLabel,
    this.onAdd,
    this.onNotify,
    this.onProfile,
    this.showBack = false,
    this.onBack,
    this.syncLabel = '已同步 · 本地优先',
    this.energyLabel = '能量 86 分',
    this.recoveryLabel = '恢复缓冲 25m',
  });

  final String title;
  final String pageLabel;
  final VoidCallback? onAdd;
  final VoidCallback? onNotify;
  final VoidCallback? onProfile;
  final bool showBack;
  final VoidCallback? onBack;
  final String syncLabel;
  final String energyLabel;
  final String recoveryLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final secondary = scheme.onSurfaceVariant;
    return Material(
      key: const ValueKey('stitch-mobile-header'),
      color: StitchMobileTokens.surface(context).withValues(alpha: 0.96),
      elevation: 0,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: StitchMobileTokens.headerHeight,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 12, 2),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    if (showBack)
                      IconButton(
                        key: const ValueKey('stitch-mobile-header-back'),
                        tooltip: '返回',
                        onPressed: onBack,
                        icon: const Icon(Icons.arrow_back_rounded),
                        constraints: const BoxConstraints.tightFor(
                          width: 44,
                          height: 44,
                        ),
                        padding: EdgeInsets.zero,
                      ),
                    if (showBack) const SizedBox(width: 2),
                    Expanded(
                      child: Row(
                        children: [
                          Text(
                            title,
                            style: StitchMobileTokens.pageTitle(context),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: StitchMobileTokens.surfaceHigh(context),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 6,
                                    height: 6,
                                    decoration: BoxDecoration(
                                      color: scheme.tertiary,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  Flexible(
                                    child: Text(
                                      syncLabel,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: StitchMobileTokens.label(
                                        context,
                                      ).copyWith(color: secondary),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (onAdd != null)
                      IconButton(
                        key: const ValueKey('stitch-mobile-header-add'),
                        tooltip: '插入紧急任务',
                        onPressed: onAdd,
                        icon: const Icon(Icons.add_circle_outline_rounded),
                        constraints: const BoxConstraints.tightFor(
                          width: 44,
                          height: 44,
                        ),
                        padding: EdgeInsets.zero,
                      ),
                    if (onNotify != null)
                      IconButton(
                        key: const ValueKey('stitch-mobile-header-notify'),
                        tooltip: '通知与提醒',
                        onPressed: onNotify,
                        icon: const Icon(Icons.notifications_none_rounded),
                        constraints: const BoxConstraints.tightFor(
                          width: 44,
                          height: 44,
                        ),
                        padding: EdgeInsets.zero,
                      ),
                    if (onProfile != null)
                      IconButton(
                        key: const ValueKey('stitch-mobile-header-profile'),
                        tooltip: '个人资料',
                        onPressed: onProfile,
                        icon: CircleAvatar(
                          radius: 16,
                          backgroundColor: scheme.primary,
                          child: Icon(
                            Icons.person_rounded,
                            size: 18,
                            color: scheme.onPrimary,
                          ),
                        ),
                        constraints: const BoxConstraints.tightFor(
                          width: 40,
                          height: 44,
                        ),
                        padding: EdgeInsets.zero,
                      ),
                  ],
                ),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: StitchMobileTokens.surfaceLow(context),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.bolt_rounded,
                            size: 14,
                            color: scheme.secondary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            energyLabel,
                            style: StitchMobileTokens.label(
                              context,
                            ).copyWith(color: scheme.onSurface),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: StitchMobileTokens.surfaceLow(context),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.spa_outlined,
                            size: 14,
                            color: scheme.tertiary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            recoveryLabel,
                            style: StitchMobileTokens.label(
                              context,
                            ).copyWith(color: secondary),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    Text(
                      pageLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: StitchMobileTokens.label(
                        context,
                      ).copyWith(color: secondary),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
