import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { createServer } from 'node:http';
import { readFile, mkdir, mkdtemp, rm, writeFile, access } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { extname, join, resolve, sep } from 'node:path';
import { createInterface } from 'node:readline';
import { createRequire } from 'node:module';
import { buildStitchWeb } from './build_stitch_web.mjs';

const require = createRequire(import.meta.url);
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const XLSX = require('../web/stitch/assets/vendor/xlsx.full.min.js');
const release = await buildStitchWeb(process.env.STITCH_WEB_SOURCE ? { sourceRoot: process.env.STITCH_WEB_SOURCE } : {});
const temporary = await mkdtemp(join(tmpdir(), 'calendar-import-'));
const backend = spawn(process.env.PYTHON || 'python', ['-u', '-c', `
import socket, uvicorn
from backend.main import create_app
sock = socket.socket(); sock.bind(('127.0.0.1', 0))
print(sock.getsockname()[1], flush=True)
uvicorn.Server(uvicorn.Config(create_app(${JSON.stringify(join(temporary, 'test.sqlite3'))}), log_level='warning')).run(sockets=[sock])
`], { stdio: ['ignore', 'pipe', 'pipe'] });
let diagnostics = '';
backend.stderr.on('data', bytes => { diagnostics = (diagnostics + bytes).slice(-4000); });
const staticServer = createServer(async (req, res) => {
  try {
    const pathname = new URL(req.url, 'http://localhost').pathname;
    const file = resolve(release.output, '.' + (pathname === '/' ? '/index.html' : pathname));
    assert.ok(file.startsWith(release.output + sep));
    res.setHeader('Content-Type', ({ '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.woff2': 'font/woff2' })[extname(file)] || 'application/octet-stream');
    res.end(await readFile(file));
  } catch { res.writeHead(404); res.end(); }
});
const output = 'build/calendar-import-qa', report = [];
let browser;
try {
  const port = await new Promise((resolvePort, reject) => {
    const timeout = setTimeout(() => reject(new Error('Backend startup timed out: ' + diagnostics)), 15000);
    createInterface({ input: backend.stdout }).once('line', line => { clearTimeout(timeout); resolvePort(Number(line)); });
    backend.once('exit', () => { clearTimeout(timeout); reject(new Error('Backend exited: ' + diagnostics)); });
  });
  const api = `http://127.0.0.1:${port}`;
  const deadline = Date.now() + 15000;
  while (true) {
    try { assert.equal((await (await fetch(api + '/health')).json()).ok, true); break; }
    catch (error) { if (Date.now() >= deadline) throw error; await new Promise(resolve => setTimeout(resolve, 100)); }
  }
  await new Promise(resolve => staticServer.listen(0, '127.0.0.1', resolve));
  const base = `http://127.0.0.1:${staticServer.address().port}/`;
  browser = await chromium.launch({ headless: true, ...(process.env.PLAYWRIGHT_CHANNEL ? { channel: process.env.PLAYWRIGHT_CHANNEL } : {}) }); await mkdir(output, { recursive: true });
  const supplied = 'C:/Users/33827/Desktop/学生个人课表_8208240318.xls';
  const hasSample = await access(supplied).then(() => true, () => false);
  const csv = Buffer.from('\ufeff标题,日期,开始时间,结束时间,标签,备注,地点\n"导入课程,复习",2026-09-07,09:00,10:30,上课学习,王老师,B座507\n错误行,2026-02-30,09:00,10:00,日程,,');
  for (const mobile of [false, true]) {
    const registration = await fetch(api + '/auth/register', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ contactAddress: `${mobile ? 'mobile' : 'desktop'}@import.test`, displayName: '导入测试', password: 'isolated-import-only' }) });
    assert.equal(registration.status, 200); const login = await registration.json();
    const context = await browser.newContext({ viewport: mobile ? { width: 390, height: 844 } : { width: 1440, height: 1000 }, timezoneId: 'Asia/Shanghai', reducedMotion: 'reduce' });
    await context.addInitScript(login => {
      window.__RUANCHUANG_API__ = location.origin + '/api'; localStorage.setItem('access_token', login.accessToken); localStorage.setItem('ruanchuang_user', JSON.stringify(login.user));
    }, login);
    const page = await context.newPage(), errors = [], writes = [];
    page.on('pageerror', error => errors.push(error.message));
    await page.route('**/api/**', async route => {
      const req = route.request(), url = new URL(req.url());
      if (req.method() !== 'GET') writes.push(url.pathname + url.search);
      const response = await fetch(api + url.pathname.slice('/api'.length) + url.search, {
        method: req.method(), headers: { 'Content-Type': 'application/json', ...(req.headers().authorization ? { Authorization: req.headers().authorization } : {}) },
        ...(['GET', 'HEAD'].includes(req.method()) ? {} : { body: req.postDataBuffer() }),
      });
      await route.fulfill({ status: response.status, contentType: response.headers.get('content-type') || 'application/json', body: Buffer.from(await response.arrayBuffer()) });
    });
    const frame = () => page.frameLocator('#prototype-screen');
    const ready = route => page.waitForFunction(route => document.getElementById('prototype-screen')?.title === `时序智配 ${route}`, route);
    const settled = () => page.waitForFunction(() => document.getElementById('prototype-screen')?.contentDocument?.querySelector('#live-calendar-root[aria-busy="false"]'));
    const previewReady = () => frame().locator('#import-status').filter({ hasText: /已生成/ }).waitFor();
    const readRecords = async () => (await fetch(api + '/schedule', { headers: { Authorization: `Bearer ${login.accessToken}` } })).json();
    const open = async () => {
      assert.equal(await frame().getByRole('button', { name: '导入日程', exact: true }).count(), 0);
      await frame().locator('[data-cal-action="create"]').first().click(); await ready('create-schedule');
      await frame().locator('#schedule-title-input').fill('保留未提交的草稿');
      await frame().getByRole('button', { name: '导入日程', exact: true }).click(); await ready('calendar-import');
    };
    const cancel = async () => {
      await frame().locator('#import-cancel').click(); await ready('create-schedule');
      assert.equal(await frame().locator('#schedule-title-input').inputValue(), '保留未提交的草稿');
      await frame().locator('[data-drawer-close]').click(); await ready('schedule'); await settled();
    };
    const selectFile = async (name, buffer) => { await frame().locator('#import-file').setInputFiles({ name, mimeType: 'application/octet-stream', buffer: Buffer.from(buffer) }); await previewReady(); };
    await page.goto(base + '#/schedule'); await ready('schedule'); await settled();
    await frame().locator('[data-cal-date]').fill('2026-09-07'); await settled();
    const calendarFrame = page.frames().find(f => f.url().includes('smart-calendar') || f.url().includes('mobile/schedule'));
    const calendarNode = await calendarFrame.evaluate(() => { window.__importRetainedCalendar = document.querySelector('#live-calendar-root'); return true; }); assert.equal(calendarNode, true);
    await open(); await selectFile('sample.csv', csv);
    assert.equal(await frame().locator('#import-file-name').textContent(), 'sample.csv');
    assert.equal(await frame().locator('#import-file-action').textContent(), '更换文件');
    assert.equal(writes.length, 0, 'Selecting and previewing must not write');
    assert.match(await frame().locator('#import-errors').textContent(), /1 行未导入/);
    assert.match(await frame().locator('#import-preview').textContent(), /王老师 · B座507/);
    await cancel();
    assert.deepEqual(await readRecords(), []);
    await open(); await selectFile('sample.csv', csv);
    assert.equal(await frame().locator('#import-confirm').isEnabled(), true);
    await page.screenshot({ path: `${output}/${mobile ? 'mobile' : 'desktop'}-preview.png` });
    await frame().locator('#import-confirm').click(); await ready('schedule'); await settled();
    let records = await readRecords(); assert.equal(records.length, 1); const imported = records[0];
    assert.equal(imported.height, 120); assert.equal(imported.description, '王老师 · B座507'); assert.equal(imported.color, 0xffd6e3ff);
    assert.equal(writes.length, 1); assert.equal(writes[0], '/api/schedule/batch?createOnly=true');
    assert.equal(await calendarFrame.evaluate(() => window.__importRetainedCalendar === document.querySelector('#live-calendar-root')), true);
    for (const view of ['day', 'week', 'month', 'gantt']) {
      await frame().locator(`[data-cal-action="${view}"]`).click(); await settled();
      await frame().locator(`[data-calendar-event="${imported.id}"]`).first().waitFor({ state: 'visible' });
      const card = frame().locator(`[data-calendar-event="${imported.id}"]`).first();
      assert.match(await card.getAttribute('aria-label'), /教室：B座507/);
      assert.match(await card.textContent(), /B座507/);
      if (view !== 'gantt') await card.locator('.cal-event-location').waitFor({ state: 'visible' });
      if (view === 'week') await page.screenshot({ path: `${output}/${mobile ? 'mobile' : 'desktop'}-classroom.png` });
    }
    await frame().locator('[data-cal-action="week"]').click(); await settled();
    await frame().locator(`[data-calendar-event="${imported.id}"]`).first().click(); await ready('schedule-detail');
    await frame().locator('#detailDescription').waitFor({ state: 'visible' }); assert.equal(await frame().locator('#detailDescription').textContent(), imported.description);
    await frame().locator('#editBtn').click(); await ready('create-schedule');
    await page.waitForFunction(() => document.getElementById('prototype-screen')?.contentDocument?.documentElement.dataset.scheduleReady === 'true');
    assert.equal(await frame().locator('#schedule-import-action').isHidden(), true);
    await frame().locator('#schedule-title-input').fill('用户已编辑'); await frame().locator('#schedule-description-input').fill('保留修改');
    await frame().locator('#schedule-save-action').click(); await ready('schedule'); await settled();
    await open(); await selectFile('sample.csv', csv);
    assert.equal(await frame().locator('#import-confirm').isDisabled(), true);
    assert.match(await frame().locator('#import-preview').textContent(), /已导入/);
    await cancel();
    assert.equal((await readRecords())[0].description, '保留修改');
    for (const [name, buffer] of [
      ['records.json', Buffer.from(JSON.stringify([{ title: 'JSON 日程', date: '2026-09-07', start: '11:00', duration: 60, note: 'JSON备注' }]))],
      ['calendar.ics', Buffer.from('BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nUID:ics-check\r\nDTSTART:20260907T130000\r\nDTEND:20260907T143000\r\nSUMMARY:ICS 日程\r\nDESCRIPTION:ICS备注\r\nEND:VEVENT\r\nEND:VCALENDAR')],
      ['records.tsv', Buffer.from('标题\t日期\t开始时间\t时长\nTSV 日程\t2026-09-07\t16:00\t30')],
    ]) {
      await open(); await selectFile(name, buffer); await frame().locator('#import-confirm').click(); await ready('schedule'); await settled();
    }
    const book = XLSX.utils.book_new();
    XLSX.utils.book_append_sheet(book, XLSX.utils.aoa_to_sheet([['标题', '日期', '开始时间', '结束时间'], ['Excel 日程', new Date(2026, 8, 7), '17:00', '18:00']]), '日程');
    await open(); await selectFile('schedules.xlsx', XLSX.write(book, { bookType: 'xlsx', type: 'buffer' }));
    await frame().locator('#import-confirm').click(); await ready('schedule'); await settled();
    if (hasSample) {
      await open();
      const chooser = page.waitForEvent('filechooser');
      await frame().locator('#import-file-button').click(); await (await chooser).setFiles(supplied);
      await frame().locator('#import-course-options').waitFor({ state: 'visible' });
      assert.equal(await frame().locator('#import-confirm').isDisabled(), true);
      assert.match(await frame().locator('#import-course-summary').textContent(), /12 条/);
      await frame().locator('#import-first-monday').fill('2026-09-07');
      for (const [sections, start, end] of [['3-4', '10:00', '11:30'], ['5-6', '14:00', '15:30'], ['7-8', '16:00', '17:30'], ['9-10', '19:00', '20:30']]) {
        await frame().locator(`[data-sections="${sections}"] [data-kind="start"]`).fill(start);
        await frame().locator(`[data-sections="${sections}"] [data-kind="end"]`).fill(end);
      }
      const timeInput = frame().locator('[data-sections="3-4"] [data-kind="start"]');
      const timeButton = frame().getByRole('button', { name: '选择第 3-4 节开始时间', exact: true });
      await timeButton.click();
      const picker = frame().locator('#import-time-picker'); await picker.waitFor({ state: 'visible' });
      assert.equal(await picker.evaluate(node => Boolean(node.closest('[data-drawer-panel]'))), true);
      await picker.getByRole('button', { name: '确定时间', exact: true }).focus();
      await page.keyboard.press('Tab');
      assert.equal(await picker.getByRole('listbox', { name: '小时', exact: true }).evaluate(node => node === node.ownerDocument.activeElement), true);
      await page.keyboard.press('Shift+Tab');
      assert.equal(await picker.getByRole('button', { name: '确定时间', exact: true }).evaluate(node => node === node.ownerDocument.activeElement), true);
      await picker.getByRole('option', { name: '10时', exact: true }).click();
      await picker.getByRole('option', { name: '00分', exact: true }).click();
      await page.screenshot({ path: `${output}/${mobile ? 'mobile' : 'desktop'}-time-picker.png` });
      const pickerBox = await picker.boundingBox();
      assert.ok(pickerBox.x >= 0 && pickerBox.y >= 0 && pickerBox.x + pickerBox.width <= (mobile ? 390 : 1440) + 1);
      await picker.getByRole('button', { name: '确定时间', exact: true }).click();
      assert.equal(await timeInput.inputValue(), '10:00');
      await timeButton.click();
      await picker.getByRole('option', { name: '11时', exact: true }).click();
      await page.keyboard.press('Escape');
      await picker.waitFor({ state: 'hidden' }); await ready('calendar-import');
      assert.equal(await timeInput.inputValue(), '10:00', 'Escape closes only the picker without committing');
      await timeInput.focus(); await page.keyboard.press('ArrowDown');
      await picker.waitFor({ state: 'visible' }); await page.keyboard.press('ArrowUp'); await page.keyboard.press('Enter');
      assert.equal(await timeInput.inputValue(), '09:00', 'Picker supports keyboard selection');
      await timeInput.fill('10:00');
      await frame().locator('#import-course-preview').click(); await previewReady();
      assert.match(await frame().locator('#import-count').textContent(), /108 条日程/);
      assert.match(await frame().locator('#import-course-warnings').textContent(), /课程设计/);
      await page.screenshot({ path: `${output}/${mobile ? 'mobile' : 'desktop'}-course-preview.png` });
      await frame().locator('#import-confirm').click(); await ready('schedule'); await settled();
      records = await readRecords(); assert.equal(records.length, 113);
      const course = records.find(row => row.title === '多模态数据处理与应用' && row.day === '2026-09-07');
      assert.equal(course.description, '王磊(副教授) · B座507'); assert.equal(course.height, 120);
    }
    await page.reload(); await ready('schedule'); await settled();
    assert.equal((await readRecords())[0] != null, true);
    assert.equal((await readRecords()).find(row => row.id === imported.id).description, '保留修改');
    assert.deepEqual(errors, []);
    report.push({ viewport: mobile ? 'mobile' : 'desktop', passed: true, realXls: hasSample, records: (await readRecords()).length, checks: ['local-file-preview', 'cancel-no-write', 'bad-row-warning', 'atomic-confirm', 'retained-calendar', 'day-week-month-gantt', 'theme-color', 'notes-edit-persist', 'duplicates-skip', 'csv-tsv-json-ics-xlsx', 'xls-course-week-expansion', 'reload'] });
    await context.close();
  }
  await writeFile(`${output}/report.json`, JSON.stringify({ release: release.release, cases: report }, null, 2));
  console.log(JSON.stringify({ release: release.release, cases: report }, null, 2));
} finally {
  await browser?.close();
  if (staticServer.listening) await new Promise(resolve => staticServer.close(resolve));
  const closed = new Promise(resolve => backend.once('exit', resolve));
  if (backend.exitCode === null) { backend.kill(); await closed; }
  await rm(temporary, { recursive: true, force: true });
}
