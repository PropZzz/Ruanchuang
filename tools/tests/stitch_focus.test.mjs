import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import vm from 'node:vm';
import test from 'node:test';

const context = vm.createContext({ Date, Intl, console });
vm.runInContext(await readFile(new URL('../../web/stitch/focus.js', import.meta.url), 'utf8'), context);
const {
  occursOnDay,
  selectCurrentNext,
  countConflicts,
  formatCountdown,
  cognitiveLoadFor,
  tagLabel,
  durationMinutes,
} = context.StitchFocus;

const at = (hours, minutes) => new Date(2026, 9, 31, hours, minutes, 0, 0);
const entry = (id, hour, minute, minutes, extra = {}) => ({
  id,
  title: id,
  day: '2026-10-31',
  time: { hour, minute },
  height: minutes * 80 / 60,
  repeat: 'none',
  ...extra,
});

test('current task is the entry covering now; later starts are upcoming', () => {
  const entries = [
    entry('a', 9, 0, 120),
    entry('b', 14, 0, 60),
    entry('c', 15, 0, 30),
  ];
  const { current, upcoming } = selectCurrentNext(entries, at(10, 30));
  assert.equal(current.entry.id, 'a');
  // Spread into the test realm: vm-realm arrays share no Array.prototype.
  assert.deepEqual([...upcoming.map((item) => item.entry.id)], ['b', 'c']);
});

test('no current task when nothing covers now; overlap keeps the later entry', () => {
  const empty = selectCurrentNext([entry('a', 9, 0, 60)], at(12, 0));
  assert.equal(empty.current, null);
  assert.deepEqual([...empty.upcoming], []);

  const overlap = selectCurrentNext(
    [entry('a', 9, 0, 120), entry('b', 10, 0, 60)],
    at(10, 30),
  );
  assert.equal(overlap.current.entry.id, 'b');
  assert.deepEqual([...overlap.upcoming.map((item) => item.entry.id)], []);
});

test('repetition follows the calendar semantics with an until bound', () => {
  const daily = { id: 'd', day: '2026-10-01', repeat: 'daily', time: { hour: 8, minute: 0 }, height: 80 };
  const weekly = { id: 'w', day: '2026-10-03', repeat: 'weekly', time: { hour: 8, minute: 0 }, height: 80 };
  const bounded = { id: 'b', day: '2026-10-01', repeat: 'daily', repeatUntil: '2026-10-30', time: { hour: 8, minute: 0 }, height: 80 };
  const floating = { id: 'f', time: { hour: 8, minute: 0 }, height: 80 };
  const saturday = at(10, 0); // 2026-10-31 is a Saturday.
  assert.equal(occursOnDay(daily, saturday), true);
  assert.equal(occursOnDay(weekly, saturday), true); // exactly 4 weeks after the Saturday anchor
  assert.equal(occursOnDay(bounded, saturday), false);
  assert.equal(occursOnDay(floating, saturday), true);
  assert.equal(occursOnDay(entry('x', 8, 0, 60), at(10, 0)), true);
  assert.equal(occursOnDay({ ...entry('x', 8, 0, 60), day: '2026-11-01' }, at(10, 0)), false);
});

test('monthly repetition follows the calendar month-end clamp', () => {
  const monthly = { day: '2026-01-31', repeat: 'monthly' };
  assert.equal(occursOnDay(monthly, new Date(2026, 0, 31)), true);
  assert.equal(occursOnDay(monthly, new Date(2026, 1, 28)), true);
  assert.equal(occursOnDay(monthly, new Date(2026, 2, 28)), true);
  assert.equal(occursOnDay(monthly, new Date(2026, 2, 31)), false);
  assert.equal(occursOnDay({ ...monthly, repeatUntil: '2026-02-28' }, new Date(2026, 2, 28)), false);
});

test('conflicts count overlapping pairs once and ignore touching boundaries', () => {
  const items = (pairs) => pairs.map(([start, end]) => ({ start, end }));
  assert.equal(countConflicts(items([[540, 660], [660, 720]])), 0);
  assert.equal(countConflicts(items([[540, 660], [600, 720]])), 1);
  assert.equal(countConflicts(items([[540, 720], [600, 660], [630, 700]])), 3);
  assert.equal(countConflicts(items([[540, 720], [600, 660], [660, 720]])), 2);
  assert.equal(countConflicts([]), 0);
});

test('countdown renders hours only when present', () => {
  assert.equal(formatCountdown(3661), '1:01:01');
  assert.equal(formatCountdown(600), '10:00');
  assert.equal(formatCountdown(0), '00:00');
  assert.equal(formatCountdown(-5), '00:00');
});

test('cognitive load prefers the stored value, then tag, then duration', () => {
  assert.equal(cognitiveLoadFor({ load: 'low', tag: 'Deep Work', height: 160 }), 'low');
  assert.equal(cognitiveLoadFor({ tag: 'Deep Work', height: 80 }), 'high');
  assert.equal(cognitiveLoadFor({ tag: 'Micro Task', height: 80 }), 'low');
  assert.equal(cognitiveLoadFor({ tag: '回复邮件', height: 80 }), 'low');
  assert.equal(cognitiveLoadFor({ tag: '核心攻坚', height: 80 }), 'high');
  assert.equal(cognitiveLoadFor({ tag: '其他', height: 120 }), 'high');
  assert.equal(cognitiveLoadFor({ tag: '其他', height: 40 }), 'medium');
  assert.equal(cognitiveLoadFor({ tag: '其他', height: 13.3 }), 'low');
});

test('tags map to localized labels and unknown tags stay readable', () => {
  assert.equal(tagLabel('Deep Work'), '深度工作');
  assert.equal(tagLabel('Micro Task'), '微任务');
  assert.equal(tagLabel('核心攻坚'), '核心攻坚');
  assert.equal(tagLabel(''), '未分类');
});

test('block duration derives minutes from the height scale (80 == 60min)', () => {
  assert.equal(durationMinutes({ height: 80 }), 60);
  assert.equal(durationMinutes({ height: 40 }), 30);
  assert.equal(durationMinutes({ height: 0 }), 45); // 0 falls back to the 60.0 default height.
  assert.equal(durationMinutes({ height: 1.3 }), 1);
});
