# Scheduling Contract v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `/schedule/replan`, Python scheduling, and Dart scheduling share one versioned JSON contract with canonical duration, time, ordering, issue, and explanation semantics.

**Architecture:** A versioned JSON Schema under `contracts/scheduling/v1` is the source of truth. Python and Dart keep runtime-specific models but serialize through explicit adapters. Persisted CRUD schedule entries retain legacy `height`; only the scheduling adapter converts between `height` and canonical `durationMinutes`. Shared fixtures are consumed by Python tests, API tests, and Dart tests.

**Tech Stack:** FastAPI/Pydantic 2, Python `jsonschema`, Flutter/Dart model adapters, pytest, Flutter test, JSON fixtures.

---

### Task 1: Add the canonical schema and shared fixtures

**Files:**
- Create: `contracts/scheduling/v1/scheduling.schema.json`
- Create: `contracts/scheduling/v1/fixtures/basic.json`
- Create: `contracts/scheduling/v1/fixtures/dependency-blocked.json`
- Modify: `backend/requirements.txt`

- [ ] **Step 1: Write the schema fixture tests first**

Create `backend/tests/test_scheduling_schema.py` with tests that load the schema and fixtures, validate both canonical requests and expected responses, and reject an invalid priority, invalid clock minute, and unknown request field.

```python
from jsonschema import Draft202012Validator


def test_shared_fixture_matches_schema():
    schema = _load_json("contracts/scheduling/v1/scheduling.schema.json")
    fixture = _load_json("contracts/scheduling/v1/fixtures/basic.json")
    validator = Draft202012Validator(schema)
    validator.validate(fixture["request"])
    validator.validate(fixture["response"])


def test_schema_rejects_unknown_task_field():
    schema = _load_json("contracts/scheduling/v1/scheduling.schema.json")
    fixture = _load_json("contracts/scheduling/v1/fixtures/basic.json")
    invalid = copy.deepcopy(fixture["request"])
    invalid["tasks"][0]["unknownField"] = True
    errors = list(Draft202012Validator(schema).iter_errors(invalid))
    assert errors
```

- [ ] **Step 2: Run the schema tests to verify the intended red state**

Run:

```powershell
python -m pytest backend/tests/test_scheduling_schema.py -q
```

Expected: FAIL because the schema, fixtures, and `jsonschema` dependency are not present yet.

- [ ] **Step 3: Add the v1 JSON Schema**

Define reusable `ClockTime`, `TimeWindow`, `Task`, `FixedEntry`, `PlanEntry`, `Issue`, `Request`, and `Response` definitions. Set `additionalProperties: false` for scheduling objects, use `camelCase`, and enforce:

```text
schemaVersion = "1"
day = YYYY-MM-DD
hour = 0..23
minute = 0..59
durationMinutes = 1..1440
priority = 1..5
energy = veryLow|low|medium|high|veryHigh
issue code = no_slot|miss_due|overdue|dependency_blocked
```

The canonical fixed and planned entry shape must contain `durationMinutes` and `time`; `height` must not appear in the schema.

- [ ] **Step 4: Add representative fixtures**

`basic.json` must include one fixed entry, two tasks with the same priority, one offset `due`, and the expected stable `id` tie-break. `dependency-blocked.json` must include a task whose dependency cannot be scheduled and an expected `dependency_blocked` issue with `blockedBy`.

- [ ] **Step 5: Pin the Python schema test dependency**

Add `jsonschema>=4.26,<5` to `backend/requirements.txt` and keep the test import in the backend test suite.

- [ ] **Step 6: Run the schema tests to verify green**

Run:

```powershell
python -m pytest backend/tests/test_scheduling_schema.py -q
```

Expected: all schema and fixture validation tests pass.

- [ ] **Step 7: Commit the schema boundary**

```powershell
git add contracts/scheduling/v1 backend/requirements.txt backend/tests/test_scheduling_schema.py
git commit -m "feat: add scheduling contract v1 schema"
```

### Task 2: Add strict Python scheduling models and API adapters

**Files:**
- Create: `backend/scheduling_contract.py`
- Modify: `backend/routers_schedule.py`
- Modify: `backend/services_scheduling.py`
- Modify: `backend/tests/test_scheduling_contract.py`
- Modify: `backend/tests/test_api_flow.py`

- [ ] **Step 1: Write failing Python contract tests**

Add tests for:

- missing `schemaVersion` being normalized to v1 only at the API boundary;
- invalid `energy`, `priority`, `ClockTime`, window order, and unknown fields returning validation errors;
- legacy fixed `height` converting to canonical `durationMinutes`;
- canonical response containing `schemaVersion`, `durationMinutes`, `source`, and `explanationCodes`, without `height`.

Example assertion:

```python
def test_legacy_height_is_converted_without_leaking_into_response():
    request = SchedulingRequestV1.model_validate(_legacy_request())
    assert request.fixed[0].duration_minutes == 60
    response = to_contract_response({"entries": [_legacy_entry(height=80.0)], "issues": []})
    assert response["entries"][0]["durationMinutes"] == 60
    assert "height" not in response["entries"][0]
```

