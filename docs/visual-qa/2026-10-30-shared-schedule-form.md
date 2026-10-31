# 新建与编辑共用日程表单

## 根因与调整

日程详情抽屉曾独立维护旧编辑表单，只有五种标签，时长输入上限为 480 分钟，与新建页不一致。现在删除这套重复实现，详情的编辑按钮进入 `create-schedule?id=...`，直接复用新建表单。标题与保存文案按模式变化，布局、11 种标签及主题颜色、日期、时间、5–1440 分钟时长、认知负荷、提醒和重复选项保持一致。

编辑重新读取原记录并回填，通过 PUT 更新原 ID；新建仍通过 POST 创建。未显示的目标关联、目标任务关联与重复截止日期随原记录保留；选择不重复时清除重复截止日期。标签未改变时保留原颜色。旧记录中的未固定日期、未评估负荷、自定义标签及非标准提醒也能回填，旧选项不会带入新建。

读取期间和失败时禁止提交，支持重试；取消编辑不写入数据，每次重新打开读取已保存记录。详情每次打开也重新读取，避免缓存抽屉显示旧内容。修改重复日程而未改锚点日期时保留日历当前查看日期。

## 验证

- `node tools/check_stitch_schedule_edit.mjs`：桌面、手机通过真实 FastAPI 与临时 SQLite 验证表单选项一致、所有字段修改持久化、午夜与长日程、四类重复规则、旧字段保留、取消重开、读取失败与重试、无重复新增。
- `node tools/check_stitch_schedule_create.mjs`：桌面、手机分别验证 11 类日程新增、配色、日历显示、刷新及进入共享编辑表单。
- `node tools/check_stitch_calendar.mjs`：桌面、手机完整日历回归，以及两个时区的日期验证通过。
- `node tools/check_stitch_drawers.mjs`：26 项桌面、手机抽屉检查通过，包括真实详情到编辑的跳转、文档复用、可逆动画与减少动态效果。
- `node tools/check_stitch_navigation.mjs`：页面保留、导航竞争、保存后刷新与账号切换检查通过。
- 日期及发布单测 8 项通过，源引用与 JavaScript 语法检查通过。
- 已查看 `build/schedule-edit-qa/desktop-edit.png` 和 `mobile-edit.png`，表单沿用原主题和抽屉布局。

编辑报告：`build/reports/schedule-edit.json`。业务写入测试均使用隔离后端和临时数据库。

## 发布

已部署版本 `7947d065031d40fb`，101 个发布文件校验通过，Nginx 配置检查通过。公网 `/release.json` 确认为该版本，`Cache-Control: no-store`，`/health` 返回 `ok=true`。

上线后执行 `node tools/check_stitch_schedule_edit.mjs --url http://8.133.250.216/`，桌面和手机的全部编辑检查通过。测试加载公网前端，业务请求转到本地隔离的真实后端，未修改正式账号日程。

发布目录：`/opt/ruanchuang/web/releases/stitch-7947d065031d40fb`；上一版本：`stitch-f587ab97f5b98c8b`；备份：`/opt/ruanchuang/web/backups/20261030T131505Z-7947d065031d40fb`。
