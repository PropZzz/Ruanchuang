# BattleMan Gap Workflow

## Goal
Turn the remaining README plan into a staged, parallelizable implementation path that keeps the app runnable after each merge.

## Skills To Use
- `codex-agent-orchestration` for splitting work into disjoint agent scopes and merging once.
- `product-plan-to-backlog` for turning README sections into epics, P0/P1 items, and acceptance criteria.
- `flutter-data-persistence` for model, storage, serialization, migration, and offline consistency work.
- `integration-mcp-ics-reminder` for MCP ingest, ICS import/export, and reminder flow.
- `flutter-ui-polish` for multi-view calendar, responsive dashboards, and empty/loading states.
- `flutter-test-qa` for analyzer-driven checks, smoke tests, and regression coverage.

## Execution Order
1. Keep `flutter analyze --no-fatal-infos` and `flutter run -d chrome` green as the baseline.
2. Split README into epics and mark each as P0, P1, or future.
3. Run 3 to 5 parallel workstreams with no file overlap.
4. Merge one workstream at a time and verify after each merge.
5. Stop only when the current epic has tests and a smoke path.

## Parallel Workstreams

### A. Calendar And Data
Scope:
- `lib/screens/smart_calendar_page.dart`
- `lib/services/local_data_service.dart`
- `lib/services/ics/ics_codec.dart`
- `lib/services/ics/ics_bridge.dart`
- `lib/services/reminders/reminder_service.dart`

Targets:
- day / week / month / Gantt views
- visible field customization
- import/export for Excel and Outlook-like formats
- real sync or sync-ready data contracts
- reminder persistence and idempotent rescheduling

Acceptance:
- can open each view without errors
- schedule entries round-trip through storage and export/import
- reminders survive reload and day reschedule

### B. Goals Review Emotion
Scope:
- `lib/screens/goals_page.dart`
- `lib/screens/review_page.dart`
- `lib/screens/emotion_page.dart`
- `lib/services/emotion/emotion_policy.dart`
- related model files if needed

Targets:
- goal trees and dependency edges
- automatic task breakdown
- daily and monthly review output
- better bottleneck attribution
- longer-lived efficiency profile updates
- richer emotion inputs and adaptive scheduling

Acceptance:
- goal create/edit/schedule flows stay stable
- review output changes when task events change
- emotion changes influence task shaping predictably

### C. Team And Integrations
Scope:
- `lib/screens/team_page.dart`
- `lib/screens/integrations_page.dart`
- `lib/services/mcp/mcp_ingest.dart`
- `lib/services/team_collab/heuristic_team_collab_engine.dart`
- `lib/services/remote_data_service.dart` if it becomes relevant

Targets:
- real MCP ingestion paths
- office app and email-like sources
- team permission editing
- real availability sharing and conflict resolution
- golden-window booking as a reusable sync primitive

Acceptance:
- pasted external text imports deterministically
- team windows and conflicts stay stable after edits
- permissions are visible and editable, not only displayed

### D. Mobile And Hardware
Scope:
- `lib/screens/profile_page.dart`
- `lib/screens/bluetooth_page.dart`
- device-specific service files

Targets:
- phone / desktop / web / wearable-ready UX splits
- bluetooth/device entry points that are safe on web
- offline-first behaviors where feasible
- cross-device handoff design

Acceptance:
- web launch does not crash on mobile-only code paths
- device pages degrade gracefully when hardware is unavailable

### E. UI And QA
Scope:
- `lib/screens/main_screen.dart`
- shared widgets and page shells
- `test/*`

Targets:
- better responsive hierarchy
- clearer empty/loading/error states
- smoke tests for the main flows
- analyzer cleanup for startup blockers

Acceptance:
- `flutter analyze` stays clean of errors
- `flutter run -d chrome` reaches the app shell
- smoke tests cover launch + one main action per epic

## P0 First
- local schedule CRUD
- smart calendar planning
- reminders
- ICS import/export
- MCP paste import
- goal scheduling
- microtask batch operations
- team golden-window booking
- review report generation
- emotion check-in and adaptive rules

## P1 Next
- multi-view calendar
- custom fields and permissions editing
- richer review analytics
- longer-term efficiency profiles
- better mobile/web separation
- more realistic external integrations

## Future
- Transformer + LSTM replacement behind the current scheduling interface
- BERT / CNN / multimodal emotion models
- real wearable inputs
- MCP server federation
- FastAPI / Gin / Consul / TLS / Merkle Tree backend stack
- RLHF-style personalization loop

## Suggested Codex Prompts
- `codex-agent-orchestration`: split A/B/C/D work into separate agents and merge once.
- `flutter-data-persistence`: harden storage and serialization first.
- `integration-mcp-ics-reminder`: finish ingestion and reminder sync flows.
- `flutter-ui-polish`: redesign the calendar and dashboard surfaces.
- `flutter-test-qa`: add smoke tests for the risky flows before widening scope.

