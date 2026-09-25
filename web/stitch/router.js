(() => {
  const pages = {
    focus: ['screens/focus/index.html', 'mobile/focus/index.html'],
    schedule: ['screens/smart-calendar/index.html', 'mobile/schedule/index.html'],
    micro: ['screens/microtasks/index.html', 'mobile/microtasks/index.html'],
    team: ['screens/team/index.html', 'mobile/team/index.html'],
    profile: ['screens/profile/index.html'],
    goals: ['screens/goals/index.html'],
    review: ['screens/review/index.html'],
    integrations: ['screens/integrations/index.html'],
    bluetooth: ['screens/bluetooth/index.html'],
    'emotion-energy': ['screens/emotion-energy/index.html'],
    diagnostics: ['screens/diagnostics/index.html'],
    'rescue-comparison': ['screens/rescue-comparison/index.html', 'mobile/urgent-rescue-comparison/index.html'],
    'settings-drawer': ['screens/settings-drawer/index.html', 'mobile/settings-drawer/index.html'],
    'create-schedule': ['mobile/create-schedule-drawer/index.html'],
    'urgent-task': ['mobile/insert-urgent-task-drawer/index.html'],
    'microtask-entry': ['mobile/microtask-entry-breakdown/index.html'],
  };

  const aliases = {
    focus: 'focus',
    schedule: 'schedule',
    micro: 'micro',
    microtasks: 'micro',
    'micro-tasks': 'micro',
    mcp: 'integrations',
    team: 'team',
    profile: 'profile',
    goals: 'goals',
    review: 'review',
    integrations: 'integrations',
    bluetooth: 'bluetooth',
    emotion: 'emotion-energy',
    'emotion-energy': 'emotion-energy',
    diagnostics: 'diagnostics',
  };

  const frame = document.getElementById('prototype-screen');
  const mobileQuery = window.matchMedia('(max-width: 780px)');
  let activeRoute = 'focus';

  function applyCanvasSize() {
    if (mobileQuery.matches) {
      const scale = Math.min(1, window.innerWidth / 780);
      frame.style.width = '780px';
      frame.style.height = `${window.innerHeight / scale}px`;
      frame.style.transform = `scale(${scale})`;
      frame.style.transformOrigin = 'top left';
      return;
    }
    frame.style.width = '100%';
    frame.style.height = '100%';
    frame.style.transform = 'none';
  }

  function routeFromHash() {
    const value = window.location.hash.replace(/^#\/?/, '').trim();
    return pages[value] ? value : 'focus';
  }

  function screenFor(route) {
    const options = pages[route] || pages.focus;
    const path = mobileQuery.matches ? options[1] || options[0] : options[0];
    return new URL(`stitch/${path}`, document.baseURI).toString();
  }

  function renderRoute(route) {
    activeRoute = pages[route] ? route : 'focus';
    applyCanvasSize();
    frame.src = screenFor(activeRoute);
    frame.title = `时序智配 ${activeRoute}`;
  }

  function navigate(route, { replace = false } = {}) {
    if (!pages[route]) route = aliases[route] || 'focus';
    const hash = `#/${route}`;
    if (replace) history.replaceState(null, '', hash);
    else if (window.location.hash !== hash) history.pushState(null, '', hash);
    renderRoute(route);
  }

  function routeForLink(anchor) {
    const path = anchor.dataset.path;
    if (path && aliases[path]) return aliases[path];
    const label = `${anchor.innerText || ''} ${anchor.getAttribute('aria-label') || ''}`.toLowerCase();
    if (label.includes('calendar') || label.includes('日历') || label.includes('日程')) return 'schedule';
    if (label.includes('micro') || label.includes('微任务')) return 'micro';
    if (label.includes('team') || label.includes('团队')) return 'team';
    if (label.includes('profile') || label.includes('我的')) return 'profile';
    if (label.includes('emotion') || label.includes('情绪')) return 'emotion-energy';
    if (label.includes('bluetooth') || label.includes('蓝牙')) return 'bluetooth';
    if (label.includes('diagnostic') || label.includes('诊断')) return 'diagnostics';
    if (label.includes('review') || label.includes('复盘')) return 'review';
    if (label.includes('goal') || label.includes('目标')) return 'goals';
    if (label.includes('mcp') || label.includes('集成')) return 'integrations';
    return null;
  }

  function routeForButton(button) {
    const label = `${button.innerText || ''} ${button.title || ''} ${button.getAttribute('aria-label') || ''}`.toLowerCase();
    if (label.includes('设置') || label.includes('settings')) return 'settings-drawer';
    if (label.includes('目标') || label.includes('goals')) return 'goals';
    if (label.includes('复盘') || label.includes('review')) return 'review';
    if (label.includes('诊断') || label.includes('diagnostics')) return 'diagnostics';
    if (label.includes('情绪') || label.includes('emotion')) return 'emotion-energy';
    if (label.includes('蓝牙') || label.includes('bluetooth')) return 'bluetooth';
    if (label.includes('mcp') || label.includes('接入')) return 'integrations';
    if (label.includes('插入紧急') || label.includes('urgent task')) return mobileQuery.matches ? 'urgent-task' : 'rescue-comparison';
    if (label.includes('新增日程') || label.includes('新建日程') || label.includes('add schedule') || label.includes('new schedule')) return mobileQuery.matches ? 'create-schedule' : null;
    if (label.includes('添加微任务') || label.includes('add microtask') || label.includes('import list') || label.includes('导入清单')) return 'microtask-entry';
    if (label.includes('救援方案') || label.includes('比较方案') || label.includes('rescue plan') || label.includes('重新规划') || label.includes('replan')) return 'rescue-comparison';
    if (label.includes('采用此方案') || label.includes('apply plan') || label.includes('导入') || label.includes('save')) {
      if (activeRoute === 'rescue-comparison' || activeRoute === 'create-schedule' || activeRoute === 'urgent-task') return 'schedule';
      if (activeRoute === 'microtask-entry') return 'micro';
      if (activeRoute === 'settings-drawer') return 'profile';
    }
    if (label.includes('取消') || label.includes('关闭') || label.includes('close') || label.includes('cancel')) {
      if (activeRoute === 'settings-drawer') return 'profile';
      if (activeRoute === 'rescue-comparison' || activeRoute === 'urgent-task' || activeRoute === 'create-schedule') return 'schedule';
      if (activeRoute === 'microtask-entry') return 'micro';
    }
    return null;
  }

  frame.addEventListener('load', () => {
    let childDocument;
    try {
      childDocument = frame.contentDocument;
      if (!childDocument) return;
    } catch (_) {
      return;
    }

    childDocument.addEventListener('click', (event) => {
      const anchor = event.target.closest('a');
      if (anchor) {
        const route = routeForLink(anchor);
        if (route) {
          event.preventDefault();
          navigate(route);
          return;
        }
      }

      const button = event.target.closest('button');
      if (!button) return;
      const route = routeForButton(button);
      if (route) {
        event.preventDefault();
        navigate(route);
      }
    });
  });

  window.addEventListener('hashchange', () => renderRoute(routeFromHash()));
  window.addEventListener('popstate', () => renderRoute(routeFromHash()));
  mobileQuery.addEventListener('change', () => renderRoute(activeRoute));
  window.addEventListener('resize', applyCanvasSize);
  window.addEventListener('keydown', (event) => {
    if (event.key === 'Escape') history.back();
  });

  activeRoute = routeFromHash();
  if (!window.location.hash) history.replaceState(null, '', '#/focus');
  renderRoute(activeRoute);
})();
