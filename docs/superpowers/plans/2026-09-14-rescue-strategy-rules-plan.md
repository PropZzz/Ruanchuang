# Rescue Strategy Rules Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the three rescue strategies executable and verifiable across the versioned contract, Python scheduler, Dart scheduler, and rescue option scoring.

**Architecture:** Keep one shared JSON policy as the source of truth for strategy metadata, constraints, metrics, weights, and explanation-code order. Both runtimes run the same hard-constraint phase first, then compute strategy-specific soft metrics; existing rescue persistence remains an adapter boundary.

**Tech Stack:** Python 3.10, pytest, Pydantic, Flutter/Dart, JSON fixtures, existing `SchedulerCore` and `ScheduleRescueService` APIs.

---

### Task 1: Extend the strategy contract and publish the rule matrix

**Files:**
- Modify: `contracts/scheduling/v1/rescue-strategies.json`
- Create: `docs/救援策略规则.md`
- Modify: `backend/scheduling/rescue_scoring.py`
- Modify: `lib/services/scheduling/rescue_strategy_weights.dart`
- Test: `backend/tests/test_rescue_scoring.py`
- Test: `test/rescue_strategy_weights_test.dart`

- [ ] **Step 1: Add machine-readable policy fields and a human rule table**

Keep `schemaVersion` at `1` and add `policyVersion`, `hardConstraintOrder`, `explanationCodeOrder`, and per-strategy fields for `scenario`, `fixedSchedule`, `baselinePolicy`, `deadlinePolicy`, `lowEnergyPolicy`, `movementPolicy`, `recoveryPolicy`, and `overdueRiskPolicy`. Keep the existing five weights and 15-minute buffer unchanged. In `docs/救援策略规则.md`, reproduce the exact strategy matrix from the design doc, including formulas and the hard-before-soft rule.

- [ ] **Step 2: Add failing contract assertions**

Assert all three strategies expose every policy field, the hard-constraint order is fixed, the explanation-code order is stable, and the existing weights still sum to `1.0` within `0.000001`.

- [ ] **Step 3: Validate and expose the policy without importing I/O**

Make Python `load_strategy_config()` validate the new enums, lists, and policy keys and return them in an immutable `RescueStrategyConfig`. Mirror the string constants and validation in Dart. Reject duplicate order entries and unknown explanation codes.

- [ ] **Step 4: Run focused contract tests**

Run `python -m pytest backend/tests/test_rescue_scoring.py -q` and `flutter test test/rescue_strategy_weights_test.dart`; both must pass before continuing.

- [ ] **Step 5: Commit the contract**

Run `git add contracts/scheduling/v1/rescue-strategies.json docs/救援策略规则.md backend/scheduling/rescue_scoring.py backend/tests/test_rescue_scoring.py lib/services/scheduling/rescue_strategy_weights.dart test/rescue_strategy_weights_test.dart` and commit with `feat: version rescue strategy rules`.

### Task 2: Make Python scheduling constraints explicit and safe

**Files:**
- Modify: `backend/scheduling/core.py`
- Modify: `backend/services_rescue.py`
- Modify: `backend/scheduling/rescue_scoring.py`
- Test: `backend/tests/test_scheduler_core.py`
- Test: `backend/tests/test_services_rescue.py`

- [ ] **Step 1: Add red tests for hard constraints**

Cover an empty-window request (must produce `no_slot`), `earliestStart` at/after the window end (must not place outside the window), fixed overlap/out-of-window diagnostics, a hard deadline with no late fallback, unresolved dependency blocking, and a recovery buffer that is inserted only into a free 15-minute interval.

- [ ] **Step 2: Fix interval and fixed-entry validation**

Validate candidate start plus duration against the actual interval after applying `earliestStart`; never use the interval length as a substitute for the shifted candidate. Keep fixed entries in the output, subtract only valid blocks from windows, and attach `fixed_conflict` when a fixed block overlaps another fixed block or lies outside every supplied work window. Do not create a default work window when the request supplied none.

- [ ] **Step 3: Preserve hard deadline semantics**

Treat `hardDeadline` as a no-late-fallback constraint and emit a hard `no_slot` issue with `deadline_proximity` when it cannot be met. Keep soft deadline fallback at the earliest legal slot and emit `miss_due`; retain `overdue` for a requested day after the due date.

- [ ] **Step 4: Implement feasible recovery placement**

Select the first 15-minute free interval at or after noon, then any free interval, after subtracting fixed blocks. Return no synthetic block when no interval can hold the buffer, and pass the actual inserted minutes to scoring.

- [ ] **Step 5: Fix Python rescue metrics and policy composition**

