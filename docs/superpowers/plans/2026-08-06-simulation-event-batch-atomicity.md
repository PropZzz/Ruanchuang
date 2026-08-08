# Simulation Event Batch Atomicity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent a failed week simulation from leaving partial or duplicate task events in local or remote review data.

**Architecture:** Add an idempotent `upsertTaskEvents` batch operation to `DataService`. Local storage will build the complete next event list and restore its in-memory snapshot on persistence failure; FastAPI will upsert the whole request inside one SQLite transaction. `ReviewPage` will create all simulation events first and persist them through that single operation before generating a report.

**Tech Stack:** Flutter/Dart, Material 3, LocalDataService, CompositeDataService, FastAPI, SQLite, Flutter widget tests, pytest.

---

### Task 1: Batch Event Contract and Local Atomicity

**Files:**
- Modify: `lib/services/data_service.dart`
- Modify: `lib/services/local_data_service.dart`
- Modify: `lib/services/mock_data_service.dart`
- Test: `test/local_data_service_test.dart`

- [ ] Add `Future<void> upsertTaskEvents(List<TaskEvent> events)` to `DataService`.
- [ ] Add a failing local-service test using a persistence fake whose `write` throws. It must call `upsertTaskEvents` with several event IDs and assert that `getTaskEvents` returns none of them after the failure.
- [ ] Implement local batch upsert by copying `_events`, replacing by stable `TaskEvent.id`, assigning the complete candidate list once, saving once, and restoring the copy when save throws.
- [ ] Make `logTaskEvent` use the same stable-ID upsert semantics so retries cannot append duplicate local events.
- [ ] Implement the same stable-ID replacement behavior in `MockDataService`.
- [ ] Run `flutter test test/local_data_service_test.dart -r compact`.

### Task 2: Remote Batch Transaction

**Files:**
- Modify: `lib/services/remote_data_service.dart`
- Modify: `lib/services/composite_data_service.dart`
- Modify: `backend/repositories.py`
- Modify: `backend/routers_events.py`
- Test: `backend/tests/test_events.py`

- [ ] Add a failing API test posting two task events to `POST /events/batch`, reposting an updated event with the same ID, and querying exactly two records with the updated value.
- [ ] Add repository batch upsert using one SQLite connection and one commit after all `INSERT ... ON CONFLICT(id) DO UPDATE` statements succeed.
- [ ] Add the authenticated batch route and have `RemoteDataService` call it with JSON event maps.
- [ ] Delegate `CompositeDataService.upsertTaskEvents` through its existing remote-then-local write policy.
- [ ] Run `F:\Tools\Python310\python.exe -m pytest backend\tests\test_events.py -q`.

### Task 2b: Batch Ownership and Safe Fallback

**Files:**
- Modify: `backend/repositories.py`
- Modify: `backend/routers_events.py`
- Modify: `backend/tests/test_events.py`
- Modify: `lib/services/composite_data_service.dart`

- [ ] Reject blank or repeated event IDs in one batch before writing any record.
- [ ] Reject an event ID owned by another user with an explicit conflict response; never update another user's row or return an empty response that becomes a server error.
- [ ] Preserve local-first offline behavior only for remote-unavailable failures. Re-throw remote HTTP 4xx authentication, authorization, validation, and conflict failures instead of running a permissive local fallback.
- [ ] Add authenticated two-user collision and duplicate-ID transaction tests.
- [ ] Run `F:\Tools\Python310\python.exe -m pytest backend\tests\test_events.py -q` and focused Flutter analysis/tests.

### Task 2c: Composite Commit Semantics

**Files:**
- Modify: `lib/services/composite_data_service.dart`
- Modify: `lib/services/remote_data_service.dart`
- Test: `test/composite_data_service_test.dart`

- [ ] Treat a completed remote write as the successful result. Attempt local cache synchronization afterward, but do not report failure or invite a duplicate retry when that cache write fails.
- [ ] Split remote-unavailable errors from remote response-contract errors. Only the unavailable subtype may use local fallback.
- [ ] Add deterministic spy tests for remote-success/local-failure, local fallback after remote unavailable, and rethrow after remote contract failure.
- [ ] Run `flutter test test/composite_data_service_test.dart -r compact` and `flutter analyze`.

### Task 1b: Local Service Transaction Boundary

**Files:**
- Modify: `lib/services/local_data_service.dart`
- Test: `test/local_data_service_test.dart`

- [ ] Add one service-wide mutation queue. Every public operation that changes persisted state must run inside the queue, including report tuning updates and authentication state updates.
- [ ] Capture an immutable copy of a batch event list before queueing it, so a caller cannot mutate a queued batch.
- [ ] Make `_ensureLoaded` single-flight. Set `_loaded` only after a required migration save succeeds, and clear the in-flight future after both success and failure so failed migrations can retry.
- [ ] Add tests for an event batch racing with a goal write, caller mutation of a queued input list, and a failed migration retry.
- [ ] Run `flutter test test/local_data_service_test.dart -r compact`.

### Task 1c: Local Failure Rollback and Ownership

**Files:**
- Modify: `lib/services/local_data_service.dart`
- Modify: `test/local_data_service_test.dart`

- [ ] Capture a deep snapshot before every queued local mutation and restore it when persistence fails, so failed writes cannot be revived by a later save.
- [ ] Treat parse failures as load failures: restore the pre-load state, do not save partial migration results, and allow the next call to retry.
- [ ] Repair blank incoming task-event IDs before batch candidate construction. Use collision-safe ID allocation for all migrated entity IDs.
- [ ] Copy mutable nested goal and tuning data at service ingress and egress, derive `UserProfile` from the persisted signed-in account, and bound synchronization waits in tests.
- [ ] Add regression tests for a failed ordinary mutation rollback, malformed-data load preservation, blank batch IDs, and successful user-profile projection.
- [ ] Run `flutter test test/local_data_service_test.dart -r compact`.

### Task 3: Simulation Integration and Recovery Tests

**Files:**
- Modify: `lib/screens/review_page.dart`
- Modify: `test/review_page_rescue_history_test.dart`

- [ ] Add a failing widget test whose data-service fake fails `upsertTaskEvents`; assert the simulated report is not generated, controls recover, the localized simulation error is shown once, and querying the local service finds no simulation events.
- [ ] Build the simulated event list before writing, then call `upsertTaskEvents` once instead of calling `logTaskEvent` in the nested loops.
- [ ] Keep the existing `try/catch/finally` feedback and loading restoration behavior, without adding duplicate error feedback when report generation itself fails.
- [ ] Run `flutter test test/review_page_rescue_history_test.dart -r compact` and `flutter analyze`.

### Task 4: Verification

**Files:**
- Test: Flutter and backend suites

- [ ] Run `flutter analyze`.
- [ ] Run `flutter test -r compact`.
- [ ] Run `F:\Tools\Python310\python.exe -m pytest backend\tests -q`.
- [ ] Request specification and code-quality reviews before declaring the task complete.
