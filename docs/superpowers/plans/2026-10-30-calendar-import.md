# 日历文件导入 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a locally parsed calendar import drawer for XLS/XLSX/CSV/TSV/JSON/ICS files, with preview, duplicate filtering, batch persistence, and unchanged calendar styling.

**Architecture:** A small browser-side import adapter normalizes supported files to the existing schedule contract. The calendar opens a right-side drawer that owns file selection, course-table mapping, preview and confirmation; only confirmation calls `/schedule/batch`. A nullable schedule description is added through the API and repository so imported teacher/location data remains editable.

**Tech Stack:** Vanilla browser JavaScript, existing Stitch HTML/CSS/drawer motion, FastAPI/Pydantic, SQLite, Node built-in tests, SheetJS browser bundle for legacy XLS/XLSX.

---

### Task 1: Add parser contract tests

**Files:**
- Create: `tools/tests/calendar_import.test.mjs`
- Create: `web/stitch/calendar-import.js`

- [x] Write failing tests for CSV/TSV/JSON/ICS normalization, BOM and quoted fields, course week expressions (`1-16[周]`, `1-16[单周]`, `3-4,6-9[周]`), term Monday plus section time mapping, stable IDs, and duplicate filtering.
- [x] Run `node --test tools/tests/calendar_import.test.mjs`; confirm failure because exported parser functions do not exist.
- [x] Implement pure parser functions with explicit errors and bounded expansion. Keep file decoding and SheetJS integration behind adapters so the normalizer is independently testable.
- [x] Re-run the focused test and then the existing calendar tests.

### Task 2: Preserve imported notes in the schedule contract

**Files:**
- Modify: `backend/schemas.py`
- Modify: `backend/repositories.py`
- Modify: `backend/tests/test_schedule_extensions.py`
- Modify: `web/stitch/components/schedule-detail-drawer.html`
- Modify: `web/stitch/router.js`

- [x] Add a failing API/repository test that creates a schedule with `description`, lists it, updates it, and verifies the value survives an old database initialized without the column.
- [x] Run the focused backend test and confirm the missing-field failure.
- [x] Add nullable `description` migration and serialization to single and batch schedule writes, including snapshot restore paths; expose the field in create/edit/detail forms without changing their existing layout.
- [x] Run the focused backend test and the existing schedule test suite.

### Task 3: Build the import drawer and calendar entry points

**Files:**
- Create: `web/stitch/mobile/import-schedule-drawer/index.html`
- Modify: `web/stitch/screens/smart-calendar/index.html`
- Modify: `web/stitch/mobile/schedule/index.html`
- Modify: `web/stitch/router.js`
- Modify: `web/stitch/calendar.js`
- Modify: `web/stitch/assets/calendar.css`
- Modify: `web/stitch/assets/vendor/xlsx.full.min.js`

- [x] Add a failing DOM/source test requiring desktop and mobile create-drawer “导入日程” controls, route registration, accepted file types, preview state, confirm/cancel actions, and no API write before confirmation.
- [x] Run the focused source test and confirm the missing-entry failure.
- [x] Place the import entry inside the existing create-schedule drawer, retain its draft on cancellation, and hide the entry while editing. Add a right-side import drawer using the existing close control and drawer-motion conventions. Keep the current button palette, spacing, typography, and responsive breakpoints.
- [x] Add local file reading and SheetJS XLS/XLSX loading; feed all formats through the pure parser and render preview rows with errors, duplicate markers, selected checkboxes, course-week controls, and section-time controls.
- [x] On confirmation, call `/schedule/batch`, show result/error state, refresh the retained calendar controller, and preserve selected date/view/Gantt state. Existing ICS exchange remains available.
- [x] Run source tests and existing drawer checks.

### Task 4: End-to-end and release verification

**Files:**
- Create: `tools/check_stitch_calendar_import.mjs`
- Create: `backend/tests/test_schedule_import.py`
- Modify: `docs/visual-qa/2026-10-31-calendar-import.md`

- [x] Add backend tests for atomic batch import, auth isolation, description persistence and duplicate-safe IDs.
- [x] Add browser checks for file selection, preview, cancel-without-write, confirm, reload persistence, day/week/month/Gantt rendering, mobile layout, and the supplied XLS sample.
- [x] Run all focused tests, `node tools/check_web_sources.mjs`, `git diff --check`, and the browser check with the configured Playwright runtime.
- [x] Build the Stitch release, deploy through the existing release script, compare manifest/file hashes, run `/health`, and document the release ID and verification evidence.
