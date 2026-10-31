((scope) => {
  const MAX_EVENTS = 2000, MAX_ROWS = 5000, MAX_COLUMNS = 64;
  const fields = [
    ['title', '标题 / 课程名称', ['title', 'name', 'subject', '课程', '课程名称', '日程', '标题']],
    ['date', '日期', ['date', 'day', '日期', '上课日期', '开始日期']],
    ['start', '开始时间', ['start', 'starttime', 'time', '开始', '开始时间', '时间']],
    ['end', '结束时间', ['end', 'endtime', '结束', '结束时间']],
    ['duration', '时长（分钟）', ['duration', 'durationminutes', 'minutes', '时长', '分钟']],
    ['tag', '属性标签', ['tag', 'category', 'categories', '标签', '分类', '课程类别']],
    ['description', '备注', ['description', 'note', 'notes', '备注', '说明']],
    ['location', '地点 / 教室', ['location', '地点', '教室']],
    ['teacher', '教师', ['teacher', '教师', '老师']],
  ];
  const headerKey = value => String(value).toLowerCase().replace(/[\s_\-（）()]/g, '');
  const fingerprint = value => {
    let left = 2166136261, right = 5381;
    for (let i = 0; i < value.length; i++) {
      left = Math.imul(left ^ value.charCodeAt(i), 16777619);
      right = Math.imul(right, 33) ^ value.charCodeAt(i);
    }
    return (left >>> 0).toString(16).padStart(8, '0') + (right >>> 0).toString(16).padStart(8, '0');
  };
  const clock = time => `${String(time.hour).padStart(2, '0')}:${String(time.minute).padStart(2, '0')}`;

  function mount(doc, { request, identity, themeFor, onImported }) {
    const parser = scope.StitchCalendarImport, XLSX = scope.XLSX;
    const controls = scope.StitchTimePicker.mount(doc);
    const get = id => doc.getElementById(id);
    const account = identity();
    let disposed = false, generation = 0, workbook = null, bytes = null, extension = '', courses = [], headers = [], table = [];
    let rows = [], errors = [], existingIds = new Set(), selected = new Set(), userId = '', pageSize = 100, busy = false, confirmed = false;
    const current = turn => !disposed && account === identity() && turn === generation;
    function status(message, error = false) {
      get('import-status').textContent = message;
      get('import-status').style.color = error ? '#ba1a1a' : '';
    }
    function clearPreview() {
      rows = []; errors = []; selected.clear(); confirmed = false;
      get('import-preview-group').hidden = true;
      get('import-confirm').disabled = true;
      get('import-preview').replaceChildren();
    }
    function setBusy(value) {
      busy = value;
      controls.setBusy(value);
      get('import-file-button').disabled = value;
      for (const id of ['import-file', 'import-sheet', 'import-encoding', 'import-first-monday', 'import-course-preview', 'import-map-preview']) get(id).disabled = value;
      for (const node of doc.querySelectorAll('#import-section-times input, #import-mapping select, #import-preview input, #import-select-all')) node.disabled = value || node.dataset.duplicate === 'true';
      get('import-confirm').disabled = value || !selected.size || confirmed;
      get('import-confirm').textContent = value ? '处理中…' : `确认导入${selected.size ? `（${selected.size} 条）` : ''}`;
    }
    function updateCount() {
      get('import-count').textContent = `${rows.length} 条日程 · 已选 ${selected.size} 条`;
      const available = rows.filter(row => !row.duplicate).length;
      get('import-select-all').checked = available > 0 && selected.size === available;
      get('import-select-all').indeterminate = selected.size > 0 && selected.size < available;
      get('import-select-all').disabled = busy || available === 0;
      get('import-confirm').disabled = busy || !selected.size || confirmed;
      get('import-confirm').textContent = `确认导入${selected.size ? `（${selected.size} 条）` : ''}`;
    }
    function renderRows() {
      const fragment = doc.createDocumentFragment();
      for (const row of rows.slice(0, pageSize)) {
        const label = doc.createElement('label'); label.className = 'import-preview-row';
        const checkbox = doc.createElement('input'); checkbox.type = 'checkbox'; checkbox.checked = selected.has(row.id);
        checkbox.disabled = row.duplicate || busy; checkbox.dataset.duplicate = String(row.duplicate); checkbox.setAttribute('aria-label', `导入 ${row.title} ${row.day}`);
        checkbox.addEventListener('change', () => { checkbox.checked ? selected.add(row.id) : selected.delete(row.id); updateCount(); });
        const content = doc.createElement('div'); content.style.minWidth = '0';
        const title = doc.createElement('strong'); title.textContent = row.title;
        const meta = doc.createElement('small'); meta.textContent = `${row.day} ${clock(row.time)} · ${Math.round(row.height * 60 / 80)} 分钟`;
        const tag = doc.createElement('span'), theme = themeFor(row);
        tag.textContent = row.tag; Object.assign(tag.style, { display: 'inline-block', background: theme.background, color: theme.title, borderRadius: '999px', padding: '3px 8px', fontSize: '11px', marginTop: '6px' });
        content.append(title, meta, tag);
        if (row.description) { const note = doc.createElement('small'); note.textContent = row.description; content.append(note); }
        if (row.duplicate) { const note = doc.createElement('small'); note.textContent = '已导入 · 自动跳过，保留日历中的修改'; content.append(note); }
        label.append(checkbox, content); fragment.append(label);
      }
      get('import-preview').replaceChildren(fragment);
      get('import-more').hidden = rows.length <= pageSize;
      updateCount();
    }
    async function preview(entries, invalid = []) {
      clearPreview();
      if (entries.length > MAX_EVENTS) throw new Error(`展开后超过 ${MAX_EVENTS} 条日程，请分批导入`);
      if (!entries.length) throw new Error(invalid.length ? invalid.slice(0, 5).join('；') : '文件中没有可导入的日程');
      const turn = ++generation;
      setBusy(true); status('正在核对账号日程…');
      try {
        const [user, existing] = await Promise.all([request('/auth/me'), request('/schedule')]);
        if (!current(turn)) return;
        userId = user.id;
        existingIds = new Set(existing.map(row => row.id));
        const seen = new Set();
        rows = entries.map(entry => {
          const id = `import-${userId}-${fingerprint(JSON.stringify([entry.id || '', entry.title, entry.day, entry.time, entry.height, entry.tag, entry.description || '']))}`;
          const duplicate = existingIds.has(entry.id) || existingIds.has(id) || seen.has(id); seen.add(id);
          return { ...entry, id, color: themeFor(entry).color, repeat: 'none', description: entry.description || '', duplicate };
        });
        selected = new Set(rows.filter(row => !row.duplicate).map(row => row.id)); errors = invalid;
        get('import-preview-group').hidden = false;
        get('import-errors').textContent = invalid.length ? `${invalid.length} 行未导入：${invalid.slice(0, 10).join('；')}` : '';
        pageSize = 100; renderRows();
        const duplicates = rows.filter(row => row.duplicate).length;
        status(`已生成 ${rows.length} 条日程${duplicates ? `，${duplicates} 条重复已跳过` : ''}。请核对日期、时间及备注后确认。`);
      } catch (error) { if (current(turn)) status(error.status === 401 ? '请先在“我的”中登录，再重新选择文件。' : error.message, true); }
      finally { if (current(turn)) setBusy(false); }
    }
    function tablePreview() {
      const mapping = Object.fromEntries([...get('import-mapping').querySelectorAll('select')].map(select => [select.dataset.field, select.value]));
      const valid = [], invalid = [];
      for (let i = 0; i < table.length; i++) {
        if (!table[i].some(value => String(value ?? '').trim())) continue;
        const source = Object.fromEntries(Object.entries(mapping).filter(([, index]) => index !== '').map(([key, index]) => [key, table[i][Number(index)] ?? '']));
        try { valid.push(parser.normalizeRow(source, i + 1)); } catch (error) { invalid.push(error.message); }
      }
      return preview(valid, invalid);
    }
    function configureTable(matrix) {
      if (!matrix.length || matrix.length > MAX_ROWS + 1 || Math.max(...matrix.map(row => row.length)) > MAX_COLUMNS) throw new Error(`表格最多支持 ${MAX_ROWS} 行、${MAX_COLUMNS} 列`);
      headers = matrix[0].map(value => String(value ?? '')); table = matrix.slice(1);
      get('import-mapping-group').hidden = false;
      get('import-mapping').replaceChildren();
      for (const [key, labelText, aliases] of fields) {
        const label = doc.createElement('label'); label.textContent = labelText;
        const select = doc.createElement('select'); select.dataset.field = key; select.setAttribute('aria-label', labelText);
        select.add(new Option(key === 'end' || key === 'duration' ? '未指定（默认 60 分钟）' : '未指定', ''));
        headers.forEach((header, i) => select.add(new Option(header || `第 ${i + 1} 列`, String(i))));
        const index = headers.findIndex(header => aliases.includes(headerKey(header))); select.value = index < 0 ? '' : String(index);
        select.addEventListener('change', () => { clearPreview(); status('字段对应已改变，请点击“更新预览”。'); });
        label.append(select); get('import-mapping').append(label);
      }
      get('import-mapping-group').open = ['title', 'date', 'start'].some(field => !get('import-mapping').querySelector(`[data-field="${field}"]`).value);
      return tablePreview();
    }
    function configureCourses(matrix) {
      courses = parser.parseCourseMatrix(matrix);
      get('import-course-options').hidden = false;
      get('import-course-summary').textContent = `识别 ${courses.length} 条课程安排，按周次展开到实际日期。`;
      get('import-section-times').replaceChildren();
      for (const sections of [...new Set(courses.map(course => course.sections))]) {
        const row = doc.createElement('div'); row.className = 'import-time-row'; row.dataset.sections = sections;
        const label = doc.createElement('span'); label.textContent = `第 ${sections} 节`;
        row.append(label);
        for (const kind of ['start', 'end']) {
          const input = doc.createElement('input'); input.type = 'time'; input.dataset.kind = kind; input.required = true;
          input.setAttribute('aria-label', `第 ${sections} 节${kind === 'start' ? '开始' : '结束'}时间`);
          input.addEventListener('input', () => { clearPreview(); status('课时已修改，请重新生成预览。'); }); row.append(controls.timeField(input));
        }
        get('import-section-times').append(row);
      }
      const notes = matrix.flat().filter(value => /^备注[:：]/.test(String(value).trim())).map(String);
      get('import-course-warnings').textContent = notes.length ? `以下备注未包含确定的星期与节次，请另行新增：${notes.join('；')}` : '';
      status('请确认学期第一周周一，并填写每组节次的开始与结束时间。');
    }
    async function processFile() {
      clearPreview(); courses = [];
      get('import-course-options').hidden = true; get('import-mapping-group').hidden = true;
      if (workbook) {
        const sheet = workbook.Sheets[get('import-sheet').value];
        const range = XLSX.utils.decode_range(sheet['!fullref'] || sheet['!ref'] || 'A1');
        if (range.e.r >= MAX_ROWS + 1 || range.e.c >= MAX_COLUMNS) throw new Error('工作表过大，请删去空白区域或分批导入');
        const matrix = XLSX.utils.sheet_to_json(sheet, { header: 1, defval: '', raw: true });
        if (matrix.some(row => row.filter(value => /星期[一二三四五六日天]/.test(String(value))).length >= 5)) configureCourses(matrix);
        else await configureTable(matrix);
      } else {
        const text = new TextDecoder(get('import-encoding').value, { fatal: true }).decode(bytes).replace(/^\ufeff/, '');
        if (extension === 'json') await preview(parser.normalizeJson(JSON.parse(text)));
        else if (extension === 'ics') await preview(parser.parseIcs(text));
        else await configureTable(parser.delimitedTable(text));
      }
    }
    async function safely(action) {
      try { await action(); } catch (error) { clearPreview(); status(error.message.includes('encoded data') ? '文本编码不匹配，请切换编码或另存为 UTF-8。' : error.message, true); setBusy(false); }
    }
    const handlers = [];
    function bind(id, event, action) {
      const node = get(id), handler = e => { e.stopPropagation(); safely(() => action(e)); };
      node.addEventListener(event, handler); handlers.push(() => node.removeEventListener(event, handler));
    }
    bind('import-file-button', 'click', () => get('import-file').click());
    bind('import-file', 'change', async () => {
      generation++; clearPreview(); workbook = null; bytes = null;
      get('import-workbook').hidden = true; get('import-course-options').hidden = true; get('import-mapping-group').hidden = true;
      const file = get('import-file').files[0];
      controls.setBusy(false);
      get('import-file-name').textContent = file?.name || '选择课表或日程文件';
      get('import-file-name').title = file?.name || '';
      get('import-file-meta').textContent = file ? `${file.name.split('.').pop().toUpperCase()} · ${file.size >= 1048576 ? (file.size / 1048576).toFixed(1) + ' MB' : Math.max(1, Math.ceil(file.size / 1024)) + ' KB'} · 本地文件` : '在本机解析，预览后确认导入';
      get('import-file-action').textContent = file ? '更换文件' : '选择文件';
      if (!file) { status('尚未选择文件。'); return; }
      extension = file.name.split('.').pop().toLowerCase();
      if (!['xls', 'xlsx', 'csv', 'tsv', 'json', 'ics'].includes(extension)) throw new Error('不支持此文件格式，请使用 XLS、XLSX、CSV、TSV、JSON 或 ICS');
      if (!file.size || file.size > 5 * 1024 * 1024) throw new Error('文件为空或大于 5 MB，请检查后分批导入');
      const turn = generation; setBusy(true); status('正在本地读取文件…');
      bytes = await file.arrayBuffer(); if (!current(turn)) return;
      get('import-encoding-group').hidden = !['csv', 'tsv'].includes(extension);
      if (['xls', 'xlsx'].includes(extension)) {
        workbook = XLSX.read(bytes, { type: 'array', cellDates: true, sheetRows: MAX_ROWS + 2 });
        get('import-sheet').replaceChildren(); workbook.SheetNames.forEach(name => get('import-sheet').add(new Option(name, name)));
        get('import-workbook').hidden = false;
      }
      await processFile(); if (current(generation)) setBusy(false);
    });
    bind('import-sheet', 'change', processFile); bind('import-encoding', 'change', processFile);
    bind('import-first-monday', 'input', () => { clearPreview(); status('学期日期已改变，请重新生成预览。'); });
    bind('import-map-preview', 'click', tablePreview);
    bind('import-course-preview', 'click', () => {
      const sectionTimes = {};
      for (const row of get('import-section-times').children) {
        const start = parser.parseTime(row.querySelector('[data-kind="start"]').value), end = parser.parseTime(row.querySelector('[data-kind="end"]').value);
        if (!start || !end) throw new Error(`请填写第 ${row.dataset.sections} 节的起止时间`);
        const minutes = end.hour * 60 + end.minute - start.hour * 60 - start.minute;
        if (minutes < 1) throw new Error(`第 ${row.dataset.sections} 节的结束时间应晚于开始时间`);
        sectionTimes[row.dataset.sections] = { ...start, minutes };
      }
      return preview(courses.flatMap(course => parser.expandCourse(course, { firstMonday: get('import-first-monday').value, sectionTimes })));
    });
    bind('import-select-all', 'change', () => { selected = new Set(get('import-select-all').checked ? rows.filter(row => !row.duplicate).map(row => row.id) : []); renderRows(); });
    bind('import-more', 'click', () => { pageSize += 100; renderRows(); });
    bind('import-confirm', 'click', async () => {
      if (busy || confirmed || !selected.size || !current(generation)) return;
      const turn = generation; setBusy(true); status('正在写入日历…');
      try {
        const payload = rows.filter(row => selected.has(row.id) && !row.duplicate).map(({ duplicate, ...row }) => row);
        // createOnly prevents a second tab or concurrent import from replacing edited entries.
        const saved = await request('/schedule/batch?createOnly=true', { method: 'POST', body: payload });
        if (!current(turn)) return;
        confirmed = true; status(`已导入 ${saved.length} 条日程。`); onImported(saved.length);
      } catch (error) { if (current(turn)) status(`导入失败，未报告成功：${error.message}`, true); }
      finally { if (current(turn)) setBusy(false); }
    });
    return () => { disposed = true; generation++; handlers.forEach(remove => remove()); controls.dispose(); bytes = null; workbook = null; };
  }
  scope.StitchCalendarImportUI = { mount };
})(window);
