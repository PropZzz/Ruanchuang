((scope) => {
  const pad = value => String(value).padStart(2, '0');

  function mount(doc) {
    const win = doc.defaultView, get = id => doc.getElementById(id), handlers = [];
    let active = null, hour = 9, minute = 0;
    const popup = doc.createElement('div');
    popup.id = 'import-time-picker'; popup.className = 'import-time-popover';
    popup.setAttribute('popover', 'manual'); popup.setAttribute('role', 'dialog');
    popup.setAttribute('aria-labelledby', 'import-time-picker-title'); popup.hidden = true;
    popup.innerHTML = '<header><strong id="import-time-picker-title">选择时间</strong><span class="import-time-value"></span></header><div class="import-time-columns"></div><button type="button" class="import-time-apply">确定时间</button>';
    (doc.querySelector('[data-drawer-panel], [data-drawer-edge], body > section') || doc.body).append(popup);
    function listen(node, event, handler, options) {
      node.addEventListener(event, handler, options);
      handlers.push(() => node.removeEventListener(event, handler, options));
    }
    function close(restoreFocus = false) {
      if (!active) return;
      const opener = active.button; active = null;
      opener.setAttribute('aria-expanded', 'false');
      if (popup.hidePopover && popup.matches(':popover-open')) popup.hidePopover();
      popup.hidden = true;
      if (restoreFocus && opener.isConnected) opener.focus({ preventScroll: true });
    }
    function update(scroll = false) {
      popup.querySelector('.import-time-value').textContent = `${pad(hour)}:${pad(minute)}`;
      for (const list of popup.querySelectorAll('[role="listbox"]')) {
        const value = list.dataset.part === 'hour' ? hour : minute;
        list.setAttribute('aria-activedescendant', `import-time-${list.dataset.part}-${value}`);
        for (const option of list.children) option.setAttribute('aria-selected', String(Number(option.dataset.value) === value));
        if (scroll) {
          const option = list.children[value];
          list.scrollTop = option.offsetTop - list.offsetTop - (list.clientHeight - option.clientHeight) / 2;
        }
      }
    }
    function commit() {
      if (!active) return;
      const input = active.input;
      input.value = `${pad(hour)}:${pad(minute)}`;
      input.dispatchEvent(new win.Event('input', { bubbles: true }));
      input.dispatchEvent(new win.Event('change', { bubbles: true }));
      close(true);
    }
    for (const [part, title, count] of [['hour', '小时', 24], ['minute', '分钟', 60]]) {
      const column = doc.createElement('div'), label = doc.createElement('label'), list = doc.createElement('div');
      label.textContent = title; label.id = `import-time-${part}-label`;
      list.className = 'import-time-list'; list.dataset.part = part; list.tabIndex = 0;
      list.setAttribute('role', 'listbox'); list.setAttribute('aria-labelledby', label.id);
      for (let value = 0; value < count; value++) {
        const option = doc.createElement('div'); option.id = `import-time-${part}-${value}`;
        option.setAttribute('role', 'option'); option.setAttribute('aria-label', `${pad(value)}${part === 'hour' ? '时' : '分'}`);
        option.dataset.value = String(value); option.textContent = pad(value); list.append(option);
      }
      listen(list, 'click', event => {
        const option = event.target.closest('[role="option"]'); if (!option) return;
        if (part === 'hour') hour = Number(option.dataset.value); else minute = Number(option.dataset.value);
        update(); list.focus({ preventScroll: true });
      });
      listen(list, 'keydown', event => {
        let value = part === 'hour' ? hour : minute;
        const step = ({ ArrowUp: -1, ArrowDown: 1, PageUp: -5, PageDown: 5 })[event.key];
        if (event.key === 'Enter') { event.preventDefault(); commit(); return; }
        if (step == null && !['Home', 'End'].includes(event.key)) return;
        event.preventDefault();
        value = event.key === 'Home' ? 0 : event.key === 'End' ? count - 1 : (value + step + count) % count;
        if (part === 'hour') hour = value; else minute = value;
        update(true);
      });
      column.append(label, list); popup.querySelector('.import-time-columns').append(column);
    }
    function open(input, button) {
      if (input.disabled || button.disabled) return;
      if (active?.input === input) { close(true); return; }
      close(); active = { input, button }; button.setAttribute('aria-expanded', 'true');
      const match = input.value.match(/^([01]\d|2[0-3]):([0-5]\d)$/);
      const parsed = match ? { hour: Number(match[1]), minute: Number(match[2]) } : null;
      hour = parsed?.hour ?? 9; minute = parsed?.minute ?? 0;
      get('import-time-picker-title').textContent = input.getAttribute('aria-label');
      popup.hidden = false; popup.showPopover?.(); update(true);
      const box = input.parentElement.getBoundingClientRect(), width = popup.offsetWidth, height = popup.offsetHeight;
      popup.style.left = `${Math.max(12, Math.min(box.right - width, win.innerWidth - width - 12))}px`;
      const top = box.bottom + 8 + height <= win.innerHeight - 12 ? box.bottom + 8 : box.top - height - 8;
      popup.style.top = `${Math.max(12, Math.min(top, win.innerHeight - height - 12))}px`;
      popup.querySelector('[role="listbox"]').focus({ preventScroll: true });
    }
    listen(popup.querySelector('.import-time-apply'), 'click', commit);
    listen(doc, 'click', event => {
      const button = event.target.closest('[data-time-picker]');
      if (button) { event.preventDefault(); open(button.parentElement.querySelector('input'), button); }
    });
    listen(doc, 'keydown', event => {
      if (active && event.key === 'Escape') { event.preventDefault(); event.stopImmediatePropagation(); close(true); }
      if (active && event.key === 'Tab' && popup.contains(event.target)) {
        const first = popup.querySelector('[role="listbox"]'), last = popup.querySelector('.import-time-apply');
        if (event.shiftKey && doc.activeElement === first) { event.preventDefault(); last.focus({ preventScroll: true }); }
        else if (!event.shiftKey && doc.activeElement === last) { event.preventDefault(); first.focus({ preventScroll: true }); }
      }
      const input = event.target.closest('.import-time-field input');
      if (input && event.key === 'ArrowDown') { event.preventDefault(); open(input, input.parentElement.querySelector('button')); }
    }, true);
    listen(doc, 'pointerdown', event => {
      if (active && !popup.contains(event.target) && !active.input.parentElement.contains(event.target)) close();
    }, true);
    listen(doc, 'focusin', event => {
      if (active && !popup.contains(event.target) && !active.input.parentElement.contains(event.target)) close();
    });
    listen(doc, 'scroll', event => { if (active && !popup.contains(event.target)) close(); }, true);
    listen(win, 'resize', () => close());
    listen(doc, 'stitch:visibility', event => { if (!event.detail.visible) close(); });

    return {
      timeField(input) {
        input.type = 'text'; input.inputMode = 'text'; input.maxLength = 5; input.placeholder = '选择时间';
        input.pattern = '([01][0-9]|2[0-3]):[0-5][0-9]'; input.autocomplete = 'off';
        const field = doc.createElement('div'), button = doc.createElement('button');
        field.className = 'import-time-field'; button.type = 'button'; button.dataset.timePicker = '';
        button.setAttribute('aria-label', `选择${input.getAttribute('aria-label')}`);
        button.setAttribute('aria-haspopup', 'dialog'); button.setAttribute('aria-controls', popup.id); button.setAttribute('aria-expanded', 'false');
        button.innerHTML = '<span class="material-symbols-outlined" aria-hidden="true">schedule</span>';
        field.append(input, button); return field;
      },
      setBusy(value) {
        for (const button of doc.querySelectorAll('[data-time-picker]')) button.disabled = value;
        if (value) close();
      },
      dispose() { close(); handlers.forEach(remove => remove()); popup.remove(); },
    };
  }
  scope.StitchTimePicker = { mount };
})(window);
