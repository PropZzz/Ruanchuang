(() => {
  const primary = new Set(['focus', 'schedule', 'micro', 'goals', 'team', 'review', 'diagnostics', 'profile']);
  const labels = { focus: '专注', schedule: '智能日历', micro: '微任务', goals: '目标', team: '团队', review: '智能复盘', diagnostics: '接入与诊断', profile: '我的' };
  const icons = { focus: 'timer', schedule: 'calendar_today', micro: 'checklist', goals: 'flag', team: 'group', review: 'insights', diagnostics: 'hub', profile: 'person' };

  window.createStitchPageHost = ({ prepare, beforeActivate, activate, navigate, notice, identity }) => {
    const entries = new Map();
    let current = null;
    let generation = 0;
    let account = identity();
    let pendingKey = null;
    const reducedMotion = matchMedia('(prefers-reduced-motion: reduce)');
    let motionLayers = [];
    const motionAnimations = new Map();
    let motionGeneration = 0;

    function pruneCache() {
      const retained = [...entries.values()].filter(e => e !== current && !motionLayers.includes(e)).sort((a, b) => a.lastUsed - b.lastUsed);
      while (entries.size > (primary.has(current?.route) ? 8 : 9) && retained.length) dispose(retained.shift());
    }

    function settleMotion() {
      motionGeneration++;
      for (const animation of motionAnimations.values()) animation.cancel();
      motionAnimations.clear();
      const layers = motionLayers;
      motionLayers = [];
      for (const layer of layers) {
        delete layer.frame.dataset.transitionLayer;
        layer.frame.style.removeProperty('opacity');
        layer.frame.style.removeProperty('z-index');
        if (layer !== current && !primary.has(layer.route)) dispose(layer);
      }
      pruneCache();
    }

    function blendPages(entry, previous) {
      if (!previous || reducedMotion.matches || document.hidden || previous.mobile !== entry.mobile) {
        settleMotion();
        if (previous && previous !== entry && !primary.has(previous.route)) dispose(previous);
        return;
      }
      const turn = ++motionGeneration;
      // Freeze the actual composite, including partially entered pages. Reversing
      // or clicking a third tab must continue from these pixels, not restart at 0.
      for (const [layer, animation] of motionAnimations) {
        const opacity = getComputedStyle(layer.frame).opacity;
        animation.cancel();
        layer.frame.style.opacity = opacity;
      }
      motionAnimations.clear();
      if (!motionLayers.length) motionLayers.push(previous);
      if (!motionLayers.includes(entry)) {
        entry.frame.style.opacity = '0';
        motionLayers.push(entry);
      }
      const targetIndex = motionLayers.indexOf(entry);
      const finished = [];
      motionLayers.forEach((layer, index) => {
        layer.frame.dataset.transitionLayer = 'true';
        layer.frame.style.zIndex = String(index + 1);
        if (index < targetIndex) return; // Keep an opaque base; never fade to white.
        const start = Number(getComputedStyle(layer.frame).opacity);
        const end = layer === entry ? 1 : 0;
        layer.frame.style.opacity = String(end);
        if (start === end) return;
        const animation = layer.frame.animate([{ opacity: start }, { opacity: end }], {
          duration: 180, easing: 'cubic-bezier(.2,0,0,1)',
        });
        motionAnimations.set(layer, animation);
        finished.push(animation.finished.catch(() => {}));
      });
      Promise.all(finished).then(() => { if (turn === motionGeneration) settleMotion(); });
    }
    reducedMotion.addEventListener('change', () => { if (reducedMotion.matches) settleMotion(); });
    const shell = document.createElement('div');
    shell.id = 'workspace-shell';
    shell.hidden = true;
    shell.innerHTML = `<aside aria-label="主导航"><div class="shell-brand"><img src="stitch/assets/images/a2aaefce0709.png" alt=""><div><strong>时序智配</strong><small>时间地图工作台</small></div></div><nav>${[
      ['今天', ['focus', 'schedule']], ['规划', ['micro', 'goals']], ['协作', ['team']], ['系统', ['review', 'diagnostics', 'profile']],
    ].map(([group, routes]) => `<section><small>${group}</small>${routes.map(route => `<a href="#/${route}" data-route="${route}"><span class="material-symbols-outlined">${icons[route]}</span><span>${labels[route]}</span></a>`).join('')}</section>`).join('')}</nav><div class="shell-footer"><button data-notice><span class="material-symbols-outlined">notifications</span>系统通知 <small>预留</small></button></div></aside><header><div class="shell-breadcrumb">时序智配 <span>/</span> <strong id="shell-title">时间工作台</strong></div><span id="shell-sync" role="status">正在连接</span><div class="shell-actions"><button data-route="urgent-task"><span class="material-symbols-outlined">bolt</span><span>插入紧急任务</span></button><button data-route="create-schedule" class="shell-add"><span class="material-symbols-outlined">add</span><span>新增日程</span></button><button data-route="settings-drawer" aria-label="设置"><span class="material-symbols-outlined">settings</span></button></div></header>`;
    document.body.append(shell);
    const status = document.createElement('div');
    status.id = 'page-load-status';
    status.hidden = true;
    status.setAttribute('role', 'status');
    document.body.append(status);
    shell.addEventListener('click', event => {
      const link = event.target.closest('[data-route]');
      if (link && !event.ctrlKey && !event.metaKey && !event.shiftKey && !event.altKey && event.button === 0) {
        event.preventDefault();
        navigate(link.dataset.route);
      } else if (event.target.closest('[data-notice]')) notice();
    });
    window.addEventListener('stitch:backend-state', event => {
      if (event.detail.route === current?.route) shell.querySelector('#shell-sync').textContent = event.detail.label || '本地模式 · 后端不可用';
    });

    function visibility(entry, visible) {
      const doc = entry?.frame.contentDocument;
      if (!doc?.documentElement) return;
      doc.documentElement.dataset.pageVisible = String(visible && !document.hidden);
      doc.dispatchEvent(new entry.frame.contentWindow.CustomEvent('stitch:visibility', { detail: { visible: visible && !document.hidden } }));
    }
    document.addEventListener('visibilitychange', () => {
      visibility(current, true);
      if (document.hidden) settleMotion();
    });
    function dispose(entry) {
      motionAnimations.get(entry)?.cancel();
      motionAnimations.delete(entry);
      motionLayers = motionLayers.filter(layer => layer !== entry);
      visibility(entry, false);
      entry.frame.remove();
      entries.delete(entry.key);
    }
    function clear() {
      settleMotion();
      generation++;
      pendingKey = null;
      for (const entry of [...entries.values()]) dispose(entry);
      current = null;
      shell.hidden = true;
    }
    function updateShell(entry) {
      shell.hidden = !entry.desktopShell;
      document.body.classList.toggle('has-workspace-shell', entry.desktopShell);
      shell.querySelector('#shell-title').textContent = labels[entry.route] || '时间工作台';
      shell.querySelector('#shell-sync').textContent = entry.frame.contentDocument.documentElement.dataset.backendState === 'online' ? '已连接 · FastAPI' : '正在同步';
      for (const link of shell.querySelectorAll('a[data-route]')) {
        if (link.dataset.route === entry.route) link.setAttribute('aria-current', 'page');
        else link.removeAttribute('aria-current');
      }
    }
    function createEntry(route, url, mobile, key) {
      const frame = document.createElement('iframe');
      const entry = { key, route, frame, mobile, ready: false, desktopShell: !mobile && primary.has(route), lastUsed: Date.now() };
      frame.className = 'workspace-page';
      frame.title = `时序智配 ${route}`;
      frame.hidden = true;
      frame.inert = true;
      frame.setAttribute('aria-hidden', 'true');
      entry.promise = new Promise((resolve, reject) => {
        const timeout = setTimeout(() => reject(new Error('页面加载超时')), 15000);
        frame.addEventListener('load', async () => {
          try {
            const doc = frame.contentDocument;
            if (!doc?.body || !doc.querySelector('#tailwind-config')) throw new Error('页面暂时无法打开');
            doc.documentElement.dataset.pageVisible = 'false';
            doc.documentElement.dataset.route = route;
            const lifecycleStyle = doc.createElement('style');
            lifecycleStyle.textContent = 'html[data-page-visible="false"] *, html[data-page-visible="false"] *::before, html[data-page-visible="false"] *::after { animation-play-state: paused !important; }';
            doc.head.append(lifecycleStyle);
            if (entry.desktopShell && doc.querySelector('aside')) {
              const css = doc.createElement('style');
              css.textContent = 'body > aside, body > div > header, body > header { visibility: hidden !important; pointer-events: none !important; }';
              doc.head.append(css);
            } else entry.desktopShell = false;
            prepare(frame, route);
            visibility(entry, false);
            const polish = doc.getElementById('ruanchuang-polish-styles');
            if (polish && !polish.sheet) await new Promise((resolve, reject) => {
              polish.addEventListener('load', resolve, { once: true });
              polish.addEventListener('error', () => reject(new Error('页面样式加载失败')), { once: true });
            });
            await doc.fonts.ready;
            entry.ready = true;
            resolve(entry);
          } catch (error) { reject(error); }
          finally { clearTimeout(timeout); }
        }, { once: true });
        frame.addEventListener('error', () => { clearTimeout(timeout); reject(new Error('页面加载失败')); }, { once: true });
      });
      frame.src = url;
      entries.set(key, entry);
      document.body.append(frame);
      return entry;
    }
    async function show(route, url, mobile) {
      if (identity() !== account) { clear(); account = identity(); }
      const key = `${mobile ? 'mobile' : 'desktop'}:${url}`;
      if (pendingKey === key) return;
      pendingKey = key;
      const turn = ++generation;
      let entry = entries.get(key);
      if (!entry) entry = createEntry(route, url, mobile, key);
      if (!entry.ready) {
        status.textContent = `正在打开${labels[route] || '页面'}…`;
        status.hidden = false;
      }
      try {
        await entry.promise;
        if (turn !== generation || !entry.frame.isConnected) return;
        if (beforeActivate(entry.frame, route) === false) return;
        const previous = current;
        const changed = previous !== entry;
        if (changed && previous) {
          previous.frame.removeAttribute('id');
          previous.frame.hidden = true;
          previous.frame.inert = true;
          previous.frame.setAttribute('aria-hidden', 'true');
          visibility(previous, false);
        }
        current = entry;
        entry.lastUsed = Date.now();
        entry.frame.id = 'prototype-screen';
        entry.frame.hidden = false;
        entry.frame.inert = shell.inert;
        entry.frame.setAttribute('aria-hidden', String(shell.inert));
        updateShell(entry);
        activate(entry.frame, route);
        visibility(entry, true);
        if (changed) blendPages(entry, previous);
        // In-flight layers are released once the current page fully covers them.
        pruneCache();
        status.hidden = true;
      } catch (error) {
        if (entries.get(key) === entry) dispose(entry);
        if (turn !== generation) return;
        status.textContent = `${error.message}，当前内容已保留。`;
        const retry = document.createElement('button');
        retry.textContent = '重试';
        retry.onclick = () => show(route, url, mobile);
        status.append(retry);
      } finally { if (turn === generation) pendingKey = null; }
    }
    return {
      show, clear, shell, primary,
      get pending() { return pendingKey !== null; },
      cancelPending() { generation++; pendingKey = null; status.hidden = true; },
      documents: () => [...entries.values()].map(entry => entry.frame.contentDocument),
    };
  };
})();
