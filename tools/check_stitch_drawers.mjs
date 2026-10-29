import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { readFile, mkdir, writeFile } from 'node:fs/promises';
import { extname, resolve, sep } from 'node:path';
import { createRequire } from 'node:module';
import { buildStitchWeb } from './build_stitch_web.mjs';

const require = createRequire(import.meta.url);
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const release = await buildStitchWeb();
const mime = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.woff2': 'font/woff2', '.ttf': 'font/ttf' };
const server = createServer(async (req, res) => {
  try {
    const path = new URL(req.url, 'http://localhost').pathname;
    const file = resolve(release.output, '.' + (path === '/' ? '/index.html' : path));
    assert.ok(file.startsWith(release.output + sep));
    res.setHeader('Content-Type', mime[extname(file)] || 'application/octet-stream');
    res.end(await readFile(file));
  } catch { res.writeHead(404); res.end(); }
});
await new Promise(r => server.listen(0, '127.0.0.1', r));
const base = process.argv.includes('--url') ? process.argv[process.argv.indexOf('--url') + 1] : `http://127.0.0.1:${server.address().port}/`;
const browser = await chromium.launch({ headless: true });
const results = [];
await mkdir('build/drawer-qa', { recursive: true });
const cases = [
  ['create-schedule', 'schedule'], ['urgent-task', 'schedule'], ['microtask-entry', 'micro'],
  ['schedule-detail', 'schedule'], ['microtask-detail', 'micro'],
];
try {
  for (const mobile of [false, true]) {
    const context = await browser.newContext({ viewport: mobile ? { width: 390, height: 844 } : { width: 1440, height: 900 } });
    await context.addInitScript(() => {
      window.__RUANCHUANG_API__ = location.origin + '/api';
      const animate = Element.prototype.animate;
      Element.prototype.animate = function (...args) {
        const animation = animate.apply(this, args);
        if (this.hasAttribute('data-drawer-panel') || this.hasAttribute('data-drawer-scrim')) animation.playbackRate = window.top.__drawerPlaybackRate ?? 0.05;
        return animation;
      };
    });
    const page = await context.newPage();
    const errors = [];
    const documents = [];
    page.on('pageerror', e => errors.push(e.message));
    page.on('request', r => { if (r.isNavigationRequest()) documents.push(r.url()); });
    await page.route('**/api/**', r => r.fulfill({ json: r.request().url().endsWith('/schedule') ? [] : r.request().url().endsWith('/microtasks') ? [] : { ok: true, themeMode: 'light', locale: 'zh_CN' } }));
    const ready = route => page.waitForFunction(route => {
      const f = document.getElementById('prototype-screen');
      return f?.title === `时序智配 ${route}` && f.contentDocument?.getElementById('ruanchuang-polish-styles');
    }, route);
    const go = async route => { await page.evaluate(route => { location.hash = '#/' + route; }, route); await ready(route); };
    const finishMotion = async () => {
      await page.evaluate(() => {
        for (const doc of [document, ...[...document.querySelectorAll('iframe')].map(f => f.contentDocument).filter(Boolean)]) {
          for (const a of doc.getAnimations()) if (a.effect.target.matches('[data-drawer-panel], [data-drawer-scrim]')) a.finish();
        }
      });
    };
    const freeze = async (route, fraction) => page.evaluate(({ route, fraction }) => {
      const f = [...document.querySelectorAll('iframe')].find(f => f.title === `时序智配 ${route}`);
      const panel = f.contentDocument.querySelector('[data-drawer-panel]');
      const animation = panel.getAnimations().find(a => a.effect.getKeyframes().some(k => 'transform' in k));
      if (animation) { animation.pause(); animation.currentTime = animation.effect.getTiming().duration * fraction; }
      const m = new f.contentWindow.DOMMatrixReadOnly(f.contentWindow.getComputedStyle(panel).transform);
      return [m.m41, m.m42];
    }, { route, fraction });
    const continuous = (before, after, message) => assert.ok(Math.hypot(before[0] - after[0], before[1] - after[1]) < 1, message);
    await page.goto(base + '#/schedule'); await ready('schedule');
    for (const [route, parent] of cases) {
      await go(parent);
      await page.evaluate(() => { window.__drawerParent = document.getElementById('prototype-screen'); window.__drawerParent.contentWindow.__preservedDrawerParent = true; });
      await go(route);
      const state = await page.evaluate(() => {
        const frame = document.getElementById('prototype-screen');
        const parent = window.__drawerParent;
        const panel = frame.contentDocument.querySelector('[data-drawer-panel]');
        return { backgroundVisible: getComputedStyle(parent).visibility === 'visible', parentInert: parent.inert, panel: !!panel,
          transformAnimations: panel?.getAnimations().filter(a => a.effect.getKeyframes().some(k => 'transform' in k)).length || 0 };
      });
      assert.ok(state.backgroundVisible && state.parentInert, `${route}: keep real background pixels visible and inert`);
      assert.ok(state.panel && state.transformAnimations, `${route}: animate the drawer panel, not the full page`);
      const firstDocument = await page.locator('#prototype-screen').getAttribute('src');
      const opening = await freeze(route, 0.45);
      await page.evaluate(() => window.__RUANCHUANG_RETURN__());
      await ready(parent);
      continuous(opening, await freeze(route, 0), `${route}: reversing an opening must preserve its rendered position`);
      const closing = await freeze(route, 0.45);
      await go(route);
      continuous(closing, await freeze(route, 0), `${route}: reopening during dismissal must preserve its rendered position`);
      await finishMotion();
      await page.waitForFunction(() => document.getElementById('prototype-screen').contentDocument.querySelector('[data-drawer-panel]').dataset.drawerState === 'open');
      await page.screenshot({ path: `build/drawer-qa/${mobile ? 'mobile' : 'desktop'}-${route}.png` });
      await page.locator('#prototype-screen').evaluate(f => {
        const panel = f.contentDocument.querySelector('[data-drawer-panel]');
        window.__drawerFocusable = [...panel.querySelectorAll('button:not([disabled]), input:not([disabled]), textarea:not([disabled]), select:not([disabled]), a[href], [tabindex="0"]')].filter(el => el.getClientRects().length && !el.closest('[hidden], .hidden'));
        window.__drawerFocusable.at(-1).focus();
      });
      await page.keyboard.press('Tab');
      assert.equal(await page.evaluate(() => window.__drawerFocusable[0].ownerDocument.activeElement === window.__drawerFocusable[0]), true, `${route}: trap keyboard focus inside the drawer`);
      if (route === 'urgent-task') await page.locator('#prototype-screen').evaluate(f => f.contentDocument.querySelector('[data-drawer-scrim]').click());
      else if (route === 'microtask-entry') await page.frameLocator('#prototype-screen').locator('[data-drawer-panel] button').first().press('Escape');
      else if (route === 'microtask-detail') await page.goBack();
      else await page.frameLocator('#prototype-screen').locator('[data-drawer-panel] button[aria-label*="关闭"]').first().click();
      await ready(parent);
      await finishMotion();
      await page.waitForFunction(() => !document.querySelector('[data-drawer-layer]'));
      assert.equal(await page.evaluate(() => document.getElementById('prototype-screen') === window.__drawerParent && window.__drawerParent.contentWindow.__preservedDrawerParent), true);
      assert.equal(await page.locator('#prototype-screen').evaluate(f => f.inert), false);
      assert.equal(documents.filter(url => url === new URL(firstDocument, base).href).length, 1, `${route}: warm reopen must reuse its document`);
      results.push({ viewport: mobile ? 'mobile' : 'desktop', route, passed: true, reversal: true, warmDocumentReuse: true });
    }
    await go('schedule');
    // Settings use the same panel motion while keeping the primary document active.
    await page.evaluate(() => { window.__settingsParent = document.getElementById('prototype-screen'); });
    await page.evaluate(() => { location.hash = '#/settings-drawer'; });
    await page.waitForFunction(() => document.querySelector('#ruanchuang-settings-overlay iframe')?.contentDocument?.querySelector('[data-drawer-panel][data-drawer-state="opening"]'));
    const settingsFrame = page.frameLocator('#ruanchuang-settings-overlay iframe');
    await page.evaluate(() => { window.__settingsFrame = document.querySelector('#ruanchuang-settings-overlay iframe'); });
    const settingsPosition = async fraction => page.evaluate(fraction => {
      const f = window.__settingsFrame, panel = f.contentDocument.querySelector('[data-drawer-panel]');
      const a = panel.getAnimations()[0];
      if (a) { a.pause(); a.currentTime = a.effect.getTiming().duration * fraction; }
      const m = new f.contentWindow.DOMMatrixReadOnly(f.contentWindow.getComputedStyle(panel).transform);
      return [m.m41, m.m42];
    }, fraction);
    const settingsOpening = await settingsPosition(0.45);
    await settingsFrame.locator('#close-drawer-btn, #btn-close-drawer').click();
    continuous(settingsOpening, await settingsPosition(0), 'Settings close must reverse from the displayed position');
    const settingsClosing = await settingsPosition(0.45);
    await page.waitForFunction(() => location.hash !== '#/settings-drawer');
    await page.evaluate(() => { location.hash = '#/settings-drawer'; });
    await page.waitForFunction(() => window.__settingsFrame.contentDocument.querySelector('[data-drawer-panel]').dataset.drawerState === 'opening');
    continuous(settingsClosing, await settingsPosition(0), 'Settings reopen must reverse the in-flight dismissal');
    assert.equal(await page.evaluate(() => document.querySelector('#ruanchuang-settings-overlay iframe') === window.__settingsFrame), true);
    await finishMotion();
    await page.screenshot({ path: `build/drawer-qa/${mobile ? 'mobile' : 'desktop'}-settings-drawer.png` });
    await settingsFrame.locator('#close-drawer-btn, #btn-close-drawer').press('Escape');
    await finishMotion();
    await page.waitForFunction(() => !document.getElementById('ruanchuang-settings-overlay'));
    assert.equal(await page.evaluate(() => document.getElementById('prototype-screen') === window.__settingsParent && !window.__settingsParent.inert && !document.getElementById('workspace-shell').inert), true);
    results.push({ viewport: mobile ? 'mobile' : 'desktop', route: 'settings-drawer', passed: true, reversal: true, warmDocumentReuse: true });

    let releasePreferences;
    const slowPreferences = new Promise(resolve => { releasePreferences = resolve; });
    await page.route('**/api/settings', async route => { await slowPreferences; await route.fulfill({ json: { themeMode: 'light', locale: 'zh_CN' } }).catch(() => {}); });
    await page.evaluate(() => { location.hash = '#/settings-drawer'; });
    await page.waitForFunction(() => document.querySelector('#ruanchuang-settings-overlay iframe')?.contentDocument?.querySelector('[data-drawer-panel][data-drawer-state="opening"]'));
    await page.frameLocator('#ruanchuang-settings-overlay iframe').locator('#close-drawer-btn, #btn-close-drawer').press('Escape');
    await finishMotion();
    await page.waitForFunction(() => !document.getElementById('ruanchuang-settings-overlay'));
    releasePreferences();
    await page.unroute('**/api/settings');
    results.push({ viewport: mobile ? 'mobile' : 'desktop', route: 'settings-slow-data', passed: true });

    await page.waitForFunction(() => location.hash !== '#/settings-drawer');
    await page.evaluate(() => { location.hash = '#/settings-drawer'; });
    await page.waitForFunction(() => document.querySelector('#ruanchuang-settings-overlay iframe')?.contentDocument?.querySelector('[data-drawer-panel][data-drawer-state="opening"]'));
    await finishMotion();
    await page.evaluate(() => { window.__responsiveSettingsFrame = document.querySelector('#ruanchuang-settings-overlay iframe'); });
    await page.setViewportSize(mobile ? { width: 1440, height: 900 } : { width: 390, height: 844 });
    await page.waitForFunction(mobile => document.querySelector('#ruanchuang-settings-overlay iframe')?.contentDocument?.documentElement.dataset.drawerMobile === String(!mobile), mobile);
    assert.equal(await page.evaluate(() => document.querySelector('#ruanchuang-settings-overlay iframe') === window.__responsiveSettingsFrame), true, 'Changing viewport must keep the settings document');
    assert.equal(await page.locator('#prototype-screen').evaluate(f => f.inert), true);
    await page.frameLocator('#ruanchuang-settings-overlay iframe').locator('#close-drawer-btn, #btn-close-drawer').press('Escape');
    await finishMotion();
    await page.waitForFunction(() => !document.getElementById('ruanchuang-settings-overlay'));
    await page.setViewportSize(mobile ? { width: 390, height: 844 } : { width: 1440, height: 900 });
    await ready('schedule');
    results.push({ viewport: mobile ? 'mobile' : 'desktop', route: 'settings-responsive', passed: true });

    await go('goals');
    await page.frameLocator('#prototype-screen').locator('main [onclick^="openDrawer"]').first().click();
    await page.waitForFunction(() => document.getElementById('prototype-screen').contentDocument.getElementById('goalDrawer').dataset.drawerState === 'opening');
    await freeze('goals', 0.45);
    await finishMotion();
    await page.screenshot({ path: `build/drawer-qa/${mobile ? 'mobile' : 'desktop'}-goal-drawer.png` });
    const goalPanel = page.frameLocator('#prototype-screen').locator('#goalDrawer');
    await goalPanel.locator('button').first().click();
    const goalClosing = await freeze('goals', 0.45);
    await page.locator('#prototype-screen').evaluate(f => f.contentWindow.openDrawer('目标详情'));
    continuous(goalClosing, await freeze('goals', 0), 'Goal drawer must reopen without restarting its position');
    await finishMotion();
    await page.frameLocator('#prototype-screen').locator('#goalDrawer button').first().press('Escape');
    await finishMotion();
    await page.waitForFunction(() => document.getElementById('prototype-screen').contentDocument.getElementById('goalDrawer').inert);
    await page.frameLocator('#prototype-screen').locator('main [onclick="openDissectModal()"]').first().click();
    await page.waitForFunction(() => document.getElementById('prototype-screen').contentDocument.querySelector('#dissectModal [data-drawer-panel]').dataset.drawerState === 'opening');
    await finishMotion();
    await page.screenshot({ path: `build/drawer-qa/${mobile ? 'mobile' : 'desktop'}-goal-decomposition.png` });
    await page.frameLocator('#prototype-screen').locator('#dissectModal button').first().press('Escape');
    await finishMotion();
    await page.waitForFunction(() => !document.getElementById('workspace-shell').inert);
    results.push({ viewport: mobile ? 'mobile' : 'desktop', route: 'goal-drawer-and-decomposition', passed: true, reversal: true });

    await page.emulateMedia({ reducedMotion: 'reduce' });
    await go('schedule');
    await go('urgent-task');
    assert.equal(await page.locator('#prototype-screen').evaluate(f => f.contentDocument.querySelector('[data-drawer-panel]').getAnimations().length), 0);
    await page.evaluate(() => window.__RUANCHUANG_RETURN__()); await ready('schedule');
    await page.waitForFunction(() => !document.querySelector('[data-drawer-layer]'));
    results.push({ viewport: mobile ? 'mobile' : 'desktop', route: 'reduced-motion', passed: true });

    await page.emulateMedia({ reducedMotion: 'no-preference' });
    await go('urgent-task');
    await finishMotion();
    await page.evaluate(() => window.__RUANCHUANG_RETURN__()); await ready('schedule');
    await page.emulateMedia({ reducedMotion: 'reduce' });
    await page.waitForFunction(() => !document.querySelector('[data-drawer-layer]') && !document.getElementById('workspace-shell').inert && !document.getElementById('prototype-screen').inert);
    results.push({ viewport: mobile ? 'mobile' : 'desktop', route: 'reduced-motion-during-dismissal', passed: true });
    await page.emulateMedia({ reducedMotion: 'no-preference' });

    if (!mobile) {
      const entry = { id: 'schedule-001', title: 'Drawer route fixture', day: '2026-10-29', tag: '开发', time: { hour: 9, minute: 0 }, height: 80 };
      await page.route('**/api/schedule', r => r.fulfill({ json: [entry] }));
      await page.route('**/api/schedule/schedule-001', r => {
        Object.assign(entry, r.request().postDataJSON());
        return r.fulfill({ json: entry });
      });
      await page.route('**/api/microtasks', r => r.fulfill({ json: [{ id: 'task-001', title: 'Microtask route fixture', status: 'pending', duration: 45, tags: [] }] }));
      await page.route('**/api/microtasks/task-001', r => r.fulfill({ json: { id: 'task-001', status: 'completed' } }));
      for (const [parent, selector, route, id, titleSelector, title] of [
        ['schedule', '[data-schedule-id="schedule-001"]', 'schedule-detail', 'schedule-001', '#detailTitle', entry.title],
        ['micro', '[data-microtask-id="task-001"]', 'microtask-detail', 'task-001', '#taskTitle', 'Microtask route fixture'],
      ]) {
        await go(parent);
        if (parent === 'schedule') await page.locator('#prototype-screen').evaluate(f => f.contentDocument.stitchCalendar.refresh());
        await page.frameLocator('#prototype-screen').locator(selector).first().evaluate(card => card.click());
        await ready(route);
        assert.equal(new URL(await page.url()).hash, `#/${route}?id=${id}`, 'Card navigation must update the parent route and preserve its id');
        await page.frameLocator('#prototype-screen').locator(titleSelector).waitFor({ state: 'visible' });
        assert.equal(await page.frameLocator('#prototype-screen').locator(titleSelector).textContent(), title);
        await finishMotion();
        if (route === 'schedule-detail') {
          await page.frameLocator('#prototype-screen').locator('#editBtn').click();
          await page.frameLocator('#prototype-screen').locator('#titleInput').fill('Saved drawer fixture');
          await page.frameLocator('#prototype-screen').locator('#saveBtn').click();
          await ready(parent); await finishMotion();
          await page.frameLocator('#prototype-screen').locator(selector).first().evaluate(card => card.click());
          await ready(route); await finishMotion();
          assert.equal(await page.frameLocator('#prototype-screen').locator('#detailTitle').textContent(), 'Saved drawer fixture', 'Retained detail must show its saved content when reopened');
          await page.frameLocator('#prototype-screen').locator('#editBtn').click();
          assert.equal(await page.frameLocator('#prototype-screen').locator('#saveBtn').isEnabled(), true, 'Retained detail must allow another save');
        } else {
          page.once('dialog', dialog => dialog.accept());
          await page.frameLocator('#prototype-screen').locator('#completeBtn').click();
          await page.frameLocator('#prototype-screen').locator('#completeBtn').waitFor({ state: 'hidden' });
        }
        await page.evaluate(() => window.__RUANCHUANG_RETURN__()); await ready(parent); await finishMotion();
        if (route === 'microtask-detail') {
          await go('goals');
          await page.evaluate(() => [...document.querySelectorAll('iframe')].find(f => f.title === '时序智配 microtask-detail' && new URL(f.src).searchParams.get('id') === 'task-001').contentWindow.closeDrawer());
          assert.equal(new URL(page.url()).hash, '#/goals', 'A callback from an inactive detail must not change the current route');
          await page.waitForTimeout(1600);
          assert.equal(await page.locator('#prototype-screen').getAttribute('title'), '时序智配 goals', 'A retained completion timer must not navigate a different page');
        }
      }
      results.push({ viewport: 'desktop', route: 'real-detail-card-navigation', passed: true });

      const direct = await context.newPage();
      await direct.goto(base + '#/urgent-task');
      await direct.waitForFunction(() => document.getElementById('prototype-screen')?.title === '时序智配 urgent-task');
      assert.equal(await direct.locator('[data-drawer-background]').count(), 1, 'Direct drawer links must first retain a real source page');
      await direct.close();
      const racing = await context.newPage();
      let releaseParent;
      const parentGate = new Promise(resolve => { releaseParent = resolve; });
      await racing.route('**/stitch/screens/smart-calendar/index.html?*', async r => { await parentGate; await r.continue().catch(() => {}); });
      const parentRequested = racing.waitForRequest('**/stitch/screens/smart-calendar/index.html?*');
      await racing.goto(base + '#/urgent-task', { waitUntil: 'domcontentloaded' });
      await parentRequested;
      await racing.evaluate(() => { location.hash = '#/micro'; });
      await racing.waitForFunction(() => document.getElementById('prototype-screen')?.title === '时序智配 micro');
      releaseParent();
      await racing.waitForFunction(() => [...document.querySelectorAll('iframe')].some(f => f.title === '时序智配 schedule' && f.contentDocument?.getElementById('ruanchuang-polish-styles')));
      await racing.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
      assert.equal(await racing.locator('#prototype-screen').getAttribute('title'), '时序智配 micro', 'A delayed direct-drawer background must not override newer navigation');
      await racing.close();
      results.push({ viewport: 'desktop', route: 'direct-drawer-and-cold-navigation-race', passed: true });
    }

    await page.evaluate(() => { window.__drawerPlaybackRate = 1; window.__frameTimes = []; window.__sampleFrames = true; const sample = t => { window.__frameTimes.push(t); if (window.__sampleFrames) requestAnimationFrame(sample); }; requestAnimationFrame(sample); });
    await go('urgent-task');
    await page.waitForFunction(() => document.getElementById('prototype-screen').contentDocument.querySelector('[data-drawer-panel]').dataset.drawerState === 'open');
    await page.evaluate(() => window.__RUANCHUANG_RETURN__()); await ready('schedule');
    await page.waitForFunction(() => !document.querySelector('[data-drawer-layer]'));
    const timing = await page.evaluate(() => {
      window.__sampleFrames = false;
      const gaps = window.__frameTimes.slice(1).map((t, i) => t - window.__frameTimes[i]).sort((a, b) => a - b);
      return { samples: gaps.length, medianMs: gaps[Math.floor(gaps.length / 2)], p95Ms: gaps[Math.floor(gaps.length * .95)], maxMs: gaps.at(-1) };
    });
    results.push({ viewport: mobile ? 'mobile' : 'desktop', route: 'warm-frame-timing', passed: true, ...timing });
    assert.deepEqual(errors, []);
    await context.close();
  }
  await mkdir('build/reports', { recursive: true });
  await writeFile('build/reports/drawer-motion.json', JSON.stringify(results, null, 2));
  console.log(JSON.stringify({ release: release.release, cases: results }, null, 2));
} finally { await browser.close(); await new Promise(r => server.close(r)); }
