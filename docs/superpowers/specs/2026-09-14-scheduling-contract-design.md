# Scheduling Contract v1 Design

> **Status:** v1 contract boundary, splitting, and risk output implemented and verified
> **Owner:** Member A  
> **Scope:** `/schedule/replan` input/output and the Dart/Python scheduling boundary

## Goal

Define one versioned scheduling JSON contract so Dart, Python and the FastAPI boundary use the same field names, time semantics, ordering rules, issue codes and explanation codes.

## Context

The current Dart and Python requests are mostly structurally similar, but their behavior is not equivalent:

- Dart serializes `SchedulingRequest.day` as a full ISO datetime while the API models it as a date.
- Persisted schedule entries use `height` as an implicit duration; scheduling tasks use `durationMinutes`.
- Python and Dart use different task ordering and placement scoring rules.
- `APIModel` ignores unknown fields, so unsupported scheduling fields can disappear silently.
- `ClockTime`, energy, tuning values and windows are not consistently range-validated.
- Python emits `no_slot`, `miss_due` and `overdue`; dependency blocking and stable explanation data are not represented.

This design establishes the data boundary first. Full `SchedulerCore` algorithm convergence remains a follow-up implementation step, but the contract and fixtures must be ready for it.

## Chosen Approach

Maintain a versioned JSON Schema as the canonical contract and validate it through three adapters:

```text
Dart SchedulingRequest/SchedulingPlan
  -> Dart contract adapter
  -> scheduling.schema.json

FastAPI request/response models
  -> Python contract adapter
  -> scheduling.schema.json

Shared JSON fixtures
  -> Dart tests + Python tests + API tests
```

The first version does not generate Dart or Python code from the schema. Each adapter remains idiomatic to its runtime, while shared fixtures prove that names, values and observable results match.

## Canonical Request

The canonical request has this shape:

```json
{
  "schemaVersion": "1",
  "day": "2026-09-14",
  "tasks": [
    {
      "id": "task_001",
      "title": "完成汇报材料",
      "durationMinutes": 90,
      "priority": 5,
      "due": "2026-09-14T17:00:00+08:00",
      "load": "high",
      "tag": "Deep Work",
      "goalId": null,
      "goalTaskId": null,
      "hardDeadline": false,
      "earliestStart": null,
      "dependsOn": []
    }
  ],
  "windows": [
    {
      "start": {"hour": 9, "minute": 0},
      "end": {"hour": 18, "minute": 0}
    }
  ],
  "energy": "medium",
  "tuning": {
    "defaultDurationMultiplier": 1.0,
    "tagDurationMultiplier": {},
    "highLoadPenaltyWhenLowEnergy": 1.0
  },
  "fixed": []
}
```

### Request rules

- `schemaVersion` is the string `"1"` in canonical payloads. The API adapter treats a missing value as legacy version 1 during migration.
- `day` is a date-only string in `YYYY-MM-DD` form.
- `due` and `earliestStart` use ISO 8601 date-times. Inputs may include an explicit offset; canonical serializers normalize instants to UTC with a `Z` suffix. Legacy naive values are normalized at the API edge as UTC and are never emitted by the canonical serializer. Cross-language tests compare parsed instants, not the original offset spelling.
- `ClockTime.hour` is `0..23`; `ClockTime.minute` is `0..59`.
- A window must have `end` strictly after `start` and applies within the requested day.
- `durationMinutes` is an integer from `1` through `1440`.
- `priority` is an integer from `1` through `5`.
- `load` is one of `low`, `medium`, `high`.
- `energy` is one of `veryLow`, `low`, `medium`, `high`, `veryHigh`.
- `dependsOn` is an array of task IDs. A dependency must be scheduled before its dependent task can start.
- `hardDeadline` is optional and defaults to `false`. When true, the task may not finish after `due`.
- `splittable` defaults to `false`. When true, `minimumChunkMinutes` defaults to 15 and must not exceed `durationMinutes`; false tasks require `minimumChunkMinutes: null`. Split entries use deterministic IDs such as `task_001#1`.
- `fixed` uses the scheduling entry adapter. Its canonical duration is `durationMinutes`; persisted `height` is a legacy storage field and is converted before entering the scheduler.

## Canonical Response

```json
{
  "schemaVersion": "1",
  "entries": [
    {
      "id": "task_001",
      "day": "2026-09-14",
      "title": "完成汇报材料",
      "tag": "Deep Work",
      "load": "high",
      "durationMinutes": 90,
      "time": {"hour": 9, "minute": 0},
      "source": "planned",
      "explanationCodes": ["deadline_proximity", "priority"]
    }
  ],
  "issues": [
      {
        "code": "miss_due",
        "taskId": "task_002",
        "message": "Task scheduled past due time",
        "blockedBy": [],
        "explanationCodes": ["deadline_proximity"]
      }
  ]
}
```

### Response rules

