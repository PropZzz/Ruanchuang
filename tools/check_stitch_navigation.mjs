import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { extname, resolve, sep } from 'node:path';
import { createRequire } from 'node:module';
import { buildStitchWeb } from './build_stitch_web.mjs';
import { checkPageMotion } from './stitch_motion_checks.mjs';

const require = createRequire(import.meta.url);
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const release = await buildStitchWeb();
const mime = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.woff2': 'font/woff2', '.png': 'image/png' };
const server = createServer(async (req, res) => {
  try {
    const path = new URL(req.url, 'http://localhost').pathname;
    if (path.startsWith('/api/')) { res.setHeader('Content-Type', 'application/json'); res.end('{}'); return; }
    const file = resolve(release.output, '.' + (path === '/' ? '/index.html' : path));
    assert.ok(file.startsWith(release.output + sep));
    res.setHeader('Content-Type', mime[extname(file)] || 'application/octet-stream');
    res.end(await readFile(file));
  } catch { res.writeHead(404); res.end(); }
});
await new Promise(r => server.listen(0, '127.0.0.1', r));
const base = process.argv.includes('--url') ? process.argv[process.argv.indexOf('--url') + 1] : `http://127.0.0.1:${server.address().port}/`;
const browser = await chromium.launch({ headless: true });
const context = await browser.newContext({ viewport: { width: 1440, height: 900 } });
await context.addInitScript(() => { window.__RUANCHUANG_API__ = location.origin + '/api'; });
const page = await context.newPage();
await page.route('**/api/**', r => ['GET', 'HEAD', 'OPTIONS'].includes(r.request().method())
  ? r.continue() : r.fulfill({ json: {} }));
