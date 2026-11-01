import assert from 'node:assert/strict';
import { readFile, readdir } from 'node:fs/promises';
import vm from 'node:vm';
import test from 'node:test';

const context = vm.createContext({});
vm.runInContext(await readFile(new URL('../../web/stitch/actions.js', import.meta.url), 'utf8'), context);
const { apiAction } = context.StitchActions;
const button = (id = '', dataset = {}) => ({
  id, dataset,
  get textContent() { throw new Error('Action dispatch must not read display text'); },
  get title() { throw new Error('Action dispatch must not read tooltip text'); },
  getAttribute() { throw new Error('Action dispatch must not read accessibility labels'); },
});

test('API actions remain stable when visible or translated text changes', () => {
  for (const action of ['create-schedule', 'rescue-options', 'urgent-task-to-microtask', 'rescue-apply', 'auth-logout']) {
    assert.equal(apiAction(button('', { action }), 'schedule'), action);
  }
  assert.equal(apiAction(button('btn-quick-add'), 'micro'), 'microtask-quick-add');
  assert.equal(apiAction(button('schedule-rescue-undo'), 'schedule'), 'rescue-history');
  assert.equal(apiAction(button('profile-save'), 'profile'), 'auth-profile-save');
  assert.equal(apiAction(button('', { rescueOptionId: 'min-change' }), 'rescue-comparison'), 'rescue-apply');
});

test('authentication uses the current form mode and only the login route', () => {
  const submit = button('auth-submit', { action: 'auth-submit', authMode: 'login' });
  assert.equal(apiAction(submit, 'login'), 'auth-login');
  submit.dataset.authMode = 'register';
  assert.equal(apiAction(submit, 'login'), 'auth-register');
  assert.equal(apiAction(submit, 'profile'), null);
});

test('unknown and focus-owned controls cannot trigger generic API dispatch', () => {
  assert.equal(apiAction(button('constructor'), 'schedule'), null);
  assert.equal(apiAction(button('schedule-save-action', { action: 'unknown' }), 'schedule'), null);
  assert.equal(apiAction(button('', { focusAction: 'finish', action: 'rescue-apply' }), 'focus'), null);
  assert.equal(apiAction(null, 'schedule'), null);
});

test('every existing API button and rescue form has an explicit template hook', async () => {
  async function htmlFiles(base) {
    const result = [];
    for (const entry of await readdir(base, { withFileTypes: true })) {
      const url = new URL(`${entry.name}${entry.isDirectory() ? '/' : ''}`, base);
      if (entry.isDirectory()) result.push(...await htmlFiles(url));
      else if (entry.name.endsWith('.html')) result.push(url);
    }
    return result;
  }
  const hooks = new Set();
  for (const file of await htmlFiles(new URL('../../web/stitch/', import.meta.url))) {
    const html = await readFile(file, 'utf8');
    for (const tag of html.matchAll(/<button\b[^>]*>/g)) {
      const id = /\bid="([^"]+)"/.exec(tag[0])?.[1];
      const expected = apiAction(button(id || ''), 'login');
      if (!expected) continue;
      assert.match(tag[0], /\bdata-action="[^"]+"/, `${file}: ${id}`);
      hooks.add(id);
    }
  }
  for (const id of ['schedule-save-action', 'auth-submit', 'profile-edit-action', 'profile-logout-action', 'schedule-rescue-undo', 'mobile-rescue-undo']) {
    assert.ok(hooks.has(id), `Missing the ${id} form control`);
  }
  const urgent = await readFile(new URL('../../web/stitch/mobile/insert-urgent-task-drawer/index.html', import.meta.url), 'utf8');
  assert.match(urgent, /data-action="rescue-options"/);
  assert.match(urgent, /data-action="urgent-task-to-microtask"/);
  for (const path of ['screens/rescue-comparison', 'mobile/urgent-rescue-comparison']) {
    const html = await readFile(new URL(`../../web/stitch/${path}/index.html`, import.meta.url), 'utf8');
    assert.equal([...html.matchAll(/<button\b[^>]*\bdata-action="rescue-apply"/g)].length, 3);
    assert.ok(!html.includes('已确认选择【'), 'Standalone pages must not claim an unwritten SQLite result');
  }
});
