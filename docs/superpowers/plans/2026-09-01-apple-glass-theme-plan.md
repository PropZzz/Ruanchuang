# Apple Glass Theme Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Apply the approved Apple Utility color and selective glass-material system to the shared Flutter UI on Android, iOS, Web, macOS, Windows, and Linux without changing business behavior.

**Architecture:** `lib/theme/app_theme.dart` becomes the single source of semantic colors, typography, motion, breakpoints, and material levels. `GlassSurface` renders explicit `surface`, `chrome`, or `overlay` materials with a solid fallback. Shell and status-bar structure use glass; content cards, timelines, and long lists remain opaque. Existing `lib/ui/app_theme.dart` imports are preserved through a compatibility export.

**Tech Stack:** Flutter Material 3, Dart, `BackdropFilter`, `ImageFilter.blur`, existing widget/test infrastructure. No new package.

---

### Task 1: Establish the visual regression contract

**Files:**
- Modify: `test/app_theme_test.dart`
- Modify: `test/glass_surface_test.dart`
- Create: `test/apple_glass_contract_test.dart`

- [ ] **Step 1: Add failing token and material assertions**

Add tests that import `theme/app_theme.dart` and assert the approved light/dark canvas, action, brand, status colors; `AppMaterialLevel` values; and that `AppTheme.light`/`dark` use Material 3. Add a widget test that pumps `GlassSurface(level: AppMaterialLevel.chrome)` and finds one `BackdropFilter` plus the child text.

- [ ] **Step 2: Run the focused tests and verify the new API fails**

Run: `flutter test test/apple_glass_contract_test.dart test/app_theme_test.dart test/glass_surface_test.dart`

Expected: FAIL because `AppMaterialLevel` and the new `GlassSurface.level` parameter do not yet exist.

- [ ] **Step 3: Commit the red contract**

```powershell
git add test/app_theme_test.dart test/glass_surface_test.dart test/apple_glass_contract_test.dart
git commit -m "test: define apple glass visual contract"
```

### Task 2: Make the canonical theme complete

**Files:**
- Modify: `lib/theme/app_theme.dart`
- Modify: `test/app_theme_test.dart`

- [ ] **Step 1: Add the shared material and breakpoint types**

Add to `lib/theme/app_theme.dart`:

```dart
enum AppMaterialLevel { canvas, surface, chrome, overlay }

abstract final class AppMaterialTokens {
  static const chromeLightOpacity = 0.76;
  static const chromeDarkOpacity = 0.72;
  static const overlayLightOpacity = 0.86;
  static const overlayDarkOpacity = 0.82;
  static const chromeBlur = 22.0;
  static const overlayBlur = 28.0;
}
```

Add `shellBreakpoint = 1024`, `comparisonBreakpoint = 760`, and helper methods that map a material level and brightness to base color, opacity, blur, and shadow alpha. Keep existing public token names and aliases intact.

- [ ] **Step 2: Align typography and component themes with the contract**

Keep the current Material 3 `ThemeData` API, but set the platform font fallback to `system-ui, PingFang SC, Noto Sans SC` through the existing Flutter-compatible font configuration, keep body text at least 12sp, enable tabular figures for timer/metric styles, and retain 44dp button minimums. Update card/dialog/input shapes only where needed to keep content surfaces at 12-14px and dialogs at 20px.

- [ ] **Step 3: Run the canonical theme tests**

Run: `flutter test test/app_theme_test.dart test/apple_glass_contract_test.dart`

Expected: PASS for colors, breakpoints, Material 3, typography sizing, and material-token helpers.

- [ ] **Step 4: Commit the theme foundation**

```powershell
git add lib/theme/app_theme.dart test/app_theme_test.dart test/apple_glass_contract_test.dart
git commit -m "feat: add apple material tokens"
```

### Task 3: Preserve the legacy theme import and implement glass materials

**Files:**
- Modify: `lib/ui/app_theme.dart`
- Modify: `lib/widgets/glass_surface.dart`
- Modify: `test/glass_surface_test.dart`

- [ ] **Step 1: Replace duplicate UI theme definitions with a compatibility export**

Retain a small `AppTheme` compatibility class only if a caller requires `light()`/`dark()` methods; otherwise export the canonical types and add the two existing breakpoint constants to the canonical class. The file must continue to satisfy imports from `main_screen.dart` and `rescue_plan_comparison.dart` without defining a second color palette.

- [ ] **Step 2: Add explicit material levels and solid fallback to `GlassSurface`**

Extend the existing constructor with:

```dart
this.level = AppMaterialLevel.surface,
this.enabled = true,
```

