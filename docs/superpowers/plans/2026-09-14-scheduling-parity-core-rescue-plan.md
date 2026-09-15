# Scheduling Parity, SchedulerCore, and Rescue Scoring Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Execute every scheduling fixture through Python and Dart, split both schedulers into pure `SchedulerCore` modules, and apply identical versioned rescue weights and score semantics.

**Architecture:** The existing v1 JSON contract remains the boundary. Python and Dart each expose a pure core with adapters around it; a Python orchestrator invokes one dedicated Flutter test runner and compares normalized results against each other and the fixture expectation. Rescue weights live in one JSON file, with a checked-in Dart constant mirror guarded by parity tests.

**Tech Stack:** Python 3.10, FastAPI/Pydantic, pytest, `jsonschema`, Flutter/Dart 3.10, `dart:convert`, `dart:io`, JSON fixtures.

---

### Task 1: Add the shared rescue weight contract and score primitives

**Files:**
- Create: `contracts/scheduling/v1/rescue-strategies.json`
- Create: `backend/scheduling/rescue_scoring.py`
- Create: `backend/tests/test_rescue_scoring.py`
- Create: `lib/services/scheduling/rescue_strategy_weights.dart`
- Create: `test/rescue_strategy_weights_test.dart`

- [ ] **Step 1: Write failing weight and metric tests**

Python tests must load the JSON file, assert all three strategy names, assert non-negative weights, assert each strategy sums to `1.0` within `0.000001`, and verify the weighted sum:

```python
def test_strategy_weights_are_normalized():
    config = load_strategy_config()
    assert config.recovery_buffer_minutes == 15
    for weights in config.strategies.values():
        assert abs(sum(weights.values()) - 1.0) <= 0.000001


def test_score_uses_weighted_metrics():
    weights = load_strategy_config().strategies["protectDeadline"]
    metrics = PlanMetrics(1.0, 0.8, 0.5, 0.9, 0.0)
    assert score_plan(weights, metrics) == 0.85
```

Dart tests must compare every constant to the JSON values and reject a sum outside the same tolerance.

- [ ] **Step 2: Run the focused tests and verify the red state**

```powershell
python -m pytest backend/tests/test_rescue_scoring.py -q
flutter test test/rescue_strategy_weights_test.dart
```

Expected: FAIL because the config, scorer, and Dart constants do not exist.

- [ ] **Step 3: Add the versioned weight file**

Use these exact strategy weights and recovery buffer:

```json
{
  "schemaVersion": "1",
  "recoveryBufferMinutes": 15,
  "strategies": {
    "protectDeadline": {"urgency": 0.55, "priority": 0.25, "energyFit": 0.10, "stability": 0.10, "recovery": 0.00},
    "protectRecovery": {"urgency": 0.20, "priority": 0.10, "energyFit": 0.35, "stability": 0.10, "recovery": 0.25},
    "minimizeChanges": {"urgency": 0.25, "priority": 0.15, "energyFit": 0.05, "stability": 0.55, "recovery": 0.00}
  }
}
```

- [ ] **Step 4: Implement pure score primitives**

Define `PlanMetrics`, `load_strategy_config()`, and `score_plan(weights, metrics)` in Python. Round scores to six decimal places. Add the equivalent immutable maps and validation method in Dart. Neither implementation may import FastAPI, repositories, SQLite, widgets, or persistence.

- [ ] **Step 5: Run both focused suites and commit**

```powershell
python -m pytest backend/tests/test_rescue_scoring.py -q
flutter test test/rescue_strategy_weights_test.dart
git diff --check
git add contracts/scheduling/v1/rescue-strategies.json backend/scheduling/rescue_scoring.py backend/tests/test_rescue_scoring.py lib/services/scheduling/rescue_strategy_weights.dart test/rescue_strategy_weights_test.dart
git commit -m "feat: add shared rescue strategy weights"
```

### Task 2: Split the Python scheduler into `SchedulerCore`

**Files:**
- Create: `backend/scheduling/core.py`
- Create: `backend/scheduling/normalization.py`
- Create: `backend/scheduling/constraints.py`
- Create: `backend/scheduling/ranking.py`
- Create: `backend/scheduling/scoring.py`
- Create: `backend/scheduling/explanations.py`
- Modify: `backend/services_scheduling.py`
- Create: `backend/tests/test_scheduler_core.py`

- [ ] **Step 1: Write failing core boundary tests**

```python
def test_scheduler_core_returns_internal_plan():
    result = SchedulerCore().plan(request)
    assert [entry["id"] for entry in result["entries"]] == ["a", "b"]
    assert result["entries"][0]["source"] == "planned"


def test_scheduler_core_has_no_persistence_imports():
    source = Path("backend/scheduling/core.py").read_text(encoding="utf-8")
    assert "repositories" not in source
    assert "sqlite" not in source.lower()
```

