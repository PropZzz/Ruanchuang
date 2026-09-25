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

  const parentRoutes = {
    goals: 'profile',
    review: 'profile',
    integrations: 'profile',
    bluetooth: 'profile',
    'emotion-energy': 'profile',
    diagnostics: 'profile',
    'settings-drawer': 'profile',
    'rescue-comparison': 'schedule',
    'create-schedule': 'schedule',
    'urgent-task': 'schedule',
    'microtask-entry': 'micro',
  };

  const frame = document.getElementById('prototype-screen');
  const mobileQuery = window.matchMedia('(max-width: 780px)');
  let activeRoute = 'focus';

  const apiBase = (window.__RUANCHUANG_API__ ||
    (window.location.hostname === '127.0.0.1' || window.location.hostname === 'localhost'
      ? 'http://127.0.0.1:8000'
      : '/api')).replace(/\/$/, '');

  function authHeaders() {
    const token = localStorage.getItem('access_token') || localStorage.getItem('token');
    return token ? { Authorization: `Bearer ${token}` } : {};
  }

  async function backendRequest(path) {
    const response = await fetch(`${apiBase}${path}`, {
      headers: { Accept: 'application/json', ...authHeaders() },
      credentials: 'omit',
    });
    if (!response.ok) {
      const error = new Error(`Backend request failed: ${response.status}`);
      error.status = response.status;
      throw error;
    }
    return response.json();
  }

  function updateSyncLabel(document, label) {
    const candidates = [...document.querySelectorAll('span')].filter((node) => {
      const value = node.textContent.trim();
      return value.startsWith('已同步');
    });
    for (const target of candidates) target.textContent = label;
  }

  async function hydrateBackend(document, route) {
    document.documentElement.dataset.backendState = 'loading';
    try {
      await backendRequest('/health');
      let label = '已连接 · FastAPI';
      if (route === 'schedule') {
        const entries = await backendRequest('/schedule');
        label = `已连接 · 日程 ${Array.isArray(entries) ? entries.length : 0} 条`;
      } else if (route === 'micro') {
        const tasks = await backendRequest('/microtasks');
        label = `已连接 · 微任务 ${Array.isArray(tasks) ? tasks.length : 0} 项`;
      } else if (route === 'team') {
        const members = await backendRequest('/team/members');
        label = `已连接 · 团队 ${Array.isArray(members) ? members.length : 0} 人`;
      } else if (route === 'focus') {
        const energy = await backendRequest('/energy/current');
        const score = energy?.batteryPercent ?? energy?.battery_percent;
        if (Number.isFinite(Number(score))) label = `已连接 · 能量 ${score} 分`;
      }
      document.documentElement.dataset.backendState = 'online';
      updateSyncLabel(document, label);
      window.dispatchEvent(new CustomEvent('stitch:backend-state', {
        detail: { state: 'online', route, label },
      }));
    } catch (error) {
      const state = error.status === 401 ? 'auth-required' : 'offline';
      const label = state === 'auth-required' ? '请登录后同步' : '本地模式 · 后端不可用';
      document.documentElement.dataset.backendState = state;
      updateSyncLabel(document, label);
      window.dispatchEvent(new CustomEvent('stitch:backend-state', {
        detail: { state, route, error: String(error) },
      }));
    }
  }

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

  function returnFromSecondary() {
    const parent = parentRoutes[activeRoute];
    if (parent) {
      navigate(parent);
      return;
    }
    history.back();
  }

  function showNotice(document, message) {
    document.getElementById('stitch-router-notice')?.remove();
    const notice = document.createElement('div');
    notice.id = 'stitch-router-notice';
    notice.textContent = message;
    Object.assign(notice.style, {
      position: 'fixed',
      left: '50%',
      bottom: '24px',
      transform: 'translateX(-50%)',
      zIndex: '9999',
      maxWidth: 'min(90vw, 420px)',
      padding: '10px 14px',
      borderRadius: '10px',
      background: '#163d3d',
      color: '#ffffff',
      font: '500 13px/1.4 system-ui, sans-serif',
      boxShadow: '0 4px 18px rgba(0,0,0,.2)',
    });
    document.body.appendChild(notice);
    window.setTimeout(() => notice.remove(), 2600);
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
    if (label.includes('通知') || label.includes('notification')) {
      return '__notice__';
    }
    if (
      label.includes('返回') ||
      label.includes('back') ||
      label.includes('previous') ||
      label.includes('关闭') ||
      label.includes('close') ||
      label.includes('cancel') ||
      label.includes('取消')
    ) {
      return parentRoutes[activeRoute] || null;
    }
    if (label.includes('设置') || label.includes('settings')) return 'settings-drawer';
    if (label.includes('目标') || label.includes('goals')) return 'goals';
    if (label.includes('复盘') || label.includes('review')) return 'review';
    if (label.includes('诊断') || label.includes('diagnostics')) return 'diagnostics';
    if (label.includes('情绪') || label.includes('emotion')) return 'emotion-energy';
    if (label.includes('蓝牙') || label.includes('bluetooth')) return 'bluetooth';
    if (label.includes('mcp') || label.includes('接入')) return 'integrations';
    if (label.includes('插入紧急') || label.includes('urgent task')) return mobileQuery.matches ? 'urgent-task' : 'rescue-comparison';
    if (label.includes('ics') || label.includes('导入/导出')) return 'integrations';
    if (label.includes('新增日程') || label.includes('新建日程') || label.includes('add schedule') || label.includes('new schedule')) return 'create-schedule';
    if (label.includes('添加微任务') || label.includes('add microtask') || label.includes('import list') || label.includes('导入清单')) return 'microtask-entry';
    if (label.includes('救援方案') || label.includes('比较方案') || label.includes('三方案救援对比') || label.includes('rescue plan') || label.includes('重新规划') || label.includes('replan')) return 'rescue-comparison';
    if (activeRoute === 'create-schedule' && (label.includes('保存') || label.includes('save'))) return 'schedule';
    if (activeRoute === 'urgent-task' && (label.includes('生成三方案') || label.includes('救援对比'))) return 'rescue-comparison';
    if (activeRoute === 'microtask-entry' && (label.includes('存入沙盒') || label.includes('confirm') || label.includes('完成'))) return 'micro';
    if (activeRoute === 'settings-drawer' && (label.includes('保存') || label.includes('save'))) return 'profile';
    if (label.includes('采用此方案') || label.includes('apply plan') || label.includes('导入') || label.includes('save')) {
      if (activeRoute === 'rescue-comparison' || activeRoute === 'create-schedule' || activeRoute === 'urgent-task') return 'schedule';
      if (activeRoute === 'microtask-entry') return 'micro';
      if (activeRoute === 'settings-drawer') return 'profile';
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
      if (route === '__notice__') {
        event.preventDefault();
        showNotice(childDocument, '通知与提醒暂未接入，当前不会发送提醒。');
        return;
      }
      if (route) {
        event.preventDefault();
        navigate(route);
      }
    });

    hydrateBackend(childDocument, activeRoute);
  });

  window.addEventListener('hashchange', () => renderRoute(routeFromHash()));
  window.addEventListener('popstate', () => renderRoute(routeFromHash()));
  mobileQuery.addEventListener('change', () => renderRoute(activeRoute));
  window.addEventListener('resize', applyCanvasSize);
  window.addEventListener('keydown', (event) => {
    if (event.key === 'Escape') returnFromSecondary();
  });

  activeRoute = routeFromHash();
  if (!window.location.hash) history.replaceState(null, '', '#/focus');
  renderRoute(activeRoute);
})();
