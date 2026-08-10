# Core UI Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the existing Flutter application into a responsive, calm, trustworthy scheduling workbench without changing scheduling, persistence, authentication, or remote API behavior.

**Architecture:** Centralize visual tokens and reusable workbench primitives, then apply them to the existing shell and page bodies. Keep all calls to `AppServices` and existing page state intact; new UI widgets are presentational and receive actions/data from the current screen state.

**Tech Stack:** Flutter, Dart, Material 3, flutter_test.

---

## File structure

- Create: `lib/ui/app_theme.dart` - color tokens and Material themes for the workbench.
- Create: `lib/widgets/workbench_surface.dart` - shared bordered surface, section heading, metric, and empty-state primitives.
- Create: `lib/widgets/rescue_plan_comparison.dart` - responsive, presentational comparison dialog for existing `ScheduleRescueOption` values.
- Modify: `lib/main.dart` - consume the new theme builder and remove the legacy neutral/glass styling.
- Modify: `lib/screens/main_screen.dart` - desktop shell, mobile navigation and top-level contextual header.
- Modify: `lib/screens/focus_page.dart` - focused two-column workbench layout.
- Modify: `lib/screens/smart_calendar_page.dart` - contextual toolbar, schedule summary, rescue comparison entry point, and undo banner.
- Modify: `lib/screens/micro_task_page.dart` - compact filters, selection toolbar, and task rows.
- Modify: `lib/screens/team_page.dart` - collaboration-window hierarchy and semantic timeline styling.
- Modify: `lib/screens/profile_page.dart` and `lib/screens/review_page.dart` - personal-hub grouping and readable review hierarchy.
- Modify: `test/app_smoke_test.dart` - shell, narrow layout and rescue comparison regressions.
- Create: `test/app_theme_test.dart` - visual token and shared component widget coverage.

### Task 1: Establish the visual token layer

**Files:**
- Create: `lib/ui/app_theme.dart`
- Modify: `lib/main.dart:138-320`
- Create: `test/app_theme_test.dart`

- [ ] **Step 1: Write the failing theme test**

```dart
testWidgets('workbench theme uses the scheduling semantic colors', (tester) async {
  await tester.pumpWidget(
    MaterialApp(theme: AppTheme.light(), home: const Scaffold()),
  );

  final scheme = Theme.of(tester.element(find.byType(Scaffold))).colorScheme;
  expect(scheme.primary, const Color(0xFF153F45));
  expect(scheme.error, const Color(0xFFA8493B));
  expect(Theme.of(tester.element(find.byType(Scaffold))).cardTheme.shape,
      isA<RoundedRectangleBorder>());
});
```

- [ ] **Step 2: Run the focused test and verify it fails**

Run: `flutter test test/app_theme_test.dart -r compact`

Expected: compilation failure because `AppTheme` does not exist.

- [ ] **Step 3: Implement semantic themes and connect them to the app**

Create `AppTheme.light()` and `AppTheme.dark()` in `lib/ui/app_theme.dart`. Both must define the colors from the approved spec, 6px/8px component radii, solid surfaces, clear focus/disabled states, and non-transparent navigation surfaces. Replace `_buildTheme` in `lib/main.dart` with `AppTheme.light()` and `AppTheme.dark()` while preserving locale, theme-mode persistence, `MediaQuery` text-scale clamping, and `BattleManApp`'s public API.

```dart
// lib/main.dart, inside MaterialApp
theme: AppTheme.light(),
darkTheme: AppTheme.dark(),
themeMode: _themeMode,
```

- [ ] **Step 4: Run the focused test and analyzer**

Run: `flutter test test/app_theme_test.dart -r compact && flutter analyze`

Expected: the theme test passes and analyzer reports no diagnostics.

- [ ] **Step 5: Commit the scoped change when the repository has a clean staging area**

Run: `git add lib/ui/app_theme.dart lib/main.dart test/app_theme_test.dart && git commit -m "feat: add scheduling workbench theme"`

Expected: only the listed files are staged; do not include unrelated existing changes.

### Task 2: Add reusable workbench primitives

**Files:**
- Create: `lib/widgets/workbench_surface.dart`
- Modify: `test/app_theme_test.dart`

- [ ] **Step 1: Write failing widget tests for the shared surface and metric**

