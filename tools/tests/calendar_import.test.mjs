import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import vm from 'node:vm';
import test from 'node:test';
import { createRequire } from 'node:module';

const context = vm.createContext({ Date, Intl, console, URL, TextDecoder });
vm.runInContext(await readFile(new URL('../../web/stitch/calendar-import.js', import.meta.url), 'utf8'), context);
const importer = context.StitchCalendarImport;
const plain = value => JSON.parse(JSON.stringify(value));

test('normalizes BOM CSV and quoted fields into schedule rows', () => {
  const rows = plain(importer.parseDelimited('\ufefftitle,date,start,end,tag\n"数据库,复习",2026-09-01,09:00,10:30,上课学习'));
  assert.deepEqual(rows, [{ title: '数据库,复习', day: '2026-09-01', time: { hour: 9, minute: 0 }, height: 120, tag: '上课学习' }]);
});

test('normalizes JSON and ICS records with duration and description', () => {
  assert.deepEqual(plain(importer.normalizeJson([{ title: '答辩', date: '2026-09-02', startTime: '14:00', duration: 90, note: 'B座' }])), [
    { title: '答辩', day: '2026-09-02', time: { hour: 14, minute: 0 }, height: 120, tag: '日程', description: 'B座' },
  ]);
  const ics = 'BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nUID:a1\r\nDTSTART:20260903T080000\r\nDTEND:20260903T093000\r\nSUMMARY:早课\r\nDESCRIPTION:李老师\\nB座\r\nCATEGORIES:上课学习\r\nEND:VEVENT\r\nEND:VCALENDAR';
  assert.deepEqual(plain(importer.parseIcs(ics)), [{ id: 'a1', title: '早课', day: '2026-09-03', time: { hour: 8, minute: 0 }, height: 120, tag: '上课学习', description: '李老师\nB座' }]);
});

test('expands course weeks, alternating weeks, and section time mapping', () => {
  const rows = plain(importer.expandCourse({ id: 'course-1', title: '分布式系统', tag: '上课学习', weekday: 2, sections: '3-4', weeks: '1-4[单周]', teacher: '余老师', location: 'B座503' }, {
    firstMonday: '2026-09-07', sectionTimes: { '3-4': { hour: 10, minute: 0, minutes: 90 } },
  }));
  assert.deepEqual(rows.map(row => row.day), ['2026-09-08', '2026-09-22']);
  assert.equal(rows[0].height, 120);
  assert.match(rows[0].description, /余老师/);
  assert.match(rows[0].description, /B座503/);
});

test('parses a weekday-by-section course matrix with multiple courses in one cell', () => {
  const matrix = [
    ['中南大学 学生个人课表'],
    ['学年学期：2026-2027-1'],
    ['', '星期日', '星期一', '星期二', '星期三', '星期四', '星期五', '星期六'],
    ['1－2', '', '', '', '', '', '', ''],
    ['3－4', '', '\n多模态数据处理与应用\n王磊(副教授)\n1-16[周]\nB座507\n', '',
      '\n分布式系统与云计算\n余腊生(教授)\n1-16[单周]\nB座503\n', '',
      '\n数据仓库与数据挖掘\n龙军(教授)\n1-16[单周]\nB座502\n\n数据仓库与数据挖掘\n龙军(教授)\n10[周]\nB座402\n', ''],
  ];
  assert.deepEqual(plain(importer.parseCourseMatrix(matrix)), [
    { id: 'course-r5-c3-1', title: '多模态数据处理与应用', weekday: 1, sections: '3-4', teacher: '王磊(副教授)', weeks: '1-16[周]', location: 'B座507', tag: '上课学习' },
    { id: 'course-r5-c5-1', title: '分布式系统与云计算', weekday: 3, sections: '3-4', teacher: '余腊生(教授)', weeks: '1-16[单周]', location: 'B座503', tag: '上课学习' },
    { id: 'course-r5-c7-1', title: '数据仓库与数据挖掘', weekday: 5, sections: '3-4', teacher: '龙军(教授)', weeks: '1-16[单周]', location: 'B座502', tag: '上课学习' },
    { id: 'course-r5-c7-2', title: '数据仓库与数据挖掘', weekday: 5, sections: '3-4', teacher: '龙军(教授)', weeks: '10[周]', location: 'B座402', tag: '上课学习' },
  ]);
});

test('filters exact existing IDs without fuzzy title replacement', () => {
  const rows = [{ id: 'import-a', title: '同名课程', day: '2026-09-01', time: { hour: 9, minute: 0 } }, { id: 'import-b', title: '新课', day: '2026-09-02', time: { hour: 9, minute: 0 } }];
  assert.deepEqual(plain(importer.filterDuplicates(rows, new Set(['import-a']))), [rows[1]]);
});