Count placed split entries by their base task ID, calculate `overdueRisk` and `urgency` from the same due-task set, and keep the denominator equal to the tasks actually evaluated by each strategy. All strategies must pass the same request to the scheduler; `minimizeChanges` locks the baseline through fixed entries, while the other strategies may move only non-fixed baseline entries. Attach stable explanation codes to planned/fixed entries and issues.

- [ ] **Step 6: Run Python rescue and scheduler tests**

Run `python -m pytest backend/tests/test_scheduler_core.py backend/tests/test_services_rescue.py backend/tests/test_rescue_scoring.py -q` and confirm all new and existing tests pass.

- [ ] **Step 7: Commit Python behavior**

Commit the touched Python files with `feat: enforce rescue hard constraints`.

### Task 3: Align the Dart scheduler and local rescue behavior

**Files:**
- Modify: `lib/services/scheduling/scheduler_core.dart`
- Modify: `lib/services/scheduling/schedule_rescue.dart`
- Modify: `lib/services/scheduling/rescue_scoring.dart`
- Modify: `lib/models/models.dart`
- Test: `test/scheduler_core_test.dart`
- Test: `test/schedule_rescue_service_test.dart`
- Test: `test/rescue_scoring_integration_test.dart`

- [ ] **Step 1: Add matching red Dart tests**

Mirror the Python cases for empty windows, shifted `earliestStart`, fixed conflicts, hard/soft deadlines, dependency blocking, feasible recovery placement, strategy-specific baseline locking, split-task metrics, overdue risk, and deterministic explanation-code order.

- [ ] **Step 2: Fix Dart hard-constraint placement**

Check `candidate + duration <= interval.end` after every earliest-start shift, stop fabricating a default window, preserve fixed entries, and emit the same issue codes and hard count as Python.

- [ ] **Step 3: Implement the shared local rescue policy**

Use the policy constants for all three strategies. Keep fixed entries immutable; add the baseline to fixed only for `minimizeChanges`; insert and count recovery only when a real legal interval exists; calculate moved IDs, split-task metrics, overdue risk, and explanation codes with the Python formulas.

- [ ] **Step 4: Extend model diagnostics additively**

Add optional `overdueRisk` and `ruleCodes`/policy metadata to rescue options only if the existing JSON readers remain backward-compatible; retain all existing fields and constructors with defaults.

- [ ] **Step 5: Run Dart focused tests and analyzer**

Run `flutter test test/scheduler_core_test.dart test/schedule_rescue_service_test.dart test/rescue_scoring_integration_test.dart` and `flutter analyze`.

- [ ] **Step 6: Commit Dart behavior**

Commit with `feat: align local rescue strategy rules`.

### Task 4: Add shared strategy fixtures and recommendation precedence tests

**Files:**
- Create: `contracts/scheduling/v1/fixtures/rescue-strategies.json`
- Modify: `backend/tests/test_rescue_api.py`
- Modify: `test/scheduling_fixture_runner_test.dart`
- Modify: `backend/tests/test_scheduling_parity.py`

- [ ] **Step 1: Add one fixture per strategy outcome**

Include a fixed conflict, a hard deadline failure, a dependency block, a low-energy recovery case with a legal 15-minute buffer, and a minimize-changes case where the urgent task has no slot unless the baseline moves.

- [ ] **Step 2: Assert hard precedence over score**

Create two options where the hard-issue-free option has a lower soft score; assert it is recommended. Also assert stable strategy order when hard counts and scores tie.

- [ ] **Step 3: Run both runtime fixture paths**

Run `python scripts/scheduling_parity.py` and `flutter test test/scheduling_fixture_runner_test.dart`; every fixture must have identical entries, issues, metrics, and explanation-code arrays in both runtimes.

- [ ] **Step 4: Commit shared verification vectors**

Commit with `test: cover rescue strategy rule matrix`.

### Task 5: Complete documentation and regression verification

**Files:**
- Modify: `docs/后端开发守则.md`
- Modify: `docs/接口预留与服务器接口文档.md`
- Modify: `docs/superpowers/specs/2026-09-14-rescue-strategy-rules-design.md`
- Modify: `docs/成员A-基线变更清单.md`

- [ ] **Step 1: Replace contradictory strategy descriptions**

Document that fixed schedules are never moved, empty windows are not defaulted, recovery minutes are actual placed minutes, `overdueRisk` is derived from deadline issues, and hard constraints precede score. Remove any recommendation text that ranks by raw issue count before hard issue count or allows score to override a hard failure.

- [ ] **Step 2: Run the full validation set**

Run `python -m pytest backend/tests -q`, `flutter test -r compact`, `flutter analyze`, `python scripts/scheduling_parity.py`, `dart format --set-exit-if-changed lib test`, and `git diff --check`.

- [ ] **Step 3: Record evidence and commit docs**

Record exact test counts and parity summary in the baseline/spec docs, then commit with `docs: record rescue strategy rule verification`.