Use the caller-provided `blur`/`opacity` when non-default; otherwise resolve defaults from `AppMaterialTokens`. Keep the constructor default at `AppMaterialLevel.chrome` for backwards compatibility, while all content call sites pass `surface` explicitly. For `canvas`/`surface`, render an opaque decorated box. For `chrome`/`overlay` with `enabled == true` and `!MediaQuery.highContrast`, render the existing `BackdropFilter` plus a tinted surface, top highlight border, and level-specific shadow. For `enabled == false` or high contrast, skip `BackdropFilter` and use the corresponding opaque color while preserving padding, radius, margin, and child semantics.

- [ ] **Step 3: Extend tests for both paths**

Assert that `chrome` uses a `BackdropFilter`, `enabled: false` does not, high-contrast mode does not, and all paths keep the child text and non-zero size.

- [ ] **Step 4: Run focused tests and commit**

Run: `flutter test test/glass_surface_test.dart test/apple_glass_contract_test.dart`

Expected: PASS with both glass and fallback paths covered.

```powershell
git add lib/ui/app_theme.dart lib/widgets/glass_surface.dart test/glass_surface_test.dart
git commit -m "feat: implement selective glass surface"
```

### Task 4: Materialize the responsive shell and status chrome

**Files:**
- Modify: `lib/screens/main_screen.dart`
- Modify: `lib/widgets/workspace_status_bar.dart`
- Modify: `test/main_screen_shell_test.dart`

- [ ] **Step 1: Add shell material tests before changing layout**

Extend `main_screen_shell_test.dart` to pump a wide shell and a narrow shell, assert the existing navigation keys, and assert at least one `BackdropFilter` is present in each shell. Keep tests for rail expansion, selection, and mobile five-item navigation.

- [ ] **Step 2: Apply `chrome` to the wide rail and mobile bottom bar**

Wrap only the rail container and bottom-navigation container with `GlassSurface(level: AppMaterialLevel.chrome, padding: EdgeInsets.zero, showShadow: false)`. Preserve `_railExpanded`, `IndexedStack`, safe-area handling, destination IDs, widths, and callbacks. Keep content pages outside the glass wrapper.

- [ ] **Step 3: Apply `chrome` to `WorkspaceStatusBar`**

Replace its opaque `Container` decoration with `GlassSurface` at `chrome` level while preserving the current compact/non-compact rows, status labels, search/settings callbacks, and 44dp icon constraints. Keep the bottom boundary as the semantic outline/highlight rather than a heavy divider.

- [ ] **Step 4: Run shell tests and commit**

Run: `flutter test test/main_screen_shell_test.dart test/responsive_layout_test.dart`

Expected: PASS with wide rail, collapsed/expanded navigation, mobile bottom bar, status bar semantics, and no shell regressions.

```powershell
git add lib/screens/main_screen.dart lib/widgets/workspace_status_bar.dart test/main_screen_shell_test.dart
git commit -m "feat: add glass responsive shell chrome"
```

### Task 5: Materialize floating summaries without glassifying content

**Files:**
- Modify: `lib/widgets/rescue_summary.dart`
- Modify: `lib/screens/auth_dialog.dart`
- Modify: `lib/widgets/workbench_surface.dart`
- Modify: `test/schedule_rescue_service_test.dart`
- Modify: `test/app_smoke_test.dart`

- [ ] **Step 1: Keep content surfaces opaque and mark floating surfaces explicitly**

Leave `WorkbenchSurface` at the opaque `surface` level for timelines, metrics, forms, and long lists. Add an optional `materialLevel` parameter defaulting to `AppMaterialLevel.surface`; use `GlassSurface` only when callers explicitly pass `chrome` or `overlay`.

- [ ] **Step 2: Update rescue summary and auth dialog visual wrappers**

Use `AppMaterialLevel.overlay` for the rescue summary and authentication dialog surface. Preserve existing callbacks, validation text, reserved/unavailable states, and modal scrim behavior. Do not change service calls or response handling.

- [ ] **Step 3: Add semantic assertions**

Extend smoke tests to assert rescue/auth text and controls remain present, and that the floating wrapper has the expected overlay material while the workbench body remains an opaque surface.

- [ ] **Step 4: Run focused tests and commit**

Run: `flutter test test/app_smoke_test.dart test/schedule_rescue_service_test.dart`

Expected: PASS with unchanged business callbacks and truthful status text.

```powershell
git add lib/widgets/rescue_summary.dart lib/screens/auth_dialog.dart lib/widgets/workbench_surface.dart test/app_smoke_test.dart test/schedule_rescue_service_test.dart
git commit -m "feat: separate overlay materials from content surfaces"
```

### Task 6: Migrate page colors to semantic tokens

