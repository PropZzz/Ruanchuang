# Scheduling Parity, SchedulerCore, and Rescue Scoring Design

> **Status:** Implemented and verified on `member-a`
> **Owner:** Member A
> **Scope:** Shared fixture execution, pure scheduler decomposition, and rescue strategy scoring

## Goal

Complete the next scheduling phase by making every shared fixture executable in both runtimes, splitting the scheduling logic into explicit pure-computation cores, and making Dart and Python use the same rescue strategy weights and score semantics.

## Current Context

The v1 JSON contract already exists at `contracts/scheduling/v1/scheduling.schema.json`. It defines canonical task, window, plan entry, issue, and explanation fields. The current implementation has these remaining gaps:

- the fixtures are schema-validated but no process runs all of them through both runtimes;
- Python scheduling remains concentrated in `backend/services_scheduling.py`;
- Dart scheduling remains concentrated in `heuristic_scheduling_engine.dart`;
- the two rescue implementations compose similar inputs but do not calculate the documented strategy weights;
- rescue responses do not expose a comparable score breakdown.

The existing CRUD `ScheduleEntry` shape, including persistence-only `height`, remains unchanged.

## Chosen Architecture

```text
contracts/scheduling/v1/
  scheduling.schema.json
  rescue-strategies.json
  fixtures/*.json

Python:
  scripts/scheduling_parity.py
    -> backend.scheduling.core.SchedulerCore
    -> canonical response adapter

Dart:
  test/scheduling_fixture_runner_test.dart
    -> lib/services/scheduling/scheduler_core.dart
    -> SchedulingContract.planToJson
```

The Python script is the report orchestrator. It invokes one dedicated Flutter test process, parses a marked JSON payload from its standard output, runs each fixture through Python, compares both results with the fixture expectation, and writes a deterministic report. The runner exits non-zero when any fixture is invalid or mismatched.

The first implementation keeps Python and Dart as separate runtime cores. They share the JSON contract, fixture data, ordering rules, constraint semantics, explanation codes, and rescue weight file. No FFI, generated source, or new network service is introduced.

## Fixture Runner Protocol

### Input

The orchestrator discovers every `*.json` file below `contracts/scheduling/v1/fixtures/`. Each fixture has:

```json
{
  "request": {},
  "response": {}
}
```

The request is canonical v1 JSON. The response is the expected canonical result for the deterministic fixture.

### Dart process output

The dedicated Flutter test loads all fixtures and writes exactly one machine-readable line between markers:

```text
SCHEDULING_PARITY_RESULT_BEGIN
{"fixtures":[...]}
SCHEDULING_PARITY_RESULT_END
```

Human test output may surround the markers. The orchestrator must reject missing, duplicated, malformed, or incomplete markers. The Dart runner must not write a success result after an exception.

### Report

The report is written to `reports/scheduling-parity-YYYY-MM-DD.json` and contains:

```json
{
  "schemaVersion": "1",
  "summary": {
    "fixtures": 2,
    "matched": 2,
    "mismatched": 0,
    "invalid": 0
  },
  "fixtures": [
    {
      "name": "basic.json",
      "status": "matched",
      "differences": []
    }
  ]
}
```

Each fixture record includes normalized Python, Dart, and expected values when available. Differences are field-level and restricted to observable contract fields:

- accepted/rejected status;
- entry IDs and order;
- entry `day`, `time`, `durationMinutes`, `source`, and `explanationCodes`;
- issue `code`, `taskId`, `blockedBy`, and `explanationCodes`.

Human-readable issue messages are retained for diagnostics but do not determine parity. Date-times are compared as parsed instants after UTC normalization. The report sorts fixture names lexicographically and preserves array order from each canonical result.

The report is an artifact of a run and is committed when it is used as release evidence. A failed run still writes a report with `mismatched` or `invalid` counts and returns a non-zero exit code.

## SchedulerCore Decomposition

### Python modules

Create `backend/scheduling/` with these boundaries:

- `core.py`: `SchedulerCore.plan(request)` orchestration only; no I/O.
- `normalization.py`: canonical task/window/fixed-entry normalization and UTC/date handling.
- `constraints.py`: fixed blocks, valid windows, `earliestStart`, dependency readiness, and hard-deadline checks.
- `ranking.py`: deterministic task ordering and candidate ordering.
- `scoring.py`: energy/load placement score and strategy score primitives.
- `explanations.py`: stable explanation and issue construction.

`backend/services_scheduling.py` becomes a compatibility facade that calls `SchedulerCore.plan` and retains the current internal dictionary shape for callers that have not migrated. No module under `backend/scheduling/` may import FastAPI, repositories, SQLite, or an HTTP client.

### Dart modules

Create `lib/services/scheduling/scheduler_core.dart` as the pure scheduling implementation boundary. Extract normalization, constraint evaluation, ranking, placement scoring, and explanation construction into private or focused helpers within the scheduling directory. `HeuristicSchedulingEngine` implements `SchedulingEngine` by delegating to `SchedulerCore`; it does not access persistence or network services.

Both cores must preserve this call chain:

```text
API Router / Screen
  -> adapter
  -> SchedulerCore (pure computation)
  -> persistence or presentation adapter
```

## Shared Scheduling Semantics

Task ordering is:

1. same-day `due` ascending;
2. non-same-day due values;
3. tasks without `due`;
4. `priority` descending;
5. `durationMinutes` descending;
6. `id` ascending.

Placement applies hard constraints before soft scoring:

1. preserve fixed entries;
2. valid work windows;
3. `earliestStart`;
4. dependencies;
5. `hardDeadline`;
6. energy, urgency, priority, and baseline stability scoring.

