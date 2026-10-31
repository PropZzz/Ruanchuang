import { stopTestBackend } from './test_backend_process.mjs';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { createServer } from 'node:http';
import { readFile, mkdir, mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { extname, join, resolve, sep } from 'node:path';
import { createInterface } from 'node:readline';
import { createRequire } from 'node:module';
import { buildStitchWeb } from './build_stitch_web.mjs';

// Verify the unified profile account controls and non-account settings against real FastAPI.
// Even with --url, all business requests go to this isolated local backend.
const { chromium } = createRequire(import.meta.url)(process.env.PLAYWRIGHT_MODULE || 'playwright');
const release = await buildStitchWeb();
const temporary = await mkdtemp(join(tmpdir(), 'account-settings-'));
const backend = spawn(process.env.PYTHON || 'python', ['-u', '-c', `
import socket, uvicorn
from backend.main import create_app
server_socket = socket.socket()
server_socket.bind(('127.0.0.1', 0))
print(server_socket.getsockname()[1], flush=True)
uvicorn.Server(uvicorn.Config(create_app(), log_level='error')).run(sockets=[server_socket])
`], { cwd: resolve('.'), env: { ...process.env, SHIXUZHIPEI_DB_PATH: join(temporary, 'accounts.sqlite3') }, stdio: ['ignore', 'pipe', 'pipe'] });
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
  await mkdir('build/account-settings-qa', { recursive: true });
  for (const mobile of [false, true]) {
    const registration = await fetch(api + '/auth/register', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ contactAddress: `${mobile ? 'mobile' : 'desktop'}@account-settings-test.local`, displayName: '账号验证', password: 'isolated-test-only' }) });
    assert.equal(registration.status, 200);
    const login = await registration.json();
    const context = await browser.newContext({ viewport: mobile ? { width: 390, height: 844 } : { width: 1440, height: 1000 }, timezoneId: 'Asia/Shanghai', reducedMotion: 'reduce' });
    await context.addInitScript(login => {
      window.__RUANCHUANG_API__ = location.origin + '/api';
      if (window === window.top && !sessionStorage.getItem('account-qa-seeded')) {
        sessionStorage.setItem('account-qa-seeded', 'true');
        localStorage.setItem('access_token', login.accessToken);
        localStorage.setItem('ruanchuang_user', JSON.stringify(login.user));
      }
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
    const ready = route => page.waitForFunction(route => document.getElementById('prototype-screen')?.title === `时序智配 ${route}` && document.getElementById('prototype-screen')?.contentDocument?.getElementById('ruanchuang-polish-styles'), route);
    const go = async route => { await page.evaluate(route => { location.hash = '#/' + route; }, route); await ready(route); };
    const readUser = async () => (await fetch(api + '/auth/me', { headers: { Authorization: `Bearer ${login.accessToken}` } })).json();
    await page.goto(base + '#/profile'); await ready('profile');
    assert.equal(await frame().locator('main h1').textContent(), login.user.displayName);
    assert.equal(await frame().locator('#profile-edit-action').isVisible(), true);
    assert.equal(await frame().locator('#profile-logout-action').isVisible(), true);
    await frame().locator('#profile-edit-action').click();
    await frame().locator('#profile-name').fill('取消修改');
    await frame().locator('#profile-cancel').click();
    await frame().locator('#profile-dialog').waitFor({ state: 'detached' });
    assert.equal((await readUser()).displayName, login.user.displayName);
    await frame().locator('#profile-edit-action').click();
    const newName = '统一账号 <真实验证>';
    await frame().locator('#profile-name').fill(newName);
    await frame().locator('#profile-name').press('Enter');
    await page.waitForFunction(name => document.getElementById('prototype-screen')?.contentDocument?.querySelector('main h1')?.textContent === name, newName);
    assert.equal((await readUser()).displayName, newName);
    await frame().locator('#profile-dialog').waitFor({ state: 'detached' });
    await frame().locator('#profile-edit-action').click();
    assert.equal(await frame().locator('#profile-name').inputValue(), newName);
    await frame().locator('#profile-name').press('Escape');
    await frame().locator('#profile-dialog').waitFor({ state: 'detached' });
    await page.reload(); await ready('profile');
    assert.equal(await frame().locator('main h1').textContent(), newName);
    assert.equal((await readUser()).displayName, newName);
    for (const route of ['profile', 'focus']) {
      await go(route);
      if (mobile && route === 'profile') await frame().locator('#profile-settings-open').click();
      else if (mobile) await page.evaluate(() => { location.hash = '#/settings-drawer'; });
      else await page.locator('#workspace-shell button[data-route="settings-drawer"]').click();
      const settings = page.frameLocator('#ruanchuang-settings-overlay iframe');
      await settings.locator('#save-settings-btn, #btn-save-settings').waitFor();
      await page.waitForFunction(() => { const doc = document.querySelector('#ruanchuang-settings-overlay iframe')?.contentDocument; return doc?.querySelector('[data-theme][aria-pressed]') && !doc.querySelector('#save-settings-btn, #btn-save-settings').disabled; });
      const content = await settings.locator('#settings-drawer').innerText();
      assert.doesNotMatch(content, /账户与多用户管理|修改昵称|切换账户|退出登录|TX-90248/);
      assert.match(content, /外观/); assert.match(content, /语言与国际化/); assert.match(content, /系统通知与外部提醒/);
      if (mobile) { assert.match(content, /本地优先与安全审计/); }
      else { assert.match(content, /时序引擎行为偏好/); }
      if (route === 'profile') {
        await page.screenshot({ path: `build/account-settings-qa/${mobile ? 'mobile' : 'desktop'}-settings.png` });
        await settings.locator('[data-theme="light"]').click();
        await settings.locator('[data-lang="zh-CN"]').click();
        await settings.locator('#save-settings-btn, #btn-save-settings').click();
        await page.locator('#ruanchuang-settings-overlay').waitFor({ state: 'detached' });
        const saved = await (await fetch(api + '/settings', { headers: { Authorization: `Bearer ${login.accessToken}` } })).json();
        assert.equal(saved.themeMode, 'light'); assert.equal(saved.locale, 'zh_CN');
      } else {
        await settings.locator('#close-drawer-btn, #btn-close-drawer').click();
        await page.locator('#ruanchuang-settings-overlay').waitFor({ state: 'detached' });
      }
      await ready(route);
    }
    await go('profile');
    await frame().locator('#profile-switch-account').click();
    await ready('login');
    await frame().locator('#login-back-action').click(); await ready('profile');
    assert.equal(await page.evaluate(() => localStorage.getItem('access_token')), login.accessToken);
    await page.screenshot({ path: `build/account-settings-qa/${mobile ? 'mobile' : 'desktop'}-profile.png` });
    await frame().locator('#profile-logout-action').click(); await ready('login');
    assert.equal(await page.evaluate(() => localStorage.getItem('access_token')), null);
    assert.equal(await page.evaluate(() => localStorage.getItem('ruanchuang_user')), null);
    assert.equal((await fetch(api + '/auth/me', { headers: { Authorization: `Bearer ${login.accessToken}` } })).status, 401);
    await go('profile');
    assert.equal(await frame().locator('#profile-edit-action').isVisible(), false);
    assert.equal(await frame().locator('#profile-logout-action').isVisible(), false);
    assert.equal(await frame().locator('#profile-switch-account [data-account-label]').textContent(), '登录 / 注册');
    await frame().locator('#profile-switch-account').click(); await ready('login');
    await frame().locator('#auth-account-input').fill(`${mobile ? 'mobile' : 'desktop'}@account-settings-test.local`);
    await frame().locator('#auth-password-input').fill('isolated-test-only');
    await frame().locator('#auth-submit').click(); await ready('profile');
    assert.equal(await frame().locator('main h1').textContent(), newName);
    assert.equal(await frame().locator('#profile-edit-action').isVisible(), true);
    assert.deepEqual(errors, []);
    report.push({ viewport: mobile ? 'mobile' : 'desktop', passed: true, backend: 'FastAPI + isolated SQLite', checks: ['profile-edit-cancel-reopen-enter', 'persisted-name', 'settings-without-account-controls', 'retained-non-account-sections', 'settings-save', 'switch-and-return', 'logout-token-revoked', 'guest-entry-and-login'] });
    await context.close();
  }
  await mkdir('build/reports', { recursive: true });
  await writeFile('build/reports/account-settings.json', JSON.stringify({ release: release.release, cases: report }, null, 2));
  console.log(JSON.stringify({ release: release.release, cases: report }, null, 2));
} finally {
  await browser?.close();
  if (staticServer.listening) await new Promise(resolve => staticServer.close(resolve));
  await stopTestBackend(backend);
  await rm(temporary, { recursive: true, force: true, maxRetries: 5, retryDelay: 200 });
}
