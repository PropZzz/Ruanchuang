import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { createServer } from 'node:http';
import { readFile, mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { extname, join, resolve, sep } from 'node:path';
import { createInterface } from 'node:readline';
import { createRequire } from 'node:module';
import { buildStitchWeb } from './build_stitch_web.mjs';
import { stopTestBackend } from './test_backend_process.mjs';

// Desktop and mobile must expose an actual undo control after applying rescue.
// This tool always uses a disposable local database, with real FastAPI requests.
const { chromium } = createRequire(import.meta.url)(process.env.PLAYWRIGHT_MODULE || 'playwright');
const release = await buildStitchWeb();
const temporary = await mkdtemp(join(tmpdir(), 'rescue-workflow-'));
const backend = spawn(process.env.PYTHON || 'python', ['-u', '-c', `
import socket, uvicorn
from backend.main import create_app
s = socket.socket(); s.bind(('127.0.0.1', 0))
print(s.getsockname()[1], flush=True)
uvicorn.Server(uvicorn.Config(create_app(), log_level='error')).run(sockets=[s])
`], { cwd: resolve('.'), env: { ...process.env, SHIXUZHIPEI_DB_PATH: join(temporary, 'rescue.sqlite3') }, stdio: ['ignore', 'pipe', 'pipe'] });
let diagnostics = '', api, browser;
backend.stderr.on('data', bytes => { diagnostics = (diagnostics + bytes).slice(-4000); });
const server = createServer(async (req, res) => {
  try {
    const path = new URL(req.url, 'http://localhost').pathname;
    if (path.startsWith('/api/')) {
      const chunks = []; for await (const chunk of req) chunks.push(chunk);
      const headers = { 'Content-Type': 'application/json' };
      if (req.headers.authorization) headers.Authorization = req.headers.authorization;
      const response = await fetch(api + req.url.slice(4), { method: req.method, headers,
        ...(['GET', 'HEAD'].includes(req.method) ? {} : { body: Buffer.concat(chunks) }) });
      res.writeHead(response.status, { 'Content-Type': response.headers.get('content-type') || 'application/json' });
      res.end(Buffer.from(await response.arrayBuffer())); return;
    }
    const file = resolve(release.output, '.' + (path === '/' ? '/index.html' : path));
    assert.ok(file.startsWith(release.output + sep));
    const types = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.woff2': 'font/woff2' };
    res.setHeader('Content-Type', types[extname(file)] || 'application/octet-stream');
    res.end(await readFile(file));
  } catch { res.writeHead(500); res.end(); }
});
try {
  const port = await new Promise((resolvePort, reject) => {
    const lines = createInterface({ input: backend.stdout });
    const timeout = setTimeout(() => reject(new Error('Backend startup timed out: ' + diagnostics)), 15000);
    backend.once('exit', () => { clearTimeout(timeout); reject(new Error('Backend exited: ' + diagnostics)); });
    lines.once('line', line => { clearTimeout(timeout); resolvePort(Number(line)); });
  });
  api = `http://127.0.0.1:${port}`;
  const deadline = Date.now() + 15000;
  while (true) {
    try { assert.equal((await (await fetch(api + '/health')).json()).ok, true); break; }
    catch (error) { if (Date.now() >= deadline) throw error; await new Promise(r => setTimeout(r, 100)); }
  }
  await new Promise(r => server.listen(0, '127.0.0.1', r));
  const base = `http://127.0.0.1:${server.address().port}/`;
  browser = await chromium.launch({ headless: true });
  const day = new Date(Date.now() + 86400000).toISOString().slice(0, 10);
  for (const mobile of [false, true]) {
    const response = await fetch(api + '/auth/register', { method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ contactAddress: `${mobile}@rescue.test`, displayName: 'Rescue', password: 'isolated-only' }) });
    assert.equal(response.status, 200); const login = await response.json();
    const context = await browser.newContext({ viewport: mobile ? { width: 390, height: 844 } : { width: 1440, height: 1000 }, timezoneId: 'Asia/Shanghai' });
    await context.addInitScript(login => {
      window.__RUANCHUANG_API__ = location.origin + '/api';
      localStorage.setItem('access_token', login.accessToken);
      localStorage.setItem('ruanchuang_user', JSON.stringify(login.user));
    }, login);
    const page = await context.newPage(), errors = [];
    page.on('pageerror', error => errors.push(error.message));
    const frame = () => page.frameLocator('#prototype-screen');
    const ready = route => page.waitForFunction(route => document.getElementById('prototype-screen')?.title === `时序智配 ${route}`, route);
    await page.goto(base + '#/urgent-task'); await ready('urgent-task');
    await frame().locator('#urgent-task-title-input').fill('Rescue workflow');
    await frame().locator('#urgent-task-deadline-input').fill(day + 'T23:30');
    await frame().locator('[data-action="rescue-options"]').click(); await ready('rescue-comparison');
    await frame().locator('[data-action="rescue-apply"]:visible').first().click(); await ready('schedule');
    const headers = { Authorization: `Bearer ${login.accessToken}` };
    const read = async path => { const result = await fetch(api + path, { headers }); assert.equal(result.status, 200); return result.json(); };
    assert.ok((await read('/schedule')).some(entry => entry.title === 'Rescue workflow'));
    // Reload proves the remembered snapshot, retained page and action still agree.
    await page.reload(); await ready('schedule');
    const undo = frame().locator(mobile ? '#mobile-rescue-undo' : '#schedule-rescue-undo');
    await undo.waitFor({ state: 'visible' });
    const [undone] = await Promise.all([
      page.waitForResponse(r => r.url().endsWith('/schedule/rescue/undo') && r.request().method() === 'POST'),
      undo.click(),
    ]);
    assert.equal(undone.status(), 200);
    assert.deepEqual(await read('/schedule'), []);
    const history = await read('/review/rescue-history');
    assert.equal(history.length, 2);
    assert.ok(history.some(event => event.reason.startsWith('rescue_accept:')));
    assert.ok(history.some(event => event.reason.startsWith('rescue_undo:')));
    await page.evaluate(() => { location.hash = '#/review'; });
    await ready('review');
    if (mobile) {
      const layout = await frame().locator('main').evaluate(main => {
        const box = main.getBoundingClientRect();
        return { left: box.left, width: box.width, viewport: innerWidth,
          scrollWidth: document.documentElement.scrollWidth };
      });
      assert.ok(layout.left < 24 && layout.width >= layout.viewport - 24,
        'Mobile review must use the full viewport instead of reserving the desktop sidebar');
      assert.ok(layout.scrollWidth <= layout.viewport + 1, 'Mobile review must not overflow horizontally');
    }
    assert.deepEqual(errors, []);
    console.log(`${mobile ? 'mobile' : 'desktop'}: real rescue generation, apply, reload, undo and history passed`);
    await context.close();
  }
} finally {
  await browser?.close();
  if (server.listening) await new Promise(r => server.close(r));
  await stopTestBackend(backend);
  await rm(temporary, { recursive: true, force: true, maxRetries: 5, retryDelay: 200 });
}