An unresolved or failed dependency produces `dependency_blocked` with `blockedBy` and no planned entry. A soft deadline miss may use the earliest feasible slot and produces `miss_due`. A hard deadline has no late fallback and produces an explicit issue. An overdue task produces `overdue` when it is placed on a later requested day.

## Rescue Strategy Weights

Add `contracts/scheduling/v1/rescue-strategies.json`:

```json
{
  "schemaVersion": "1",
  "recoveryBufferMinutes": 15,
  "strategies": {
    "protectDeadline": {
      "urgency": 0.55,
      "priority": 0.25,
      "energyFit": 0.10,
      "stability": 0.10,
      "recovery": 0.00
    },
    "protectRecovery": {
      "urgency": 0.20,
      "priority": 0.10,
      "energyFit": 0.35,
      "stability": 0.10,
      "recovery": 0.25
    },
    "minimizeChanges": {
      "urgency": 0.25,
      "priority": 0.15,
      "energyFit": 0.05,
      "stability": 0.55,
      "recovery": 0.00
    }
  }
}
```

Each weight must be non-negative and the five weights for one strategy must sum to `1.0` within a tolerance of `0.000001`.

The normalized plan metrics are:

- `urgency`: `1 - missedDeadlineCount / max(1, dueTaskCount)`; `1.0` when no due task is missed.
- `priority`: sum of placed task priorities divided by `5 * max(1, taskCount)`.
- `energyFit`: `1 - weightedLoadMismatch / max(1, placedTaskCount)`; mismatch is `0` for a matching load tier and `1` for the furthest tier.
- `stability`: `1 - movedEntryCount / max(1, baselineEntryCount)`.
- `recovery`: `min(recoveryMinutes / recoveryBufferMinutes, 1.0)`.

The total score is the weighted sum of these five values. Strategy selection first minimizes hard issue count (`fixed_conflict`, `no_slot`, `dependency_blocked`, and hard-deadline failures), then maximizes total score, then uses the fixed strategy order `protectDeadline`, `protectRecovery`, `minimizeChanges` as a stable tie-break.

Each rescue option exposes:

```json
{
  "score": 0.82,
  "scoreBreakdown": {
    "urgency": 0.95,
    "priority": 0.80,
    "energyFit": 0.75,
    "stability": 0.90,
    "recovery": 0.00
  }
}
```

The existing `movedEntryCount`, `recoveryMinutes`, `issueCount`, `affectedEntries`, and `plannedEntries` remain present. Score values are diagnostic and must not override hard-constraint failures.

Python loads the JSON configuration at module initialization through a repository-local path helper. Dart uses a checked-in constant representation maintained from the same JSON; a parity test compares every strategy name, weight, sum, and buffer value to the file. This keeps the synchronous `ScheduleRescueService.propose` API while making divergence visible in CI.

## Error Handling and Compatibility

- Invalid fixture JSON, schema violations, malformed runner markers, or process failures produce an invalid report and non-zero status.
- A single fixture mismatch does not stop collection of later fixtures.
- The Python facade and Dart engine keep existing public method signatures.
- CRUD schedule persistence continues to use `height`; rescue planned entries continue to pass through the existing persistence adapters.
- Existing rescue API fields remain compatible; new `score` and `scoreBreakdown` fields are additive.
- The runner never changes fixtures or rewrites expected output automatically.

## Testing and Acceptance

The implementation is accepted only when:

1. every fixture validates against the v1 Schema;
2. one runner command executes every fixture in both runtimes;
3. the generated report contains no invalid or mismatched fixture;
4. Python and Dart core tests cover deterministic ordering, fixed preservation, windows, earliest start, dependency order/blocking, soft and hard deadlines, low-energy placement, and explanation codes;
5. rescue tests verify all three weight sets, metric calculations, score ordering, stable tie-breaks, recovery buffer, and hard-issue precedence;
6. existing API, rescue transaction, Flutter, and persistence tests remain green;
7. `flutter analyze`, `flutter test -r compact`, `python -m pytest backend/tests -q`, `dart format --set-exit-if-changed ...`, and `git diff --check` pass.

## Non-goals

- No FFI, Go, Rust, C++, or new network scheduling service.
- No database schema migration.
- No offline sync or third-party calendar work.
- No automatic fixture rewriting or tolerance that hides semantic differences.
- No change to the existing rescue transaction's atomicity, baseline hash, snapshot, undo, or event behavior.

## Implementation Evidence

Implemented commits:

- `1370d3f`: versioned rescue strategy weights and pure Python/Dart weight validation.
- `b0c6efb`: Python and Dart `SchedulerCore` entry points with compatibility facades.
- `276dd72`: UTC `Z` parsing compatibility in the Python core.
- `4d0c6b6`: Dart fixture runner and canonical request execution.
- `754caeb`: Python orchestrator and committed parity report.
- `1c8102e`: weighted rescue metrics, option scores, hard-issue precedence, and UI recommendation alignment.
- `acda463`, `0300370`: runner/test cleanup and formatting verification.
- `13fee36`: public documentation and implementation evidence.

Final evidence:

```text
flutter analyze                  -> No issues found
flutter test -r compact          -> 193 tests passed
python -m pytest backend/tests -q -> 106 tests passed, 4 dependency deprecation warnings
python scripts/scheduling_parity.py -> 2 fixtures, 2 matched, 0 mismatched, 0 invalid
dart format --set-exit-if-changed (touched files) -> clean
git diff --check                 -> clean
```

The report is stored at `reports/scheduling-parity-2026-09-14.json`. The two runtime cores are separated behind compatibility facades, support deterministic task splitting, and emit the same risk object. Production-scale performance benchmarking remains separate from this verified behavior change.
