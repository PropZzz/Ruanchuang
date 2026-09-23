# Client Identity Isolation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Isolate every local snapshot by stable authenticated user identity, remove local password authentication, and restrict remote-to-local fallback to an explicit recoverable-error allowlist.

**Architecture:** The platform persistence adapters receive logical namespaces and encode them with unpadded base64url before building physical names. `LocalDataService` owns the active guest or authenticated namespace and performs a copy-once legacy-to-guest migration. `CompositeDataService` coordinates remote authentication with local identity activation, while data operations share one fallback predicate and logout preserves remote diagnostics after client cleanup.

**Tech Stack:** Flutter 3.38, Dart 3.10, `package:http`, `flutter_test`, existing local file/Web Storage adapters.

**Spec:** `docs/superpowers/specs/2026-09-24-client-identity-isolation-design.md`

## Global Constraints

- Keep `Screen -> AppServices -> DataService -> CompositeDataService -> Remote/Local -> ApiClient/LocalPersistence`.
- Do not modify backend schemas, routes, transactions, or databases.
- Do not modify `main_screen.dart`, `focus_page.dart`, or `smart_calendar_page.dart`.
- Do not add dependencies.
- Never derive a user namespace from contact address, display name, password, guest data, or legacy data.
- Only socket/network errors, timeouts, and HTTP 500/502/503/504 may fall back locally.
- Preserve 401/403/409/422/501, parse errors, and response-contract errors.
- Preserve the old global snapshot unchanged for rollback.
- Format only files changed by this plan.

## Review Focus

- A malicious `userId` containing slashes, backslashes, Unicode, or `..` produces only a base64url physical suffix and cannot escape the storage directory; Task 1 tests this.
- A valid guest snapshot plus an older legacy snapshot keeps the guest snapshot unchanged; Task 2 tests this.
- A malformed or ID-less successful auth response installs neither token nor local authenticated namespace; Task 3 tests this.
- A remote logout failure followed by a local switch failure still clears the token and reports the original remote failure; Task 4 tests this.
- A 501 reserved response never falls back even though it is a 5xx status; Task 4 tests both reads and writes.

---

### Task 1: Diagnose the Flutter test startup and add namespaced persistence

**Files:**
- Modify: `lib/services/local_persistence/local_persistence.dart`
- Modify: `lib/services/local_persistence/local_persistence_io.dart`
- Modify: `lib/services/local_persistence/local_persistence_web.dart`
- Create: `test/local_persistence_test.dart`

**Interfaces:**
- Produces: `encodeLocalPersistenceNamespace(String namespace) -> String`
- Produces: `LocalPersistence.exists/read/write({String namespace = legacyLocalNamespace})`
- Consumes: no new package; uses `dart:convert` only.

- [ ] **Step 1: Run bounded diagnostics before changing code**

Run PowerShell jobs with 30-second bounds for `flutter --version` and one existing service test, record whether each completes, inspect active `dart`/`flutter` processes, and stop only the diagnostic job on timeout. Expected: either a concrete tool-lock/startup cause or a reproducible bounded timeout; neither is reported as a pass.

- [ ] **Step 2: Write failing namespace tests**

Add tests whose hand-derived expectations require:

```dart
expect(encodeLocalPersistenceNamespace('user:../张三\\data'),
    'dXNlcjouLi_lvKDkuIlcZGF0YQ');
await persistence.write('guest-value', namespace: 'guest');
await persistence.write('user-value', namespace: 'user:abc');
expect(await persistence.read(namespace: 'guest'), 'guest-value');
expect(await persistence.read(namespace: 'user:abc'), 'user-value');
```

The exact base64url literal must be verified independently before committing the test. Also prove that the default namespace still addresses the legacy slot.

- [ ] **Step 3: Verify RED**

Run: `flutter test test/local_persistence_test.dart -r compact`

Expected: compile failure because namespaced methods and the encoder do not exist.

- [ ] **Step 4: Implement the minimal namespace adapter**

Use these signatures:

```dart
const legacyLocalNamespace = 'legacy';

String encodeLocalPersistenceNamespace(String namespace) =>
    base64Url.encode(utf8.encode(namespace)).replaceAll('=', '');

abstract class LocalPersistence {
  Future<bool> exists({String namespace = legacyLocalNamespace});
  Future<String?> read({String namespace = legacyLocalNamespace});
  Future<void> write(
    String content, {
    String namespace = legacyLocalNamespace,
  });
}
```

Keep the existing file/key names only for `legacy`. For every other namespace,
append the encoded suffix to a fixed application-controlled prefix. Give every
IO namespace its own primary, temporary, and backup file. Store in-memory test
values in a map keyed by logical namespace.

- [ ] **Step 5: Verify GREEN and commit**

Run: `flutter test test/local_persistence_test.dart -r compact`

Expected: all namespace tests pass.

Commit: `fix(client): add safely encoded local namespaces`

### Task 2: Isolate local data and migrate legacy data to guest once

**Files:**
- Modify: `lib/models/models.dart`
- Modify: `lib/services/data_service.dart`
- Modify: `lib/services/local_data_service.dart`
- Modify: `lib/services/mock_data_service.dart`
- Modify: `test/local_data_service_test.dart`

