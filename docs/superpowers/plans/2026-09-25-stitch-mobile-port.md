# Stitch Mobile Port Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 `<720px` Flutter 移动端把 `design/stitch-mobile` 的 9 个 Stitch 页面原生全保真移植并接回现有服务。

**Architecture:** 保留现有 `MainScreen`、五个主页面控制器和 `DataService` 业务边界。新增一组只负责视觉和交互组合的 Stitch 移动组件/令牌；主页面状态控制器通过构造参数传入模型和回调，抽屉通过现有 `showModalBottomSheet`/`StitchFormSheet` 打开。桌面和平板路径保持原实现。

**Tech Stack:** Flutter 3.38 / Dart 3.10、Material 3、CupertinoIcons、flutter_test、现有 FastAPI/pytest 后端。

---

### Task 1: 建立 Stitch 移动令牌和共享组件

**Files:**
- Create: `lib/ui/stitch_mobile_tokens.dart`
- Create: `lib/widgets/stitch_mobile_scaffold.dart`
- Create: `lib/widgets/stitch_mobile_header.dart`
- Create: `lib/widgets/stitch_mobile_bottom_bar.dart`
- Modify: `lib/theme/app_theme.dart`
- Test: `test/stitch_mobile_shell_test.dart`

- [ ] **Step 1: 写移动壳失败测试**

  在 `test/stitch_mobile_shell_test.dart` 中 pump 一个 390x844 的 `StitchMobileScaffold`，断言存在 `stitch-mobile-header`、五个底栏目的 key、页面标题和安全区 padding；pump 1024px 时断言组件不接管宽屏布局。

- [ ] **Step 2: 运行测试确认失败**

  Run: `flutter test test/stitch_mobile_shell_test.dart -r compact`
  Expected: FAIL，因为 Stitch 移动组件尚不存在。

- [ ] **Step 3: 实现令牌和共享壳**

  在 `stitch_mobile_tokens.dart` 提供 Stitch 浅色/深色语义色、`pageInset`、`componentRadius`、`controlRadius`、字号和 `TextStyle` 工厂；`StitchMobileHeader` 渲染产品名、同步状态、能量/恢复摘要、上下文标题和 44dp 图标按钮；`StitchMobileBottomBar` 使用现有五个 destination id 和回调；`StitchMobileScaffold` 只在 `constraints.maxWidth < AppTheme.compactShellBreakpoint` 时渲染顶部/底栏，否则返回传入的宽屏 child。

- [ ] **Step 4: 把令牌接入主题**

  在 `lib/theme/app_theme.dart` 中让 Stitch 移动组件使用现有 `AppThemeTokens` 的语义色和 `StitchInter`/`NotoSerifSC`，不在页面内新增原始十六进制值；确保深色主题仍能生成完整 `ColorScheme`。

- [ ] **Step 5: 运行测试并提交**

  Run: `dart format lib/ui/stitch_mobile_tokens.dart lib/widgets/stitch_mobile_*.dart test/stitch_mobile_shell_test.dart && flutter test test/stitch_mobile_shell_test.dart -r compact`
  Expected: PASS。

  Commit: `git add lib/ui/stitch_mobile_tokens.dart lib/widgets/stitch_mobile_scaffold.dart lib/widgets/stitch_mobile_header.dart lib/widgets/stitch_mobile_bottom_bar.dart lib/theme/app_theme.dart test/stitch_mobile_shell_test.dart && git commit -m "feat: add Stitch mobile shell tokens"`

### Task 2: 接入 MainScreen 移动壳并保留宽屏行为

**Files:**
- Modify: `lib/screens/main_screen.dart`
- Modify: `lib/widgets/responsive_page_frame.dart`
- Test: `test/main_screen_shell_test.dart`

- [ ] **Step 1: 添加移动壳集成测试**

  为 390x844 的 `MainScreen` 断言 Stitch header、五项底栏和当前页面上下文；为 1024x768 断言现有 rail key 仍存在，确保宽屏分支不被改变。

- [ ] **Step 2: 运行测试确认缺少 Stitch 集成**

  Run: `flutter test test/main_screen_shell_test.dart --plain-name "mobile shell uses Stitch chrome" -r compact`
  Expected: FAIL，当前窄屏仍直接渲染旧 `_NarrowShell`。

- [ ] **Step 3: 替换窄屏 shell**

  将 `_NarrowShell` 的内容区包入 `StitchMobileScaffold`，把页面标题、同步状态和顶部快捷动作通过构造参数传入；保留 `IndexedStack`、导航 key、`_onSelect`、auth prompt、`secondaryPage` 和 Cupertino iOS 底栏语义。

- [ ] **Step 4: 处理二级页返回和安全区**

  在窄屏二级页显示统一返回按钮，使用现有 `secondaryPage`/`secondaryTabIndex` 恢复主 tab；底部内容 padding 读取 `MediaQuery.paddingOf(context).bottom`，不让 Stitch 底栏覆盖可操作内容。

