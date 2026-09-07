# 服务器 Web 部署与预留接口完善 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the SQLite-backed server interfaces usable for the app's real data workflows, publish the Flutter Web build at `http://8.133.250.216`, and preserve truthful 501 boundaries for external capabilities.

**Architecture:** Keep FastAPI routers thin and put validation/transactions in schemas, services, and repositories. Add a rescue snapshot table and a small sync change log; Nginx serves the Flutter build on port 80 and proxies API requests to the systemd FastAPI service on localhost port 8000.

**Tech Stack:** Python 3.12, FastAPI, Pydantic 2, SQLite, pytest/TestClient, Flutter 3.38/Dart 3.10, Nginx, systemd.

---

### Task 1: Add persistent platform state and token/profile operations

**Files:**
- Modify: `backend/auth.py`
- Modify: `backend/repositories.py`
- Modify: `backend/schemas.py`
- Modify: `backend/routers_auth.py`
- Create: `backend/routers_platform.py`
- Test: `backend/tests/test_platform_api.py`

- [ ] **Step 1: Write failing tests for token revocation, profile update, version, time, and diagnostics**

  Add a temporary user helper and assert: `POST /auth/logout` makes the bearer token return 401, `PUT /auth/profile` changes only the authenticated user's display name, `GET /version` returns `apiVersion` and `clientCompatibility`, `GET /server/time` returns an ISO timestamp and integer epoch milliseconds, and diagnostics counts are scoped to the user.

- [ ] **Step 2: Run the focused tests and verify they fail**

  Run `F:\Tools\Python310\python.exe -m pytest backend/tests/test_platform_api.py -q`.

- [ ] **Step 3: Implement the minimum platform contract**

  Add `revoke_token()` and make `resolve_token()` ignore revoked tokens. Add repository functions `update_user_profile()` and `user_diagnostics()` using the existing user filter. Add schemas `ProfileUpdate`, `VersionOut`, `ServerTimeOut`, and `DiagnosticsOut`. Register `routers_platform` and move the implemented auth routes out of the generated reserved handler. Keep password reset routes at 501 with `RESERVED_ENDPOINT`.

- [ ] **Step 4: Run focused tests and the existing auth tests**

  Run `F:\Tools\Python310\python.exe -m pytest backend/tests/test_platform_api.py backend/tests/test_api_flow.py -q` and expect zero failures.

- [ ] **Step 5: Commit the platform slice**

  Run `git add backend/auth.py backend/repositories.py backend/schemas.py backend/routers_auth.py backend/routers_platform.py backend/tests/test_platform_api.py && git commit -m "完善服务器诊断与账号接口"`.

### Task 2: Implement ICS, schedule batch/conflicts, and rescue transactions

**Files:**
- Modify: `backend/repositories.py`
- Modify: `backend/schemas.py`
- Modify: `backend/routers_schedule.py`
- Create: `backend/services_ics.py`
- Create: `backend/services_rescue.py`
- Create: `backend/tests/test_schedule_extensions.py`

- [ ] **Step 1: Write failing tests for batch atomicity, conflicts, ICS round-trip, rescue apply, undo, and baseline conflict**

  Use `TestClient(create_app(tmp_path / "schedule.sqlite3"))`. Register one user, post two schedule entries through `/schedule/batch`, assert both are returned, submit an invalid second item and assert 422 with no new row, assert overlapping entries appear in `/schedule/conflicts`, export an ICS calendar and import it into a fresh test database, assert three rescue strategies are returned, apply one option, assert the schedule and `rescue_accept:<strategy>` event are written, undo it, assert the original schedule and `rescue_undo:<strategy>` event are restored, and submit a stale `baselineHash` to assert 409.

- [ ] **Step 2: Run the focused tests and verify they fail**

  Run `F:\Tools\Python310\python.exe -m pytest backend/tests/test_schedule_extensions.py -q`.

- [ ] **Step 3: Implement transaction helpers and schemas**

  Add `ScheduleBatchRequest`, `ScheduleConflictOut`, `RescueOptionsRequest`, `RescueOptionOut`, `RescueApplyRequest`, `RescueUndoRequest`, and `RescueSnapshotOut`. Add repository functions that reuse one connection for batch upserts, compute a deterministic SHA-256 over the user's ordered schedule JSON, persist `rescue_snapshots` in `init_db`, and apply/undo schedule plus task event in one transaction. A snapshot must store `before` and `after` JSON, `strategy`, `baselineHash`, and status.

