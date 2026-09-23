# Client Identity Isolation and Fallback Semantics Design

## Goal

Prevent local authentication bypass and cross-user data exposure while keeping
the existing `Screen -> AppServices -> DataService -> CompositeDataService ->
Remote/Local -> ApiClient/LocalPersistence` call chain. Remote failures may use
local data only for explicitly recoverable transport conditions.

## Scope

This change is limited to the Flutter client service layer, directly related
models, the existing guest action in `auth_dialog.dart`, and regression tests.
It does not add an outbox, synchronization protocol, conflict resolver,
production password store, server transaction, database migration, or main-path
screen redesign.

No new dependency is required. Namespace encoding uses Dart's built-in UTF-8
and unpadded base64url encoding.

## Identity model

`UserAccount` keeps the server's stable `id` as an optional `userId` field so
old serialized objects without an ID still decode. It also carries a client
identity state that distinguishes a server-authenticated result from a cached
offline identity. A guest has no `UserAccount` and never receives a fabricated
server `userId`.

Remote login and registration responses are accepted only when all of the
following are valid:

- the response is an object;
- `accessToken` is a non-empty string;
- `user` is an object;
- `user.id` is a non-empty string;
- the remaining user fields satisfy the existing model contract.

The token and current remote user are installed only after validation. Local
`login` and `registerAccount` never authenticate credentials and always return
false. `CompositeDataService` does not apply ordinary data fallback to login or
registration: only a successful remote result with a valid `userId` may switch
the local service to an authenticated namespace.

The existing guest action explicitly calls `continueAsGuest()`. This clears the
client-side remote identity without a network request and switches local data
to the guest namespace.

## Local storage namespaces

`LocalPersistence` accepts a logical namespace for `exists`, `read`, and
`write`. Callers pass logical names; platform adapters encode every non-legacy
logical name as:

```text
base64url(utf8(namespace)), with trailing '=' padding removed
```

The raw `userId` is therefore never inserted into a file path or Web Storage
key. IO and Web adapters use the same stable encoding rule.

The logical namespaces are:

- `legacy`: the pre-change global file/key;
- `guest`: unauthenticated and explicitly selected guest data;
- `session`: the active client identity descriptor;
- `user:<userId>`: an authenticated user's data, encoded by the adapter before
  it becomes a physical file or storage key.

`LocalDataService` derives `user:<userId>` only after receiving a validated
remote `UserAccount`. It never derives an authenticated namespace from contact
address, display name, password, legacy data, or guest state.

Schedules, microtasks, goals, team calendars, emotion check-ins, task events,
scheduling tuning, favorite device, theme, and locale all live inside the
active data namespace. The profile view is derived from the active identity.
Switching identities unloads the old in-memory snapshot before loading the new
one. Logout changes the session to guest but does not delete any namespace.

## Legacy compatibility

The old global snapshot has unknown ownership. It is never assigned to an
authenticated user.

On the first guest load:

1. If a guest snapshot already exists, use it and do not inspect or copy the
   legacy snapshot.
2. Otherwise, read the legacy snapshot.
3. If legacy data exists and is valid, migrate it to the guest namespace with
   the new schema version and a `legacyMigration` marker containing the source
   version and completion state.
4. Leave the legacy file/key unchanged for rollback.
5. Future starts see the guest snapshot and do not copy again.

This is idempotent, preserves rollback data, and never overwrites guest data.
Malformed legacy data remains untouched and its parse error is exposed.
Legacy `currentUser` data is ignored because it lacks a trustworthy server ID.

## Fallback and error matrix

Both read and write paths use one allowlist:

| Remote result | Local fallback | Observable behavior |
| --- | --- | --- |
| Socket/network unreachable | Yes | Use local operation |
| Timeout | Yes | Use local operation |
| HTTP 500 | Yes | Use local operation |
| HTTP 502 | Yes | Use local operation |
| HTTP 503 | Yes | Use local operation |
| HTTP 504 | Yes | Use local operation |
| HTTP 401/403/409/422 | No | Rethrow original error |
| HTTP 501 | No | Rethrow original error |
| Other HTTP status | No | Rethrow original error |
| JSON parse failure | No | Rethrow original error |
| Response contract failure | No | Rethrow original error |
| Unimplemented/reserved remote capability | No | Rethrow original error |

Authentication does not use this data fallback matrix. A transport failure
during login or registration remains a failed remote authentication attempt;
it never creates a local authenticated session.

## Logout semantics

`RemoteDataService.logout()` calls the server and clears the `ApiClient` token
and cached remote user in `finally`. A 401 is treated as already logged out.
Network, timeout, 5xx, and other actionable errors are rethrown after cleanup.

`CompositeDataService.logout()` always invokes the remote logout first, then
switches local state to guest in `finally`. It preserves the original remote
exception, including recoverable transport and 5xx failures; generic write
fallback must not swallow logout diagnostics. If local guest switching also
fails, the remote failure remains primary and the local failure is not reported
as a false successful logout.

## Testing strategy

Tests are written and observed failing before production changes.

- Persistence tests verify stable safe encoding, independent physical storage,
  and backup behavior.
- Local service tests populate user A, user B, and guest across every stored
  data category; switch identities; reload; and prove no cross-visibility.
- Migration tests verify copy-once behavior, an explicit version marker,
  rollback preservation, no overwrite of guest data, and no assignment to a
  later authenticated user.
- Authentication tests verify arbitrary passwords cannot authenticate locally,
  remote failures never become local success, malformed auth responses install
  neither token nor identity, and only valid remote `userId` values activate a
  user namespace.
- Composite tests cover the read and write matrix for network, timeout,
  500/502/503/504, 401/403/409/422/501, parse errors, and contract errors.
- Logout tests cover success, 401, network exception, timeout, and 5xx; every
  case proves the next request carries no token and the cached user is cleared.

## Rollback

Reverting the client commits restores the old service behavior. The original
legacy file/key is retained unchanged, so an old build can still read it.
New namespaced files/keys are additive and need not be deleted during rollback.

## Follow-up ownership

- Member B: align server authentication/session and future synchronization
  contracts; no server change is part of this PR.
- Member C: consume the explicit cached-offline identity state in UI if a
  visible offline identity indicator is required.
- Member E: run full regression, device/browser checks, and release evidence.
