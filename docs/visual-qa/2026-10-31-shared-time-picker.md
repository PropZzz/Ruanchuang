# 新增与导入统一时间选择器

用户要求把导入日程的时间菜单同步到新增日程。已抽取 `web/stitch/time-picker.js` 和 `assets/time-picker.css`，新增、编辑及导入共同复用同一组件；文件卡片逻辑留在导入 UI。保留既有抽屉、配色和字段布局。

小时/分钟选择、手动输入、方向键、Tab 循环、Escape 取消、确认事件、隐藏与销毁清理均沿用已验收行为；新增和编辑共用原来的时间校验、保存 API 及数据库字段。组件独立解析 HH:mm，不再依赖导入解析库。

验证结果：

- 新增端到端先确认缺少时间选择按钮而失败，实现后桌面/手机各创建 11 种标签日程，全部经真实隔离 FastAPI/SQLite 保存和重载验证通过。
- 编辑回归桌面/手机通过，增加 00:15 回显、改变小时后 Escape 取消仍保留旧值的检查。
- 导入六格式、真实课表及键盘操作桌面/手机全部通过。
- 20 项日历、导入、发布测试通过；源检查与脚本语法通过。
- 整个工作区 Node 测试另有一项并行开发中的 mobile shell 源码断言失败，本轮未修改该模块；发布采用线上已发布代码作为基线，只增量合入时间控件相关文件，避免带入未完成工作。
- 只读审查无 P1/P2，独立验证 23:59、00:15、fieldset 禁用、input/change、隐藏及销毁。

发布基线：`910e6ec151d88348`（从线上下载并核对全部 112 文件 SHA-256）。本轮源快照位于忽略目录 `build/time-picker-source`；最终版本 `24620816aa1098bf`。发布脚本新增可选 `--source-root`，用于发布已审查的独立源码快照。

三个浏览器回归均针对该最终快照执行通过，报告在 `build/reports/calendar-create.json`、`build/reports/schedule-edit.json` 和 `build/calendar-import-qa/report.json`。截图在 `build/calendar-create-qa/*-time-picker.png`。

已部署至 <http://8.133.250.216/>，逐个核对线上 113 个发布文件 SHA-256、健康和版本均通过。桌面/手机实际页面选择 23:59、确认、跳转导入后取消仍保留时间与草稿均通过，线上业务 API 已拦截且写入为零。备份为 `/opt/ruanchuang/web/backups/20261031T055136Z-24620816aa1098bf`，详见 `build/calendar-import-qa/live-report.json`。