- [ ] **Step 4: Implement ICS and rescue services**

  Add a dependency-free ICS parser that unfolds lines, reads `SUMMARY`, `DTSTART`, `DTEND`/`DURATION`, and `CATEGORIES`, rejects malformed events with 422, and emits the existing schedule JSON shape. Export `VEVENT` rows with UTC-free local date/time fields and escaped text. Build rescue options by calling `plan_schedule()` three times with the same strategy semantics as `ScheduleRescueService`; report `movedEntryCount`, `recoveryMinutes`, `affectedEntries`, `plannedEntries`, and issues.

- [ ] **Step 5: Add the routes and preserve unsupported handlers**

  Add `POST /schedule/import-ics`, `GET /schedule/export-ics`, `GET /schedule/conflicts`, `POST /schedule/batch`, `POST /schedule/rescue/options`, `POST /schedule/rescue/apply`, `POST /schedule/rescue/undo`, and `GET /schedule/rescue/history`. Remove only these paths from `RESERVED_ENDPOINTS`; keep all external-capability routes unchanged at 501.

- [ ] **Step 6: Run schedule tests and all backend tests**

  Run `F:\Tools\Python310\python.exe -m pytest backend/tests/test_schedule_extensions.py backend/tests -q` and expect all tests to pass.

- [ ] **Step 7: Commit the schedule slice**

  Run `git add backend/repositories.py backend/schemas.py backend/routers_schedule.py backend/services_ics.py backend/services_rescue.py backend/routers_reserved.py backend/tests/test_schedule_extensions.py && git commit -m "完善日程批量与救援接口"`.

### Task 3: Implement microtask, goal, and team reserved workflows

**Files:**
- Modify: `backend/repositories.py`
- Modify: `backend/schemas.py`
- Modify: `backend/routers_microtasks.py`
- Modify: `backend/routers_goals.py`
- Modify: `backend/routers_team.py`
- Create: `backend/services_team.py`
- Create: `backend/tests/test_workflow_extensions.py`
- Modify: `lib/services/remote_data_service.dart`
- Test: `test/remote_data_service_test.dart`

- [ ] **Step 1: Write failing tests for batch microtasks, goal next task, team windows, meeting booking, and remote logout/meeting calls**

  Assert batch completion changes only the authenticated user's tasks, batch scheduling creates schedule rows linked to microtask IDs, import accepts newline-delimited task text, goal scheduling selects the first unfinished task whose dependencies are complete, team conflict detection finds overlapping member busy entries, golden-window recommendation returns only windows free for all selected members, and booking creates a schedule entry for the owner. Add a Dart HTTP fake asserting `RemoteDataService.logout()` calls `/auth/logout` before clearing its token and `bookTeamMeeting()` posts `/team/book-meeting`.

- [ ] **Step 2: Run focused tests and verify they fail**

  Run `F:\Tools\Python310\python.exe -m pytest backend/tests/test_workflow_extensions.py -q` and `flutter test test/remote_data_service_test.dart -r compact`.

- [ ] **Step 3: Implement repository and service operations**

  Add transaction functions for microtask completion/scheduling and goal dependency selection. Parse import text as one non-empty task per line with optional `#tag` suffix. Add a team interval service that converts schedule `height` to minutes, intersects free windows, and returns explicit conflict objects. Book meetings by validating member IDs, checking conflicts, then inserting one owner schedule entry in the same transaction.

- [ ] **Step 4: Implement routes and remote service calls**

  Add `POST /microtasks/batch-complete`, `POST /microtasks/batch-schedule`, `POST /microtasks/import`, `POST /goals/{goal_id}/schedule-next`, `POST /team/conflicts`, `POST /team/golden-windows`, and `POST /team/book-meeting`. Update `RemoteDataService` to call implemented routes while retaining `_unavailable()` for device, AI, integration, file, notification, theme, and locale capabilities.

- [ ] **Step 5: Run focused, full backend, and Flutter tests**

  Run `F:\Tools\Python310\python.exe -m pytest backend/tests -q`, `flutter test test/remote_data_service_test.dart -r compact`, and `flutter analyze`.

- [ ] **Step 6: Commit the workflow slice**

  Run `git add backend lib/services/remote_data_service.dart test/remote_data_service_test.dart && git commit -m "完善微任务目标与团队接口"`.

### Task 4: Add honest sync endpoints and lock the 501 boundary

**Files:**
- Modify: `backend/repositories.py`
- Modify: `backend/schemas.py`
- Modify: `backend/routers_reserved.py`
- Create: `backend/routers_sync.py`
- Create: `backend/tests/test_sync_and_reserved_boundary.py`