const documents = [];
const errors = [];
page.on('pageerror', e => errors.push(e.message));
page.on('request', r => { if (r.isNavigationRequest() && /stitch\/(screens|mobile)/.test(r.url())) documents.push(r.url()); });
const ready = route => page.waitForFunction(route => {
  const f = document.getElementById('prototype-screen');
  return f?.title === `时序智配 ${route}` && f.contentDocument?.getElementById('ruanchuang-polish-styles');
}, route);
const go = async route => { await page.evaluate(route => { location.hash = '#/' + route; }, route); await ready(route); };
try {
  await page.goto(base + '#/micro'); await ready('micro');
  await page.locator('#prototype-screen').evaluate(f => {
    f.contentWindow.__navigationProbe = 'retained';
    f.contentDocument.querySelector('input').value = '尚未提交的草稿';
    f.contentWindow.scrollTo(0, 180);
  });
  const scroll = await page.locator('#prototype-screen').evaluate(f => f.contentWindow.scrollY);
  await go('schedule'); await go('micro');
  assert.equal(documents.filter(u => u.includes('/screens/microtasks/')).length, 1, 'Revisiting a primary route must not reload its document');
  assert.deepEqual(await page.locator('#prototype-screen').evaluate(f => [f.contentWindow.__navigationProbe, f.contentDocument.querySelector('input').value, f.contentWindow.scrollY]), ['retained', '尚未提交的草稿', scroll]);
  console.log('Primary document, draft and scroll survive navigation.');
  await checkPageMotion(page, go);
  await page.evaluate(() => { window.__shell = document.getElementById('workspace-shell'); });
  for (const route of ['review', 'diagnostics', 'goals', 'team', 'profile', 'focus', 'schedule', 'micro']) {
    await page.locator(`#workspace-shell a[data-route="${route}"]`).click();
    await ready(route);
    assert.equal(await page.evaluate(() => window.__shell === document.getElementById('workspace-shell')), true);
    assert.equal(await page.locator('#workspace-shell a[aria-current="page"]').getAttribute('data-route'), route);
    assert.deepEqual(await page.locator('#workspace-shell header button').evaluateAll(buttons => buttons.map(button => button.dataset.route)), ['settings-drawer']);
  }
  const beforeWarm = documents.length;
  for (const route of ['focus', 'schedule', 'micro', 'review', 'diagnostics', 'profile', 'goals', 'team']) await go(route);
  assert.equal(documents.length, beforeWarm, 'All eight primary routes must remain warm');
  assert.equal(await page.locator('.workspace-page:not([hidden])').count(), 1);
  assert.equal(await page.locator('.workspace-page[hidden]:not([inert])').count(), 0);
  console.log('Persistent shell, eight warm routes and hidden-frame accessibility passed.');
  await page.goBack(); await ready('goals');
  await page.goForward(); await ready('team');
  await page.emulateMedia({ reducedMotion: 'reduce' });
  await go('micro');
  assert.equal(await page.locator('#prototype-screen').evaluate(f => f.getAnimations().length), 0);
  await page.emulateMedia({ reducedMotion: 'no-preference' });

  // A running focus session continues logically while its hidden DOM stops ticking.
  await go('focus');
  await page.route('**/api/focus/**', r => r.fulfill({ json: {} }));
  await page.frameLocator('#prototype-screen').locator('#toggle-timer-btn').click();
  await go('micro');
  const hiddenTime = await page.evaluate(() => {
    const f = [...document.querySelectorAll('iframe')].find(f => f.title === '时序智配 focus');
    return f.contentDocument.getElementById('focus-timer-display').textContent;
  });
  await page.waitForTimeout(2100);
  assert.equal(await page.evaluate(() => [...document.querySelectorAll('iframe')].find(f => f.title === '时序智配 focus').contentDocument.getElementById('focus-timer-display').textContent), hiddenTime);
  await go('focus');
  const resumedTime = await page.frameLocator('#prototype-screen').locator('#focus-timer-display').innerText();
  const seconds = value => value.split(':').reduce((a, b) => a * 60 + Number(b), 0);
  assert.ok(seconds(hiddenTime) - seconds(resumedTime) >= 2);
  console.log('Hidden countdown stops DOM work and reconciles elapsed time on return.');

  await go('profile');
  await page.setViewportSize({ width: 390, height: 844 });
  await page.waitForFunction(() => document.getElementById('workspace-shell').hidden);
  await go('micro');
  await page.locator('#prototype-screen').evaluate(f => { f.contentWindow.__mobileProbe = true; });
  await go('schedule'); await go('micro');
  assert.equal(await page.locator('#prototype-screen').evaluate(f => f.contentWindow.__mobileProbe), true);
  await page.setViewportSize({ width: 1440, height: 900 });
  await page.waitForFunction(() => !document.getElementById('workspace-shell').hidden);
  await go('profile');
  await page.mouse.move(900, 80);
  await page.locator('#workspace-shell').evaluate(async shell => {
    await Promise.all(shell.getAnimations({ subtree: true }).map(a => a.finished.catch(() => {})));
  });
  await page.screenshot({ path: 'build/navigation-desktop.png' });
  console.log('Desktop/mobile breakpoint and mobile document retention passed.');

  // A cold request must never replace a newer selection when it finishes late.
  await page.reload(); await ready('profile');
  let finishCold;
  const coldGate = new Promise(resolve => { finishCold = resolve; });
  await page.route('**/stitch/screens/team/index.html?*', async r => { await coldGate; await r.continue(); });
  const coldRequest = page.waitForRequest('**/stitch/screens/team/index.html?*');
  await page.locator('#workspace-shell a[data-route="team"]').click();
  await coldRequest;
  assert.equal(await page.locator('#prototype-screen').getAttribute('title'), '时序智配 profile');
  await go('micro'); finishCold();
  await page.waitForFunction(() => [...document.querySelectorAll('iframe')].find(f => f.title === '时序智配 team')?.contentDocument?.getElementById('ruanchuang-polish-styles'));
  assert.equal(await page.locator('#prototype-screen').getAttribute('title'), '时序智配 micro');
  await page.unroute('**/stitch/screens/team/index.html?*');
  let finishRescue;
  const rescueGate = new Promise(resolve => { finishRescue = resolve; });
  await page.route('**/stitch/screens/rescue-comparison/index.html?*', async r => { await rescueGate; await r.continue(); });
  const rescueRequest = page.waitForRequest('**/stitch/screens/rescue-comparison/index.html?*');
  await page.evaluate(() => { location.hash = '#/rescue-comparison'; }); await rescueRequest;
  await go('profile'); finishRescue();
  await page.waitForFunction(() => [...document.querySelectorAll('iframe')].find(f => f.title === '时序智配 rescue-comparison')?.contentDocument?.getElementById('ruanchuang-polish-styles')?.sheet);
  assert.equal(await page.locator('#prototype-screen').getAttribute('title'), '时序智配 profile');
  await page.unroute('**/stitch/screens/rescue-comparison/index.html?*');
  await go('micro');
  await page.route('**/stitch/screens/diagnostics/index.html?*', r => r.fulfill({ status: 503, contentType: 'text/html', body: '<h1>Unavailable</h1>' }));
  await page.locator('#workspace-shell a[data-route="diagnostics"]').click();
  await page.locator('#page-load-status button').waitFor();
  assert.equal(await page.locator('#prototype-screen').getAttribute('title'), '时序智配 micro');
  await page.unroute('**/stitch/screens/diagnostics/index.html?*');
  await page.locator('#page-load-status button').click(); await ready('diagnostics');
  console.log('Cold-load continuity, latest-navigation wins and retry recovery passed.');

  // Stub writes even against production: this test must not mutate server data.
  let writes = 0;
  let reads = 0;
  await page.route('**/api/schedule', async r => {
    if (r.request().method() === 'POST') writes++; else reads++;
    await r.fulfill({ json: r.request().method() === 'POST' ? {} : [] });
  });
  await go('schedule');
  await page.waitForFunction(() => document.getElementById('prototype-screen').contentDocument.documentElement.dataset.backendState !== 'loading');
  const beforeReads = reads;
  const beforeSchedule = documents.filter(u => u.includes('/screens/smart-calendar/')).length;
  await go('create-schedule');
  await page.frameLocator('#prototype-screen').locator('textarea').fill('导航测试日程');
  await page.frameLocator('#prototype-screen').getByRole('button', { name: /保存并写入日程/ }).click();
  await ready('schedule');
  await page.waitForFunction(() => document.getElementById('prototype-screen').contentDocument.documentElement.dataset.backendState !== 'loading');
  assert.equal(writes, 1); assert.ok(reads > beforeReads);
  assert.equal(documents.filter(u => u.includes('/screens/smart-calendar/')).length, beforeSchedule);
  console.log('Saving refreshes destination data without replacing its document.');

  await page.route('**/api/settings', r => r.fulfill({ json: { themeMode: 'light', locale: 'zh_CN' } }));
  await page.evaluate(() => { localStorage.setItem('access_token', 'navigation-test-account-a'); window.dispatchEvent(new StorageEvent('storage', { key: 'access_token' })); });
  await ready('schedule');
  await page.locator('#workspace-shell button[data-route="settings-drawer"]').click();
  await page.locator('#ruanchuang-settings-overlay').waitFor();
  assert.equal(await page.locator('#workspace-shell').evaluate(el => el.inert), true);
  await page.evaluate(() => { localStorage.setItem('access_token', 'navigation-test-account-b'); window.dispatchEvent(new StorageEvent('storage', { key: 'access_token' })); });
  await page.waitForFunction(() => !document.getElementById('ruanchuang-settings-overlay'));
  await ready('schedule');
  assert.equal(await page.locator('.workspace-page').count(), 1);
  assert.equal(await page.locator('#workspace-shell').evaluate(el => el.inert), false);
  console.log('Account changes clear retained pages and close stale settings.');
  assert.deepEqual(errors, []);
} finally { await browser.close(); await new Promise(r => server.close(r)); }
