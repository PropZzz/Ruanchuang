// lib/screens/profile_page.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../main.dart';
import '../models/models.dart';
import '../services/app_services.dart';
import '../theme/app_theme.dart';
import '../utils/app_strings.dart';
import '../utils/mobile_feedback.dart';
import '../utils/schedule_occurrence.dart';
import '../widgets/glass_surface.dart';
import '../widgets/responsive_page_frame.dart';
import '../widgets/stitch_mobile_scaffold.dart';
import 'bluetooth_page.dart';
import 'debug/diagnostics_page.dart';
import 'emotion_page.dart';
import 'goals_page.dart';
import 'integrations_page.dart';
import 'main_screen.dart';
import 'review_page.dart';
import 'auth_dialog.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  static final ValueNotifier<String?> globalNameNotifier =
      ValueNotifier<String?>(null);
  static final ValueNotifier<Uint8List?> globalAvatarNotifier =
      ValueNotifier<Uint8List?>(null);

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final ImagePicker _picker = ImagePicker();
  late Future<_ProfileDashboardData> _dashboardFuture;

  @override
  void initState() {
    super.initState();
    _dashboardFuture = _loadDashboard();
  }

  Future<_ProfileDashboardData> _loadDashboard() async {
    final service = AppServices.dataService;
    final now = DateTime.now();
    final day = DateTime(now.year, now.month, now.day);
    final weekStart = day.subtract(Duration(days: day.weekday - 1));

    Future<T?> safeLoad<T>(Future<T> Function() request) async {
      try {
        return await request();
      } catch (_) {
        return null;
      }
    }

    final values = await Future.wait<Object?>([
      safeLoad(() => service.getUserProfile()),
      safeLoad(() => service.getScheduleEntries()),
      safeLoad(() => service.getGoals()),
      safeLoad(() => service.getEmotionCheckIns(day)),
      safeLoad(
        () => service.getTaskEvents(
          weekStart,
          weekStart.add(const Duration(days: 7)),
        ),
      ),
    ]);

    return _ProfileDashboardData(
      profile: values[0] as UserProfile?,
      schedules: (values[1] as List<ScheduleEntry>?) ?? const [],
      goals: (values[2] as List<Goal>?) ?? const [],
      todayCheckIns: (values[3] as List<EmotionCheckIn>?) ?? const [],
      weekEvents: (values[4] as List<TaskEvent>?) ?? const [],
      isPartial: values.any((value) => value == null),
      today: day,
    );
  }

  void _refreshDashboard() {
    setState(() => _dashboardFuture = _loadDashboard());
  }

  bool _supportsDeviceEntry() {
    if (kIsWeb) return false;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
        return true;
      case TargetPlatform.fuchsia:
        return false;
    }
  }

  String? _deviceSubtitle() {
    if (kIsWeb) {
      return 'Web 预览：无法访问设备。';
    }
    if (!_supportsDeviceEntry()) {
      return '当前平台不支持设备入口。';
    }
    return null;
  }

  void _openDeviceEntry(BuildContext context) {
    if (!_supportsDeviceEntry()) {
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(AppStrings.of(ctx, 'profile_device')),
          content: const Text('当前平台暂不支持设备功能。\n请在支持蓝牙的移动端或桌面端设备上打开。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(AppStrings.of(ctx, 'btn_confirm')),
            ),
          ],
        ),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const MainScreen(
          secondaryPage: BluetoothPage(),
          secondaryTabIndex: 4,
        ),
      ),
    );
  }

  void _showAuthPopup(BuildContext context) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '关闭登录',
      barrierColor: Colors.transparent,
      transitionDuration: AppMotion.resolve(context, AppMotion.enter),
      pageBuilder: (ctx, anim1, anim2) {
        return AuthDialog(
          onAuthSuccess: () {
            Navigator.of(ctx).pop();
          },
        );
      },
      transitionBuilder: (ctx, anim1, anim2, child) {
        return FadeTransition(opacity: anim1, child: child);
      },
    );
  }

  void _showPendingFeatureDialog({
    required String title,
    required String message,
  }) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(AppStrings.of(ctx, 'btn_close')),
          ),
        ],
      ),
    );
  }

  Future<void> _pickAvatar() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );
      if (image != null) {
        final bytes = await image.readAsBytes();
        ProfilePage.globalAvatarNotifier.value = bytes;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('头像修改成功')));
      }
    } catch (e) {
      debugPrint('获取头像失败: $e');
    }
  }

  Future<void> _showEditNameDialog() async {
    final ctrl = TextEditingController(
      text: ProfilePage.globalNameNotifier.value ?? '时序智配用户',
    );
    final isNarrow = MobileFeedback.isNarrow(context, breakpoint: 760);

    Widget editor(BuildContext dialogContext) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('修改昵称', style: Theme.of(dialogContext).textTheme.titleLarge),
        const SizedBox(height: 18),
        TextField(
          key: const ValueKey('profile-edit-name-input'),
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: '新昵称'),
          textInputAction: TextInputAction.done,
        ),
        const SizedBox(height: 18),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(AppStrings.of(dialogContext, 'btn_cancel')),
            ),
            const SizedBox(width: 8),
            FilledButton(
              key: const ValueKey('profile-edit-name-save'),
              onPressed: () {
                final newName = ctrl.text.trim();
                if (newName.isNotEmpty)
                  ProfilePage.globalNameNotifier.value = newName;
                Navigator.of(dialogContext).pop();
              },
              child: Text(AppStrings.of(dialogContext, 'btn_save')),
            ),
          ],
        ),
      ],
    );

    try {
      if (isNarrow) {
        await showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          showDragHandle: true,
          builder: (ctx) => Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              8,
              20,
              MediaQuery.viewInsetsOf(ctx).bottom + 20,
            ),
            child: editor(ctx),
          ),
        );
      } else {
        await showDialog<void>(
          context: context,
          builder: (ctx) => Dialog(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: editor(ctx),
              ),
            ),
          ),
        );
      }
    } finally {
      ctrl.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.sizeOf(context).width < 720;
    return Scaffold(
      key: ValueKey(isMobile ? 'stitch-profile-mobile' : 'profile-page'),
      backgroundColor: AppWindowTones.canvas(context, AppWindowTone.neutral),
      appBar: isMobile && StitchMobileShellScope.isHosted(context)
          ? null
          : AppBar(
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(AppStrings.of(context, 'profile_title')),
                  Text(
                    'PROFILE & WORKSPACE',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              actions: [
                IconButton(
                  key: const ValueKey('profile-refresh-action'),
                  tooltip: AppStrings.of(context, 'calendar_refresh'),
                  onPressed: _refreshDashboard,
                  icon: const Icon(Icons.refresh),
                ),
                IconButton(
                  key: const ValueKey('profile-settings-action'),
                  icon: const Icon(Icons.settings_outlined),
                  tooltip: AppStrings.of(context, 'settings_title'),
                  onPressed: () => _openSettingsPanel(context),
                ),
                const SizedBox(width: 8),
              ],
            ),
      body: SafeArea(
        child: ResponsivePageFrame(
          maxWidth: 1240,
          child: FutureBuilder<_ProfileDashboardData>(
            future: _dashboardFuture,
            builder: (context, snapshot) {
              final data = snapshot.data;
              if (data == null &&
                  snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (data == null) {
                return _ProfileLoadFailure(onRetry: _refreshDashboard);
              }

              return ListView(
                physics: const BouncingScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  0,
                  12,
                  0,
                  MediaQuery.paddingOf(context).bottom + 100,
                ),
                children: [
                  if (isMobile)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              AppStrings.of(context, 'profile_title'),
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(
                                    fontFamily: 'NotoSerifSC',
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ),
                          IconButton(
                            key: const ValueKey('profile-settings-action'),
                            tooltip: AppStrings.of(context, 'settings_title'),
                            onPressed: () => _openSettingsPanel(context),
                            icon: const Icon(Icons.settings_outlined),
                          ),
                        ],
                      ),
                    ),
                  _buildUserProfileCard(context, data),
                  if (data.isPartial) ...[
                    const SizedBox(height: 10),
                    _buildPartialDataNotice(context),
                  ],
                  const SizedBox(height: 20),
                  _buildSectionTitle(context, '工作节奏与完成情况'),
                  const SizedBox(height: 10),
                  _buildAnalytics(context, data),
                  const SizedBox(height: 12),
                  _buildPendingCapability(context),
                  const SizedBox(height: 22),
                  _buildSectionTitle(context, '核心操作'),
                  const SizedBox(height: 10),
                  _buildEntryGrid(context, [
                    _ProfileEntry(
                      key: const ValueKey('profile-device-entry'),
                      icon: Icons.watch_outlined,
                      title: AppStrings.of(context, 'profile_device'),
                      detail: _deviceSubtitle() ?? '设备连接与能量同步',
                      status: _supportsDeviceEntry() ? '可用' : 'Web 不支持',
                      color: Theme.of(context).colorScheme.primary,
                      onTap: () => _openDeviceEntry(context),
                    ),
                    _ProfileEntry(
                      key: const ValueKey('profile-mcp-entry'),
                      icon: Icons.sync_alt_rounded,
                      title: AppStrings.of(context, 'profile_auth'),
                      detail: '文本解析与日程导入',
                      status: '解析可用',
                      color: Theme.of(context).colorScheme.secondary,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const MainScreen(
                            secondaryPage: IntegrationsPage(),
                            secondaryTabIndex: 4,
                          ),
                        ),
                      ),
                    ),
                    _ProfileEntry(
                      key: const ValueKey('profile-goals-entry'),
                      icon: Icons.flag_outlined,
                      title: AppStrings.of(context, 'goal_title'),
                      detail: '拆解目标并安排下一步',
                      color: Theme.of(context).colorScheme.tertiary,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const MainScreen(
                            secondaryPage: GoalsPage(),
                            secondaryTabIndex: 4,
                          ),
                        ),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 22),
                  _buildSectionTitle(context, '洞察分析'),
                  const SizedBox(height: 10),
                  _buildEntryGrid(context, [
                    _ProfileEntry(
                      key: const ValueKey('profile-emotion-entry'),
                      icon: Icons.monitor_heart_outlined,
                      title: AppStrings.of(context, 'emo_title'),
                      detail: '查看状态与今日打卡',
                      color: Theme.of(context).colorScheme.secondary,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const MainScreen(
                            secondaryPage: EmotionPage(),
                            secondaryTabIndex: 4,
                          ),
                        ),
                      ),
                    ),
                    _ProfileEntry(
                      key: const ValueKey('profile-review-entry'),
                      icon: Icons.query_stats_rounded,
                      title: AppStrings.of(context, 'review_nav_label'),
                      detail: '复盘任务完成与调度历史',
                      color: Theme.of(context).colorScheme.primary,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const MainScreen(
                            secondaryPage: ReviewPage(),
                            secondaryTabIndex: 4,
                          ),
                        ),
                      ),
                    ),
                    _ProfileEntry(
                      key: const ValueKey('profile-diagnostics-entry'),
                      icon: Icons.monitor_heart_outlined,
                      title: AppStrings.of(context, 'diag_title'),
                      detail: '数据源、存储与运行日志',
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const MainScreen(
                            secondaryPage: DiagnosticsPage(),
                            secondaryTabIndex: 4,
                          ),
                        ),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 18),
                  _buildLocalFirstFooter(context),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildAccentPresetPicker(BuildContext context) {
    final presets = [
      _AccentPreset(
        color: AppThemeTokens.recoveryLight,
        label: AppStrings.of(context, 'accent_sea'),
      ),
      _AccentPreset(
        color: AppThemeTokens.brandDark,
        label: AppStrings.of(context, 'accent_moss'),
      ),
      _AccentPreset(
        color: AppThemeTokens.deadlineLight,
        label: AppStrings.of(context, 'accent_amber'),
      ),
    ];
    final selected = BattleManApp.getAccentColor(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 16, bottom: 8),
          child: Text(
            AppStrings.of(context, 'settings_accent'),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.62),
            ),
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final preset in presets)
              FilterChip(
                selected: selected == preset.color,
                onSelected: (_) =>
                    BattleManApp.setAccentColor(context, preset.color),
                avatar: CircleAvatar(radius: 8, backgroundColor: preset.color),
                label: Text(preset.label),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildUserProfileCard(
    BuildContext context,
    _ProfileDashboardData data,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      key: const ValueKey('profile-dashboard'),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth < 540 ? 2 : 4;
          final gap = 0.0;
          final metricWidth =
              (constraints.maxWidth - gap * (columns - 1)) / columns;
          final signedIn = ProfilePage.globalNameNotifier.value != null;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  GestureDetector(
                    onTap: _pickAvatar,
                    child: ValueListenableBuilder<Uint8List?>(
                      valueListenable: ProfilePage.globalAvatarNotifier,
                      builder: (context, avatarBytes, _) => CircleAvatar(
                        radius: 31,
                        backgroundColor: scheme.surfaceContainerHigh,
                        backgroundImage: avatarBytes == null
                            ? null
                            : MemoryImage(avatarBytes),
                        child: avatarBytes == null
                            ? Icon(
                                Icons.person_outline_rounded,
                                color: scheme.onSurfaceVariant,
                                size: 32,
                              )
                            : null,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: ValueListenableBuilder<String?>(
                      valueListenable: ProfilePage.globalNameNotifier,
                      builder: (context, overrideName, _) {
                        final name =
                            overrideName ??
                            data.profile?.displayName ??
                            AppStrings.of(context, 'nav_signed_out');
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            GestureDetector(
                              onTap: _showEditNameDialog,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Flexible(
                                    child: Text(
                                      name,
                                      key: const ValueKey('profile-user-name'),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.titleLarge
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                  ),
                                  const SizedBox(width: 7),
                                  Icon(
                                    Icons.edit_outlined,
                                    size: 16,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 5),
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                _ProfileStatusTag(
                                  label: signedIn
                                      ? '已登录'
                                      : AppStrings.of(
                                          context,
                                          'nav_signed_out',
                                        ),
                                  color: signedIn
                                      ? scheme.tertiary
                                      : scheme.secondary,
                                ),
                                if (data.profile?.status case final status?
                                    when status.trim().isNotEmpty)
                                  Text(
                                    status,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  if (constraints.maxWidth >= 620)
                    OutlinedButton.icon(
                      onPressed: () => _showAuthPopup(context),
                      icon: const Icon(Icons.switch_account_outlined, size: 18),
                      label: Text(
                        AppStrings.of(context, 'profile_switch_account'),
                      ),
                    )
                  else
                    IconButton(
                      tooltip: AppStrings.of(context, 'profile_switch_account'),
                      onPressed: () => _showAuthPopup(context),
                      icon: const Icon(Icons.switch_account_outlined),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              Divider(color: scheme.outlineVariant),
              const SizedBox(height: 14),
              Wrap(
                key: const ValueKey('profile-summary-metrics'),
                spacing: gap,
                runSpacing: 14,
                children: [
                  SizedBox(
                    width: metricWidth,
                    child: _ProfileMetric(
                      label: '今日安排',
                      value: '${data.todayScheduleCount}',
                      detail: '日程块',
                      icon: Icons.calendar_month_outlined,
                    ),
                  ),
                  SizedBox(
                    width: metricWidth,
                    child: _ProfileMetric(
                      label: '本周完成',
                      value: '${data.weekCompletedCount}',
                      detail: '任务',
                      icon: Icons.task_alt_outlined,
                    ),
                  ),
                  SizedBox(
                    width: metricWidth,
                    child: _ProfileMetric(
                      label: '目标进度',
                      value: '${data.doneGoalTaskCount}/${data.goalTaskCount}',
                      detail: '已完成任务',
                      icon: Icons.flag_outlined,
                    ),
                  ),
                  SizedBox(
                    width: metricWidth,
                    child: _ProfileMetric(
                      label: '今日打卡',
                      value: '${data.todayCheckIns.length}',
                      detail: '次记录',
                      icon: Icons.monitor_heart_outlined,
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Text(
      title,
      style: Theme.of(
        context,
      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
    );
  }

  Widget _buildAnalytics(BuildContext context, _ProfileDashboardData data) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 850) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _buildWeeklyActivity(context, data)),
              const SizedBox(width: 14),
              Expanded(child: _buildGoalProgress(context, data)),
            ],
          );
        }
        return Column(
          children: [
            _buildWeeklyActivity(context, data),
            const SizedBox(height: 14),
            _buildGoalProgress(context, data),
          ],
        );
      },
    );
  }

  Widget _buildWeeklyActivity(
    BuildContext context,
    _ProfileDashboardData data,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('profile-weekly-activity'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '本周完成任务',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                '${data.weekCompletedCount} 项',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 136,
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _ProfileActivityChartPainter(
                      values: data.weekCompletionCounts,
                      lineColor: scheme.secondary,
                      barColor: scheme.primary,
                      gridColor: scheme.outlineVariant,
                    ),
                  ),
                ),
                if (data.weekCompletedCount == 0)
                  Center(
                    child: Text(
                      '完成的任务会显示在这里',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: data.weekdayLabels
                .map(
                  (label) => Text(
                    label,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildGoalProgress(BuildContext context, _ProfileDashboardData data) {
    final scheme = Theme.of(context).colorScheme;
    final rate = data.goalTaskCount == 0
        ? 0.0
        : data.doneGoalTaskCount / data.goalTaskCount;
    return Container(
      key: const ValueKey('profile-goal-progress'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '目标执行概况',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              SizedBox(
                width: 86,
                height: 86,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: rate,
                      strokeWidth: 7,
                      backgroundColor: scheme.surfaceContainerHigh,
                      color: scheme.primary,
                    ),
                    Text(
                      '${(rate * 100).round()}%',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _ProfileStatLine(
                      label: '目标数量',
                      value: '${data.goals.length}',
                    ),
                    const SizedBox(height: 10),
                    _ProfileStatLine(
                      label: '已完成任务',
                      value: '${data.doneGoalTaskCount}/${data.goalTaskCount}',
                    ),
                    const SizedBox(height: 10),
                    _ProfileStatLine(
                      label: '临近截止',
                      value: '${data.dueSoonGoalCount}',
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (data.goalTaskCount == 0) ...[
            const SizedBox(height: 12),
            Text(
              '添加目标后会显示执行进度。',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPendingCapability(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        key: const ValueKey('profile-capability-ai-pending'),
        borderRadius: BorderRadius.circular(10),
        onTap: () => _showPendingFeatureDialog(
          title: AppStrings.of(context, 'profile_model_card'),
          message: AppStrings.of(context, 'profile_model_pending'),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(
                Icons.auto_awesome_outlined,
                color: scheme.primary,
                size: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppStrings.of(context, 'profile_model_card'),
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      AppStrings.of(context, 'profile_model_pending'),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              const _ProfileStatusTag(label: '待接入'),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPartialDataNotice(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('profile-partial-data-notice'),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: scheme.primary, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '部分统计数据暂不可用，其他已加载内容仍可使用。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          IconButton(
            tooltip: AppStrings.of(context, 'calendar_refresh'),
            visualDensity: VisualDensity.compact,
            onPressed: _refreshDashboard,
            icon: const Icon(Icons.refresh, size: 18),
          ),
        ],
      ),
    );
  }

  Widget _buildEntryGrid(BuildContext context, List<_ProfileEntry> entries) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1050
            ? 3
            : constraints.maxWidth >= 640
            ? 2
            : 1;
        const spacing = 12.0;
        final width =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: entries
              .map(
                (entry) => SizedBox(
                  width: width,
                  child: _ProfileEntryCard(entry: entry),
                ),
              )
              .toList(),
        );
      },
    );
  }

  Widget _buildLocalFirstFooter(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.lock_outline, color: scheme.primary, size: 17),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '本地优先工作台 · 个人数据保存在当前工作区',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const MainScreen(
                  secondaryPage: DiagnosticsPage(),
                  secondaryTabIndex: 4,
                ),
              ),
            ),
            child: Text(AppStrings.of(context, 'diag_title')),
          ),
        ],
      ),
    );
  }

  Widget _buildActionGroup(
    BuildContext context, {
    required List<Widget> children,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.72),
        ),
        boxShadow: isDark
            ? []
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Column(children: children),
    );
  }

  Widget _profileActionTile(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String title,
    String? subtitle,
    bool showTrailing = true,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (showTrailing)
              Icon(
                Icons.chevron_right_rounded,
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.3),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDivider(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 60),
      child: Divider(
        height: 1,
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.05),
      ),
    );
  }

  void _openSettingsPanel(BuildContext context) {
    if (MobileFeedback.isNarrow(context, breakpoint: 760)) {
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => FractionallySizedBox(
          key: const ValueKey('profile-settings-mobile-sheet'),
          heightFactor: 0.9,
          alignment: Alignment.bottomCenter,
          child: _buildSettingsPanelBody(
            ctx,
            onClose: () => Navigator.of(ctx).pop(),
            onSwitchAccount: () {
              Navigator.of(ctx).pop();
              _showAuthPopup(context);
            },
          ),
        ),
      );
      return;
    }

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '关闭',
      barrierColor: Colors.black54,
      transitionDuration: AppMotion.resolve(context, AppMotion.enter),
      pageBuilder: (ctx, anim1, anim2) {
        return Align(
          alignment: Alignment.centerRight,
          child: Material(
            elevation: 16,
            borderRadius: const BorderRadius.horizontal(
              left: Radius.circular(24),
            ),
            child: Container(
              width: MediaQuery.of(context).size.width.clamp(360.0, 460.0),
              height: double.infinity,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(24),
                ),
              ),
              child: _buildSettingsPanelBody(
                ctx,
                onClose: () => Navigator.of(ctx).pop(),
                onSwitchAccount: () {
                  Navigator.of(ctx).pop();
                  _showAuthPopup(context);
                },
              ),
            ),
          ),
        );
      },
      transitionBuilder: (ctx, anim1, anim2, child) {
        return SlideTransition(
          position: Tween(begin: const Offset(1, 0), end: Offset.zero).animate(
            CurvedAnimation(
              parent: anim1,
              curve: Curves.easeOut,
              reverseCurve: Curves.easeOut,
            ),
          ),
          child: child,
        );
      },
    );
  }

  ThemeMode _getCurrentThemeMode(BuildContext context) {
    return BattleManApp.getThemeMode(context);
  }

  Widget _buildSettingsPanelBody(
    BuildContext context, {
    required VoidCallback onClose,
    required VoidCallback onSwitchAccount,
  }) {
    final theme = Theme.of(context);

    return GlassSurface(
      key: const ValueKey('profile-settings-material'),
      level: AppMaterialLevel.overlay,
      padding: EdgeInsets.zero,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      showShadow: false,
      child: Container(
        color: Colors.transparent,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const SizedBox(width: 48),
                  Expanded(
                    child: Text(
                      AppStrings.of(context, 'settings_title'),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.1,
                        ),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close, size: 20),
                    ),
                    onPressed: onClose,
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                physics: const BouncingScrollPhysics(),
                children: [
                  _buildActionGroup(
                    context,
                    children: [
                      _profileActionTile(
                        context,
                        icon: Icons.switch_account_rounded,
                        iconColor: theme.colorScheme.primary,
                        title: AppStrings.of(context, 'profile_switch_account'),
                        onTap: onSwitchAccount,
                      ),
                      _buildDivider(context),
                      _profileActionTile(
                        context,
                        icon: Icons.language_rounded,
                        iconColor: theme.colorScheme.primary,
                        title: AppStrings.of(context, 'settings_language'),
                        onTap: () => _showLanguageDialog(context),
                      ),
                      _buildDivider(context),
                      _profileActionTile(
                        context,
                        icon: Icons.notifications_rounded,
                        iconColor: theme.colorScheme.tertiary,
                        title: AppStrings.of(context, 'settings_notify'),
                        onTap: () => _showPendingFeatureDialog(
                          title: AppStrings.of(context, 'settings_notify'),
                          message: AppStrings.of(
                            context,
                            'settings_notify_pending',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _buildAccentPresetPicker(context),
                  const SizedBox(height: 24),
                  _buildActionGroup(
                    context,
                    children: [
                      ExpansionTile(
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary.withValues(
                              alpha: 0.15,
                            ),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.dark_mode_rounded,
                            color: theme.colorScheme.primary,
                            size: 22,
                          ),
                        ),
                        title: Builder(
                          builder: (context) {
                            final currentThemeMode = _getCurrentThemeMode(
                              context,
                            );
                            String themeModeName =
                                currentThemeMode == ThemeMode.system
                                ? AppStrings.of(context, 'theme_system')
                                : currentThemeMode == ThemeMode.light
                                ? AppStrings.of(context, 'theme_light')
                                : AppStrings.of(context, 'theme_dark');
                            return Text(
                              '${AppStrings.of(context, 'settings_dark')}: $themeModeName',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w500,
                              ),
                            );
                          },
                        ),
                        shape: const Border(),
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                            child: SegmentedButton<ThemeMode>(
                              segments: [
                                ButtonSegment<ThemeMode>(
                                  value: ThemeMode.system,
                                  icon: const Icon(
                                    Icons.settings_suggest_outlined,
                                  ),
                                  label: Text(
                                    AppStrings.of(context, 'theme_system'),
                                  ),
                                ),
                                ButtonSegment<ThemeMode>(
                                  value: ThemeMode.light,
                                  icon: const Icon(Icons.light_mode_outlined),
                                  label: Text(
                                    AppStrings.of(context, 'theme_light'),
                                  ),
                                ),
                                ButtonSegment<ThemeMode>(
                                  value: ThemeMode.dark,
                                  icon: const Icon(Icons.dark_mode_outlined),
                                  label: Text(
                                    AppStrings.of(context, 'theme_dark'),
                                  ),
                                ),
                              ],
                              selected: {_getCurrentThemeMode(context)},
                              showSelectedIcon: false,
                              style: ButtonStyle(
                                visualDensity: VisualDensity.compact,
                                tapTargetSize: MaterialTapTargetSize.padded,
                                padding: const WidgetStatePropertyAll(
                                  EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 10,
                                  ),
                                ),
                              ),
                              onSelectionChanged: (selection) {
                                if (selection.isNotEmpty) {
                                  BattleManApp.setThemeMode(
                                    context,
                                    selection.first,
                                  );
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _buildActionGroup(
                    context,
                    children: [
                      _profileActionTile(
                        context,
                        icon: Icons.bug_report_rounded,
                        iconColor: Theme.of(
                          context,
                        ).colorScheme.onSurfaceVariant,
                        title: AppStrings.of(context, 'diag_title'),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const MainScreen(
                              secondaryPage: DiagnosticsPage(),
                              secondaryTabIndex: 4,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showLanguageDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          AppStrings.of(context, 'settings_language'),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        children: [
          SimpleDialogOption(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
            onPressed: () {
              BattleManApp.setLocale(context, const Locale('zh', 'CN'));
              Navigator.pop(ctx);
            },
            child: Text(
              AppStrings.of(context, 'lang_zh'),
              style: const TextStyle(fontSize: 16),
            ),
          ),
          SimpleDialogOption(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
            onPressed: () {
              BattleManApp.setLocale(context, const Locale('en', 'US'));
              Navigator.pop(ctx);
            },
            child: Text(
              AppStrings.of(context, 'lang_en'),
              style: const TextStyle(fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }
}

class _AccentPreset {
  const _AccentPreset({required this.color, required this.label});

  final Color color;
  final String label;
}

class _ProfileDashboardData {
  const _ProfileDashboardData({
    required this.profile,
    required this.schedules,
    required this.goals,
    required this.todayCheckIns,
    required this.weekEvents,
    required this.isPartial,
    required this.today,
  });

  final UserProfile? profile;
  final List<ScheduleEntry> schedules;
  final List<Goal> goals;
  final List<EmotionCheckIn> todayCheckIns;
  final List<TaskEvent> weekEvents;
  final bool isPartial;
  final DateTime today;

  int get todayScheduleCount =>
      entriesForDay(day: today, allEntries: schedules).length;

  int get goalTaskCount =>
      goals.fold(0, (total, goal) => total + goal.tasks.length);

  int get doneGoalTaskCount => goals.fold(
    0,
    (total, goal) => total + goal.tasks.where((task) => task.done).length,
  );

  int get weekCompletedCount =>
      weekEvents.where((event) => event.type == TaskEventType.complete).length;

  int get dueSoonGoalCount {
    final end = today.add(const Duration(days: 7));
    return goals
        .where((goal) => !goal.due.isBefore(today) && goal.due.isBefore(end))
        .length;
  }

  List<int> get weekCompletionCounts {
    final monday = today.subtract(Duration(days: today.weekday - 1));
    return List<int>.generate(7, (index) {
      final day = monday.add(Duration(days: index));
      return weekEvents.where((event) {
        if (event.type != TaskEventType.complete) return false;
        final local = event.at.toLocal();
        return local.year == day.year &&
            local.month == day.month &&
            local.day == day.day;
      }).length;
    });
  }

  List<String> get weekdayLabels => const ['一', '二', '三', '四', '五', '六', '日'];
}

class _ProfileMetric extends StatelessWidget {
  const _ProfileMetric({
    required this.label,
    required this.value,
    required this.detail,
    required this.icon,
  });

  final String label;
  final String value;
  final String detail;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 19, color: scheme.primary),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Flexible(
                    child: Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    detail,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProfileStatusTag extends StatelessWidget {
  const _ProfileStatusTag({required this.label, this.color});

  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = color ?? scheme.secondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: foreground.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: foreground,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ProfileStatLine extends StatelessWidget {
  const _ProfileStatLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
        Text(
          value,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _ProfileEntry {
  const _ProfileEntry({
    required this.key,
    required this.icon,
    required this.title,
    required this.detail,
    required this.color,
    required this.onTap,
    this.status,
  });

  final Key key;
  final IconData icon;
  final String title;
  final String detail;
  final String? status;
  final Color color;
  final VoidCallback onTap;
}

class _ProfileEntryCard extends StatelessWidget {
  const _ProfileEntryCard({required this.entry});

  final _ProfileEntry entry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        key: entry.key,
        onTap: entry.onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: entry.color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(entry.icon, color: entry.color, size: 20),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      entry.detail,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    if (entry.status != null) ...[
                      const SizedBox(height: 6),
                      _ProfileStatusTag(
                        label: entry.status!,
                        color: entry.color,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 5),
              Icon(
                Icons.chevron_right,
                size: 19,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileLoadFailure extends StatelessWidget {
  const _ProfileLoadFailure({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off_outlined, color: scheme.error, size: 32),
          const SizedBox(height: 10),
          const Text('暂时无法加载个人工作台'),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: Text(AppStrings.of(context, 'common_retry')),
          ),
        ],
      ),
    );
  }
}

class _ProfileActivityChartPainter extends CustomPainter {
  const _ProfileActivityChartPainter({
    required this.values,
    required this.lineColor,
    required this.barColor,
    required this.gridColor,
  });

  final List<int> values;
  final Color lineColor;
  final Color barColor;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    const top = 8.0;
    const bottomInset = 8.0;
    final bottom = size.height - bottomInset;
    final plotHeight = bottom - top;
    final gridPaint = Paint()
      ..color = gridColor.withValues(alpha: 0.7)
      ..strokeWidth = 1;
    for (var row = 0; row < 4; row++) {
      final y = top + plotHeight * row / 3;
      canvas.drawLine(
        Offset.zero.translate(0, y),
        Offset(size.width, y),
        gridPaint,
      );
    }

    final maxValue = values.fold<int>(
      1,
      (max, value) => value > max ? value : max,
    );
    final slot = size.width / values.length;
    final points = <Offset>[];
    for (var index = 0; index < values.length; index++) {
      final value = values[index];
      final barHeight = (value / maxValue) * plotHeight * 0.8;
      final x = slot * index + slot * 0.25;
      final barRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, bottom - barHeight, slot * 0.5, barHeight),
        const Radius.circular(3),
      );
      canvas.drawRRect(
        barRect,
        Paint()
          ..color = value == 0
              ? gridColor.withValues(alpha: 0.38)
              : barColor.withValues(alpha: 0.82),
      );
      points.add(Offset(slot * (index + 0.5), bottom - barHeight));
    }

    final line = Path();
    for (var index = 0; index < points.length; index++) {
      final point = points[index];
      if (index == 0) {
        line.moveTo(point.dx, point.dy);
      } else {
        final previous = points[index - 1];
        final middle = (previous.dx + point.dx) / 2;
        line.cubicTo(middle, previous.dy, middle, point.dy, point.dx, point.dy);
      }
    }
    canvas.drawPath(
      line,
      Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
    for (final point in points) {
      canvas.drawCircle(
        point,
        2.5,
        Paint()
          ..color = lineColor
          ..style = PaintingStyle.fill,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ProfileActivityChartPainter oldDelegate) =>
      oldDelegate.values != values ||
      oldDelegate.lineColor != lineColor ||
      oldDelegate.barColor != barColor ||
      oldDelegate.gridColor != gridColor;
}