Include cases for fixed preservation, valid windows, `earliestStart`, dependency order/blocking, soft and hard deadlines, low-energy placement, issue codes, and explanation codes.

- [ ] **Step 2: Run the core tests and verify red**

```powershell
python -m pytest backend/tests/test_scheduler_core.py -q
```

Expected: FAIL because `backend.scheduling.core.SchedulerCore` does not exist.

- [ ] **Step 3: Extract normalization and ranking**

Move the pure date, time, height conversion, task sort, and interval helpers from `backend/services_scheduling.py`. Expose this exact ranking function:

```python
def task_sort_key(task: dict[str, Any], current_day: str | None) -> tuple:
    """same-day due, other due, no due, priority, duration, id."""
```

Do not change the existing internal `height` result shape in this task.

- [ ] **Step 4: Extract constraints, scoring, and explanations**

Implement pure functions for fixed blocks, windows, earliest start, dependency readiness, hard deadlines, energy placement, and stable issue/explanation construction. Return new lists instead of mutating request data. Use `dependency_blocked` with `blockedBy` and no planned entry for unresolved dependencies.

- [ ] **Step 5: Implement the core and keep the facade**

Expose `SchedulerCore.plan(request: dict[str, Any]) -> dict[str, Any]` as the only core entry point. Its implementation must return the internal plan dictionary. Keep `plan_schedule(request: dict[str, Any]) -> dict[str, Any]` in the facade and make it return `SchedulerCore().plan(request)`.

`backend/services_scheduling.py` must become the compatibility facade. It must not add I/O, and the existing API/rescue adapters must continue receiving internal `height` entries.

- [ ] **Step 6: Run tests and commit**

```powershell
python -m pytest backend/tests/test_scheduler_core.py backend/tests/test_scheduling.py -q
python -m pytest backend/tests -q
git add backend/scheduling backend/services_scheduling.py backend/tests/test_scheduler_core.py backend/tests/test_scheduling.py
git commit -m "refactor: split Python scheduler core"
```

### Task 3: Split the Dart scheduler into `SchedulerCore`

**Files:**
- Create: `lib/services/scheduling/scheduler_core.dart`
- Modify: `lib/services/scheduling/heuristic_scheduling_engine.dart`
- Create: `test/scheduler_core_test.dart`

- [ ] **Step 1: Write failing Dart core tests**

```dart
test('SchedulerCore preserves ordering and dependency issues', () {
  final plan = SchedulerCore().plan(request);
  expect(plan.entries.map((entry) => entry.id), ['a', 'b']);
  expect(plan.issues.single.code, 'dependency_blocked');
});
```

Cover the same fixed/window/earliest/dependency/deadline/energy cases as the Python core.

- [ ] **Step 2: Run the focused test and verify red**

```powershell
flutter test test/scheduler_core_test.dart
```

Expected: FAIL because `SchedulerCore` does not exist.

- [ ] **Step 3: Extract the pure scheduling implementation**

Move interval, ranking, constraints, placement scoring, and explanation helpers from `heuristic_scheduling_engine.dart` into `SchedulerCore`. The file may import models and standard collections, but no screen, service, network, database, or persistence module.

- [ ] **Step 4: Delegate from the existing engine interface**

```dart
class HeuristicSchedulingEngine implements SchedulingEngine {
  const HeuristicSchedulingEngine({SchedulerCore? core})
      : _core = core ?? const SchedulerCore();

  final SchedulerCore _core;

  @override
  SchedulingPlan plan(SchedulingRequest request) => _core.plan(request);
}
```

Preserve constructor compatibility and existing low-energy behavior.

- [ ] **Step 5: Run focused tests and commit**

```powershell
flutter test test/scheduler_core_test.dart test/heuristic_scheduling_engine_test.dart
flutter analyze
git add lib/services/scheduling/scheduler_core.dart lib/services/scheduling/heuristic_scheduling_engine.dart test/scheduler_core_test.dart
git commit -m "refactor: split Dart scheduler core"
```

### Task 4: Add the dedicated Dart fixture runner

**Files:**
- Create: `test/scheduling_fixture_runner_test.dart`
- Create: `test/support/scheduling_fixture_runner.dart`
- Modify: `test/scheduling_contract_test.dart`

- [ ] **Step 1: Write failing runner protocol tests**

```dart
test('runner discovers every fixture and emits one marked payload', () {
  final result = runFixtureDirectory('contracts/scheduling/v1/fixtures');
  expect(result.beginMarkerCount, 1);
  expect(result.endMarkerCount, 1);
  expect(result.fixtures, hasLength(2));
});
```

