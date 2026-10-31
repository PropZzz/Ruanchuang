# 运行形态与前端收口决定

依据已确认的项目收口计划，继续维护当前三条边界：HTML/JS Web、Flutter 原生客户端、FastAPI/SQLite 后端。

## 源码职责

- `web/` 是线上 Web 的唯一发布源，包含桌面与手机页面。`router.js` 负责路由和 API 协调，`page-host.js` 保留文档及状态，`actions.js` 根据显式标识分派 API，`calendar.js` 与 `focus.js` 各自维护工作台状态。
- `lib/` 与各原生平台工程是 Flutter 客户端；不恢复已停用的 Flutter Web 构建链路。两端共用后端与调度契约，不要求两套页面源码互相复制。
- `lib/screens/smart_calendar_page.dart` 组合已有时间轴、救援比较和 `lib/widgets/calendar/` 组件；组件接收数据与回调，页面保留服务访问和持久化职责。删除的是已被 `ScheduleTimeline` 替代的休眠渲染器。

## 动作与状态

API 操作使用 `data-action`，认证提交根据当前 `data-auth-mode` 选择登录/注册；已有稳定 ID 保留兼容。未知动作不触发 API，专注控件仅交给 `data-focus-action` 控制器，避免重复写事件。声明式导航按钮可用 `data-route`，普通历史导航入口仍保留兼容识别。

原生请求错误通过 `serviceFailureMessage` 映射到原因和下一步，服务端正文仅保留在诊断中。Focus、日历、微任务、团队、目标、复盘有页面内的持续重试入口；失败不会只闪过一个提示后伪装为空数据。个人中心明确标记部分数据并可刷新，登录保留已有认证专用错误和输入。

`offlineQueued` 只在真正存在同步队列时可用。本轮没有新增队列或多端同步，不展示“待同步”来掩盖未落库请求。

## 验收

`test/workspace_failure_states_test.dart` 在 6 个工作页面分别验证 401、409、422、501、503、超时、断网共 42 条失败与恢复路径，再验证个人中心部分数据刷新。登录、救援采用/撤销、复盘事务失败、五档布局和视觉基线继续由原有测试覆盖。

Web 的 Node 行为测试不读取按钮文字；浏览器回归验证真实日程写入、编辑、导入、账号设置、导航及缓存迁移。所有业务写入针对隔离本地数据库。本轮没有进行 Android/iOS/Windows 安装包发布或真实设备验收。
