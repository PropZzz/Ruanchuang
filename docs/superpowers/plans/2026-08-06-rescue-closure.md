# 日程救援闭环 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让紧急任务救援支持真实截止时间、可持久化确认/撤销和可见的复盘决策记录。

**Architecture:** 在 Flutter 端增加一个只负责稳定 ID 日程条目同步与补偿的 `ScheduleRescuePersistence`。智能日历仅在同步成功后更新状态；复盘页直接利用已有 `TaskEvent.reason` 呈现救援事件，不改变 FastAPI、SQLite 或启发式调度引擎。

**Tech Stack:** Flutter/Dart、Material 3、现有 `DataService` 与 `CompositeDataService`、Flutter widget tests。

---

## 文件结构

- Create: `lib/services/scheduling/schedule_rescue_persistence.dart` - 本次救援前后日程集合的同步和失败补偿。
- Create: `test/schedule_rescue_persistence_test.dart` - 持久化服务的成功、撤销和补偿行为。
- Modify: `lib/screens/smart_calendar_page.dart` - 截止时间输入、确认/撤销调用持久化服务、错误状态。
- Modify: `lib/screens/review_page.dart` - 当前统计区间内的救援决策列表。
- Modify: `lib/utils/app_strings.dart` - 中英文截止时间、保存错误和救援记录文案。
- Modify: `test/app_smoke_test.dart` - 智能日历紧急任务入口及截止时间控件的可达性测试。
- Create: `test/review_page_rescue_history_test.dart` - 复盘页救援事件展示测试。

## Task 1: 救援日程持久化服务

**Files:**
- Create: `test/schedule_rescue_persistence_test.dart`
- Create: `lib/services/scheduling/schedule_rescue_persistence.dart`

- [ ] **Step 1: 写入失败测试**

```dart
test('restores the previous schedule when an apply write fails', () async {
  final stored = <String, ScheduleEntry>{'focus': entry('focus', 'Focus')};
  var failNextUpsert = true;
  final persistence = ScheduleRescuePersistence(
    upsert: (entry) async {
      if (entry.id == 'urgent' && failNextUpsert) {
        failNextUpsert = false;
        throw StateError('write failed');
      }
      stored[entry.id!] = entry;
    },
    remove: (entry) async => stored.remove(entry.id),
  );

  await expectLater(
    persistence.apply(
      before: [entry('focus', 'Focus')],
      after: [entry('focus', 'Moved focus'), entry('urgent', 'Urgent')],
    ),
    throwsA(isA<StateError>()),
  );

  expect(stored.values.single.title, 'Focus');
  expect(stored.containsKey('urgent'), isFalse);
});
```

- [ ] **Step 2: 运行失败测试，确认失败原因是服务尚不存在**

Run: `flutter test test/schedule_rescue_persistence_test.dart -r compact`

Expected: FAIL with an import or undefined `ScheduleRescuePersistence` error.

- [ ] **Step 3: 实现最小持久化服务**

```dart
import '../../models/models.dart';

typedef ScheduleEntryWriter = Future<void> Function(ScheduleEntry entry);

class ScheduleRescuePersistence {
  final ScheduleEntryWriter upsert;
  final ScheduleEntryWriter remove;

  const ScheduleRescuePersistence({
    required this.upsert,
    required this.remove,
  });

  Future<void> apply({
    required List<ScheduleEntry> before,
    required List<ScheduleEntry> after,
  }) async {
    try {
      await _synchronize(from: before, to: after);
    } catch (error, stackTrace) {
      try {
        await _synchronize(from: after, to: before);
      } catch (_) {}
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<void> _synchronize({
    required List<ScheduleEntry> from,
    required List<ScheduleEntry> to,
  }) async {
    final toIds = _entriesById(to).keys.toSet();
    for (final entry in _entriesById(to).values) {
      await upsert(entry);
    }
    for (final entry in _entriesById(from).values) {
      if (!toIds.contains(entry.id)) await remove(entry);
    }
  }

  Map<String, ScheduleEntry> _entriesById(List<ScheduleEntry> entries) => {
        for (final entry in entries)
          if (entry.id != null && entry.id!.isNotEmpty) entry.id!: entry,
      };
}
```

- [ ] **Step 4: 补充成功和反向同步断言并运行测试**

