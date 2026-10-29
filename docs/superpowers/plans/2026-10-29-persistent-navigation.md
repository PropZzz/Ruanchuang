# Persistent navigation implementation plan

**Goal:** Stop reloading primary pages on every navigation and deploy the verified result.

**Architecture:** A bounded page host retains the eight primary iframe documents, isolated from each other. A persistent desktop shell owns navigation and common actions. Cold loads keep the previous page visible; a navigation generation prevents late loads from replacing the latest selection. Secondary forms remain disposable. Data hydration runs independently of document loading; account changes clear retained documents.

**Tech stack:** Existing vanilla JavaScript/HTML frontend, Playwright browser checks, deterministic release builder, Nginx atomic deployment.

- [x] Add `tools/check_stitch_navigation.mjs`: reproduce repeated document requests and lost state with real Chromium; assert document identity, scroll/input retention, latest navigation, history, layout change, reduced motion, auth invalidation and failure recovery.
- [x] Add `web/stitch/page-host.js`: retained documents, loading/error feedback, lifecycle events, shell and short content transition. Version its entry script in `tools/build_stitch_web.mjs`.
- [x] Integrate `web/stitch/router.js`: capture each document's route during setup, activate only ready destinations, refresh data without replacing DOM, clear cached documents on account changes, retain modal accessibility.
- [x] Adapt desktop/mobile focus timers to pause rendering while hidden and reconcile elapsed wall time on return. Keep the mobile design source synchronized.
- [x] Run `node --test tools/tests/*.test.mjs`, browser navigation/release checks and Flutter web source contracts. Review changes independently and resolve findings.
- [x] Run `python build/deploy_web_release.py`; verify the deployed manifest, navigation behavior and health at the production URL. Record release and review results.

Completed and deployed release `b2008b5ffb562f54`; see the navigation release review for verification and rollback details.