- [ ] **Step 5: 运行壳测试并提交**

  Run: `flutter test test/main_screen_shell_test.dart -r compact`
  Expected: PASS，既有宽屏断言和新增移动断言均通过。

  Commit: `git add lib/screens/main_screen.dart lib/widgets/responsive_page_frame.dart test/main_screen_shell_test.dart && git commit -m "feat: use Stitch chrome on mobile shell"`

### Task 3: 移植 Focus 页面

**Files:**
- Modify: `lib/screens/focus_page.dart`
- Modify: `lib/widgets/focus_task_card.dart`
- Modify: `lib/widgets/energy_status_card.dart`
- Modify: `lib/widgets/mini_timeline.dart`
- Test: `test/focus_page_stitch_test.dart`

- [ ] **Step 1: 写 Focus 首屏行为测试**

  在 390x844 设备尺寸中断言 Stitch 的能量状态、当前任务标题、三段模式按钮、计时显示、暂停/开始主动作、阶段流水线和四小时摘要存在；点击主动作后断言现有计时状态改变。

- [ ] **Step 2: 运行测试确认旧层级不匹配**

  Run: `flutter test test/focus_page_stitch_test.dart -r compact`
  Expected: FAIL，旧 Focus 页面缺少 Stitch 结构 key。

- [ ] **Step 3: 用共享 Stitch 组件重排移动内容**

  在 `LayoutBuilder` 的窄屏分支按截图顺序放置状态概览、当前任务/计时卡、阶段流水线、白噪音、协作状态和未来四小时卡；复用 `FocusTaskCard` 的业务回调、`EnergyStatusCard` 的数据来源和 `MiniTimeline` 的时间块，不在组件内部访问服务。

- [ ] **Step 4: 保持桌面 Focus 分支和计时语义**

  仅替换 `<720px` 的布局；开始、暂停、跳过、结算、完成和加入协作室仍调用现有方法，加载/空数据/离线提示保留。

- [ ] **Step 5: 运行测试并提交**

  Run: `dart format lib/screens/focus_page.dart lib/widgets/focus_task_card.dart lib/widgets/energy_status_card.dart lib/widgets/mini_timeline.dart test/focus_page_stitch_test.dart && flutter test test/focus_page_stitch_test.dart -r compact`
  Expected: PASS。

  Commit: `git add lib/screens/focus_page.dart lib/widgets/focus_task_card.dart lib/widgets/energy_status_card.dart lib/widgets/mini_timeline.dart test/focus_page_stitch_test.dart && git commit -m "feat: port Stitch focus mobile page"`

### Task 4: 移植 Schedule 页面和三个排期抽屉

**Files:**
- Modify: `lib/screens/smart_calendar_page.dart`
- Modify: `lib/widgets/stitch_form_sheet.dart`
- Modify: `lib/widgets/schedule_timeline.dart`
- Create: `lib/widgets/stitch_schedule_drawers.dart`
- Test: `test/smart_calendar_stitch_test.dart`

- [ ] **Step 1: 写日历和抽屉失败测试**

  在 390x844 断言日期条、视图分段、手动/智能切换、时间线、救援提示和“插入紧急任务”主动作存在；点击新建排期和紧急任务后断言底部抽屉标题、关闭按钮、保存/比较回调存在。

- [ ] **Step 2: 运行测试确认失败**

  Run: `flutter test test/smart_calendar_stitch_test.dart -r compact`
  Expected: FAIL，旧移动布局没有 Stitch 抽屉标题和结构 key。

- [ ] **Step 3: 实现 Stitch Schedule 移动布局**

  在 `SmartCalendarPage` 窄屏分支按 Stitch 顺序组合日期选择、状态摘要、视图切换、时间地图和救援摘要；使用 `ScheduleTimeline` 现有事件/筛选数据，保留日/周/月/甘特与手动/智能状态。

- [ ] **Step 4: 实现排期/紧急任务/ICS 抽屉**

  在 `stitch_schedule_drawers.dart` 复用现有表单字段和验证：新建排期写入 DataService，插入紧急任务先走救援候选，ICS 仍走现有导入逻辑；采用前不写入，成功后提供撤销，409/422/5xx 显示原语义。

- [ ] **Step 5: 运行测试并提交**

  Run: `dart format lib/screens/smart_calendar_page.dart lib/widgets/stitch_form_sheet.dart lib/widgets/schedule_timeline.dart lib/widgets/stitch_schedule_drawers.dart test/smart_calendar_stitch_test.dart && flutter test test/smart_calendar_stitch_test.dart -r compact`
  Expected: PASS。

  Commit: `git add lib/screens/smart_calendar_page.dart lib/widgets/stitch_form_sheet.dart lib/widgets/schedule_timeline.dart lib/widgets/stitch_schedule_drawers.dart test/smart_calendar_stitch_test.dart && git commit -m "feat: port Stitch schedule mobile flow"`

### Task 5: 移植 Microtasks 和录入拆解抽屉

**Files:**
- Modify: `lib/screens/micro_task_page.dart`
- Create: `lib/widgets/stitch_microtask_drawer.dart`
- Test: `test/micro_task_stitch_test.dart`

- [ ] **Step 1: 写微任务失败测试**

  断言 390x844 页面显示统计摘要、标签筛选、推荐时间晶体、待办分组和添加按钮；点击添加后显示录入拆解抽屉，提交、编辑、完成、删除和批量模式均触发现有回调。

