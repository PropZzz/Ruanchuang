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
const temporary = await mkdtemp(join(tmpdir(), 'schedule-edit-'));
const backend = spawn(process.env.PYTHON || 'python', ['-u', '-c', `
import socket, uvicorn
from backend.main import create_app
server_socket = socket.socket()
server_socket.bind(('127.0.0.1', 0))
print(server_socket.getsockname()[1], flush=True)
uvicorn.Server(uvicorn.Config(create_app(), log_level='error')).run(sockets=[server_socket])
`], { cwd: resolve('.'), env: { ...process.env, SHIXUZHIPEI_DB_PATH: join(temporary, 'schedule-edit.sqlite3') }, stdio: ['ignore', 'pipe', 'pipe'] });
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
  await mkdir('build/schedule-edit-qa', { recursive: true });
  for (const mobile of [false, true]) {
    const registration = await fetch(api + '/auth/register', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ contactAddress: `${mobile ? 'mobile' : 'desktop'}@edit-test.local`, displayName: '日历验证', password: 'isolated-test-only' }) });
    assert.equal(registration.status, 200);
    const login = await registration.json();
    const context = await browser.newContext({ viewport: mobile ? { width: 390, height: 844 } : { width: 1440, height: 1000 }, timezoneId: 'Asia/Shanghai', reducedMotion: 'reduce' });
    await context.addInitScript(login => {
      window.__RUANCHUANG_API__ = location.origin + '/api';
      if (window === window.top && !sessionStorage.getItem('edit-test-seeded')) {
        sessionStorage.setItem('edit-test-seeded', 'true');
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
    const ready = name => page.waitForFunction(name => document.getElementById('prototype-screen')?.title === `时序智配 ${name}`, name);
    const settled = () => page.waitForFunction(() => document.getElementById('prototype-screen')?.contentDocument?.querySelector('#live-calendar-root[aria-busy="false"]'));
    const editorReady = () => page.waitForFunction(() => document.getElementById('prototype-screen')?.contentDocument?.documentElement.dataset.scheduleReady === 'true');
    const readRecords = async () => (await fetch(api + '/schedule', {headers:{Authorization:`Bearer ${login.accessToken}`}})).json();
    const writeRecord = async (method, path, body) => {
      const response = await fetch(api + path, { method, headers: {'Content-Type':'application/json',Authorization:`Bearer ${login.accessToken}`}, body:JSON.stringify(body) });
      assert.equal(response.status, 200); return response.json();
    };
    const openEdit = async id => { await page.evaluate(id => { location.hash = '#/create-schedule?id=' + encodeURIComponent(id); }, id); await ready('create-schedule'); await editorReady(); };
    const save = async () => { await frame().locator('#schedule-save-action').click(); await ready('schedule'); await settled(); };
    const choose = async (group, selector) => frame().locator(`#${group} ${selector}`).click();
    const setConstraints = async (flexible, locked) => {
      for (const [id,value] of [['schedule-flexible-switch',flexible],['schedule-locked-switch',locked]]) {
        const control = frame().locator('#'+id);
        if ((await control.getAttribute('aria-checked')) !== String(value)) await control.click();
        assert.equal(await control.getAttribute('aria-checked'),String(value));
      }
    };
    const snapshot = () => frame().locator('#schedule-form-fields').evaluate(node => ({
      ids: [...node.querySelectorAll('input,textarea')].map(n=>n.id),
      tags: [...node.querySelectorAll('#tagGroup button span:last-child')].map(n=>n.textContent),
      reminders: [...node.querySelectorAll('#reminderGroup button')].map(n=>n.dataset.reminder),
      repeats: [...node.querySelectorAll('#repeatGroup button')].map(n=>n.dataset.repeat),
      loads: [...node.querySelectorAll('#loadGroup button')].map(n=>n.dataset.load),
      duration: ['min','max','step'].map(k=>node.querySelector('#schedule-duration-input').getAttribute(k)),
      disabledSwitches: [...node.querySelectorAll('[role=switch]')].map(n=>n.disabled),
    }));
    await page.goto(base+'#/schedule'); await ready('schedule'); await settled();
    await frame().locator('[data-cal-date]').fill('2026-11-05'); await settled();
    await frame().locator('[data-cal-action="create"]').first().click(); await ready('create-schedule'); await editorReady();
    const newShape = await snapshot();
    assert.equal(newShape.tags.length,11); assert.deepEqual(newShape.duration,['5','1440','5']);
    assert.deepEqual(newShape.disabledSwitches,[false,false],'Schedule constraint switches must be usable');
    assert.equal(await frame().locator('#schedule-flexible-switch').getAttribute('aria-checked'),'true');
    assert.equal(await frame().locator('#schedule-locked-switch').getAttribute('aria-checked'),'false');
    await frame().locator('#schedule-locked-switch').click();
    assert.equal(await frame().locator('#schedule-flexible-switch').getAttribute('aria-checked'),'false','Locking must disable flexibility');
    await frame().locator('#schedule-flexible-switch').click();
    assert.equal(await frame().locator('#schedule-locked-switch').getAttribute('aria-checked'),'false','Flexibility must disable locking');
    await setConstraints(false,true);
    await frame().locator('#schedule-constraints-summary').scrollIntoViewIfNeeded();
    assert.match(await frame().locator('#schedule-constraints-summary').textContent(),/硬锁定/);
    assert.match(await frame().locator('#schedule-constraints-note').textContent(),/自动重排接入后生效/);
    await page.screenshot({path:`build/schedule-edit-qa/${mobile?'mobile':'desktop'}-constraints.png`});
    await frame().locator('#schedule-title-input').fill('共享表单初始日程');
    await choose('tagGroup','button:has-text("上课学习")');
    await choose('loadGroup','[data-load="high"]');
    await choose('reminderGroup','[data-reminder="0"]');
    await choose('repeatGroup','[data-repeat="weekly"]');
    await frame().locator('#schedule-time-input').fill('00:15');
    await frame().locator('#schedule-duration-input').fill('720');
    await save();
    let [entry] = await readRecords();
    assert.equal(entry.rescheduleFlexible,false); assert.equal(entry.hardLocked,true);
    assert.equal(entry.load,'high'); assert.equal(entry.reminderMinutesBefore,0); assert.equal(entry.repeat,'weekly');
    assert.equal(entry.height,960); assert.equal(entry.color,0xffd6e3ff);
    entry = await writeRecord('PUT','/schedule/'+entry.id,{...entry,goalId:'goal-preserved',goalTaskId:'task-preserved',repeatUntil:'2027-12-31'});
    await frame().locator(`[data-schedule-id="${entry.id}"]`).first().click(); await ready('schedule-detail');
    await frame().locator('#detailTitle').waitFor({state:'visible'});
    assert.equal(await frame().locator('#detailFlexible').textContent(),'不允许微调');
    assert.equal(await frame().locator('#detailLocked').textContent(),'已开启');
    await frame().locator('#editBtn').click(); await ready('create-schedule'); await editorReady();
    assert.deepEqual(await snapshot(),newShape,'New and edit must render the same controls from one document');
    assert.equal(await frame().locator('#schedule-form-title').textContent(),'编辑日程');
    assert.equal(await frame().locator('#schedule-title-input').inputValue(),entry.title);
    assert.equal(await frame().locator('#schedule-flexible-switch').getAttribute('aria-checked'),'false');
    assert.equal(await frame().locator('#schedule-locked-switch').getAttribute('aria-checked'),'true');
    assert.equal(await frame().locator('#schedule-time-input').inputValue(),'00:15');
    await frame().getByRole('button',{name:'选择开始时间',exact:true}).click();
    const timePicker = frame().locator('#import-time-picker');
    await timePicker.waitFor({state:'visible'});
    assert.equal(await timePicker.locator('.import-time-value').textContent(),'00:15');
    await timePicker.getByRole('option',{name:'08时',exact:true}).click();
    await page.keyboard.press('Escape');
    await ready('create-schedule');
    assert.equal(await frame().locator('#schedule-time-input').inputValue(),'00:15');
    assert.equal(await frame().locator('#schedule-duration-input').inputValue(),'720');
    assert.equal(await frame().locator('#tagGroup .active-tag span:last-child').textContent(),'上课学习');
    assert.equal(await frame().locator('#loadGroup .active-radio').getAttribute('data-load'),'high');
    assert.equal(await frame().locator('#reminderGroup .active-radio').getAttribute('data-reminder'),'0');
    assert.equal(await frame().locator('#repeatGroup .active-radio').getAttribute('data-repeat'),'weekly');
    await page.screenshot({path:`build/schedule-edit-qa/${mobile?'mobile':'desktop'}-edit.png`});
    await frame().locator('#schedule-title-input').fill('修改全部可编辑字段');
    await choose('tagGroup','button:has-text("考试复习")');
    await choose('loadGroup','[data-load="low"]');
    await choose('reminderGroup','[data-reminder="10"]');
    await choose('repeatGroup','[data-repeat="monthly"]');
    await setConstraints(true,false);
    await frame().locator('#schedule-date-input').fill('2026-11-06');
    await frame().locator('#schedule-time-input').fill('08:30');
    await frame().locator('#schedule-duration-input').fill('95');
    await save();
    let records=await readRecords(); assert.equal(records.length,1);
    let updated=records[0]; assert.equal(updated.id,entry.id); assert.equal(updated.title,'修改全部可编辑字段');
    assert.equal(updated.tag,'考试复习'); assert.equal(updated.color,0xfff5e6c8); assert.equal(updated.day,'2026-11-06');
    assert.deepEqual(updated.time,{hour:8,minute:30}); assert.equal(Math.round(updated.height*60/80),95);
    assert.equal(updated.load,'low'); assert.equal(updated.reminderMinutesBefore,10); assert.equal(updated.repeat,'monthly');
    assert.equal(updated.rescheduleFlexible,true); assert.equal(updated.hardLocked,false);
    for(const key of ['goalId','goalTaskId','repeatUntil']) assert.equal(updated[key],entry[key]);
    await page.reload(); await ready('schedule'); await settled();
    await openEdit(entry.id);
    assert.equal(await frame().locator('#schedule-title-input').inputValue(),updated.title);
    await frame().locator('#schedule-title-input').fill('取消编辑不能保存');
    await setConstraints(false,true);
    await choose('tagGroup','button:has-text("工作会议")');
    await frame().locator('[data-drawer-panel] button[aria-label="关闭抽屉"]').click(); await ready('schedule');
    assert.equal((await readRecords())[0].title,updated.title);
    await openEdit(entry.id); assert.equal(await frame().locator('#schedule-title-input').inputValue(),updated.title);
    assert.equal(await frame().locator('#schedule-flexible-switch').getAttribute('aria-checked'),'true');
    assert.equal(await frame().locator('#schedule-locked-switch').getAttribute('aria-checked'),'false');
    assert.equal(await frame().locator('#tagGroup .active-tag span:last-child').textContent(),'考试复习');
    await frame().locator('#schedule-title-input').fill('');
    await frame().locator('#schedule-save-action').click();
    await frame().locator('#stitch-router-notice').waitFor();
    assert.deepEqual(await readRecords(),[updated],'Invalid edits must not write');
    await frame().locator('#schedule-title-input').fill(updated.title);
    await choose('reminderGroup','[data-reminder="30"]'); await choose('repeatGroup','[data-repeat="daily"]');
    await save(); await openEdit(entry.id);
    assert.equal(await frame().locator('#reminderGroup .active-radio').getAttribute('data-reminder'),'30');
    assert.equal(await frame().locator('#repeatGroup .active-radio').getAttribute('data-repeat'),'daily');
    await choose('repeatGroup','[data-repeat="none"]'); await save();
    assert.equal((await readRecords())[0].repeatUntil,null);
    for (const [flexible,locked] of [[false,false],[false,true],[true,false]]) {
      await openEdit(entry.id); await setConstraints(flexible,locked); await save();
      const saved=(await readRecords()).find(row=>row.id===entry.id);
      assert.equal(saved.rescheduleFlexible,flexible); assert.equal(saved.hardLocked,locked);
      await page.reload(); await ready('schedule'); await settled(); await openEdit(entry.id);
      assert.equal(await frame().locator('#schedule-flexible-switch').getAttribute('aria-checked'),String(flexible));
      assert.equal(await frame().locator('#schedule-locked-switch').getAttribute('aria-checked'),String(locked));
      await frame().locator('[data-drawer-panel] button[aria-label="关闭抽屉"]').click(); await ready('schedule');
    }
    const legacy=await writeRecord('POST','/schedule',{title:'旧版未固定日程',tag:'历史自定义标签',day:null,time:{hour:0,minute:15},height:40,color:0xffabcdef,load:null,reminderMinutesBefore:15,repeat:'none'});
    await openEdit(legacy.id);
    assert.equal(await frame().locator('#schedule-date-input').inputValue(),'');
    assert.equal(await frame().locator('#schedule-time-input').inputValue(),'00:15');
    assert.equal(await frame().locator('#tagGroup .active-tag span:last-child').textContent(),legacy.tag);
    assert.equal(await frame().locator('#reminderGroup .active-radio').getAttribute('data-reminder'),'15');
    assert.equal(await frame().locator('#loadGroup .active-radio').getAttribute('data-load'),'');
    await frame().locator('#schedule-title-input').fill('旧记录仅修改标题'); await save();
    const legacySaved=(await readRecords()).find(n=>n.id===legacy.id);
    for(const key of ['tag','day','time','height','color','load','reminderMinutesBefore']) assert.deepEqual(legacySaved[key],legacy[key]);
    let unavailable = true;
    await page.route('**/api/schedule', route => unavailable ? route.fulfill({status:503,json:{detail:'isolated load failure'}}) : route.fallback());
    await page.evaluate(id=>{location.hash='#/create-schedule?id='+id;},entry.id); await ready('create-schedule');
    await frame().locator('#schedule-form-retry').waitFor();
    assert.equal(await frame().locator('#schedule-save-action').isEnabled(),false);
    unavailable=false; await frame().locator('#schedule-form-retry').click(); await editorReady();
    assert.equal(await frame().locator('#schedule-title-input').inputValue(),updated.title);
    await frame().locator('[data-drawer-panel] button[aria-label="关闭抽屉"]').click(); await ready('schedule');
    await frame().locator('[data-cal-action="create"]').first().click(); await ready('create-schedule'); await editorReady();
    assert.equal(await frame().locator('#schedule-title-input').inputValue(),'');
    assert.equal(await frame().locator('#tagGroup button').count(),11,'Legacy options must not leak into fresh forms');
    assert.equal(await frame().locator('#reminderGroup button').count(),3);
    assert.equal(await frame().locator('#schedule-form-title').textContent(),'新建日程');
    assert.equal(await frame().locator('#schedule-flexible-switch').getAttribute('aria-checked'),'true');
    assert.equal(await frame().locator('#schedule-locked-switch').getAttribute('aria-checked'),'false');
    assert.deepEqual(errors,[]);
    report.push({viewport:mobile?'mobile':'desktop',passed:true,checks:['same-form-fields-and-limits','eleven-tag-themes','zero-time-and-reminder','long-duration','all-fields-persisted','metadata-preserved','reload-and-cancel','recurrence-options','legacy-values-preserved','read-error-and-retry','new-form-isolation','constraint-switches-three-exclusive-states','constraint-detail-and-reload','constraint-cancel-and-default-reset']});
    await context.close();
  }
  await mkdir('build/reports',{recursive:true});
  await writeFile('build/reports/schedule-edit.json',JSON.stringify({release:release.release,cases:report},null,2));
  console.log(JSON.stringify({release:release.release,cases:report},null,2));
} finally {
  await browser?.close();
  if(staticServer.listening) await new Promise(resolve=>staticServer.close(resolve));
  const closed=new Promise(resolve=>backend.once('exit',resolve));
  if(backend.exitCode===null){backend.kill();await closed;}
  await rm(temporary,{recursive:true,force:true});
}