- [ ] **Step 2: Run the runner test and verify red**

```powershell
flutter test test/scheduling_fixture_runner_test.dart
```

Expected: FAIL because the runner and marker protocol do not exist.

- [ ] **Step 3: Implement fixture loading and execution**

The runner must discover and lexicographically sort every `*.json`, decode `request` and `response`, validate the request through `SchedulingContract`, execute `const SchedulerCore().plan(request)`, serialize with `SchedulingContract.planToJson(plan)`, and collect a result for every fixture without stopping at the first mismatch. Use `Platform.environment['SCHEDULING_FIXTURES_DIR']` when set and default to `contracts/scheduling/v1/fixtures`.

- [ ] **Step 4: Implement the marked output protocol**

Print exactly one JSON payload between `SCHEDULING_PARITY_RESULT_BEGIN` and `SCHEDULING_PARITY_RESULT_END`. Reject missing, duplicate, malformed, or incomplete payloads. Compare accepted status, entry IDs/order/day/time/duration/source/explanation codes, and issue code/taskId/blockedBy/explanation codes; compare date-times as UTC instants and keep messages diagnostic only.

- [ ] **Step 5: Run focused tests and commit**

```powershell
flutter test test/scheduling_fixture_runner_test.dart test/scheduling_contract_test.dart
flutter analyze
git diff --check
git add test/scheduling_fixture_runner_test.dart test/support/scheduling_fixture_runner.dart test/scheduling_contract_test.dart
git commit -m "test: add Dart scheduling fixture runner"
```

### Task 5: Add the Python parity orchestrator and report

**Files:**
- Create: `scripts/scheduling_parity.py`
- Create: `backend/tests/test_scheduling_parity.py`
- Create: `reports/.gitkeep`
- Create: `reports/scheduling-parity-2026-09-14.json`
- Modify: `.gitignore` only if needed to keep the report trackable

- [ ] **Step 1: Write failing orchestrator tests**

```python
def test_parse_runner_output_requires_one_marker_pair():
    parsed = parse_runner_output(_marked_payload())
    assert len(parsed["fixtures"]) == 2
    with pytest.raises(ParityRunnerError):
        parse_runner_output("SCHEDULING_PARITY_RESULT_BEGIN\n{}\n")


def test_compare_results_reports_field_level_difference():
    diff = compare_results(expected, python_result, dart_result)
    assert diff["status"] == "mismatched"
    assert any(item["field"] == "entries[0].durationMinutes" for item in diff["differences"])
```

- [ ] **Step 2: Run the orchestrator tests and verify red**

```powershell
python -m pytest backend/tests/test_scheduling_parity.py -q
```

Expected: FAIL because the orchestrator functions do not exist.

- [ ] **Step 3: Implement the orchestrator functions**

Implement these functions in `scripts/scheduling_parity.py` with the listed signatures and behavior: `load_fixtures(root: Path) -> list[tuple[str, dict[str, Any]]]` reads and sorts fixture files; `run_python_fixture(fixture: dict[str, Any]) -> dict[str, Any]` validates and executes Python; `run_dart_runner(root: Path) -> dict[str, Any]` launches Flutter and parses its markers; `parse_runner_output(stdout: str) -> dict[str, Any]` enforces one complete marker pair; `compare_results(expected: dict[str, Any], python: dict[str, Any], dart: dict[str, Any]) -> dict[str, Any]` returns field-level differences; `write_report(report: dict[str, Any], path: Path) -> None` writes stable UTF-8 JSON.

`run_python_fixture` validates through the Python v1 adapter, calls `SchedulerCore`, and converts to canonical response. `run_dart_runner` launches one process with `subprocess.run(["flutter", "test", "test/scheduling_fixture_runner_test.dart", "-r", "compact"], cwd=root, capture_output=True, text=True, check=False)` and passes `SCHEDULING_FIXTURES_DIR` through the environment.

- [ ] **Step 4: Implement deterministic reports and exit status**

Sort fixture names, include `summary.fixtures`, `matched`, `mismatched`, and `invalid`, write `reports/scheduling-parity-2026-09-14.json`, and return exit code `0` only when mismatched and invalid are both zero. A failed run must still write its diagnostic report.

- [ ] **Step 5: Run and resolve every reported difference**

```powershell
python scripts/scheduling_parity.py
```

Expected: every fixture appears in the report with zero mismatches and zero invalid results. Resolve differences in core code or fixture expectations; do not edit the report to hide a mismatch.

- [ ] **Step 6: Commit the runner and report**

```powershell
git add scripts/scheduling_parity.py backend/tests/test_scheduling_parity.py reports
git commit -m "test: generate scheduling parity report"
```

