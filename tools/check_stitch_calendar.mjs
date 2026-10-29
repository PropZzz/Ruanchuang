import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { readFile, mkdir, writeFile } from 'node:fs/promises';
import { extname, resolve, sep } from 'node:path';
import { createRequire } from 'node:module';
import { buildStitchWeb } from './build_stitch_web.mjs';

const { chromium } = createRequire(import.meta.url)(process.env.PLAYWRIGHT_MODULE || 'playwright');
const release = await buildStitchWeb();
const mime = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.woff2': 'font/woff2' };
const server = createServer(async (req, res) => {
  try {
    const pathname = new URL(req.url, 'http://localhost').pathname;
    const file = resolve(release.output, '.' + (pathname === '/' ? '/index.html' : pathname));
    assert.ok(file.startsWith(release.output + sep));
    res.setHeader('Content-Type', mime[extname(file)] || 'application/octet-stream'); res.end(await readFile(file));
  } catch { res.writeHead(404); res.end(); }
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const base = process.argv.includes('--url') ? process.argv[process.argv.indexOf('--url') + 1] : `http://127.0.0.1:${server.address().port}/`;
const browser = await chromium.launch({ headless: true });
const report = [];
await mkdir('build/calendar-qa', { recursive: true });
const seed = () => [
  { id: 'real-1', title: '真实账号的架构评审', day: '2026-10-29', time: { hour: 9, minute: 30 }, height: 120, tag: '评审', repeat: 'none' },
  { id: 'real-2', title: '另一个重叠日程', day: '2026-10-29', time: { hour: 9, minute: 45 }, height: 60, tag: '工作' },
  { id: 'repeat', title: '每周固定同步', day: '2026-10-22', time: { hour: 9, minute: 45 }, height: 40, tag: '协作', repeat: 'weekly', repeatUntil: '2026-12-31', color: 4280954708, goalId: 'goal-a', goalTaskId: 'goal-task-a' },
  { id: 'floating', title: '旧版未固定日期日程', day: null, time: { hour: 16, minute: 0 }, height: 40, tag: '常规' },
  { id: 'night', title: '跨午夜发布', day: '2026-10-28', time: { hour: 23, minute: 30 }, height: 160, tag: '发布' },
  { id: 'midnight', title: '零点任务', day: '2026-10-29', time: { hour: 0, minute: 15 }, height: 40, tag: '常规' },
];
try {
  for (const mobile of [false, true]) {
    const context = await browser.newContext({ viewport: mobile ? { width: 390, height: 844 } : { width: 1440, height: 1000 }, timezoneId: 'Asia/Shanghai', reducedMotion: 'reduce' });
    await context.addInitScript(() => {
      window.__RUANCHUANG_API__ = location.origin + '/api';
      const NativeDate = Date, fixed = new NativeDate('2026-10-29T10:30:00+08:00').valueOf();
      window.Date = class extends NativeDate { constructor(...args) { super(...(args.length ? args : [fixed])); } static now() { return fixed; } };
      if (!localStorage.getItem('access_token')) localStorage.setItem('access_token', 'calendar-account-a');
    });
    let records = seed(), mode = 'normal', writes = 0;
    const errors = [], page = await context.newPage();
    page.on('pageerror', e => errors.push(e.message));
    await page.route('**/api/**', async route => {
      const req = route.request(), url = new URL(req.url()), method = req.method();
      if (url.pathname === '/api/schedule' && method === 'GET') {
        if (mode === 'unauthorized') return route.fulfill({ status: 401, json: { detail: 'Login required' } });
        if (mode === 'offline') return route.fulfill({ status: 503, json: { detail: 'Unavailable' } });
        return route.fulfill({ json: req.headers().authorization?.includes('account-b') ? [] : records });
      }
      if (url.pathname === '/api/schedule' && method === 'POST') {
        const item = { ...req.postDataJSON(), id: 'created-calendar-record' }; records.push(item); writes++; return route.fulfill({ json: item });
      }
      if (url.pathname.startsWith('/api/schedule/') && ['PUT', 'DELETE'].includes(method)) {
        const id = url.pathname.split('/').at(-1);
        if (method === 'DELETE') { records = records.filter(r => r.id !== id); writes++; return route.fulfill({ status: 204 }); }
        const item = { ...req.postDataJSON(), id }; records = records.map(r => r.id === id ? item : r); writes++; return route.fulfill({ json: item });
      }
      if (url.pathname === '/api/schedule/conflicts') return route.fulfill({ json: { conflicts: url.searchParams.get('day') === '2026-10-29' ? [{ a: 'real-1', b: 'real-2' }] : [] } });
      return route.fulfill({ json: { ok: true } });
    });
    const ready = route => page.waitForFunction(route => document.getElementById('prototype-screen')?.title === `时序智配 ${route}`, route);
    const settled = () => page.waitForFunction(() => document.getElementById('prototype-screen')?.contentDocument?.querySelector('#live-calendar-root[aria-busy="false"]'));
    const frame = () => page.frameLocator('#prototype-screen');
    const selectDate = async day => { await frame().locator('[data-cal-date]').fill(day); await settled(); };
    const selectView = async mode => { await frame().locator(`[data-cal-action="${mode}"]`).click(); await settled(); };
    await page.goto(base + '#/schedule'); await ready('schedule'); await settled();
    assert.equal(await frame().locator('#live-calendar-root').getAttribute('data-selected-day'), '2026-10-29');
    assert.equal(await frame().locator('#live-calendar-root').getAttribute('data-calendar-view'), mobile ? 'day' : 'week');
    assert.ok(await frame().locator('[data-schedule-id="real-1"]').count());
    assert.equal(await frame().locator('[data-schedule-id="schedule-001"]').count(), 0);
    assert.equal(await frame().locator('.cal-now').count(), mobile ? 0 : 1);
    assert.equal(await frame().locator('.cal-heading, .cal-layout, .cal-agenda').count(), 0, 'The calendar must enhance the original layout');
    assert.ok(await frame().getByText(mobile ? '生成服务端救援方案' : '日程健康与救援摘要', { exact: true }).count(), 'Original rescue component must remain');
    await page.locator('#prototype-screen').evaluate(f => { const d = f.contentDocument; d.__calendarDeck = d.getElementById('calendar-period'); d.__calendarRescue = d.getElementById('calendar-conflict-status') || d.getElementById('schedule-conflict-status'); });
    if (mobile) {
      await frame().getByRole('button', {name: /生成服务端救援方案/}).click(); await ready('urgent-task');
      await frame().locator('[data-drawer-panel] button[aria-label="关闭抽屉"]').click(); await ready('schedule'); await settled();
      assert.ok((await frame().locator('#rescue-sheet').getAttribute('class')).includes('translate-y-full'), 'Rescue must use the shared drawer without opening a stale inline sheet behind it');
    }
    await selectView('day');
    assert.ok(await frame().locator('[data-schedule-id="repeat"]').count());
    assert.ok(await frame().locator('[data-schedule-id="night"]').count());
    assert.ok(await frame().locator('[data-schedule-id="floating"]').count());
    assert.match(await frame().locator(mobile ? '#schedule-conflict-status' : '#calendar-conflict-status').textContent(), /4 处/);
    const positions = await frame().locator('.cal-position:has([data-schedule-id="real-1"]), .cal-position:has([data-schedule-id="real-2"])').evaluateAll(nodes => nodes.map(n => n.style.left));
    if (!mobile) assert.equal(new Set(positions).size, 2, 'Overlapping cards must occupy different columns');
    await page.screenshot({ path: `build/calendar-qa/${mobile ? 'mobile' : 'desktop'}-day.png` });
    await selectView('week');
    assert.equal(await frame().locator('.cal-column-heading').count(), 7);
    await page.screenshot({ path: `build/calendar-qa/${mobile ? 'mobile' : 'desktop'}-week.png` });
    await selectDate('2027-01-03');
    assert.match(await frame().locator('#calendar-range').textContent(), mobile ? /53/ : /2026\/12\/28/);
    await selectView('month'); assert.equal(await frame().locator('.cal-month-day').count(), 42);
    await frame().locator('[data-cal-action="next"]').click(); await settled();
    assert.equal(await frame().locator('[data-cal-date]').inputValue(), '2027-02-03');
    await frame().locator('[data-cal-action="today"]').click(); await settled();
    await page.screenshot({ path: `build/calendar-qa/${mobile ? 'mobile' : 'desktop'}-month.png` });

    await selectDate('2026-11-05');
    await frame().locator('[data-cal-action="create"]').first().click(); await ready('create-schedule');
    assert.equal(await frame().locator('#schedule-date-input').inputValue(), '2026-11-05');
    await frame().locator('textarea').fill('新增 <真实> 日程');
    await frame().locator('#schedule-time-input').fill('16:15');
    await frame().locator('#schedule-duration-input').fill('50');
    await frame().getByRole('button', { name: /保存并写入日程/ }).click(); await ready('schedule'); await settled();
    const created = records.find(r => r.id === 'created-calendar-record');
    assert.equal(created.day, '2026-11-05'); assert.deepEqual(created.time, { hour: 16, minute: 15 });
    assert.equal(Math.round(created.height * 60 / 80), 50);
    assert.match(await frame().locator('[data-schedule-id="created-calendar-record"]').first().textContent(), /新增 <真实> 日程/);
    await frame().locator('[data-cal-action="create"]').first().click(); await ready('create-schedule');
    assert.equal(await frame().locator('#schedule-time-input').inputValue(), '09:00', 'A committed form must reset when starting a fresh schedule');
    assert.equal(await frame().locator('textarea').inputValue(), '');
    await frame().locator('[data-drawer-panel] button[aria-label="关闭抽屉"]').click(); await ready('schedule'); await settled();
    await frame().locator('[data-schedule-id="created-calendar-record"]').first().click(); await ready('schedule-detail');
    await frame().locator('#editBtn').click();
    await frame().locator('#titleInput').fill('修改后的真实日程');
    await frame().locator('#dateInput').fill('2026-11-06');
    await frame().locator('#saveBtn').click(); await ready('schedule'); await settled();
    assert.equal(await frame().locator('[data-cal-date]').inputValue(), '2026-11-06');
    assert.match(await frame().locator('[data-schedule-id="created-calendar-record"]').first().textContent(), /修改后的真实日程/);
    await frame().locator('[data-schedule-id="created-calendar-record"]').first().click(); await ready('schedule-detail');
    page.once('dialog', dialog => dialog.accept());
    await frame().locator('#deleteBtn').click(); await ready('schedule'); await settled();
    assert.equal(await frame().locator('[data-schedule-id="created-calendar-record"]').count(), 0);
    assert.equal(writes, 3, 'Create/edit/delete must each write once');
    assert.equal(await page.locator('#prototype-screen').evaluate(f => { const d = f.contentDocument; return d.__calendarDeck === d.getElementById('calendar-period') && d.__calendarRescue === (d.getElementById('calendar-conflict-status') || d.getElementById('schedule-conflict-status')); }), true, 'Calendar updates must preserve the original controller and rescue DOM');

    for (const day of ['2026-11-07', '2026-11-08']) {
      await selectDate(day);
      await frame().locator('[data-cal-action="create"]').first().click(); await ready('create-schedule');
      assert.equal(await frame().locator('#schedule-date-input').inputValue(), day, 'Different create contexts must not reuse a stale date');
      await frame().locator('[data-drawer-panel] button[aria-label="关闭抽屉"]').click(); await ready('schedule'); await settled();
    }

    await selectDate('2026-10-29'); await selectView('day');
    await frame().locator('[data-schedule-id="repeat"]').click(); await ready('schedule-detail');
    await frame().locator('#editBtn').click(); await frame().locator('#titleInput').fill('重复规则保留');
    await frame().locator('#saveBtn').click(); await ready('schedule'); await settled();
    assert.equal(await frame().locator('[data-cal-date]').inputValue(), '2026-10-29', 'Editing an occurrence must keep the viewed day when its anchor is unchanged');
    const repeated = records.find(r => r.id === 'repeat');
    assert.equal(repeated.repeatUntil, '2026-12-31'); assert.equal(repeated.goalId, 'goal-a'); assert.equal(repeated.goalTaskId, 'goal-task-a'); assert.equal(repeated.color, 4280954708);
    await frame().locator('[data-schedule-id="midnight"]').click(); await ready('schedule-detail');
    await frame().locator('#editBtn').click(); assert.equal(await frame().locator('#timeInput').inputValue(), '00:15');
    await frame().locator('#closeBtn').click(); await ready('schedule'); await settled();
    await frame().locator('[data-schedule-id="floating"]').click(); await ready('schedule-detail');
    await frame().locator('#editBtn').click(); assert.equal(await frame().locator('#dateInput').inputValue(), '');
    await frame().locator('#titleInput').fill('保留无固定日期'); await frame().locator('#saveBtn').click(); await ready('schedule'); await settled();
    assert.equal(records.find(r => r.id === 'floating').day, null);

    await selectDate('2026-11-07');
    let releaseViewportRead, holdViewportRead = true;
    const viewportGate = new Promise(resolve => { releaseViewportRead = resolve; });
    const holdOneRead = async route => {
      if (!holdViewportRead) return route.fallback();
      holdViewportRead = false; await viewportGate; return route.fulfill({ json: records });
    };
    await page.route('**/api/schedule', holdOneRead);
    const viewportRead = page.waitForRequest('**/api/schedule');
    await page.evaluate(() => { document.getElementById('prototype-screen').contentDocument.stitchCalendar.refresh(); }); await viewportRead;
    await page.evaluate(() => { window.__viewportCalendar = document.getElementById('prototype-screen'); });
    await page.setViewportSize(mobile ? { width: 1440, height: 1000 } : { width: 390, height: 844 });
    await page.waitForFunction(() => document.getElementById('prototype-screen') !== window.__viewportCalendar); await settled();
    assert.equal(await frame().locator('[data-cal-date]').inputValue(), '2026-11-07');
    await selectDate('2026-11-08'); await selectView('month');
    const viewportResponse = page.waitForResponse(response => response.url().endsWith('/api/schedule'));
    releaseViewportRead(); await (await viewportResponse).finished();
    await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
    await page.unroute('**/api/schedule', holdOneRead);
    await page.evaluate(() => { window.__viewportCalendar = document.getElementById('prototype-screen'); });
    await page.setViewportSize(mobile ? { width: 390, height: 844 } : { width: 1440, height: 1000 });
    await page.waitForFunction(() => document.getElementById('prototype-screen') !== window.__viewportCalendar); await settled();
    assert.equal(await frame().locator('[data-cal-date]').inputValue(), '2026-11-08', 'Returning to a cached viewport must keep the latest selected date');
    assert.equal(await frame().locator('#live-calendar-root').getAttribute('data-calendar-view'), 'month');

    await selectDate('2026-10-29'); await selectView('day');
    await page.evaluate(() => { window.__calendarDocument = document.getElementById('prototype-screen'); location.hash = '#/micro'; }); await ready('micro');
    await page.evaluate(() => { location.hash = '#/schedule'; }); await ready('schedule'); await settled();
    assert.equal(await page.evaluate(() => document.getElementById('prototype-screen') === window.__calendarDocument), true);
    assert.equal(await frame().locator('[data-cal-date]').inputValue(), '2026-10-29');
    mode = 'offline'; await frame().locator('[data-cal-action="retry"]').click(); await settled();
    assert.match(await frame().locator('[data-calendar-status]').textContent(), /上次读取/);
    assert.ok(await frame().locator('[data-schedule-id="real-1"]').count());
    mode = 'unauthorized'; await frame().locator('[data-cal-action="retry"]').click(); await settled();
    assert.equal(await frame().locator('[data-schedule-id]').count(), 0);
    assert.match(await frame().locator('[data-calendar-status]').textContent(), /登录后/);
    await page.screenshot({ path: `build/calendar-qa/${mobile ? 'mobile' : 'desktop'}-login.png` });
    mode = 'normal';
    let releaseRead;
    const gate = new Promise(resolve => { releaseRead = resolve; });
    await page.route('**/api/schedule', async r => {
      if (r.request().headers().authorization?.includes('account-a')) { await gate; return r.fulfill({ json: records }).catch(() => {}); }
      return r.fulfill({ json: [] });
    });
    const heldRead = page.waitForRequest('**/api/schedule');
    await page.evaluate(() => { document.getElementById('prototype-screen').contentDocument.stitchCalendar.refresh(); }); await heldRead;
    await page.evaluate(() => { localStorage.setItem('access_token', 'calendar-account-b'); window.dispatchEvent(new StorageEvent('storage', { key: 'access_token' })); }); await ready('schedule'); await settled();
    const oldResponse = page.waitForResponse(response => response.url().endsWith('/api/schedule') && response.request().headers().authorization?.includes('account-a'));
    releaseRead(); await oldResponse;
    await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
    assert.equal(await frame().locator('[data-schedule-id]').count(), 0, 'Another account must never inherit previous cards');
    assert.match(await frame().locator('.cal-empty').textContent(), /还没有日程/);
    assert.equal(await page.locator('#prototype-screen').evaluate(f => f.contentDocument.documentElement.scrollWidth <= f.contentWindow.innerWidth), true, 'Page must not overflow horizontally');
    assert.deepEqual(errors, []);
    report.push({ viewport: mobile ? 'mobile' : 'desktop', passed: true, checks: ['real-date', 'day-week-month', 'cross-year', 'recurrence', 'floating-legacy', 'overnight', 'overlap', 'create-edit-delete', 'create-date-context', 'recurrence-metadata', 'retained-document', 'viewport-return', 'offline', 'login', 'account-isolation-with-late-response', 'responsive'] });
    await context.close();
  }
  for (const [timezoneId, expectedDay] of [['Asia/Shanghai', '2026-10-29'], ['Pacific/Honolulu', '2026-10-28']]) {
    const context = await browser.newContext({ timezoneId, viewport: { width: 1280, height: 900 } });
    await context.addInitScript(() => {
      window.__RUANCHUANG_API__ = location.origin + '/api';
      const NativeDate = Date, fixed = new NativeDate('2026-10-28T16:30:00Z').valueOf();
      window.Date = class extends NativeDate { constructor(...args) { super(...(args.length ? args : [fixed])); } static now() { return fixed; } };
    });
    const page = await context.newPage();
    await page.route('**/api/**', r => r.fulfill({ json: new URL(r.request().url()).pathname === '/api/schedule' ? [] : { ok: true } }));
    await page.goto(base + '#/schedule');
    await page.waitForFunction(() => document.getElementById('prototype-screen')?.contentDocument?.querySelector('#live-calendar-root[aria-busy="false"]'));
    assert.equal(await page.frameLocator('#prototype-screen').locator('[data-cal-date]').inputValue(), expectedDay, 'Today must follow the browser timezone, including just after midnight');
    report.push({ timezoneId, expectedDay, passed: true });
    await context.close();
  }
  await mkdir('build/reports', { recursive: true });
  await writeFile('build/reports/calendar.json', JSON.stringify({ release: release.release, cases: report }, null, 2));
  console.log(JSON.stringify({ release: release.release, cases: report }, null, 2));
} finally { await browser.close(); await new Promise(resolve => server.close(resolve)); }