- [ ] **Step 1: Write failing tests for sync cursor/status and unsupported routes**

  Assert `/sync/status` reports a cursor and counts, `/sync/pull` returns only the authenticated user's changes after a cursor, `/sync/push` applies valid schedule/microtask changes atomically and reports conflicts, and representative AI/device/integration/file/notification routes still return `501` with `detail.code == "RESERVED_ENDPOINT"`.

- [ ] **Step 2: Implement the sync change log**

  Add an idempotent `sync_changes` table with integer cursor, user ID, entity type, entity ID, operation, JSON payload, and timestamp. Record changes from the newly added batch/workflow routes and existing schedule/microtask/event writes without changing existing response shapes. Implement cursor validation, per-user pull, atomic push, and explicit conflict records.

- [ ] **Step 3: Register sync routes and update reserved tests**

  Register `routers_sync` from `backend/main.py`, remove only `/sync/pull`, `/sync/push`, and `/sync/status` from the reserved tuple, and update the old reserved test list to cover the remaining unsupported paths.

- [ ] **Step 4: Run the complete backend suite**

  Run `F:\Tools\Python310\python.exe -m pytest backend/tests -q`; expected result is zero failures with only the existing Starlette/httpx deprecation warnings.

- [ ] **Step 5: Commit the sync slice**

  Run `git add backend && git commit -m "增加基础离线同步接口"`.

### Task 5: Build the Flutter Web artifact and prepare the server release

**Files:**
- Create: `deploy/nginx-ruanchuang.conf`
- Create: `deploy/ruanchuang-web.service`
- Modify: `run_web_preview.bat` only if its checks need a documented public-base-url option
- Test: generated `build/web` artifact and HTTP smoke checks

- [ ] **Step 1: Run the full local verification before building**

  Run `F:\Tools\Python310\python.exe -m pytest backend/tests -q`, `flutter analyze`, and `flutter test -r compact`.

- [ ] **Step 2: Build Web with the server base URL**

  Run `flutter pub get` followed by `flutter build web --release --no-wasm-dry-run --dart-define=API_BASE_URL=http://8.133.250.216`. Verify `build/web/index.html`, `flutter_bootstrap.js`, `main.dart.js`, and `assets/` exist, and search `main.dart.js` for the compiled base URL.

- [ ] **Step 3: Define Nginx and static service contracts**

  Configure Nginx root `/opt/ruanchuang/web/current`, `try_files` fallback to `index.html`, explicit proxy locations for API prefixes, `X-Forwarded-*` headers, and a `/health` proxy. Add a `ruanchuang-web.service` or Nginx-managed static root with an atomic `current` symlink; never place the SQLite file under the web root.

- [ ] **Step 4: Commit deployment artifacts**

  Run `git add deploy run_web_preview.bat && git commit -m "增加 Web 发布配置"`.

### Task 6: Deploy the new release and verify from the public IP

**Files/servers:**
- Local release archive from `backend/`, `build/web/`, and `deploy/`
- Remote: `/opt/ruanchuang/releases/<timestamp>`, `/opt/ruanchuang/web/releases/<timestamp>`, `/etc/systemd/system/ruanchuang.service`, `/etc/nginx/sites-available/ruanchuang.conf`

- [ ] **Step 1: Capture local hashes and back up remote state**

  Create one archive with backend source, Web assets, and deployment config; record SHA-256. On the server, archive `/opt/ruanchuang/current`, `/opt/ruanchuang/web/current`, and `/opt/ruanchuang/data` before mutation.

- [ ] **Step 2: Install Nginx and publish atomic release**

  Install Nginx if absent, extract the release into timestamped directories, keep the existing database file, install the systemd/Nginx configs, run `nginx -t`, reload Nginx, restart FastAPI, and switch both `current` symlinks only after validation.

- [ ] **Step 3: Verify server-local behavior**

  Check `systemctl is-active/is-enabled ruanchuang.service`, `systemctl is-active nginx`, `curl http://127.0.0.1/`, `curl http://127.0.0.1/health`, `curl http://127.0.0.1/auth/...` for the expected auth status, SQLite `PRAGMA integrity_check`, and all relevant listeners. If any check fails, restore the prior symlinks and restart the prior release.

- [ ] **Step 4: Verify public behavior and report the security-group gate**

  From the local machine run `curl.exe -i --max-time 10 http://8.133.250.216/` and `curl.exe -i --max-time 10 http://8.133.250.216/health`. Report the actual HTTP code/body. If TCP 80 is blocked by the Alibaba Cloud security group, report the server-local success and the exact inbound rule required instead of claiming the page is reachable.

- [ ] **Step 5: Record deployment evidence and final status**

  Record release paths, hashes, service states, database integrity, local/public HTTP results, and rollback path. Keep SSH credentials out of logs and repository files.