- `entries` is the full plan, including fixed entries and planned entries.
- `durationMinutes` is the only canonical duration field in scheduler output.
- `source` is `fixed`, `planned` or `recovery`.
- `issues.code` is one of `no_slot`, `miss_due`, `overdue` or `dependency_blocked`.
- `issues.taskId` is present when an issue maps to a task. `blockedBy` is an optional array of task IDs and is populated for `dependency_blocked`.
- `explanationCodes` uses stable machine codes, not generated prose. Initial codes are `deadline_proximity`, `priority`, `energy_fit`, `kept_baseline` and `fixed_conflict`.
- Human-readable messages remain informative but are not used for client branching.
- The response does not expose the persistence-only `height` field.
- The response includes `risk.level` (`none`, `low`, `medium`, `high`), `risk.issueCount`, and `risk.hardIssueCount`.

## Ordering and Constraint Semantics

Both implementations must use the same observable ordering:

1. Earlier same-day `due` first.
2. Tasks with a due time before tasks without a due time.
3. Higher `priority` first.
4. Longer `durationMinutes` first.
5. Lexicographically ascending `id` as the final stable tie-breaker.

Placement must apply hard constraints before soft scoring:

1. Preserve fixed entries.
2. Restrict candidates to valid windows.
3. Apply `earliestStart`.
4. Apply dependencies.
5. Apply `hardDeadline`.
6. Score remaining candidates using energy, urgency, priority and baseline stability.

If no candidate satisfies a hard constraint, the result must carry an explicit issue. A soft `due` miss may fall back to the earliest feasible slot and emit `miss_due`; a hard deadline failure must not be presented as an ordinary successful placement.

## Compatibility Boundary

- CRUD schedule endpoints continue to use the persisted `ScheduleEntry` shape, including `height`.
- Only the scheduling adapter converts `height` to/from `durationMinutes` using the existing `80px ~= 60 minutes` compatibility rule.
- `/schedule/replan` accepts canonical v1 payloads. During migration, a missing `schemaVersion` is treated as v1 and legacy fixed entries may carry `height`.
- Unknown fields in scheduling-specific models are rejected with a validation response. The global `APIModel` behavior is not changed for unrelated endpoints.
- Existing clients that only consume `entries`, `issues`, `time` and legacy schedule fields must continue to parse the response through a Dart compatibility adapter while the canonical response remains duration-based.

## Files and Responsibilities

- `contracts/scheduling/v1/scheduling.schema.json`: canonical machine-readable schema.
- `contracts/scheduling/v1/fixtures/*.json`: shared request/response vectors.
- `backend/schemas.py`: strict scheduling boundary models and legacy adapters.
- `backend/services_scheduling.py`: serialize/deserialize through the contract without adding I/O.
- `lib/models/models.dart`: canonical scheduler JSON adapters; persistence models keep their existing storage shape.
- `lib/services/scheduling/`: local engine input/output adapters.
- `backend/tests/`: schema, API and Python fixture tests.
- `test/`: Dart serialization and fixture parity tests.
- `docs/接口预留与服务器接口文档.md`: public endpoint examples and migration note.
- `docs/后端开发守则.md`: link to the schema, ordering and issue-code rules.

## Testing Strategy

Shared fixtures must cover:

- deterministic tie-breaking;
- fixed-entry preservation;
- valid and invalid windows;
- due-time success, soft miss and overdue input;
- low-energy/high-load matching;
- dependency ordering and dependency blocking;
- canonical `durationMinutes` conversion from legacy `height`;
- date-only `day` and offset date-time serialization;
- strict rejection of invalid enum/range/unknown fields.

For every fixture, tests compare:

- accepted/rejected request shape;
- entry IDs and order;
- entry start time and duration;
- issue codes and task IDs;
- explanation codes.

The API test additionally verifies that the response validates against the same JSON Schema. Tests must be written before changing production adapters, and each new contract behavior must first be observed failing.

## Non-goals

- This change does not replace Python with another language.
- This change does not implement the full `SchedulerCore` refactor or rescue strategy weight calculations.
- This change does not alter schedule CRUD storage semantics.
- This change does not add offline sync, third-party calendars or new device integrations.

## Implementation Evidence

The v1 boundary is implemented across the JSON Schema, Python API adapter, Dart adapter, and both heuristic engines:

- `3cbe46d`, `9919c60`, `047b2db`: Schema, fixtures, strict schema validation and reserved-field rules.
- `2ad5988`: strict FastAPI `/schedule/replan` request/response adapter with legacy `height` input conversion.
- `22d08f6`: Dart canonical adapter and persistence compatibility tests.
- `bb0f1db`: matching ordering, dependency blocking, hard-deadline behavior and explanation metadata in Dart/Python.
- `5452dd5`: public API and backend rule documentation.

Verification on the final implementation:

```text
flutter analyze                 -> No issues found
flutter test -r compact         -> 188 tests passed
python -m pytest backend/tests -q -> 98 passed, 4 dependency deprecation warnings
git diff --check                -> clean
```

The shared fixtures are schema-validated and the automated runner executes every fixture through both runtimes, compares the canonical risk object, and emits a machine-generated difference report. Current evidence covers three fixtures with zero differences; production-scale performance benchmarking remains separate.