```dart
test('applies a rescue plan and restores its snapshot when reversed', () async {
  final stored = <String, ScheduleEntry>{'focus': entry('focus', 'Focus')};
  final persistence = ScheduleRescuePersistence(
    upsert: (entry) async => stored[entry.id!] = entry,
    remove: (entry) async => stored.remove(entry.id),
  );
  final before = [entry('focus', 'Focus')];
  final after = [entry('focus', 'Moved focus'), entry('urgent', 'Urgent')];

  await persistence.apply(before: before, after: after);
  expect(stored['focus']!.title, 'Moved focus');
  expect(stored['urgent']!.title, 'Urgent');

  await persistence.apply(before: after, after: before);
  expect(stored['focus']!.title, 'Focus');
  expect(stored.containsKey('urgent'), isFalse);
});
```

Run: `flutter test test/schedule_rescue_persistence_test.dart -r compact`

Expected: PASS with three tests: apply, inverse apply, compensation after failure.

- [ ] **Step 5: Format changed files**

Run: `dart format lib/services/scheduling/schedule_rescue_persistence.dart test/schedule_rescue_persistence_test.dart`

Repository note: do not commit. The repository has no initial commit and contains unrelated user changes.

## Task 2: 在确认与撤销中持久化计划

**Files:**
- Modify: `lib/screens/smart_calendar_page.dart:365-537`
- Test: `test/schedule_rescue_persistence_test.dart`

- [ ] **Step 1: 为确认与撤销写入失败 widget test**

在 `test/app_smoke_test.dart` 添加以下测试，并在同文件添加 `openSmartCalendar` 辅助函数：

```dart
Future<void> openSmartCalendar(WidgetTester tester) async {
  await tester.pumpWidget(const BattleManApp());
  await tester.pumpAndSettle();
  await _dismissStartupAuthIfShown(tester);
  await tester.tap(find.byKey(const ValueKey('shell-rail-schedule-icon')));
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('切换到智能规划'));
  await tester.pumpAndSettle();
}

testWidgets('accepting a rescue persists the plan and undo restores its snapshot', (tester) async {
  final local = LocalDataService.forPersistence(InMemoryLocalPersistence());
  AppServices.installTestOverrides(
    dataService: local,
    reminderService: _NoopReminderService(),
  );
  await tester.binding.setSurfaceSize(const Size(800, 900));
  try {
    await openSmartCalendar(tester);
    await tester.tap(find.byTooltip('插入紧急任务并重新规划'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('插入并重新规划'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('优先保住截止时间'));
    await tester.pumpAndSettle();

    expect((await local.getScheduleEntries()).any(
      (entry) => entry.id?.startsWith('urgent_') ?? false,
    ), isTrue);

    await tester.tap(find.text('撤销救援'));
    await tester.pumpAndSettle();
    expect((await local.getScheduleEntries()).any(
      (entry) => entry.id?.startsWith('urgent_') ?? false,
    ), isFalse);
  } finally {
    await tester.binding.setSurfaceSize(null);
  }
});
```

Run: `flutter test test/app_smoke_test.dart -r compact`

Expected: FAIL because确认路径仍直接 `setState`，因此本地日程中不存在 `urgent_` 条目。

- [ ] **Step 2: 将同步封装接入确认路径**

在 `smart_calendar_page.dart` 添加：

```dart
ScheduleRescuePersistence get _rescuePersistence => ScheduleRescuePersistence(
      upsert: _dataService.addScheduleEntry,
      remove: _dataService.removeScheduleEntry,
    );
```

在 `_showRescueOptions` 选中方案后，将下列逻辑放在现有 `setState` 之前：

```dart
setState(() => _isLoading = true);
await _rescuePersistence.apply(before: previous, after: planned);
if (!mounted) return;
setState(() {
  _urgentInserted = urgent;
  _acceptedRescue = selected;
  _rescueUndoBlocks = previous;
  _blocks = planned;
  _isLoading = false;
});
```

在 `catch` 分支确保 `_isLoading` 复位，并把中文/英文错误替换为 `calendar_rescue_save_failed` 文案。提醒重排和 `rescue_accept:` 事件保留在成功同步之后。

- [ ] **Step 3: 将同步封装接入撤销路径**

在 `_undoRescue` 中先设置加载状态，再执行：

```dart
await _rescuePersistence.apply(before: _blocks, after: previous);
if (!mounted) return;
setState(() {
  _blocks = previous;
  _urgentInserted = null;
  _acceptedRescue = null;
  _rescueUndoBlocks = null;
  _isLoading = false;
});
```

撤销失败时保持已采用方案和撤销按钮，复用 `MobileFeedback.showError`，并在 `finally` 中只在仍加载时清除 `_isLoading`。