- [ ] **Step 2: 运行测试确认失败**

  Run: `flutter test test/micro_task_stitch_test.dart -r compact`
  Expected: FAIL，旧页面没有对应 Stitch key。

- [ ] **Step 3: 重排窄屏微任务内容**

  按 Stitch 截图重排头部统计、筛选横向滚动区、推荐卡、待办分组和折叠项；保留 `_selected`、批量操作、分页/加载、导入、编辑、删除和 DataService 调用。

- [ ] **Step 4: 实现录入拆解抽屉**

  复用现有微任务字段、标签、时长和优先级校验，抽屉提交后刷新本地列表并显示来源状态；远端推荐不可用时显示本地引擎来源，不显示实时远端。

- [ ] **Step 5: 运行测试并提交**

  Run: `dart format lib/screens/micro_task_page.dart lib/widgets/stitch_microtask_drawer.dart test/micro_task_stitch_test.dart && flutter test test/micro_task_stitch_test.dart -r compact`
  Expected: PASS。

  Commit: `git add lib/screens/micro_task_page.dart lib/widgets/stitch_microtask_drawer.dart test/micro_task_stitch_test.dart && git commit -m "feat: port Stitch microtasks mobile flow"`

### Task 6: 移植 Team、Profile、Settings 和救援比较

**Files:**
- Modify: `lib/screens/team_page.dart`
- Modify: `lib/screens/profile_page.dart`
- Create: `lib/widgets/stitch_settings_drawer.dart`
- Modify: `lib/widgets/rescue_plan_comparison.dart`
- Test: `test/team_profile_stitch_test.dart`

- [ ] **Step 1: 写团队和设置失败测试**

  断言 Team 首屏显示团队状态、黄金窗口、共享块和成员列表；Profile 显示账户/主题/语言入口；打开设置后显示 Stitch 设置抽屉并可关闭；救援比较显示三方案和确认/撤销入口。

- [ ] **Step 2: 运行测试确认失败**

  Run: `flutter test test/team_profile_stitch_test.dart -r compact`
  Expected: FAIL，旧移动层级缺少 Stitch 结构。

- [ ] **Step 3: 重排 Team/Profile 移动页面**

  按 Stitch HTML 的信息顺序重排窄屏内容，成员、权限、日历、账户、主题、语言、复盘、目标、设备和集成继续使用现有服务和二级入口；预留能力使用统一“待接入”状态组件。

- [ ] **Step 4: 实现设置抽屉与救援比较**

  设置抽屉连接 `BattleManApp.setThemeMode`、`setLocale`、本地持久化和 accent color；救援比较组件显示移动任务数、恢复缓冲、逾期风险、解释码和受影响任务，确认前不写入。

- [ ] **Step 5: 运行测试并提交**

  Run: `dart format lib/screens/team_page.dart lib/screens/profile_page.dart lib/widgets/stitch_settings_drawer.dart lib/widgets/rescue_plan_comparison.dart test/team_profile_stitch_test.dart && flutter test test/team_profile_stitch_test.dart -r compact`
  Expected: PASS。

  Commit: `git add lib/screens/team_page.dart lib/screens/profile_page.dart lib/widgets/stitch_settings_drawer.dart lib/widgets/rescue_plan_comparison.dart test/team_profile_stitch_test.dart && git commit -m "feat: port Stitch team profile and rescue mobile flows"`

### Task 7: 全量回归、视觉检查和交付

**Files:**
- Review: all modified Flutter files, `git diff --check`, generated build output
- Test: existing Flutter and backend test suites

- [ ] **Step 1: 格式化和静态检查**

  Run: `dart format --set-exit-if-changed lib test && flutter analyze`
  Expected: exit 0；若发现新增 lint，只修复本次移植引入的问题。

- [ ] **Step 2: 跑 Flutter 全量测试**

  Run: `flutter test -r compact`
  Expected: 新增 Stitch 测试和现有测试通过；已有用户改动导致的失败单独记录，不覆盖或回滚。

- [ ] **Step 3: 跑后端测试和 Web release 构建**

  Run: `python -m pytest backend/tests -q`
  Run: `flutter build web --release --no-wasm-dry-run --dart-define=API_BASE_URL=http://8.133.250.216`
  Expected: 后端全量通过，`build/web` 生成成功。

- [ ] **Step 4: 检查移动截图和 diff**

  使用现有 Flutter Web 预览在 390x844 检查 Focus、Schedule、Microtasks、Team、Settings；确认无横向滚动、底栏遮挡、标题截断和控制台错误。运行 `git diff --check` 并核对未修改已有 `test/failures/` 文件。

- [ ] **Step 5: 提交并推送**

  Run: `git status --short; git log --oneline -8; git add lib test docs/superpowers/plans/2026-09-25-stitch-mobile-port.md; git commit -m "feat: port Stitch mobile frontend"; git push origin main`
  Expected: 当前分支 `main` 推送到 `origin/main` 成功；远端提交包含设计、实现和测试变更，用户已有未相关改动仍保留在工作区。