- [ ] **Step 2: Run the focused Python tests and confirm red**

Run:

```powershell
python -m pytest backend/tests/test_scheduling_contract.py -q
```

Expected: FAIL because the v1 models and adapters do not exist.

- [ ] **Step 3: Implement `backend/scheduling_contract.py`**

Add strict Pydantic models with `extra="forbid"` for scheduling-only objects:

```python
class SchedulingModel(BaseModel):
    model_config = ConfigDict(
        populate_by_name=True,
        extra="forbid",
    )


class SchedulingRequestV1(SchedulingModel):
    schema_version: Literal["1"] = Field(default="1", alias="schemaVersion")
    day: date
    tasks: list[SchedulingTaskV1]
    windows: list[SchedulingWindowV1]
    energy: Literal["veryLow", "low", "medium", "high", "veryHigh"] = "medium"
    tuning: SchedulingTuningV1 = Field(default_factory=SchedulingTuningV1)
    fixed: list[SchedulingFixedEntryV1] = Field(default_factory=list)
```

Add explicit validators for date-time normalization, clock bounds, window order, range limits, and reserved `splittable` values. Add `to_engine_request()` and `to_contract_response()` adapters. Keep the internal engine dictionary shape private to the adapter.

- [ ] **Step 4: Make `/schedule/replan` use the adapter**

Change `backend/routers_schedule.py` so the route accepts `SchedulingRequestV1`, calls `plan_schedule()` through `to_engine_request()`, and returns the canonical response model. The route must continue to accept a missing `schemaVersion` as legacy v1, while invalid scheduling fields return 422.

- [ ] **Step 5: Add canonical output fields without changing CRUD storage**

Keep `ScheduleEntryIn/Out` unchanged for `/schedule` CRUD. Convert internal `height` to `durationMinutes` only in the `/schedule/replan` response adapter. Mark fixed entries as `source: "fixed"` and generated entries as `source: "planned"`; preserve the current `height` conversion rule at this boundary.

- [ ] **Step 6: Run focused tests and the existing backend suite**

Run:

```powershell
python -m pytest backend/tests/test_scheduling_contract.py backend/tests/test_api_flow.py -q
python -m pytest backend/tests -q
```

Expected: focused tests and the full backend suite pass.

- [ ] **Step 7: Commit the Python/API adapter**

```powershell
git add backend/scheduling_contract.py backend/routers_schedule.py backend/services_scheduling.py backend/tests/test_scheduling_contract.py backend/tests/test_api_flow.py
git commit -m "feat: enforce scheduling contract at API boundary"
```

### Task 3: Add Dart canonical scheduling adapters

**Files:**
- Modify: `lib/models/models.dart`
- Create: `lib/services/scheduling/scheduling_contract.dart`
- Create: `test/scheduling_contract_test.dart`
- Modify: `test/heuristic_scheduling_engine_test.dart`

- [ ] **Step 1: Write failing Dart serialization tests**

Test that:

- `SchedulingRequest.toJson()` emits date-only `day` and `schemaVersion: "1"`;
- `PlanTask` emits UTC-`Z` normalized `due` when present, while accepting an input offset;
- fixed entries emit `durationMinutes`, not `height`, through the scheduler adapter;
- `SchedulingPlan.fromJson()` reads canonical entries and `blockedBy`/`explanationCodes`;
- invalid canonical enum/range values are rejected by the adapter instead of silently falling back.

Example:

```dart
test('request uses canonical date and version fields', () {
  final json = request.toJson();
  expect(json['schemaVersion'], '1');
  expect(json['day'], '2026-09-14');
  expect(json['fixed'], isA<List>());
});
```

- [ ] **Step 2: Run the focused Dart test and confirm red**

Run:

```powershell
flutter test test/scheduling_contract_test.dart
```

Expected: FAIL because the current serializer emits a full datetime and persistence `height` fields.

- [ ] **Step 3: Implement the Dart contract adapter**

Add `SchedulingContract` helpers for date-only serialization, canonical fixed/plan entry conversion, enum validation, legacy `height` input conversion, and issue parsing. Keep `ScheduleEntry.toJson()` unchanged for local persistence and CRUD compatibility.

- [ ] **Step 4: Extend scheduling model metadata**

Add optional `schemaVersion`, `source`, `blockedBy`, and `explanationCodes` to scheduling-specific models with safe defaults. Do not add scheduler-only fields to unrelated persisted models.

- [ ] **Step 5: Run focused and existing Dart tests**

Run:

```powershell
flutter test test/scheduling_contract_test.dart test/heuristic_scheduling_engine_test.dart
```

Expected: all focused tests pass.

- [ ] **Step 6: Commit the Dart adapter**

```powershell
git add lib/models/models.dart lib/services/scheduling/scheduling_contract.dart test/scheduling_contract_test.dart test/heuristic_scheduling_engine_test.dart
git commit -m "feat: add Dart scheduling contract adapter"
```

