import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import vm from 'node:vm';
import test from 'node:test';

const context = vm.createContext({ Date, Intl, console });
vm.runInContext(await readFile(new URL('../../web/stitch/calendar.js', import.meta.url), 'utf8'), context);
const { dayKey, parseDay, addDays, addMonths, visibleRange, occurrences, layoutEvents, countConflicts, ganttRows } = context.StitchCalendar;
const record = (id, day, hour, minute, minutes, extra = {}) => ({ id, title: id, day, time: { hour, minute }, height: minutes * 80 / 60, ...extra });

test('course cards recover classrooms from imported and explicitly labelled notes without exposing unrelated notes', () => {
  const room = context.StitchCalendar.classroomFor;
  assert.equal(room({ tag: '上课学习', description: '王老师 · B座507' }), 'B座507');
  assert.equal(room({ tag: '上课学习', description: '教师：李老师\n上课教室：三教 204\n请带教材' }), '三教 204');
  assert.equal(room({ tag: '上课学习', description: 'Room 204' }), 'Room 204');
  assert.equal(room({ tag: '上课学习', description: '复习资料 · C座302 · 李老师' }), 'C座302');
  assert.equal(room({ tag: '上课学习', description: '王老师 · 体育馆' }), '体育馆');
  assert.equal(room({ tag: '上课学习', description: '王老师' }), '');
  assert.equal(room({ tag: '上课学习', description: '请提前阅读资料' }), '');
  assert.equal(room({ tag: '工作会议', description: '地点：会议室 204' }), '');
  assert.equal(room({ tag: '上课学习' }), '');
});

test('local date keys validate dates and keep local days across month and year boundaries', () => {
  assert.equal(dayKey(new Date(2026, 9, 29, 0, 5)), '2026-10-29');
  assert.equal(parseDay('2026-02-30'), null);
  assert.equal(dayKey(addDays(parseDay('2026-12-31'), 1)), '2027-01-01');
  assert.equal(dayKey(addDays(parseDay('2024-02-28'), 1)), '2024-02-29');
  assert.equal(dayKey(addMonths(parseDay('2026-01-31'), 1)), '2026-02-28');
});

test('week starts Monday and the month grid includes six complete weeks', () => {
  const week = visibleRange('week', '2027-01-03');
  assert.equal(week.start, '2026-12-28'); assert.equal(week.end, '2027-01-03');
  const month = visibleRange('month', '2026-02-17');
  assert.equal(month.start, '2026-01-26'); assert.equal(month.days.length, 42);
  assert.equal(visibleRange('day', '2026-10-29').days.length, 1);
});

test('recurrences respect start, cutoff, clamped month-days and original ids', () => {
  const items = [record('daily', '2026-10-01', 9, 0, 30, { repeat: 'daily', repeatUntil: '2026-10-03' }), record('weekly', '2026-09-28', 10, 0, 60, { repeat: 'weekly' }), record('monthly', '2026-01-31', 11, 0, 60, { repeat: 'monthly' })];
  const october = occurrences(items, '2026-10-01', '2026-10-31');
  assert.equal(october.filter(e => e.id === 'daily').length, 3);
  assert.equal(october.filter(e => e.id === 'weekly').length, 4);
  assert.equal(october.find(e => e.id === 'monthly').day, '2026-10-28');
  assert.equal(occurrences(items, '2026-02-01', '2026-02-28').find(e => e.id === 'monthly').day, '2026-02-28');
  assert.equal(items[0].day, '2026-10-01');
});

test('legacy records with no anchored day stay visible on each day', () => {
  const shown = occurrences([record('floating', null, 9, 0, 60)], '2026-10-28', '2026-10-29');
  assert.equal(shown.length, 2);
});

test('overnight records split into visible day segments, including the previous day tail', () => {
  const items = [record('night', '2026-10-28', 23, 30, 120)];
  const shown = occurrences(items, '2026-10-29', '2026-10-29');
  assert.equal(shown.length, 1); assert.equal(shown[0].start, 0); assert.equal(shown[0].end, 90);
  assert.equal(shown[0].sourceDay, '2026-10-28');
});

test('overlapping events receive separate columns while adjacent events share one', () => {
  const input = [{ id: 'a', start: 540, end: 630 }, { id: 'b', start: 570, end: 600 }, { id: 'c', start: 630, end: 660 }];
  const output = layoutEvents(input);
  assert.equal(output[0].columns, 2); assert.notEqual(output[0].column, output[1].column);
  assert.equal(output[2].columns, 1); assert.equal(input[0].column, undefined);
  assert.equal(countConflicts(input), 1);
});

test('Gantt merges overnight segments, clips visible week boundaries and preserves recurrence rows', () => {
  const range = visibleRange('gantt', '2026-10-29');
  assert.equal(range.start, '2026-10-26'); assert.equal(range.end, '2026-11-01');
  const items = [record('night', '2026-10-28', 23, 30, 120),
    record('before', '2026-10-25', 23, 30, 120), record('after', '2026-11-01', 23, 30, 120),
    record('daily', '2026-10-26', 9, 0, 30, { repeat: 'daily', repeatUntil: '2026-10-28' })];
  const rows = ganttRows(occurrences(items, range.start, range.end), range.start);
  const night = rows.find(r => r.event.id === 'night');
  assert.equal(rows.filter(r => r.event.id === 'night').length, 1);
  assert.equal(night.minutes, 120); assert.equal(night.end - night.start, 120);
  assert.equal(night.event.day, '2026-10-28'); assert.equal(night.endEvent.day, '2026-10-29');
  assert.equal(rows.find(r => r.event.id === 'before').start, 0);
  assert.equal(rows.find(r => r.event.id === 'before').minutes, 90);
  assert.equal(rows.find(r => r.event.id === 'after').end, 7 * 1440);
  assert.equal(rows.filter(r => r.event.id === 'daily').length, 3);
  assert.ok(rows.every(r => r.start >= 0 && r.end <= 7 * 1440));
});