test('rejects invalid dates, times, duration and unbounded weeks', () => {
  for (const record of [
    { title: '无效日期', date: '2026-02-30', start: '09:00' },
    { title: '无效时刻', date: '2026-09-01', start: '24:00' },
    { title: '无效时长', date: '2026-09-01', start: '09:00', duration: -5 },
    { title: '错误结束', date: '2026-09-01', start: '09:00', end: 'bad' },
  ]) assert.throws(() => importer.normalizeRow(record));
  assert.throws(() => importer.parseWeekExpression('1-99999999[周]'), /周次/);
  assert.deepEqual(plain(importer.parseWeekExpression('3-4,6-9[周]')), [3, 4, 6, 7, 8, 9]);
  assert.deepEqual(plain(importer.parseWeekExpression('1-6[双周]')), [2, 4, 6]);
  assert.throws(() => importer.expandCourse({ weekday: 1, sections: '1-2', weeks: '1[周]' }, { firstMonday: '2026-09-08', sectionTimes: { '1-2': { hour: 8, minute: 0, minutes: 90 } } }), /周一/);
});

test('handles empty input, TSV, embedded quotes and newline without swallowing empty lines', () => {
  assert.deepEqual(plain(importer.parseDelimited('')), []);
  assert.deepEqual(plain(importer.parseDelimited('标题\t日期\t开始时间\t结束时间\n开会\t2026/9/1\t9:00\t10:00'))[0].time, { hour: 9, minute: 0 });
  assert.equal(importer.parseDelimited('title,date,start\n"a ""quoted""\nname",2026-09-01,09:00')[0].title, 'a "quoted"\nname');
  assert.throws(() => importer.parseDelimited('title,date,start\n"unclosed'), /引号/);
  const rows = importer.delimitedTable('title,date,start\n\nnext,2026-09-01,09:00');
  assert.equal(rows.length, 2);
  assert.deepEqual(plain(rows[1]), ['next', '2026-09-01', '09:00']);
});

test('normalizes persisted schedule shape and preserves location plus notes', () => {
  const row = plain(importer.normalizeJson([{ title: '课程', day: '2026-09-01', time: { hour: 9, minute: 5 }, height: 120, description: '说明', location: 'B座', teacher: '王老师' }]))[0];
  assert.equal(row.height, 120);
  assert.equal(row.description, '说明 · B座 · 王老师');
});

test('ICS preserves multiday duration, all-day bounds, and rejects unsupported recurrence/timezones', () => {
  const ics = lines => ['BEGIN:VCALENDAR', 'BEGIN:VEVENT', 'SUMMARY:日程', ...lines, 'END:VEVENT', 'END:VCALENDAR'].join('\r\n');
  assert.equal(importer.parseIcs(ics(['DTSTART:20260901T230000', 'DTEND:20260903T010000']))[0].height, 26 * 80);
  assert.equal(importer.parseIcs(ics(['DTSTART;VALUE=DATE:20260901', 'DTEND;VALUE=DATE:20260903']))[0].height, 48 * 80);
  assert.throws(() => importer.parseIcs(ics(['DTSTART:20260901T090000', 'RRULE:FREQ=WEEKLY'])), /重复规则/);
  assert.throws(() => importer.parseIcs(ics(['DTSTART;TZID=Unknown/Zone:20260901T090000'])), /时区/);
  assert.throws(() => importer.parseIcs(ics(['DTSTART:20260230T090000'])), /日期|开始时间/);
  assert.throws(() => importer.parseIcs(ics(['DTSTART:20260901T090000Z', 'DTEND;TZID=America/New_York:20260901T100000'])), /时区/);
  const reminder = importer.parseIcs(ics(['DTSTART:20260901T090000', 'DESCRIPTION:王老师 · B座', 'BEGIN:VALARM', 'ACTION:DISPLAY', 'TRIGGER:-PT10M', 'DESCRIPTION:Reminder', 'SUMMARY:错误标题', 'END:VALARM']));
  assert.equal(reminder[0].description, '王老师 · B座'); assert.equal(reminder[0].title, '日程');
});

test('self-hosted SheetJS reads legacy XLS and XLSX without remote requests', () => {
  const XLSX = createRequire(import.meta.url)('../../web/stitch/assets/vendor/xlsx.full.min.js');
  const matrix = [['', '星期日', '星期一', '星期二', '星期三', '星期四', '星期五', '星期六'],
    ['3－4', '', '\n多模态数据处理与应用\n王磊(副教授)\n1-16[周]\nB座507\n', '', '', '', '', '']];
  for (const bookType of ['biff8', 'xlsx']) {
    const book = XLSX.utils.book_new(); XLSX.utils.book_append_sheet(book, XLSX.utils.aoa_to_sheet(matrix), '课表');
    const bytes = XLSX.write(book, { type: 'buffer', bookType });
    const roundtrip = XLSX.read(bytes, { type: 'buffer' });
    const courses = importer.parseCourseMatrix(XLSX.utils.sheet_to_json(roundtrip.Sheets['课表'], { header: 1, defval: '' }));
    assert.equal(courses.length, 1); assert.equal(courses[0].weekday, 1); assert.equal(courses[0].location, 'B座507');
  }
});
