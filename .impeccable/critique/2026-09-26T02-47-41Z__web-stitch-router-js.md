---
target: web/stitch/router.js
total_score: 28
max_score: 40
na_heuristics:
p0_count: 1
p1_count: 3
timestamp: 2026-09-26T02-47-41Z
slug: web-stitch-router-js
---
# Critique: web/stitch/router.js

## Design Health Score

| # | Heuristic | Score | Key Issue |
|---|---|---:|---|
| 1 | Visibility of System Status | 3/4 | Sync, energy, conflict states are visible, but many actions have no success/loading/error feedback. |
| 2 | Match System / Real World | 3/4 | Recovery, buffer, conflict language fits the domain; technical terms such as SQLite WAL leak into the primary path. |
| 3 | User Control and Freedom | 2/4 | Drawers can visually close without always leaving the parent hash route; undo and confirmation paths are inconsistent. |
| 4 | Consistency and Standards | 2/4 | Desktop screens duplicate action bars and vary in sidebar/header patterns; mobile and desktop IA differ. |
| 5 | Error Prevention | 2/4 | Conflict warnings are strong, but high-impact rescue actions lack consistent confirmation and disabled/error states. |
| 6 | Recognition Rather Than Recall | 3/4 | Grouped navigation and rescue explanations help, but icon-only controls and color-coded states lack labels. |
| 7 | Flexibility and Efficiency | 2/4 | There are period/view controls, but no keyboard shortcuts, bulk actions, or quick workflows for power users. |
| 8 | Aesthetic and Minimalist Design | 2/4 | The palette is restrained, but focus/calendar pages present too many cards, filters, modes, and status signals at once. |
| 9 | Error Recovery | 2/4 | Errors are described, but retry, post-apply undo, and offline recovery are not consistently visible. |
| 10 | Help and Documentation | 2/4 | Domain terms have little contextual explanation; first-use guidance and inline help are absent. |
| **Total** | | **28/40** | Good foundation, but primary workflows and exit states need repair. |

## Design Specificity Verdict

The product has a moderately strong authored identity (about 7/10): “cognitive load”, “recovery buffer”, and rescue strategy tradeoffs are specific to this scheduler. The desktop shell still relies on a generic productivity SaaS pattern, and the most distinctive rescue decision is surrounded by repeated cards and controls instead of being the primary action.

The deterministic detector found 53 warnings in degraded regex mode: 45 `overused-font`, 6 `flat-type-hierarchy`, and 2 `side-tab`. The font findings are mostly bundled Stitch CSS and likely false positives until actual font application is evaluated. The flat hierarchy and side-tab findings are plausible review cues on the schedule/rescue/drawer surfaces, but the detector could not compute CSS variables, selector matching, or contrast. Browser evidence was unavailable: local URLs were blocked by the browser policy, so no `detect.js` injection, overlay, or console findings are claimed.

## Overall Impression

The interface looks polished enough to communicate a sophisticated scheduling product, but it asks users to trust too many static signals. The biggest opportunity is to make one core decision obvious and make every visible control honest about whether it is live, pending, or unavailable.

## What's Working

- Recovery and rescue semantics give the product a clear point of view beyond a normal calendar.
- Desktop grouping and mobile bottom navigation establish a usable information architecture baseline.
- Rescue/settings drawers use a strong visual pattern with overlays, close affordances, and clear comparison content.

## Priority Issues

### [P0] Drawer visual state and route state can diverge

The settings drawer and similar secondary surfaces can hide themselves with a CSS transform or iframe-local `history.back()` while the parent hash remains on the secondary route. Back, refresh, or direct links can therefore reopen a supposedly closed surface. Make the parent router the single source of truth: backdrop, close, save, Escape, browser back, and successful submit must all navigate to the parent route; add dialog semantics and focus return.

Suggested commands: `/impeccable harden`, `/impeccable audit`.

### [P1] Visible controls still drift from real capability

Focus modes, soundscape, emotion controls, calendar filters/views, diagnostics actions, and some rescue actions look interactive but do not consistently expose loading, success, error, disabled, or backend behavior. The router infers behavior from button labels, which is brittle and makes copy changes alter navigation. Give each control an explicit action contract; disable unavailable capabilities or show a deliberate pending state.

Suggested commands: `/impeccable harden`, `/impeccable clarify`.

### [P1] Calendar action hierarchy is duplicated and noisy

The desktop header and calendar controller both expose urgent task, new schedule, ICS, and settings, followed by multiple filters and views. The primary job, “see today and resolve one conflict”, is visually diluted. Keep one action bar, put filters and Pro/Gantt controls behind “Display options”, and expand rescue details only in the selected date context.

Suggested commands: `/impeccable distill`, `/impeccable layout`.

### [P1] Persistent red urgency competes with focus

Focus and mobile schedule surfaces repeatedly show red P0/overload/rescue signals, pulses, and warning chips. This keeps a user in an alert state even when they are trying to work. Use one calm status strip and one “Handle conflict” action; after acceptance, replace the warning with an explicit reversible confirmation.

Suggested commands: `/impeccable quieter`, `/impeccable polish`.

### [P2] Accessibility and responsive semantics are incomplete

Several desktop icon-only settings, account, tune, and avatar buttons lack labels; drawer focus is not reliably trapped/returned; mobile date/view controls lack selected semantics. The mobile deployment scales a 780px canvas into narrow screens, which preserves the mockup but weakens true responsive behavior and text legibility. Add `aria-label`, `aria-pressed`/`aria-selected`, dialog semantics, focus-visible states, and real responsive layout constraints.

Suggested commands: `/impeccable audit`, `/impeccable adapt`.

## Persona Red Flags

- **Alex, power user:** no keyboard shortcuts or bulk actions; several competing action bars and filters make “start focus” or “resolve conflict” take too many decisions.
- **Sam, accessibility-focused user:** icon-only controls lack labels, color and pulse carry important status, and drawer focus behavior is not guaranteed.
- **Casey, distracted mobile user:** seven dates, three views, rescue capsules, and persistent warnings compete for attention; after interruption, the current task is hard to re-establish.

## Minor Observations

- Product title, English page labels, active colors, and sync copy vary between focus, calendar, and mobile surfaces.
- “Local first”, “SQLite WAL”, and “SQLite bidirectional persistence mirror” expose implementation details in the main workflow; keep them in diagnostics.
- Rounded cards and shadows are used almost everywhere, so long pages lose grouping and wayfinding.
- Rescue strategy labels are too long for narrow cards; separate strategy name, consequence, and commit action.

## Questions to Consider

- If the user may do only one thing on the first screen, should it be “Start focus” or “Handle conflict”?
- Can the five calendar filters and Gantt/Pro controls move into one display-options surface?
- Which controls must be disabled offline, and which may work locally while showing a pending sync state?
