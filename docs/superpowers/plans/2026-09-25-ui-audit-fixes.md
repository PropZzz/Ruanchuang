# UI Audit Fixes Implementation Plan

> **For agentic workers:** Execute inline task-by-task with review checkpoints. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Resolve the five accepted UI audit findings while preserving the current navigation destinations, app copy, and responsive layout.

**Architecture:** Keep changes in existing Flutter screen, theme, and surface abstractions. Add a small reusable fatal-error dialog so theme behavior is directly testable; choose the narrow navigation widget from the active Flutter target platform while retaining the same selected-index state.

**Tech Stack:** Flutter Material/Cupertino, Dart, flutter_test.

---

## Files

- Modify `lib/utils/app_strings.dart` for Chinese and English action labels.
- Modify `lib/screens/micro_task_page.dart`, `lib/screens/team_page.dart`, `lib/screens/smart_calendar_page.dart`, and `lib/widgets/schedule_timeline.dart` for accessible icon labels and calendar text sizes.
- Add `lib/widgets/fatal_error_dialog.dart`; use it from `lib/main.dart`.
- Modify `lib/screens/main_screen.dart` for iOS narrow navigation.
- Modify `lib/theme/app_theme.dart` and existing GlassSurface callers only if profiling the call-site inventory shows remaining repeated content surfaces still request blur.
- Modify `lib/widgets/glass_surface.dart` for lower chrome/overlay blur tokens.
- Add or extend focused widget tests in `test/ui_audit_fixes_test.dart`, `test/main_screen_shell_test.dart`, and `test/app_theme_test.dart`.

## Task 1: Label Icon Actions and Improve Calendar Text

**Files:** `lib/utils/app_strings.dart`, `lib/screens/micro_task_page.dart`, `lib/screens/team_page.dart`, `lib/screens/smart_calendar_page.dart`, `lib/widgets/schedule_timeline.dart`, `test/ui_audit_fixes_test.dart`.

- [ ] **Step 1: Add failing tests.** Pump the actual screens with mock data and assert that refresh, previous/next period, timeline delete controls expose localized tooltips. Assert task title, summary, and duration text styles in the calendar are at least 12 logical pixels.
- [ ] **Step 2: Run the focused tests and verify expected failures.** Run `flutter test test/ui_audit_fixes_test.dart`; the missing-tooltip and undersized-style expectations must fail, while setup and rendering complete normally.
- [ ] **Step 3: Add localized labels.** Add `common_refresh`, `calendar_previous_period`, and `calendar_next_period` values to both locale maps, then pass those values to the currently unlabeled icon buttons. Use existing `btn_delete` for timeline delete controls.
- [ ] **Step 4: Raise task-information text sizes.** Set compact calendar task title/summary/time metadata to at least 12; keep decorative axis ticks compact and naturally scalable.
- [ ] **Step 5: Run the focused tests.** Run `flutter test test/ui_audit_fixes_test.dart`; all new assertions must pass.

## Task 2: Make Fatal Error Dialog Theme-Aware

**Files:** `lib/widgets/fatal_error_dialog.dart`, `lib/main.dart`, `test/ui_audit_fixes_test.dart`.

- [ ] **Step 1: Add a failing dark-theme widget test.** Pump `FatalErrorDialog` under `AppTheme.dark`; assert its surface and text colors resolve from the active theme and its close action remains labeled.
- [ ] **Step 2: Run the focused test and verify it fails for the absent widget.** Run `flutter test test/ui_audit_fixes_test.dart`.
- [ ] **Step 3: Extract the dialog.** Implement `FatalErrorDialog` with the existing Chinese message and a close action, using `AlertDialog` and `TextButton` theme defaults rather than literal colors.
- [ ] **Step 4: Use the widget from `main.dart`.** Replace the inline hard-coded dialog subtree with `const FatalErrorDialog()`.
- [ ] **Step 5: Run the focused test.** Run `flutter test test/ui_audit_fixes_test.dart`; verify dark-theme colors and button semantics.

## Task 3: Use Cupertino Navigation on Narrow iOS

**Files:** `lib/screens/main_screen.dart`, `test/main_screen_shell_test.dart`.

- [ ] **Step 1: Add a failing iOS shell test.** Pump `MainScreen` with `ThemeData.platform == TargetPlatform.iOS`; assert `CupertinoTabBar` is present, `NavigationBar` is absent, and tapping a destination updates selection.
- [ ] **Step 2: Run the iOS test and verify the expected widget assertion fails.** Run `flutter test test/main_screen_shell_test.dart --plain-name "iOS narrow shell uses Cupertino tab navigation"`.
- [ ] **Step 3: Add a platform branch in `_NarrowShell`.** Keep the existing `NavigationBar` for Android and use a `CupertinoTabBar` with the same five destination labels, icons, and selected index on iOS. Do not change the wide shell.
- [ ] **Step 4: Run shell tests.** Run `flutter test test/main_screen_shell_test.dart test/responsive_layout_test.dart`; verify Android defaults, iOS selection, and width breakpoints.

## Task 4: Reduce Backdrop Blur Cost

**Files:** `lib/theme/app_theme.dart`, `lib/widgets/glass_surface.dart`, `test/app_theme_test.dart`.

- [ ] **Step 1: Add failing token bounds tests.** Assert chrome and overlay blur tokens remain positive but are lower than the existing 22 and 28 sigma values.
- [ ] **Step 2: Run the test and verify it fails on current token values.** Run `flutter test test/app_theme_test.dart --plain-name "blur tokens keep structural blur restrained"`.
- [ ] **Step 3: Lower only the chrome and overlay blur values.** Preserve semantic surface opacity, high-contrast blur disabling, and existing explicit surface levels. Do not add blur to callers that currently use opaque surfaces.
- [ ] **Step 4: Run surface and theme tests.** Run `flutter test test/app_theme_test.dart`; verify surface-level widgets still omit `BackdropFilter`, chrome/overlay keep it, and high contrast disables it.

## Final Verification

- [ ] Run `flutter analyze`.
- [ ] Run `flutter test test/ui_audit_fixes_test.dart test/main_screen_shell_test.dart test/responsive_layout_test.dart test/app_theme_test.dart`.
- [ ] Inspect `git diff --check`, `git status --short`, and the complete diff; confirm existing `test/failures/` files are untouched.
- [ ] Commit the implementation with a focused message and push `main` to `origin` after all verification passes.
