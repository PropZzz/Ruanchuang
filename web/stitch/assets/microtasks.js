(() => {
  const $ = (id) => document.getElementById(id);
  const pageContent = $('mt-page-content');
  const focusLayer = $('mt-focus');
  const focusPanel = $('mt-focus-panel');
  const confirmLayer = $('mt-confirm');
  const confirmPanel = $('mt-confirm-panel');
  const ringValue = $('mt-ring-value');
  const ringCircumference = 2 * Math.PI * 88;

  const setParentFocusMode = (enabled) => {
    const host = window.parent;
    if (host && host !== window && typeof host.__RUANCHUANG_FOCUS_MODE__ === 'function') {
      host.__RUANCHUANG_FOCUS_MODE__(enabled);
    }
  };

  const state = {
    tasks: [],
    filter: 'queue',
    backendState: 'loading',
    focus: null,
    pendingHydration: null,
  };

  const el = (tag, className, text) => {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (text != null) node.textContent = text;
    return node;
  };

  const icon = (name) => el('span', 'material-symbols-outlined', name);
  const clampPriority = (value) => Math.min(5, Math.max(1, Number(value) || 3));
  const minutesFor = (task) => Math.min(24 * 60, Math.max(1, Math.round(Number(task.minutes) || 15)));
  const formatDuration = (seconds) => {
    const total = Math.max(0, Math.round(seconds));
    const hours = Math.floor(total / 3600);
    const minutes = Math.floor((total % 3600) / 60);
    const rest = total % 60;
    const mm = String(minutes).padStart(2, '0');
    const ss = String(rest).padStart(2, '0');
    return hours > 0 ? `${hours}:${mm}:${ss}` : `${mm}:${ss}`;
  };

  const pointsFor = (task) => {
    const minutes = minutesFor(task);
    const priority = clampPriority(task.priority);
    const durationBonus = minutes <= 10 ? 5 : minutes <= 20 ? 4 : minutes <= 40 ? 2 : 1;
    const tag = String(task.tag || '');
    let tagBonus = 0;
    if (/邮件|收件箱|email|inbox/i.test(tag)) tagBonus = 2;
    else if (/会议|沟通|meeting|call/i.test(tag)) tagBonus = 1;
    else if (/开发|修复|bug|dev/i.test(tag)) tagBonus = 1;
    return Math.min(20, priority * 2 + durationBonus + tagBonus);
  };

  const pendingTasks = () => state.tasks.filter((task) => !task.done);
  const doneTasks = () => state.tasks.filter((task) => task.done);

  const buckets = (tasks) => [
    tasks.filter((task) => clampPriority(task.priority) >= 5),
    tasks.filter((task) => clampPriority(task.priority) < 5 && minutesFor(task) <= 5),
    tasks.filter((task) => {
      const p = clampPriority(task.priority);
      return p >= 3 && p <= 4 && minutesFor(task) > 5;
    }),
    tasks.filter((task) => clampPriority(task.priority) <= 2 && minutesFor(task) > 5),
  ];

  const nextTask = () => {
    for (const bucket of buckets(pendingTasks())) {
      if (bucket.length) return bucket[0];
    }
    return null;
  };

  const groupMeta = [
    { title: '紧急', color: 'var(--rc-danger)' },
    { title: '5 分钟内', color: 'var(--rc-action)' },
    { title: '排队中', color: 'var(--rc-brand)' },
    { title: '稍后', color: 'var(--rc-faint)' },
  ];

  const callAction = async (action, payload) => {
    const host = window.parent;
    if (!host || host === window || typeof host.__RUANCHUANG_API_ACTION__ !== 'function') {
      return { ok: false, error: new Error('未连接到工作台') };
    }
    try {
      return await host.__RUANCHUANG_API_ACTION__(action, document, null, payload);
    } catch (error) {
      return { ok: false, error };
    }
  };

  const setText = (node, text) => {
    if (node) node.textContent = text;
  };

  const renderStats = () => {
    const open = pendingTasks();
    const done = doneTasks();
    const pendingMinutes = open.reduce((sum, task) => sum + minutesFor(task), 0);
    const points = done.reduce((sum, task) => sum + pointsFor(task), 0);
    setText($('mt-stat-pending'), String(open.length));
    setText($('mt-stat-pending-note'), `约 ${(pendingMinutes / 60).toFixed(1)}h`);
    setText($('mt-stat-done'), String(done.length));
    setText($('mt-stat-done-note'), '今日');
    setText($('mt-stat-points'), String(points));
    setText($('mt-stat-points-note'), '累计');
  };

  const renderTabs = () => {
    const open = pendingTasks().length;
    const done = doneTasks().length;
    setText($('mt-queue-count'), String(open));
    setText($('mt-done-count'), String(done));
    for (const button of document.querySelectorAll('.mt-tabs [data-filter]')) {
      button.setAttribute('aria-selected', String(button.dataset.filter === state.filter));
    }
  };

  const renderSide = () => {
    const done = doneTasks().length;
    const total = state.tasks.length;
    const open = pendingTasks().length;
    const ratio = total ? done / total : 0;
    setText($('mt-progress-pct'), `${Math.round(ratio * 100)}%`);
    const bar = $('mt-progress-bar');
    if (bar) bar.style.width = `${Math.round(ratio * 100)}%`;
    setText($('mt-progress-copy'), `${done} / ${total}`);
    const points = doneTasks().reduce((sum, task) => sum + pointsFor(task), 0);
    setText($('mt-progress-points'), `${points} 积分`);
    setText($('mt-backlog-copy'), open === 0 ? '没有待处理任务。' : `还有 ${open} 项待处理。`);
  };

  const buildTaskRow = (task) => {
    const row = el('article', `mt-task${task.done ? ' done' : ''}`);
    row.dataset.id = String(task.id || '');
    const check = el('button', 'mt-check');
    check.type = 'button';
    check.dataset.action = 'toggle';
    check.dataset.id = String(task.id || '');
    check.setAttribute('role', 'checkbox');
    check.setAttribute('aria-checked', String(Boolean(task.done)));
    check.setAttribute('aria-label', task.done ? '标记未完成' : '标记完成');
    check.append(icon('check'));
    row.append(check);

    const copy = el('div', 'mt-task-copy');
    const titleLine = el('div', 'mt-task-title');
    const priority = el(
      'span',
      `mt-priority mt-p${clampPriority(task.priority)}`,
      `P${clampPriority(task.priority)}`,
    );
    titleLine.append(priority, el('h4', null, task.title || '未命名任务'));
    copy.append(titleLine);

    const meta = el('div', 'mt-task-meta');
    const time = el('span');
    time.append(icon('schedule'), document.createTextNode(`${minutesFor(task)} 分钟`));
    meta.append(time);
    const tag = String(task.tag || '').trim();
    if (tag) {
      const tagNode = el('span');
      tagNode.append(icon('tag'), document.createTextNode(`#${tag}`));
      meta.append(tagNode);
    }
    copy.append(meta);
    row.append(copy);

    if (!task.done) {
      const focusButton = el('button', 'rc-btn mt-focus-btn');
      focusButton.type = 'button';
      focusButton.dataset.action = 'focus';
      focusButton.dataset.id = String(task.id || '');
      focusButton.append(icon('play_arrow'), el('span', null, '专注'));
      row.append(focusButton);
    }
    return row;
  };

  const renderGroup = (title, color, tasks) => {
    const section = el('section', 'mt-group');
    const head = el('div', 'mt-group-head');
    const dot = el('span', 'mt-dot');
    dot.style.background = color;
    head.append(dot, el('h3', null, title), el('span', null, `${tasks.length} 项`));
    section.append(head);
    tasks.forEach((task) => section.append(buildTaskRow(task)));
    return section;
  };

  const renderNext = () => {
    const host = $('mt-next-host');
    host.replaceChildren();
    if (state.backendState !== 'online' || state.filter !== 'queue') return;
    const task = nextTask();
    if (!task) return;

    const card = el('section', 'mt-next');
    const head = el('div', 'mt-next-head');
    const label = el('span', 'mt-next-label');
    label.append(icon('play_circle'), document.createTextNode('下一项'));
    head.append(label);
    card.append(head);

    card.append(el('h2', null, task.title || '未命名任务'));

    const meta = el('div', 'mt-next-meta');
    meta.append(el('span', 'mt-next-chip', `P${clampPriority(task.priority)}`));
    meta.append(el('span', 'mt-next-chip', `${minutesFor(task)} 分钟`));
    const tag = String(task.tag || '').trim();
    if (tag) meta.append(el('span', 'mt-next-chip', `#${tag}`));
    card.append(meta);

    const actions = el('div', 'mt-next-actions');
    const start = el('button', 'rc-btn rc-btn-primary');
    start.type = 'button';
    start.dataset.action = 'focus';
    start.dataset.id = String(task.id || '');
    start.append(icon('play_arrow'), el('span', null, '开始专注'));
    const done = el('button', 'rc-btn');
    done.type = 'button';
    done.dataset.action = 'complete';
    done.dataset.id = String(task.id || '');
    done.append(icon('check'), el('span', null, '完成'));
    actions.append(start, done);
    card.append(actions);
    host.append(card);
  };

  const renderGroups = () => {
    const host = $('mt-groups');
    host.replaceChildren();
    if (state.backendState !== 'online') return;

    if (state.filter === 'done') {
      const done = doneTasks();
      if (done.length) host.append(renderGroup('已完成', 'var(--rc-success)', done));
      return;
    }

    const open = pendingTasks();
    if (!open.length) return;
    const next = nextTask();
    const rest = next ? open.filter((task) => String(task.id) !== String(next.id)) : open;
    if (!rest.length) {
      host.append(el('p', 'mt-hint', '没有其他排队任务。'));
      return;
    }
    buckets(rest).forEach((tasks, index) => {
      if (!tasks.length) return;
      host.append(renderGroup(groupMeta[index].title, groupMeta[index].color, tasks));
    });
  };

  const renderEmpty = () => {
    const host = $('mt-empty');
    host.replaceChildren();
    host.hidden = true;
    const show = (title, copy, action) => {
      const box = document.createElement('div');
      box.append(el('strong', null, title), el('p', null, copy));
      if (action) box.append(action);
      host.replaceChildren(box);
      host.hidden = false;
    };

    if (state.backendState === 'loading') {
      show('正在读取微任务…', '稍等片刻。');
      return;
    }
    if (state.backendState === 'auth-required') {
      const link = el('a', 'rc-btn', '去登录');
      link.href = '#/login';
      link.dataset.path = 'login';
      show('登录后同步微任务', '登录后这里会显示服务端任务。', link);
      return;
    }
    if (state.backendState === 'offline') {
      const retry = el('button', 'rc-btn', '重试');
      retry.type = 'button';
      retry.dataset.emptyAction = 'reload';
      show('暂时无法连接服务端', '后端恢复后重新打开此页即可。', retry);
      return;
    }
    if (!state.tasks.length) {
      const add = el('button', 'rc-btn rc-btn-primary', '添加一项');
      add.type = 'button';
      add.dataset.emptyAction = 'add';
      show('暂无微任务', '添加一项，或导入清单。', add);
      return;
    }
    if (state.filter === 'queue' && !pendingTasks().length) {
      show('队列已清空', '切到“已完成”查看记录。');
      return;
    }
    if (state.filter === 'done' && !doneTasks().length) {
      show('没有已完成任务', '完成一项后会出现在这里。');
    }
  };

  const renderAll = () => {
    if (state.focus) return;
    renderStats();
    renderTabs();
    renderSide();
    renderNext();
    renderGroups();
    renderEmpty();
  };

  const applyHydration = (detail) => {
    state.tasks = Array.isArray(detail?.tasks) ? detail.tasks.map((task) => ({ ...task })) : [];
    state.backendState = detail?.state || 'online';
    renderAll();
  };

  const toggleDone = async (task, done) => {
    const result = await callAction('microtask-set-done', { taskId: task.id, done });
    if (!result?.ok) return;
    task.done = done;
    renderAll();
  };

  const quickAdd = async (event) => {
    event.preventDefault();
    const input = $('nlp-task-input');
    const raw = input?.value.trim();
    if (!raw) {
      input?.focus();
      return;
    }
    const result = await callAction('microtask-quick-add', {});
    if (!result?.ok || !result.task) return;
    state.tasks.push({ ...result.task });
    input.value = '';
    renderAll();
    input.focus();
  };

  const setFocusVisibility = (visible) => {
    focusLayer.hidden = !visible;
    focusLayer.setAttribute('aria-hidden', String(!visible));
    document.body.classList.toggle('mt-focus-mode', visible);
    if (pageContent) pageContent.inert = visible;
  };

  const paintFocus = () => {
    const focus = state.focus;
    if (!focus) return;
    const completed = focus.completed;
    const total = Math.max(1, focus.total);
    const ratio = 1 - Math.min(1, Math.max(0, focus.remaining / total));
    if (ringValue) {
      ringValue.style.strokeDasharray = String(ringCircumference);
      ringValue.style.strokeDashoffset = String(ringCircumference * (1 - ratio));
    }
    focusPanel.dataset.complete = String(completed);
    setText($('mt-focus-timer'), completed ? '已完成' : formatDuration(focus.remaining));
    setText(
      $('mt-focus-note'),
      completed
        ? `+${pointsFor(focus.task)} 积分`
        : focus.running
          ? `预计 ${minutesFor(focus.task)} 分钟`
          : '已暂停',
    );

    const pause = $('mt-focus-pause');
    const end = $('mt-focus-end');
    const retry = $('mt-focus-retry');
    pause.hidden = completed;
    pause.textContent = focus.running ? '暂停' : '继续';
    pause.disabled = focus.saving;
    end.disabled = focus.saving;
    end.textContent = focus.saving ? '正在保存…' : '关闭';
    end.classList.toggle('rc-btn-primary', completed);
    retry.hidden = !focus.saveFailed;
  };

  const tickFocus = () => {
    const focus = state.focus;
    if (!focus || !focus.running || focus.completed) return;
    const remaining = Math.max(0, Math.ceil((focus.deadline - Date.now()) / 1000));
    if (remaining !== focus.remaining) {
      focus.remaining = remaining;
      paintFocus();
    }
    if (remaining <= 0) finishFocus();
  };

  const startTicker = () => {
    const focus = state.focus;
    if (!focus || focus.completed) return;
    focus.running = true;
    focus.deadline = Date.now() + focus.remaining * 1000;
    clearInterval(focus.timer);
    focus.timer = setInterval(tickFocus, 250);
    tickFocus();
  };

  const pauseFocus = () => {
    const focus = state.focus;
    if (!focus || focus.completed) return;
    focus.remaining = Math.max(0, Math.ceil((focus.deadline - Date.now()) / 1000));
    focus.running = false;
    clearInterval(focus.timer);
    focus.timer = null;
    paintFocus();
  };

  const resumeFocus = () => {
    const focus = state.focus;
    if (!focus || focus.completed) return;
    startTicker();
    paintFocus();
  };

  const completeFocus = async () => {
    const focus = state.focus;
    if (!focus || focus.saving || focus.saved) return;
    focus.saving = true;
    focus.saveFailed = false;
    paintFocus();
    const activeMinutes = Math.max(1, Math.round(focus.activeSeconds / 60));
    const result = await callAction('microtask-focus-complete', {
      taskId: focus.task.id,
      activeMinutes,
    });
    if (!state.focus) return;
    if (result?.ok) {
      focus.saved = true;
      focus.saving = false;
      focus.task.done = true;
      const stored = state.tasks.find((task) => String(task.id) === String(focus.task.id));
      if (stored) stored.done = true;
      paintFocus();
    } else {
      focus.saving = false;
      focus.saveFailed = true;
      paintFocus();
    }
  };

  const finishFocus = () => {
    const focus = state.focus;
    if (!focus) return;
    focus.running = false;
    clearInterval(focus.timer);
    focus.timer = null;
    focus.remaining = 0;
    focus.activeSeconds = focus.total;
    focus.completed = true;
    paintFocus();
    void completeFocus();
  };

  const hideConfirm = () => {
    confirmLayer.hidden = true;
    focusPanel.inert = false;
    const pause = $('mt-focus-pause');
    if (pause && !pause.hidden) pause.focus({ preventScroll: true });
  };

  const showConfirm = () => {
    const focus = state.focus;
    if (!focus) return;
    setText($('mt-confirm-body'), `「${focus.task.title || '未命名任务'}」还未完成。`);
    confirmLayer.hidden = false;
    focusPanel.inert = true;
    confirmPanel.querySelector('[data-confirm="keep"]')?.focus({ preventScroll: true });
  };

  const closeFocus = () => {
    const focus = state.focus;
    if (!focus) return;
    clearInterval(focus.timer);
    confirmLayer.hidden = true;
    focusPanel.inert = false;
    setParentFocusMode(false);
    setFocusVisibility(false);
    const trigger = focus.trigger;
    state.focus = null;
    if (state.pendingHydration) {
      const detail = state.pendingHydration;
      state.pendingHydration = null;
      applyHydration(detail);
    } else {
      renderAll();
    }
    if (trigger && typeof trigger.focus === 'function') {
      trigger.focus({ preventScroll: true });
    }
  };

  const requestClose = () => {
    const focus = state.focus;
    if (!focus || focus.saving) return;
    if (focus.completed) {
      closeFocus();
      return;
    }
    showConfirm();
  };

  const openFocus = (task) => {
    if (!task || state.focus) return;
    const total = minutesFor(task) * 60;
    state.focus = {
      task,
      total,
      remaining: total,
      deadline: 0,
      timer: null,
      running: true,
      completed: false,
      saving: false,
      saved: false,
      saveFailed: false,
      activeSeconds: 0,
      trigger: document.activeElement,
    };
    setText($('mt-focus-title'), task.title || '未命名任务');
    const tag = String(task.tag || '').trim();
    const meta = [`P${clampPriority(task.priority)}`, `${minutesFor(task)} 分钟`];
    if (tag) meta.push(`#${tag}`);
    setText($('mt-focus-meta'), meta.join(' · '));
    setFocusVisibility(true);
    setParentFocusMode(true);
    paintFocus();
    startTicker();
    void callAction('microtask-focus-start', {
      task: {
        id: task.id,
        title: task.title,
        tag: task.tag,
        minutes: minutesFor(task),
        priority: clampPriority(task.priority),
      },
    });
    $('mt-focus-pause').focus({ preventScroll: true });
  };

  const handleConfirm = async (choice) => {
    const focus = state.focus;
    if (!focus) return;
    if (choice === 'keep') {
      hideConfirm();
      return;
    }
    if (choice === 'abandon') {
      hideConfirm();
      void callAction('microtask-focus-abandon', {
        taskId: focus.task.id,
        title: focus.task.title,
        tag: focus.task.tag,
        minutes: minutesFor(focus.task),
        activeMinutes: Math.max(1, Math.round((focus.total - focus.remaining) / 60)),
      });
      closeFocus();
      return;
    }
    hideConfirm();
    focus.running = false;
    clearInterval(focus.timer);
    focus.timer = null;
    focus.activeSeconds = focus.total - focus.remaining;
    focus.completed = true;
    paintFocus();
    await completeFocus();
    if (state.focus?.saved) closeFocus();
  };

  const trapFocus = (event) => {
    if (event.key !== 'Tab') return;
    const container = !confirmLayer.hidden ? confirmPanel : state.focus ? focusPanel : null;
    if (!container) return;
    const focusable = [...container.querySelectorAll('button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])')]
      .filter((node) => !node.disabled && node.offsetParent !== null);
    if (!focusable.length) return;
    const first = focusable[0];
    const last = focusable[focusable.length - 1];
    if (event.shiftKey && document.activeElement === first) {
      event.preventDefault();
      last.focus();
    } else if (!event.shiftKey && document.activeElement === last) {
      event.preventDefault();
      first.focus();
    }
  };

  document.addEventListener('click', (event) => {
    const emptyAction = event.target.closest('[data-empty-action]');
    if (emptyAction) {
      if (emptyAction.dataset.emptyAction === 'add') {
        $('nlp-task-input')?.focus();
      } else if (emptyAction.dataset.emptyAction === 'reload') {
        window.location.reload();
      }
      return;
    }
    const action = event.target.closest('[data-action]');
    if (!action) {
      const confirmButton = event.target.closest('[data-confirm]');
      if (confirmButton) void handleConfirm(confirmButton.dataset.confirm);
      return;
    }
    const task = state.tasks.find((item) => String(item.id) === String(action.dataset.id));
    if (!task) return;
    if (action.dataset.action === 'focus') openFocus(task);
    else if (action.dataset.action === 'toggle') void toggleDone(task, !task.done);
    else if (action.dataset.action === 'complete') void toggleDone(task, true);
  });

  for (const button of document.querySelectorAll('.mt-tabs [data-filter]')) {
    button.addEventListener('click', () => {
      state.filter = button.dataset.filter === 'done' ? 'done' : 'queue';
      renderAll();
    });
  }

  $('mt-quick-form')?.addEventListener('submit', quickAdd);
  $('mt-focus-close')?.addEventListener('click', requestClose);
  $('mt-focus-end')?.addEventListener('click', requestClose);
  $('mt-focus-pause')?.addEventListener('click', () => {
    const focus = state.focus;
    if (!focus) return;
    if (focus.running) pauseFocus();
    else resumeFocus();
  });
  $('mt-focus-retry')?.addEventListener('click', () => void completeFocus());

  focusLayer?.addEventListener('click', (event) => {
    if (event.target === focusLayer) requestClose();
  });
  confirmLayer?.addEventListener('click', (event) => {
    if (event.target === confirmLayer) hideConfirm();
  });

  document.addEventListener('keydown', (event) => {
    if (event.key === 'Escape') {
      if (!confirmLayer.hidden) {
        hideConfirm();
        return;
      }
      if (state.focus) requestClose();
      return;
    }
    if (event.key === 'Tab') trapFocus(event);
  });

  document.addEventListener('visibilitychange', () => {
    if (state.focus) setParentFocusMode(!document.hidden);
    if (!document.hidden && state.focus?.running) tickFocus();
  });

  document.addEventListener('stitch:visibility', (event) => {
    const visible = event.detail?.visible !== false;
    if (state.focus) setParentFocusMode(visible);
    if (visible && state.focus?.running) tickFocus();
  });

  window.addEventListener('pagehide', () => setParentFocusMode(false));

  document.addEventListener('stitch:microtasks', (event) => {
    const detail = event.detail || {};
    if (state.focus) {
      state.pendingHydration = detail;
      return;
    }
    applyHydration(detail);
  });

  renderAll();
  window.setTimeout(() => {
    if (state.backendState !== 'loading') return;
    state.backendState = 'offline';
    renderAll();
  }, 5000);
})();