**Interfaces:**
- Consumes: namespaced `LocalPersistence` from Task 1.
- Produces: `UserAccount.userId`, `ClientIdentityState`, and `LocalIdentityStore.activateAuthenticatedUser`/`activateGuest`.
- Produces: schema version 6 snapshot with `legacyMigration` metadata in guest after migration.

- [ ] **Step 1: Write failing identity and isolation tests**

Add a table-driven local-service test that:

1. activates user A with `userId: 'user-a'`;
2. writes unique schedule, microtask, goal, team member, emotion, task event,
   tuning, favorite device, theme, and locale values;
3. activates user B and proves none of A's unique values is visible;
4. writes B values, switches back to A, and proves only A values return;
5. activates guest and proves neither authenticated user's unique values is
   visible;
6. reloads service instances between switches to prove persistence, not only
   in-memory filtering.

Add tests that arbitrary local passwords return false without changing
identity, logout switches to guest without deleting A or B, and a guest/legacy
identity never exposes a non-null `userId`.

- [ ] **Step 2: Write failing migration tests**

Seed only the default legacy slot with schema-5 data and an old `currentUser`.
Assert first guest load copies the data into `guest`, writes schema 6 plus:

```json
{"legacyMigration":{"sourceVersion":5,"state":"completed"}}
```

Assert the legacy bytes remain identical. Modify legacy after migration,
reload, and prove guest is not copied again. Seed both legacy and guest and
prove guest wins without overwrite. Activate a valid authenticated user and
prove migrated data is not visible there. Seed malformed legacy JSON and prove
the original parse error is exposed while both slots remain unchanged.

- [ ] **Step 3: Verify RED**

Run: `flutter test test/local_data_service_test.dart -r compact`

Expected: compile/assertion failures for missing identity APIs, shared data,
password-based local success, and absent migration metadata.

- [ ] **Step 4: Implement the identity model and namespace switching**

Add the compatible model:

```dart
enum ClientIdentityState { remoteAuthenticated, offlineCached }

class UserAccount {
  final String? userId;
  final String contactAddress;
  final String displayName;
  final ClientIdentityState identityState;
}
```

`fromJson` accepts missing `id` for old data; `toJson` writes `id` only when it
exists. Remote and local callers explicitly choose the state.

Add the narrow service seam:

```dart
abstract interface class LocalIdentityStore {
  Future<void> activateAuthenticatedUser(UserAccount user);
  Future<void> activateGuest();
}
```

`LocalDataService` implements it, validates a non-empty `userId`, derives the
logical `user:<userId>` namespace, serializes identity switches through the
existing mutation queue, clears all active in-memory collections before load,
and stores session metadata separately. Local login and registration return
false. Logout delegates to `activateGuest()` and never removes another slot.

Implement the legacy copy rules exactly as specified. Ignore legacy
`currentUser`. Never overwrite an existing guest slot and never delete or edit
the legacy slot.

- [ ] **Step 5: Verify GREEN and commit**

Run: `flutter test test/local_data_service_test.dart test/local_persistence_test.dart -r compact`

Expected: all local persistence, isolation, authentication, and migration tests pass.

Commit: `fix(client): isolate local data by stable identity`

### Task 3: Validate remote identity and clear tokens in every logout outcome

**Files:**
- Modify: `lib/services/api_client.dart`
- Modify: `lib/services/remote_data_service.dart`
- Modify: `test/remote_data_service_test.dart`

**Interfaces:**
- Consumes: `UserAccount.userId` and `ClientIdentityState` from Task 2.
- Produces: atomic auth-response validation and `RemoteDataService.continueAsGuest()` for local-only client-session clearing.

- [ ] **Step 1: Write failing auth contract tests**

For login and registration, return 200 responses with each invalid shape:
missing/blank `accessToken`, missing/non-object `user`, and missing/blank
`user.id`. Assert `RemoteDataException` and prove a following `/auth/me`
request has no Authorization header. Add a valid response test that preserves
the exact server ID and marks the account `remoteAuthenticated`.

- [ ] **Step 2: Write failing logout cleanup tests**

Use separate cases for 204 success, 401, `http.ClientException`,
`TimeoutException`, and HTTP 500/502/503/504. After each logout attempt, call
`getCurrentUser()` against a test `/auth/me` endpoint and assert it receives no
Authorization header. Assert success and 401 complete normally; network,
timeout, and 5xx rethrow their original diagnostics after cleanup.

- [ ] **Step 3: Verify RED**

Run: `flutter test test/remote_data_service_test.dart -r compact`

Expected: malformed responses currently install invalid state or throw the
wrong error, and failing logout leaves the bearer token attached.

- [ ] **Step 4: Implement strict auth parsing and finally cleanup**

Parse token and user into local variables, validate both, then install them.
Construct remote accounts with `identityState:
ClientIdentityState.remoteAuthenticated`. Implement logout as:

```dart
try {
  await _api.post('/auth/logout', null);
} on ApiException catch (error) {
  if (error.statusCode != 401) rethrow;
} finally {
  _api.setToken(null);
  _currentUser = null;
}
```

