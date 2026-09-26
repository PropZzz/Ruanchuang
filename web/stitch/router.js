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
  let rescueState = null;

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
    const target = labels.find((node) => /探测到\s*\d+\s*处/.test(node.textContent));
    if (target) target.textContent = `探测到 ${count} 处日程冲突`;
    const severity = labels.find((node) => node.textContent.trim() === '高紧迫性');
    if (severity) {
      severity.textContent = count ? '需要处理' : '当前正常';
      severity.classList.toggle('text-error', Boolean(count));
    }
    const priority = labels.find((node) => node.textContent.trim() === 'P0 核心中断');
    if (priority) priority.textContent = count ? 'P0 核心中断' : '今日无硬冲突';
  }

  function enhanceAccessibility(document) {
    const iconLabels = {
      settings: '设置',
      tune: '调整选项',
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
        if (label) button.setAttribute('aria-label', label);
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

  // Secondary surfaces live inside an iframe, so their local history is not
  // the application's route state. Expose one parent-owned escape hatch for
  // close buttons, backdrops, Escape, and injected navigation affordances.
  window.__RUANCHUANG_RETURN__ = returnFromSecondary;

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
    return new Date().toISOString().slice(0, 10);
  }

  function parseClock(value) {
    const match = String(value || '').match(/(\d{1,2}):(\d{2})/);
    return match ? { hour: Number(match[1]), minute: Number(match[2]) } : { hour: 9, minute: 0 };
  }

  async function runApiAction(action, document, button) {
    try {
      setActionBusy(button, true, '同步中...');
      if (action === 'create-schedule') {
        const title = document.querySelector('textarea')?.value.trim();
        if (!title) throw new Error('日程主题不能为空');
        const tag = document.querySelector('.tag-pill.active-tag span:last-child')?.textContent.trim() || '未分类';
        const timeNode = [...document.querySelectorAll('span')].find((node) => /^\d{1,2}:\d{2}$/.test(node.textContent.trim()));
        const durationNode = [...document.querySelectorAll('span')].find((node) => /分钟/.test(node.textContent));
        const minutes = Number(durationNode?.textContent.match(/\d+/)?.[0] || 30);
        await backendRequest('/schedule', {
          method: 'POST',
          body: {
            day: todayIso(),
            title,
            tag,
            height: minutes * 80 / 60,
            color: 0,
            time: parseClock(timeNode?.textContent),
            reminderMinutesBefore: 30,
            repeat: 'none',
          },
        });
        showNotice(document, '日程已写入服务端排期。');
        navigate('schedule');
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
        const day = todayIso();
        const currentEntries = await backendRequest('/schedule');
        const urgentTask = {
          id: `web-urgent-${Date.now()}`,
          title: '紧急调度任务',
          durationMinutes: 30,
          priority: 5,
          due: new Date(Date.now() + 4 * 60 * 60 * 1000).toISOString(),
          load: 'high',
          tag: 'Urgent',
          hardDeadline: true,
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
        rescueState = { ...options, day, urgentTask, currentEntries };
        showNotice(document, `服务端已生成 ${options?.options?.length ?? 0} 个救援方案。`);
        navigate('rescue-comparison');
        return;
      }

      if (action === 'rescue-apply') {
        if (!rescueState?.options?.length) throw new Error('请先生成服务端救援方案');
        const option = rescueState.options.find((item) => item.recommended) || rescueState.options[0];
        await backendRequest('/schedule/rescue/apply', {
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
        showNotice(document, '救援方案已由服务端事务写入，可在复盘中查看。');
        navigate('schedule');
        return;
      }

      if (action === 'rescue-history') {
        const history = await backendRequest('/schedule/rescue/history');
        showNotice(document, `已读取 ${Array.isArray(history) ? history.length : 0} 条救援记录。`);
        return;
      }

      if (action === 'settings-save') {
        const activeTheme = document.querySelector('.theme-seg-btn.bg-surface-container-lowest')?.dataset.theme ||
          document.querySelector('[data-theme].bg-surface-container-lowest')?.dataset.theme ||
          'light';
        const themeMode = activeTheme === 'auto' ? 'system' : activeTheme;
        const activeLang = document.querySelector('.lang-btn[data-lang].bg-surface-container')?.dataset.lang || 'zh-CN';
        await backendRequest('/settings', {
          method: 'PUT',
          body: {
            themeMode,
            locale: activeLang === 'en-US' ? 'en_US' : 'zh_CN',
          },
        });
        showNotice(document, '设置已保存到服务端。');
        returnFromSecondary();
        return;
      }

      throw new Error(`Unknown API action: ${action}`);
    } catch (error) {
      const message = error.status === 401 ? '请先登录后再同步此操作。' : `操作失败：${error.message}`;
      showNotice(document, message);
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

  function apiActionForButton(button) {
    if (button.id === 'btn-refresh' || button.id === 'btn-self-test') return 'diagnostics-summary';
    if (button.id === 'save-settings-btn' || button.id === 'btn-save-settings') return 'settings-save';
    if (button.id === 'btn-quick-reserve' || button.id === 'btn-silent-room') return 'team-book';
    if (button.id === 'btn-conflict-check') return 'team-conflicts';
    const label = `${button.textContent || ''} ${button.title || ''} ${button.getAttribute('aria-label') || ''}`;
    if (activeRoute === 'focus' && (label.includes('跳过') || label.includes('结算'))) return 'focus-event';
    if (activeRoute === 'schedule' && label.includes('立即对比并执行救援方案')) return 'rescue-options';
    if (activeRoute === 'schedule' && label.includes('撤销上次自动调度')) return 'rescue-history';
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
        if (route) {
          event.preventDefault();
          navigate(route);
          return;
        }
      }

      const button = event.target.closest('button');
      if (!button) return;
      const apiAction = apiActionForButton(button);
      if (apiAction) {
        event.preventDefault();
        runApiAction(apiAction, childDocument, button);
        return;
      }
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