- [ ] **Step 4: 运行相关界面与服务测试**

Run: `flutter test test/schedule_rescue_persistence_test.dart test/app_smoke_test.dart -r compact`

Expected: PASS; 确认失败不会改变页面状态，成功确认和撤销会调用同一持久化逻辑。

- [ ] **Step 5: Format changed files**

Run: `dart format lib/screens/smart_calendar_page.dart test/app_smoke_test.dart`

Repository note: do not commit. The repository has no initial commit and contains unrelated user changes.

## Task 3: 让用户输入实际截止时间

**Files:**
- Modify: `lib/screens/smart_calendar_page.dart:2184-2307`
- Modify: `lib/utils/app_strings.dart`
- Modify: `test/app_smoke_test.dart`

- [ ] **Step 1: 写入截止时间控件的失败 widget test**

```dart
testWidgets('urgent task dialog exposes a selectable deadline', (tester) async {
  await openSmartCalendar(tester);
  await tester.tap(find.byTooltip('插入紧急任务并重新规划'));
  await tester.pumpAndSettle();

  expect(find.byKey(const ValueKey('calendar-urgent-deadline')), findsOneWidget);
  expect(find.text('截止时间'), findsOneWidget);
});
```

Run: `flutter test test/app_smoke_test.dart -r compact`

Expected: FAIL because the urgent task dialog has no deadline control.

- [ ] **Step 2: 添加文案和时间选择控件**

在两种语言字典添加下列键：

```dart
'calendar_urgent_deadline': '截止时间',
'calendar_urgent_deadline_invalid': '截止时间必须晚于当前时刻。',
'calendar_rescue_save_failed': '暂时无法保存救援方案，请稍后重试。',
'review_rescue_history': '日程救援记录',
'review_rescue_empty': '当前周期暂无日程救援记录。',
'review_rescue_accepted': '已采用',
'review_rescue_undone': '已撤销',
'review_rescue_protect_deadline': '优先保住截止时间',
'review_rescue_protect_recovery': '优先保留恢复时间',
'review_rescue_minimize_changes': '尽量少动原计划',
```

在 `_showInsertUrgentDialog` 保存 `TimeOfDay deadlineTime`。默认值为今天的“现在加两小时”并限制在 23:59；未来日期为 17:00。以带图标的 `ListTile` 添加 `ValueKey('calendar-urgent-deadline')`，点击后调用 `showTimePicker` 并通过 `setInner` 更新显示值。

- [ ] **Step 3: 校验并把所选时间传入算法**

在确认按钮内构造：

```dart
final deadline = DateTime(
  day.year,
  day.month,
  day.day,
  deadlineTime.hour,
  deadlineTime.minute,
);
final today = dateOnly(DateTime.now());
if (day.isBefore(today) ||
    (sameDay(day, today) && !deadline.isAfter(DateTime.now()))) {
  MobileFeedback.showInfo(
    context,
    zhMessage: AppStrings.of(context, 'calendar_urgent_deadline_invalid'),
    enMessage: AppStrings.of(context, 'calendar_urgent_deadline_invalid'),
  );
  return;
}
```

将 `PlanTask.due` 从硬编码 `now.add(const Duration(hours: 2))` 改为 `deadline`。保留现有弹窗层级、间距、`DropdownButton` 和 Material 3 组件，不引入新的页面布局。

- [ ] **Step 4: 运行 widget 测试**

Run: `flutter test test/app_smoke_test.dart -r compact`

Expected: PASS; 智能日历的原有手机适配测试仍通过，新增测试找到截止时间选择器。

- [ ] **Step 5: Format changed files**

Run: `dart format lib/screens/smart_calendar_page.dart lib/utils/app_strings.dart test/app_smoke_test.dart`

Repository note: do not commit. The repository has no initial commit and contains unrelated user changes.

## Task 4: 在复盘页展示救援决策记录

**Files:**
- Create: `test/review_page_rescue_history_test.dart`
- Modify: `lib/screens/review_page.dart`
- Modify: `lib/utils/app_strings.dart`

- [ ] **Step 1: 写入失败 widget test**