```dart
testWidgets('workbench surface renders a bordered title and child', (tester) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: const WorkbenchSurface(
        title: '今日概览',
        child: Text('内容'),
      ),
    ),
  );

  expect(find.text('今日概览'), findsOneWidget);
  expect(find.text('内容'), findsOneWidget);
  expect(find.byType(WorkbenchSurface), findsOneWidget);
});
```

- [ ] **Step 2: Run the widget tests and verify they fail**

Run: `flutter test test/app_theme_test.dart -r compact`

Expected: compilation failure because `WorkbenchSurface` does not exist.

- [ ] **Step 3: Implement focused primitives**

Implement `WorkbenchSurface`, `WorkbenchSectionHeader`, `WorkbenchMetric`, `WorkbenchEmptyState`, and `WorkbenchStatusBadge`. Each must accept child content instead of reading service data, use theme colors, use 8px-or-less corners, and expose optional keys/tooltips for testable actions. Keep these primitives presentation-only; no `AppServices` import is allowed.

```dart
class WorkbenchSurface extends StatelessWidget {
  const WorkbenchSurface({super.key, this.title, required this.child});
  final String? title;
  final Widget child;
  // build a bordered Material surface with optional section heading
}
```

- [ ] **Step 4: Run the shared-widget tests**

Run: `flutter test test/app_theme_test.dart -r compact`

Expected: all token and surface assertions pass.

- [ ] **Step 5: Commit the scoped change when safe**

Run: `git add lib/widgets/workbench_surface.dart test/app_theme_test.dart && git commit -m "feat: add reusable workbench surfaces"`

Expected: only the two scoped files are staged.

### Task 3: Rebuild the responsive application shell

**Files:**
- Modify: `lib/screens/main_screen.dart:89-380`
- Modify: `test/app_smoke_test.dart`

- [ ] **Step 1: Add failing shell assertions for both form factors**

```dart
testWidgets('wide shell exposes all primary destinations', (tester) async {
  await tester.binding.setSurfaceSize(const Size(1440, 960));
  await tester.pumpWidget(const BattleManApp());
  await tester.pumpAndSettle();

  for (final label in ['专注', '日程', '微任务', '团队', '我的']) {
    expect(find.text(label), findsWidgets);
  }
});
```

Add a narrow companion test at `Size(390, 844)` that finds each `shell-nav-*` key and verifies `tester.takeException()` is null.

- [ ] **Step 2: Run the shell tests and verify the new assertions fail**

Run: `flutter test test/app_smoke_test.dart --plain-name "wide shell exposes all primary destinations" -r compact`

Expected: failure until the shell uses the workbench labels, selected-state treatment, and responsive spacing.

- [ ] **Step 3: Implement the navigation workbench**

Refactor `_WideShell` to use a 240px solid surface, a brand lockup, selected destination label/icon treatment, and a bottom user/settings area. Add a compact contextual header above each desktop page. Refactor `_NarrowShell` to use the same semantic colors without `BackdropFilter`. Preserve the existing destination IDs and keys: `shell-nav-focus`, `shell-nav-schedule`, `shell-nav-micro`, `shell-nav-team`, and `shell-nav-profile`.

- [ ] **Step 4: Run desktop and mobile shell tests**

Run: `flutter test test/app_smoke_test.dart --plain-name "BattleManApp builds shell" -r compact && flutter test test/app_smoke_test.dart --plain-name "Smart calendar month view fits on small screens" -r compact`

Expected: both pass with no overflow or uncaught exceptions.

- [ ] **Step 5: Commit the scoped change when safe**

Run: `git add lib/screens/main_screen.dart test/app_smoke_test.dart && git commit -m "feat: redesign responsive application shell"`

Expected: only the shell and related test hunks are staged.

### Task 4: Rework focus and micro-task priority views

**Files:**
- Modify: `lib/screens/focus_page.dart:389-650`
- Modify: `lib/screens/micro_task_page.dart:1063-1300`
- Modify: `test/app_smoke_test.dart`

- [ ] **Step 1: Add failing rendering tests for priority content**

```dart
testWidgets('focus page keeps the current task action visible on mobile', (tester) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  await tester.pumpWidget(const BattleManApp());
  await tester.pumpAndSettle();
  await _dismissStartupAuthIfShown(tester);

  expect(find.text('当前任务'), findsOneWidget);
  expect(find.text('开始').first, findsOneWidget);
  expect(tester.takeException(), isNull);
});
```