### Task 6: Integrate weighted rescue scoring

**Files:**
- Modify: `backend/scheduling/rescue_scoring.py`
- Modify: `backend/services_rescue.py`
- Modify: `backend/schemas.py`
- Modify: `backend/tests/test_services_rescue.py`
- Modify: `lib/services/scheduling/rescue_strategy_weights.dart`
- Modify: `lib/services/scheduling/schedule_rescue.dart`
- Modify: `lib/models/models.dart`
- Create: `test/rescue_scoring_integration_test.dart`

- [ ] **Step 1: Write failing rescue score tests**

Assert every option exposes `score` and `scoreBreakdown`, every breakdown has `urgency`, `priority`, `energyFit`, `stability`, and `recovery`, the score equals the weighted sum, and hard issue count outranks a higher soft score.

```python
def test_rescue_options_are_ranked_by_hard_issues_then_score():
    result = build_options(_request())
    for option in result["options"]:
        assert set(option["scoreBreakdown"]) == {"urgency", "priority", "energyFit", "stability", "recovery"}
        assert 0.0 <= option["score"] <= 1.0
```

- [ ] **Step 2: Run rescue tests and verify red**

```powershell
python -m pytest backend/tests/test_services_rescue.py -q
flutter test test/rescue_scoring_integration_test.dart
```

Expected: FAIL because current options have no score or breakdown.

- [ ] **Step 3: Implement the exact shared metric formulas**

Use these formulas in Python and Dart, clamp each metric to `[0, 1]`, then apply the strategy weights:

```text
urgency   = 1 - missedDeadlineCount / max(1, dueTaskCount)
priority  = placedPrioritySum / (5 * max(1, taskCount))
energyFit = 1 - weightedLoadMismatch / max(1, placedTaskCount)
stability = 1 - movedEntryCount / max(1, baselineEntryCount)
recovery  = min(recoveryMinutes / recoveryBufferMinutes, 1)
```

- [ ] **Step 4: Extend options additively and integrate ranking**

Add optional `score` and `scoreBreakdown` to `RescueOptionOut` and the Dart rescue option model. Replace recommendation ordering with `(hardIssueCount, -score, strategyOrder)`. Use the configured recovery buffer, preserving baseline hash, transaction, snapshot, undo, events, and existing fields.

- [ ] **Step 5: Run rescue and full regression tests**

```powershell
python -m pytest backend/tests/test_services_rescue.py backend/tests/test_rescue_api.py -q
flutter test test/rescue_scoring_integration_test.dart test/schedule_rescue_service_test.dart
python -m pytest backend/tests -q
flutter test -r compact
```

- [ ] **Step 6: Commit weighted rescue integration**

```powershell
git add backend/scheduling/rescue_scoring.py backend/services_rescue.py backend/schemas.py backend/tests/test_services_rescue.py lib/services/scheduling/rescue_strategy_weights.dart lib/services/scheduling/schedule_rescue.dart lib/models/models.dart test/rescue_scoring_integration_test.dart
git commit -m "feat: unify weighted rescue scoring"
```

### Task 7: Publish evidence and complete verification

**Files:**
- Modify: `docs/superpowers/specs/2026-09-14-scheduling-parity-core-rescue-design.md`
- Modify: `docs/成员A-基线变更清单.md`
- Modify: `docs/接口预留与服务器接口文档.md`
- Modify: `docs/后端开发守则.md`
- Modify: `docs/五人开发分工文档.md`

- [ ] **Step 1: Document the final behavior**

Record the runner command and report path, Python/Dart core chain, weight file, score fields, hard-issue precedence, and the persistence-only `height` boundary.

- [ ] **Step 2: Run the complete validation set**

```powershell
flutter analyze
flutter test -r compact
python -m pytest backend/tests -q
python scripts/scheduling_parity.py
dart format --set-exit-if-changed lib test
git diff --check
git status --short --branch
```

Expected: no analysis errors, all tests pass, parity report has zero mismatches and invalid fixtures, formatting and diff checks pass, and the working tree is clean after committing evidence.

- [ ] **Step 3: Record exact evidence and residual scope**

Update the spec and baseline record with exact test counts, report summary, dependency warnings, and any remaining production performance or deployment work. Do not mark unverified capabilities complete.

- [ ] **Step 4: Commit final evidence**

```powershell
git add docs/superpowers/specs/2026-09-14-scheduling-parity-core-rescue-design.md docs/成员A-基线变更清单.md docs/接口预留与服务器接口文档.md docs/后端开发守则.md docs/五人开发分工文档.md
git commit -m "docs: record scheduling parity and rescue evidence"
```
