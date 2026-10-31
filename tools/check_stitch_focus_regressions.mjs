// Focus security and elapsed-time regressions, using the production mount.
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const browser = await chromium.launch({ headless: true });
try {
  const page = await browser.newPage();
  await page.route('http://focus.test/', route => route.fulfill({ body: '<html><body></body></html>', contentType: 'text/html' }));
  await page.goto('http://focus.test/');
  const markup = '<div id="focus-tag-chip"></div><div id="focus-stat-current-sub"></div><div id="focus-stat-conflict"></div><div id="focus-timer-display"></div><button data-focus-action="toggle"></button><button data-focus-action="finish"></button>';
  await page.setContent(markup);
  await page.evaluate(() => {
    localStorage.setItem('ruanchuang-focus-mode', 'flow');
    const now = new Date();
    window.focusEntry = { id: 'regression', title: '测试任务', tag: '<img src=x onerror="window.tagExecuted=true">', day: null, time: { hour: now.getHours(), minute: now.getMinutes() }, height: 80 };
    window.offset = 0;
    const realNow = Date.now;
    Date.now = () => realNow() + window.offset;
    window.events = [];
  });
  await page.addScriptTag({ path: fileURLToPath(new URL('../web/stitch/focus.js', import.meta.url)) });
  await page.evaluate(() => {
    window.controller = StitchFocus.mount(document, { request: async (path, options) => {
      if (path === '/schedule') return [window.focusEntry];
      if (path === '/events' && options?.method === 'POST') window.events.push(options.body);
      if (path.startsWith('/events')) return [];
      return {};
    } });
  });
  await page.waitForFunction(() => document.getElementById('focus-timer-display').textContent === '00:00');
  assert.equal(await page.locator('#focus-tag-chip img').count(), 0, 'custom tags must render as text, never HTML');
  assert.equal(await page.locator('#focus-tag-chip').textContent(), '<img src=x onerror="window.tagExecuted=true">');
  assert.equal(await page.evaluate(() => window.tagExecuted), undefined);
  await page.evaluate(() => {
    document.documentElement.dataset.pageVisible = 'false';
    window.offset += 125000;
  });
  await page.waitForTimeout(1100);
  await page.evaluate(() => {
    document.documentElement.dataset.pageVisible = 'true';
    document.dispatchEvent(new Event('stitch:visibility'));
  });
  const seconds = async () => (await page.locator('#focus-timer-display').textContent()).split(':').reduce((sum, part) => sum * 60 + Number(part), 0);
  assert.ok(await seconds() >= 125, 'flow must include time spent on another page');
  await page.locator('[data-focus-action="toggle"]').click();
  const paused = await seconds();
  await page.evaluate(() => { window.offset += 60000; document.dispatchEvent(new Event('stitch:visibility')); });
  assert.equal(await seconds(), paused, 'paused flow must exclude paused time');
  await page.locator('[data-focus-action="toggle"]').click();
  await page.evaluate(() => { window.offset += 65000; document.dispatchEvent(new Event('stitch:visibility')); });
  assert.ok(await seconds() >= paused + 65, 'resumed flow must retain prior elapsed time');
  await page.locator('[data-focus-action="finish"]').click();
  await page.waitForFunction(() => window.events.some(event => event.type === 'complete'));
  assert.equal(await page.evaluate(() => window.events.find(event => event.type === 'complete').actualMinutes), 3);
  console.log('focus tag safety, hidden-page elapsed time, pause/resume and completion OK');
  await page.evaluate(async () => {
    window.controller.dispose();
    window.controller = StitchFocus.mount(document, { request: async path => {
      if (path === '/schedule') return [window.focusEntry];
      if (path.startsWith('/events')) return window.events;
      return {};
    } });
    await window.controller.refresh();
  });
  assert.notEqual(await page.locator('#focus-stat-current-sub').textContent(), '测试任务', 'completed tasks must stay completed after remount');
  await page.evaluate(() => window.controller.dispose());
  await page.setContent(markup);
  await page.evaluate(async () => {
    window.controller = StitchFocus.mount(document, { request: async path => {
      if (path === '/schedule') return [window.focusEntry, { ...window.focusEntry, id: 'overlap' }];
      if (path.startsWith('/events')) return [];
      return {};
    } });
    await window.controller.refresh();
  });
  assert.equal(await page.locator('#focus-stat-conflict').textContent(), '1', 'all overlapping current tasks must count as conflicts');
  await page.evaluate(() => window.controller.dispose());
  await page.setContent(markup);
  await page.evaluate(async () => {
    const next = new Date(Date.now() - window.offset + 600000);
    window.puts = [];
    window.controller = StitchFocus.mount(document, { request: async (path, options) => {
      if (path === '/schedule') return [{ ...window.focusEntry, time: { hour: next.getHours(), minute: next.getMinutes() } }];
      if (options?.method === 'PUT') window.puts.push(options.body);
      if (path.startsWith('/events')) return [];
      return {};
    } });
    await window.controller.refresh();
  });
  await page.locator('[data-focus-action="toggle"]').click();
  await page.waitForTimeout(100);
  assert.equal(await page.evaluate(() => window.puts.length), 0, 'early start must preserve floating daily schedules');
  console.log('completed-task restore, overlapping tasks and floating daily schedule preservation OK');
} finally {
  await browser.close();
}
