((scope) => {
  // API actions are stable identifiers. Visible labels belong to the UI and
  // must never decide whether a click writes data.
  const byId = Object.freeze({
    'schedule-save-action': 'create-schedule',
    'btn-quick-add': 'microtask-quick-add',
    'btn-sweep-start': 'microtask-sweep',
    'schedule-rescue-undo': 'rescue-history',
    'mobile-rescue-undo': 'rescue-history',
    'btn-refresh': 'diagnostics-summary',
    'btn-self-test': 'diagnostics-summary',
    'save-settings-btn': 'settings-save',
    'btn-save-settings': 'settings-save',
    'btn-quick-reserve': 'team-book',
    'btn-silent-room': 'team-book',
    'btn-conflict-check': 'team-conflicts',
    'profile-weekly-export': 'profile-weekly-export',
    'profile-edit-action': 'auth-profile-edit',
    'profile-save': 'auth-profile-save',
    'auth-guest': 'auth-guest',
    'profile-logout-action': 'auth-logout',
  });
  const actions = new Set([
    ...Object.values(byId), 'rescue-options', 'urgent-task-to-microtask',
    'rescue-apply',
  ]);

  function apiAction(button, route) {
    if (!button || button.dataset?.focusAction) return null;
    const explicit = button.dataset?.action;
    if (explicit === 'auth-submit' || (!explicit && button.id === 'auth-submit')) {
      return route === 'login'
        ? (button.dataset?.authMode === 'register' ? 'auth-register' : 'auth-login')
        : null;
    }
    if (explicit) return actions.has(explicit) ? explicit : null;
    if (Object.hasOwn(byId, button.id)) return byId[button.id];
    if (route === 'rescue-comparison' && button.dataset?.rescueOptionId) return 'rescue-apply';
    return null;
  }

  scope.StitchActions = Object.freeze({ apiAction });
})(typeof window === 'undefined' ? globalThis : window);
