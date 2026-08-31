# 时序智配 Web 端设计文档

**日期：** 2026-08-31  
**状态：** 待实施  
**范围：** 与现有 Flutter 客户端并行的浏览器版本  
**项目：** `Ruanchuang-main`

## 1. 目标

为“时序智配”增加一个可部署的浏览器版本，保留现有 Flutter 客户端、FastAPI 后端、SQLite 数据和本地优先策略。Web 端首版优先完成以下可演示、可验证的业务闭环：

```text
突发任务输入
  -> 生成三种日程救援方案
  -> 比较方案代价
  -> 用户确认
  -> 日程持久化
  -> 事件记录
  -> 可撤销
  -> 周/月复盘
```

首版不是营销落地页，也不引入未实现的硬件、传感器或第三方深度集成能力。

## 2. 现有系统基线

当前项目是 Flutter + FastAPI + SQLite 的本地优先调度原型，已具备：

- Flutter Chrome 运行入口和 Web `localStorage` 持久化适配。
- `DataService`、`RemoteDataService`、`CompositeDataService` 的远端优先/本地兜底结构。
- 日程增删改、任务事件、精力/情绪、目标、团队和复盘接口。
- `POST /schedule/replan` 后端启发式重排接口。
- Flutter 端三种救援策略：优先截止时间、优先恢复时间、尽量少动原计划。
- 接受、撤销、持久化和事件记录闭环。
- 已批准的“时间地图”响应式视觉规范，见 `docs/superpowers/specs/2026-08-31-temporal-intelligence-frontend-design.md`。

Web 端应复用这些能力，不另建一套任务模型或第二套前端业务状态机。

## 3. 竞品机制分析

以下结论来自产品公开帮助文档和功能页面。竞品内部源码和完整权重未公开，因此实现时采用可解释的启发式算法，不声称复刻其专有算法。

