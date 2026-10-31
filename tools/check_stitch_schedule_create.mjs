import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { createServer } from 'node:http';
import { readFile, mkdir, mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { extname, join, resolve, sep } from 'node:path';
import { createInterface } from 'node:readline';
import { createRequire } from 'node:module';
import { buildStitchWeb } from './build_stitch_web.mjs';

// Exercise browser -> authenticated FastAPI -> temporary SQLite -> browser.
// Even with --url, all business requests go to this isolated local backend.
const { chromium } = createRequire(import.meta.url)(process.env.PLAYWRIGHT_MODULE || 'playwright');
const release = await buildStitchWeb(process.env.STITCH_WEB_SOURCE ? { sourceRoot: process.env.STITCH_WEB_SOURCE } : {});
const temporary = await mkdtemp(join(tmpdir(), 'calendar-create-'));
const backend = spawn(process.env.PYTHON || 'python', ['-u', '-c', `
import socket, uvicorn
from backend.main import create_app
server_socket = socket.socket()
server_socket.bind(('127.0.0.1', 0))
print(server_socket.getsockname()[1], flush=True)
uvicorn.Server(uvicorn.Config(create_app(), log_level='error')).run(sockets=[server_socket])
`], { cwd: resolve('.'), env: { ...process.env, SHIXUZHIPEI_DB_PATH: join(temporary, 'calendar.sqlite3') }, stdio: ['ignore', 'pipe', 'pipe'] });
let diagnostics = '';
backend.stderr.on('data', bytes => { diagnostics = (diagnostics + bytes).slice(-4000); });
const staticServer = createServer(async (req, res) => {
  try {
    const pathname = new URL(req.url, 'http://localhost').pathname;
    const file = resolve(release.output, '.' + (pathname === '/' ? '/index.html' : pathname));
    assert.ok(file.startsWith(release.output + sep));
    const types = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.woff2': 'font/woff2' };
    res.setHeader('Content-Type', types[extname(file)] || 'application/octet-stream');
    res.end(await readFile(file));
  } catch { res.writeHead(404); res.end(); }
});
let browser;
const report = [];
const themes = [
  { tag: '方案评审', time: '09:00', color: 0xff163d3d, background: 'rgb(22, 61, 61)', foreground: 'rgb(129, 168, 167)' },
  { tag: '跨部门协同', time: '11:00', color: 0xff62a1fe, background: 'rgba(98, 161, 254, 0.4)', foreground: 'rgb(0, 55, 111)' },
  { tag: '架构编码', time: '13:00', color: 0xffe9e7ed, background: 'rgb(233, 231, 237)', foreground: 'rgb(26, 27, 31)' },
  { tag: '随笔调研', time: '15:00', color: 0xffefedf3, background: 'rgb(239, 237, 243)', foreground: 'rgb(26, 27, 31)' },
  { tag: '日常规程', time: '08:00', color: 0xffc2eae9, background: 'rgb(194, 234, 233)', foreground: 'rgb(39, 77, 77)' },
  { tag: '上课学习', time: '10:00', color: 0xffd6e3ff, background: 'rgb(214, 227, 255)', foreground: 'rgb(0, 70, 139)' },
  { tag: '作业自习', time: '12:00', color: 0xffede5f5, background: 'rgb(237, 229, 245)', foreground: 'rgb(81, 70, 95)' },
  { tag: '考试复习', time: '14:00', color: 0xfff5e6c8, background: 'rgb(245, 230, 200)', foreground: 'rgb(94, 73, 29)' },
  { tag: '工作会议', time: '16:00', color: 0xff62a1fe, background: 'rgba(98, 161, 254, 0.4)', foreground: 'rgb(0, 55, 111)' },
  { tag: '项目推进', time: '18:00', color: 0xff163d3d, background: 'rgb(22, 61, 61)', foreground: 'rgb(129, 168, 167)' },
  { tag: '运动休息', time: '20:00', color: 0xffe1eedf, background: 'rgb(225, 238, 223)', foreground: 'rgb(54, 88, 58)' },
];
try {
  const port = await new Promise((resolve, reject) => {
    const lines = createInterface({ input: backend.stdout });
    const timeout = setTimeout(() => reject(new Error('Backend startup timed out: ' + diagnostics)), 15000);
    backend.once('exit', () => { clearTimeout(timeout); reject(new Error('Backend exited: ' + diagnostics)); });
    lines.once('line', line => { clearTimeout(timeout); resolve(Number(line)); });
  });
  const api = `http://127.0.0.1:${port}`;
  const healthDeadline = Date.now() + 15000;
  while (true) {
    try { assert.equal((await (await fetch(api + '/health')).json()).ok, true); break; }
    catch (error) { if (Date.now() >= healthDeadline) throw error; await new Promise(resolve => setTimeout(resolve, 100)); }
  }
  await new Promise(resolve => staticServer.listen(0, '127.0.0.1', resolve));
  const base = process.argv.includes('--url') ? process.argv[process.argv.indexOf('--url') + 1] : `http://127.0.0.1:${staticServer.address().port}/`;
  browser = await chromium.launch({ headless: true });
  await mkdir('build/calendar-create-qa', { recursive: true });
  for (const mobile of [false, true]) {
    const registration = await fetch(api + '/auth/register', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ contactAddress: `${mobile ? 'mobile' : 'desktop'}@calendar-test.local`, displayName: '日历验证', password: 'isolated-test-only' }) });
    assert.equal(registration.status, 200);
    const login = await registration.json();
    const context = await browser.newContext({ viewport: mobile ? { width: 390, height: 844 } : { width: 1440, height: 1000 }, timezoneId: 'Asia/Shanghai', reducedMotion: 'reduce' });
    await context.addInitScript(login => {
      window.__RUANCHUANG_API__ = location.origin + '/api';
      localStorage.setItem('access_token', login.accessToken);
      localStorage.setItem('ruanchuang_user', JSON.stringify(login.user));
    }, login);
    const page = await context.newPage(), errors = [];
    page.on('pageerror', error => errors.push(error.message));
    await page.route('**/api/**', async route => {
      const req = route.request(), url = new URL(req.url());
      const response = await fetch(api + url.pathname.slice('/api'.length) + url.search, {
        method: req.method(), headers: { 'Content-Type': 'application/json', ...(req.headers().authorization ? { Authorization: req.headers().authorization } : {}) },
        ...(['GET', 'HEAD'].includes(req.method()) ? {} : { body: req.postDataBuffer() }),
      });
      await route.fulfill({ status: response.status, contentType: response.headers.get('content-type') || 'application/json', body: Buffer.from(await response.arrayBuffer()) });
    });
    const frame = () => page.frameLocator('#prototype-screen');
    const ready = route => page.waitForFunction(route => document.getElementById('prototype-screen')?.title === `时序智配 ${route}`, route);
    const settled = () => page.waitForFunction(() => document.getElementById('prototype-screen')?.contentDocument?.querySelector('#live-calendar-root[aria-busy="false"]'));
    const readRecords = async () => {
      const response = await fetch(api + '/schedule', { headers: { Authorization: `Bearer ${login.accessToken}` } });
      assert.equal(response.status, 200); return response.json();
    };
    await page.goto(base + '#/schedule'); await ready('schedule'); await settled();
    await frame().locator('[data-cal-date]').fill('2026-11-05'); await settled();
    for (const theme of themes) {
      await frame().getByRole('button', { name: mobile ? '新增日程' : /新增普通日程/, exact: mobile }).click(); await ready('create-schedule');
      assert.equal(await frame().locator('#tagGroup button').count(), themes.length);
      assert.equal(await frame().locator('#tagGroup').evaluate(n => n.scrollWidth <= n.clientWidth), true, 'All tags must wrap instead of being hidden horizontally');
      await frame().locator('#schedule-title-input').fill(theme.tag + ' <真实新增日程>');
      await frame().locator('#tagGroup button').filter({ hasText: theme.tag }).click();
      assert.equal(await frame().locator('#tagGroup [aria-pressed="true"]').count(), 1);
      const selectedTag = frame().locator('#tagGroup .active-tag');
      assert.equal(await selectedTag.evaluate(n => getComputedStyle(n).backgroundColor), theme.background, 'Selected tag and calendar card must share their theme');
      if (theme.tag === '上课学习') await page.screenshot({ path: `build/calendar-create-qa/${mobile ? 'mobile' : 'desktop'}-tag-picker.png` });
      await frame().getByRole('button', { name: '选择开始时间', exact: true }).click();
      const picker = frame().locator('#import-time-picker');
      await picker.waitFor({ state: 'visible' });
      await picker.getByRole('option', { name: theme.time.slice(0, 2) + '时', exact: true }).click();
      await picker.getByRole('option', { name: '00分', exact: true }).click();
      if (theme.tag === '上课学习') await page.screenshot({ path: `build/calendar-create-qa/${mobile ? 'mobile' : 'desktop'}-time-picker.png` });
      await picker.getByRole('button', { name: '确定时间', exact: true }).click();
      assert.equal(await frame().locator('#schedule-time-input').inputValue(), theme.time);
      await frame().locator('#schedule-duration-input').fill('90');
      assert.equal(await frame().locator('#tagGroup .active-tag').innerText(), theme.tag, 'Visible tag and submitted tag must agree');
      await frame().getByRole('button', { name: /保存并写入日程/ }).click(); await ready('schedule'); await settled();
      const records = await readRecords(), item = records.find(item => item.title === theme.tag + ' <真实新增日程>');
      assert.ok(item, 'Saved schedule must exist in the real backend');
      assert.equal(item.tag, theme.tag); assert.equal(item.day, '2026-11-05');
      assert.equal(item.color, theme.color, 'Creation must persist the original theme color');
      assert.equal(Math.round(item.height * 60 / 80), 90);
      assert.deepEqual(item.time, { hour: Number(theme.time.slice(0, 2)), minute: 0 });
      const card = frame().locator(`[data-schedule-id="${item.id}"]`).first();
      assert.ok(await card.count()); assert.match(await card.innerText(), /真实新增日程/);
      theme[mobile ? 'mobileId' : 'desktopId'] = item.id;
    }
    await page.reload(); await ready('schedule'); await settled();
    await frame().locator('[data-cal-date]').fill('2026-11-05'); await settled();
    for (const view of ['day', 'week', 'gantt', 'month']) {
      await frame().locator(`[data-cal-action="${view}"]`).click(); await settled();
      for (const theme of themes) {
        const id = theme[mobile ? 'mobileId' : 'desktopId'];
        const card = frame().locator(`${view === 'gantt' ? '.cal-gantt-bar' : ''}[data-schedule-id="${id}"]`).first();
        if (view === 'month' && !await card.count()) {
          assert.equal(await frame().locator('[data-calendar-day="2026-11-05"] [data-cal-open-day]').textContent(), `另 ${themes.length - 3} 项`);
          continue;
        }
        assert.ok(await card.count(), `${theme.tag}: reloaded ${view} must display the saved entry`);
        const style = await card.evaluate(node => { const s = getComputedStyle(node); return { background: s.backgroundColor, foreground: s.color, radius: s.borderRadius }; });
        assert.equal(style.background, theme.background, `${theme.tag}: ${view} must use the original demo background`);
        if (view !== 'gantt') assert.equal(style.foreground, theme.foreground, `${theme.tag}: ${view} must use the matching foreground`);
        if (!mobile && view === 'day') {
          const position = await card.evaluate(node => ({ top: parseFloat(node.parentElement.style.top), height: parseFloat(node.parentElement.style.height) }));
          assert.equal(position.top, (Number(theme.time.slice(0, 2)) - 8) * 60); assert.equal(position.height, 90);
        }
      }
      await page.screenshot({ path: `build/calendar-create-qa/${mobile ? 'mobile' : 'desktop'}-${view}.png` });
    }
    await frame().locator('[data-calendar-day="2026-11-05"] [data-cal-open-day]').click(); await settled();
    assert.equal(await frame().locator('#live-calendar-root').getAttribute('data-calendar-view'), 'day');
    assert.ok(await frame().locator(`[data-schedule-id="${themes[3][mobile ? 'mobileId' : 'desktopId']}"]`).count());
    const first = themes[0][mobile ? 'mobileId' : 'desktopId'];
    await frame().locator(`[data-schedule-id="${first}"]`).click(); await ready('schedule-detail');
    await frame().locator('#detailTitle').waitFor({ state: 'visible' });
    assert.equal(await frame().locator('#detailTag').textContent(), themes[0].tag);
    assert.equal(await frame().locator('#detailStartTime').textContent(), themes[0].time);
    await frame().locator('#editBtn').click(); await ready('create-schedule'); await page.waitForFunction(() => document.getElementById('prototype-screen')?.contentDocument?.documentElement.dataset.scheduleReady === 'true'); await frame().locator('#schedule-title-input').fill('修改后保持主题');
    await frame().locator('#schedule-save-action').click(); await ready('schedule'); await settled();
    assert.equal((await readRecords()).find(item => item.id === first).color, themes[0].color);
    assert.equal(await frame().locator(`[data-schedule-id="${first}"]`).evaluate(n => getComputedStyle(n).backgroundColor), themes[0].background);
    const records = await readRecords(); assert.equal(records.length, themes.length, 'Each save must create exactly one entry');
    for (const item of records) assert.equal((await fetch(api + '/schedule/' + item.id, { method: 'DELETE', headers: { Authorization: `Bearer ${login.accessToken}` } })).status, 204);
    assert.deepEqual(await readRecords(), []); assert.deepEqual(errors, []);
    report.push({ viewport: mobile ? 'mobile' : 'desktop', passed: true, backend: 'FastAPI + isolated SQLite', created: themes.length, checks: ['real-add-button', 'all-student-and-work-tags', 'tag-selection', 'wrapped-picker-and-shared-theme', 'persisted-fields-and-color', 'reload-persistence', 'day-week-month', 'demo-theme-colors', 'time-position', 'detail-and-edit', 'no-duplicate-writes'] });
    await context.close();
  }
  await mkdir('build/reports', { recursive: true });
  await writeFile('build/reports/calendar-create.json', JSON.stringify({ release: release.release, cases: report }, null, 2));
  console.log(JSON.stringify({ release: release.release, cases: report }, null, 2));
} finally {
  await browser?.close();
  if (staticServer.listening) await new Promise(resolve => staticServer.close(resolve));
  const closed = new Promise(resolve => backend.once('exit', resolve));
  if (backend.exitCode === null) { backend.kill(); await closed; }
  await rm(temporary, { recursive: true, force: true });
}
