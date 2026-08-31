# 时序智配多端前端 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在不改变 FastAPI + SQLite 与现有调度业务的前提下，将 Flutter 客户端统一为响应式“时间地图”工作台，并加入可持久化的主题预设、轻量毛玻璃和克制动效。

**Architecture:** 保留 `MainScreen`、`DataService` 和现有页面业务状态；新增令牌化主题层与少量无网络依赖的组合组件。桌面、平板、手机只在壳层、详情呈现方式和间距上分流，业务操作仍由现有页面回调完成。

**Tech Stack:** Flutter 3.x, Dart 3.10, Material 3, `BackdropFilter`, `AnimatedSwitcher`, Flutter widget tests, FastAPI + SQLite (unchanged).

---

### Task 1: 提取令牌化主题与 GlassSurface

**Files:**
- Create: `lib/theme/app_theme.dart`
- Create: `lib/widgets/glass_surface.dart`
- Modify: `lib/main.dart` (replace private theme builder with `AppTheme.light`/`AppTheme.dark`)
- Test: `test/app_theme_test.dart`
- Test: `test/glass_surface_test.dart`

- [ ] **Step 1: Write failing theme tests**

  Add tests that assert light/dark themes expose the approved canvas, ink, recovery, deadline and risk colors; assert `GlassSurface` builds a `BackdropFilter`, keeps a stable child, and honors a disabled-motion flag without changing layout bounds.

- [ ] **Step 2: Run tests to verify the failure**

  Run `flutter test test/app_theme_test.dart test/glass_surface_test.dart`.
  Expected: FAIL because `AppTheme` and `GlassSurface` do not exist.

- [ ] **Step 3: Implement the minimal theme layer**

  Define `AppThemeTokens` with the design-spec colors and `AppTheme.build(Brightness)` using `ThemeData(useMaterial3: true)`. Configure `CardTheme`, `NavigationBarTheme`, `NavigationRailTheme`, `DialogTheme`, `SnackBarTheme`, and `ButtonStyle` from tokens. Implement `GlassSurface` as a `StatelessWidget` that composes `ClipRRect`, `BackdropFilter`, `DecoratedBox`, and `Padding`; expose `blur`, `opacity`, `padding`, `borderRadius`, and `child` only.

- [ ] **Step 4: Wire `main.dart` and run tests**

  Keep `ThemeMode` persistence and locale code unchanged. Replace `_buildTheme` calls with `AppTheme.light` and `AppTheme.dark`. Run `flutter test test/app_theme_test.dart test/glass_surface_test.dart`; expected PASS.

- [ ] **Step 5: Commit**

  Run `git add lib/theme/app_theme.dart lib/widgets/glass_surface.dart lib/main.dart test/app_theme_test.dart test/glass_surface_test.dart` and commit with `feat: add tokenized glass theme`.

### Task 2: Responsive workspace shell

**Files:**
- Create: `lib/widgets/workspace_status_bar.dart`
- Modify: `lib/screens/main_screen.dart`
- Test: `test/main_screen_shell_test.dart`

- [ ] **Step 1: Write failing shell tests**

  Pump `MainScreen` with a local mock service and assert the wide layout exposes a navigation rail and a workspace status bar; at 390px assert a `NavigationBar`; assert the selected destination changes the page without recreating the page stack.

- [ ] **Step 2: Run the focused test and confirm RED**

  Run `flutter test test/main_screen_shell_test.dart`; expected FAIL on the missing status bar and responsive assertions.

- [ ] **Step 3: Implement shell composition**

  Refactor only shell composition: use `LayoutBuilder` for 720/1200 breakpoints, add `WorkspaceStatusBar` with date, sync-state label and a theme action routed to the existing profile settings, and wrap content in `GlassSurface` where appropriate. Preserve the five destination IDs, `IndexedStack`, auth prompt and bottom navigation semantics.

- [ ] **Step 4: Run shell tests and the existing smoke test**

  Run `flutter test test/main_screen_shell_test.dart test/app_smoke_test.dart`; expected PASS.

- [ ] **Step 5: Commit**

  Commit `feat: refresh responsive workspace shell`.

### Task 3: Focus page visual pass

**Files:**
- Create: `lib/widgets/energy_status_card.dart`
- Create: `lib/widgets/focus_task_card.dart`
- Modify: `lib/screens/focus_page.dart`
- Test: `test/focus_page_visual_test.dart`

- [ ] **Step 1: Write failing widget tests**

  Assert the focus page renders the current task, a tabular countdown, energy score, next-task list and a disabled-safe loading state. Use the existing mock data service; no network calls.

