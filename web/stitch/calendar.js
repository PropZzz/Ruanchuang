((scope) => {
  const scriptUrl = typeof document === 'undefined' ? null : document.currentScript.src;
  const pad = n => String(n).padStart(2, '0');
  const dayKey = date => `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
  function parseDay(value) {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(value || '')) return null;
    const [year, month, day] = value.split('-').map(Number);
    const date = new Date(year, month - 1, day, 12);
    return dayKey(date) === value ? date : null;
  }
  const addDays = (date, amount) => { const next = new Date(date); next.setDate(next.getDate() + amount); return next; };
  function addMonths(date, amount) {
    const next = new Date(date);
    next.setDate(1); next.setMonth(next.getMonth() + amount);
    next.setDate(Math.min(date.getDate(), new Date(next.getFullYear(), next.getMonth() + 1, 0).getDate()));
    return next;
  }
  const dayNumber = date => Date.UTC(date.getFullYear(), date.getMonth(), date.getDate()) / 86400000;
  function visibleRange(view, selected) {
    let start = parseDay(selected) || new Date();
    let count = view === 'day' ? 1 : 7;
    if (view === 'month') { start.setDate(1); count = 42; }
    if (view !== 'day') start = addDays(start, -((start.getDay() + 6) % 7));
    const days = Array.from({ length: count }, (_, i) => dayKey(addDays(start, i)));
    return { start: days[0], end: days.at(-1), days };
  }
  function occurrences(entries, from, to) {
    const result = [];
    for (const entry of entries) {
      const floating = entry.day == null;
      const origin = floating ? parseDay(from) : parseDay(entry.day);
      if (!origin || !entry.id) continue;
      const duration = Math.max(1, Math.min(10080, Math.round((Number(entry.height) || 60) * 60 / 80)));
      const first = addDays(parseDay(from), -Math.ceil(duration / 1440));
      const monthlyDays = new Set();
      if (!floating && entry.repeat === 'monthly') {
        for (let occurrence = origin; dayKey(occurrence) <= to; occurrence = addMonths(occurrence, 1)) {
          if (occurrence >= first) monthlyDays.add(dayKey(occurrence));
        }
      }
      for (let date = first; dayKey(date) <= to; date = addDays(date, 1)) {
        const key = dayKey(date);
        if (!floating && (key < entry.day || (entry.repeatUntil && key > entry.repeatUntil))) continue;
        const delta = dayNumber(date) - dayNumber(origin);
        const repeats = floating || key === entry.day || entry.repeat === 'daily' ||
          (entry.repeat === 'weekly' && delta % 7 === 0) ||
          monthlyDays.has(key);
        if (!repeats) continue;
        const start = Math.max(0, Math.min(1439, (Number(entry.time?.hour) || 0) * 60 + (Number(entry.time?.minute) || 0)));
        for (let offset = 0; offset * 1440 < start + duration; offset++) {
          const day = dayKey(addDays(date, offset));
          if (day < from || day > to) continue;
          result.push({ ...entry, day, sourceDay: entry.day, occurrenceDay: key,
            start: offset ? 0 : start, end: Math.min(1440, start + duration - offset * 1440),
            continuation: offset > 0, key: `${entry.id}:${key}:${offset}` });
        }
      }
    }
    return result.sort((a, b) => a.day.localeCompare(b.day) || a.start - b.start || a.end - b.end || String(a.id).localeCompare(String(b.id)));
  }
  function layoutEvents(events) {
    const sorted = events.map(e => ({ ...e })).sort((a, b) => a.start - b.start || b.end - a.end);
    let group = [], ends = [], groupEnd = -1;
    const finish = () => { for (const e of group) e.columns = ends.length; group = []; ends = []; };
    for (const event of sorted) {
      if (event.start >= groupEnd) finish();
      let column = ends.findIndex(end => end <= event.start);
      if (column < 0) column = ends.length;
      ends[column] = event.end;
      event.column = column; group.push(event); groupEnd = Math.max(groupEnd, event.end);
    }
    finish(); return sorted;
  }
  function countConflicts(events) {
    let count = 0;
    events.forEach((left, index) => {
      for (const right of events.slice(index + 1)) if (left.start < right.end && right.start < left.end) count++;
    });
    return count;
  }
  // 与 countConflicts 同口径，但返回冲突对本身，供救援摘要计算受影响日程与风险等级。
  function conflictPairs(events) {
    const pairs = [];
    events.forEach((left, index) => {
      for (const right of events.slice(index + 1)) if (left.start < right.end && right.start < left.end) pairs.push([left, right]);
    });
    return pairs;
  }
  function ganttRows(events, from) {
    const rows = new Map(), origin = dayNumber(parseDay(from)) * 1440;
    for (const event of events) {
      const key = JSON.stringify([event.id, event.occurrenceDay]);
      const start = dayNumber(parseDay(event.day)) * 1440 - origin + event.start;
      const end = dayNumber(parseDay(event.day)) * 1440 - origin + event.end;
      const row = rows.get(key);
      if (!row) rows.set(key, { event, endEvent: event, start, end, minutes: event.end - event.start });
      else {
        if (start < row.start) { row.start = start; row.event = event; }
        if (end > row.end) { row.end = end; row.endEvent = event; }
        row.minutes += event.end - event.start;
      }
    }
    return [...rows.values()].sort((a, b) => a.start - b.start || a.end - b.end || String(a.event.id).localeCompare(String(b.event.id)));
  }
  const escape = text => String(text ?? '').replace(/[&<>"']/g, char => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[char]);
  const clock = minutes => `${pad(Math.floor(minutes / 60))}:${pad(minutes % 60)}`;
  const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
  // The same palette as the original time-map demo, selected from persisted fields.
  const eventThemes = {
    focus: { color: 0xff163d3d, background: '#163d3d', foreground: '#81a8a7', title: '#ffffff', accent: '#72fe88', icon: 'psychology' },
    collaboration: { color: 0xff62a1fe, background: 'rgba(98,161,254,.4)', foreground: '#00376f', title: '#002727', accent: '#005db5', icon: 'groups' },
    ordinary: { color: 0xffe9e7ed, background: '#e9e7ed', foreground: '#1a1b1f', title: '#1a1b1f', accent: '#005db5', icon: 'code' },
    research: { color: 0xffefedf3, background: '#efedf3', foreground: '#1a1b1f', title: '#1a1b1f', accent: '#163d3d', icon: 'edit_note' },
    recovery: { color: 0xff72fe88, background: '#72fe88', foreground: '#002107', title: '#002107', accent: '#00531c', icon: 'spa' },
    urgent: { color: 0xffffdad6, background: '#ffdad6', foreground: '#93000a', title: '#93000a', accent: '#ba1a1a', icon: 'crisis_alert' },
    routine: { color: 0xffc2eae9, background: '#c2eae9', foreground: '#274d4d', title: '#002727', accent: '#3f6564', icon: 'event_repeat' },
    learning: { color: 0xffd6e3ff, background: '#d6e3ff', foreground: '#00468b', title: '#001b3d', accent: '#005db5', icon: 'school' },
    study: { color: 0xffede5f5, background: '#ede5f5', foreground: '#51465f', title: '#2c2438', accent: '#685478', icon: 'menu_book' },
    exam: { color: 0xfff5e6c8, background: '#f5e6c8', foreground: '#5e491d', title: '#3d2f11', accent: '#806026', icon: 'quiz' },
    leisure: { color: 0xffe1eedf, background: '#e1eedf', foreground: '#36583a', title: '#203e23', accent: '#3f6b43', icon: 'self_improvement' },
  };
  const scheduleTagThemes = {
    日常规程: 'routine', 上课学习: 'learning', 作业自习: 'study', 考试复习: 'exam',
    工作会议: 'collaboration', 项目推进: 'focus', 运动休息: 'leisure',
  };
  // Local display options written by the calendar-options drawer. They shape
  // this device's rendering only; persisted schedule data stays untouched.
  const optionsKey = 'ruanchuang-calendar-options';
  const defaultOptions = { startHour: 8, endHour: 21, hourHeight: 60, nowLine: true, autoScroll: true };
  function readOptions() {
    try {
      const stored = JSON.parse(localStorage.getItem(optionsKey) || '{}');
      const merged = { ...defaultOptions, ...(stored && typeof stored === 'object' ? stored : {}) };
      return {
        startHour: Math.max(0, Math.min(24, Number(merged.startHour) || 8)),
        endHour: Math.max(1, Math.min(24, Number(merged.endHour) || 21)),
        hourHeight: [44, 60, 80].includes(merged.hourHeight) ? merged.hourHeight : 60,
        nowLine: merged.nowLine !== false,
        autoScroll: merged.autoScroll !== false,
      };
    } catch (_) {
      return { ...defaultOptions };
    }
  }
  function themeFor(entry) {
    const tag = String(entry.tag || '');
    const name = Object.hasOwn(scheduleTagThemes, tag) ? scheduleTagThemes[tag]
      : /紧急|urgent/i.test(tag) ? 'urgent' : /恢复|休息|recovery/i.test(tag) ? 'recovery'
      : /协同|协作|团队|会议/.test(tag) ? 'collaboration' : /评审|深度|专注/.test(tag) ? 'focus'
      : /随笔|调研|复盘|走查/.test(tag) ? 'research' : /编码|开发/.test(tag) ? 'ordinary'
      : Object.keys(eventThemes).find(name => eventThemes[name].color === Number(entry.color)) || 'ordinary';
    return { name, ...eventThemes[name] };
  }

  function classroomFor(entry) {
    if (entry.tag !== '上课学习') return '';
    const notes = String(entry.description || '').trim();
    const labelled = notes.match(/(?:^|[\n;；·])\s*(?:上课教室|上课地点|教室|地点|location)\s*[:：]\s*([^\n;；·]+)/i);
    if (labelled) return labelled[1].trim();
    // Existing imports store teacher and room in notes, separated by a middle dot.
    // A teacher-only or free-form study note must never become a classroom label.
    const parts = notes.split(/[·\n]/).map(part => part.trim()).filter(Boolean);
    return parts.find(part => /(?:座|楼|馆|室|厅|教学|教\s*\d|room|building|lab).*\d|\d.*(?:教室|实验室)|^(?:[A-Z][-\s]?)?\d{2,4}(?:室)?$|^(?:.*(?:操场|体育场|体育馆|游泳馆)|线上授课|在线课堂)$/i.test(part)) || '';
  }

  // 智能规划算法预留接口：接入真实算法前原样返回账号日程。
  // 约定：入参为账号日程记录数组；返回用于展示的记录数组。算法可重排时间与时段，
  // 但不得修改入参元素、不得丢弃 id（详情抽屉依赖 id 打开）。实现时替换本函数体
  // （或在内部调用调度引擎），保持同步签名与"不写库、仅影响展示"的语义。
  function planEntries(records) {
    return records;
  }

  function mount(doc, { request, navigate, identity, state = {}, onState = () => {}, readRescueContext = null }) {
    const root = doc.getElementById('live-calendar-root');
    const win = doc.defaultView;
    const mobile = win.innerWidth <= 780;
    const style = doc.createElement('link'); style.rel = 'stylesheet'; style.id = 'ruanchuang-calendar-styles';
    const css = new URL('assets/calendar.css', scriptUrl); css.searchParams.set('v', scriptUrl.split('/').at(-1)); style.href = css.href;
    doc.head.append(style);
    let selected = parseDay(state.day) ? state.day : dayKey(new Date());
    const views = ['day', 'week', 'month', 'gantt'];
    let view = views.includes(state.view) ? state.view : mobile ? 'day' : 'week';
    let ganttScale = state.ganttScale === 'day' ? 'day' : 'week';
    // 调度模式：smart（智能规划）与 manual（手动安排）二者选一，默认智能规划。
    let mode = state.mode === 'manual' || state.mode === 'smart' ? state.mode : 'smart';
    let options = readOptions();
    let entries = [], loaded = false, pending = false, error = null, generation = 0, timer = null, disposed = false;
    let lastToday = dayKey(new Date());
    // 救援摘要侧栏的数据：服务端救援历史（最近一次救援快照卡）与生成守卫。
    let rescueHistory = null;
    let rescueHistoryTurn = 0;
    const account = identity();
    const remember = () => Object.assign(state, { day: selected, view, ganttScale, mode });
    const icon = name => `<span class="material-symbols-outlined" aria-hidden="true">${name}</span>`;
    const action = (name, label, content, extra = '') => `<button type="button" data-cal-action="${name}" aria-label="${label}" ${extra}>${content}</button>`;
    const create = (day = selected, time = '09:00') => navigate(`create-schedule?day=${day}&time=${encodeURIComponent(time)}`);
    // 把当前调度模式同步到分段按钮（互斥选中态）、根节点标记与提示语。
    function syncModeControls() {
      root.dataset.calendarMode = mode;
      for (const button of root.querySelectorAll('[data-cal-mode]')) {
        const active = button.dataset.calMode === mode;
        button.setAttribute('aria-pressed', String(active));
        const label = button.querySelector('[data-cal-mode-label]');
        if (label) label.textContent = active ? '智能规划已激活' : '智能规划';
      }
      const hint = doc.getElementById('calendar-mode-hint');
      if (hint) hint.textContent = mode === 'smart'
        ? '智能规划已激活：调度算法接口已预留，当前按已保存日程原样展示'
        : '手动安排：日程以保存的内容为准，可直接新增、编辑与删除';
    }
    function setMode(next) {
      if (mode === next) return;
      mode = next;
      remember();
      syncModeControls();
      // 重新读取并应用调度结果：接入真实算法后，切换模式即按新算法重排当前视域。
      refresh();
    }
    // 读取宿主注入的救援上下文（最近生成的服务端方案与可撤销快照）。
    const rescueContext = () => {
      try {
        return typeof readRescueContext === 'function' ? readRescueContext() : null;
      } catch (_) {
        return null;
      }
    };
    // 最近一次救援快照卡：数据源为 GET /schedule/rescue/history（服务端救援事件）。
    function renderRescueSnapshotCard() {
      const nameNode = doc.getElementById('calendar-rescue-snapshot-name');
      if (!nameNode) return;
      const stateNode = doc.getElementById('calendar-rescue-snapshot-state');
      const copyNode = doc.getElementById('calendar-rescue-snapshot-copy');
      const latest = Array.isArray(rescueHistory) ? rescueHistory[0] : null;
      if (!latest) {
        nameNode.textContent = '暂无已加载的快照';
        if (stateNode) stateNode.textContent = rescueHistory === null ? '待同步' : '待执行';
        if (copyNode) copyNode.textContent = rescueHistory === null
          ? '正在读取服务端救援历史；同步失败时可稍后重试。'
          : '执行真实救援方案后，将创建可撤销的服务端快照。';
        return;
      }
      nameNode.textContent = latest.title || '救援方案';
      const undone = String(latest.reason || '').startsWith('rescue_undo:');
      if (stateNode) stateNode.textContent = undone ? '已撤销' : '已执行';
      const at = latest.at ? new Date(latest.at) : null;
      const strategy = String(latest.reason || '').split(':')[1];
      const atText = at && !Number.isNaN(at.getTime())
        ? `${pad(at.getMonth() + 1)}-${pad(at.getDate())} ${clock(at.getHours() * 60 + at.getMinutes())} · `
        : '';
      // 是否还能回滚以账号的可用快照为准，而不是"存在过救援历史"。
      const canUndo = Boolean(rescueContext()?.hasSnapshot);
      if (copyNode) copyNode.textContent = `${atText}${undone ? '服务端已撤销救援并恢复原日程' : '服务端已创建救援快照'}${strategy ? `（策略 ${strategy}）` : ''}，${canUndo ? '可通过"撤销上次自动调度"回滚。' : '当前没有可撤销的快照。'}`;
    }
    // 拉取服务端救援历史；独立于日程同步，不阻塞 aria-busy。
    async function refreshRescueHistory() {
      const turn = ++rescueHistoryTurn;
      try {
        const events = await request('/schedule/rescue/history');
        if (disposed || turn !== rescueHistoryTurn) return;
        rescueHistory = Array.isArray(events) ? events : [];
      } catch (_) {
        if (disposed || turn !== rescueHistoryTurn) return;
        rescueHistory = null;
      }
      renderRescueSnapshotCard();
    }
    // 推荐救援方案预览：已生成时回填服务端三方案的真实指标；否则按冲突状态给出诚实占位。
    function renderRescuePreview(pairs, { syncing, hasError }) {
      const context = rescueContext();
      const matchesBaseline = context?.day === selected && !context?.snapshotId &&
        Array.isArray(context?.currentEntries) && JSON.stringify(context.currentEntries) === JSON.stringify(entries);
      const generated = matchesBaseline && Array.isArray(context?.options) ? context.options : [];
      const idle = !generated.length;
      const idleTitles = { A: '优先保护截止期', B: '最小化团队扰动', C: '顺延次日非核心目标' };
      for (let index = 0; index < 3; index++) {
        const letter = 'ABC'[index];
        const card = root.querySelector(`[data-rescue-preview-option="${letter}"]`);
        if (!card) continue;
        const option = generated[index] || null;
        card.classList.toggle('cal-rescue-preview-idle', idle);
        const titleNode = card.querySelector('[data-rescue-preview-title]');
        const checkNode = card.querySelector('[data-rescue-preview-check]');
        const noteNode = card.querySelector('[data-rescue-preview-note]');
        const metric = name => card.querySelector(`[data-rescue-preview-metric="${name}"]`);
        if (option) {
          if (titleNode) titleNode.textContent = `方案 ${letter} · ${option.title || '服务端方案'}`;
          if (checkNode) checkNode.hidden = !option.recommended;
          const moved = metric('moved');
          if (moved) moved.textContent = `${option.movedEntryCount ?? 0} 项`;
          const buffer = metric('buffer');
          if (buffer) buffer.textContent = `${option.recoveryMinutes ?? 0}m`;
          const score = metric('score');
          if (score) score.textContent = Number.isFinite(Number(option.score))
            ? String(Math.round(Number(option.score) * 10) / 10)
            : '—';
          if (noteNode && (option.rationale || option.tradeoff)) {
            noteNode.textContent = option.rationale || option.tradeoff;
          }
          continue;
        }
        if (checkNode) checkNode.hidden = true;
        const idleText = syncing || hasError ? '待同步' : pairs.length ? '待生成' : '无需救援';
        if (titleNode) titleNode.textContent = `方案 ${letter} · ${idleTitles[letter]}`;
        for (const name of ['moved', 'buffer', 'score']) {
          const node = metric(name);
          if (node) node.textContent = idleText;
        }
        if (noteNode && !syncing && !hasError) {
          noteNode.textContent = pairs.length
            ? '检测到时间重叠；插入紧急任务并填写截止时间后，由服务端计算三套救援排期。'
            : '当前日期没有时间重叠；如需插入紧急任务，服务端会在现有空档中安排。';
        }
      }
    }
    // 日程健康与救援摘要侧栏：撤销按钮状态 + 快照卡 + 方案预览，全部随真实数据刷新。
    function renderRescueSummaryPanel(pairs, { syncing, hasError }) {
      const context = rescueContext();
      const undoButton = root.querySelector('[data-rescue-undo]');
      if (undoButton) undoButton.disabled = !context?.hasSnapshot;
      renderRescueSnapshotCard();
      renderRescuePreview(pairs, { syncing, hasError });
    }
    const setText = (selector, text) => { const node = root.querySelector(selector); if (node) node.textContent = text; };
    const period = doc.getElementById('calendar-period');
    const dateLabel = doc.createElement('label'); dateLabel.className = 'cal-date-label'; dateLabel.title = '选择日期';
    period.before(dateLabel); dateLabel.append(period);
    const dateInput = doc.createElement('input'); dateInput.type = 'date'; dateInput.dataset.calDate = '';
    dateInput.setAttribute('aria-label', '选择日期'); dateInput.min = '1900-01-01'; dateInput.max = '2100-12-31'; dateLabel.append(dateInput);
    dateLabel.addEventListener('click', () => { try { dateInput.showPicker?.(); } catch (_) {} });
    // Bind the incumbent controls without rebuilding the controller deck or rescue panels.
    // 调度模式分段（手动安排 / 智能规划）走统一的 data-cal-action 分发，互斥切换。
    for (const button of root.querySelectorAll('[data-cal-mode]')) button.dataset.calAction = `mode-${button.dataset.calMode}`;
    for (const button of root.querySelectorAll('button')) {
      const text = button.textContent.trim(), symbol = button.querySelector('.material-symbols-outlined')?.textContent.trim();
      let name = ({ '日视图': 'day', '周视图': 'week', '月视图': 'month', '甘特视图': 'gantt', '日': 'day', '周': 'week', '月': 'month', '甘特': 'gantt', '今天': 'today' })[text];
      if (symbol === 'chevron_left') name = 'previous';
      if (symbol === 'chevron_right') name = 'next';
      if (/新增普通日程/.test(text) || button.getAttribute('aria-label') === '新增日程') name = 'create';
      if (/插入紧急任务/.test(text) || (mobile && button.getAttribute('onclick')?.includes("classList.remove('translate-y-full')"))) name = 'urgent';
      if (symbol === 'tune' && button.getAttribute('aria-label') === '日历显示选项') name = 'options';
      if (name) {
        button.dataset.calAction = name; button.removeAttribute('onclick');
        if (name === 'urgent') { button.removeAttribute('aria-controls'); button.removeAttribute('aria-expanded'); }
      }
    }
    if (mobile) {
      const controls = dateLabel.parentElement.parentElement.lastElementChild;
      controls.innerHTML = action('previous', '上一周期', icon('chevron_left')) + action('today', '回到今天', '今天') + action('next', '下一周期', icon('chevron_right'));
      controls.classList.add('cal-mobile-period');
    }
    const viewButtons = [...root.querySelectorAll('[data-cal-action]')].filter(b => views.includes(b.dataset.calAction));
    for (const button of viewButtons) button.className = mobile
      ? 'px-3 py-1.5 rounded-lg text-xs font-medium text-on-surface-variant cal-view-button'
      : 'px-3 py-1.5 rounded-md text-xs font-medium text-on-surface-variant cal-view-button';
    const sync = root.querySelector('[data-calendar-status]');
    const syncText = doc.createElement('span'); sync.replaceWith(syncText); syncText.dataset.calendarStatus = ''; syncText.setAttribute('role', 'status');
    const retry = doc.createElement('button'); retry.type = 'button'; retry.dataset.calAction = 'retry'; retry.className = 'cal-sync-retry'; retry.setAttribute('aria-label', '刷新日程'); retry.innerHTML = icon('sync'); syncText.after(retry);
    const dateHead = doc.getElementById('calendar-date-head');
    const allDay = doc.getElementById('calendar-all-day');
    const canvas = doc.getElementById('calendar-time-canvas');
    const mobileEvents = doc.getElementById('calendar-mobile-events');
    const month = doc.getElementById('calendar-month');
    const gantt = doc.createElement('div'); gantt.id = 'calendar-gantt'; gantt.className = 'cal-gantt-scroll'; gantt.hidden = true;
    gantt.tabIndex = 0; gantt.setAttribute('role', 'region'); gantt.setAttribute('aria-label', '甘特视图，按周展示日程时间轴，可横向滚动'); month.after(gantt);
    const ganttTools = doc.createElement('div'); ganttTools.className = 'cal-gantt-tools'; ganttTools.hidden = true;
    ganttTools.innerHTML = `<span>甘特时间轴</span><div>${action('gantt-week', '按周查看甘特图', '按周')}${action('gantt-day', '按日查看甘特图', '按日')}</div>`;
    gantt.before(ganttTools);
    let startMinute = 480;
    const eventLabel = event => `${event.title}，${event.day} ${clock(event.start)}至${clock(event.end)}${classroomFor(event) ? '，教室：' + classroomFor(event) : ''}${event.repeat && event.repeat !== 'none' ? '，重复日程，编辑将修改整条规则' : ''}`;
    function eventButton(event, compact = false) {
      const theme = themeFor(event), repeats = event.repeat && event.repeat !== 'none', classroom = classroomFor(event);
      const style = `--cal-event-bg:${theme.background};--cal-event-fg:${theme.foreground};--cal-event-title:${theme.title};--cal-event-accent:${theme.accent}`;
      return `<button type="button" class="cal-event ${compact ? 'cal-event-compact' : ''} ${classroom ? 'cal-event-course' : ''} p-2 rounded-xl shadow-sm flex flex-col text-left" style="${style}" data-cal-theme="${theme.name}" data-calendar-event="${escape(event.id)}" data-schedule-id="${escape(event.id)}" aria-label="${escape(eventLabel(event))}" title="${escape(eventLabel(event))}"><div class="cal-event-meta"><span class="cal-event-category">${icon(theme.icon)}<span>${escape(event.tag || '日程')}</span></span><span class="cal-event-time">${event.continuation ? '续 ' : ''}${clock(event.start)}${compact ? '' : ' – ' + clock(event.end)}</span></div><strong class="text-xs font-bold leading-tight line-clamp-2">${escape(event.title || '未命名日程')}</strong>${classroom ? `<span class="cal-event-location" aria-label="教室：${escape(classroom)}">${icon('location_on')}<span>${escape(classroom)}</span></span>` : ''}${!compact && !classroom ? `<div class="cal-event-footer"><span class="cal-event-tag">${escape(event.tag || '日程')}${repeats ? ' · 重复' : ''}</span><span class="cal-event-duration">${event.end - event.start}m</span></div>` : ''}</button>`;
    }
    function render() {
      if (disposed) return;
      const focusedDay = doc.activeElement?.dataset.calSelect;
      if (doc.documentElement.dataset.pageVisible !== 'false') remember();
      const periodView = view === 'gantt' ? ganttScale : view;
      const range = visibleRange(periodView, selected), today = dayKey(new Date()), date = parseDay(selected);
      const items = occurrences(entries, range.start, range.end), chosen = occurrences(entries, selected, selected);
      const conflictPairList = conflictPairs(chosen);
      const conflicts = conflictPairList.length;
      root.dataset.calendarView = view; root.dataset.selectedDay = selected; root.setAttribute('aria-busy', String(pending));
      syncModeControls();
      dateInput.value = selected;
      const weekStart = parseDay(visibleRange('week', selected).start);
      const firstThursday = addDays(weekStart, 3);
      const week = Math.floor((dayNumber(firstThursday) - dayNumber(new Date(firstThursday.getFullYear(), 0, 1))) / 7) + 1;
      period.textContent = `${date.getFullYear()}年${date.getMonth() + 1}月${periodView === 'day' ? date.getDate() + '日' : !mobile && periodView === 'week' ? ' 第' + week + '周' : ''}`;
      setText('#calendar-range', mobile ? `第 ${week} 周` : periodView === 'day' ? `星期${weekdays[(date.getDay() + 6) % 7]}` : `${range.start.replaceAll('-', '/')} – ${range.end.replaceAll('-', '/')}`);
      for (const button of viewButtons) button.setAttribute('aria-pressed', String(button.dataset.calAction === view));
      for (const button of root.querySelectorAll('[data-cal-action="previous"], [data-cal-action="next"]')) button.setAttribute('aria-label', `${button.dataset.calAction === 'previous' ? '上一' : '下一'}${({day:'天',week:'周',month:'月'})[periodView]}`);
      const count = new Set(items.map(e => `${e.id}:${e.occurrenceDay}`)).size;
      const status = pending ? '正在同步日程…' : error ? error.status === 401 ? '登录后查看你的日程' : loaded ? '同步失败，正在显示上次读取的日程' : '暂时无法读取日程，请重试' : `已同步 · 当前视图 ${count} 项日程`;
      syncText.textContent = status; retry.dataset.calAction = error?.status === 401 ? 'login' : 'retry'; retry.setAttribute('aria-label', error?.status === 401 ? '去登录' : '刷新日程');
      setText('#calendar-total', `${selected === today ? '今日' : '所选日期'} ${chosen.length} 项日程`);
      setText('#calendar-duration', `已安排 ${chosen.reduce((sum, e) => sum + e.end - e.start, 0)} 分钟`);
      const conflictText = pending ? '正在检查所选日期…' : error ? '同步后检查日程冲突' : conflicts ? `所选日期有 ${conflicts} 处时间重叠` : '所选日期暂无时间重叠';
      setText(mobile ? '#schedule-conflict-status' : '#calendar-conflict-status', conflictText);
      setText(mobile ? '#schedule-conflict-severity' : '#calendar-conflict-severity', pending || error ? '等待同步' : conflicts ? '需要处理' : '当前正常');
      setText('#calendar-banner-conflicts', pending || error ? '日程检查待同步' : conflicts ? `待解决冲突 ${conflicts} 处` : '日程暂无冲突');
      setText('#calendar-banner-copy', '按所选日期检查');
      // 救援摘要侧栏的真实数据：受影响日程、重叠时长与风险等级都由当天日程推导。
      const affectedEntries = [];
      const affectedSeen = new Set();
      let overlapMinutes = 0;
      for (const [left, right] of conflictPairList) {
        overlapMinutes += Math.min(left.end, right.end) - Math.max(left.start, right.start);
        for (const occurrence of [left, right]) {
          if (occurrence.id && !affectedSeen.has(occurrence.id)) {
            affectedSeen.add(occurrence.id);
            affectedEntries.push(occurrence);
          }
        }
      }
      const riskLabel = !conflictPairList.length || (conflictPairList.length === 1 && overlapMinutes <= 30)
        ? '低'
        : conflictPairList.length <= 2 || overlapMinutes <= 90 ? '中' : '高';
      const conflictCopy = pending
        ? '正在根据当前日期的真实日程检查时间重叠…'
        : error
          ? '日程同步后检查冲突；可编辑日程调整时间，或填写紧急任务生成救援方案。'
          : affectedEntries.length
            ? `当前日期有 ${affectedEntries.length} 项日程互相重叠：${affectedEntries.slice(0, 3).map(e => e.title || '未命名日程').join('、')}${affectedEntries.length > 3 ? ' 等' : ''}。可编辑重叠日程调整时间，或插入紧急任务由服务端生成三方案救援对比。重复日程的编辑或删除会作用于整条规则。`
            : '根据当前日期的真实日程检查，暂无时间重叠；可编辑日程调整时间，或填写紧急任务生成救援方案。重复日程的编辑或删除会作用于整条规则。';
      setText(mobile ? '#schedule-conflict-copy' : '#calendar-conflict-copy', conflictCopy);
      const riskNode = root.querySelector(mobile ? '#schedule-conflict-risk' : '#calendar-conflict-risk');
      if (riskNode) {
        const riskTarget = mobile ? riskNode.querySelector('span:last-child') || riskNode : riskNode;
        riskTarget.textContent = pending || error
          ? (mobile ? '紧急任务风险：待分析' : '救援风险：待服务端分析')
          : mobile
            ? `紧急任务风险：${riskLabel}`
            : `救援风险：${riskLabel}（${conflictPairList.length ? `${conflictPairList.length} 处重叠 ${overlapMinutes} 分钟` : '当前无重叠'}）`;
      }
      const affectedNode = root.querySelector('#calendar-conflict-affected');
      if (affectedNode) {
        affectedNode.textContent = pending || error
          ? '受影响日程：待分析'
          : affectedEntries.length ? `受影响日程：${affectedEntries.length} 项` : '受影响日程：无';
      }
      renderRescueSummaryPanel(conflictPairList, { syncing: pending, hasError: Boolean(error) });
      const banner = root.querySelector('#calendar-banner-conflicts')?.closest('.animate-pulse'); banner?.classList.remove('animate-pulse');
      month.hidden = view !== 'month';
      gantt.hidden = view !== 'gantt';
      ganttTools.hidden = gantt.hidden;
      for (const button of ganttTools.querySelectorAll('button')) button.setAttribute('aria-pressed', String(button.dataset.calAction === `gantt-${ganttScale}`));
      if (view !== 'gantt') gantt.replaceChildren();
      if (view !== 'month') month.replaceChildren();
      if (view === 'month' || view === 'gantt') { canvas?.replaceChildren(); mobileEvents?.replaceChildren(); }
      if (mobile) {
        renderDateHead(visibleRange('week', selected).days, today);
        mobileEvents.hidden = view === 'month' || view === 'gantt';
        if (view !== 'month' && view !== 'gantt') renderMobile(range, items);
        updateFocusStrip(chosen);
      } else {
        dateHead.hidden = view === 'month' || view === 'gantt'; allDay.hidden = dateHead.hidden; canvas.parentElement.hidden = dateHead.hidden;
        if (view !== 'month' && view !== 'gantt') renderTime(range, items, today);
      }
      if (view === 'month') month.innerHTML = monthMarkup(range, items, today);
      if (view === 'gantt') renderGantt(range, items, today);
      if (focusedDay) root.querySelector(`[data-cal-select="${focusedDay}"]`)?.focus({ preventScroll: true });
    }
    function renderDateHead(days, today) {
      dateHead.innerHTML = days.map(day => {
        const active = day === selected, current = day === today;
        return `<button type="button" data-cal-select="${day}" aria-label="选择${day}" ${current ? 'aria-current="date"' : ''} aria-pressed="${active}" class="cal-column-heading ${mobile ? `flex flex-col items-center justify-between min-w-[52px] h-[74px] p-2 rounded-xl shadow-sm shrink-0 ${active ? 'bg-primary text-on-primary' : 'bg-surface-container-lowest text-on-surface-variant'}` : `p-3 flex flex-col items-center justify-center gap-0.5 ${active ? 'bg-primary-container text-on-primary-container rounded-t-xl shadow-sm' : 'bg-surface-container-low text-on-surface'}`}"><span class="text-[11px] font-label">${current ? '今日·' : mobile ? '' : '周'}${weekdays[(parseDay(day).getDay() + 6) % 7]}</span><strong class="text-sm font-bold tabular-nums">${mobile ? parseDay(day).getDate() : day.slice(5).replace('-', '/')}</strong>${mobile ? '<span class="w-1.5 h-1.5 rounded-full bg-surface-tint"></span>' : current ? '<span class="text-[10px] font-label opacity-90">今日专注中</span>' : ''}</button>`;
      }).join('');
      if (!mobile) dateHead.insertAdjacentHTML('afterbegin', `<div class="p-3 text-[11px] font-semibold text-outline text-center flex flex-col justify-center"><span>时刻</span><span class="text-[9px] font-normal">${escape(Intl.DateTimeFormat().resolvedOptions().timeZone)}</span></div>`);
    }
    function emptyMarkup() {
      return `<div class="cal-empty p-5 text-xs text-outline">${pending && !loaded ? '正在读取日程' : error && !loaded ? '日程尚未加载' : '这一天还没有日程'}${!error ? action('create', '安排一项日程', '安排一项日程', 'class="text-secondary ml-3"') : ''}</div>`;
    }
    function renderTime(range, items, today) {
      const now = new Date(), minutes = now.getHours() * 60 + now.getMinutes();
      const scale = minutes => Math.round(minutes * options.hourHeight / 60);
      // Keep the configured window (default 08:00–21:00); expand only for the
      // live "now" marker and real off-hours events.
      startMinute = Math.min(options.startHour * 60, range.days.includes(today) ? now.getHours() * 60 : options.startHour * 60, ...items.map(e => Math.floor(e.start / 60) * 60));
      const end = Math.max(options.endHour * 60, range.days.includes(today) ? (now.getHours() + 1) * 60 : options.endHour * 60, ...items.map(e => Math.ceil(e.end / 60) * 60));
      const columns = `68px repeat(${range.days.length}, minmax(0,1fr))`;
      for (const node of [dateHead, allDay, canvas]) node.style.gridTemplateColumns = columns;
      renderDateHead(range.days, today);
      allDay.innerHTML = '<div class="text-[10px] text-outline font-semibold text-center">全天任务</div>' + range.days.map(() => '<div class="p-1"></div>').join('');
      canvas.style.setProperty('--cal-hour-height', `${options.hourHeight}px`);
      canvas.style.height = `${scale(end - startMinute)}px`;
      canvas.innerHTML = `<div class="flex flex-col text-[11px] text-outline tabular-nums select-none bg-surface-container-low/40">${Array.from({ length: (end - startMinute) / 60 }, (_, i) => `<div style="height:${options.hourHeight}px" class="p-1.5 text-right font-medium">${clock(startMinute + i * 60)}</div>`).join('')}</div>${range.days.map(day => `<div class="cal-time-column relative ${day === today ? 'bg-primary-container/[0.02]' : 'bg-surface-container-lowest'}" data-calendar-day="${day}">${layoutEvents(items.filter(e => e.day === day)).map(e => `<div class="cal-position" style="top:${scale(e.start - startMinute)}px;height:${Math.max(22, scale(e.end - e.start))}px;left:calc(${100 * e.column / e.columns}% + 4px);width:calc(${100 / e.columns}% - 8px)">${eventButton(e)}</div>`).join('')}${day === today && options.nowLine ? `<div class="cal-now" style="top:${scale(minutes - startMinute)}px" aria-label="当前时间 ${clock(minutes)}"><span class="cal-now-label">现在 ${clock(minutes)}</span></div>` : ''}</div>`).join('')}`;
      if (!items.length) canvas.insertAdjacentHTML('beforeend', `<div class="cal-map-empty">${emptyMarkup()}</div>`);
    }
    function renderMobile(range, items) {
      mobileEvents.innerHTML = range.days.map(day => {
        const events = items.filter(e => e.day === day);
        return `${view === 'week' ? `<h3 class="text-xs font-bold text-primary">${day} 星期${weekdays[(parseDay(day).getDay() + 6) % 7]}</h3>` : ''}${events.length ? events.map(e => `<div class="flex items-start gap-3" data-calendar-day="${day}"><div class="w-10 text-right shrink-0 pt-1"><span class="text-xs font-mono font-medium text-on-surface-variant">${clock(e.start)}</span><div class="text-[10px] font-mono text-outline mt-0.5">${e.end - e.start}m</div></div><div class="flex-1 min-w-0">${eventButton(e)}</div></div>`).join('') : emptyMarkup()}`;
      }).join('');
    }
    function updateFocusStrip(chosen) {
      const section = root.querySelector('section:nth-of-type(4)');
      if (!section) return;
      const now = new Date(), start = selected === dayKey(now) ? Math.min(1200, Math.floor(now.getHours() / 4) * 240) : 480;
      const header = section.querySelector('.font-semibold'); if (header) header.textContent = `当前 4 小时动态认知负荷 (${clock(start)} - ${clock(start + 240)})`;
      const marker = section.querySelector('.font-mono'); if (marker) marker.textContent = selected === dayKey(now) ? `${clock(now.getHours() * 60 + now.getMinutes())} 刻度` : '所选日期';
      const bar = section.querySelector('.overflow-hidden');
      if (bar) bar.innerHTML = Array.from({length:16}, (_, i) => { const point = start + i * 15; const active = chosen.filter(e => e.start < point + 15 && e.end > point); return `<div class="h-full rounded-sm ${active.length > 1 ? 'bg-error' : active.length ? 'bg-secondary' : 'bg-surface-container-highest'}" style="width:6.25%" title="${clock(point)} · ${active.length} 项日程"></div>`; }).join('');
      const legend = section.querySelector('.text-\\[10px\\]');
      if (legend) legend.innerHTML = '<span>空闲</span><span>重叠日程</span><span>按真实日程计算</span><span>已安排</span>';
    }
    function monthMarkup(range, items, today) {
      return `<div class="cal-month-weekdays">${weekdays.map(d => `<span>周${d}</span>`).join('')}</div><div class="cal-month-grid">${range.days.map(day => {
        const events = items.filter(e => e.day === day);
        return `<div class="cal-month-day ${day.slice(0,7) !== selected.slice(0,7) ? 'cal-outside' : ''} ${day === selected ? 'cal-selected' : ''}" data-calendar-day="${day}"><button type="button" class="cal-day-number" data-cal-select="${day}" aria-label="选择${day}" ${day === today ? 'aria-current="date"' : ''}>${parseDay(day).getDate()}</button>${events.slice(0,3).map(e => eventButton(e,true)).join('')}${events.length > 3 ? `<button type="button" class="text-xs text-secondary" data-cal-select="${day}" data-cal-open-day>另 ${events.length - 3} 项</button>` : ''}</div>`;
      }).join('')}</div>`;
    }
    function renderGantt(range, items, today) {
      const rows = ganttRows(items, range.start), total = range.days.length * 1440;
      const now = new Date(), nowOffset = range.days.indexOf(today) * 1440 + now.getHours() * 60 + now.getMinutes();
      const dateText = event => `${event.day.slice(5).replace('-', '/')} ${clock(event.start)}`;
      gantt.dataset.ganttScale = ganttScale;
      gantt.style.setProperty('--gantt-columns', ganttScale === 'day' ? '24' : '7');
      gantt.setAttribute('aria-label', `甘特视图，按${ganttScale === 'day' ? '日' : '周'}展示日程时间轴，可横向滚动`);
      const headings = ganttScale === 'day' ? Array.from({ length: 24 }, (_, hour) => `<div class="cal-gantt-hour">${pad(hour)}:00</div>`).join('')
        : range.days.map(day => `<button type="button" class="cal-gantt-day" data-cal-select="${day}" aria-label="选择${day}" aria-pressed="${day === selected}" ${day === today ? 'aria-current="date"' : ''}><span>周${weekdays[(parseDay(day).getDay() + 6) % 7]}</span><strong>${day.slice(5).replace('-', '/')}</strong>${day === today ? '<span>今天</span>' : ''}</button>`).join('');
      const cells = ganttScale === 'day' ? Array.from({ length: 24 }, () => '<span class="cal-gantt-cell" aria-hidden="true"></span>').join('')
        : range.days.map(day => `<span class="cal-gantt-cell ${day === selected ? 'cal-gantt-selected' : ''}" aria-hidden="true"></span>`).join('');
      gantt.innerHTML = `<div class="cal-gantt-grid"><div class="cal-gantt-head"><div class="cal-gantt-corner"><strong>日程 · ${rows.length} 项</strong><span>${ganttScale === 'day' ? selected.slice(5).replace('-', '/') + ' · 每格 1 小时' : '每格 1 天 · 可按日放大'}</span></div><div class="cal-gantt-days">${headings}</div></div>${rows.map(row => {
        const e = row.event, theme = themeFor(e), end = row.endEvent;
        const label = `${e.title || '未命名日程'}，${e.day} ${clock(e.start)}至${end.day} ${clock(end.end)}${classroomFor(e) ? '，教室：' + classroomFor(e) : ''}${e.repeat && e.repeat !== 'none' ? '，重复日程，编辑将修改整条规则' : ''}`;
        const colors = `--cal-event-bg:${theme.background};--cal-event-fg:${theme.foreground};--cal-event-title:${theme.title};--cal-event-accent:${theme.accent}`;
        return `<div class="cal-gantt-row" style="${colors}"><button type="button" class="cal-gantt-label" data-schedule-id="${escape(e.id)}" data-calendar-event="${escape(e.id)}" aria-label="${escape(label)}" title="${escape(label)}"><strong>${escape(e.title || '未命名日程')}</strong><span>${dateText(e)} – ${end.day === e.day ? '' : end.day.slice(5).replace('-', '/') + ' '}${clock(end.end)}</span><small>${escape(e.tag || '日程')}${classroomFor(e) ? ' · ' + escape(classroomFor(e)) : ''} · ${row.minutes}m${e.repeat && e.repeat !== 'none' ? ' · 重复' : ''}${e.continuation ? ' · 接上期' : ''}</small></button><div class="cal-gantt-track">${cells}<button type="button" class="cal-gantt-bar" data-cal-theme="${theme.name}" data-schedule-id="${escape(e.id)}" data-calendar-event="${escape(e.id)}" style="--gantt-start:${100 * row.start / total}%;--gantt-length:${100 * (row.end - row.start) / total}%" aria-label="${escape(label)}" title="${escape(label)}"><span>${escape(e.title || '未命名日程')}</span></button></div></div>`;
      }).join('')}${range.days.includes(today) ? `<div class="cal-gantt-now" style="--gantt-now:${nowOffset / total}" aria-label="当前时间 ${clock(now.getHours() * 60 + now.getMinutes())}"><span>现在</span></div>` : ''}</div>${!rows.length ? `<div class="cal-gantt-empty cal-empty">${pending && !loaded ? '正在读取日程' : error && !loaded ? '日程尚未加载' : (ganttScale === 'day' ? '这一天' : '本周') + '还没有日程'}${!error ? action('create', '安排一项日程', '安排一项日程', 'class="text-secondary"') : ''}</div>` : ''}`;
    }
    const activeScroll = () => view === 'gantt' ? gantt : root.querySelector('.cal-time-scroll');
    function scrollTime() {
      if (view === 'gantt') { gantt.scrollTop = 0; gantt.scrollLeft = 0; return; }
      const scroll = root.querySelector('.cal-time-scroll'); if (!scroll) return;
      if (!options.autoScroll) { scroll.scrollTop = 0; return; }
      const now = new Date();
      scroll.scrollTop = Math.max(0, (selected === dayKey(now) ? now.getHours() * 60 + now.getMinutes() : 540) - startMinute - 110);
    }
    async function refresh() {
      if (doc.documentElement.dataset.pageVisible === 'false') {
        if (parseDay(state.day)) selected = state.day;
        if (views.includes(state.view)) view = state.view;
        ganttScale = state.ganttScale === 'day' ? 'day' : 'week';
        if (state.mode === 'manual' || state.mode === 'smart') mode = state.mode;
      }
      const turn = ++generation;
      pending = true; error = null;
      const previousScroll = activeScroll();
      const position = previousScroll && { top: previousScroll.scrollTop, left: previousScroll.scrollLeft };
      render();
      if (position) restoreScroll(position); else scrollTime();
      refreshRescueHistory();
      onState('loading', '正在同步日程');
      try {
        const records = await request('/schedule');
        if (disposed || turn !== generation || account !== identity()) return;
        if (!Array.isArray(records)) throw new Error('日程响应格式不正确');
        const firstLoad = !loaded;
        // 智能规划模式经预留接口生成展示用的日程序列；手动安排直接展示账号数据。
        entries = mode === 'smart' ? planEntries(records) : records;
        loaded = true; pending = false;
        const pos = activeScroll();
        const keep = pos && { top: pos.scrollTop, left: pos.scrollLeft };
        render(); if (firstLoad) scrollTime(); else if (keep) restoreScroll(keep);
        onState('online', `已连接 · 日程 ${records.length} 条`);
      } catch (failure) {
        if (disposed || turn !== generation || account !== identity()) return;
        pending = false; error = failure;
        if (failure.status === 401) { entries = []; loaded = false; }
        render(); onState(failure.status === 401 ? 'auth-required' : 'offline', failure.status === 401 ? '请登录后同步' : '日程同步失败', failure);
      }
    }
    function restoreScroll(position) { const scroll = activeScroll(); if (scroll) { scroll.scrollTop = position.top; scroll.scrollLeft = position.left; } }
    function applyOptions(next) {
      if (JSON.stringify(next) === JSON.stringify(options)) return;
      options = next;
      if (!disposed) render();
    }
    function select(day, mode = view) {
      if (!parseDay(day)) return;
      selected = day; view = mode; remember(); render(); scrollTime(); refresh();
    }
    root.addEventListener('click', event => {
      const target = event.target.closest('button[data-cal-action], button[data-cal-select], button[data-calendar-event], button[data-rescue-preview-option]'); if (!target) return;
      event.preventDefault(); event.stopPropagation();
      if (target.dataset.calendarEvent) { navigate(`schedule-detail?id=${encodeURIComponent(target.dataset.calendarEvent)}`); return; }
      if (target.dataset.rescuePreviewOption) { navigate('urgent-task'); return; }
      if (target.dataset.calSelect) { select(target.dataset.calSelect, target.hasAttribute('data-cal-open-day') ? 'day' : view); return; }
      const name = target.dataset.calAction;
      if (views.includes(name)) select(selected, name);
      else if (name === 'mode-smart' || name === 'mode-manual') setMode(name === 'mode-smart' ? 'smart' : 'manual');
      else if (name === 'gantt-day' || name === 'gantt-week') { ganttScale = name === 'gantt-day' ? 'day' : 'week'; select(selected); }
      else if (name === 'today') select(dayKey(new Date()));
      else if (name === 'previous' || name === 'next') {
        const direction = name === 'next' ? 1 : -1;
        select(dayKey(view === 'month' ? addMonths(parseDay(selected), direction) : addDays(parseDay(selected), direction * (view === 'week' || (view === 'gantt' && ganttScale === 'week') ? 7 : 1))));
      } else if (name === 'create') create();
      else if (name === 'urgent' || name === 'rescue') navigate('urgent-task');
      else if (name === 'options') navigate('calendar-options');
      else if (name === 'retry') refresh();
      else if (name === 'login') navigate('login');
    });
    root.addEventListener('change', event => { if (event.target.matches('[data-cal-date]')) select(event.target.value); });
    function tick() {
      clearTimeout(timer);
      if (disposed || doc.documentElement.dataset.pageVisible === 'false') return;
      const today = dayKey(new Date());
      if (today !== lastToday) {
        if (selected === lastToday) selected = today;
        lastToday = today; refresh();
      } else {
        const now = new Date(), minutes = now.getHours() * 60 + now.getMinutes();
        for (const line of root.querySelectorAll('.cal-now')) {
          const top = Math.round((minutes - startMinute) * options.hourHeight / 60);
          line.hidden = !options.nowLine || top < 0 || top >= canvas.clientHeight;
          line.style.top = `${top}px`;
          line.setAttribute('aria-label', `当前时间 ${clock(minutes)}`);
          line.firstElementChild.textContent = `现在 ${clock(minutes)}`;
        }
        const ganttNow = gantt.querySelector('.cal-gantt-now');
        if (ganttNow) {
          const days = visibleRange(ganttScale, selected).days;
          ganttNow.style.setProperty('--gantt-now', `${(days.indexOf(today) * 1440 + minutes) / (days.length * 1440)}`);
          ganttNow.setAttribute('aria-label', `当前时间 ${clock(minutes)}`);
        }
      }
      timer = setTimeout(tick, 60000 - Date.now() % 60000);
    }
    const visibility = event => { if (event.detail.visible) { remember(); applyOptions(readOptions()); tick(); } else clearTimeout(timer); };
    doc.addEventListener('stitch:visibility', visibility);
    // The options drawer runs in a sibling iframe: it persists options to
    // localStorage and this page re-renders through the storage event.
    const onStorage = event => { if (event.key === optionsKey || event.key === null) applyOptions(readOptions()); };
    win.addEventListener('storage', onStorage);
    pending = true; render(); scrollTime(); tick();
    return { refresh, selectDay: day => select(day), getSelection: () => selected,
      dispose() { disposed = true; generation++; clearTimeout(timer); doc.removeEventListener('stitch:visibility', visibility); win.removeEventListener('storage', onStorage); } };
  }
  scope.StitchCalendar = { dayKey, parseDay, addDays, addMonths, visibleRange, occurrences, layoutEvents, countConflicts, ganttRows, themeFor, classroomFor, mount };
})(typeof window === 'undefined' ? globalThis : window);
