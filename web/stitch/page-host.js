(() => {
  const primary = new Set(['focus', 'schedule', 'micro', 'goals', 'team', 'review', 'diagnostics', 'profile']);
  const drawers = new Set(['create-schedule', 'urgent-task', 'calendar-options', 'calendar-import', 'microtask-entry', 'schedule-detail', 'microtask-detail', 'integrations']);
  const labels = { focus: '专注', schedule: '智能日历', micro: '微任务', goals: '目标', team: '团队', review: '智能复盘', diagnostics: '接入与诊断', profile: '我的' };
  const icons = { focus: 'timer', schedule: 'calendar_today', micro: 'checklist', goals: 'flag', team: 'group', review: 'insights', diagnostics: 'hub', profile: 'person' };

  window.createStitchPageHost = ({ prepare, beforeActivate, activate, navigate, notice, identity }) => {
    const entries = new Map();
    let current = null;
    let generation = 0;
    let account = identity();
    let pendingKey = null;
    let drawerBackground = null;
    let drawerOpener = null;
    let drawerGeneration = 0;
    const reducedMotion = matchMedia('(prefers-reduced-motion: reduce)');
    let motionLayers = [];
    const motionAnimations = new Map();
    let motionGeneration = 0;

    function pruneCache() {
      const retained = [...entries.values()].filter(e => e !== current && e !== drawerBackground && !e.frame.hasAttribute('data-drawer-layer') && !motionLayers.includes(e)).sort((a, b) => Number(primary.has(a.route)) - Number(primary.has(b.route)) || a.lastUsed - b.lastUsed);
      while (entries.size > 10 && retained.length) dispose(retained.shift());
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
        if (layer !== current && !primary.has(layer.route) && !drawers.has(layer.route)) dispose(layer);
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
    ].map(([group, routes]) => `<section><small>${group}</small>${routes.map(route => `<a href="#/${route}" data-route="${route}"><span class="material-symbols-outlined">${icons[route]}</span><span>${labels[route]}</span></a>`).join('')}</section>`).join('')}</nav><div class="shell-footer"><button data-notice><span class="material-symbols-outlined">notifications</span>系统通知 <small>预留</small></button></div></aside><header><div class="shell-breadcrumb">时序智配 <span>/</span> <strong id="shell-title">时间工作台</strong></div><span id="shell-sync" role="status">正在连接</span><div class="shell-actions"><button data-route="settings-drawer" aria-label="设置"><span class="material-symbols-outlined">settings</span></button></div></header><nav class="shell-mobile-nav" aria-label="移动端主导航">${['focus', 'schedule', 'micro', 'team', 'profile'].map(route => `<a href="#/${route}" data-route="${route}"><span class="material-symbols-outlined">${icons[route]}</span><span>${labels[route]}</span></a>`).join('')}</nav>`;
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
      entry.drawerMotion?.destroy();
      entry.frame.contentDocument?.stitchDrawerCleanup?.forEach(cleanup => cleanup());
      motionAnimations.get(entry)?.cancel();
      motionAnimations.delete(entry);
      motionLayers = motionLayers.filter(layer => layer !== entry);
      visibility(entry, false);
      entry.frame.remove();
      entries.delete(entry.key);
    }
    function clear() {
      drawerGeneration++;
      drawerBackground = null;
      drawerOpener = null;
      settleMotion();
      generation++;
      pendingKey = null;
      for (const entry of [...entries.values()]) dispose(entry);
      current = null;
      shell.hidden = true;
      shell.inert = false;
    }
    function updateShell(entry) {
      if (entry.drawerMotion) return;
      shell.hidden = !entry.desktopShell;
      document.body.classList.toggle('has-workspace-shell', entry.desktopShell);
      shell.querySelector('#shell-title').textContent = labels[entry.route] || '时间工作台';
      shell.querySelector('#shell-sync').textContent = entry.frame.contentDocument.documentElement.dataset.backendState === 'online' ? '已连接 · FastAPI' : '正在同步';
      const mobileParent = { goals: 'profile', review: 'profile', diagnostics: 'profile' };
      for (const link of shell.querySelectorAll('a[data-route]')) {
        const isMobileLink = link.closest('.shell-mobile-nav');
        const activeRoute = isMobileLink ? (mobileParent[entry.route] || entry.route) : entry.route;
        if (link.dataset.route === activeRoute) link.setAttribute('aria-current', 'page');
        else link.removeAttribute('aria-current');
      }
    }
    function prepareDrawer(entry) {
      const doc = entry.frame.contentDocument;
      const panel = doc.querySelector('body > section, #root > div');
      if (!panel) throw new Error('抽屉内容暂时无法打开');
      const bottomSheet = entry.mobile && panel.dataset.drawerEdge !== 'right';
      let scrim = doc.querySelector('body > button.fixed.inset-0');
      if (!scrim) {
        scrim = doc.createElement('button');
        scrim.type = 'button';
        scrim.setAttribute('aria-label', '关闭抽屉');
        doc.body.prepend(scrim);
      }
      scrim.dataset.routerReturn = 'true';
      scrim.dataset.drawerScrim = 'true';
      scrim.removeAttribute('onclick');
      panel.dataset.drawerPanel = 'true';
      panel.setAttribute('role', 'dialog');
      panel.setAttribute('aria-modal', 'true');
      panel.setAttribute('aria-label', panel.querySelector('h2')?.textContent || '详情');
      entry.frame.dataset.drawerSurface = entry.route;
      entry.frame.style.background = 'transparent';
      const style = doc.createElement('style');
      style.textContent = `
        [hidden] { display: none !important; }
        html, body { position: fixed !important; inset: 0 !important; width: 100% !important; height: 100% !important; min-height: 0 !important; margin: 0 !important; overflow: hidden !important; background: transparent !important; backdrop-filter: none !important; }
        #root { display: contents !important; background: transparent !important; backdrop-filter: none !important; }
        [data-drawer-scrim] { position: fixed !important; inset: 0 !important; width: 100% !important; height: 100% !important; padding: 0 !important; border: 0 !important; border-radius: 0 !important; background: rgba(26,27,31,.32) !important; transform: none !important; cursor: default; z-index: 0 !important; }
        [data-drawer-panel] { position: absolute !important; z-index: 1 !important; margin: 0 !important; animation: none !important; display: flex !important; flex-direction: column !important; overflow: hidden !important; }
        ${bottomSheet
          ? '[data-drawer-panel] { left: 0 !important; right: 0 !important; bottom: 0 !important; top: auto !important; width: 100% !important; max-width: 520px !important; margin-inline: auto !important; max-height: 92dvh !important; border-radius: 24px 24px 0 0 !important; }'
          : '[data-drawer-panel] { inset: 0 0 0 auto !important; width: min(var(--stitch-drawer-width, 480px), 100vw) !important; max-width: none !important; height: 100% !important; max-height: none !important; border-radius: 0 !important; }'}
      `;
      doc.head.append(style);
      entry.drawerMotion = window.createStitchDrawerMotion({ panel, scrim, axis: bottomSheet ? 'y' : 'x' });
      doc.addEventListener('keydown', event => {
        if (event.key === 'Escape') { event.preventDefault(); event.stopPropagation(); window.__RUANCHUANG_RETURN__(); }
        if (event.key !== 'Tab') return;
        const controls = [...panel.querySelectorAll('button:not([disabled]), input:not([disabled]), textarea:not([disabled]), select:not([disabled]), a[href], [tabindex="0"]')].filter(el => el.getClientRects().length && !el.closest('[hidden], .hidden'));
        const first = controls[0], last = controls.at(-1);
        if (!first) { event.preventDefault(); return; }
        if (event.shiftKey && doc.activeElement === first) { event.preventDefault(); last.focus(); }
        else if (!event.shiftKey && doc.activeElement === last) { event.preventDefault(); first.focus(); }
      });
    }
    function createEntry(route, url, mobile, key) {
      const frame = document.createElement('iframe');
      const entry = { key, route, frame, mobile, ready: false, desktopShell: primary.has(route), lastUsed: Date.now() };
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
            const authenticationPage = route === 'login'
              && doc?.querySelector('meta[name="shell-type"][content="authentication"]')
              && doc.querySelector('#auth-submit');
            if (!doc?.body || (!doc.querySelector('#tailwind-config') && !authenticationPage)) throw new Error('页面暂时无法打开');
            doc.documentElement.dataset.pageVisible = 'false';
            doc.documentElement.dataset.route = route;
            const lifecycleStyle = doc.createElement('style');
            lifecycleStyle.textContent = 'html[data-page-visible="false"] *, html[data-page-visible="false"] *::before, html[data-page-visible="false"] *::after { animation-play-state: paused !important; }';
            doc.head.append(lifecycleStyle);
            if (entry.desktopShell && doc.querySelector('aside')) {
              const css = doc.createElement('style');
              css.textContent = 'body > aside, body > div > header, body > header { visibility: hidden !important; pointer-events: none !important; }';
              doc.head.append(css);
            }
            prepare(frame, route);
            visibility(entry, false);
            await Promise.all(['ruanchuang-polish-styles', 'ruanchuang-calendar-styles'].map(id => {
              const link = doc.getElementById(id);
              if (!link || link.sheet) return;
              return new Promise((resolve, reject) => {
                link.addEventListener('load', resolve, { once: true });
                link.addEventListener('error', () => reject(new Error('页面样式加载失败')), { once: true });
              });
            }));
            await doc.fonts.ready;
            if (drawers.has(route)) prepareDrawer(entry);
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
    async function show(route, url, mobile, background = null) {
      if (identity() !== account) { clear(); account = identity(); }
      if (drawers.has(route) && !current && background) {
        const expectedGeneration = generation + 1;
        await show(background.route, background.url, mobile);
        if (generation !== expectedGeneration || !current) return;
      }
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
        if (entry.drawerMotion && changed) settleMotion();
        if (entry.drawerMotion && !drawerBackground && previous && !previous.drawerMotion) {
          drawerBackground = previous;
          drawerOpener = document.activeElement === previous.frame ? previous.frame.contentDocument.activeElement : document.activeElement;
          previous.frame.dataset.drawerBackground = 'true';
        }
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
        entry.frame.inert = Boolean(!entry.drawerMotion && document.getElementById('ruanchuang-settings-overlay'));
        entry.frame.setAttribute('aria-hidden', String(entry.frame.inert));
        updateShell(entry);
        activate(entry.frame, route);
        visibility(entry, true);
        if (entry.drawerMotion) {
          drawerGeneration++;
          shell.inert = true;
          if (changed && previous?.drawerMotion) {
            previous.frame.dataset.drawerLayer = 'true';
            previous.drawerMotion.setOpen(false).then(done => { if (done && previous !== current) delete previous.frame.dataset.drawerLayer; });
          }
          entry.drawerMotion.setOpen(true);
          entry.frame.contentDocument.querySelector('[data-drawer-panel] button')?.focus({ preventScroll: true });
        } else if (changed && previous?.drawerMotion) {
          const drawerTurn = ++drawerGeneration;
          previous.frame.dataset.drawerLayer = 'true';
          shell.inert = true;
          entry.frame.inert = true;
          previous.drawerMotion.setOpen(false).then(done => {
            if (!done) return;
            delete previous.frame.dataset.drawerLayer;
            if (drawerTurn !== drawerGeneration) return;
            if (drawerBackground) delete drawerBackground.frame.dataset.drawerBackground;
            drawerBackground = null;
            shell.inert = false;
            entry.frame.inert = false;
            if (drawerOpener?.isConnected && (drawerOpener.ownerDocument === entry.frame.contentDocument || drawerOpener.ownerDocument === document)) drawerOpener.focus({ preventScroll: true });
            else entry.frame.contentDocument.querySelector('[data-cal-date], main button, main input')?.focus({ preventScroll: true });
            drawerOpener = null;
            pruneCache();
          });
        } else {
          drawerGeneration++;
          if (drawerBackground) delete drawerBackground.frame.dataset.drawerBackground;
          drawerBackground = null;
          const externalSettings = Boolean(document.getElementById('ruanchuang-settings-overlay'));
          const inlineDialog = entry.frame.contentDocument.querySelector('[data-drawer-panel]:not([data-drawer-state="closed"])');
          shell.inert = externalSettings || Boolean(inlineDialog);
          entry.frame.inert = externalSettings;
          entry.frame.setAttribute('aria-hidden', String(externalSettings));
          if (changed) blendPages(entry, previous);
        }
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
      show, clear, shell, primary, drawers, settleMotion,
      get pending() { return pendingKey !== null; },
      cancelPending() { generation++; pendingKey = null; status.hidden = true; },
      documents: () => [...entries.values()].map(entry => entry.frame.contentDocument),
    };
  };
})();
