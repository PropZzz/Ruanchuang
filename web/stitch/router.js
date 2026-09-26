(() => {
  const pages = {
    focus: ['screens/focus/index.html', 'mobile/focus/index.html'],
    login: ['screens/login/index.html'],
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
    'rescue-comparison': 'schedule',
    'create-schedule': 'schedule',
    'urgent-task': 'schedule',
    'microtask-entry': 'micro',
  };

  const frame = document.getElementById('prototype-screen');
  const mobileQuery = window.matchMedia('(max-width: 780px)');
  const routeAssetVersion = '2026-09-26';
  let activeRoute = 'focus';
  let loginReturnRoute = 'focus';
  let hasRenderedRoute = false;
  let rescueState = null;
  let settingsOverlayHost = null;
  let settingsOverlayFrame = null;
  let settingsReturnRoute = 'focus';
  let settingsHistoryPending = false;
  let settingsOpener = null;
  let previousBodyOverflow = '';
  let previousFrameInert = false;
  let previousFrameAriaHidden = null;
  let activeThemeMode = 'system';
  let settingsDraft = null;
  let settingsPreferencesLoaded = false;
  let settingsOverlayMobile = false;
  let settingsTokenHydrated = '';
  const rescueSnapshotMemory = new Map();

  const apiBase = (window.__RUANCHUANG_API__ ||
    (window.location.hostname === '127.0.0.1' || window.location.hostname === 'localhost'
      ? 'http://127.0.0.1:8000'
      : '/api')).replace(/\/$/, '');

  function authHeaders() {
    const token = localStorage.getItem('access_token') || localStorage.getItem('token');
    return token ? { Authorization: `Bearer ${token}` } : {};
  }

  async function backendRequest(path, { method = 'GET', body } = {}) {
    const response = await fetch(`${apiBase}${path}`, {
      method,
      headers: { Accept: 'application/json', ...authHeaders() },
      credentials: 'omit',
      ...(body === undefined ? {} : {
        headers: {
          Accept: 'application/json',
          'Content-Type': 'application/json',
          ...authHeaders(),
        },
        body: JSON.stringify(body),
      }),
    });
    if (!response.ok) {
      const detail = await response.text();
      const error = new Error(detail || `Backend request failed: ${response.status}`);
      error.status = response.status;
      throw error;
    }
    if (response.status === 204) return null;
    const text = await response.text();
    return text ? JSON.parse(text) : null;
  }

  function updateSyncLabel(document, label) {
    const candidates = [...document.querySelectorAll('span')].filter((node) => {
      const value = node.textContent.trim();
      return value.startsWith('已同步');
    });
    for (const target of candidates) target.textContent = label;
  }

  function updateConflictCopy(document, count) {
    const labels = [...document.querySelectorAll('span, p, h3, h4')];
    const target = document.getElementById('schedule-conflict-status') ||
      document.getElementById('calendar-conflict-status') ||
      labels.find((node) => /探测到\s*\d+\s*处/.test(node.textContent));
    const statusText = count
      ? `服务端检测到 ${count} 处日程冲突`
      : '服务端检测到当前日程无冲突';
    if (target) {
      target.textContent = statusText;
    }
    const severity = labels.find((node) => node.textContent.trim() === '高紧迫性');
    if (severity) {
      severity.textContent = count ? '需要处理' : '当前正常';
      severity.classList.toggle('text-error', Boolean(count));
    }
    const conflictCount = document.getElementById('schedule-conflict-severity') ||
      document.getElementById('calendar-conflict-severity');
    if (conflictCount) {
      conflictCount.textContent = count ? '需要处理' : '当前正常';
      conflictCount.classList.toggle('text-error', Boolean(count));
      conflictCount.classList.toggle('text-on-surface-variant', !count);
    }
    const panel = document.getElementById('schedule-conflict-panel') ||
      target?.closest('.p-3.rounded-xl');
    const copy = document.getElementById('schedule-conflict-copy') ||
      document.getElementById('calendar-conflict-copy') ||
      panel?.querySelector('p');
    if (copy) {
      copy.textContent = count
        ? `服务端检测到 ${count} 处排期重叠。填写紧急任务目标和硬截止时间后，可生成对应救援方案。`
        : '当前服务端日程没有时间重叠。插入紧急任务前，请先填写任务目标和硬截止时间以计算方案。';
    }
    const risk = document.getElementById('schedule-conflict-risk');
    if (risk) {
      risk.classList.toggle('text-error/80', Boolean(count));
      risk.classList.toggle('text-on-surface-variant', !count);
    }
    const riskCopy = document.getElementById('calendar-conflict-risk') ||
      labels.find((node) => node.textContent.includes('违背硬约束风险'));
    if (riskCopy) riskCopy.textContent = '救援风险：需提交任务后分析';
    const affectedCopy = document.getElementById('calendar-conflict-affected') ||
      labels.find((node) => node.textContent.includes('受影响日程'));
    if (affectedCopy) affectedCopy.textContent = '受影响日程：需提交任务后分析';
    if (panel) {
      panel.classList.toggle('bg-error-container', Boolean(count));
      panel.classList.toggle('text-on-error-container', Boolean(count));
      panel.classList.remove('bg-surface-container-low');
      panel.classList.toggle('bg-surface-container-lowest', !count);
      panel.classList.toggle('text-on-surface', !count);
      const icon = panel.querySelector('.material-symbols-outlined');
      if (icon) {
        icon.textContent = count ? 'warning' : 'check_circle_outline';
        icon.classList.toggle('text-error', Boolean(count));
        icon.classList.toggle('text-on-tertiary-container', !count);
      }
    }
    const priority = labels.find((node) => node.textContent.trim() === 'P0 核心中断');
    if (priority) priority.textContent = count ? 'P0 核心中断' : '今日无硬冲突';
  }

  function enhanceAccessibility(document) {
    const iconLabels = {
      settings: '设置',
      tune: '调整选项',
      bolt: '插入紧急任务',
      more_vert: '更多操作',
      notifications: '通知',
      person: '个人资料',
      chevron_left: '上一项',
      chevron_right: '下一项',
    };
    for (const button of document.querySelectorAll('button')) {
      const icon = button.querySelector('.material-symbols-outlined');
      const visibleText = [...button.childNodes]
        .filter((node) => node.nodeType === Node.TEXT_NODE)
        .map((node) => node.textContent.trim())
        .join(' ')
        .trim();
      if (!button.getAttribute('aria-label') && !button.title && !visibleText && icon) {
        const label = iconLabels[icon.textContent.trim()];
        if (label) {
          button.setAttribute('aria-label', label);
          button.title = label;
        }
      }
      if (icon && !visibleText && !button.style.minWidth) {
        button.style.minWidth = '44px';
        button.style.minHeight = '44px';
      }
    }
    for (const dialog of document.querySelectorAll('[id*="drawer"], [id*="Modal"], [id*="modal"]')) {
      if (dialog.tagName === 'ASIDE' || dialog.tagName === 'SECTION' || dialog.getAttribute('role') === 'dialog') {
        dialog.setAttribute('role', 'dialog');
        dialog.setAttribute('aria-modal', 'true');
      }
    }

    for (const button of document.querySelectorAll('header button')) {
      const icon = button.querySelector('.material-symbols-outlined')?.textContent.trim();
      const visibleLabel = Array.from(button.querySelectorAll(':scope > span:not(.material-symbols-outlined)'))
        .some((node) => getComputedStyle(node).display !== 'none' && node.textContent.trim());
      if (icon === 'add' && !visibleLabel && !button.getAttribute('aria-label')) {
        button.setAttribute('aria-label', '新增日程');
        button.title = '新增日程';
      }
    }
  }

  function injectPolishStyles(document) {
    const existing = document.getElementById('ruanchuang-polish-styles');
    if (existing) return;
    const link = document.createElement('link');
    link.id = 'ruanchuang-polish-styles';
    link.rel = 'stylesheet';
    link.href = new URL(
      mobileQuery.matches ? 'stitch/mobile/assets/polish.css' : 'stitch/assets/polish.css',
      window.location.href,
    ).toString();
    document.head.appendChild(link);
    document.documentElement.dataset.route = activeRoute;
    if (activeRoute === 'create-schedule' || activeRoute === 'urgent-task') {
      const backdrop = document.querySelector('body > button.fixed.inset-0.z-0');
      const drawer = document.querySelector('body > section');
      if (backdrop) {
        backdrop.removeAttribute('onclick');
        backdrop.dataset.routerReturn = 'true';
        backdrop.style.zIndex = '0';
      }
      for (const closeButton of document.querySelectorAll('button[aria-label="关闭抽屉"]')) {
        closeButton.removeAttribute('onclick');
      }
      if (drawer) {
        drawer.style.position = 'relative';
        drawer.style.zIndex = '1';
      }
    }
  }

  async function hydrateBackend(document, route) {
    document.documentElement.dataset.backendState = 'loading';
    try {
      await backendRequest('/health');
      let label = '已连接 · FastAPI';
      if (route === 'schedule') {
        const entries = await backendRequest('/schedule');
        const conflicts = await backendRequest(`/schedule/conflicts?day=${todayIso()}`);
        const conflictCount = Array.isArray(conflicts?.conflicts) ? conflicts.conflicts.length : 0;
        updateConflictCopy(document, conflictCount);
        const dateLabel = Array.from(document.querySelectorAll('span, div'))
          .find((node) => /^\d{4}年\d+月\d+日 星期[一二三四五六日]$/.test(node.textContent.trim()));
        if (dateLabel) {
          const now = new Date();
          const weekdays = ['日', '一', '二', '三', '四', '五', '六'];
          dateLabel.textContent = `${now.getFullYear()}年${now.getMonth() + 1}月${now.getDate()}日 星期${weekdays[now.getDay()]}`;
        }
        label = `已连接 · 日程 ${Array.isArray(entries) ? entries.length : 0} 条 · 冲突 ${conflictCount}`;
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

  function readStoredUser() {
    try {
      return JSON.parse(localStorage.getItem('ruanchuang_user') || '{}');
    } catch (_) {
      return {};
    }
  }

  function rescueSnapshotStorageKey() {
    let token = '';
    try {
      token = localStorage.getItem('access_token') || localStorage.getItem('token') || '';
    } catch (_) {}
    const identity = readStoredUser().contactAddress || token;
    return identity ? `ruanchuang_rescue_snapshots:${identity}` : null;
  }

  function readRescueSnapshots() {
    const key = rescueSnapshotStorageKey();
    if (!key) return [];
    try {
      const stored = localStorage.getItem(key);
      if (stored == null || stored === '') return rescueSnapshotMemory.get(key) || [];
      const value = JSON.parse(stored);
      const snapshots = Array.isArray(value)
        ? value.filter((item) => typeof item?.snapshotId === 'string')
        : [];
      rescueSnapshotMemory.set(key, snapshots);
      return snapshots;
    } catch (_) {
      return rescueSnapshotMemory.get(key) || [];
    }
  }

  function rememberRescueSnapshot(snapshotId) {
    if (!snapshotId) return;
    const key = rescueSnapshotStorageKey();
    if (!key) return;
    const snapshots = readRescueSnapshots().filter((item) => item.snapshotId !== snapshotId);
    snapshots.push({ snapshotId, createdAt: Date.now() });
    const bounded = snapshots.slice(-20);
    rescueSnapshotMemory.set(key, bounded);
    try {
      localStorage.setItem(key, JSON.stringify(bounded));
    } catch (_) {}
  }

  function forgetRescueSnapshot(snapshotId) {
    const key = rescueSnapshotStorageKey();
    if (!key) return;
    const snapshots = readRescueSnapshots().filter((item) => item.snapshotId !== snapshotId);
    rescueSnapshotMemory.set(key, snapshots);
    try {
      localStorage.setItem(key, JSON.stringify(snapshots));
    } catch (_) {}
  }

  async function hydrateStoredTheme(document) {
    const token = localStorage.getItem('access_token') || localStorage.getItem('token');
    if (!token || token === settingsTokenHydrated) return;
    try {
      const settings = await backendRequest('/settings');
      activeThemeMode = ['system', 'light', 'dark'].includes(settings?.themeMode)
        ? settings.themeMode
        : 'system';
      settingsTokenHydrated = token;
      applyThemeMode(activeThemeMode);
    } catch (error) {
      if (error.status === 401) {
        localStorage.removeItem('access_token');
        localStorage.removeItem('token');
        localStorage.removeItem('ruanchuang_user');
        settingsTokenHydrated = '';
        showNotice(document, '登录状态已失效，请重新登录。');
      }
    }
  }

  function applyCanvasSize() {
    if (mobileQuery.matches) {
      frame.style.width = '100%';
      frame.style.height = '100%';
      frame.style.transform = 'none';
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
    const url = new URL(`stitch/${path}`, document.baseURI);
    url.searchParams.set('v', routeAssetVersion);
    return url.toString();
  }

  function applyThemeMode(themeMode) {
    const dark = themeMode === 'dark' ||
      (themeMode === 'system' && window.matchMedia('(prefers-color-scheme: dark)').matches);
    const canvas = dark ? '#101b1d' : '#faf8fe';
    document.documentElement.classList.toggle('dark', dark);
    document.documentElement.style.colorScheme = dark ? 'dark' : 'light';
    document.body.style.backgroundColor = canvas;
    frame.style.backgroundColor = canvas;

    for (const target of [frame.contentDocument, settingsOverlayFrame?.contentDocument]) {
      if (!target?.documentElement) continue;
      target.documentElement.classList.toggle('dark', dark);
      target.documentElement.style.colorScheme = dark ? 'dark' : 'light';
      if (target.body) target.body.style.backgroundColor = canvas;
    }
  }

  function setThemeButtons(document, themeMode) {
    const selectedValue = themeMode === 'system' ? 'auto' : themeMode;
    for (const button of document.querySelectorAll('button[data-theme]')) {
      const selected = button.dataset.theme === selectedValue;
      button.setAttribute('aria-pressed', String(selected));
      button.classList.remove(
        'bg-surface-container-lowest',
        'text-primary',
        'text-primary-container',
        'font-semibold',
        'shadow-sm',
        'text-on-surface-variant',
      );
      button.classList.add(selected ? 'bg-surface-container-lowest' : 'text-on-surface-variant');
      if (selected) {
        button.classList.add(
          mobileQuery.matches ? 'text-primary-container' : 'text-primary',
          'font-semibold',
          'shadow-sm',
        );
      }
    }
  }

  function setLocaleButtons(document, locale) {
    const selectedValue = locale === 'en_US' ? 'en-US' : 'zh-CN';
    for (const button of document.querySelectorAll('button[data-lang]')) {
      const selected = button.dataset.lang === selectedValue;
      button.setAttribute('aria-pressed', String(selected));
      button.classList.remove(
        'bg-surface-container-lowest',
        'bg-surface-container',
        'bg-surface-container-low',
        'text-primary',
        'text-on-surface',
        'text-on-surface-variant',
        'font-semibold',
        'font-medium',
        'shadow-sm',
      );
      button.classList.add(
        selected ? 'bg-surface-container-lowest' : 'bg-surface-container-low',
        selected ? 'text-primary' : 'text-on-surface-variant',
        selected ? 'font-semibold' : 'font-medium',
      );
      if (selected) button.classList.add('shadow-sm');

      const icon = button.querySelector('.material-symbols-outlined');
      if (selected && !icon) {
        const check = document.createElement('span');
        check.className = 'material-symbols-outlined text-[15px] text-primary';
        check.textContent = 'check';
        button.prepend(check);
      } else if (!selected) {
        icon?.remove();
      } else if (icon) {
        icon.textContent = 'check';
      }

      if (button.dataset.lang === 'zh-CN') {
        for (const node of button.childNodes) {
          if (node.nodeType !== Node.TEXT_NODE || !node.textContent.trim()) continue;
          node.textContent = selected ? '简体中文 (当前)' : '简体中文';
        }
      }
    }
  }

  function setSettingsControlsDisabled(document, disabled) {
    for (const control of document.querySelectorAll('button[data-theme], button[data-lang], [data-settings-reset], #save-settings-btn, #btn-save-settings')) {
      control.disabled = disabled;
      if (disabled) control.setAttribute('aria-disabled', 'true');
      else control.removeAttribute('aria-disabled');
      control.style.opacity = disabled ? '0.58' : '';
      control.style.cursor = disabled ? 'not-allowed' : '';
    }
  }

  function markUnsupportedSettingsControls(document) {
    for (const checkbox of document.querySelectorAll('#settings-drawer input[type="checkbox"]')) {
      checkbox.checked = false;
      checkbox.disabled = true;
      checkbox.title = '当前后端未提供此开关的保存接口';
      checkbox.setAttribute('aria-label', '该设置暂未接入保存接口');
      const label = checkbox.closest('label');
      label?.classList.remove('cursor-pointer');
      if (label) {
        label.title = checkbox.title;
        label.style.cursor = 'not-allowed';
        label.style.opacity = '0.58';
      }

      const section = checkbox.closest('section');
      if (section && !section.querySelector('[data-settings-unavailable]')) {
        const note = document.createElement('p');
        note.dataset.settingsUnavailable = 'true';
        note.className = 'text-[11px] text-on-surface-variant';
        note.textContent = '本版本后端暂不支持保存这些开关。';
        section.appendChild(note);
      }
    }

    const swatches = Array.from(document.querySelectorAll('#settings-drawer button'))
      .filter((button) => button.matches('.palette-btn') || button.title.includes('#'));
    for (const swatch of swatches) {
      swatch.disabled = true;
      swatch.title = `${swatch.title || swatch.getAttribute('aria-label') || '强调色'} · 当前后端未提供保存接口`;
      swatch.setAttribute('aria-disabled', 'true');
      swatch.style.cursor = 'not-allowed';
      swatch.style.opacity = '0.58';
    }
    const paletteSection = swatches[0]?.closest('section');
    if (paletteSection && !paletteSection.querySelector('[data-settings-unavailable]')) {
      const note = document.createElement('p');
      note.dataset.settingsUnavailable = 'true';
      note.className = 'text-[11px] text-on-surface-variant';
      note.textContent = '当前后端仅支持主题模式和语言，强调色暂不可保存。';
      paletteSection.appendChild(note);
    }

    const notificationToggle = document.querySelector('#notification-toggle, [role="switch"]');
    if (notificationToggle) {
      notificationToggle.disabled = true;
      notificationToggle.setAttribute('aria-disabled', 'true');
      notificationToggle.setAttribute('aria-checked', 'false');
      notificationToggle.title = '通知推送接口尚未接入，当前不会发送外部提醒';
      notificationToggle.style.cursor = 'not-allowed';
      notificationToggle.style.opacity = '0.58';
      const section = notificationToggle.closest('section');
      if (section && !section.querySelector('[data-settings-notification-unavailable]')) {
        const note = document.createElement('p');
        note.dataset.settingsNotificationUnavailable = 'true';
        note.className = 'text-[11px] text-on-surface-variant';
        note.textContent = '通知推送尚未接入保存接口，当前不会发送外部提醒。';
        section.appendChild(note);
      }
    }

    const reservedButtons = Array.from(document.querySelectorAll('#settings-drawer button'))
      .filter((button) => /导出离线备份|诊断日志入口/.test(button.textContent || ''));
    for (const button of reservedButtons) {
      button.disabled = true;
      button.setAttribute('aria-disabled', 'true');
      button.title = '当前后端尚未提供此功能';
      button.style.cursor = 'not-allowed';
      button.style.opacity = '0.58';
    }
  }

  function openSettingsOverlay({ addHistoryEntry = true } = {}) {
    if (settingsOverlayHost) return;

    settingsReturnRoute = activeRoute;
    settingsOpener = frame.contentDocument?.activeElement ?? null;
    settingsDraft = null;
    settingsPreferencesLoaded = false;
    settingsOverlayMobile = mobileQuery.matches;
    previousFrameInert = frame.inert;
    previousFrameAriaHidden = frame.getAttribute('aria-hidden');
    frame.inert = true;
    frame.setAttribute('aria-hidden', 'true');
    if (addHistoryEntry && window.location.hash !== '#/settings-drawer') {
      history.pushState(
        { settingsDrawer: true, returnRoute: settingsReturnRoute },
        '',
        '#/settings-drawer',
      );
    }
    settingsHistoryPending = window.location.hash === '#/settings-drawer';

    const host = document.createElement('div');
    host.id = 'ruanchuang-settings-overlay';
    Object.assign(host.style, {
      position: 'fixed',
      inset: '0',
      zIndex: '10000',
    });

    const backdrop = document.createElement('div');
    backdrop.setAttribute('aria-hidden', 'true');
    Object.assign(backdrop.style, {
      position: 'absolute',
      inset: '0',
      background: 'rgba(26, 27, 31, 0.32)',
      backdropFilter: 'blur(8px)',
    });
    backdrop.addEventListener('click', () => closeSettingsOverlay());

    const settingsFrame = document.createElement('iframe');
    settingsFrame.title = '系统偏好设置';
    settingsFrame.setAttribute('aria-label', '系统偏好设置');
    settingsFrame.setAttribute('scrolling', 'no');
    Object.assign(settingsFrame.style, {
      position: 'absolute',
      top: '0',
      right: '0',
      bottom: '0',
      width: settingsOverlayMobile ? '100vw' : 'min(420px, 100vw)',
      height: '100%',
      border: '0',
      background: 'transparent',
    });
    settingsFrame.src = screenFor('settings-drawer');
    host.append(backdrop, settingsFrame);
    previousBodyOverflow = document.body.style.overflow;
    document.body.style.overflow = 'hidden';
    document.body.appendChild(host);
    settingsOverlayHost = host;
    settingsOverlayFrame = settingsFrame;

    settingsFrame.addEventListener('load', async () => {
      if (settingsOverlayFrame !== settingsFrame) return;

      let settingsDocument;
      try {
        settingsDocument = settingsFrame.contentDocument;
      } catch (_) {
        closeSettingsOverlay();
        return;
      }

      const drawer = settingsDocument?.getElementById('settings-drawer');
      if (!drawer) {
        closeSettingsOverlay();
        const primaryDocument = frame.contentDocument;
        if (primaryDocument) showNotice(primaryDocument, '设置面板暂时无法打开，请稍后重试。');
        return;
      }

      drawer.setAttribute('role', 'dialog');
      drawer.setAttribute('aria-modal', 'true');
      if (!drawer.hasAttribute('aria-label') && !drawer.hasAttribute('aria-labelledby')) {
        drawer.setAttribute('aria-label', '系统偏好设置');
      }

      const saveButton = settingsDocument.querySelector('#save-settings-btn, #btn-save-settings');
      const editNameButton = Array.from(drawer.querySelectorAll('button')).find(
        (button) => /修改昵称|edit name/i.test(button.textContent),
      );
      if (editNameButton) editNameButton.id = 'settings-profile-edit-action';
      const logoutButton = Array.from(drawer.querySelectorAll('button')).find(
        (button) => /退出登录|log out/i.test(button.textContent),
      );
      if (logoutButton) logoutButton.id = 'settings-logout-action';
      const resetButton = Array.from(settingsDocument.querySelectorAll('button')).find(
        (button) => /恢复默认设置|restore default/i.test(button.textContent),
      );
      if (resetButton) resetButton.dataset.settingsReset = 'true';
      const storedUser = readStoredUser();
      if (storedUser.displayName) updateSettingsUserName(settingsDocument, storedUser.displayName);
      markUnsupportedSettingsControls(settingsDocument);
      setSettingsControlsDisabled(settingsDocument, true);

      const overlayStyles = settingsDocument.createElement('style');
      overlayStyles.id = 'router-settings-overlay-styles';
      overlayStyles.textContent = `
        html, body { background: transparent !important; overflow: hidden !important; }
        body * { visibility: hidden !important; }
        #settings-drawer, #settings-drawer * { visibility: visible !important; }
        #stitch-router-notice, #stitch-router-notice * { visibility: visible !important; }
        #settings-backdrop, #drawer-backdrop { display: none !important; }
        #settings-drawer { z-index: 10001 !important; }
        ${settingsOverlayMobile
          ? '#settings-drawer { position: fixed !important; left: 0 !important; right: 0 !important; bottom: 0 !important; width: 100% !important; max-width: none !important; }'
          : '#settings-drawer { position: fixed !important; inset: 0 !important; width: 100% !important; max-width: none !important; border-radius: 0 !important; }'}
      `;
      settingsDocument.head.appendChild(overlayStyles);

      try {
        if (settingsDraft == null) {
          const settings = await backendRequest('/settings');
          if (
            settingsOverlayFrame !== settingsFrame ||
            settingsFrame.contentDocument !== settingsDocument
          ) return;
          activeThemeMode = ['system', 'light', 'dark'].includes(settings?.themeMode)
            ? settings.themeMode
            : 'system';
          settingsDraft = {
            themeMode: activeThemeMode,
            locale: settings?.locale === 'en_US' ? 'en_US' : 'zh_CN',
          };
          settingsTokenHydrated = authHeaders().Authorization || '';
        }
        setThemeButtons(settingsDocument, settingsDraft.themeMode);
        setLocaleButtons(settingsDocument, settingsDraft.locale);
        settingsPreferencesLoaded = true;
        setSettingsControlsDisabled(settingsDocument, false);
        applyThemeMode(settingsDraft.themeMode);
      } catch (error) {
        if (
          settingsOverlayFrame !== settingsFrame ||
          settingsFrame.contentDocument !== settingsDocument
        ) return;
        if (saveButton) {
          saveButton.title = error.status === 401
            ? '登录后才能保存个人偏好'
            : '无法读取服务端偏好，保存已停用以避免覆盖已有设置';
        }
        showNotice(
          settingsDocument,
          error.status === 401
            ? '请先登录，才能读取和保存个人偏好。'
            : '无法读取服务端偏好；为避免覆盖已有设置，保存已停用。',
        );
      }

      settingsDocument.addEventListener('click', (event) => {
        const target = event.target;
        if (!drawer.contains(target)) {
          event.preventDefault();
          event.stopPropagation();
          closeSettingsOverlay();
          return;
        }

        const closeButton = target.closest?.('#close-drawer-btn, #btn-close-drawer');
        if (closeButton) {
          event.preventDefault();
          event.stopPropagation();
          closeSettingsOverlay();
          return;
        }

        if (target.closest?.('#settings-profile-cancel')) {
          event.preventDefault();
          event.stopPropagation();
          settingsDocument.getElementById('settings-profile-dialog')?.close();
          return;
        }

        const button = target.closest?.('button');
        if (!button) return;
        if (button.matches('[data-theme]')) {
          event.preventDefault();
          event.stopPropagation();
          if (!settingsPreferencesLoaded) return;
          const selected = button.dataset.theme === 'auto' ? 'system' : button.dataset.theme;
          settingsDraft.themeMode = selected;
          setThemeButtons(settingsDocument, selected);
          applyThemeMode(selected);
          return;
        }
        if (button.matches('[data-lang]')) {
          event.preventDefault();
          event.stopPropagation();
          if (!settingsPreferencesLoaded) return;
          settingsDraft.locale = button.dataset.lang === 'en-US' ? 'en_US' : 'zh_CN';
          setLocaleButtons(settingsDocument, settingsDraft.locale);
          return;
        }
        if (button.matches('[data-settings-reset]')) {
          event.preventDefault();
          event.stopPropagation();
          if (!settingsPreferencesLoaded) return;
          settingsDraft = { themeMode: 'system', locale: 'zh_CN' };
          setThemeButtons(settingsDocument, settingsDraft.themeMode);
          setLocaleButtons(settingsDocument, settingsDraft.locale);
          applyThemeMode(settingsDraft.themeMode);
          showNotice(settingsDocument, '已恢复默认选项；保存后会同步到账号。');
          return;
        }
        const action = apiActionForButton(button);
        if (action) {
          event.preventDefault();
          event.stopPropagation();
          runApiAction(action, settingsDocument, button);
          return;
        }
        const route = routeForButton(button);
        if (route === 'login') {
          event.preventDefault();
          event.stopPropagation();
          loginReturnRoute = settingsReturnRoute;
          closeSettingsOverlay({ fromHistory: true });
          history.replaceState({ route: loginReturnRoute }, '', `#/${loginReturnRoute}`);
          navigate('login');
        }
      }, true);

      settingsDocument.addEventListener('keydown', (event) => {
        if (event.key === 'Escape') {
          event.preventDefault();
          closeSettingsOverlay();
          return;
        }
        if (event.key === 'Tab') {
          const focusable = Array.from(drawer.querySelectorAll(
            'button:not([disabled]), input:not([disabled]), select:not([disabled]), a[href], [tabindex]:not([tabindex="-1"])',
          )).filter((element) => element.getClientRects().length > 0);
          const first = focusable[0];
          const last = focusable[focusable.length - 1];
          if (!first || !last) {
            event.preventDefault();
          } else if (event.shiftKey && settingsDocument.activeElement === first) {
            event.preventDefault();
            last.focus();
          } else if (!event.shiftKey && settingsDocument.activeElement === last) {
            event.preventDefault();
            first.focus();
          }
        }
      });

      settingsFrame.focus();
      settingsDocument.querySelector('#close-drawer-btn, #btn-close-drawer')?.focus({
        preventScroll: true,
      });
    });
  }

  function closeSettingsOverlay({ fromHistory = false } = {}) {
    const host = settingsOverlayHost;
    if (host) host.remove();
    settingsOverlayHost = null;
    settingsOverlayFrame = null;
    document.body.style.overflow = previousBodyOverflow;
    frame.inert = previousFrameInert;
    if (previousFrameAriaHidden == null) frame.removeAttribute('aria-hidden');
    else frame.setAttribute('aria-hidden', previousFrameAriaHidden);
    if (settingsDraft != null) applyThemeMode(activeThemeMode);
    settingsDraft = null;
    settingsPreferencesLoaded = false;
    settingsOpener?.focus?.({ preventScroll: true });
    settingsOpener = null;

    if (fromHistory) {
      settingsHistoryPending = false;
    } else if (settingsHistoryPending) {
      settingsHistoryPending = false;
      history.back();
    } else if (window.location.hash === '#/settings-drawer') {
      history.replaceState(null, '', `#/${settingsReturnRoute}`);
    }
  }

  function syncRouteFromHistory() {
    const route = routeFromHash();
    if (route === 'settings-drawer') {
      if (!settingsOverlayHost) openSettingsOverlay({ addHistoryEntry: false });
      return;
    }

    if (settingsOverlayHost) closeSettingsOverlay({ fromHistory: true });
    if (route === 'login') {
      const returnRoute = history.state?.login ? history.state.returnRoute : null;
      if (pages[returnRoute] && returnRoute !== 'login') loginReturnRoute = returnRoute;
    }
    if (route !== activeRoute) renderRoute(route);
  }

  function resizeSettingsOverlay() {
    if (!settingsOverlayFrame) return;
    settingsOverlayFrame.style.width = mobileQuery.matches ? '100vw' : 'min(420px, 100vw)';
    if (settingsOverlayMobile !== mobileQuery.matches) {
      settingsOverlayMobile = mobileQuery.matches;
      settingsOverlayFrame.src = screenFor('settings-drawer');
    }
  }

  function renderRoute(route) {
    activeRoute = pages[route] ? route : 'focus';
    applyCanvasSize();
    if (hasRenderedRoute) frame.classList.add('route-switching');
    frame.src = screenFor(activeRoute);
    frame.title = `时序智配 ${activeRoute}`;
    hasRenderedRoute = true;
  }

  function parentRouteFor(route) {
    const requested = history.state?.returnRoute;
    if (pages[requested] && requested !== route) return requested;
    return parentRoutes[route] || null;
  }

  function navigate(route, { replace = false, returnRoute = null } = {}) {
    if (!pages[route]) route = aliases[route] || 'focus';
    if (route === 'settings-drawer') {
      openSettingsOverlay({ addHistoryEntry: !replace });
      return;
    }
    if (route === 'login') {
      if (settingsOverlayHost) {
        loginReturnRoute = settingsReturnRoute;
        closeSettingsOverlay({ fromHistory: true });
        history.replaceState({ route: loginReturnRoute }, '', `#/${loginReturnRoute}`);
      } else if (activeRoute !== 'login') {
        loginReturnRoute = activeRoute;
      }
      const loginHash = '#/login';
      const state = { login: true, returnRoute: loginReturnRoute };
      if (replace) history.replaceState(state, '', loginHash);
      else if (window.location.hash !== loginHash) history.pushState(state, '', loginHash);
      renderRoute('login');
      return;
    }
    const hash = `#/${route}`;
    const requestedReturnRoute = pages[returnRoute] && returnRoute !== route
      ? returnRoute
      : activeRoute !== route
        ? activeRoute
        : parentRoutes[route];
    const state = parentRoutes[route]
      ? { route, returnRoute: requestedReturnRoute || parentRoutes[route] }
      : null;
    if (replace) history.replaceState(state, '', hash);
    else if (window.location.hash !== hash) history.pushState(state, '', hash);
    renderRoute(route);
  }

  function returnFromSecondary() {
    if (settingsOverlayHost) {
      closeSettingsOverlay();
      return;
    }
    if (activeRoute === 'login') {
      navigate(loginReturnRoute, { replace: true });
      return;
    }
    const parent = parentRouteFor(activeRoute);
    if (parent) {
      navigate(parent);
      return;
    }
    history.back();
  }

  // Secondary surfaces live inside an iframe, so their local history is not
  // the application's route state. Expose one parent-owned escape hatch for
  // close buttons, backdrops, Escape, and injected navigation affordances.
  window.__RUANCHUANG_RETURN__ = returnFromSecondary;

  function showNotice(document, message) {
    document.getElementById('stitch-router-notice')?.remove();
    const notice = document.createElement('div');
    notice.id = 'stitch-router-notice';
    notice.setAttribute('role', 'status');
    notice.setAttribute('aria-live', 'polite');
    notice.setAttribute('aria-atomic', 'true');
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

  function showAuthError(document, message) {
    const error = document.getElementById('auth-error');
    if (!error) {
      showNotice(document, message);
      return;
    }
    error.textContent = message;
    error.hidden = false;
  }

  function escapeHtml(value) {
    return String(value).replace(/[&<>"']/g, (character) => ({
      '&': '&amp;',
      '<': '&lt;',
      '>': '&gt;',
      '"': '&quot;',
      "'": '&#39;',
    })[character]);
  }

  function openProfileEditor(settingsDocument) {
    if (settingsDocument.getElementById('settings-profile-dialog')) return;
    const user = JSON.parse(localStorage.getItem('ruanchuang_user') || '{}');
    const accountSection = Array.from(settingsDocument.querySelectorAll('#settings-drawer section'))
      .find((section) => section.textContent.includes('账户与多用户管理'));
    const currentName = user.displayName || accountSection?.textContent.match(/林知行/)?.[0] || '';
    const dialog = settingsDocument.createElement('dialog');
    dialog.id = 'settings-profile-dialog';
    dialog.setAttribute('aria-labelledby', 'settings-profile-title');
    dialog.innerHTML = `
      <form method="dialog" class="profile-editor-form">
        <h2 id="settings-profile-title">修改昵称</h2>
        <label for="settings-profile-name">新昵称</label>
        <input id="settings-profile-name" maxlength="40" value="${escapeHtml(currentName)}" />
        <p id="settings-profile-error" role="alert" hidden></p>
        <div class="profile-editor-actions">
          <button id="settings-profile-cancel" type="button">取消</button>
          <button id="settings-profile-save" type="button">保存</button>
        </div>
      </form>
    `;
    const style = settingsDocument.createElement('style');
    style.textContent = `
      #settings-profile-dialog { width: min(420px, calc(100vw - 32px)); border: 1px solid #c0c8c7; border-radius: 12px; padding: 22px; color: #1a1b1f; background: #fff; box-shadow: 0 16px 40px rgba(16,27,29,.22); }
      #settings-profile-dialog::backdrop { background: rgba(16,27,29,.42); backdrop-filter: blur(4px); }
      .profile-editor-form { display: grid; gap: 10px; }
      .profile-editor-form h2 { margin: 0 0 4px; font-size: 18px; }
      .profile-editor-form label { font-size: 13px; font-weight: 600; }
      .profile-editor-form input { width: 100%; height: 44px; border: 1px solid #c0c8c7; border-radius: 8px; padding: 0 12px; background: #faf8fe; color: #1a1b1f; }
      .profile-editor-actions { display: flex; justify-content: flex-end; gap: 8px; margin-top: 8px; }
      .profile-editor-actions button { min-height: 40px; padding: 0 14px; border: 1px solid #c0c8c7; border-radius: 8px; background: #f4f3f8; color: #1a1b1f; }
      .profile-editor-actions #settings-profile-save { border-color: #005db5; background: #005db5; color: #fff; }
    `;
    settingsDocument.head.appendChild(style);
    settingsDocument.getElementById('settings-drawer').appendChild(dialog);
    dialog.showModal();
    dialog.querySelector('#settings-profile-name').focus();
  }

  function updateSettingsUserName(settingsDocument, displayName) {
    const drawer = settingsDocument.getElementById('settings-drawer');
    if (!drawer) return;
    const accountSection = Array.from(drawer.querySelectorAll('section'))
      .find((section) => section.textContent.includes('账户与多用户管理'));
    let nameNode = accountSection?.querySelector('[data-user-display-name]');
    if (!nameNode) {
      nameNode = Array.from(accountSection?.querySelectorAll('*') || [])
        .find((node) => node.children.length === 0 && node.textContent.trim() === '林知行');
      if (nameNode) nameNode.dataset.userDisplayName = 'true';
    }
    if (nameNode) nameNode.textContent = displayName;
  }

  function updateProfileDisplayName(profileDocument, displayName) {
    if (!profileDocument) return;
    const heading = profileDocument.querySelector('main h1');
    if (heading) {
      if (!heading.dataset.defaultDisplayName) {
        heading.dataset.defaultDisplayName = heading.textContent.trim();
      }
      heading.textContent = displayName || heading.dataset.defaultDisplayName;
    }

    const sidebarName = Array.from(profileDocument.querySelectorAll('aside span'))
      .find((node) => node.textContent.trim() === '知行');
    if (sidebarName) {
      if (!sidebarName.dataset.defaultDisplayName) {
        sidebarName.dataset.defaultDisplayName = sidebarName.textContent.trim();
      }
      sidebarName.textContent = displayName || sidebarName.dataset.defaultDisplayName;
    }
  }

  function readProfilePreferences() {
    try {
      const preferences = JSON.parse(
        localStorage.getItem('ruanchuang_profile_preferences') || '{}',
      );
      return {
        colorTone: ['teal', 'gray', 'jade'].includes(preferences.colorTone)
          ? preferences.colorTone
          : 'teal',
        compactMode: preferences.compactMode === true,
      };
    } catch (_) {
      return { colorTone: 'teal', compactMode: false };
    }
  }

  function saveProfilePreferences(preferences) {
    localStorage.setItem('ruanchuang_profile_preferences', JSON.stringify(preferences));
  }

  function applyProfilePreferences(profileDocument, preferences) {
    profileDocument.documentElement.dataset.profileTone = preferences.colorTone;
    profileDocument.documentElement.dataset.profileCompact = String(preferences.compactMode);
    for (const button of profileDocument.querySelectorAll('button[data-profile-tone]')) {
      const selected = button.dataset.profileTone === preferences.colorTone;
      button.setAttribute('aria-pressed', String(selected));
      button.classList.remove(
        'bg-primary',
        'text-on-primary',
        'bg-surface-container',
        'text-on-surface',
        'shadow-sm',
        'ring-2',
        'ring-primary',
      );
      button.classList.add(
        selected ? 'bg-primary' : 'bg-surface-container',
        selected ? 'text-on-primary' : 'text-on-surface',
      );
      if (selected) button.classList.add('shadow-sm', 'ring-2', 'ring-primary');
    }
    const compactMode = profileDocument.getElementById('profile-compact-mode');
    if (compactMode) compactMode.checked = preferences.compactMode;
  }

  function disableProfileControl(profileDocument, control, message) {
    if (!control) return;
    control.disabled = true;
    control.title = message;
    control.setAttribute('aria-disabled', 'true');
    const label = control.closest('label');
    if (label) {
      label.classList.remove('cursor-pointer');
      label.title = message;
      label.style.cursor = 'not-allowed';
      label.style.opacity = '0.58';
    }
    const section = control.closest('.bg-surface-container-lowest');
    if (!section || section.querySelector('[data-profile-unavailable]')) return;
    const note = profileDocument.createElement('p');
    note.dataset.profileUnavailable = 'true';
    note.className = 'text-[11px] text-on-surface-variant';
    note.textContent = message;
    section.appendChild(note);
  }

  function hydrateProfileView(profileDocument, route) {
    if (route !== 'profile') return;

    if (!profileDocument.getElementById('ruanchuang-profile-preferences')) {
      const styles = profileDocument.createElement('link');
      styles.id = 'ruanchuang-profile-preferences';
      styles.rel = 'stylesheet';
      styles.href = new URL('stitch/assets/profile-preferences.css', window.location.href).toString();
      profileDocument.head.appendChild(styles);
    }

    const user = readStoredUser();
    updateProfileDisplayName(profileDocument, user.displayName || '');

    for (const link of profileDocument.querySelectorAll('aside nav a[data-path]')) {
      const label = link.querySelector('span.truncate')?.textContent.trim();
      if (label) {
        link.setAttribute('aria-label', label);
        link.title = label;
      }
    }

    const unavailableActions = new Map([
      ['添加应用', '应用静默名单尚未接入保存接口，当前无法添加拦截规则。'],
      ['立即绑定', '日历提供方授权接口尚未开放，当前无法绑定。'],
      ['数字工牌', '数字工牌尚未接入账号凭证服务，当前不会生成虚假凭证。'],
      ['导出加密数据副本', '后端暂未提供完整加密数据导出接口，当前不会生成不完整副本。'],
      ['账号安全审计', '账号安全审计服务暂未接入，当前无法读取审计记录。'],
    ]);
    const toneValues = new Map([
      ['深青原色', 'teal'],
      ['沉静冷灰', 'gray'],
      ['墨玉青绿', 'jade'],
    ]);
    for (const button of profileDocument.querySelectorAll('button')) {
      const label = button.textContent.trim().replace(/\s+/g, ' ');
      if (label.includes('导出周报')) button.id = 'profile-weekly-export';
      for (const [toneLabel, toneValue] of toneValues) {
        if (label.includes(toneLabel)) button.dataset.profileTone = toneValue;
      }
      for (const [actionLabel, notice] of unavailableActions) {
        if (label.includes(actionLabel)) button.dataset.unavailableNotice = notice;
      }
    }

    const compactLabel = Array.from(profileDocument.querySelectorAll('label'))
      .find((label) => label.textContent.includes('超紧凑高密度模式'));
    const compactInput = compactLabel?.querySelector('input[type="checkbox"]');
    if (compactInput) compactInput.id = 'profile-compact-mode';
    const preferences = readProfilePreferences();
    applyProfilePreferences(profileDocument, preferences);

    const backendUnavailable = '当前后端没有此项保存接口，开关暂不可用。';
    disableProfileControl(profileDocument, profileDocument.querySelector('input[type="range"]'), backendUnavailable);
    disableProfileControl(
      profileDocument,
      Array.from(profileDocument.querySelectorAll('input[type="checkbox"]'))
        .find((input) => input !== compactInput && input.closest('label')?.textContent.includes('自动开启下一个专注时序')),
      backendUnavailable,
    );
    disableProfileControl(profileDocument, profileDocument.querySelector('select'), backendUnavailable);
    for (const input of profileDocument.querySelectorAll('input[type="checkbox"]')) {
      const label = input.closest('label')?.textContent || '';
      if (label.includes('系统级免打扰联动') || label.includes('浏览器 Web Push')) {
        disableProfileControl(profileDocument, input, '通知和系统免打扰接口尚未接入，当前不会发送或拦截通知。');
      }
    }

    for (const row of profileDocument.querySelectorAll('main div.flex.items-center.justify-between')) {
      if (!/Google Calendar|Outlook 365/.test(row.textContent)) continue;
      const status = Array.from(row.children)
        .find((node) => node.tagName === 'SPAN' && node.textContent.includes('已同步'));
      if (!status) continue;
      status.textContent = '暂未接入';
      status.classList.remove('bg-tertiary-fixed', 'text-on-tertiary-fixed');
      status.classList.add('bg-surface-container-high', 'text-on-surface-variant');
    }
  }

  function prepareRouteControls(document, route) {
    if (route === 'schedule') {
      const dateLabel = Array.from(document.querySelectorAll('span, div'))
        .find((node) => /^(?:当前日期|\d{4}年\d+月\d+日 星期[一二三四五六日])$/.test(node.textContent.trim()));
      if (dateLabel) {
        const now = new Date();
        const weekdays = ['日', '一', '二', '三', '四', '五', '六'];
        dateLabel.textContent = `${now.getFullYear()}年${now.getMonth() + 1}月${now.getDate()}日 星期${weekdays[now.getDay()]}`;
      }
      const rescueSheet = document.getElementById('rescue-sheet');
      if (rescueSheet && mobileQuery.matches) {
        rescueSheet.hidden = true;
        rescueSheet.setAttribute('aria-hidden', 'true');
      }

      const rescuePreviewLabel = Array.from(document.querySelectorAll('span'))
        .find((node) => node.textContent.trim() === '推荐救援方案预览');
      const rescuePreview = rescuePreviewLabel?.closest('.flex.flex-col.gap-2');
      if (rescuePreview) {
        const summary = document.createElement('p');
        summary.className = 'text-xs text-on-surface-variant leading-relaxed';
        summary.textContent = '救援方案必须根据实际任务、硬截止时间和服务端日程生成。';
        const action = document.createElement('button');
        action.id = 'schedule-create-urgent-task';
        action.type = 'button';
        action.className = 'w-full min-h-11 rounded-lg bg-error text-on-error text-sm font-semibold';
        action.textContent = '填写紧急任务并生成救援方案';
        rescuePreview.replaceChildren(summary, action);
      }

      let undoButton = document.getElementById('mobile-rescue-undo') ||
        Array.from(document.querySelectorAll('button'))
          .find((button) => button.textContent.includes('撤销上次自动调度'));
      if (!undoButton && mobileQuery.matches) {
        const rescueEntry = Array.from(document.querySelectorAll('button'))
          .find((button) => button.textContent.includes('查看救援方案'));
        if (rescueEntry) {
          undoButton = document.createElement('button');
          undoButton.id = 'mobile-rescue-undo';
          undoButton.type = 'button';
          undoButton.className = 'mt-2 min-h-10 w-full rounded-lg bg-surface-container text-on-surface-variant text-xs font-semibold';
          undoButton.textContent = '撤销上次救援';
          rescueEntry.insertAdjacentElement('afterend', undoButton);
        }
      }
      if (undoButton) {
        undoButton.id = 'schedule-rescue-undo';
        const hasSnapshot = readRescueSnapshots().length > 0;
        undoButton.disabled = !hasSnapshot;
        undoButton.title = hasSnapshot
          ? '撤销本账号在此浏览器最近应用的救援方案'
          : '此浏览器没有可撤销的服务端快照';
        if (!hasSnapshot && mobileQuery.matches) {
          const note = document.createElement('span');
          note.id = 'mobile-rescue-undo-note';
          note.className = 'mt-1 block text-[11px] text-on-surface-variant';
          note.textContent = '暂无可撤销的救援快照';
          undoButton.insertAdjacentElement('afterend', note);
        }
      }

      if (mobileQuery.matches) {
        const dayButtons = Array.from(document.querySelectorAll('button'))
          .filter((button) => /^[一二三四五六日]\s*\d+$/.test(button.textContent.trim()));
        for (const button of dayButtons) {
          button.dataset.scheduleDay = button.textContent.trim();
        }
        const viewButtons = Array.from(document.querySelectorAll('button'))
          .filter((button) => ['日', '周', '列表'].includes(button.textContent.trim()));
        for (const button of viewButtons) {
          button.dataset.scheduleView = button.textContent.trim();
        }
      }
    }

    if (route === 'urgent-task') {
      const previousTask = rescueState?.urgentTask;
      if (previousTask) {
        const titleInput = document.getElementById('urgent-task-title-input');
        if (titleInput) titleInput.value = previousTask.title || '';
        const deadlineInput = document.getElementById('urgent-task-deadline-input');
        const previousDue = previousTask.due ? new Date(previousTask.due) : null;
        if (deadlineInput && previousDue && !Number.isNaN(previousDue.getTime())) {
          const localDue = new Date(
            previousDue.getTime() - previousDue.getTimezoneOffset() * 60000,
          );
          deadlineInput.value = localDue.toISOString().slice(0, 16);
          document.defaultView.updateUrgentTaskDeadline?.();
        }
        const durationMinutes = Number(previousTask.durationMinutes || 30);
        const durationButton = Array.from(
          document.querySelectorAll('#duration-selector .duration-pill'),
        ).find((button) => Number(button.textContent.match(/\d+/)?.[0]) === durationMinutes);
        if (durationButton) document.defaultView.selectDuration?.(durationButton, `${durationMinutes}m`);
        const tagButton = Array.from(document.querySelectorAll('.tag-pill'))
          .find((button) => button.querySelector('span:last-child')?.textContent.trim() === previousTask.tag);
        if (tagButton) document.defaultView.selectTag?.(tagButton);
        const level = previousTask.load === 'high' ? 5 : previousTask.load === 'medium' ? 3 : 1;
        document.defaultView.setLoadLevel?.(level);
        const hardLock = Array.from(document.querySelectorAll('[role="switch"]'))
          .find((button) => button.parentElement?.textContent.includes('硬约束防挤压锁定'));
        const checked = hardLock?.getAttribute('aria-checked') === 'true';
        if (hardLock && Boolean(previousTask.hardDeadline) !== checked) {
          document.defaultView.toggleSwitch?.(hardLock);
        }
      }

      const tagButton = Array.from(document.querySelectorAll('button')).find((button) =>
        button.querySelector('.material-symbols-outlined')?.textContent.trim() === 'add' &&
        !button.textContent.trim(),
      );
      if (tagButton) {
        tagButton.dataset.unavailableNotice = '自定义任务标签尚未接入账号偏好保存。';
        tagButton.title = '自定义任务标签暂不可用';
      }

      const customDuration = Array.from(
        document.querySelectorAll('#duration-selector button'),
      ).find((button) => button.textContent.includes('自定义'));
      if (customDuration) {
        customDuration.disabled = true;
        customDuration.title = '请从当前提供的时长中选择';
        customDuration.setAttribute('aria-disabled', 'true');
        const durationGroup = customDuration.closest('#duration-selector')?.parentElement;
        if (durationGroup && !durationGroup.querySelector('[data-route-unavailable]')) {
          const note = document.createElement('p');
          note.dataset.routeUnavailable = 'true';
          note.className = 'text-[11px] text-on-surface-variant';
          note.textContent = '自定义时长暂不可用，请从预设时长中选择。';
          durationGroup.appendChild(note);
        }
      }

      const elasticSwitch = Array.from(document.querySelectorAll('[role="switch"]'))
        .find((control) => control.parentElement?.textContent.includes('排期灵活性微调'));
      if (elasticSwitch) {
        elasticSwitch.disabled = true;
        elasticSwitch.title = '当前救援接口不支持此项弹性约束';
        elasticSwitch.setAttribute('aria-disabled', 'true');
        elasticSwitch.style.cursor = 'not-allowed';
        elasticSwitch.style.opacity = '0.58';
        const switchGroup = elasticSwitch.parentElement?.parentElement;
        if (switchGroup && !switchGroup.querySelector('[data-route-unavailable]')) {
          const note = document.createElement('p');
          note.dataset.routeUnavailable = 'true';
          note.className = 'text-[11px] text-on-surface-variant';
          note.textContent = '弹性重排偏好尚未接入救援算法。';
          switchGroup.appendChild(note);
        }
      }
    }

    if (route === 'create-schedule') {
      const dateLabel = document.getElementById('schedule-date-label');
      if (dateLabel) {
        const date = new Date();
        const weekdays = ['日', '一', '二', '三', '四', '五', '六'];
        dateLabel.textContent = `${date.getFullYear()}年${date.getMonth() + 1}月${date.getDate()}日 周${weekdays[date.getDay()]}`;
      }
      const switches = document.querySelectorAll('[role="switch"]');
      for (const control of switches) {
        control.disabled = true;
        control.title = '当前排期接口不支持保存此项约束';
        control.setAttribute('aria-disabled', 'true');
        control.style.cursor = 'not-allowed';
        control.style.opacity = '0.58';
      }
      const switchGroup = switches[0]?.closest('.bg-surface-container-low');
      if (switchGroup && !switchGroup.querySelector('[data-route-unavailable]')) {
        const note = document.createElement('p');
        note.dataset.routeUnavailable = 'true';
        note.className = 'text-[11px] text-on-surface-variant';
        note.textContent = '排期弹性和硬约束标记暂未提供服务端字段。';
        switchGroup.appendChild(note);
      }
    }
  }

  function formatPlanClock(time) {
    const hour = Number(time?.hour || 0);
    const minute = Number(time?.minute || 0);
    return `${String(hour).padStart(2, '0')}:${String(minute).padStart(2, '0')}`;
  }

  function formatRescueEntryTime(entry, fallbackDay) {
    return `${entry.day || fallbackDay} ${formatPlanClock(entry.time)}`;
  }

  function buildRescueDetailRows(document, option, dayEntries, urgentTask, day) {
    const affectedIds = new Set(option.affectedEntries || []);
    if (urgentTask?.id) affectedIds.add(urgentTask.id);
    const currentById = new Map(dayEntries.map((entry) => [entry.id, entry]));
    const plannedById = new Map((option.plannedEntries || []).map((entry) => [entry.id, entry]));
    const rows = [];

    for (const id of affectedIds) {
      const before = currentById.get(id);
      const after = plannedById.get(id);
      if (!before && !after && id !== urgentTask?.id) continue;
      const row = document.createElement('div');
      row.className = 'flex flex-col p-4 rounded-lg bg-surface-container-low gap-1';
      const name = document.createElement('span');
      name.className = 'text-sm font-semibold text-on-surface';
      name.textContent = before?.title || after?.title || urgentTask?.title || id;
      const timing = document.createElement('span');
      timing.className = 'text-xs text-on-surface-variant';
      timing.textContent = before && after
        ? formatRescueEntryTime(before, day) === formatRescueEntryTime(after, day)
          ? `保持原排期 ${formatRescueEntryTime(after, day)}`
          : `原排期 ${formatRescueEntryTime(before, day)} → 新排期 ${formatRescueEntryTime(after, day)}`
        : before
          ? `原排期 ${formatRescueEntryTime(before, day)} · 服务端方案未保留此项目`
          : after
            ? `新增排期 ${formatRescueEntryTime(after, day)}`
            : '服务端未返回时段';
      row.append(name, timing);
      rows.push(row);
    }
    return rows;
  }

  function hydrateMobileRescueComparisonView(document, options, dayEntries, urgentTask, dueDate) {
    const cards = Array.from(document.querySelectorAll('.plan-card'));
    const pageTitle = document.querySelector('header h1');
    if (pageTitle) pageTitle.textContent = '救援方案';
    const strategyLabels = {
      protectDeadline: '截止优先',
      protectRecovery: '恢复优先',
      minimizeChanges: '最小变动',
    };
    const recommendationIndex = Math.max(
      options.findIndex((option) => option.recommended),
      0,
    );
    const minutesRemaining = dueDate
      ? Math.ceil((dueDate.getTime() - Date.now()) / 60000)
      : null;

    if (dueDate) {
      const countdown = document.getElementById('rescue-task-countdown');
      if (countdown) {
        countdown.textContent = minutesRemaining <= 0
          ? '已过截止时间'
          : `${Math.floor(minutesRemaining / 60)}h ${minutesRemaining % 60}m`;
      }
      const due = document.getElementById('rescue-task-due');
      if (due) {
        due.textContent = `${localIsoDate(dueDate)} ${dueDate.toLocaleTimeString('zh-CN', {
          hour: '2-digit',
          minute: '2-digit',
        })}`;
      }
    }
    const duration = document.getElementById('rescue-task-duration');
    if (duration && urgentTask?.durationMinutes != null) {
      duration.textContent = `${urgentTask.durationMinutes} 分钟`;
    }
    const status = document.querySelector('[data-rescue-status]');
    if (status) status.textContent = `服务端已生成 ${options.length} 个方案`;
    const safeguard = Array.from(document.querySelectorAll('span'))
      .find((node) => node.textContent.includes('双重确认'));
    if (safeguard) safeguard.textContent = '服务端快照 · 可撤销';
    const summary = Array.from(document.querySelectorAll('main > div > section p'))
      .find((node) => node.textContent.includes('服务端已针对当前日程生成救援方案'));
    if (summary) {
      summary.textContent = '方案数据、风险与时段均来自服务端。写入后可从日历页撤销。';
    }

    for (const [index, card] of cards.entries()) {
      const option = options[index];
      const tab = document.querySelector(`[data-rescue-tab="${index}"]`);
      if (!option) {
        card.hidden = true;
        if (tab) tab.hidden = true;
        continue;
      }
      card.hidden = false;
      card.dataset.rescueOptionId = option.id;
      card.dataset.rescueRecommended = String(Boolean(option.recommended));
      if (tab) {
        tab.hidden = false;
        tab.title = option.title;
        tab.setAttribute('aria-pressed', String(index === recommendationIndex));
        const label = tab.querySelector('[data-rescue-tab-title]');
        if (label) label.textContent = `方案 ${String.fromCharCode(65 + index)}`;
      }
      const letter = String.fromCharCode(65 + index);
      const heading = card.querySelector('h3');
      if (heading) heading.textContent = `方案 ${letter} · ${option.title}`;
      const rationale = card.querySelector('p');
      if (rationale) rationale.textContent = `${option.rationale || ''} ${option.tradeoff || ''}`.trim();
      const recommendation = card.querySelector('[data-rescue-recommendation]');
      if (recommendation) {
        recommendation.textContent = option.recommended ? '服务端推荐' : '备选策略';
        recommendation.className = option.recommended
          ? 'inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-[11px] font-semibold bg-secondary-fixed text-on-secondary-fixed'
          : 'inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-[11px] font-semibold bg-surface-container-high text-on-surface-variant';
      }
      const risk = card.querySelector('[data-rescue-risk]');
      const overdueRisk = Number(option.overdueRisk || 0);
      const riskPercent = Math.round(overdueRisk <= 1 ? overdueRisk * 100 : overdueRisk);
      if (risk) risk.textContent = `逾期风险 ${riskPercent}%`;

      const urgentEntry = option.plannedEntries?.find((entry) =>
        entry.id === urgentTask?.id || entry.title === urgentTask?.title,
      );
      let completionTime = '待排程';
      let completionStatus = '服务端尚未返回时段';
      if (urgentEntry) {
        const start = new Date(`${urgentEntry.day || localIsoDate(dueDate || new Date())}T${formatPlanClock(urgentEntry.time)}:00`);
        const finish = new Date(start.getTime() + Number(urgentTask?.durationMinutes || 0) * 60000);
        completionTime = finish.toLocaleTimeString('zh-CN', { hour: '2-digit', minute: '2-digit' });
        if (dueDate) {
          const difference = Math.round((dueDate.getTime() - finish.getTime()) / 60000);
          completionStatus = difference >= 0 ? `提前 ${difference} 分钟` : `超过截止 ${Math.abs(difference)} 分钟`;
        }
      }
      const completion = card.querySelector('[data-rescue-completion]');
      if (completion) completion.textContent = completionTime;
      const completionLabel = card.querySelector('[data-rescue-completion-status]');
      if (completionLabel) completionLabel.textContent = completionStatus;
      const recovery = card.querySelector('[data-rescue-recovery]');
      if (recovery) recovery.textContent = `${Number(option.recoveryMinutes || 0)} 分钟`;
      const moved = Number(option.movedEntryCount || 0);
      const retained = Math.max(dayEntries.length - moved, 0);
      const movedLabel = card.querySelector('[data-rescue-moved]');
      if (movedLabel) movedLabel.textContent = `${moved} 项`;
      const retainedLabel = card.querySelector('[data-rescue-retained]');
      if (retainedLabel) retainedLabel.textContent = `${retained} 项未调整`;

      const tradeoff = card.querySelector('[data-rescue-tradeoff]');
      if (tradeoff) tradeoff.textContent = option.tradeoff || option.rationale || '服务端未提供说明。';
      const timeline = card.querySelector('[data-rescue-timeline]');
      if (timeline) {
        const title = document.createElement('p');
        title.className = 'text-[11px] font-label text-outline';
        title.textContent = '服务端返回的计划顺序';
        const list = document.createElement('ol');
        list.className = 'flex flex-col gap-1.5 text-xs text-on-surface';
        const entries = [...(option.plannedEntries || [])].sort((left, right) =>
          `${left.day || ''} ${formatPlanClock(left.time)}`.localeCompare(`${right.day || ''} ${formatPlanClock(right.time)}`),
        );
        for (const entry of entries) {
          const item = document.createElement('li');
          item.className = 'flex min-w-0 gap-2';
          const time = document.createElement('span');
          time.className = 'font-mono font-semibold text-primary shrink-0';
          time.textContent = formatPlanClock(entry.time);
          const name = document.createElement('span');
          name.className = 'min-w-0';
          name.textContent = `${entry.day && entry.day !== rescueState.day ? `${entry.day} ` : ''}${entry.title || '未命名任务'}`;
          item.append(time, name);
          list.appendChild(item);
        }
        timeline.replaceChildren(title, list);
      }
      const applyButton = card.querySelector('[data-rescue-apply]');
      if (applyButton) {
        applyButton.dataset.rescueOptionId = option.id;
        applyButton.setAttribute('aria-label', `采用方案 ${letter}：${option.title}`);
        const label = applyButton.querySelector('span:last-child');
        if (label) label.textContent = '采用此方案并写入日程';
      }
    }

    const recommended = options.find((option) => option.recommended) || options[0];
    const selectedRecommendationIndex = Math.max(options.indexOf(recommended), 0);
    document.defaultView.switchPlan?.(String.fromCharCode(97 + selectedRecommendationIndex));
    const detailSection = document.querySelector('[data-rescue-details]');
    const detailRows = detailSection?.querySelector('[data-rescue-details-list]');
    if (detailRows && recommended) {
      const moved = Number(recommended.movedEntryCount || 0);
      const retained = Math.max(dayEntries.length - moved, 0);
      const heading = detailSection.querySelector('[data-rescue-details-heading]');
      const summary = detailSection.querySelector('[data-rescue-details-summary]');
      if (heading) heading.textContent = `执行明细 · 方案 ${String.fromCharCode(65 + selectedRecommendationIndex)}：${recommended.title}`;
      if (summary) summary.textContent = `${moved} 项调整 · ${retained} 项未调整`;
      detailRows.replaceChildren(...buildRescueDetailRows(document, recommended, dayEntries, urgentTask, rescueState.day));
    }
  }

  function hydrateRescueComparisonView(comparisonDocument) {
    if (!rescueState?.options?.length) {
      navigate('schedule', { replace: true });
      showNotice(window.document, '方案数据已失效，请重新生成服务端救援方案。');
      return false;
    }

    const { options, currentEntries = [], urgentTask } = rescueState;
    const dayEntries = currentEntries.filter((entry) => entry.day === rescueState.day);
    const isMobileComparison = comparisonDocument.querySelector('.plan-card') != null;
    const taskHeading = comparisonDocument.getElementById('rescue-task-title') ||
      Array.from(comparisonDocument.querySelectorAll('h2'))
        .find((node) => node.textContent.includes('生产网关鉴权补丁上线'));
    if (taskHeading && urgentTask?.title) taskHeading.textContent = urgentTask.title;
    const headerCopy = Array.from(comparisonDocument.querySelectorAll('p'))
      .find((node) => node.textContent.includes('调度引擎在不突破硬约束') ||
        node.textContent.includes('服务端已针对当前日程生成救援方案'));
    if (headerCopy) {
      headerCopy.textContent = `服务端已针对当前日程生成 ${options.length} 个可比较方案。方案差异和推荐结果以下方数据为准。`;
    }
    const dueDate = urgentTask?.due ? new Date(urgentTask.due) : null;

    if (isMobileComparison) {
      hydrateMobileRescueComparisonView(comparisonDocument, options, dayEntries, urgentTask, dueDate);
      for (const button of comparisonDocument.querySelectorAll('button')) {
        if (button.getAttribute('aria-label') === '更多选项') {
          button.id = 'rescue-view-details';
          button.setAttribute('aria-label', '查看执行明细');
          button.title = '查看执行明细';
          const icon = button.querySelector('.material-symbols-outlined');
          if (icon) icon.textContent = 'format_list_bulleted';
        }
      }
      return true;
    }

    const durationLabel = Array.from(comparisonDocument.querySelectorAll('span'))
      .find((node) => node.textContent.trim() === '预估净耗时');
    const durationValue = durationLabel?.parentElement?.querySelector('.text-base');
    if (durationValue && urgentTask?.durationMinutes != null) {
      durationValue.textContent = `${urgentTask.durationMinutes} 分钟`;
    }
    const dueLabel = Array.from(comparisonDocument.querySelectorAll('span'))
      .find((node) => node.textContent.trim() === '硬截止时间');
    const dueValue = dueLabel?.parentElement?.querySelector('.text-base');
    if (dueValue && dueDate) {
      dueValue.textContent = `${localIsoDate(dueDate)} ${dueDate.toLocaleTimeString('zh-CN', {
        hour: '2-digit',
        minute: '2-digit',
      })}`;
    }
    const countdownLabel = Array.from(comparisonDocument.querySelectorAll('span'))
      .find((node) => node.textContent.trim() === '距离截止倒计时');
    const countdownValue = countdownLabel?.parentElement?.querySelector('.text-base');
    if (countdownValue && dueDate) {
      const minutesRemaining = Math.max(0, Math.ceil((dueDate.getTime() - Date.now()) / 60000));
      countdownValue.textContent = `${Math.floor(minutesRemaining / 60)}h ${minutesRemaining % 60}m`;
    }
    const priorityBadge = Array.from(comparisonDocument.querySelectorAll('span'))
      .find((node) => node.textContent.trim() === 'P0 核心中断');
    if (priorityBadge) {
      priorityBadge.textContent = Number(urgentTask?.priority || 0) >= 5
        ? 'P0 紧急插入'
        : 'P1 紧急插入';
    }

    const cards = Array.from(comparisonDocument.querySelectorAll('main .grid > div'))
      .filter((card) => card.querySelector('h4')?.textContent.includes('方案'));
    const strategyLabels = {
      protectDeadline: 'DEADLINE FIRST',
      protectRecovery: 'RECOVERY FIRST',
      minimizeChanges: 'MINIMAL DISRUPTION',
    };

    for (const [index, card] of cards.entries()) {
      const option = options[index];
      if (!option) {
        card.hidden = true;
        continue;
      }
      card.hidden = false;
      card.dataset.rescueOptionId = option.id;
      card.classList.remove('border-2', 'border-secondary/40');
      if (option.recommended) card.classList.add('border-2', 'border-secondary/40');

      const heading = card.querySelector('h4');
      if (heading) heading.textContent = `方案 ${String.fromCharCode(65 + index)}：${option.title}`;
      const strategy = heading?.parentElement?.querySelector('span');
      if (strategy) strategy.textContent = strategyLabels[option.strategy] || option.strategy;
      const rationale = heading?.parentElement?.parentElement?.querySelector('p');
      if (rationale) rationale.textContent = `${option.rationale || ''} ${option.tradeoff || ''}`.trim();

      card.querySelector('[data-rescue-recommended], .absolute.-top-3')?.remove();
      if (option.recommended) {
        const badge = comparisonDocument.createElement('div');
        badge.dataset.rescueRecommended = 'true';
        badge.className = 'absolute -top-3 left-6 px-3 py-0.5 rounded-full bg-secondary text-on-secondary text-xs font-bold shadow-sm';
        badge.textContent = `服务端推荐 · ${option.title}`;
        card.classList.add('relative');
        card.prepend(badge);
      }

      const tags = card.querySelector('.flex.flex-wrap.mb-5');
      if (tags) {
        tags.replaceChildren();
        const labels = [
          option.recommended ? '服务端推荐' : '备选策略',
          Number(option.movedEntryCount || 0) === 0
            ? '不移动原排期'
            : `移动 ${Number(option.movedEntryCount || 0)} 项`,
          Number(option.hardIssueCount || 0) === 0
            ? '无硬冲突'
            : `${Number(option.hardIssueCount)} 个硬冲突`,
        ];
        for (const label of labels) {
          const tag = comparisonDocument.createElement('span');
          tag.className = 'px-2 py-0.5 rounded text-[11px] font-medium bg-surface-container-high text-on-surface-variant';
          tag.textContent = label;
          tags.appendChild(tag);
        }
      }

      const metricGrid = Array.from(card.querySelectorAll('.grid'))
        .find((grid) => grid.classList.contains('grid-cols-2') && grid.children.length >= 5);
      const metrics = metricGrid ? Array.from(metricGrid.children) : [];
      const setMetric = (metricIndex, value) => {
        const node = metrics[metricIndex]?.querySelector('.font-bold');
        if (node) node.textContent = value;
      };
      setMetric(0, `1 项 / ${Number(option.movedEntryCount || 0)} 项`);
      setMetric(1, `${Math.max(dayEntries.length - Number(option.movedEntryCount || 0), 0)} 项未改动`);
      const overdueRisk = Number(option.overdueRisk || 0);
      setMetric(2, `${Math.round(overdueRisk <= 1 ? overdueRisk * 100 : overdueRisk)}%`);
      setMetric(3, `${Number(option.recoveryMinutes || 0)} 分钟`);

      const urgentEntry = option.plannedEntries?.find((entry) =>
        entry.id === urgentTask?.id || entry.title === urgentTask?.title,
      );
      const completion = urgentEntry
        ? (() => {
            const [hour, minute] = formatPlanClock(urgentEntry.time).split(':').map(Number);
            const end = hour * 60 + minute + Number(urgentTask?.durationMinutes || 0);
            return `${String(Math.floor(end / 60) % 24).padStart(2, '0')}:${String(end % 60).padStart(2, '0')}`;
          })()
        : '待排程';
      const footerValue = metrics[4]?.querySelector('.font-headline');
      if (footerValue) footerValue.textContent = completion;

      const timeline = card.querySelector('.mb-6');
      if (timeline) {
        const title = comparisonDocument.createElement('p');
        title.className = 'text-[11px] font-label text-outline mb-2';
        title.textContent = '服务端返回的计划顺序';
        const list = comparisonDocument.createElement('ol');
        list.className = 'flex flex-col gap-1.5 text-xs text-on-surface';
        const entries = [...(option.plannedEntries || [])].sort((left, right) =>
          formatPlanClock(left.time).localeCompare(formatPlanClock(right.time)),
        );
        for (const entry of entries) {
          const item = comparisonDocument.createElement('li');
          item.className = 'flex gap-2';
          const time = comparisonDocument.createElement('span');
          time.className = 'font-mono font-semibold text-primary shrink-0';
          time.textContent = formatPlanClock(entry.time);
          const name = comparisonDocument.createElement('span');
          name.textContent = entry.title || '未命名任务';
          item.append(time, name);
          list.appendChild(item);
        }
        timeline.replaceChildren(title, list);
      }

      const applyButton = Array.from(card.querySelectorAll('button'))
        .find((button) => button.textContent.includes('采用此方案'));
      if (applyButton) {
        applyButton.dataset.rescueOptionId = option.id;
        applyButton.setAttribute('aria-label', `采用方案 ${String.fromCharCode(65 + index)}：${option.title}`);
      }
    }

    const strategyHeading = Array.from(comparisonDocument.querySelectorAll('h3'))
      .find((heading) => heading.textContent.includes('智能救援策略权衡矩阵'));
    if (strategyHeading) strategyHeading.textContent = `${options.length} 种服务端救援策略`;
    const conflictSummary = Array.from(comparisonDocument.querySelectorAll('span'))
      .find((node) => node.textContent.includes('所有方案均已通过硬碰撞物理检查'));
    if (conflictSummary) {
      const hardIssues = options.reduce((total, option) => total + Number(option.hardIssueCount || 0), 0);
      conflictSummary.textContent = hardIssues === 0
        ? '服务端硬约束检查完成：无硬冲突'
        : `服务端检测到 ${hardIssues} 个硬冲突`;
    }

    const detailHeading = Array.from(comparisonDocument.querySelectorAll('h3'))
      .find((heading) => heading.textContent.includes('执行调度详情'));
    const detailSection = detailHeading?.closest('section');
    const details = detailSection?.querySelector('[data-rescue-details-list]');
    if (details) {
      detailSection.dataset.rescueDetails = 'true';
      const recommended = options.find((option) => option.recommended) || options[0];
      details.replaceChildren(...buildRescueDetailRows(
        comparisonDocument,
        recommended,
        dayEntries,
        urgentTask,
        rescueState.day,
      ));
      if (detailHeading) {
        detailHeading.textContent = `执行调度详情与受影响项目清单（${recommended.title}）`;
      }
      const detailCopy = detailHeading?.parentElement?.querySelector('p');
      if (detailCopy) detailCopy.textContent = recommended.tradeoff || recommended.rationale || '';
    }

    const recommended = options.find((option) => option.recommended) || options[0];
    const movedCount = Number(recommended?.movedEntryCount || 0);
    const unchangedCount = Math.max(dayEntries.length - movedCount, 0);
    const unchangedSummary = comparisonDocument.querySelector('[data-rescue-summary-unchanged]');
    const movedSummary = comparisonDocument.querySelector('[data-rescue-summary-moved]');
    if (unchangedSummary) unchangedSummary.textContent = `未调整日程：${unchangedCount} 项`;
    if (movedSummary) movedSummary.textContent = `服务端调整：${movedCount} 项`;

    const detailButtons = Array.from(comparisonDocument.querySelectorAll('button'));
    for (const button of detailButtons) {
      const label = button.textContent.trim();
      if (label.includes('查看细节')) button.id = 'rescue-view-details';
      if (label.includes('调整时长')) button.id = 'rescue-adjust-duration';
      if (label.includes('比较更多微调参数')) {
        button.dataset.unavailableNotice = '当前后端只提供三种固定救援策略，尚未开放自定义参数比较。';
      }
    }
    return true;
  }

  function setActionBusy(button, busy, label) {
    if (!button) return;
    if (busy) {
      button.dataset.originalHtml = button.innerHTML;
      button.disabled = true;
      button.innerHTML = `<span class="material-symbols-outlined animate-spin">progress_activity</span><span>${label}</span>`;
      button.classList.add('opacity-70', 'pointer-events-none');
      return;
    }
    if (button.dataset.originalHtml) button.innerHTML = button.dataset.originalHtml;
    button.disabled = false;
    button.classList.remove('opacity-70', 'pointer-events-none');
  }

  function todayIso() {
    return localIsoDate(new Date());
  }

  function localIsoDate(date) {
    return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
  }

  function currentWeekStartIso() {
    const date = new Date();
    date.setDate(date.getDate() - ((date.getDay() + 6) % 7));
    return [
      date.getFullYear(),
      String(date.getMonth() + 1).padStart(2, '0'),
      String(date.getDate()).padStart(2, '0'),
    ].join('-');
  }

  function downloadJson(document, filename, value) {
    const url = URL.createObjectURL(new Blob([JSON.stringify(value, null, 2)], {
      type: 'application/json;charset=utf-8',
    }));
    const link = document.createElement('a');
    link.href = url;
    link.download = filename;
    document.body.appendChild(link);
    link.click();
    link.remove();
    window.setTimeout(() => URL.revokeObjectURL(url), 0);
  }

  function parseClock(value) {
    const match = String(value || '').match(/(\d{1,2}):(\d{2})/);
    return match ? { hour: Number(match[1]), minute: Number(match[2]) } : { hour: 9, minute: 0 };
  }

  async function runApiAction(action, document, button) {
    try {
      setActionBusy(button, true, action.startsWith('auth-') ? '请稍候...' : '同步中...');
      if (action === 'auth-login' || action === 'auth-register') {
        const registering = action === 'auth-register';
        const account = document.getElementById('auth-account-input')?.value.trim() || '';
        const nickname = document.getElementById('auth-nickname-input')?.value.trim() || '';
        const password = document.getElementById('auth-password-input')?.value || '';
        const confirmation = document.getElementById('auth-confirm-input')?.value || '';
        const isZh = document.documentElement.lang.startsWith('zh');
        const contactValid = /^[^@]+@[^@]+\.[^@]+$/.test(account) || /^\d{11}$/.test(account);

        if (!account) {
          showAuthError(document, isZh ? '请输入手机号或邮箱。' : 'Enter your phone or email.');
          return;
        }
        if (!contactValid) {
          showAuthError(document, isZh ? '请输入有效的手机号或邮箱。' : 'Enter a valid phone or email.');
          return;
        }
        if (password.length < 6) {
          showAuthError(document, isZh ? '密码长度不能少于 6 位。' : 'Password must contain at least 6 characters.');
          return;
        }
        if (registering && !nickname) {
          showAuthError(document, isZh ? '请填写昵称。' : 'Enter a nickname.');
          return;
        }
        if (registering && password !== confirmation) {
          showAuthError(document, isZh ? '两次输入的密码不一致。' : 'The passwords do not match.');
          return;
        }

        const session = await backendRequest(registering ? '/auth/register' : '/auth/login', {
          method: 'POST',
          body: {
            contactAddress: account,
            ...(registering ? { displayName: nickname } : {}),
            password,
          },
        });
        if (typeof session?.accessToken !== 'string' || !session.user) {
          throw new Error('认证服务返回了无效响应');
        }

        localStorage.setItem('access_token', session.accessToken);
        localStorage.removeItem('token');
        localStorage.setItem('ruanchuang_user', JSON.stringify(session.user));
        settingsTokenHydrated = '';
        const destination = loginReturnRoute;
        navigate(destination, { replace: true });
        showNotice(
          window.document,
          registering
            ? `注册成功，欢迎 ${session.user.displayName || nickname}。`
            : `已登录 ${session.user.displayName || account}。`,
        );
        return;
      }

      if (action === 'auth-guest') {
        localStorage.removeItem('access_token');
        localStorage.removeItem('token');
        localStorage.removeItem('ruanchuang_user');
        settingsTokenHydrated = '';
        navigate(loginReturnRoute, { replace: true });
        showNotice(window.document, '已以游客身份继续；账号数据登录后同步。');
        return;
      }

      if (action === 'auth-profile-edit') {
        openProfileEditor(document);
        return;
      }

      if (action === 'auth-profile-save') {
        const displayName = document.getElementById('settings-profile-name')?.value.trim();
        if (!displayName) throw new Error('昵称不能为空');
        const user = await backendRequest('/auth/profile', {
          method: 'PUT',
          body: { displayName },
        });
        localStorage.setItem('ruanchuang_user', JSON.stringify(user));
        const updatedName = user.displayName || displayName;
        updateSettingsUserName(document, updatedName);
        if (activeRoute === 'profile') {
          updateProfileDisplayName(frame.contentDocument, updatedName);
        }
        document.getElementById('settings-profile-dialog')?.close();
        showNotice(document, '昵称已更新。');
        return;
      }

      if (action === 'auth-logout') {
        if (authHeaders().Authorization) {
          try {
            await backendRequest('/auth/logout', { method: 'POST' });
          } catch (error) {
            if (error.status !== 401) throw error;
          }
        }
        localStorage.removeItem('access_token');
        localStorage.removeItem('token');
        localStorage.removeItem('ruanchuang_user');
        settingsTokenHydrated = '';
        let destination = activeRoute;
        if (settingsOverlayHost) {
          destination = settingsReturnRoute;
          closeSettingsOverlay({ fromHistory: true });
          history.replaceState({ route: destination }, '', `#/${destination}`);
        }
        loginReturnRoute = destination;
        navigate('login');
        showNotice(window.document, '已退出登录。');
        return;
      }

      if (action === 'create-schedule') {
        const title = document.querySelector('textarea')?.value.trim();
        if (!title) throw new Error('日程主题不能为空');
        const tag = document.querySelector('.tag-pill.active-tag span:last-child')?.textContent.trim() || '未分类';
        const timeNode = [...document.querySelectorAll('span')].find((node) => /^\d{1,2}:\d{2}$/.test(node.textContent.trim()));
        const durationNode = [...document.querySelectorAll('span')].find((node) => /分钟/.test(node.textContent));
        const minutes = Number(durationNode?.textContent.match(/\d+/)?.[0] || 30);
        const repeatText = document.querySelector('#repeatGroup button.bg-primary')?.textContent.trim();
        const reminderText = document.querySelector('#reminderGroup button.bg-primary')?.textContent.trim();
        const repeat = ({ 不重复: 'none', 每天: 'daily', 每周: 'weekly', 每月: 'monthly' })[repeatText] || 'none';
        const reminderMinutesBefore = reminderText?.includes('不提醒')
          ? 0
          : Number(reminderText?.match(/\d+/)?.[0] || 30);
        await backendRequest('/schedule', {
          method: 'POST',
          body: {
            day: todayIso(),
            title,
            tag,
            height: minutes * 80 / 60,
            color: 0,
            time: parseClock(timeNode?.textContent),
            reminderMinutesBefore,
            repeat,
          },
        });
        showNotice(document, '日程已写入服务端排期。');
        navigate('schedule');
        return;
      }

      if (action === 'urgent-task-to-microtask') {
        const title = document.getElementById('urgent-task-title-input')?.value.trim();
        if (!title) throw new Error('请先填写紧急任务名称');
        const durationMinutes = Number(
          document.getElementById('selected-duration-label')?.textContent.match(/\d+/)?.[0] || 30,
        );
        const tag = document.querySelector('.tag-pill.active-tag span:last-child')?.textContent.trim() || 'Urgent';
        await backendRequest('/microtasks', {
          method: 'POST',
          body: {
            title,
            tag,
            minutes: durationMinutes,
            priority: 5,
            requirement: '从紧急任务暂存',
          },
        });
        showNotice(document, '紧急任务已存入微任务。');
        navigate('micro');
        return;
      }

      if (action === 'import-microtasks') {
        const text = document.getElementById('task-input')?.value.trim();
        if (!text) throw new Error('请先输入微任务内容');
        await backendRequest('/microtasks/import', { method: 'POST', body: { text } });
        showNotice(document, '微任务已导入服务端。');
        navigate('micro');
        return;
      }

      if (action === 'microtask-quick-add') {
        const raw = document.getElementById('nlp-task-input')?.value.trim();
        if (!raw) throw new Error('请先输入微任务内容');
        const title = raw.split('#')[0].replace(/~\d+m/i, '').replace(/!P\d/i, '').trim();
        const minutes = Number(raw.match(/~(\d+)m/i)?.[1] || 15);
        const priority = Number(raw.match(/!P(\d)/i)?.[1] || 3);
        const tag = raw.match(/#([^\s#]+)/)?.[1] || '未分类';
        await backendRequest('/microtasks', {
          method: 'POST',
          body: { title, tag, minutes, priority, requirement: 'NLP 快捷建单' },
        });
        showNotice(document, '微任务已写入服务端。');
        navigate('micro');
        return;
      }

      if (action === 'microtask-sweep') {
        const tasks = await backendRequest('/microtasks');
        const now = new Date();
        const recommendations = await backendRequest('/microtasks/recommend-crystals', {
          method: 'POST',
          body: {
            schedule: [],
            microTasks: Array.isArray(tasks) ? tasks : [],
            windows: [],
            energy: 'medium',
            now: { hour: now.getHours(), minute: now.getMinutes() },
            maxRecommendations: 4,
          },
        });
        showNotice(document, `服务端返回 ${Array.isArray(recommendations) ? recommendations.length : 0} 项冲刺建议。`);
        return;
      }

      if (action === 'import-ics') {
        const ics = document.getElementById('raw-input')?.value.trim();
        if (!ics) throw new Error('请先粘贴 ICS 内容');
        await backendRequest('/schedule/import-ics', { method: 'POST', body: { ics } });
        showNotice(document, 'ICS 日程已导入服务端。');
        navigate('schedule');
        return;
      }

      if (action === 'import-microtask-text') {
        const text = document.getElementById('raw-input')?.value.trim();
        if (!text) throw new Error('请先粘贴任务清单');
        await backendRequest('/microtasks/import', { method: 'POST', body: { text } });
        showNotice(document, '任务清单已导入服务端。');
        return;
      }

      if (action === 'diagnostics-summary') {
        const summary = await backendRequest('/diagnostics/summary');
        showNotice(document, `诊断完成：日程 ${summary?.counts?.schedules ?? 0} 条，事件 ${summary?.counts?.events ?? 0} 条。`);
        return;
      }

      if (action === 'team-book' || action === 'team-conflicts') {
        const members = await backendRequest('/team/members');
        const memberIds = Array.isArray(members) ? members.map((member) => member.memberId).filter(Boolean) : [];
        if (!memberIds.length) throw new Error('当前账号没有可用的团队成员');
        const day = todayIso();
        if (action === 'team-conflicts') {
          const result = await backendRequest('/team/conflicts', {
            method: 'POST',
            body: { day, memberIds, start: { hour: 14, minute: 0 }, minutes: 60 },
          });
          showNotice(document, `冲突检查完成：${result?.conflicts?.length ?? 0} 个冲突。`);
        } else {
          await backendRequest('/team/book-meeting', {
            method: 'POST',
            body: {
              day,
              title: '协作窗口预约',
              start: { hour: 14, minute: 0 },
              minutes: 60,
              participantIds: memberIds,
            },
          });
          showNotice(document, '协作会议已写入日程并同步团队成员。');
        }
        return;
      }

      if (action === 'focus-event') {
        const complete = button?.textContent.includes('结算');
        await backendRequest('/events', {
          method: 'POST',
          body: {
            id: `web_${complete ? 'complete' : 'skip'}_${Date.now()}`,
            taskId: 'web-focus-task',
            title: '当前专注任务',
            tag: 'Focus',
            at: new Date().toISOString(),
            type: complete ? 'complete' : 'postpone',
            plannedMinutes: 25,
            reason: complete ? 'focus_completed' : 'focus_skipped',
          },
        });
        showNotice(document, complete ? '专注任务已结算并写入事件。' : '专注任务已记录为跳过。');
        return;
      }

      if (action === 'focus-start') {
        await backendRequest('/events', {
          method: 'POST',
          body: {
            id: `web_start_${Date.now()}`,
            taskId: 'web-focus-task',
            title: '当前专注任务',
            tag: 'Focus',
            at: new Date().toISOString(),
            type: 'start',
            plannedMinutes: 25,
          },
        });
        showNotice(document, '专注已开始，启动事件已同步。');
        return;
      }

      if (action === 'rescue-options') {
        const currentEntries = await backendRequest('/schedule');
        const titleInput = document.getElementById('urgent-task-title-input');
        const title = titleInput?.value.trim() ||
          document.querySelector('textarea')?.value.trim() ||
          '紧急调度任务';
        if (activeRoute === 'urgent-task' && !titleInput?.value.trim()) {
          throw new Error('请先填写紧急任务名称');
        }
        const durationMinutes = Number(
          document.getElementById('selected-duration-label')?.textContent.match(/\d+/)?.[0] || 30,
        );
        const loadText = document.getElementById('cognitive-load-label')?.textContent || '';
        const loadLevel = Number(loadText.match(/Level\s*(\d+)/i)?.[1] || 3);
        const tag = document.querySelector('.tag-pill.active-tag span:last-child')?.textContent.trim() || 'Urgent';
        const hardLock = Array.from(document.querySelectorAll('[role="switch"]'))
          .find((switchButton) => switchButton.parentElement?.textContent.includes('硬约束防挤压锁定'))
          ?.getAttribute('aria-checked') === 'true';
        const deadlineInput = activeRoute === 'urgent-task'
          ? document.getElementById('urgent-task-deadline-input')
          : null;
        const dueDate = deadlineInput
          ? new Date(deadlineInput.value)
          : new Date(Date.now() + 4 * 60 * 60 * 1000);
        if (Number.isNaN(dueDate.getTime()) || dueDate.getTime() <= Date.now()) {
          throw new Error('请设置一个晚于现在的硬截止时间');
        }
        const day = deadlineInput?.value
          ? deadlineInput.value.slice(0, 10)
          : localIsoDate(new Date());
        const urgentTask = {
          id: `web-urgent-${Date.now()}`,
          title,
          durationMinutes,
          priority: 5,
          due: dueDate.toISOString(),
          load: loadLevel >= 4 ? 'high' : loadLevel >= 3 ? 'medium' : 'low',
          tag,
          hardDeadline: hardLock,
        };
        const options = await backendRequest('/schedule/rescue/options', {
          method: 'POST',
          body: {
            day,
            urgentTask,
            currentEntries,
            energy: 'medium',
            windows: [
              { start: { hour: 9, minute: 0 }, end: { hour: 12, minute: 0 } },
              { start: { hour: 13, minute: 30 }, end: { hour: 18, minute: 30 } },
            ],
            tuning: {
              defaultDurationMultiplier: 1,
              tagDurationMultiplier: {},
              highLoadPenaltyWhenLowEnergy: 1,
            },
            fixed: [],
            tasks: [],
          },
        });
        const originRoute = activeRoute === 'urgent-task'
          ? parentRouteFor(activeRoute) || 'schedule'
          : activeRoute;
        rescueState = { ...options, day, urgentTask, currentEntries, originRoute };
        showNotice(document, `服务端已生成 ${options?.options?.length ?? 0} 个救援方案。`);
        const returnRoute = activeRoute === 'urgent-task' ? 'urgent-task' : activeRoute;
        navigate('rescue-comparison', { returnRoute });
        return;
      }

      if (action === 'rescue-apply') {
        if (!rescueState?.options?.length) throw new Error('请先生成服务端救援方案');
        const option = rescueState.options.find((item) => item.id === button?.dataset.rescueOptionId) ||
          rescueState.options.find((item) => item.recommended) ||
          rescueState.options[0];
        const applied = await backendRequest('/schedule/rescue/apply', {
          method: 'POST',
          body: {
            day: rescueState.day,
            baselineHash: rescueState.baselineHash,
            strategy: option.strategy,
            before: rescueState.currentEntries.filter((entry) => entry.day === rescueState.day),
            after: option.plannedEntries,
            urgentTask: rescueState.urgentTask,
            eventId: `web_rescue_${Date.now()}`,
            energy: 'medium',
          },
        });
        rescueState.snapshotId = applied.snapshotId;
        rememberRescueSnapshot(applied.snapshotId);
        showNotice(document, '救援方案已写入服务端；可在日历页撤销此次变更。');
        navigate('schedule');
        return;
      }

      if (action === 'rescue-history') {
        const snapshots = readRescueSnapshots();
        const snapshotId = snapshots.at(-1)?.snapshotId || '';
        if (!snapshotId) throw new Error('没有可撤销的救援快照');
        await backendRequest('/schedule/rescue/undo', {
          method: 'POST',
          body: {
            snapshotId,
            eventId: `web_rescue_undo_${Date.now()}`,
          },
        });
        forgetRescueSnapshot(snapshotId);
        showNotice(document, '最近一次救援已撤销，服务端已恢复变更前的日程。');
        navigate('schedule');
        return;
      }

      if (action === 'profile-weekly-export') {
        const weekStart = currentWeekStartIso();
        const report = await backendRequest(`/review/weekly?week_start=${weekStart}`);
        downloadJson(document, `ruanchuang-weekly-report-${weekStart}.json`, {
          title: '时序智配周报',
          generatedAt: new Date().toISOString(),
          report,
        });
        showNotice(document, '周报已导出；本周复盘建议已同步到调度设置。');
        return;
      }

      if (action === 'settings-save') {
        if (!settingsPreferencesLoaded || !settingsDraft) {
          throw new Error('请先读取服务器偏好，再保存设置');
        }
        const selectedTheme = document.querySelector('[data-theme][aria-pressed="true"]')?.dataset.theme;
        const selectedLang = document.querySelector('[data-lang][aria-pressed="true"]')?.dataset.lang;
        const themeMode = selectedTheme === 'auto' ? 'system' : selectedTheme;
        const locale = selectedLang === 'en-US' ? 'en_US' : 'zh_CN';
        await backendRequest('/settings', {
          method: 'PUT',
          body: {
            themeMode,
            locale,
          },
        });
        if (settingsOverlayHost) {
          const primaryDocument = frame.contentDocument;
          activeThemeMode = themeMode;
          settingsDraft = null;
          settingsPreferencesLoaded = false;
          applyThemeMode(activeThemeMode);
          closeSettingsOverlay();
          if (primaryDocument) {
            showNotice(primaryDocument, '设置已保存。主题已应用，语言偏好已同步到账户。');
          }
        } else {
          showNotice(document, '设置已保存。主题已应用，语言偏好已同步到账户。');
          returnFromSecondary();
        }
        return;
      }

      throw new Error(`Unknown API action: ${action}`);
    } catch (error) {
      if (action === 'auth-login' || action === 'auth-register') {
        const registering = action === 'auth-register';
        const message = error.status === 401 && !registering
          ? '手机号/邮箱或密码不正确。'
          : error.status === 409 && registering
            ? '该手机号或邮箱已注册，请切换到登录。'
            : error.status === 422
              ? '提交信息未通过服务器校验，请检查后重试。'
              : error.status >= 500
                ? '认证服务暂时不可用，请稍后重试。'
                : error.status == null
                  ? '无法连接认证服务，请检查网络后重试；也可以继续游客体验。'
                  : '认证请求未完成，请稍后重试。';
        showAuthError(document, message);
      } else {
        const message = error.status === 401 ? '请先登录后再同步此操作。' : `操作失败：${error.message}`;
        showNotice(document, message);
      }
    } finally {
      setActionBusy(button, false);
    }
  }

  window.__RUANCHUANG_API_ACTION__ = runApiAction;

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
    if (button.id === 'login-back-action') return '__login_back__';
    if (button.id === 'schedule-create-urgent-task') return 'urgent-task';
    if (button.id === 'mobile-rescue-generate') return 'urgent-task';
    if (button.dataset.scheduleView) return '__schedule-view__';
    if (button.dataset.scheduleDay) return '__schedule-day__';
    if (activeRoute === 'schedule' && mobileQuery.matches && label.includes('救援')) return 'urgent-task';
    if (label.includes('通知') || label.includes('notification')) {
      return '__notice__';
    }
    if (label.includes('切换账户') || label.includes('switch account')) return 'login';
    if (
      label.includes('返回') ||
      label.includes('back') ||
      label.includes('previous') ||
      label.includes('关闭') ||
      label.includes('close') ||
      label.includes('cancel') ||
      label.includes('取消')
    ) {
      return parentRouteFor(activeRoute);
    }
    if (label.includes('设置') || label.includes('settings')) {
      return activeRoute === 'profile' ? 'settings-drawer' : 'profile';
    }
    if (label.includes('目标') || label.includes('goals')) return 'goals';
    if (label.includes('复盘') || label.includes('review')) return 'review';
    if (label.includes('诊断') || label.includes('diagnostics')) return 'diagnostics';
    if (label.includes('情绪') || label.includes('emotion')) return 'emotion-energy';
    if (label.includes('蓝牙') || label.includes('bluetooth')) return 'bluetooth';
    if (label.includes('mcp') || label.includes('接入')) return 'integrations';
    if (label.includes('插入紧急') || label.includes('urgent task')) return 'urgent-task';
    if (label.includes('ics') || label.includes('导入/导出')) return 'integrations';
    if (label.includes('新增日程') || label.includes('新建日程') || label.includes('add schedule') || label.includes('new schedule')) return 'create-schedule';
    if (activeRoute === 'schedule' && label.includes('立即对比并执行救援方案')) return 'urgent-task';
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

  function apiActionForButton(button) {
    if (button.id === 'btn-quick-add') return 'microtask-quick-add';
    if (button.id === 'btn-sweep-start') return 'microtask-sweep';
    if (button.id === 'schedule-rescue-undo' || button.id === 'mobile-rescue-undo') return 'rescue-history';
    if (button.id === 'btn-refresh' || button.id === 'btn-self-test') return 'diagnostics-summary';
    if (button.id === 'save-settings-btn' || button.id === 'btn-save-settings') return 'settings-save';
    if (button.id === 'btn-quick-reserve' || button.id === 'btn-silent-room') return 'team-book';
    if (button.id === 'btn-conflict-check') return 'team-conflicts';
    if (button.id === 'profile-weekly-export') return 'profile-weekly-export';
    if (button.id === 'settings-profile-edit-action') return 'auth-profile-edit';
    if (button.id === 'settings-profile-save') return 'auth-profile-save';
    if (activeRoute === 'login' && button.id === 'auth-submit') {
      return button.dataset.authMode === 'register' ? 'auth-register' : 'auth-login';
    }
    if (button.id === 'auth-guest') return 'auth-guest';
    if (button.id === 'settings-logout-action') return 'auth-logout';
    const label = `${button.textContent || ''} ${button.title || ''} ${button.getAttribute('aria-label') || ''}`;
    if (activeRoute === 'create-schedule' && label.includes('保存并写入日程')) return 'create-schedule';
    if (activeRoute === 'urgent-task' && label.includes('立即生成三方案救援对比')) return 'rescue-options';
    if (activeRoute === 'urgent-task' && label.includes('暂存至微任务沙盒')) return 'urgent-task-to-microtask';
    if (activeRoute === 'create-schedule' && label.includes('保存并写入日程')) return 'create-schedule';
    if (activeRoute === 'urgent-task' && label.includes('立即生成三方案救援对比')) return 'rescue-options';
    if (activeRoute === 'urgent-task' && label.includes('暂存至微任务沙盒')) return 'urgent-task-to-microtask';
    if (activeRoute === 'focus' && (label.includes('跳过') || label.includes('结算'))) return 'focus-event';
    if (activeRoute === 'schedule' && label.includes('撤销上次自动调度')) return 'rescue-history';
    if (activeRoute === 'rescue-comparison' && button.dataset.rescueOptionId) return 'rescue-apply';
    if (activeRoute === 'rescue-comparison' && label.includes('采用此方案')) return 'rescue-apply';
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

    if (activeRoute === 'rescue-comparison' && !hydrateRescueComparisonView(childDocument)) {
      return;
    }

    requestAnimationFrame(() => frame.classList.remove('route-switching'));

    injectPolishStyles(childDocument);
    applyThemeMode(settingsDraft?.themeMode ?? activeThemeMode);

    if (parentRoutes[activeRoute]) {
      const hasNativeExit = childDocument.querySelector(
        '[data-router-return], [aria-label*="返回"], [aria-label*="关闭"], [aria-label*="Back"], [aria-label*="Close"]',
      );
      if (!hasNativeExit) {
        const back = childDocument.createElement('button');
        back.type = 'button';
        back.dataset.routerBack = 'true';
        back.setAttribute('aria-label', '返回上一页');
        back.title = '返回上一页';
        back.textContent = '‹';
        Object.assign(back.style, {
          position: 'fixed',
          top: '16px',
          left: '16px',
          zIndex: '9998',
          width: '44px',
          height: '44px',
          border: '1px solid rgba(65,72,72,.18)',
          borderRadius: '12px',
          background: 'rgba(255,255,255,.92)',
          color: '#163d3d',
          font: '28px/1 system-ui, sans-serif',
          cursor: 'pointer',
          boxShadow: '0 2px 10px rgba(0,0,0,.08)',
        });
        back.addEventListener('click', () => returnFromSecondary());
        childDocument.body.appendChild(back);
      }
    }

    enhanceAccessibility(childDocument);
    hydrateProfileView(childDocument, activeRoute);
    prepareRouteControls(childDocument, activeRoute);

    childDocument.addEventListener('click', (event) => {
      const exitSurface =
        event.target.closest('[data-router-return], #settings-backdrop, #drawer-backdrop') ||
        (event.target === childDocument.body.firstElementChild &&
          event.target.matches('div.fixed.inset-0.-z-10'));
      if (exitSurface && parentRoutes[activeRoute]) {
        event.preventDefault();
        returnFromSecondary();
        return;
      }

      const anchor = event.target.closest('a');
      if (anchor) {
        const route = routeForLink(anchor);
        const modifiedClick =
          event.button !== 0 ||
          event.metaKey ||
          event.ctrlKey ||
          event.shiftKey ||
          event.altKey;
        if (route && !modifiedClick) {
          event.preventDefault();
          navigate(route);
          return;
        }
      }

      const button = event.target.closest('button');
      if (!button) return;
      if (button.id === 'rescue-view-details') {
        event.preventDefault();
        childDocument.querySelector('[data-rescue-details]')?.scrollIntoView({
          behavior: 'smooth',
          block: 'start',
        });
        return;
      }
      if (button.id === 'rescue-adjust-duration') {
        event.preventDefault();
        navigate('urgent-task', {
          replace: true,
          returnRoute: rescueState?.originRoute || 'schedule',
        });
        return;
      }
      if (button.dataset.profileTone) {
        const preferences = readProfilePreferences();
        preferences.colorTone = button.dataset.profileTone;
        saveProfilePreferences(preferences);
        applyProfilePreferences(childDocument, preferences);
        showNotice(childDocument, '色彩偏好已保存在此浏览器，不会同步到账户。');
        return;
      }
      const apiAction = apiActionForButton(button);
      if (apiAction) {
        event.preventDefault();
        runApiAction(apiAction, childDocument, button);
        return;
      }
      if (button.dataset.unavailableNotice) {
        event.preventDefault();
        showNotice(childDocument, button.dataset.unavailableNotice);
        return;
      }
      const route = routeForButton(button);
      if (route === '__notice__') {
        event.preventDefault();
        showNotice(childDocument, '通知与提醒暂未接入，当前不会发送提醒。');
        return;
      }
      if (route === '__login_back__') {
        event.preventDefault();
        returnFromSecondary();
        return;
      }
      if (route === '__schedule-view__' || route === '__schedule-day__') {
        event.preventDefault();
        const selector = route === '__schedule-view__' ? '[data-schedule-view]' : '[data-schedule-day]';
        const attribute = route === '__schedule-view__' ? 'scheduleView' : 'scheduleDay';
        const selected = button.dataset[attribute];
        for (const sibling of childDocument.querySelectorAll(selector)) {
          const active = sibling.dataset[attribute] === selected;
          sibling.classList.toggle('bg-surface-container-lowest', active);
          sibling.classList.toggle('text-primary', active);
          sibling.classList.toggle('font-semibold', active);
          sibling.setAttribute('aria-pressed', String(active));
        }
        showNotice(childDocument, route === '__schedule-view__'
          ? `已切换到${selected}视图；列表数据仍以服务端日程为准。`
          : `已选择${selected}；刷新后将按服务端日程重新加载。`);
        return;
      }
      if (route) {
        event.preventDefault();
        if (route === 'urgent-task' && activeRoute !== 'rescue-comparison') {
          rescueState = null;
        }
        navigate(route);
      }
    });

    childDocument.addEventListener('change', (event) => {
      const compactMode = event.target.closest?.('#profile-compact-mode');
      if (!compactMode) return;
      const preferences = readProfilePreferences();
      preferences.compactMode = compactMode.checked;
      saveProfilePreferences(preferences);
      applyProfilePreferences(childDocument, preferences);
      showNotice(childDocument, '紧凑布局已保存在此浏览器，不会同步到账户。');
    });

    hydrateBackend(childDocument, activeRoute);
    hydrateStoredTheme(childDocument);
  });

  window.addEventListener('hashchange', syncRouteFromHistory);
  window.addEventListener('popstate', syncRouteFromHistory);
  mobileQuery.addEventListener('change', () => {
    renderRoute(activeRoute);
    resizeSettingsOverlay();
  });
  window.addEventListener('resize', () => {
    applyCanvasSize();
    resizeSettingsOverlay();
  });
  window.addEventListener('keydown', (event) => {
    if (event.key === 'Escape') {
      if (settingsOverlayHost) closeSettingsOverlay();
      else returnFromSecondary();
    }
  });

  const initialRoute = routeFromHash();
  const openSettingsInitially = initialRoute === 'settings-drawer';
  const requestedReturnRoute = history.state?.settingsDrawer
    ? history.state.returnRoute
    : null;
  const requestedLoginReturnRoute = history.state?.login
    ? history.state.returnRoute
    : null;
  loginReturnRoute = pages[requestedLoginReturnRoute] && requestedLoginReturnRoute !== 'login'
    ? requestedLoginReturnRoute
    : 'focus';
  activeRoute = openSettingsInitially
    ? (pages[requestedReturnRoute] && requestedReturnRoute !== 'settings-drawer'
        ? requestedReturnRoute
        : 'focus')
    : initialRoute;
  if (!window.location.hash) history.replaceState(null, '', '#/focus');
  if (openSettingsInitially) {
    history.replaceState({ route: activeRoute }, '', `#/${activeRoute}`);
  }
  renderRoute(activeRoute);
  if (openSettingsInitially) openSettingsOverlay();
})();
