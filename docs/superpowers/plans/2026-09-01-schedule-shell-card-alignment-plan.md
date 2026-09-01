# 导航、日程与卡片对齐改造实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在保留现有 Flutter 业务逻辑和数据契约的前提下，交付可收起桌面导航、更大更易读的智能日程时间轴，以及全页面等宽对齐的卡片布局。

**Architecture:** `MainScreen` 只管理侧栏展开状态；新增的 `ResponsivePageFrame`、`ResponsiveCardGrid` 和 `ScheduleTimeline` 均为无服务依赖的组合组件。页面继续负责数据加载、调度/救援、持久化和错误状态，组件通过构造参数接收模型与回调。

**Tech Stack:** Flutter 3.x、Dart 3.10、Material 3、现有 `AppTheme`/`AppWindowTones`、Flutter widget tests；不新增第三方 UI 或日历依赖。

---

### Task 1: 可收起的桌面导航壳层

**Files:**
- Modify: `lib/screens/main_screen.dart`
- Test: `test/main_screen_shell_test.dart`

- [ ] **Step 1: 写默认窄栏与切换行为的失败测试**

在现有 `pumpShell` 辅助方法后加入以下断言。测试通过 `ValueKey` 检查宽度和展开语义，不依赖实现私有类：

```dart
testWidgets('wide shell starts collapsed and toggles labels', (tester) async {
  await pumpShell(tester, const Size(1440, 900));

  final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
  expect(rail.extended, isFalse);
  expect(find.byKey(const ValueKey('shell-rail-toggle')), findsOneWidget);
  expect(find.byKey(const ValueKey('shell-rail-expanded')), findsNothing);

  await tester.tap(find.byKey(const ValueKey('shell-rail-toggle')));
  await tester.pumpAndSettle();

  final expanded = tester.widget<NavigationRail>(find.byType(NavigationRail));
  expect(expanded.extended, isTrue);
  expect(find.byKey(const ValueKey('shell-rail-expanded')), findsOneWidget);
  expect(find.byKey(const ValueKey('shell-rail-collapsed')), findsNothing);
  tester.view.reset();
});
```

同时在宽度 1024 的响应式测试中断言 `NavigationRail` 仍存在，在 390 的测试中继续断言只存在 `NavigationBar`。

- [ ] **Step 2: 运行目标测试确认失败**

运行：`flutter test test/main_screen_shell_test.dart test/responsive_layout_test.dart`

预期：失败，因为当前壳层没有切换键、没有 `_railExpanded`，且默认展开状态由屏幕宽度控制。

- [ ] **Step 3: 实现壳层状态与固定宽度**

在 `_MainScreenState` 增加 `bool _railExpanded = false;`，将其传给 `_WideShell`，并增加回调：

```dart
_WideShell(
  railExpanded: _railExpanded,
  onToggleRail: () => setState(() => _railExpanded = !_railExpanded),
  // 其他参数保持不变
)
```

将 `_WideShell` 的构造函数改为接收 `required this.railExpanded` 与 `required this.onToggleRail`。侧栏宽度使用 `railExpanded ? 248 : 76`，`NavigationRail` 使用 `extended: railExpanded`、`minWidth: 76`、`minExtendedWidth: 248`。顶部切换按钮使用 `IconButton`，固定 `ValueKey('shell-rail-toggle')`，并在展开/收起状态下分别附加 `ValueKey('shell-rail-expanded')` 或 `ValueKey('shell-rail-collapsed')` 的语义标签；Tooltip 文案为“收起导航/展开导航”。

窄栏顶部只保留品牌图标与切换按钮，展开后显示品牌标题；导航标签仅在 `extended` 为真时呈现。保持现有五个 destination、`IndexedStack`、认证弹窗和移动端 `_NarrowShell` 不变。

- [ ] **Step 4: 运行壳层与响应式测试确认通过**

运行：`flutter test test/main_screen_shell_test.dart test/responsive_layout_test.dart`

预期：全部通过，且 `tester.takeException()` 为 `null`。

- [ ] **Step 5: 提交壳层改造**

```powershell
git add lib/screens/main_screen.dart test/main_screen_shell_test.dart test/responsive_layout_test.dart
git commit -m "feat: add collapsible desktop navigation rail"
```

### Task 2: 统一页面内容框架与等宽卡片网格

**Files:**
- Create: `lib/widgets/responsive_page_frame.dart`
- Create: `lib/widgets/responsive_card_grid.dart`
- Test: `test/responsive_page_frame_test.dart`

- [ ] **Step 1: 写布局约束失败测试**

新增测试覆盖桌面最大宽度、手机单列和桌面等宽两列：

