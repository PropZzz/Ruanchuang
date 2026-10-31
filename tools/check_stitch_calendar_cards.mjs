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
await mkdir('build/calendar-card-qa', { recursive: true });
const durations = [5, 15, 30, 45, 60, 75, 90, 120];
const records = durations.map((minutes, i) => ({ id: `duration-${minutes}`, title: minutes === 60 ? '学习' : `${minutes}分钟日程标题自适应显示`, day: `2026-11-0${2 + i % 4}`, time: { hour: i < 4 ? 9 : 13, minute: 0 }, height: minutes * 80 / 60, tag: '跨部门协同', color: 0xff62a1fe }));
records.push({ id: 'long-title', title: '这是一条较长的日程标题需要通过悬停和键盘聚焦查看完整内容，且不能改变原有的时间刻度或遮住永久日程', day: '2026-11-06', time: {hour: 13, minute: 0}, height: 80, tag: '评审' });
const inspectTitle = card => card.evaluate(node => {
  const title = node.querySelector('strong'), range = node.ownerDocument.createRange(); range.selectNodeContents(title);
  const text = range.getBoundingClientRect(), box = title.getBoundingClientRect(), cardBox = node.getBoundingClientRect();
  return { text: title.textContent, lineHeight: parseFloat(getComputedStyle(title).lineHeight), titleHeight: box.height, textHeight: text.height, top: box.top, bottom: box.bottom, cardTop: cardBox.top, cardBottom: cardBox.bottom, background: getComputedStyle(node).backgroundColor };
});
try {
  for (const width of [1440, 2048, 1024, 390]) {
    const mobile = width === 390;
    const context = await browser.newContext({ viewport: { width, height: 1100 }, timezoneId: 'Asia/Shanghai', reducedMotion: 'reduce' });
    await context.addInitScript(() => { window.__RUANCHUANG_API__ = location.origin + '/api'; localStorage.setItem('access_token', 'isolated-layout-test'); });
    const page = await context.newPage(), errors = [];
    page.on('pageerror', e => errors.push(e.message));
    await page.route('**/api/**', route => route.fulfill({ json: new URL(route.request().url()).pathname === '/api/schedule' ? records : {} }));
    const frame = () => page.frameLocator('#prototype-screen');
    const settled = () => page.waitForFunction(() => document.getElementById('prototype-screen')?.contentDocument?.querySelector('#live-calendar-root[aria-busy="false"]'));
    await page.goto(base + '#/schedule'); await settled();
    await frame().locator('[data-cal-date]').fill('2026-11-02'); await settled();
    await frame().locator('[data-cal-action="week"]').click(); await settled();
    // Keep screenshots and measurements independent of hover/focus expansion.
    await page.mouse.move(0, 0);
    await frame().locator('[data-schedule-id="duration-60"]').scrollIntoViewIfNeeded();
    for (const duration of durations) {
      const card = frame().locator(`[data-schedule-id="duration-${duration}"]`);
      const metrics = await inspectTitle(card);
      assert.ok(metrics.titleHeight >= metrics.lineHeight - 1, `${width}px/${duration}m: title must retain at least a full line: ${JSON.stringify(metrics)}`);
      assert.ok(metrics.top >= metrics.cardTop && metrics.bottom <= metrics.cardBottom + 1, `${width}px/${duration}m: title must fit vertically inside the card`);
      assert.equal(metrics.background, 'rgba(98, 161, 254, 0.4)');
      if (duration === 60) assert.ok(metrics.textHeight <= metrics.titleHeight + 1, 'The screenshot title 学习 must be fully visible');
      if (!mobile) {
        const slot = await card.evaluate(node => ({ top: parseFloat(node.parentElement.style.top), height: parseFloat(node.parentElement.style.height) }));
        assert.equal(slot.height, Math.max(22, duration));
        assert.equal(slot.top, duration < 60 ? 60 : 300);
      }
    }
    await page.screenshot({ path: `build/calendar-card-qa/${width}-week.png` });
    if (!mobile) {
      for (const duration of durations) {
        const card = frame().locator(`[data-schedule-id="duration-${duration}"]`);
        const slot = await card.evaluate(n => n.parentElement.style.cssText);
        await card.hover();
        const expanded = await inspectTitle(card);
        assert.ok(expanded.textHeight <= expanded.titleHeight + 1, `${duration}m: hover must reveal the full title`);
        await page.mouse.move(0, 0);
        assert.equal(await card.evaluate(n => n.parentElement.style.cssText), slot);
      }
      const long = frame().locator('[data-schedule-id="long-title"]');
      const before = await long.evaluate(n => n.parentElement.style.cssText);
      await long.hover();
      const full = await inspectTitle(long);
      assert.ok(full.textHeight <= full.titleHeight + 1, 'Hover must reveal the complete long title');
      await page.screenshot({ path: `build/calendar-card-qa/${width}-hover.png` });
      await page.mouse.move(0, 0);
      await long.focus();
      const focused = await inspectTitle(long);
      assert.ok(focused.textHeight <= focused.titleHeight + 1, 'Keyboard focus must reveal the complete title');
      assert.equal(await long.evaluate(n => n.parentElement.style.cssText), before, 'Expansion must not change the time slot');
      await long.evaluate(n => n.blur());
      await frame().locator('[data-cal-action="day"]').click(); await settled();
      await page.screenshot({ path: `build/calendar-card-qa/${width}-day.png` });
      const short = frame().locator('[data-schedule-id="duration-5"]');
      await short.click();
      await page.waitForFunction(() => document.getElementById('prototype-screen')?.title === '时序智配 schedule-detail');
      await frame().locator('#detailTag').waitFor();
    }
    assert.deepEqual(errors, []);
    report.push({ width, passed: true, durations, checks: ['visible-title-line', 'no-vertical-title-clipping', 'original-theme', ...(mobile ? ['mobile-week-list'] : ['time-slot-geometry', 'hover-and-focus-full-title', 'day-week', 'detail-opening'])] });
    await context.close();
  }
  await mkdir('build/reports', { recursive: true });
  await writeFile('build/reports/calendar-cards.json', JSON.stringify({release:release.release,cases:report},null,2));
  console.log(JSON.stringify({release:release.release,cases:report},null,2));
} finally { await browser.close(); await new Promise(resolve => server.close(resolve)); }
