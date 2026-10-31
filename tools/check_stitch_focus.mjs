// Browser verification for the live focus workbench (stitch/focus.js).
//
// Serves a freshly built stitch-web release with stubbed /api endpoints and
// asserts that the four metric cards and the pomodoro card show real data:
// current-task display, upcoming preview, manual early start moving the
// calendar slot (PUT /schedule/:id), and the mobile layout.
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { extname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';

import { buildStitchWeb } from './build_stitch_web.mjs';

const require = createRequire(import.meta.url);
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const root = fileURLToPath(new URL('..', import.meta.url));
const pad = (n) => String(n).padStart(2, '0');
const dateKey = (date) => `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;

const build = await buildStitchWeb();
const output = build.output;
const mime = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.png': 'image/png', '.woff2': 'font/woff2', '.ttf': 'font/ttf', '.json': 'application/json' };

const minuteOf = (date) => ({ hour: date.getHours(), minute: date.getMinutes() });
const now = new Date();
const today = dateKey(now);

// One entry inside its window (current) and one starting in ten minutes
// (upcoming; the early-start scenario moves this one).
const currentEntry = {
  id: 'sch_current', title: '编写双写一致性降级回滚补丁', tag: 'Deep Work', load: null,
  day: today, height: 80, color: 0, repeat: 'none',
  time: minuteOf(new Date(now.getTime() - 10 * 60000)),
};
const upcomingEntry = {
  id: 'sch_upcoming', title: '预发布环境灰度放量观测', tag: 'Routine', load: 'medium',
  day: today, height: 40, color: 0, repeat: 'none',
  time: minuteOf(new Date(now.getTime() + 55 * 60000)),
};
const laterEntry = {
  id: 'sch_later', title: '算法调度模型回归复盘', tag: 'Goal', load: 'low',
  day: today, height: 80, color: 0, repeat: 'none',
  time: minuteOf(new Date(now.getTime() + 120 * 60000)),
};

let putCalls = [];
let eventCalls = [];
const server = createServer(async (request, response) => {
  const url = new URL(request.url, 'http://localhost');
  try {
    if (url.pathname === '/api/schedule' && request.method === 'GET') {
      response.writeHead(200, { 'Content-Type': 'application/json' });
      response.end(JSON.stringify([currentEntry, upcomingEntry, laterEntry]));
      return;
    }
    if (url.pathname.startsWith('/api/schedule/') && request.method === 'PUT') {
      let body = '';
      for await (const chunk of request) body += chunk;
      putCalls.push(JSON.parse(body));
      response.writeHead(200, { 'Content-Type': 'application/json' });
      response.end(body);
      return;
    }
    if (url.pathname === '/api/events' && request.method === 'GET') {
      response.writeHead(200, { 'Content-Type': 'application/json' });
      response.end(JSON.stringify([]));
      return;
    }
    if (url.pathname === '/api/events' && request.method === 'POST') {
      let body = '';
      for await (const chunk of request) body += chunk;
      eventCalls.push(JSON.parse(body));
      response.writeHead(200, { 'Content-Type': 'application/json' });
      response.end(body);
      return;
    }
    if (url.pathname === '/api/energy/current') {
      response.writeHead(200, { 'Content-Type': 'application/json' });
      response.end(JSON.stringify({ level: 'high', status: '高效', description: '根据情绪打卡记录推算', batteryPercent: 75, emotion: 'efficient', flowState: 'flow' }));
      return;
    }
    if (url.pathname === '/api/emotion/current') {
      response.writeHead(200, { 'Content-Type': 'application/json' });
      response.end(JSON.stringify({ state: 'efficient' }));
      return;
    }
    if (url.pathname === '/api/health') {
      response.writeHead(200, { 'Content-Type': 'application/json' });
      response.end('{"status":"ok"}');
      return;
    }
    let path = url.pathname === '/' ? '/index.html' : url.pathname;
    const file = join(output, path.replace(/^\/api/, ''));
    response.writeHead(200, { 'Content-Type': mime[extname(file)] || 'application/octet-stream' });
    response.end(await readFile(file));
  } catch {
    response.writeHead(404);
    response.end();
  }
});
await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
const base = `http://127.0.0.1:${server.address().port}/`;

const browser = await chromium.launch({ headless: true });
try {
  // Desktop: the current task drives the pomodoro card.
  const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
  // Point the router at the stubbed API on this origin (localhost would
  // otherwise hard-code http://127.0.0.1:8000).
  await page.addInitScript(() => { window.__RUANCHUANG_API__ = '/api'; });
  await page.goto(new URL('#/focus', base).href);
  const frame = page.frameLocator('#prototype-screen');
  await frame.locator('#focus-task-title').filter({ hasText: '编写双写一致性降级回滚补丁' }).waitFor({ timeout: 15000 });

  const desktop = await frame.locator('body').evaluate(() => ({
    current: document.getElementById('focus-stat-current')?.textContent,
    currentSub: document.getElementById('focus-stat-current-sub')?.textContent,
    energy: document.getElementById('focus-stat-energy')?.textContent,
    energySub: document.getElementById('focus-stat-energy-sub')?.textContent,
    next: document.getElementById('focus-stat-next')?.textContent,
    nextSub: document.getElementById('focus-stat-next-sub')?.textContent,
    conflict: document.getElementById('focus-stat-conflict')?.textContent,
    load: document.getElementById('focus-load-chip')?.textContent.trim(),
    loadDot: !!document.querySelector('#focus-load-chip .rounded-full'),
    tag: document.getElementById('focus-tag-chip')?.textContent.trim(),
    range: document.getElementById('focus-time-range')?.textContent,
    remaining: document.getElementById('focus-remaining-label')?.textContent,
    status: document.getElementById('focus-timer-status')?.textContent,
    headerEnergy: document.getElementById('focus-header-energy')?.textContent,
    demoChips: document.body.textContent.includes('P0 关键攻坚'),
    finishHidden: document.querySelector('[data-focus-action="finish"]')?.hidden,
    modeButtons: [...document.querySelectorAll('[data-focus-mode]')].map((b) => b.dataset.focusMode),
    selectedMode: document.querySelector('[data-focus-mode].bg-primary, [data-focus-mode].bg-surface-container-lowest')?.dataset.focusMode,
    legacyInlineTimer: [...document.querySelectorAll('script:not([src])')]
      .some((script) => script.textContent.includes('toggle-timer-btn') || script.textContent.includes("23 * 60")),
  }));
  assert.equal(desktop.demoChips, false, 'hardcoded P0 demo chip must be gone');
  assert.match(desktop.current, /^\d+:\d\d(:\d\d)?$/, 'countdown shows the current task remaining time');
  assert.equal(desktop.currentSub, '编写双写一致性降级回滚补丁');
  assert.equal(desktop.energy, '75%');
  assert.equal(desktop.energySub, '当前情绪：高效');
  assert.equal(desktop.next, '2');
  assert.equal(desktop.nextSub, '预发布环境灰度放量观测');
  assert.equal(desktop.conflict, '0');
  assert.equal(desktop.load, '负荷 高');
  assert.equal(desktop.loadDot, true, 'load chip leads with a dot');
  assert.equal(desktop.tag, '深度工作');
  assert.match(desktop.range, /^\d{2}:\d{2} - \d{2}:\d{2}$/);
  assert.match(desktop.remaining, /^剩余 /);
  // The in-window task auto-starts on load: the pomodoro is already running.
  assert.equal(desktop.status, '专注状态中');
  assert.ok(eventCalls.some((event) => event.type === 'start' && event.taskId === 'sch_current'),
    'auto-start logs one start event for the in-window task');
  assert.equal(desktop.headerEnergy, '能量 75 分');
  assert.equal(desktop.finishHidden, false);
  assert.deepEqual(desktop.modeButtons, ['flow', 'pomodoro', 'deep']);
  assert.equal(desktop.selectedMode, 'pomodoro', 'classic pomodoro is the default mode');
  assert.equal(desktop.legacyInlineTimer, false, 'the old demo inline timer script must stay removed');
  console.log('desktop focus hydration OK');

  // Manual early start on the upcoming task moves its calendar slot.
  const beforeClick = new Date();
  await frame.locator('#focus-task-title').filter({ hasText: '编写双写一致性降级回滚补丁' }).waitFor();
  // The current task owns the card; finish it so the upcoming task takes over.
  await frame.locator('[data-focus-action="finish"]').click();
  await frame.locator('#focus-task-title').filter({ hasText: '预发布环境灰度放量观测' }).waitFor({ timeout: 15000 });
  const preview = await frame.locator('body').evaluate(() => ({
    display: document.getElementById('focus-timer-display')?.textContent,
    status: document.getElementById('focus-timer-status')?.textContent,
    remaining: document.getElementById('focus-remaining-label')?.textContent,
    finishHidden: document.querySelector('[data-focus-action="finish"]')?.hidden,
  }));
  assert.equal(preview.display, '30:00', 'pomodoro countdown matches the task duration, not a fixed 25m');
  assert.equal(preview.status, '到点自动开始');
  assert.match(preview.remaining, /^计划 /);
  assert.equal(preview.finishHidden, true);

  await frame.locator('[data-focus-action="toggle"]').click();
  await frame.locator('#focus-task-title').filter({ hasText: '预发布环境灰度放量观测' }).waitFor();
  await page.waitForTimeout(400);
  assert.equal(putCalls.length, 1, 'manual start must move the calendar entry once');
  assert.equal(putCalls[0].id, 'sch_upcoming');
  assert.equal(putCalls[0].time.hour, beforeClick.getHours());
  assert.ok(Math.abs(putCalls[0].time.minute - beforeClick.getMinutes()) <= 1, 'moved start time is now');
  const started = await frame.locator('body').evaluate(() => ({
    status: document.getElementById('focus-timer-status')?.textContent,
  }));
  assert.equal(started.status, '专注状态中');
  assert.ok(eventCalls.some((event) => event.type === 'start' && event.taskId === 'sch_upcoming'), 'start event logged');
  console.log('manual early start + calendar move OK');

  // Switching to another page and back must NOT terminate the running timer.
  const beforeSwitch = await frame.locator('#focus-timer-display').textContent();
  await page.goto(new URL('#/schedule', base).href);
  await page.waitForTimeout(600);
  await page.goto(new URL('#/focus', base).href);
  await page.waitForTimeout(2500);
  const afterSwitch = await frame.locator('body').evaluate(() => ({
    display: document.getElementById('focus-timer-display')?.textContent,
    status: document.getElementById('focus-timer-status')?.textContent,
    title: document.getElementById('focus-task-title')?.textContent,
  }));
  assert.equal(afterSwitch.status, '专注状态中', 'session keeps running after page switch');
  assert.equal(afterSwitch.title, '预发布环境灰度放量观测');
  assert.notEqual(afterSwitch.display, '25:00', 'countdown continued from the wall clock instead of resetting');
  assert.ok(beforeSwitch.startsWith('30:') || beforeSwitch.startsWith('29:'), 'sanity: countdown started from the task duration');
  console.log('page-switch session persistence OK');

  // 沉浸 mode = do-not-disturb: silent session with an explicit off notice.
  await frame.locator('[data-focus-action="finish"]').click();
  await frame.locator('#focus-task-title').filter({ hasText: '算法调度模型回归复盘' }).waitFor({ timeout: 15000 });
  await frame.locator('[data-focus-mode="deep"]').click();
  await frame.locator('[data-focus-action="toggle"]').click();
  await page.waitForTimeout(500);
  const dndState = await frame.locator('body').evaluate(() => ({
    status: document.getElementById('focus-timer-status')?.textContent,
  }));
  assert.equal(dndState.status, '勿扰专注中');
  assert.ok(eventCalls.some((event) => event.type === 'start' && event.taskId === 'sch_later'), 'deep session start logged');
  await frame.locator('[data-focus-action="finish"]').click();
  await page.waitForTimeout(400);
  const dndOffNotice = await frame.locator('body').evaluate(
    () => document.getElementById('stitch-router-notice')?.textContent,
  );
  assert.equal(dndOffNotice, '勿扰模式已关闭，通知已恢复。', 'DND off notice must surface after the session ends');
  console.log('do-not-disturb mode OK');

  await page.close();

  // Mobile layout hydrates with the same module.
  const mobile = await browser.newPage({ viewport: { width: 390, height: 844 } });
  await mobile.addInitScript(() => { window.__RUANCHUANG_API__ = '/api'; });
  await mobile.goto(new URL('#/focus', base).href);
  const mobileFrame = mobile.frameLocator('#prototype-screen');
  await mobileFrame.locator('#focus-task-title').filter({ hasText: '编写双写一致性降级回滚补丁' }).waitFor({ timeout: 15000 });
  const mobileState = await mobileFrame.locator('body').evaluate(() => ({
    energyTitle: document.getElementById('focus-energy-title')?.textContent,
    date: document.getElementById('focus-date-label')?.textContent,
    demo: document.body.textContent.includes('#Ruanchuang-Core') || document.body.textContent.includes('深度心流指数'),
    modeButtons: [...document.querySelectorAll('[data-focus-mode]')].map((b) => b.dataset.focusMode),
  }));
  assert.equal(mobileState.demo, false, 'mobile demo markers must be gone');
  assert.deepEqual(mobileState.modeButtons, ['flow', 'pomodoro', 'deep'], 'real timer mode switcher present');
  assert.equal(mobileState.energyTitle, '认知能量池 75分');
  assert.match(mobileState.date, /^\d+月\d+日/);
  console.log('mobile focus hydration OK');
  await mobile.close();

  // 到点自动开始: an entry whose scheduled time arrives while the page is
  // open must start counting without user action.
  const soonServer = createServer(async (request, response) => {
    const url = new URL(request.url, 'http://localhost');
    try {
      if (url.pathname === '/api/schedule') {
        // The entry lands on the next minute boundary: the auto-start wait
        // is between 0 and 60 seconds.
        const boundary = new Date(Math.ceil(Date.now() / 60000) * 60000);
        response.writeHead(200, { 'Content-Type': 'application/json' });
        response.end(JSON.stringify([{
          id: 'sch_soon', title: '到点自动开始任务', tag: 'Routine', load: 'medium',
          day: today, height: 80, color: 0, repeat: 'none',
          time: minuteOf(boundary),
        }]));
        return;
      }
      if (url.pathname === '/api/energy/current') {
        response.writeHead(200, { 'Content-Type': 'application/json' });
        response.end(JSON.stringify({ batteryPercent: 75, status: '高效' }));
        return;
      }
      if (url.pathname === '/api/emotion/current') {
        response.writeHead(200, { 'Content-Type': 'application/json' });
        response.end(JSON.stringify({ state: 'stable' }));
        return;
      }
      if (url.pathname === '/api/events') {
        response.writeHead(200, { 'Content-Type': 'application/json' });
        response.end('[]'); return;
      }
      if (url.pathname === '/api/health') { response.writeHead(200); response.end('{}'); return; }
      const file = join(output, url.pathname === '/' ? '/index.html' : url.pathname);
      const body = await readFile(file);
      if (!response.headersSent) {
        response.writeHead(200, { 'Content-Type': mime[extname(file)] || 'application/octet-stream' });
        response.end(body);
      }
    } catch {
      if (!response.headersSent) { response.writeHead(404); response.end(); }
    }
  });
  await new Promise((resolve) => soonServer.listen(0, '127.0.0.1', resolve));
  const soonBase = `http://127.0.0.1:${soonServer.address().port}/`;
  const soonPage = await browser.newPage({ viewport: { width: 1440, height: 900 } });
  await soonPage.addInitScript(() => { window.__RUANCHUANG_API__ = '/api'; });
  await soonPage.goto(new URL('#/focus', soonBase).href);
  const soonFrame = soonPage.frameLocator('#prototype-screen');
  // The entry starts within ~65s; the card previews it, then auto-starts.
  await soonFrame.locator('#focus-task-title').filter({ hasText: '到点自动开始任务' }).waitFor({ timeout: 15000 });
  await soonFrame.locator('#focus-timer-status').filter({ hasText: '专注状态中' }).waitFor({ timeout: 80000 });
  const soonState = await soonFrame.locator('body').evaluate(() => ({
    display: document.getElementById('focus-timer-display')?.textContent,
    remaining: document.getElementById('focus-remaining-label')?.textContent,
  }));
  assert.match(soonState.remaining, /^剩余 (1:00:00|60:|59:)/, 'countdown runs the task duration after auto-start');
  await soonPage.close();
  soonServer.close();
  console.log('scheduled auto-start OK');
} finally {
  await browser.close();
  server.close();
}
console.log('stitch focus checks passed');