### Task 4: Align deterministic ordering and issue explanations

**Files:**
- Modify: `backend/services_scheduling.py`
- Modify: `lib/services/scheduling/heuristic_scheduling_engine.dart`
- Modify: `backend/tests/test_scheduling_contract.py`
- Modify: `backend/tests/test_scheduling.py`
- Modify: `test/heuristic_scheduling_engine_test.dart`
- Modify: `contracts/scheduling/v1/fixtures/basic.json`

- [ ] **Step 1: Add failing parity tests**

Use the same fixture to assert both runtimes return:

- the same entry ID order;
- the same start times and durations;
- the same issue codes and task IDs;
- the same explanation codes.

Include equal priority/due tasks so the final `id` tie-break is exercised.

- [ ] **Step 2: Run parity tests and confirm the existing implementations diverge**

Run the focused Python and Dart parity tests. Expected: FAIL on the current Python/Dart sorting difference and the absence of explanation metadata.

- [ ] **Step 3: Implement the shared ordering rule**

Use the contract ordering in both runtimes:

```text
same-day due ascending
missing due last
priority descending
durationMinutes descending
id ascending
```

Keep energy-specific behavior in placement scoring, not in the final task tie-break.

- [ ] **Step 4: Add stable explanation codes**

Emit only the documented machine codes: `deadline_proximity`, `priority`, `energy_fit`, `kept_baseline`, and `fixed_conflict`. Keep human-readable messages separate from client branching.

- [ ] **Step 5: Implement the v1 hard-constraint semantics**

Apply the same rules in both runtimes:

- process tasks only after all `dependsOn` tasks are placed;
- emit `dependency_blocked` with `blockedBy` when a dependency is missing or cannot be placed;
- do not place a task before `earliestStart`;
- when `hardDeadline` is true, reject placements whose end is after `due`;
- when `hardDeadline` is false, allow the earliest feasible fallback and emit `miss_due` when it passes `due`.

Keep `splittable != false` and unsupported `minimumChunkMinutes` values as explicit validation failures until task splitting is implemented.

- [ ] **Step 6: Run parity and regression tests**

Run:

```powershell
python -m pytest backend/tests/test_scheduling.py backend/tests/test_scheduling_contract.py -q
flutter test test/heuristic_scheduling_engine_test.dart test/scheduling_contract_test.dart
```

Expected: all tests pass and the shared fixture has identical observable results.

- [ ] **Step 7: Commit the parity behavior**

```powershell
git add backend/services_scheduling.py lib/services/scheduling/heuristic_scheduling_engine.dart backend/tests test contracts/scheduling/v1/fixtures/basic.json
git commit -m "feat: align scheduling ordering and explanations"
```

### Task 5: Update public contract documentation

**Files:**
- Modify: `docs/接口预留与服务器接口文档.md`
- Modify: `docs/后端开发守则.md`
- Modify: `docs/五人开发分工文档.md`

- [ ] **Step 1: Replace the `/schedule/replan` example with the v1 payload**

Document `schemaVersion`, date-only `day`, offset date-times, canonical `durationMinutes`, strict enums, issue codes, explanation codes, and the `height` compatibility boundary.

- [ ] **Step 2: Link the machine-readable schema and shared fixture location**

Add links to `contracts/scheduling/v1/scheduling.schema.json` and explain that CRUD `height` is not part of the scheduler contract.

- [ ] **Step 3: Record the migration and compatibility behavior**

State that missing `schemaVersion` is accepted as legacy v1, unknown scheduling fields are rejected, and the public API response is canonical duration-based.

- [ ] **Step 4: Run documentation checks and commit**

Run:

```powershell
git diff --check
```

Then commit:

```powershell
git add docs/接口预留与服务器接口文档.md docs/后端开发守则.md docs/五人开发分工文档.md
git commit -m "docs: publish scheduling contract v1"
```

### Task 6: Full verification and contract evidence

**Files:**
- Modify: `docs/superpowers/specs/2026-09-14-scheduling-contract-design.md`
- Modify: `docs/成员A-基线变更清单.md`

- [ ] **Step 1: Run the complete validation set**

```powershell
flutter analyze
flutter test -r compact
python -m pytest backend/tests -q
git diff --check
```

- [ ] **Step 2: Verify the working tree and contract commits**

```powershell
git status --short --branch
git log --oneline -6
git show --stat --oneline HEAD
```

The working tree must be clean, and the final diff must contain only the planned contract, adapter, tests, and documentation changes.

- [ ] **Step 3: Record evidence and known limitations**

Update the baseline/decision documentation with the test counts, any dependency warnings, and the explicit remaining limitation that full `SchedulerCore` decomposition is a follow-up.

- [ ] **Step 4: Commit the evidence**

```powershell
git add docs/superpowers/specs/2026-09-14-scheduling-contract-design.md docs/成员A-基线变更清单.md
git commit -m "docs: record scheduling contract verification"
```
