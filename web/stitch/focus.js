// Live focus workbench: hydrates the static focus screen with real backend
// data and drives the pomodoro session (next-task preview, scheduled
// auto-start, manual start moving the calendar slot earlier, timer modes).
//
// Follows the calendar.js contract: the router mounts it onto a screen
// iframe's document and passes an authenticated `request` helper.
//
// Timer modes (all base the session on the task's own planned length):
// - pomodoro: countdown for exactly the task duration, then the task is
//   settled automatically and the next one takes over.
// - flow:     count-up ("正向心流"), the ring fills over the planned length.
// - deep:     same task-length countdown as pomodoro plus do-not-disturb:
//     page notifications stay silent until the session ends.
// The countdown derives from a wall-clock deadline, so switching tabs or
// leaving the page never freezes or rewinds the timer. A running session
// survives refreshes (the router re-hydrates on every page activation).
((scope) => {
  const pad = (n) => String(n).padStart(2, '0');
  const dateKey = (date) =>
    `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
  const clock = (minutes) => `${pad(Math.floor(minutes / 60))}:${pad(minutes % 60)}`;
  const nowMinutes = (now) => now.getHours() * 60 + now.getMinutes();

  const MODE_STORAGE_KEY = 'ruanchuang-focus-mode';

  const durationMinutes = (entry) =>
    Math.max(1, Math.min(1440, Math.round((Number(entry?.height) || 60) * 60 / 80)));
  const startMinutes = (entry) =>
    (Number(entry?.time?.hour) || 0) * 60 + (Number(entry?.time?.minute) || 0);
  const endMinutes = (entry) => startMinutes(entry) + durationMinutes(entry);

  // Same repetition semantics as the calendar/Flutter app: floating entries
  // (day == null) repeat every day; anchored entries follow their frequency.
  function occursOnDay(entry, day) {
    const target = dateKey(day);
    const anchor = entry?.day ? String(entry.day).slice(0, 10) : null;
    if (!anchor) return true;
    if (target < anchor) return false;
    if (entry.repeatUntil && target > String(entry.repeatUntil).slice(0, 10)) return false;
    if (entry.repeat === 'none' || !entry.repeat) return target === anchor;
    if (entry.repeat === 'daily') return true;
    if (entry.repeat === 'weekly') {
      const parse = (value) => {
        const [y, m, d] = value.split('-').map(Number);
        return Date.UTC(y, m - 1, d) / 86400000;
      };
      return (parse(target) - parse(anchor)) % 7 === 0;
    }
    if (entry.repeat === 'monthly') {
      const [year, month, date] = anchor.split('-').map(Number);
      let occurrence = new Date(year, month - 1, date, 12);
      while (dateKey(occurrence) < target) {
        const previousDay = occurrence.getDate();
        occurrence.setDate(1);
        occurrence.setMonth(occurrence.getMonth() + 1);
        occurrence.setDate(Math.min(previousDay, new Date(occurrence.getFullYear(), occurrence.getMonth() + 1, 0).getDate()));
      }
      return dateKey(occurrence) === target;
    }
    return false;
  }

  function todaysEntries(entries, now) {
    const items = [];
    for (const entry of Array.isArray(entries) ? entries : []) {
      if (!entry || !occursOnDay(entry, now)) continue;
      items.push({ entry, start: startMinutes(entry), end: endMinutes(entry) });
    }
    return items.sort((a, b) => a.start - b.start || String(a.entry.id || '').localeCompare(String(b.entry.id || '')));
  }

  // Mirrors the Flutter FocusPage split: the entry whose window contains now
  // is current (last match wins on overlaps); later starts are upcoming.
  function selectCurrentNext(entries, now = new Date()) {
    const minutes = nowMinutes(now);
    let current = null;
    const upcoming = [];
    for (const item of todaysEntries(entries, now)) {
      if (item.start <= minutes && minutes < item.end) current = item;
      else if (item.start > minutes) upcoming.push(item);
    }
    return { current, upcoming };
  }

  function countConflicts(items) {
    let count = 0;
    const list = Array.isArray(items) ? items : [];
    list.forEach((left, index) => {
      for (const right of list.slice(index + 1)) {
        if (left.start < right.end && right.start < left.end) count++;
      }
    });
    return count;
  }

  function formatCountdown(totalSeconds) {
    const seconds = Math.max(0, Math.round(totalSeconds));
    const hh = Math.floor(seconds / 3600);
    const mm = Math.floor((seconds % 3600) / 60);
    const ss = seconds % 60;
    return hh > 0 ? `${hh}:${pad(mm)}:${pad(ss)}` : `${pad(mm)}:${pad(ss)}`;
  }

  const TAG_LABELS = {
    General: '通用',
    'Deep Work': '深度工作',
    'Micro Task': '微任务',
    Routine: '例行',
    Urgent: '紧急',
    Goal: '目标',
  };
  const tagLabel = (tag) => TAG_LABELS[tag] || String(tag || '未分类');

  // Stored load first; otherwise a deterministic estimate from the entry's
  // own tag and duration so the chip never shows a made-up placeholder.
  function cognitiveLoadFor(entry) {
    const stored = String(entry?.load || '').toLowerCase();
    if (['low', 'medium', 'high'].includes(stored)) return stored;
    const tag = String(entry?.tag || '');
    const lower = tag.toLowerCase();
    if (/micro|email|mail/.test(lower) || tag.includes('微任务') || tag.includes('邮件')) return 'low';
    if (/deep|architecture|arch|code|dev/.test(lower) || /深度|架构|攻坚/.test(tag)) return 'high';
    const minutes = durationMinutes(entry);
    if (minutes >= 60) return 'high';
    if (minutes >= 25) return 'medium';
    return 'low';
  }

  const LOAD_LABELS = { low: '负荷 低', medium: '负荷 中', high: '负荷 高' };
  const LOAD_CHIP_CLASSES = {
    high: 'bg-error-container text-on-error-container',
    medium: 'bg-secondary-container text-on-secondary-container',
    low: 'bg-surface-container-high text-on-surface-variant',
  };
  const LOAD_DOT_CLASSES = {
    high: 'bg-error',
    medium: 'bg-secondary',
    low: 'bg-on-surface-variant',
  };

  const EMOTION_LABELS = {
    efficient: '高效',
    stable: '平稳',
    tired: '疲惫',
    irritable: '烦躁',
  };
  const emotionLabel = (state) => EMOTION_LABELS[state] || null;

  const taskIdOf = (entry) =>
    String(entry?.id || '') || `focus_${entry?.title}_${startMinutes(entry)}`;

  const EMPTY_TEXT = '今天没有更多日程';

  function setText(doc, id, text) {
    const node = doc.getElementById(id);
    if (node) node.textContent = text;
  }

  function readStoredMode() {
    try {
      const value = localStorage.getItem(MODE_STORAGE_KEY);
      return ['pomodoro', 'flow', 'deep'].includes(value) ? value : 'pomodoro';
    } catch (_) {
      return 'pomodoro';
    }
  }

  function mount(doc, { request, notify = () => {}, onState = () => {} }) {
    const win = doc.defaultView;
    let disposed = false;
    let generation = 0;
    let entriesCache = [];
    let energy = null;
    let emotionState = null;
    let current = null; // { entry, start, end }
    let upcoming = [];
    let display = null; // { item, isNext }
    let plannedSeconds = 0;
    let mode = readStoredMode();
    // Both timer modes use wall-clock anchors so background throttling does
    // not lose time. Count-up sessions retain accumulated time while paused.
    let segment = null; // { kind, countUp, totalSeconds, deadline?, remainingAtPause?, elapsed?, startedAt? }
    let isRunning = false;
    let activeTaskId = null;
    const finishedTaskIds = new Set();
    let tickTimer = null;
    let autoStartTimer = null;
    // 今日专注累计：seconds from today's completed focus events (server) plus
    // the live session's work time committed on finish.
    let focusBase = 0;
    let focusCommitted = 0;
    let eventsTodayCount = 0;

    function workElapsedOf(activeSegment) {
      if (!activeSegment || activeSegment.kind !== 'work') return 0;
      return activeSegment.countUp
        ? countUpElapsed(activeSegment)
        : Math.max(0, activeSegment.totalSeconds - segmentRemainingOf(activeSegment));
    }

    function countUpElapsed(activeSegment) {
      return (activeSegment.elapsed || 0) + (activeSegment.startedAt == null
        ? 0 : Math.max(0, (Date.now() - activeSegment.startedAt) / 1000));
    }

    function segmentRemainingOf(activeSegment) {
      if (!activeSegment || activeSegment.countUp) return 0;
      if (activeSegment.deadline) {
        return Math.max(0, Math.round((activeSegment.deadline - Date.now()) / 1000));
      }
      return activeSegment.remainingAtPause ?? activeSegment.totalSeconds;
    }

    function todayFocusTotal() {
      return focusBase + focusCommitted + workElapsedOf(segment);
    }

    function segmentRemaining() {
      if (!segment || segment.countUp) return 0;
      if (segment.deadline) {
        return Math.max(0, Math.round((segment.deadline - Date.now()) / 1000));
      }
      return segment.remainingAtPause ?? segment.totalSeconds;
    }

    function segmentValue() {
      if (!segment) return 0;
      return segment.countUp ? countUpElapsed(segment) : segmentRemaining();
    }

    function stopTimers() {
      if (tickTimer) { win.clearInterval(tickTimer); tickTimer = null; }
      if (autoStartTimer) { win.clearTimeout(autoStartTimer); autoStartTimer = null; }
    }

    function renderChips(item) {
      const loadChip = doc.getElementById('focus-load-chip');
      if (loadChip) {
        const load = cognitiveLoadFor(item.entry);
        const frame = loadChip.dataset.desktop === 'true'
          ? 'inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-bold font-label'
          : 'inline-flex items-center gap-1 px-1.5 py-0.5 rounded font-label text-[10px] font-bold tracking-wider';
        const dotPulse = isRunning && segment?.kind === 'work' ? ' animate-pulse' : '';
        loadChip.className = `${frame} ${LOAD_CHIP_CLASSES[load]}`;
        loadChip.innerHTML =
          `<span class="w-1.5 h-1.5 rounded-full shrink-0 ${LOAD_DOT_CLASSES[load]}${dotPulse}"></span>` +
          `<span>${LOAD_LABELS[load]}</span>`;
      }
      const tagChip = doc.getElementById('focus-tag-chip');
      if (tagChip) {
        const frame = tagChip.dataset.desktop === 'true'
          ? 'inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full bg-surface-container-high text-on-surface-variant text-xs font-medium font-label'
          : 'inline-flex items-center gap-1 px-1.5 py-0.5 rounded bg-surface-container-high text-on-surface-variant font-label text-[11px] font-mono';
        tagChip.className = frame;
        const dot = doc.createElement('span');
        dot.className = 'w-1.5 h-1.5 rounded-full shrink-0 bg-on-surface-variant opacity-60';
        const label = doc.createElement('span');
        label.textContent = tagLabel(item.entry.tag);
        tagChip.replaceChildren(dot, label);
      }
    }

    function renderEmptyState() {
      const body = doc.querySelector('[data-focus-task-body]');
      const empty = doc.querySelector('[data-focus-task-empty]');
      // Inline display wins over the Tailwind utilities on these wrappers.
      if (body) body.style.display = display ? '' : 'none';
      if (empty) empty.style.display = display ? 'none' : 'flex';
    }

    function renderScheduleStatus() {
      const conflicts = countConflicts(todaysEntries(entriesCache, new Date()));
      const icon = doc.getElementById('focus-schedule-icon');
      if (icon) icon.textContent = conflicts > 0 ? 'error_outline' : 'check_circle_outline';
      const title = doc.getElementById('focus-schedule-title');
      if (title) {
        title.textContent = conflicts > 0
          ? `发现 ${conflicts} 处日程冲突`
          : '排期状态无冲突';
      }
      const copy = doc.getElementById('focus-schedule-copy');
      if (copy) {
        copy.textContent = conflicts > 0
          ? '存在时间重叠的安排，打开智能日历查看冲突详情并处理。'
          : '按原计划推进即可，暂无需要处理的时间冲突。';
      }
    }

    function renderModePills() {
      for (const button of doc.querySelectorAll('[data-focus-mode]')) {
        const desktop = button.dataset.desktop === 'true';
        const selected = button.dataset.focusMode === mode;
        button.className = (desktop
          ? 'px-3.5 py-1.5 rounded-md font-semibold transition-all '
          : 'py-1.5 rounded-md text-center font-medium transition-all ')
          + (selected
            ? (desktop
              ? 'bg-primary text-on-primary shadow-sm'
              : 'bg-surface-container-lowest text-secondary font-semibold shadow-xs')
            : 'text-on-surface-variant hover:text-on-surface');
      }
    }

    function previewValue() {
      if (!display) return 0;
      if (display.isNext) return plannedSeconds;
      // Current task, not started: show the real remaining window.
      const minutes = nowMinutes(new Date());
      return Math.max(0, (display.item.end - minutes) * 60);
    }

    function sessionStatus() {
      if (isRunning) return dnd ? '勿扰专注中' : '专注状态中';
      if (segment) return '等待开始'; // paused mid-session
      if (display?.isNext) return '到点自动开始';
      return current ? '等待开始' : '暂无任务';
    }

    // Do-not-disturb: while a 沉浸 session is live, informational notices
    // are suppressed; state changes still happen silently.
    let dnd = false;
    function notifyUser(message) {
      if (dnd) return;
      notify(message);
    }

    function render() {
      // Metric band: the four cards mirror the Flutter focus page.
      const value = segment
        ? formatCountdown(segmentValue())
        : (display ? formatCountdown(previewValue()) : '--:--');
      // Card 1 counts UP: the total focused time recorded today.
      setText(doc, 'focus-stat-current', formatCountdown(todayFocusTotal()));
      setText(doc, 'focus-stat-current-sub', display?.item.entry.title || EMPTY_TEXT);
      const battery = Number(energy?.batteryPercent ?? energy?.battery_percent);
      setText(doc, 'focus-stat-energy', Number.isFinite(battery) ? `${battery}%` : '--');
      const emotion = emotionLabel(emotionState);
      setText(
        doc,
        'focus-stat-energy-sub',
        Number.isFinite(battery)
          ? `当前情绪：${emotion || String(energy?.status || '') || '平稳'}`
          : '暂无能量数据',
      );
      setText(doc, 'focus-stat-next', String(upcoming.length));
      setText(doc, 'focus-stat-next-sub', upcoming[0]?.entry.title || EMPTY_TEXT);
      const conflicts = countConflicts(todaysEntries(entriesCache, new Date()));
      setText(doc, 'focus-stat-conflict', String(conflicts));
      setText(doc, 'focus-stat-conflict-sub', conflicts > 0 ? '需要处理' : '无需处理');
      renderScheduleStatus();

      // Header pills.
      setText(doc, 'focus-header-energy', Number.isFinite(battery) ? `能量 ${battery} 分` : '能量 --');
      setText(doc, 'focus-energy-title', Number.isFinite(battery) ? `认知能量池 ${battery}分` : '认知能量池 --');
      setText(doc, 'focus-energy-status', String(energy?.status || '暂无数据'));
      setText(doc, 'focus-energy-sub', emotion
        ? `当前情绪：${emotion}`
        : String(energy?.description || '暂无能量数据'));
      const bar = doc.getElementById('focus-energy-bar');
      if (bar) bar.style.width = `${Number.isFinite(battery) ? Math.min(100, Math.max(0, battery)) : 0}%`;
      const now = new Date();
      setText(doc, 'focus-date-label', `${now.getMonth() + 1}月${now.getDate()}日 星期${'日一二三四五六'[now.getDay()]}`);

      // Pomodoro card.
      renderEmptyState();
      renderModePills();
      if (!display) return;
      const { item, isNext } = display;
      const entry = item.entry;
      renderChips(item);
      setText(doc, 'focus-task-title', entry.title || '未命名任务');
      const desc = doc.getElementById('focus-task-desc');
      if (desc) {
        desc.textContent = String(entry.description || '').trim();
        desc.hidden = !String(entry.description || '').trim();
      }
      const end = item.end;
      setText(doc, 'focus-time-range', `${clock(startMinutes(entry))} - ${clock(end)}`);
      const value2 = segment ? formatCountdown(segmentValue()) : formatCountdown(previewValue());
      setText(
        doc,
        'focus-remaining-label',
        segment
          ? (segment.countUp ? `已专注 ${value2}` : `剩余 ${value2}`)
          : (isNext ? `计划 ${durationMinutes(entry)} 分钟` : `剩余 ${value2}`),
      );
      const timerDisplay = doc.getElementById('focus-timer-display');
      if (timerDisplay) timerDisplay.textContent = value;
      setText(doc, 'focus-timer-status', sessionStatus());
      renderGauge();

      const toggle = doc.querySelector('[data-focus-action="toggle"]');
      if (toggle) {
        toggle.innerHTML = isRunning
          ? '<span class="material-symbols-outlined text-[18px]">pause_circle</span><span>暂停专注</span>'
          : '<span class="material-symbols-outlined text-[18px]">play_circle</span><span>开始专注</span>';
      }
      const finish = doc.querySelector('[data-focus-action="finish"]');
      if (finish) finish.hidden = isNext && !segment;
    }

    function renderGauge() {
      const ring = doc.getElementById('focus-progress-ring');
      if (!ring) return;
      const circumference = Number(ring.dataset.circumference) ||
        2 * Math.PI * Number(ring.getAttribute('r') || 42);
      let progress = 0;
      if (segment) {
        progress = segment.countUp
          ? Math.min(1, countUpElapsed(segment) / (plannedSeconds || 1))
          : Math.min(1, Math.max(0, segmentRemaining() / (segment.totalSeconds || 1)));
      } else if (display) {
        // Idle: the ring shows how much of the session/task time remains.
        progress = display.isNext
          ? 1
          : Math.min(1, Math.max(0, previewValue() / (plannedSeconds || 1)));
      }
      // The visible arc equals the remaining-time percentage of the ring.
      ring.style.strokeDashoffset = String(circumference * (1 - progress));
    }

    function fireEvent(type, entry, { actualMinutes } = {}) {
      const payload = {
        id: `evt_${type}_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`,
        taskId: taskIdOf(entry),
        title: entry.title || '',
        tag: entry.tag || '',
        load: entry.load || null,
        at: new Date().toISOString(),
        type,
        plannedMinutes: durationMinutes(entry),
      };
      if (actualMinutes !== undefined) payload.actualMinutes = actualMinutes;
      Promise.resolve()
        .then(() => request('/events', { method: 'POST', body: payload }))
        .catch(() => {}); // Telemetry is best effort; never block the timer.
    }

    function ensureTicker() {
      if (tickTimer || disposed) return;
      tickTimer = win.setInterval(() => {
        if (disposed || !segment) return;
        if (doc.documentElement.dataset.pageVisible === 'false') return;
        if (!segment.countUp && segmentRemaining() <= 0) {
          onSegmentExpired();
          return;
        }
        renderDynamic();
      }, 1000);
    }

    // Cheap per-second updates: numbers and ring only, no structural DOM.
    function renderDynamic() {
      const value = formatCountdown(segmentValue());
      const timerDisplay = doc.getElementById('focus-timer-display');
      if (timerDisplay) timerDisplay.textContent = value;
      // Card 1 keeps counting up while a work segment is live.
      setText(doc, 'focus-stat-current', formatCountdown(todayFocusTotal()));
      setText(
        doc,
        'focus-remaining-label',
        segment.countUp ? `已专注 ${value}` : `剩余 ${value}`,
      );
      renderGauge();
    }

    function onSegmentExpired() {
      // Every countdown segment now lasts exactly the task's planned length,
      // so expiry means the task is done: settle it and let the next one
      // take over.
      finishRunning({ automatic: true });
      notifyUser('任务时长已到，已自动结算并切换下一任务。');
    }

    function startWorkSegment() {
      if (mode === 'flow') {
        segment = { kind: 'work', countUp: true, totalSeconds: plannedSeconds, elapsed: 0, startedAt: Date.now() };
        dnd = false;
      } else {
        segment = { kind: 'work', countUp: false, totalSeconds: plannedSeconds, deadline: Date.now() + plannedSeconds * 1000 };
        dnd = mode === 'deep';
      }
      isRunning = true;
      render();
      ensureTicker();
      if (dnd) notify('已开启勿扰模式，页面通知将保持静默，直到本次专注结束。');
    }

    // One start event per task per day, so re-opening the page (which
    // auto-starts the in-window task) never spams the event log.
    function markStartedToday(taskId) {
      try {
        const key = `ruanchuang-focus-starts:${dateKey(new Date())}`;
        const recorded = new Set(JSON.parse(localStorage.getItem(key) || '[]'));
        if (recorded.has(taskId)) return false;
        recorded.add(taskId);
        localStorage.setItem(key, JSON.stringify([...recorded]));
        return true;
      } catch (_) {
        return true;
      }
    }

    function beginRunning({ movedEarlier } = {}) {
      if (!current) return;
      const taskId = taskIdOf(current.entry);
      if (activeTaskId !== taskId) {
        if (markStartedToday(taskId)) fireEvent('start', current.entry);
        activeTaskId = taskId;
      }
      plannedSeconds = durationMinutes(current.entry) * 60;
      startWorkSegment();
      if (movedEarlier) notifyUser('已提前开始，智能日历中的安排已前移至现在。');
    }

    function promote(item) {
      current = item;
      upcoming = upcoming.filter((candidate) => candidate !== item);
      display = { item, isNext: false };
      beginRunning();
    }

    function armAutoStart() {
      if (autoStartTimer) { win.clearTimeout(autoStartTimer); autoStartTimer = null; }
      if (current || isRunning || segment || !upcoming.length) return;
      const next = upcoming[0];
      const now = new Date();
      const scheduled = new Date(now.getFullYear(), now.getMonth(), now.getDate());
      scheduled.setMinutes(next.start);
      const wait = scheduled.getTime() - now.getTime();
      if (wait <= 0) {
        promote(next);
        notifyUser('已到计划时间，自动开始计时。');
        return;
      }
      autoStartTimer = win.setTimeout(() => {
        autoStartTimer = null;
        if (disposed || current || isRunning || segment || !upcoming.length) return;
        promote(upcoming[0]);
        notifyUser('已到计划时间，自动开始计时。');
      }, wait);
    }

    function applySchedule({ keepSession = false } = {}) {
      const now = new Date();
      const selection = selectCurrentNext(entriesCache.filter(entry => !finishedTaskIds.has(taskIdOf(entry))), now);
      const sessionAlive = keepSession && (isRunning || segment);
      if (!sessionAlive) {
        stopTimers();
        // Tasks settled in this browser session must not come back as the
        // current task or the next preview before the server reflects them.
        current = selection.current && !finishedTaskIds.has(taskIdOf(selection.current.entry))
          ? selection.current
          : null;
        upcoming = selection.upcoming.filter((item) => !finishedTaskIds.has(taskIdOf(item.entry)));
        if (current) {
          // The task's scheduled time has arrived: the pomodoro runs on its
          // own from here, no user action required.
          display = { item: current, isNext: false };
          beginRunning();
        } else if (upcoming.length) {
          display = { item: upcoming[0], isNext: true };
          plannedSeconds = durationMinutes(upcoming[0].entry) * 60;
        } else {
          display = null;
          plannedSeconds = 0;
        }
      } else {
        // Keep the running session untouched; only refresh the upcoming list.
        upcoming = selection.upcoming.filter((candidate) => candidate !== current);
      }
      render();
      armAutoStart();
    }

    async function moveEntryEarlier(item) {
      const entry = item.entry;
      const id = String(entry.id || '');
      if (!id || entry.day == null || entry.repeat && entry.repeat !== 'none') return { entry, moved: false };
      const now = new Date();
      const scheduledStart = new Date(now.getFullYear(), now.getMonth(), now.getDate());
      scheduledStart.setMinutes(startMinutes(entry));
      if (scheduledStart.getTime() <= now.getTime()) return { entry, moved: false };
      const moved = {
        ...entry,
        day: dateKey(now),
        time: { hour: now.getHours(), minute: now.getMinutes() },
      };
      try {
        await request(`/schedule/${encodeURIComponent(id)}`, { method: 'PUT', body: moved });
        return { entry: moved, moved: true };
      } catch (_) {
        return { entry, moved: false }; // Start the timer even if the move failed.
      }
    }

    async function manualStart() {
      if (isRunning || !display) {
        if (segment && !isRunning) {
          // Resume the paused session.
          if (segment.countUp) segment.startedAt = Date.now();
          if (segment && !segment.countUp && !segment.deadline) {
            segment.deadline = Date.now() + segmentRemaining() * 1000;
          }
          isRunning = true;
          render();
          ensureTicker();
        }
        return;
      }
      if (!display.isNext) {
        // Current task, not started: run it in the selected mode.
        current = display.item;
        beginRunning();
        return;
      }
      _startNextNow();
    }

    async function _startNextNow() {
      const item = display.item;
      const { entry, moved } = await moveEntryEarlier(item);
      if (disposed) return;
      if (moved) {
        item.entry = entry;
        item.start = startMinutes(entry);
        item.end = item.start + durationMinutes(entry);
      }
      current = item;
      upcoming = upcoming.filter((candidate) => candidate !== item);
      display = { item, isNext: false };
      beginRunning({ movedEarlier: moved });
      if (!moved) notifyUser('已开始专注。');
    }

    function finishRunning({ automatic }) {
      const item = current;
      if (!item) return;
      finishedTaskIds.add(taskIdOf(item.entry));
      const planned = durationMinutes(item.entry);
      const done = segment
        ? (segment.countUp
          ? countUpElapsed(segment)
          : (segment.kind === 'work' ? Math.max(60, segment.totalSeconds - segmentValue()) : planned * 60))
        : planned * 60;
      // Keep today's accumulated total intact until the event log reflects
      // the session (the next refresh folds it into focusBase).
      focusCommitted += workElapsedOf(segment);
      fireEvent('complete', item.entry, {
        actualMinutes: Math.min(planned, Math.max(1, Math.round(done / 60))),
      });
      isRunning = false;
      segment = null;
      activeTaskId = null;
      current = null;
      const wasDnd = dnd;
      dnd = false;
      applySchedule();
      if (wasDnd) notify('勿扰模式已关闭，通知已恢复。');
      else if (!automatic) notify('已结算当前任务，继续下一个安排。');
    }

    async function refresh() {
      const turn = ++generation;
      try {
        onState('loading', '正在同步…');
        const now = new Date();
        const dayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate());
        const localIso = (date) => {
          const offset = date.getTimezoneOffset() * 60000;
          return new Date(date.getTime() - offset).toISOString().slice(0, 19);
        };
        const [schedule, energyResult, emotionResult, eventsResult] = await Promise.all([
          request('/schedule'),
          request('/energy/current').catch((error) => ({ __error: error })),
          request('/emotion/current').catch(() => null),
          request(`/events?from=${encodeURIComponent(localIso(dayStart))}&to=${encodeURIComponent(localIso(now))}`)
            .catch(() => []),
        ]);
        if (disposed || turn !== generation) return;
        entriesCache = Array.isArray(schedule) ? schedule : [];
        if (energyResult && !energyResult.__error) energy = energyResult;
        emotionState = emotionResult?.state ?? null;
        // Today's focused time: settled focus sessions from the event log.
        const events = Array.isArray(eventsResult) ? eventsResult : [];
        for (const event of events) {
          if (event?.type === 'complete' && event.taskId) finishedTaskIds.add(String(event.taskId));
        }
        eventsTodayCount = events.filter((event) => event?.type === 'complete').length;
        const sessionLive = Boolean(isRunning || segment);
        if (!sessionLive) {
          focusBase = events
            .filter((event) => event?.type === 'complete')
            .reduce((sum, event) => sum + (Number(event?.actualMinutes ?? event?.actual_minutes) || 0), 0) * 60;
          focusCommitted = 0; // The fetched log already includes them.
        }
        // A running or paused session survives re-hydration (the router
        // refreshes on every page activation); only idle state re-derives.
        applySchedule({ keepSession: sessionLive });
        onState('online', '已连接 · FastAPI');
      } catch (error) {
        if (disposed || turn !== generation) return;
        const state = error?.status === 401 ? 'auth-required' : 'offline';
        entriesCache = [];
        applySchedule({ keepSession: Boolean(isRunning || segment) });
        onState(state, state === 'auth-required' ? '请登录后同步' : '本地模式 · 后端不可用');
      }
    }

    for (const node of doc.querySelectorAll('[data-focus-action]')) {
      const action = node.dataset.focusAction;
      node.addEventListener('click', (event) => {
        event.preventDefault();
        if (action === 'toggle') {
          if (isRunning) {
            // Pause: freeze the segment where it is.
            if (segment?.countUp) {
              segment.elapsed = countUpElapsed(segment);
              delete segment.startedAt;
            }
            if (segment && !segment.countUp && segment.deadline) {
              segment.remainingAtPause = segmentRemaining();
              delete segment.deadline;
            }
            isRunning = false;
            if (tickTimer) { win.clearInterval(tickTimer); tickTimer = null; }
            render();
          } else if (segment) {
            if (segment.countUp) segment.startedAt = Date.now();
            if (!segment.countUp && !segment.deadline) {
              segment.deadline = Date.now() + segmentRemaining() * 1000;
            }
            isRunning = true;
            render();
            ensureTicker();
          } else if (current) {
            plannedSeconds = durationMinutes(current.entry) * 60;
            startWorkSegment();
            if (activeTaskId !== taskIdOf(current.entry)) {
              fireEvent('start', current.entry);
              activeTaskId = taskIdOf(current.entry);
            }
          } else {
            manualStart();
          }
        } else if (action === 'finish') {
          finishRunning({ automatic: false });
        } else if (action === 'refresh') {
          refresh();
        }
      });
    }
    for (const button of doc.querySelectorAll('[data-focus-mode]')) {
      button.addEventListener('click', (event) => {
        event.preventDefault();
        if (button.dataset.focusMode === mode) return;
        mode = button.dataset.focusMode;
        try { localStorage.setItem(MODE_STORAGE_KEY, mode); } catch (_) {}
        renderModePills();
        if (isRunning) {
          notify('计时模式将在下一轮专注时生效。');
        } else if (segment) {
          // Paused session keeps its remaining time; mode applies next round.
          notify('计时模式将在下一轮专注时生效。');
        } else {
          render(); // Re-base the standing preview on the new mode.
        }
      });
    }
    const visibility = () => {
      if (doc.documentElement.dataset.pageVisible === 'false') return;
      // Safety net for a throttled background timer: when this page becomes
      // visible with an overdue task and no live session, start it now.
      if (!current && !isRunning && !segment && upcoming.length
        && upcoming[0].start <= nowMinutes(new Date())) {
        promote(upcoming[0]);
        return;
      }
      render();
    };
    doc.addEventListener('stitch:visibility', visibility);

    refresh();

    return {
      refresh,
      dispose() {
        disposed = true;
        generation++;
        stopTimers();
        doc.removeEventListener('stitch:visibility', visibility);
      },
    };
  }

  scope.StitchFocus = {
    mount,
    occursOnDay,
    todaysEntries,
    selectCurrentNext,
    countConflicts,
    formatCountdown,
    cognitiveLoadFor,
    tagLabel,
    durationMinutes,
    EMPTY_TEXT,
  };
})(typeof window === 'undefined' ? globalThis : window);