Add a micro-task test that opens the destination and asserts its add action and batch-state action are accessible without overflow.

- [ ] **Step 2: Run the new priority-view tests and verify they fail**

Run: `flutter test test/app_smoke_test.dart --plain-name "focus page keeps the current task action visible on mobile" -r compact`

Expected: failure until testable page hierarchy keys and compact layout are in place.

- [ ] **Step 3: Apply the workbench layout without changing actions**

Use `WorkbenchSurface` and metrics to turn the focus page into a 7:5 wide layout and priority-first mobile stack. In the micro-task page, group filters, batch controls, recommended time crystals, and compact task rows; retain existing add, edit, delete, import, batch, and one-click schedule callbacks exactly as they are.

- [ ] **Step 4: Run the focused page tests**

Run: `flutter test test/app_smoke_test.dart -r compact`

Expected: all existing app-smoke tests still pass, including task scheduling and narrow-calendar cases.

- [ ] **Step 5: Commit the scoped change when safe**

Run: `git add lib/screens/focus_page.dart lib/screens/micro_task_page.dart test/app_smoke_test.dart && git commit -m "feat: prioritize focus and micro-task work views"`

Expected: only the listed changes are staged.

### Task 5: Make schedule rescue a deliberate comparison flow

**Files:**
- Create: `lib/widgets/rescue_plan_comparison.dart`
- Modify: `lib/screens/smart_calendar_page.dart:350-470, 685-900`
- Modify: `test/app_smoke_test.dart`

- [ ] **Step 1: Add a failing rescue comparison test**

```dart
testWidgets('urgent rescue presents all strategies before acceptance', (tester) async {
  _setWideSurface(tester);
  await _openSmartCalendar(tester);
  await tester.tap(find.byTooltip('插入紧急任务并重新规划'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('插入并重新规划'));
  await tester.pumpAndSettle();

  expect(find.text('优先保住截止时间'), findsOneWidget);
  expect(find.text('优先保留恢复时间'), findsOneWidget);
  expect(find.text('尽量少动原计划'), findsOneWidget);
  expect(find.text('采用此方案'), findsNothing);
});
```

- [ ] **Step 2: Run the rescue test and verify it fails**

Run: `flutter test test/app_smoke_test.dart --plain-name "urgent rescue presents all strategies before acceptance" -r compact`

Expected: failure until the comparison dialog exposes the three explicit strategy tiles.

- [ ] **Step 3: Implement the responsive comparison surface**

Create `RescuePlanComparison` with a `List<ScheduleRescueOption>`, `onSelect`, and `onCancel`. Use a three-column `LayoutBuilder` at desktop widths and a vertically stacked layout below 760px. Each option must show its rationale, tradeoff, moved-entry count, recovery minutes, issue count, an explicit recommendation state, and a button labelled `采用此方案`. Replace `_showRescueOptions`'s `AlertDialog` list tiles with the new component, keeping the existing persistence, event logging, reminder rescheduling, and undo code unchanged. Display the existing undo action as a persistent semantic banner above the schedule canvas.

```dart
final selected = await showDialog<ScheduleRescueOption>(
  context: context,
  builder: (_) => RescuePlanComparison(
    options: options,
    onCancel: () => Navigator.of(context).pop(),
    onSelect: (option) => Navigator.of(context).pop(option),
  ),
);
```

- [ ] **Step 4: Run rescue behavior regressions**

Run: `flutter test test/app_smoke_test.dart --plain-name "Urgent task dialog opens a deadline date picker" -r compact && flutter test test/app_smoke_test.dart --plain-name "Urgent rescue reschedules reminders on accept and undo" -r compact && flutter test test/app_smoke_test.dart --plain-name "urgent rescue presents all strategies before acceptance" -r compact`

Expected: input validation, persistence, reminders, undo, and all-three-options rendering pass.

- [ ] **Step 5: Commit the scoped change when safe**

Run: `git add lib/widgets/rescue_plan_comparison.dart lib/screens/smart_calendar_page.dart test/app_smoke_test.dart && git commit -m "feat: present schedule rescue as comparison workflow"`

Expected: only the listed rescue UI and test changes are staged.

### Task 6: Apply the system to team, profile, and review

**Files:**
- Modify: `lib/screens/team_page.dart:587-1900`
- Modify: `lib/screens/profile_page.dart:166-850`
- Modify: `lib/screens/review_page.dart:319-700`
- Modify: `test/app_smoke_test.dart`