- [ ] **Step 2: Run the test to verify RED**

  Run `flutter test test/focus_page_visual_test.dart`; expected FAIL on the new semantic labels/widgets.

- [ ] **Step 3: Implement composition-only cards**

  Extract the existing energy and current-task sections into `EnergyStatusCard` and `FocusTaskCard`, compose them with `GlassSurface`, use Material 3 `FilledButton`/`OutlinedButton`/`ListTile`, and add a single staggered entrance driven by `AnimationController` that resolves immediately when animations are disabled. Keep timer, task-event logging and recommendation code untouched.

- [ ] **Step 4: Run focused and regression tests**

  Run `flutter test test/focus_page_visual_test.dart test/app_smoke_test.dart`; expected PASS.

- [ ] **Step 5: Commit**

  Commit `feat: refine focus dashboard cards`.

### Task 4: Time-map calendar and rescue summary

**Files:**
- Create: `lib/widgets/rescue_summary.dart`
- Modify: `lib/screens/smart_calendar_page.dart`
- Test: `test/smart_calendar_visual_test.dart`

- [ ] **Step 1: Write failing calendar tests**

  Assert the calendar exposes the view `SegmentedButton`, today-status strip, time-map region, rescue summary and the urgent-task action. Assert compact constraints route entry editing to a bottom sheet while wide constraints use a dialog.

- [ ] **Step 2: Run the test to verify RED**

  Run `flutter test test/smart_calendar_visual_test.dart`; expected FAIL on the new semantic keys and summary widget.

- [ ] **Step 3: Implement the visual layer without changing rescue logic**

  Add the status strip and `RescueSummary` around the existing calendar view. Use `GlassSurface`, `SegmentedButton`, `FilterChip`, `Tooltip`, and existing dialogs; keep `_showRescueOptions`, persistence, undo, validation and event recording unchanged. Use `LayoutBuilder` to select dialog vs bottom sheet and add `AnimatedSwitcher` for view changes.

- [ ] **Step 4: Run focused calendar and rescue regression tests**

  Run `flutter test test/smart_calendar_visual_test.dart test/review_page_rescue_history_test.dart test/urgent_deadline_test.dart`; expected PASS.

- [ ] **Step 5: Commit**

  Commit `feat: add glass time-map calendar layer`.

### Task 5: Theme presets, accessibility and responsive verification

**Files:**
- Modify: `lib/screens/profile_page.dart` (theme preset control using existing persistence)
- Modify: `lib/utils/app_strings.dart` (localized labels for new status/preset text)
- Test: `test/theme_persistence_widget_test.dart`
- Test: `test/responsive_layout_test.dart`

- [ ] **Step 1: Write failing persistence and responsive tests**

  Assert selecting system/light/dark and an accent preset calls the existing `DataService` settings methods; pump at 375, 768, 1024 and 1440 widths and assert no horizontal overflow and valid navigation semantics.

- [ ] **Step 2: Run tests to verify RED**

  Run `flutter test test/theme_persistence_widget_test.dart test/responsive_layout_test.dart`; expected FAIL until controls and keys are added.

- [ ] **Step 3: Implement settings and accessibility polish**

  Add a Material 3 `SegmentedButton<ThemeMode>` and preset `FilterChip` group to the existing profile settings surface. Add `Tooltip`, semantic labels, visible focus styles, 44/48dp hit areas, safe-area padding and reduced-motion handling. Keep unsupported capabilities out of the UI.

- [ ] **Step 4: Run complete verification**

  Run `flutter analyze`, `flutter test -r compact`, and `F:\Tools\Python310\python.exe -m pytest backend\tests -q`. Expected: analyzer clean, all existing/new Flutter tests pass, backend tests unchanged and passing.

- [ ] **Step 5: Commit**

  Commit `feat: persist theme presets and accessibility states`.

### Task 6: Simplify and review

**Files:** recently modified Dart files and tests only.

- [ ] **Step 1: Run `git diff --check` and inspect changed code**
- [ ] **Step 2: Apply the code-simplifier pass**

  Remove duplicated decoration/spacing code, avoid nested ternaries, keep component boundaries explicit, and preserve behavior.

- [ ] **Step 3: Re-run `flutter analyze` and the full test commands from Task 5**
- [ ] **Step 4: Review requirements against `docs/superpowers/specs/2026-08-31-temporal-intelligence-frontend-design.md`**
- [ ] **Step 5: Request a focused code review before final delivery**

