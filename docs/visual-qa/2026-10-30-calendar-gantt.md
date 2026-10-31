# 智能日历甘特视图

## 需求与实现

原甘特按钮没有绑定日历动作或数据渲染。本次在原日历内补全甘特视图，继续使用账号 `/schedule` 数据、新增／编辑／删除抽屉、日期选择与当前配色。

- 桌面启用原“甘特视图”按钮并移除占位 Pro 标签；手机在原分段器中添加“甘特”。
- 周时间轴和日小时轴可切换；日期翻页对应一周／一天，保留今天、日期选择、刷新、新建与紧急任务入口。
- 日程分行排列，左侧固定标题、日期、时间、标签、时长与重复标记；右侧时段条使用原主题，点击名称或条形均进入现有日程详情。
- 跨午夜分段合并为连续条形，重复日程逐次显示；超出周期的部分裁剪到边界，旧版浮动日程继续按天出现。
- 固定表头、横向／纵向滚动、当前时间竖线、选中日期提示；短条形不强行挤入标题，完整标题和时间可从固定名称栏与 tooltip 查看。
- 保留原控制台、统计与救援侧栏，其他日／周／月视图保持原行为。
- 使用原账号隔离和缓存机制，离线保留已读取数据，未授权清空日程，切换屏幕尺寸与编辑后保留甘特选择。

## 验证

- `node --test tools/tests/stitch_calendar.test.mjs tools/tests/stitch_release.test.mjs`：9 项通过。新增跨午夜合并、跨周裁剪与重复日程的计算验证。
- `node tools/check_stitch_calendar.mjs`：桌面／手机均通过 20 类检查，另有上海与檀香山时区用例；覆盖真实日期、日周月甘特、小时缩放、条形位置／时长、当前时刻、标签颜色、滚动保持、新增编辑删除、账号隔离、离线、登录与响应式。
- `node tools/check_stitch_schedule_create.mjs`：真实 FastAPI + 临时 SQLite，桌面及手机各新增 11 种标签的日程，重载后核对日／周／甘特／月视图与持久化颜色，编辑与删除通过。测试未写线上账号数据。
- `node tools/check_stitch_drawers.mjs`：32 项通过，覆盖已有抽屉与 ICS 加宽抽屉。
- `node tools/check_web_sources.mjs`：98 个 Web 文件、25 个路由、275 个本地引用通过。
- 桌面／手机甘特周轴与日轴截图人工检查通过，截图位于 `build/calendar-qa/`。
- Impeccable detector 本轮运行一次：因缺 HTML parser 依赖降级到正则扫描，仅报告原页面字号层级警告；不将扫描视为完整视觉验证。
- `git diff --check` 通过。

## 发布

已发布到 `http://8.133.250.216/`，release `808f374af8849b11`。线上 `/release.json` 与本地生产构建编号一致；`stitch/calendar.808f374af8849b11.js` 的 SHA-256 均为 `025dacd84ab3554ae62cc6d07df411486308056a973c956f4bb06aee2791c241`。公网 `/health` 返回 `{"ok":true,"version":"0.1.0","database":"sqlite"}`，入口清单响应 `Cache-Control: no-store`。
