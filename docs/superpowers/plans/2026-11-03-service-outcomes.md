# Service outcomes implementation plan

> **For agentic workers:** Use superpowers:executing-plans inline. Track each test-first slice below; no product pages in this PR.

**Goal:** Return honest per-operation results and preserve draft snapshots while enforcing a shared fallback whitelist.

**Architecture:** Existing DataService methods retain their throwing API. Composite exposes typed read/write results and uses the same implementation for legacy calls. A small ServiceOperations facade handles direct Remote/Local services and draft copying; results are immutable and scoped to each Future, never a global last-status.

**Tech Stack:** Existing Dart/Flutter/http/flutter_test; no new dependencies.

**Spec:** `docs/superpowers/specs/2026-11-03-interactive-cards-design.md` on approved audit commit f562a29. This branch starts from latest main 28c4bff and does not stack on the audit branch or PR #3.

## Global constraints

- Network unavailable, timeout, HTTP 500/502/503/504 only; 501, all 4xx, parsing and contract errors never fall back.
- No backend/API contract changes, page edits, outbox, identity migration or new dependencies.
- Existing favorite-device preference is explicitly local-only, not an unimplemented-remote fallback.
- No automatic PR merge; stop after this PR.

## Review focus

- Concurrent Futures with different data sources must not overwrite each other's result.
- Remote commit followed by cache failure must remain success with a warning, not invite retry.
- Failed or mutating save callbacks must not modify the retained draft snapshot.
- A transport/parse failure after a write can mean unknown remote commit; never claim definitely unsaved.
- Explicit guest/local preference must differ from offline fallback and from Reserved.

## Task 1: Whitelist and unimplemented capability

Files: composite_data_service.dart, remote_data_service.dart, composite_data_service_test.dart.

- [ ] Add public read/write rejection tests for 501/505 and unimplemented capability. Run RED.
- [ ] Restrict fallback to network/timeouts and {500,502,503,504}; distinguish RemoteUnavailable (transport) from RemoteNotImplemented (capability). Route favorite-device preference explicitly locally. Run GREEN.
- [ ] Cover every 4xx, JSON/contract failures and permitted transport/HTTP cases using real HTTP and local persistence.

## Task 2: Per-operation outcomes and draft retention

Create service_result.dart, service_operations.dart, service_operations_test.dart; modify Composite helpers.

Interfaces: ServiceResult<T> = ServiceSuccess<T> or ServiceFailure<T>; ServiceSource remote/local; failure kind, original cause/stack, commit state; success fallback cause/cache warning. Composite readResult<T>(Future<T> Function(DataService)) and writeResult(Future<void> Function(DataService)). ServiceOperations.read/write dispatch those for Composite and capture direct-service outcomes. saveDraft<D> requires a copy function, gives the writer a separate copy and returns a retained draft with ServiceResult<void>.

- [ ] Write typed success/source, conflict/Reserved/parsing and permitted-fallback tests; run RED, implement minimal value objects/classification and shared Composite execution, run GREEN.
- [ ] Write cache-warning, concurrent result, mutable-draft failure/ retry/local readback tests; run RED, implement facade/copy boundary, run GREEN.
- [ ] Keep old throwing methods and original errors intact; logout is a session command, never an offline-success fallback. Test network/5xx logout diagnostics.

## Task 3: Verify, review, deliver

- [ ] Only format changed Dart files.
- [ ] Run related tests, flutter analyze, flutter test -r compact, backend pytest, git diff --check. Record command/status and any bounded timeout honestly.
- [ ] Fresh whole-branch review; fix material findings with regression tests.
- [ ] Commit small changes, push codex/cards-service-outcomes, create unmerged main-base PR with outcomes matrix, tests, limits, rollback and next-card handoff.

## Execution record

- Baseline: `flutter test --no-pub test/composite_data_service_test.dart -r expanded`: exit 0, 23 passed. Initial loading finished normally; no persistent silent hang reproduced.
- PR #3 is OPEN at 276fc7c. It overlaps Composite's whitelist/logout but includes separate identity/storage/UI changes. This PR deliberately implements only current service outcomes against main, with no implicit stack or merge.
- User already authorized inline TDD implementation and push/PR; no additional plan approval gate.
