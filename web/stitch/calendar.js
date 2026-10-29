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
  const escape = text => String(text ?? '').replace(/[&<>"']/g, char => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[char]);
  const clock = minutes => `${pad(Math.floor(minutes / 60))}:${pad(minutes % 60)}`;
  const weekdays = ['一', '二', '三', '四', '五', '六', '日'];

  function mount(doc, { request, navigate, identity, state = {}, onState = () => {} }) {
    const root = doc.getElementById('live-calendar-root');
    const win = doc.defaultView;
    const mobile = win.innerWidth <= 780;
    const style = doc.createElement('link'); style.rel = 'stylesheet'; style.id = 'ruanchuang-calendar-styles';
    const css = new URL('assets/calendar.css', scriptUrl); css.searchParams.set('v', scriptUrl.split('/').at(-1)); style.href = css.href;
    doc.head.append(style);
    let selected = parseDay(state.day) ? state.day : dayKey(new Date());
    let view = ['day', 'week', 'month'].includes(state.view) ? state.view : mobile ? 'day' : 'week';
    let entries = [], loaded = false, pending = false, error = null, generation = 0, timer = null, disposed = false;
    let lastToday = dayKey(new Date());
    const account = identity();
    const remember = () => Object.assign(state, { day: selected, view });
    const icon = name => `<span class="material-symbols-outlined" aria-hidden="true">${name}</span>`;
    const action = (name, label, content, extra = '') => `<button type="button" data-cal-action="${name}" aria-label="${label}" ${extra}>${content}</button>`;
    const create = (day = selected, time = '09:00') => navigate(`create-schedule?day=${day}&time=${encodeURIComponent(time)}`);
    const setText = (selector, text) => { const node = root.querySelector(selector); if (node) node.textContent = text; };
    const period = doc.getElementById('calendar-period');
    const dateLabel = doc.createElement('label'); dateLabel.className = 'cal-date-label'; dateLabel.title = '选择日期';
    period.before(dateLabel); dateLabel.append(period);
    const dateInput = doc.createElement('input'); dateInput.type = 'date'; dateInput.dataset.calDate = '';
    dateInput.setAttribute('aria-label', '选择日期'); dateInput.min = '1900-01-01'; dateInput.max = '2100-12-31'; dateLabel.append(dateInput);
    dateLabel.addEventListener('click', () => { try { dateInput.showPicker?.(); } catch (_) {} });
    // Bind the incumbent controls without rebuilding the controller deck or rescue panels.
    for (const button of root.querySelectorAll('button')) {
      const text = button.textContent.trim(), symbol = button.querySelector('.material-symbols-outlined')?.textContent.trim();
      let name = ({ '日视图': 'day', '周视图': 'week', '月视图': 'month', '日': 'day', '周': 'week', '月': 'month', '今天': 'today' })[text];
      if (symbol === 'chevron_left') name = 'previous';
      if (symbol === 'chevron_right') name = 'next';
      if (/新增普通日程/.test(text) || button.getAttribute('aria-label') === '新增日程') name = 'create';
      if (/插入紧急任务/.test(text) || (mobile && button.getAttribute('onclick')?.includes("classList.remove('translate-y-full')"))) name = 'urgent';
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
    const viewButtons = [...root.querySelectorAll('[data-cal-action]')].filter(b => ['day', 'week', 'month'].includes(b.dataset.calAction));
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
    let startMinute = 480;
    const eventLabel = event => `${event.title}，${event.day} ${clock(event.start)}至${clock(event.end)}${event.repeat && event.repeat !== 'none' ? '，重复日程，编辑将修改整条规则' : ''}`;
    function eventButton(event, compact = false) {
      const theme = event.status === 'completed' ? 'bg-primary-container text-on-primary-container' : event.isUrgent ? 'bg-error-container text-on-error-container' : 'bg-surface-container-high text-on-surface';
      return `<button type="button" class="cal-event ${compact ? 'cal-event-compact' : event.end - event.start < 45 ? 'cal-event-short' : ''} p-2 rounded-xl ${theme} shadow-sm flex flex-col justify-between text-left" data-calendar-event="${escape(event.id)}" data-schedule-id="${escape(event.id)}" aria-label="${escape(eventLabel(event))}" title="${escape(eventLabel(event))}"><span class="text-[10px] font-label tabular-nums opacity-80">${event.continuation ? '续 ' : ''}${clock(event.start)}${!compact ? ' – ' + clock(event.end) : ''}${event.repeat && event.repeat !== 'none' ? ' · 重复' : ''}</span><strong class="text-xs font-bold leading-tight line-clamp-2">${escape(event.title || '未命名日程')}</strong>${!compact && event.tag ? `<span class="cal-event-tag text-[10px] opacity-75">${escape(event.tag)}</span>` : ''}</button>`;
    }
    function render() {
      if (disposed) return;
      const focusedDay = doc.activeElement?.dataset.calSelect;
      if (doc.documentElement.dataset.pageVisible !== 'false') remember();
      const range = visibleRange(view, selected), today = dayKey(new Date()), date = parseDay(selected);
      const items = occurrences(entries, range.start, range.end), chosen = occurrences(entries, selected, selected);
      const conflicts = countConflicts(chosen);
      root.dataset.calendarView = view; root.dataset.selectedDay = selected; root.setAttribute('aria-busy', String(pending));
      dateInput.value = selected;
      const weekStart = parseDay(visibleRange('week', selected).start);
      const firstThursday = addDays(weekStart, 3);
      const week = Math.floor((dayNumber(firstThursday) - dayNumber(new Date(firstThursday.getFullYear(), 0, 1))) / 7) + 1;
      period.textContent = `${date.getFullYear()}年${date.getMonth() + 1}月${view === 'day' ? date.getDate() + '日' : !mobile && view === 'week' ? ' 第' + week + '周' : ''}`;
      setText('#calendar-range', mobile ? `第 ${week} 周` : view === 'day' ? `星期${weekdays[(date.getDay() + 6) % 7]}` : `${range.start.replaceAll('-', '/')} – ${range.end.replaceAll('-', '/')}`);
      for (const button of viewButtons) button.setAttribute('aria-pressed', String(button.dataset.calAction === view));
      for (const button of root.querySelectorAll('[data-cal-action="previous"], [data-cal-action="next"]')) button.setAttribute('aria-label', `${button.dataset.calAction === 'previous' ? '上一' : '下一'}${({day:'天',week:'周',month:'月'})[view]}`);
      const count = new Set(items.map(e => `${e.id}:${e.occurrenceDay}`)).size;
      const status = pending ? '正在同步日程…' : error ? error.status === 401 ? '登录后查看你的日程' : loaded ? '同步失败，正在显示上次读取的日程' : '暂时无法读取日程，请重试' : `已同步 · 当前视图 ${count} 项日程`;
      syncText.textContent = status; retry.dataset.calAction = error?.status === 401 ? 'login' : 'retry'; retry.setAttribute('aria-label', error?.status === 401 ? '去登录' : '刷新日程');
      setText('#calendar-total', `${selected === today ? '今日' : '所选日期'} ${chosen.length} 项日程`);
      setText('#calendar-duration', `已安排 ${chosen.reduce((sum, e) => sum + e.end - e.start, 0)} 分钟`);
      const conflictText = pending ? '正在检查所选日期…' : error ? '同步后检查日程冲突' : conflicts ? `所选日期有 ${conflicts} 处时间重叠` : '所选日期暂无时间重叠';
      setText(mobile ? '#schedule-conflict-status' : '#calendar-conflict-status', conflictText);
      setText(mobile ? '#schedule-conflict-severity' : '#calendar-conflict-severity', pending || error ? '等待同步' : conflicts ? '需要处理' : '当前正常');
      setText(mobile ? '#schedule-conflict-copy' : '#calendar-conflict-copy', '根据当前日期的真实日程检查；可编辑日程调整时间，或填写紧急任务生成救援方案。重复日程的编辑或删除会作用于整条规则。');
      setText('#calendar-banner-conflicts', pending || error ? '日程检查待同步' : conflicts ? `待解决冲突 ${conflicts} 处` : '日程暂无冲突');
      setText('#calendar-banner-copy', '按所选日期检查');
      const banner = root.querySelector('#calendar-banner-conflicts')?.closest('.animate-pulse'); banner?.classList.remove('animate-pulse');
      month.hidden = view !== 'month';
      if (view !== 'month') month.replaceChildren();
      else { canvas?.replaceChildren(); mobileEvents?.replaceChildren(); }
      if (mobile) {
        renderDateHead(visibleRange('week', selected).days, today);
        mobileEvents.hidden = view === 'month';
        if (view !== 'month') renderMobile(range, items);
        updateFocusStrip(chosen);
      } else {
        dateHead.hidden = view === 'month'; allDay.hidden = view === 'month'; canvas.parentElement.hidden = view === 'month';
        if (view !== 'month') renderTime(range, items, today);
      }
      if (view === 'month') month.innerHTML = monthMarkup(range, items, today);
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
      // Preserve the original 08:00–21:00 map when possible; expand only for real off-hours events.
      startMinute = Math.min(480, range.days.includes(today) ? now.getHours() * 60 : 480, ...items.map(e => Math.floor(e.start / 60) * 60));
      const end = Math.max(1320, range.days.includes(today) ? (now.getHours() + 1) * 60 : 1320, ...items.map(e => Math.ceil(e.end / 60) * 60));
      const columns = `68px repeat(${range.days.length}, minmax(0,1fr))`;
      for (const node of [dateHead, allDay, canvas]) node.style.gridTemplateColumns = columns;
      renderDateHead(range.days, today);
      allDay.innerHTML = '<div class="text-[10px] text-outline font-semibold text-center">全天任务</div>' + range.days.map(() => '<div class="p-1"></div>').join('');
      canvas.style.height = `${end - startMinute}px`;
      canvas.innerHTML = `<div class="flex flex-col text-[11px] text-outline tabular-nums select-none bg-surface-container-low/40">${Array.from({ length: (end - startMinute) / 60 }, (_, i) => `<div style="height:60px" class="p-1.5 text-right font-medium">${clock(startMinute + i * 60)}</div>`).join('')}</div>${range.days.map(day => `<div class="cal-time-column relative ${day === today ? 'bg-primary-container/[0.02]' : 'bg-surface-container-lowest'}" data-calendar-day="${day}">${layoutEvents(items.filter(e => e.day === day)).map(e => `<div class="cal-position" style="top:${e.start - startMinute}px;height:${Math.max(22, e.end - e.start)}px;left:calc(${100 * e.column / e.columns}% + 4px);width:calc(${100 / e.columns}% - 8px)">${eventButton(e)}</div>`).join('')}${day === today && minutes >= startMinute && minutes < end ? `<div class="cal-now" style="top:${minutes - startMinute}px" aria-label="当前时间 ${clock(minutes)}"></div>` : ''}</div>`).join('')}`;
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
    function scrollTime() {
      const scroll = root.querySelector('.cal-time-scroll'); if (!scroll) return;
      const now = new Date();
      scroll.scrollTop = Math.max(0, (selected === dayKey(now) ? now.getHours() * 60 + now.getMinutes() : 540) - startMinute - 110);
    }
    async function refresh() {
      if (doc.documentElement.dataset.pageVisible === 'false') {
        if (parseDay(state.day)) selected = state.day;
        if (['day', 'week', 'month'].includes(state.view)) view = state.view;
      }
      const turn = ++generation;
      pending = true; error = null;
      const previousScroll = root.querySelector('.cal-time-scroll');
      const position = previousScroll && { top: previousScroll.scrollTop, left: previousScroll.scrollLeft };
      render();
      if (position) restoreScroll(position); else scrollTime();
      onState('loading', '正在同步日程');
      try {
        const records = await request('/schedule');
        if (disposed || turn !== generation || account !== identity()) return;
        if (!Array.isArray(records)) throw new Error('日程响应格式不正确');
        const firstLoad = !loaded;
        entries = records;
        loaded = true; pending = false;
        const pos = root.querySelector('.cal-time-scroll');
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
    function restoreScroll(position) { const scroll = root.querySelector('.cal-time-scroll'); if (scroll) { scroll.scrollTop = position.top; scroll.scrollLeft = position.left; } }
    function select(day, mode = view) {
      if (!parseDay(day)) return;
      selected = day; view = mode; remember(); render(); scrollTime(); refresh();
    }
    root.addEventListener('click', event => {
      const target = event.target.closest('button[data-cal-action], button[data-cal-select], button[data-calendar-event]'); if (!target) return;
      event.preventDefault(); event.stopPropagation();
      if (target.dataset.calendarEvent) { navigate(`schedule-detail?id=${encodeURIComponent(target.dataset.calendarEvent)}`); return; }
      if (target.dataset.calSelect) { select(target.dataset.calSelect, target.hasAttribute('data-cal-open-day') ? 'day' : view); return; }
      const name = target.dataset.calAction;
      if (['day', 'week', 'month'].includes(name)) select(selected, name);
      else if (name === 'today') select(dayKey(new Date()));
      else if (name === 'previous' || name === 'next') {
        const direction = name === 'next' ? 1 : -1;
        select(dayKey(view === 'month' ? addMonths(parseDay(selected), direction) : addDays(parseDay(selected), direction * (view === 'week' ? 7 : 1))));
      } else if (name === 'create') create();
      else if (name === 'urgent') navigate('urgent-task');
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
        const now = new Date();
        for (const line of root.querySelectorAll('.cal-now')) line.style.top = `${now.getHours() * 60 + now.getMinutes() - startMinute}px`;
      }
      timer = setTimeout(tick, 60000 - Date.now() % 60000);
    }
    const visibility = event => { if (event.detail.visible) { remember(); tick(); } else clearTimeout(timer); };
    doc.addEventListener('stitch:visibility', visibility);
    pending = true; render(); scrollTime(); tick();
    return { refresh, selectDay: day => select(day), getSelection: () => selected,
      dispose() { disposed = true; generation++; clearTimeout(timer); doc.removeEventListener('stitch:visibility', visibility); } };
  }
  scope.StitchCalendar = { dayKey, parseDay, addDays, addMonths, visibleRange, occurrences, layoutEvents, countConflicts, mount };
})(typeof window === 'undefined' ? globalThis : window);
