# Stitch Web API Contract

`web/stitch/router.js` owns the deployed iframe shell and exposes the following action contract to child screens through `window.parent.__RUANCHUANG_API_ACTION__`.

| Frontend action | HTTP contract | Payload source | Success behavior |
|---|---|---|---|
| `create-schedule` | `POST /schedule` | Create-schedule drawer title, tag, time and duration | Navigate to schedule and refresh sync state |
| `import-microtasks` | `POST /microtasks/import` | Microtask breakdown textarea | Navigate to microtasks |
| `import-ics` | `POST /schedule/import-ics` | Integrations raw input | Navigate to schedule |
| `import-microtask-text` | `POST /microtasks/import` | Integrations raw input | Keep integrations page and show result |
| `team-book` | `POST /team/book-meeting` | Current team member IDs and default collaboration window | Show server-confirmed booking |
| `team-conflicts` | `POST /team/conflicts` | Current team member IDs and selected probe window | Show conflict count |
| `diagnostics-summary` | `GET /diagnostics/summary` | Authenticated session | Show server counts |
| `settings-save` | `PUT /settings` | Theme and locale controls | Return to profile after server commit |
| `focus-event` | `POST /events` | Current focus action | Record complete or postpone event |
| `rescue-options` | `POST /schedule/rescue/options` | Current schedule plus urgent-task contract | Open rescue comparison with server options |
| `rescue-apply` | `POST /schedule/rescue/apply` | Selected server option and baseline hash | Commit one transaction and return to schedule |
| `rescue-history` | `GET /schedule/rescue/history` | Authenticated session | Show server history count |

All mutations use the API client's bearer token when present. `401`, validation, conflict and malformed-response errors remain visible to the user; the shell does not convert them into a false success state.