```dart
testWidgets('page frame centers content and card grid equalizes columns', (tester) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(
      body: ResponsivePageFrame(
        child: ResponsiveCardGrid(
          children: [
            Container(key: const ValueKey('card-a'), height: 80),
            Container(key: const ValueKey('card-b'), height: 140),
          ],
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();

  final frame = tester.getRect(find.byKey(const ValueKey('responsive-page-frame')));
  expect(frame.width, lessThanOrEqualTo(1320));
  final cardA = tester.getSize(find.byKey(const ValueKey('card-a')));
  final cardB = tester.getSize(find.byKey(const ValueKey('card-b')));
  expect(cardA.width, closeTo(cardB.width, 1));
  expect(cardA.height, closeTo(cardB.height, 1));
  expect(tester.takeException(), isNull);
  tester.view.reset();
});
```

- [ ] **Step 2: 运行测试确认失败**

运行：`flutter test test/responsive_page_frame_test.dart`

预期：失败，因为两个组合组件尚不存在。

- [ ] **Step 3: 实现 `ResponsivePageFrame`**

组件使用 `LayoutBuilder` 和 `ConstrainedBox`，保持页面内容居中：

```dart
class ResponsivePageFrame extends StatelessWidget {
  const ResponsivePageFrame({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final inset = constraints.maxWidth >= 1200
            ? 32.0
            : constraints.maxWidth >= 720
                ? 24.0
                : 16.0;
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            key: const ValueKey('responsive-page-frame'),
            constraints: const BoxConstraints(maxWidth: 1320),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: inset),
              child: child,
            ),
          ),
        );
      },
    );
  }
}
```

- [ ] **Step 4: 实现 `ResponsiveCardGrid`**

组件在宽度小于 720 时使用 `Column`；宽度达到 720 时将 children 按两项分行，每行使用 `IntrinsicHeight`、两个 `Expanded` 和 16px 间距，让同一行的卡片等宽等高。单数卡片使用 `SizedBox.shrink()` 保持第二列的网格节奏，避免下一行宽度漂移。组件给每个子项提供 `Key('responsive-card-grid-item-$index')`，不改变子项内部业务。

- [ ] **Step 5: 接入代表性页面并验证**

先将 `FocusPage`、`MicroTaskPage`、`TeamPage`、`ProfilePage` 的页面主内容外层包在 `ResponsivePageFrame`，把已有的两列摘要 `Row` 替换为 `ResponsiveCardGrid`；长列表、表单和日历时间地图保持全宽。运行：

`flutter test test/responsive_page_frame_test.dart test/focus_page_visual_test.dart test/app_smoke_test.dart`

预期：通过且无渲染异常。

- [ ] **Step 6: 提交通用布局组件**

```powershell
git add lib/widgets/responsive_page_frame.dart lib/widgets/responsive_card_grid.dart test/responsive_page_frame_test.dart lib/screens/focus_page.dart lib/screens/micro_task_page.dart lib/screens/team_page.dart lib/screens/profile_page.dart
git commit -m "feat: align responsive page cards"
```

### Task 3: 新的智能日程时间轴组件

**Files:**
- Create: `lib/widgets/schedule_timeline.dart`
- Modify: `lib/screens/smart_calendar_page.dart`
- Test: `test/schedule_timeline_test.dart`
- Modify: `test/smart_calendar_visual_test.dart`

- [ ] **Step 1: 写时间轴组件失败测试**

新增公开的 `ScheduleTimelineView` 枚举和组件测试，验证空状态、事件标题、删除回调和稳定轨道宽度：

```dart
testWidgets('timeline renders event metadata and delete action', (tester) async {
  var deleted = false;
  final entry = ScheduleEntry(
    day: DateTime(2026, 9, 1),
    title: 'Architecture design',
    tag: 'Deep Work',
    height: 96,
    color: Colors.teal,
    time: const TimeOfDay(hour: 9, minute: 0),
  );
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(
      body: ScheduleTimeline(
        view: ScheduleTimelineView.day,
        selectedDay: DateTime(2026, 9, 1),
        entries: [entry],
        visibleFields: const {ScheduleTimelineField.time, ScheduleTimelineField.tag},
        onDelete: (_) => deleted = true,
      ),
    ),
  ));
  await tester.pumpAndSettle();
  expect(find.text('Architecture design'), findsOneWidget);
  expect(find.byKey(const ValueKey('schedule-timeline-track')), findsOneWidget);
  await tester.tap(find.byKey(const ValueKey('schedule-entry-delete')));
  expect(deleted, isTrue);
});
```

- [ ] **Step 2: 运行测试确认失败**

运行：`flutter test test/schedule_timeline_test.dart`

预期：失败，因为组件及其公开枚举尚不存在。

- [ ] **Step 3: 实现无服务依赖的 `ScheduleTimeline`**