**Files:**
- Modify: `lib/screens/focus_page.dart`
- Modify: `lib/screens/smart_calendar_page.dart`
- Modify: `lib/screens/micro_task_page.dart`
- Modify: `lib/screens/team_page.dart`
- Modify: `lib/screens/profile_page.dart`
- Modify: `lib/screens/goals_page.dart`
- Modify: `lib/screens/review_page.dart`
- Modify: `lib/screens/integrations_page.dart`
- Modify: `lib/screens/bluetooth_page.dart`
- Modify: `lib/screens/device_detail_page.dart`
- Modify: `lib/widgets/energy_status_card.dart`
- Modify: `lib/widgets/emotion_quick_checkin_card.dart`
- Modify: `lib/widgets/focus_task_card.dart`
- Modify: `lib/widgets/rescue_plan_comparison.dart`

- [ ] **Step 1: Replace structural hard-coded colors**

For backgrounds, dividers, primary text, secondary text, selected states, disabled states, and generic icons, use `Theme.of(context).colorScheme` or `AppThemeTokens`. Preserve model-provided task/tag colors only for the tag itself. Replace generic `Colors.grey`, `Colors.blueAccent`, `Colors.deepPurpleAccent`, and `Colors.redAccent` used as UI semantics with action/secondary/risk tokens; keep diagnostic-only colors in `screens/debug` unchanged.

- [ ] **Step 2: Normalize semantic status presentation**

Use the existing `WorkbenchStatus` mapping for success/warning/risk/neutral, adding an icon or label wherever a state was previously color-only. Keep 44dp hit targets and existing button callbacks.

- [ ] **Step 3: Apply selective material levels at page boundaries**

Use `AppWindowTones.canvas` for page roots, opaque `WorkbenchSurface`/cards for content, and `overlay` only for existing floating rescue/auth/detail panels. Do not wrap the schedule timeline or long list rows in `BackdropFilter`.

- [ ] **Step 4: Run page visual and responsive tests**

Run: `flutter test test/focus_page_visual_test.dart test/smart_calendar_visual_test.dart test/micro_task_responsive_test.dart test/responsive_layout_test.dart test/responsive_page_frame_test.dart`

Expected: PASS with existing page text, controls, view switches, and responsive constraints intact.

- [ ] **Step 5: Commit the semantic migration**

```powershell
git add lib/screens lib/widgets
git commit -m "refactor: migrate pages to semantic apple colors"
```

### Task 7: Add accessibility and reduced-motion coverage

**Files:**
- Modify: `lib/theme/app_theme.dart`
- Modify: `lib/widgets/glass_surface.dart`
- Modify: `lib/screens/main_screen.dart`
- Modify: `test/app_theme_test.dart`
- Modify: `test/main_screen_shell_test.dart`

- [ ] **Step 1: Test reduced-motion and high-contrast behavior**

Pump shell transitions under `MediaQueryData(disableAnimations: true)` and assert resolved durations are zero. Pump a glass surface under `highContrast: true` and assert it contains no `BackdropFilter`. Assert rail toggle and icon buttons expose tooltip/semantic labels.

- [ ] **Step 2: Keep feedback immediate and interruptible**

Ensure shell transitions use existing `AppMotion.resolve`, press states use the existing `PressScale`, and no new transition disables pointer input. Use opacity/transform-only transitions for material appearance.

- [ ] **Step 3: Run accessibility-focused tests and commit**

Run: `flutter test test/app_theme_test.dart test/main_screen_shell_test.dart test/press_scale_test.dart`

Expected: PASS with reduced motion, high contrast, focus/tooltip, and press feedback assertions.

```powershell
git add lib/theme/app_theme.dart lib/widgets/glass_surface.dart lib/screens/main_screen.dart test/app_theme_test.dart test/main_screen_shell_test.dart
git commit -m "test: cover accessible apple material states"
```

### Task 8: Full verification and visual QA

**Files:**
- Modify: `docs/superpowers/plans/2026-09-01-apple-glass-theme-plan.md` (check off completed steps)
- Create: `docs/visual-qa/apple-glass-1440.png`
- Create: `docs/visual-qa/apple-glass-390.png`

- [ ] **Step 1: Format and statically analyze**

Run: `dart format --set-exit-if-changed lib test`

Expected: exit code 0 with no files needing formatting.

Run: `flutter analyze`

Expected: no new analyzer errors or warnings.

- [ ] **Step 2: Run the full Flutter suite**

Run: `flutter test`

Expected: all existing tests pass, with any pre-existing skips reported separately.

- [ ] **Step 3: Run repository hygiene checks**

Run: `git diff --check`

Expected: no whitespace errors.

- [ ] **Step 4: Capture desktop and mobile screenshots**

Run the existing Flutter Web target or desktop target using the repository startup instructions, capture 1440x900 and 390x844 screens, and inspect that glass is limited to chrome/overlay, text is readable, no content is clipped, and the mobile bottom bar respects the safe area. Record the actual command and paths in the delivery report.

- [ ] **Step 5: Update plan status and commit verification artifacts**

```powershell
git add docs/superpowers/plans/2026-09-01-apple-glass-theme-plan.md docs/visual-qa
git commit -m "test: verify apple glass visual rollout"
```