```dart
testWidgets('review page shows rescue acceptance and undo records', (tester) async {
  TaskEvent rescueEvent(String id, String reason) => TaskEvent(
    id: id,
    taskId: 'urgent-1',
    title: '客户紧急问题',
    tag: 'Urgent',
    at: DateTime(2026, 8, 6, id == 'accept' ? 9 : 10),
    type: TaskEventType.interrupt,
    reason: reason,
  );
  final local = LocalDataService.forPersistence(InMemoryLocalPersistence());
  await local.logTaskEvent(rescueEvent('accept', 'rescue_accept:protectRecovery'));
  await local.logTaskEvent(rescueEvent('undo', 'rescue_undo:protectRecovery'));
  AppServices.installTestOverrides(dataService: local);

  await tester.pumpWidget(const MaterialApp(home: ReviewPage()));
  await tester.tap(find.text('生成报告'));
  await tester.pumpAndSettle();

  expect(find.text('日程救援记录'), findsOneWidget);
  expect(find.text('优先保留恢复时间'), findsOneWidget);
  expect(find.text('已采用'), findsOneWidget);
  expect(find.text('已撤销'), findsOneWidget);
});
```

Run: `flutter test test/review_page_rescue_history_test.dart -r compact`

Expected: FAIL because `ReviewPage` does not retain or render rescue events.

- [ ] **Step 2: 加载当前范围的事件并筛选救援事件**

在 `_ReviewPageState` 添加 `List<TaskEvent> _rescueEvents = const [];` 和 `_rangeBounds()`，周范围为 `_weekStart` 到加七天，月范围为 `_monthStart` 到下月第一天。每次 `_generate()` 均读取 `getTaskEvents(from, to)`，用：

```dart
final rescueEvents = events.where((event) {
  final reason = event.reason;
  return reason != null &&
      (reason.startsWith('rescue_accept:') || reason.startsWith('rescue_undo:'));
}).toList()
  ..sort((a, b) => b.at.compareTo(a.at));
```

周报仍调用 `getWeeklyReport`；月报仍调用 `ReviewRules.monthlySummary`。两条路径都将 `rescueEvents` 赋给状态。

- [ ] **Step 3: 以现有复盘排版添加记录区**

在周报和月报内容后追加 `_buildRescueHistory(context)`。使用一个普通 `Card`，标题配 `Icons.route_outlined`；空时显示 `review_rescue_empty`；非空时用紧凑 `ListTile` 显示 `MaterialLocalizations.formatShortTime(event.at)`、`event.title`、策略名称和状态。

策略和状态的映射固定为：

```dart
String _rescueStrategyLabel(BuildContext context, String reason) {
  if (reason.endsWith('protectDeadline')) {
    return AppStrings.of(context, 'review_rescue_protect_deadline');
  }
  if (reason.endsWith('protectRecovery')) {
    return AppStrings.of(context, 'review_rescue_protect_recovery');
  }
  if (reason.endsWith('minimizeChanges')) {
    return AppStrings.of(context, 'review_rescue_minimize_changes');
  }
  return reason;
}
```

实现时用新增的 `AppStrings` 键替代三条中文文字，并为英文 map 提供同键翻译。

- [ ] **Step 4: 运行复盘页测试**

Run: `flutter test test/review_page_rescue_history_test.dart -r compact`

Expected: PASS; 记录按时间倒序显示，接受与撤销状态区分正确。

- [ ] **Step 5: Format changed files**

Run: `dart format lib/screens/review_page.dart lib/utils/app_strings.dart test/review_page_rescue_history_test.dart`

Repository note: do not commit. The repository has no initial commit and contains unrelated user changes.

## Task 5: 全量验证与交接

**Files:**
- Modify: `功能核对与启动说明.md`
- Modify: `README.md`

- [ ] **Step 1: 更新说明文档**

在两份文档的“日程救援”描述中写明：用户可输入截止时间；确认与撤销会持久化；个人中心的复盘页可查看策略记录。不要声称 Node.js 后端已实现，因为本次保留的是现有 FastAPI 接口。

- [ ] **Step 2: 运行静态检查**

Run: `flutter analyze`

Expected: `No issues found`。

- [ ] **Step 3: 运行所有 Flutter 测试**

Run: `flutter test -r compact`

Expected: 所有测试通过。

- [ ] **Step 4: 验证后端契约没有回归**

Run: `F:\\Tools\\Python310\\python.exe -m pytest backend\\tests -q`

Expected: `6 passed`，可能仍有既有的 Starlette/httpx 弃用警告。

- [ ] **Step 5: 查看变更边界**

Run: `git diff -- lib/services/scheduling/schedule_rescue_persistence.dart lib/screens/smart_calendar_page.dart lib/screens/review_page.dart lib/utils/app_strings.dart test README.md 功能核对与启动说明.md`

Expected: 仅包含本计划列出的救援闭环、测试与说明文档改动；不提交，因为仓库没有初始提交且存在用户未提交文件。