| 产品 | 公开机制 | 对本项目的借鉴 |
| --- | --- | --- |
| [Motion 自动排程](https://www.usemotion.com/help/time-management/auto-scheduling) | 可用时间、时长、截止时间、优先级、开始时间和重复规则；ASAP/硬截止优先；可拆分任务；日程变化后自动重排 | 区分 ASAP、硬截止和软截止；支持任务分块 |
| [Reclaim 自动管理](https://help.reclaim.ai/en/articles/6207587-how-reclaim-manages-your-schedule-automatically) | P1-P4 优先级；综合截止时间、日历空闲、调度时段、频率和时长；高优先级可覆盖低优先级事件 | 将任务、习惯、会议视为同一时间资源上的竞争者 |
| [SkedPal 任务属性](https://docs.skedpal.com/planning/understanding-task-properties) | 计划完成日期和参考截止日期分离；有时间窗和调度粒度；短任务可聚合 | 分离硬约束与展示型日期，明确调度粒度 |
| [TimeHero 功能](https://www.timehero.com/features) | 按可用时间自动排程；项目开始/截止和依赖变化会触发重排；显示风险和容量 | 增加风险、容量和依赖状态 |
| [Morgen AI Planner](https://www.morgen.so/ai-planner) | 从任务、日历和容量生成计划；支持拆分；先预览、调整，再确认 | 与本项目“比较后确认”最接近 |
| [Sunsama Timeboxing](https://help.sunsama.com/docs/usage-guides/timeboxing/) | 引导式每日规划，拖拽任务到日历进行时间块安排，也支持自动安排 | 自动化必须保留人工控制和明确提交动作 |
| [Akiflow](https://akiflow.com/) / [Structured AI](https://structured.app/blog/the-new-structured-ai) | 收件箱、任务、日历和时间线统一；AI 结果先编辑再加入时间线 | 生成草案不等于立即写入日程 |

### 3.1 竞品 Web UI 共性

1. 任务列表和日历时间线处在同一个主要工作区，减少来回跳转。
2. 自动排程产品都提供可配置的优先级、时长、截止时间和可用时段。
3. 复杂结果先以预览或差异展示，用户确认后才提交。
4. 日程变化后的影响通过移动数量、风险、容量或冲突提示表达。
5. 手动拖拽是加速操作，不应成为唯一的排序、移动或调整入口。

## 4. 当前算法问题

现有 Dart 和 Python 调度器存在可能导致 Web 与 Flutter 结果不一致的差异：

- Python `backend/services_scheduling.py` 的任务排序优先考虑优先级，再考虑截止时间。
- Flutter `lib/services/scheduling/heuristic_scheduling_engine.dart` 对当天截止时间优先，再比较优先级和负荷。
- Python 主要按空档顺序填充；Flutter 还计算时间段、精力和负荷得分。
- 两边均不支持可拆分任务。
- Flutter 端负责三种救援方案，后端 `/schedule/rescue/*` 目前仍是预留能力。

首版 Web 不应复制这些差异。排序规则必须有一组跨语言测试向量，后续逐步将服务端作为多端共享的规范实现。

## 5. 统一调度算法

### 5.1 输入模型

在现有字段基础上，算法内部允许使用以下可选属性；新增属性必须保持向后兼容：

```text
Task
  id
  title
  durationMinutes
  priority: 1..5
  due
  hardDeadline: boolean
  earliestStart
  load: low | medium | high
  splittable: boolean
  minimumChunkMinutes
  tag / goalId / goalTaskId

Calendar
  fixed blocks
  available windows
  current energy and emotion
  scheduling tuning
```

### 5.2 约束优先级

候选时间块必须先满足硬约束，再计算软目标分数：

```text
1. 固定日程和不可占用区间
2. 硬截止时间可行性
3. ASAP 标记
4. 截止时间剩余裕量 slack
5. 优先级
6. 当前精力与认知负荷匹配度
7. 对原计划的改动数量
8. 空档填充效率
```

```text
slack = due - currentTime - remainingDuration - recoveryBuffer
```

如果不存在满足硬约束的时间块，允许返回最早可行时间，但必须返回 `miss_due`、`overdue` 或 `no_slot` 问题码，不能静默掩盖风险。

### 5.3 三种策略权重

```text
protectDeadline:
  urgency 0.55, priority 0.25, energyFit 0.10, stability 0.10

protectRecovery:
  energyFit 0.35, recovery 0.25, urgency 0.20, priority 0.10, stability 0.10

minimizeChanges:
  stability 0.55, urgency 0.25, priority 0.15, energyFit 0.05
```

策略只改变软目标权重，不突破固定日程和硬截止校验。恢复策略默认预留 15 分钟缓冲；该数值应进入响应中的解释字段，而不是隐藏在 UI 中。

### 5.4 解释结果

每个方案至少返回：

```text
strategy
entries
issues[]
movedEntryCount
recoveryMinutes
missedDeadlineCount
earliestFinish
scoreBreakdown[]
```

`scoreBreakdown` 使用稳定的解释码，例如 `deadline_proximity`、`priority`、`energy_fit`、`kept_baseline`、`fixed_conflict`，供 Web 和 Flutter 使用同一套文案映射。

## 6. Web 端 UI 设计

### 6.1 设计方向

采用现有“冷静可信的调度工作台”，不复制竞品的营销型首屏：

- 页面背景、文字、恢复、截止、风险颜色沿用现有设计令牌。
- 信息密度偏高，优先支持快速比较和重复操作。
- 一个页面只保留一个主要动作；日历主动作是“添加紧急任务/启动救援”。
- 明确显示远端、加载、本地兜底、空数据、冲突和失败状态。
- 毛玻璃只用于分层，不作为唯一对比手段。

### 6.2 桌面端布局（>=1200px）

```text
┌──────────────┬───────────────────────────────────┬──────────────┐
│ 240-260px    │ 顶部：日期 / 数据来源 / 精力状态   │              │
│ 侧栏         ├───────────────────────────────────┤  救援摘要    │
│              │ 日程时间地图                        │  冲突列表    │
│ 五个入口     │ 日/周/月/甘特 + 任务时间块          │  最近操作    │
│              │                                     │              │
└──────────────┴───────────────────────────────────┴──────────────┘
```

时间地图左侧显示时间刻度和固定块，任务块显示标题、标签、负荷、截止和状态。右侧摘要展示当前冲突、最近救援和撤销入口，不遮挡主时间线。

### 6.3 救援方案界面

救援不是普通弹窗中的三段文字，而是三个可比较的候选计划：

- 方案标题、适用场景和核心取舍。
- 时间线差异：新增、移动、保留和可能逾期的任务。
- 移动任务数、恢复缓冲、逾期风险和问题数。
- 明确的“采用此方案”动作。
- 写入失败保留原计划；成功后显示撤销横幅。

### 6.4 响应式断点

| 宽度 | 布局 |
| --- | --- |
| `>=1200px` | 展开侧栏、时间地图、右侧救援摘要 |
| `720-1199px` | 紧凑导航，救援摘要改为可展开面板 |
| `<720px` | 底部导航，编辑和救援使用 Bottom Sheet |

拖拽必须有键盘或菜单替代操作。所有交互控件提供可见焦点、语义名称和足够的点击区域；不以 hover 作为唯一反馈。

## 7. 系统架构

### 7.1 首选技术路线

使用同一 Flutter 工程构建 Web 版本：

```text
Flutter Web
  -> DataService / CompositeDataService
  -> FastAPI REST API
  -> SQLite（首版单实例）
```

原因：现有项目已经有 Chrome 启动脚本、Web 持久化、平台文件适配和响应式页面。另建 React/Next.js 会重复实现模型、登录、救援状态机和测试，首版不划算。

React/Next.js 仅在未来需要独立 Web 团队、SEO 公共页面或极致桌面 Web 交互时再评估，不作为本轮方案。

### 7.2 Flutter 侧边界

建议新增一个 `SchedulingGateway` 抽象：

- 远端可用时调用 `/schedule/replan`。
- 网络不可用或服务端 5xx 时使用本地启发式引擎。
- 4xx、鉴权失败、冲突和响应格式错误不转换为空结果。
- 救援方案在第一阶段可继续复用 `ScheduleRescueService`；第二阶段再切换到服务端事务接口。

相关文件：

```text
lib/services/scheduling/scheduling_gateway.dart        新增
lib/services/scheduling/heuristic_scheduling_engine.dart  统一本地规则
lib/services/scheduling/schedule_rescue.dart            复用三策略
lib/services/remote_data_service.dart                   接入远端规划
lib/services/composite_data_service.dart                处理降级
lib/screens/smart_calendar_page.dart                    Web 工作区接入
lib/screens/main_screen.dart                             响应式壳层
lib/screens/review_page.dart                             救援复盘
lib/config/app_config.dart                               生产 API 地址
web/index.html                                           标题和元信息
```

### 7.3 后端边界

首版复用：

```text
POST /auth/register
POST /auth/login
GET  /auth/me
GET/POST/PUT/DELETE /schedule
POST /schedule/replan
POST /events
POST /events/batch
GET  /energy/current
GET  /emotion/current
GET  /review/weekly
GET  /review/monthly
GET/PUT /review/tuning
```

第二阶段再实现并解除预留状态：

```text
POST /schedule/rescue/options
POST /schedule/rescue/apply
POST /schedule/rescue/undo
GET  /schedule/rescue/history
```

`apply` 必须携带 `baselineHash`、`strategy`、`before` 和 `after`，服务端验证基线未变化后，在同一个事务中更新日程、写入事件并保存撤销快照。

## 8. 部署设计

### 8.1 运行拓扑

```text
浏览器
  -> Nginx HTTPS
       /       -> Flutter build/web 静态文件
       /api/   -> FastAPI 127.0.0.1:8000
                         -> 持久化 SQLite 文件
```

构建命令：

```text
flutter build web --release \
  --dart-define=API_BASE_URL=https://your-domain.example/api
```

Nginx 的 `/api/` 代理应去掉 `/api` 前缀后转发到现有 FastAPI 路由，并将其他路径回退到 Flutter 的 `index.html`。

### 8.2 首版生产约束

- 使用单 Uvicorn worker，SQLite 开启 WAL。
- 持久化 `.appdata` 或明确的数据库目录，并设置备份策略。
- 将 CORS 从 `*` 收紧为正式 Web 域名。
- `backend/auth.py` 当前 Token 存在进程内，重启会失效；正式多进程部署前应改为签名 JWT/持久化会话，或使用 Redis 会话存储。
- 未完成持久化认证和并发冲突控制前，不启用多 worker 或多实例写入。
- Web 本地 `localStorage` 只作为离线缓存，不能替代服务端数据源。

## 9. 分阶段实施

### 阶段 A：Web 可运行基线

- 整理生产 API 地址和 Web 元信息。
- 构建 Flutter Web 静态包。
- 验证登录、日程读写、事件写入、复盘读取。
- 验证远端失败时的本地兜底状态。

### 阶段 B：核心救援工作区

- 完成桌面三栏、时间地图、状态条和救援摘要。
- 复用现有三策略、截止时间校验、确认、撤销和事件记录。
- 为救援卡补齐时间线差异和风险指标。

### 阶段 C：算法统一

- 统一 Dart/Python 的任务排序、时段评分、问题码和解释码。
- 增加同一输入向量下的跨语言结果对比测试。
- 在不改变现有客户端协议的前提下，逐步让 Web/Flutter 调用后端规范规划。

### 阶段 D：服务端救援事务

- 实现救援方案、应用、撤销和历史接口。
- 增加基线哈希和并发冲突处理。
- 保存前后快照，确保失败回滚和撤销可重复执行。

## 10. 测试与验收

### 功能验收

- 输入精确截止时间后稳定生成三种方案。
- 三种方案的移动数量、恢复缓冲和问题数可解释。
- 确认后日程和事件同时写入；写入失败不改变原计划。
- 撤销后完整恢复基线，并留下撤销事件。
- 同一账号在 Flutter 和 Web 看到相同日程。

### 算法验收

- Dart 与 Python 对同一测试向量返回相同任务顺序和问题码。
- 固定日程不会被覆盖。
- 无可行时间块时返回明确的 `no_slot` 或 `miss_due`。
- 低精力时高负荷任务不会被静默安排为“正常可行”。

### Web 验收

- 在 375、768、1024、1440 宽度下无横向溢出。
- 键盘可完成登录、切换视图、打开任务、选择方案、确认和撤销。
- 远端、加载、本地模式、空状态、冲突和失败状态可见且不混淆。
- 运行 `flutter analyze`、完整 Flutter 测试和后端测试。
- `/api/health`、登录、日程读取和核心救援流程可通过 HTTPS 访问。

## 11. 非目标

本轮不包含：

- 迁移到 React/Next.js 或新增第三方 UI 框架。
- 重写现有 FastAPI/SQLite 数据模型。
- 将多模态生理信号、GPU 模型或硬件采样伪装成已上线能力。
- 未经实现的 Google/Outlook 深度 OAuth 同步。
- 多实例实时协同编辑和无限并发承诺。
- 用本地预览数据冒充实时远端数据。

## 12. 设计决策

1. Web 与 Flutter 并行，但共享同一套 Flutter 业务代码和 FastAPI 数据契约。
2. 首版聚焦核心救援闭环，全量页面作为后续扩展，不在首版引入第二套前端状态机。
3. 排序算法保持启发式、可解释、可回归测试；暂不使用无法验证的机器学习模型。
4. 自动排程只生成建议，日程写入必须经过用户确认或明确的后续自动化设置。
5. 任何降级、冲突和能力缺口都必须在 UI 中诚实显示。
