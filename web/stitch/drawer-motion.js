(() => {
  // One interruptible motion model for routed, settings and inline drawers.
  window.createStitchDrawerMotion = ({ panel, scrim, axis = 'x', open = false, travel = null }) => {
    const view = panel.ownerDocument.defaultView;
    const reduce = window.matchMedia('(prefers-reduced-motion: reduce)');
    const animations = new Map();
    let generation = 0;
    const offset = travel == null ? '100%' : `${travel}px`;
    const closed = () => axis === 'y' ? `translate3d(0, ${offset}, 0)` : `translate3d(${offset}, 0, 0)`;
    panel.style.transition = 'none';
    panel.style.transform = open ? 'translate3d(0, 0, 0)' : closed();
    panel.dataset.drawerState = open ? 'open' : 'closed';
    if (scrim) scrim.dataset.drawerScrim = 'true';
    if (scrim) { scrim.style.transition = 'none'; scrim.style.opacity = open ? '1' : '0'; }

    function stop() {
      for (const [element, animation] of animations) {
        const style = element.ownerDocument.defaultView.getComputedStyle(element);
        const property = element === panel ? 'transform' : 'opacity';
        const value = style[property];
        animation.cancel();
        element.style[property] = value;
        element.style.removeProperty('will-change');
      }
      animations.clear();
    }

    async function setOpen(nextOpen, { immediate = false } = {}) {
      const turn = ++generation;
      stop();
      panel.dataset.drawerState = nextOpen ? 'opening' : 'closing';
      const matrix = new view.DOMMatrixReadOnly(view.getComputedStyle(panel).transform);
      const distance = travel ?? (axis === 'y' ? panel.getBoundingClientRect().height : panel.getBoundingClientRect().width);
      const progress = Math.min(1, Math.max(0, Math.abs(axis === 'y' ? matrix.m42 : matrix.m41) / (distance || 1)));
      const remaining = nextOpen ? progress : 1 - progress;
      const duration = Math.max(80, (nextOpen ? 300 : 220) * remaining);
      const jobs = [];
      for (const [element, property, end] of [[panel, 'transform', nextOpen ? 'translate3d(0, 0, 0)' : closed()], [scrim, 'opacity', nextOpen ? '1' : '0']]) {
        if (!element) continue;
        const start = element.ownerDocument.defaultView.getComputedStyle(element)[property];
        element.style[property] = end;
        if (immediate || reduce.matches || remaining < 0.001) continue;
        element.style.willChange = property;
        const animation = element.animate([{ [property]: start }, { [property]: end }], {
          duration, easing: nextOpen ? 'cubic-bezier(.22,1,.36,1)' : 'cubic-bezier(.4,0,1,1)', fill: 'both',
        });
        animations.set(element, animation);
        jobs.push(animation.finished.catch(() => {}));
      }
      await Promise.all(jobs);
      if (turn !== generation) return false;
      for (const [element, animation] of animations) {
        animation.cancel();
        element.style.removeProperty('will-change');
      }
      animations.clear();
      panel.dataset.drawerState = nextOpen ? 'open' : 'closed';
      return true;
    }

    const onReduce = () => { if (reduce.matches) for (const animation of animations.values()) animation.finish(); };
    reduce.addEventListener('change', onReduce);
    return {
      setOpen,
      destroy() { generation++; stop(); reduce.removeEventListener('change', onReduce); },
    };
  };

  window.bindStitchInlineDrawer = ({ panel, scrim, shell, beforeOpen, axis = 'x', travel = null }) => {
    const doc = panel.ownerDocument;
    const motion = window.createStitchDrawerMotion({ panel, scrim, axis, travel });
    let opened = false;
    let opener = null;
    let oldShellInert = false;
    let inertElements = [];
    panel.dataset.drawerPanel = 'true';
    panel.setAttribute('role', 'dialog');
    panel.setAttribute('aria-modal', 'true');
    panel.setAttribute('aria-label', panel.querySelector('h2, h3')?.textContent || '详情');
    panel.style.visibility = 'hidden';
    panel.inert = true;
    panel.setAttribute('aria-hidden', 'true');
    scrim.style.pointerEvents = 'none';
    scrim.style.backdropFilter = 'none';
    const frame = doc.defaultView.frameElement;
    const canvas = doc.querySelector('body > div > header')?.parentElement;
    if (canvas) canvas.dataset.inlineCanvas = 'true';
    if (!doc.getElementById('inline-drawer-canvas')) {
      const style = doc.createElement('style');
      style.id = 'inline-drawer-canvas';
      style.textContent = 'html[data-inline-drawer], html[data-inline-drawer] body, html[data-inline-drawer] [data-inline-canvas] { background: transparent !important; }';
      doc.head.append(style);
    }
    const controls = () => [...panel.querySelectorAll('button:not([disabled]), input:not([disabled]), textarea:not([disabled]), select:not([disabled]), a[href], [tabindex="0"]')].filter(el => el.getClientRects().length);
    const close = ({ immediate = false } = {}) => {
      if (!opened) return;
      opened = false;
      motion.setOpen(false, { immediate }).then(done => {
        if (!done || opened) return;
        panel.style.visibility = 'hidden';
        panel.inert = true;
        panel.setAttribute('aria-hidden', 'true');
        scrim.style.pointerEvents = 'none';
        for (const [element, previous] of inertElements) element.inert = previous;
        inertElements = [];
        if (!doc.querySelector('[data-drawer-panel]:not([data-drawer-state="closed"])')) {
          delete doc.documentElement.dataset.inlineDrawer;
          if (frame) delete frame.dataset.inlineDrawer;
        }
        if (doc.documentElement.dataset.pageVisible !== 'false') shell.inert = oldShellInert;
        if (opener?.isConnected && doc.documentElement.dataset.pageVisible !== 'false') opener.focus({ preventScroll: true });
      });
    };
    const open = () => {
      beforeOpen?.();
      if (!opened && panel.dataset.drawerState !== 'closing') {
        opener = doc.activeElement;
        oldShellInert = shell.inert;
        for (let branch = panel; branch.parentElement; branch = branch.parentElement) {
          for (const sibling of branch.parentElement.children) {
            if (sibling === branch || sibling === scrim || sibling.contains(scrim)) continue;
            inertElements.push([sibling, sibling.inert]);
            sibling.inert = true;
          }
          if (branch.parentElement === doc.body) break;
        }
      }
      opened = true;
      doc.documentElement.dataset.inlineDrawer = 'true';
      if (frame) frame.dataset.inlineDrawer = 'true';
      shell.inert = true;
      panel.style.visibility = 'visible';
      panel.inert = false;
      panel.setAttribute('aria-hidden', 'false');
      scrim.style.pointerEvents = 'auto';
      motion.setOpen(true);
      controls()[0]?.focus({ preventScroll: true });
    };
    scrim.addEventListener('click', event => { if (event.target === scrim) close(); });
    doc.addEventListener('stitch:visibility', event => { if (!event.detail.visible) close({ immediate: true }); });
    doc.addEventListener('keydown', event => {
      if (panel.dataset.drawerState === 'closed') return;
      if (event.key === 'Escape') { event.preventDefault(); event.stopImmediatePropagation(); close(); }
      if (event.key !== 'Tab') return;
      const list = controls(), first = list[0], last = list.at(-1);
      if (!first) event.preventDefault();
      else if (event.shiftKey && doc.activeElement === first) { event.preventDefault(); last.focus(); }
      else if (!event.shiftKey && doc.activeElement === last) { event.preventDefault(); first.focus(); }
    }, true);
    (doc.stitchDrawerCleanup ||= []).push(() => motion.destroy());
    return { open, close };
  };
})();