- [ ] **Step 1: Add failing navigation and empty-state tests**

```dart
testWidgets('profile hub exposes review and settings entries', (tester) async {
  await tester.pumpWidget(const BattleManApp());
  await tester.pumpAndSettle();
  await _dismissStartupAuthIfShown(tester);
  await tester.tap(find.byKey(const ValueKey('shell-nav-profile')));
  await tester.pumpAndSettle();

  expect(find.text('复盘'), findsOneWidget);
  expect(find.text('设置'), findsOneWidget);
  expect(tester.takeException(), isNull);
});
```

Add a team test that asserts the collaboration-window heading and the no-members state both remain readable at 390px width.

- [ ] **Step 2: Run the new lower-frequency-module tests and verify they fail**

Run: `flutter test test/app_smoke_test.dart --plain-name "profile hub exposes review and settings entries" -r compact`

Expected: failure until explicit hub grouping and stable labels are implemented.

- [ ] **Step 3: Restructure visual hierarchy while preserving callbacks**

Use a primary collaboration-window surface and a secondary member/permission detail surface in the team page. Replace hard-coded green/blue/grey presentation colors in the timeline with theme semantic colors. Group profile links into account, planning, and system sections; make review metrics, rescue history, and suggestions distinct workbench sections. Preserve every existing navigation target, dialog callback, permission action, report generation action, and data-service call.

- [ ] **Step 4: Run the targeted and existing review tests**

Run: `flutter test test/app_smoke_test.dart -r compact && flutter test test/review_page_rescue_history_test.dart -r compact && flutter test test/team_collab_engine_test.dart -r compact`

Expected: UI navigation and existing team/review logic tests pass.

- [ ] **Step 5: Commit the scoped change when safe**

Run: `git add lib/screens/team_page.dart lib/screens/profile_page.dart lib/screens/review_page.dart test/app_smoke_test.dart && git commit -m "feat: unify collaboration and personal workbench views"`

Expected: only the listed UI and test changes are staged.

### Task 7: Verify responsive behavior and regression safety

**Files:**
- Modify: `test/app_smoke_test.dart`
- Modify: `docs/superpowers/specs/2026-08-09-core-ui-redesign-design.md` only if implementation reveals a material requirement change

- [ ] **Step 1: Add a wide and narrow no-overflow regression test matrix**

```dart
testWidgets('primary destinations render without exceptions at target widths', (tester) async {
  for (final size in [const Size(1440, 960), const Size(390, 844)]) {
    await tester.binding.setSurfaceSize(size);
    await tester.pumpWidget(const BattleManApp());
    await tester.pumpAndSettle();
    await _dismissStartupAuthIfShown(tester);
    expect(tester.takeException(), isNull, reason: 'failed at $size');
  }
});
```

- [ ] **Step 2: Run the new regression matrix and verify it fails before any missing responsive constraint is fixed**

Run: `flutter test test/app_smoke_test.dart --plain-name "primary destinations render without exceptions at target widths" -r compact`

Expected: PASS only after resetting surface size between iterations and fixing any recorded overflow.

- [ ] **Step 3: Fix only verified responsive defects**

For each exception from Step 2, add `Wrap`, `Expanded`, `Flexible`, scroll containment, or breakpoint-specific layout selection at the widget producing the exception. Do not change service calls, scheduling policies, or stored data to solve a presentation failure.

- [ ] **Step 4: Run complete verification**

Run: `flutter analyze && flutter test -r compact`

Expected: analyzer reports no diagnostics and every Flutter test passes.

- [ ] **Step 5: Review the final diff and commit scoped work only when safe**

Run: `git diff --check && git status --short`

Expected: no whitespace errors; unrelated user changes remain unstaged and untouched.

## Plan self-review

- Spec coverage: Tasks 1-3 implement visual tokens and shell; Task 4 covers focus and micro tasks; Task 5 covers the priority rescue flow; Task 6 covers team, profile, and review; Task 7 covers loading/narrow/wide regression validation.
- Placeholder scan: no unfinished markers, deferred actions, or unspecified implementation steps remain.
- Type consistency: new presentational types are `AppTheme`, `WorkbenchSurface`, `WorkbenchSectionHeader`, `WorkbenchMetric`, `WorkbenchEmptyState`, `WorkbenchStatusBadge`, and `RescuePlanComparison`; none overlap with current model or service names.