`continueAsGuest()` performs only the two cleanup assignments and does not
contact the server.

- [ ] **Step 5: Verify GREEN and commit**

Run: `flutter test test/remote_data_service_test.dart -r compact`

Expected: all remote auth and logout cases pass.

Commit: `fix(client): validate remote identity and clear logout tokens`

### Task 4: Enforce composite fallback and authentication semantics

**Files:**
- Modify: `lib/services/data_service.dart`
- Modify: `lib/services/composite_data_service.dart`
- Modify: `lib/screens/auth_dialog.dart`
- Modify: `test/composite_data_service_test.dart`
- Modify: relevant authentication widget test if compilation or guest behavior requires it.

**Interfaces:**
- Consumes: `LocalIdentityStore` and validated remote accounts.
- Produces: one fallback allowlist used by `_read`, `_writeVoid`, and `_writeValue` data operations.
- Produces: `DataService.continueAsGuest()` explicit client-state transition.

- [ ] **Step 1: Write failing read/write matrix tests**

For reads and writes, use literal tables for:

```dart
const fallbackStatuses = [500, 502, 503, 504];
const preservedStatuses = [401, 403, 409, 422, 501];
```

Also cover `SocketException`, `http.ClientException`, `TimeoutException`,
`FormatException`, `RemoteDataException`, and reserved
`RemoteUnavailableException`. Assert fallback cases call local exactly once;
preserved cases return the same error object and never call local.

- [ ] **Step 2: Write failing auth and logout orchestration tests**

Assert remote login/register 401, network, timeout, and 5xx never call local
credential methods or activate a namespace. Assert only a successful response
with non-empty `userId` calls `activateAuthenticatedUser`. Assert activation
failure clears the remote client session and reports the local failure.

For logout, assert remote is attempted first, local guest activation always
runs, and network/timeout/5xx/403 errors remain observable. Include a case where
both remote logout and local activation fail and assert the remote error remains
primary.

- [ ] **Step 3: Verify RED**

Run: `flutter test test/composite_data_service_test.dart -r compact`

Expected: 501/reserved errors currently fall back, remote login can call local
login, and recoverable logout failures are swallowed.

- [ ] **Step 4: Implement the allowlist and explicit auth flows**

Use this status predicate only:

```dart
const recoverableStatuses = <int>{500, 502, 503, 504};
```

Do not treat `RemoteUnavailableException`, parsing failures, or arbitrary
status-less `ApiException` as recoverable. Implement login/register without
`_writeValue`: call remote, fetch its validated current user, activate local,
and roll back the remote client session if activation fails.

Implement composite logout with captured error and stack trace so local guest
activation runs in `finally` and the original remote error is rethrown with its
stack. Implement `continueAsGuest()` as client-only remote cleanup plus local
guest activation. Update the existing guest button to await this explicit
method before reporting success.

- [ ] **Step 5: Verify GREEN and commit**

Run: `flutter test test/composite_data_service_test.dart test/remote_data_service_test.dart test/local_data_service_test.dart test/local_persistence_test.dart -r compact`

Expected: all identity, fallback, migration, and logout regressions pass.

Commit: `fix(client): harden auth and fallback orchestration`

### Task 5: Format, verify, review, and prepare the PR

**Files:**
- Modify only files already changed by Tasks 1-4 if formatting or verified review fixes require it.

**Interfaces:**
- Consumes: all prior task outputs.
- Produces: reviewable branch and truthful verification evidence.

- [ ] **Step 1: Format only changed Dart files**

Run `dart format` with the explicit changed Dart file list from
`git diff --name-only origin/main -- '*.dart'`. Do not format the repository.

- [ ] **Step 2: Run direct verification**

Run and record exact exits:

```text
flutter test test/local_persistence_test.dart test/local_data_service_test.dart test/remote_data_service_test.dart test/composite_data_service_test.dart -r compact
flutter analyze
flutter test -r compact
python -m pytest backend/tests -q
git diff --check
```

Use bounded diagnostics again if Flutter produces no output. A timeout,
environment denial, or missing dependency is recorded as blocked, never pass.

- [ ] **Step 3: Audit scope and secrets**

Confirm `git status --short`, `git diff --stat origin/main`, and
`git diff --name-only origin/main` include only this task. Search the diff for
the supplied server address/password, bearer tokens, database files, build
artifacts, and unrelated formatting. None may be committed.

- [ ] **Step 4: Perform the final branch review**

Review every diff against the spec, error matrix, migration invariants, and
test mutation cases. Because repository instructions prohibit unrequested
subagent delegation, perform and record a self-review instead of dispatching a
reviewer. Any Critical or Important finding receives a new failing regression
test before its fix.

- [ ] **Step 5: Push and create the unmerged PR**

Push `codex/member-d-client-identity-isolation` to `origin` and create a PR
against `main` titled `fix(client): isolate local identities and harden fallback semantics`.
The description includes problem/impact, identity and namespace model, legacy
strategy, fallback matrix, logout behavior, changed files, exact verification
results, limitations, rollback, and B/C/E handoffs. Do not merge it.
