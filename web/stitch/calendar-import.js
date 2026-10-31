((scope) => {
  const pad = value => String(value).padStart(2, '0');
  const clamp = (value, min, max) => Math.max(min, Math.min(max, value));
  const dayKey = date => `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;

  function parseDate(value) {
    if (value instanceof Date && !Number.isNaN(value.valueOf())) return dayKey(value);
    const raw = String(value ?? '').trim().replace(/[年月]/g, '-').replace(/日/g, '').replace(/[/.]/g, '-');
    const match = raw.match(/^(\d{4})-(\d{1,2})-(\d{1,2})$/);
    if (!match) return null;
    const date = new Date(Number(match[1]), Number(match[2]) - 1, Number(match[3]), 12);
    return date.getFullYear() === Number(match[1]) && date.getMonth() === Number(match[2]) - 1 && date.getDate() === Number(match[3]) ? dayKey(date) : null;
  }

  function parseTime(value) {
    if (value instanceof Date && !Number.isNaN(value.valueOf())) return { hour: value.getHours(), minute: value.getMinutes() };
    if (value && typeof value === 'object') value = `${value.hour}:${value.minute}`;
    const match = String(value ?? '').trim().match(/^(\d{1,2})(?::|：)(\d{1,2})(?::\d{2})?$/);
    if (!match) return null;
    const hour = Number(match[1]), minute = Number(match[2]);
    if (hour > 23 || minute > 59) return null;
    return { hour, minute };
  }

  function minutesBetween(start, end) {
    if (!end) return null;
    const startMinutes = start.hour * 60 + start.minute;
    const endTime = parseTime(end);
    if (!endTime) return null;
    let duration = endTime.hour * 60 + endTime.minute - startMinutes;
    if (duration <= 0) duration += 1440;
    return duration;
  }

  function headerName(value) {
    return String(value ?? '').trim().toLowerCase().replace(/[\s_\-（）()]/g, '');
  }

  function field(row, names) {
    const keys = Object.keys(row);
    const key = keys.find(candidate => names.includes(headerName(candidate)));
    return key == null ? '' : row[key];
  }

  function normalizeRow(row, index = 0) {
    const title = String(field(row, ['title', 'name', 'subject', '课程', '课程名称', '日程', '标题']) || '').trim();
    const day = parseDate(field(row, ['date', 'day', '日期', '上课日期', '开始日期']));
    const start = parseTime(field(row, ['start', 'starttime', 'time', '开始', '开始时间', '时间']));
    if (!title || !day || !start) throw new Error(`第 ${index + 1} 行缺少标题、日期或开始时间`);
    const endValue = field(row, ['end', 'endtime', '结束', '结束时间']);
    const durationValue = field(row, ['duration', 'durationminutes', 'minutes', '时长', '分钟']);
    const duration = durationValue !== '' ? Number(durationValue) : endValue !== '' ? minutesBetween(start, endValue) : row.height ? Number(row.height) * 60 / 80 : 60;
    if (!Number.isFinite(duration) || duration <= 0 || duration > 10080) throw new Error(`第 ${index + 1} 行时长无效（应为 1 至 10080 分钟）`);
    return {
      ...(field(row, ['id', 'uid', '编号']) ? { id: String(field(row, ['id', 'uid', '编号'])) } : {}),
      title, day, time: start, height: Math.round(clamp(duration, 1, 10080) * 80 / 60),
      tag: String(field(row, ['tag', 'category', 'categories', '标签', '分类', '课程类别']) || '日程').trim() || '日程',
      ...([field(row, ['description', 'note', 'notes', '备注', '说明']), field(row, ['地点', 'location', '教室']), field(row, ['teacher', '教师', '老师'])].some(Boolean) ? { description: [...new Set([field(row, ['description', 'note', 'notes', '备注', '说明']), field(row, ['地点', 'location', '教室']), field(row, ['teacher', '教师', '老师'])].filter(Boolean))].join(' · ') } : {}),
    };
  }

  function delimitedTable(text) {
    const source = String(text ?? '').replace(/^\ufeff/, '');
    const delimiter = source.split(/\r?\n/, 1)[0].includes('\t') ? '\t' : ',';
    const rows = [], cells = [];
    let quoted = false, value = '';
    for (let i = 0; i < source.length; i += 1) {
      const char = source[i], next = source[i + 1];
      if (char === '"' && quoted && next === '"') { value += '"'; i += 1; continue; }
      if (char === '"') { quoted = !quoted; continue; }
      if (!quoted && char === delimiter) { cells.push(value); value = ''; continue; }
      if (!quoted && (char === '\n' || char === '\r')) {
        if (char === '\r' && next === '\n') i += 1;
        cells.push(value); value = '';
        const line = cells.splice(0);
        if (line.some(cell => String(cell).trim())) rows.push(line);
        continue;
      }
      value += char;
    }
    if (quoted) throw new Error('CSV 文件包含未闭合的引号');
    if (value || cells.length) { cells.push(value); if (cells.some(cell => String(cell).trim())) rows.push(cells); }
    return rows;
  }

  function parseDelimited(text) {
    const rows = delimitedTable(text);
    if (rows.length < 2) return [];
    const headers = rows.shift().map((header, index) => String(header || `column${index + 1}`).trim());
    return rows.map((values, index) => normalizeRow(Object.fromEntries(headers.map((header, column) => [header, values[column] ?? ''])), index));
  }

  function normalizeJson(input) {
    const rows = Array.isArray(input) ? input : input?.events || input?.schedules || input?.data;
    if (!Array.isArray(rows)) throw new Error('JSON 必须是日程数组或包含 events/schedules/data 数组');
    return rows.map((row, index) => normalizeRow(row, index));
  }

  function unescapeIcs(value) {
    return String(value ?? '').replace(/\\n/gi, '\n').replace(/\\([,;\\])/g, '$1');
  }

  function parseIcs(text) {
    if (!/BEGIN:VCALENDAR/i.test(text)) throw new Error('ICS 文件缺少 BEGIN:VCALENDAR');
    const lines = String(text).replace(/\r\n/g, '\n').replace(/\r/g, '\n').split('\n');
    const unfolded = [];
    for (const line of lines) line.match(/^[ \t]/) && unfolded.length ? unfolded[unfolded.length - 1] += line.slice(1) : unfolded.push(line);
    const events = [], current = {};
    let open = false, nested = 0;
    for (const line of unfolded) {
      if (line === 'BEGIN:VEVENT') { if (open) throw new Error('ICS 包含嵌套事件'); open = true; nested = 0; continue; }
      if (open && line.startsWith('BEGIN:')) { nested++; continue; }
      if (open && nested > 0) { if (line.startsWith('END:')) nested--; continue; }
      if (line === 'END:VEVENT') {
        if (!open) throw new Error('ICS 事件边界不完整');
        if (current.RRULE || current.RDATE || current.EXDATE || current['RECURRENCE-ID']) throw new Error('此 ICS 包含重复规则，请先从原日历导出展开后的独立日程，避免遗漏停课或例外日期');
        const startRaw = current.DTSTART, title = unescapeIcs(current.SUMMARY);
        if (current.startTimezone && current.startTimezone !== Intl.DateTimeFormat().resolvedOptions().timeZone) throw new Error(`ICS 使用 ${current.startTimezone} 时区，请先导出为 UTC（Z 结尾）或本地时间格式`);
        if (current.endTimezone && current.endTimezone !== Intl.DateTimeFormat().resolvedOptions().timeZone) throw new Error(`ICS 结束时间使用 ${current.endTimezone} 时区，请先导出为 UTC 或本地时间格式`);
        if (current.DTEND && /Z$/.test(startRaw) !== /Z$/.test(current.DTEND)) throw new Error('ICS 起止时间使用不同的时区基准，请先导出为统一的 UTC 或本地时间格式');
        const match = String(startRaw || '').match(/^(\d{4})(\d{2})(\d{2})T?(\d{2})?(\d{2})?/);
        if (!match || !title) throw new Error('ICS 事件必须包含 DTSTART 和 SUMMARY');
        const start = { hour: Number(match[4] || 0), minute: Number(match[5] || 0) };
        let day = `${match[1]}-${match[2]}-${match[3]}`;
        if (!parseDate(day) || start.hour > 23 || start.minute > 59) throw new Error('ICS 日期或时间无效');
        const endRaw = current.DTEND?.replace(/Z$/, '');
        const durationMatch = current.DURATION?.match(/^P(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?)?$/i);
        const icsInstant = raw => {
          const parts = String(raw || '').match(/^(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2})?Z?)?$/);
          if (!parts || !parseDate(`${parts[1]}-${parts[2]}-${parts[3]}`) || Number(parts[4] || 0) > 23 || Number(parts[5] || 0) > 59) return NaN;
          return Date.UTC(Number(parts[1]), Number(parts[2]) - 1, Number(parts[3]), Number(parts[4] || 0), Number(parts[5] || 0), Number(parts[6] || 0));
        };
        if (!Number.isFinite(icsInstant(startRaw))) throw new Error('ICS 开始时间无效');
        const duration = current.DTEND ? (icsInstant(current.DTEND) - icsInstant(startRaw)) / 60000
          : durationMatch ? Number(durationMatch[1] || 0) * 1440 + Number(durationMatch[2] || 0) * 60 + Number(durationMatch[3] || 0) : /T/.test(startRaw) ? 60 : 1440;
        if (!Number.isFinite(duration) || duration <= 0 || duration > 10080) throw new Error('ICS 结束时间或时长无效（最多七天）');
        if (/Z$/.test(startRaw)) {
          const utc = new Date(`${day}T${pad(start.hour)}:${pad(start.minute)}:00Z`);
          day = dayKey(utc); start.hour = utc.getHours(); start.minute = utc.getMinutes();
        }
        events.push({ ...(current.UID ? { id: current.UID } : {}), title, day, time: start, height: Math.round(clamp(duration, 1, 10080) * 80 / 60), tag: unescapeIcs(current.CATEGORIES || '日程'), ...((current.DESCRIPTION || current.LOCATION) ? { description: [current.DESCRIPTION, current.LOCATION].filter(Boolean).map(unescapeIcs).join(' · ') } : {}) });
        Object.keys(current).forEach(key => delete current[key]); open = false; continue;
      }
      if (open && line.includes(':')) {
        const [name, ...rest] = line.split(':'); current[name.split(';', 1)[0].toUpperCase()] = rest.join(':');
        if (/^DTSTART;/i.test(name)) current.startTimezone = name.match(/TZID=([^;]+)/i)?.[1]?.replace(/^"|"$/g, '');
        if (/^DTEND;/i.test(name)) current.endTimezone = name.match(/TZID=([^;]+)/i)?.[1]?.replace(/^"|"$/g, '');
      }
    }
    if (open) throw new Error('ICS 事件未闭合');
    return events;
  }

  function parseWeekExpression(expression) {
    const match = String(expression || '').replace(/[－—]/g, '-').match(/^(.+?)(?:\[([^\]]+)\])?$/);
    if (!match) return [];
    const weeks = new Set();
    for (const token of match[1].split(/[,，]/)) {
      const parts = token.trim().split(/\s*[-~至]\s*/).map(Number);
      if (!Number.isInteger(parts[0]) || parts[0] < 1 || parts[0] > 60) throw new Error('课程周次应为 1 至 60');
      const end = Number.isFinite(parts[1]) ? parts[1] : parts[0];
      if (end < parts[0] || end > 60) throw new Error('课程周次范围无效');
      for (let week = parts[0]; week <= end; week += 1) weeks.add(week);
    }
    const mode = match[2] || '';
    return [...weeks].filter(week => !/单周|奇/.test(mode) || week % 2 === 1).filter(week => !/双周|偶/.test(mode) || week % 2 === 0).sort((a, b) => a - b);
  }

  function parseCourseMatrix(matrix) {
    if (!Array.isArray(matrix) || !matrix.length) throw new Error('工作表为空');
    const weekdayRow = matrix.findIndex(row => (row || []).filter(cell => /星期[一二三四五六日天]/.test(String(cell || ''))).length >= 5);
    if (weekdayRow < 0) throw new Error('未识别到按星期排列的课表表头');
    const weekdayColumns = new Map();
    for (let column = 0; column < (matrix[weekdayRow] || []).length; column += 1) {
      const match = String(matrix[weekdayRow][column] || '').match(/星期([一二三四五六日天])/);
      if (match) weekdayColumns.set(column, ({ 一: 1, 二: 2, 三: 3, 四: 4, 五: 5, 六: 6, 日: 7, 天: 7 })[match[1]]);
    }
    const courses = [];
    for (let row = weekdayRow + 1; row < matrix.length; row += 1) {
      const sectionText = String(matrix[row]?.[0] || '').trim().replace(/[－—~至]/g, '-');
      const sectionMatch = sectionText.match(/(\d+\s*-\s*\d+|\d+)/);
      if (!sectionMatch) continue;
      const sections = sectionMatch[1].replace(/\s/g, '');
      for (const [column, weekday] of weekdayColumns) {
        const raw = String(matrix[row]?.[column] || '').trim();
        if (!raw) continue;
        const blocks = raw.split(/\n\s*\n+/).map(block => block.split(/\r?\n/).map(line => line.trim()).filter(Boolean)).filter(lines => lines.length);
        for (let blockIndex = 0; blockIndex < blocks.length; blockIndex += 1) {
          const lines = blocks[blockIndex];
          const weekIndex = lines.findIndex(line => /^\d+(?:\s*[-~至－—]\s*\d+)?(?:\s*[,，、]\s*\d+(?:\s*[-~至－—]\s*\d+)?)*(?:\s*\[(?:单周|双周|周|奇数周|偶数周)\])?$/.test(line));
          if (weekIndex < 1) continue;
          const title = lines.slice(0, weekIndex).find(line => !/^\d+$/.test(line));
          if (!title) continue;
          courses.push({
            id: `course-r${row + 1}-c${column + 1}-${blockIndex + 1}`,
            title,
            weekday,
            sections,
            teacher: lines[weekIndex - 1] || '',
            weeks: lines[weekIndex],
            location: lines.slice(weekIndex + 1).find(line => line && !/^\d+$/.test(line)) || '',
            tag: '上课学习',
          });
        }
      }
    }
    if (!courses.length) throw new Error('未识别到包含课程名称和周次的课表单元格');
    return courses;
  }

  function expandCourse(course, options) {
    const firstMonday = parseDate(options?.firstMonday);
    if (!firstMonday) throw new Error('课表必须指定学期第一周周一');
    const weekday = Number(course.weekday);
    if (!Number.isInteger(weekday) || weekday < 1 || weekday > 7) throw new Error('课程星期必须是 1-7');
    const sections = String(course.sections || '').trim();
    const sectionTime = options?.sectionTimes?.[sections];
    if (!sectionTime) throw new Error(`未配置第 ${sections} 节的时间`);
    const first = new Date(`${firstMonday}T12:00:00`);
    if (first.getDay() !== 1) throw new Error('学期第一周日期必须是周一');
    if (!Number.isInteger(sectionTime.hour) || sectionTime.hour < 0 || sectionTime.hour > 23 || !Number.isInteger(sectionTime.minute) || sectionTime.minute < 0 || sectionTime.minute > 59 || !Number.isFinite(sectionTime.minutes) || sectionTime.minutes < 1 || sectionTime.minutes > 1440) throw new Error(`第 ${sections} 节时间无效`);
    const weeks = parseWeekExpression(course.weeks);
    const output = [];
    for (const week of weeks) {
      const date = new Date(first); date.setDate(first.getDate() + (week - 1) * 7 + weekday - 1);
      const day = dayKey(date);
      output.push({ id: `${course.id || course.title}-${day}`, title: String(course.title || '未命名课程').trim(), day, time: { hour: sectionTime.hour, minute: sectionTime.minute }, height: Math.round(sectionTime.minutes * 80 / 60), tag: course.tag || '上课学习', description: [course.teacher, course.location].filter(Boolean).join(' · ') });
    }
    return output;
  }

  function filterDuplicates(rows, existingIds) { return rows.filter(row => !existingIds.has(row.id)); }
  scope.StitchCalendarImport = { parseDate, parseTime, delimitedTable, parseDelimited, normalizeJson, parseIcs, parseWeekExpression, parseCourseMatrix, expandCourse, filterDuplicates, normalizeRow };
})(typeof window === 'undefined' ? globalThis : window);