在 `lib/widgets/schedule_timeline.dart` 定义 `ScheduleTimelineView { day, week, month, gantt }`、`ScheduleTimelineField { time, tag, status, reminder, goal }` 和 `ScheduleTimeline`。组件将传入的 `ScheduleEntry` 按日期和时间排序；日视图使用左侧 68dp 时间刻度、最小 760dp 轨道宽度、80dp 小时行高和 `SingleChildScrollView`；事件块使用主题语义色的浅色底、左侧强调线、标题、时间和标签，并通过 `Semantics`/`Tooltip` 暴露删除操作。周/月/甘特视图复用同一事件元信息和卡片令牌，日期选择通过 `onSelectDay` 回调返回。

组件不得调用 `AppServices`、修改 `_blocks` 或计算救援方案。所有尺寸使用 `LayoutBuilder` 约束，避免窗口全屏后卡片被无限拉伸。

- [ ] **Step 4: 在日历页面接入新组件**

在 `SmartCalendarPage` 中保留 `_CalendarView` 与业务状态，通过一个私有转换方法映射到 `ScheduleTimelineView`，将 `_buildViewBody` 的时间地图分支替换为 `ScheduleTimeline`。保留现有 `_loadSchedule`、`_showAddDialog`、`_showInsertUrgentDialog`、`ScheduleRescuePersistence`、ICS 方法、字段筛选和撤销回调。页面的状态条与工具栏包在 `ResponsivePageFrame` 中，主时间轴置于 `Expanded`，确保详细日程获得剩余高度。

- [ ] **Step 5: 更新日历回归测试**

在 `smart_calendar_visual_test.dart` 继续检查 `calendar-today-status`、`calendar-time-map`、`calendar-rescue-summary` 和 `Icons.bolt`，增加 `schedule-timeline-track` 断言，并在 390px 与 1440px 两个尺寸各 pump 一次检查无异常。

- [ ] **Step 6: 运行日历与救援回归测试**

运行：`flutter test test/schedule_timeline_test.dart test/smart_calendar_visual_test.dart test/review_page_rescue_history_test.dart test/urgent_deadline_test.dart`

预期：全部通过；救援、日期翻页、视图切换和删除仍调用原有回调。

- [ ] **Step 7: 提交时间轴组件**

```powershell
git add lib/widgets/schedule_timeline.dart lib/screens/smart_calendar_page.dart test/schedule_timeline_test.dart test/smart_calendar_visual_test.dart
git commit -m "feat: refresh smart calendar timeline"
```

### Task 4: 全局接入、可访问性与发布前验证

**Files:**
- Modify: `lib/screens/smart_calendar_page.dart`
- Modify: `lib/screens/focus_page.dart`
- Modify: `lib/screens/micro_task_page.dart`
- Modify: `lib/screens/team_page.dart`
- Modify: `lib/screens/profile_page.dart`
- Modify: `test/responsive_layout_test.dart`
- Modify: `test/main_screen_shell_test.dart`
- Modify: `test/smart_calendar_visual_test.dart`

- [ ] **Step 1: 完成剩余页面接入并检查交互命中区**

为所有新增/调整的切换、日期翻页、删除和事件入口保留 Tooltip、语义标签和至少 44dp 的 `SizedBox`/`IconButton` 约束；不把长列表包装进 `IntrinsicHeight`，不修改文字或服务状态映射。

- [ ] **Step 2: 扩展响应式测试**

在 `responsive_layout_test.dart` 循环 pump `375、768、1024、1440` 宽度，检查 `tester.takeException()` 和导航语义；为 1440 宽度断言默认 `NavigationRail.extended == false`，为 390 宽度断言 `NavigationBar` 存在且底部安全区不遮挡内容。

- [ ] **Step 3: 运行格式、静态分析和目标测试**

运行：

```powershell
dart format --output=none lib/screens/main_screen.dart lib/screens/smart_calendar_page.dart lib/screens/focus_page.dart lib/screens/micro_task_page.dart lib/screens/team_page.dart lib/screens/profile_page.dart lib/widgets/responsive_page_frame.dart lib/widgets/responsive_card_grid.dart lib/widgets/schedule_timeline.dart test/main_screen_shell_test.dart test/responsive_page_frame_test.dart test/schedule_timeline_test.dart test/smart_calendar_visual_test.dart test/responsive_layout_test.dart
flutter analyze
flutter test test/main_screen_shell_test.dart test/responsive_page_frame_test.dart test/schedule_timeline_test.dart test/smart_calendar_visual_test.dart test/responsive_layout_test.dart
git diff --check
```

预期：格式命令无修改、分析无诊断、目标测试全通过、差异检查无输出。

- [ ] **Step 4: 运行完整 Flutter 测试并记录已知基线**

运行：`flutter test -r compact`

记录总数、通过、跳过和失败；如果出现历史基线失败，逐项确认是否与本轮文件相关，不把局部通过描述为全量通过。

- [ ] **Step 5: 完成最终差异审查**

检查 `git diff --stat` 与 `git status --short`，确认提交只包含本轮目标文件，未修改后端、服务契约、调度/救援算法或用户已有的其他工作树改动。完成后再决定是否合并分支或保留提交。
