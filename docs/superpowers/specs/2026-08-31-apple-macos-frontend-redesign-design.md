# 时序智配前端二代重构设计方案

**状态**：设计已获用户确认，待实现

**确认方向**：C「双层工作台」+ A「Apple 实用型」+ macOS 侧边栏工作区

**适用项目**：`Ruanchuang-main` Flutter 客户端

## 1. 目标与范围

本轮彻底重构前端视觉、信息架构和交互反馈，使应用成为个人效率优先、团队协作自然延伸的日程工作台。

本轮保留并继续使用：

- FastAPI + SQLite 后端
- `DataService`、`CompositeDataService`、`RemoteDataService` 契约
- 本地优先、远端可用时同步、远端不可用时本地兜底
- 日程调度、三方案救援、确认、撤销、事件记录
- Focus、Schedule、Micro、Team、Profile 五个主入口及已有路由

本轮只改变：

- 应用壳层和导航层级
- 页面布局、颜色、字体、组件样式
- 加载、空状态、错误、离线、预留状态的呈现
- 按钮反馈、动效、触控和键盘交互

## 2. 参考筛选结论

参考 [Motion Sites](https://motionsites.ai/) 公开案例后，保留以下适合效率工具的做法：

- 分段式信息节奏和明确的视觉焦点
- 有节制的非对称留白，避免所有内容变成同样大小的卡片
- 轻量进入动效和页面空间连续性
- 标题、数据、状态之间清楚的层级关系

不直接移植以下做法：

- 营销型巨型 Hero 标题
- 渐变背景、装饰性光球和持续背景动画
- 仅依赖悬停的操作反馈
- 影响日程扫描效率的过度留白

## 3. 设计决策

### 3.1 信息架构

首页采用“双层工作台”：

1. 上层回答“现在做什么”：当前任务、计时器、能量、同步状态和唯一主动作。
2. 下层回答“接下来怎么安排”：未来四小时时间轴、冲突、救援摘要、团队窗口和今日队列。

### 3.2 桌面壳层

- `>= 1200px`：264px 展开侧栏 + 顶部标题栏 + 主工作区
- `720-1199px`：88px 紧凑 `NavigationRail`
- `< 720px`：顶部状态栏 + 五项 `NavigationBar`
- 桌面侧栏分组：今天、规划、协作、复盘、系统
- 顶部栏显示页面标题、日期、同步来源、搜索入口、账户入口
- 主内容最大宽度约 1320px，侧栏与内容之间保持稳定间距

### 3.3 视觉令牌

| 令牌 | 浅色 | 深色 | 用途 |
| --- | --- | --- | --- |
| `canvas` | `#F5F5F7` | `#111214` | 页面背景 |
| `surface` | `#FFFFFF` | `#1C1C1E` | 内容表面 |
| `ink` | `#1D1D1F` | `#F5F5F7` | 主文字 |
| `secondary` | `#6E6E73` | `#98989D` | 辅助文字 |
| `brand` | `#163D3D` | `#A7D4C6` | 品牌标识、关键标题 |
| `action` | `#007AFF` | `#0A84FF` | 主操作、链接 |
| `recovery` | `#34C759` | `#30D158` | 能量和恢复 |
| `pressure` | `#FF9F0A` | `#FF9F0A` | 截止和计划压力 |
| `risk` | `#FF3B30` | `#FF453A` | 冲突、失败、逾期 |

- 字体：`SF Pro`、`PingFang SC`、`Noto Sans SC` 回退链
- 正文基线 16sp，辅助文字不低于 12sp
- 间距使用 4/8dp 节奏，页面内边距 16/24/32
- 控件圆角 10-12，组件圆角 14-16，弹层圆角 20
- 使用不透明表面和细分隔线，禁止用透明度单独表达层级
- 数字计时使用等宽数字或 `FontFeature.tabularFigures()`

### 3.4 动效和可访问性

- 控件反馈约 180ms，页面过渡约 260ms
- 使用淡入、轻微位移、颜色和进度动画，不动画化布局尺寸
- 页面切换使用 `AnimatedSwitcher` 保持空间连续
- 支持 `MediaQuery.disableAnimations` 或等价 reduced-motion 策略
- 可点击区域最小 44x44，桌面端必须有键盘焦点和可见焦点环
- 图标优先使用 `CupertinoIcons`，无等价图标再使用 Material Symbols
- 图标按钮必须提供 Tooltip、语义标签和禁用原因

## 4. 页面方案

### 4.1 首页双层工作台

上层组件：

- `CurrentTaskPanel`：当前任务、开始/暂停/完成、剩余时间
- `EnergyStatus`：当前能量、情绪提示、建议动作
- `SyncStatus`：远端、离线、本地缓存、待同步

下层组件：

- `MiniTimeline`：未来四小时节奏
- `RescueSummary`：待处理冲突、最近接受、撤销入口
- `TeamWindowPreview`：团队空闲窗口摘要
- `TodayQueue`：今日任务队列和下一步动作

首页只保留一个主动作；其他动作使用次级按钮、菜单或图标按钮。

### 4.2 智能日历

- 日/周/月/甘特使用 `SegmentedButton`
- 时间地图为主要内容，日程块按标签和状态着色
- 日程点击：桌面/平板 `Dialog`，手机 `ModalBottomSheet`
- 右侧显示救援摘要；平板改为可展开面板
- 保留手动/智能模式、字段筛选、冲突定位、三方案比较、确认、撤销和事件写入

### 4.3 微任务、团队、目标和复盘

- 微任务：收件箱式列表、批量选择、批量完成、批量安排、时间晶体建议
- 团队：成员状态、共享权限、忙碌块、共同空闲窗口、团队任务
- 目标：目标进度树、任务拆解、安排下一个任务
- 复盘：周报、月报、救援历史、调度参数和调优保存
- 个人/集成/设备：统一设置表面；接口预留必须显示待接入状态

## 5. 组件边界

允许新增或重构的组合组件：

- `AppShell`
- `MacSidebar`
- `WorkspaceTitlebar`
- `CurrentTaskPanel`
- `MiniTimeline`
- `RescueSummary`
- `EnergyStatus`
- `SyncStatus`
- `ScheduleTimeline`
- `StatusBanner`
- `EmptyState`
- `ActionFeedback`

组件只接收模型、状态和回调，不直接访问网络、数据库或全局单例服务。页面控制器负责调用 `DataService`，并把结果映射成可渲染状态。

## 6. 按钮与后端映射

| 用户操作 | Flutter 服务 | 远端接口或边界 |
| --- | --- | --- |
| 添加/编辑/删除日程 | `DataService` | `/schedule` POST、PUT、DELETE |
| 重新规划 | `DataService` | `/schedule/replan` |
| 日程救援生成/应用/撤销 | `ScheduleRescueService` | 本地流程可用；`/schedule/rescue/*` 远端保持 501/预留 |
| 能量/情绪读取和打卡 | `DataService` | `/energy/current`、`/energy/samples`、`/emotion/current`、`/emotion/checkins` |
| 微任务 CRUD | `DataService` | `/microtasks` POST、PUT、DELETE |
| 微任务推荐 | 本地引擎或适配器 | `/microtasks/recommend-crystals`；未接入时显示本地来源 |
| 目标 CRUD 和目标任务 | `DataService` | `/goals` 及目标任务接口 |
| 团队成员、权限、日历 | `DataService` | `/team/members`、`/team/calendars`、`/permission` |
| 团队冲突、黄金窗口、预约 | 服务适配器 | 当前接口预留，不得伪造成功 |
| 周报、月报、救援历史、调优 | `DataService` | `/review/*` |
| 行为事件 | `logTaskEvent`、`upsertTaskEvents` | `/events`、`/events/batch` |
| 登录、注册、当前用户 | `RemoteDataService` | `/auth/login`、`/auth/register`、`/auth/me` |
| 主题和语言 | 本地 `DataService` | 远端方法当前不可用，保持本地持久化 |

统一反馈状态：

```text
idle -> loading -> success
             -> offlineQueued
             -> validationError
             -> unauthorized401
             -> conflict409
             -> reserved501
```

错误必须显示在触发控件附近；删除、撤销和覆盖操作必须在执行前确认，并提供可撤销反馈。

## 7. 实施阶段

### 阶段 0：审计和基线

读取当前屏幕、服务、后端路由和测试；运行 `flutter analyze`、`flutter test`；保存桌面、平板、手机截图基线。

### 阶段 1：令牌和壳层

重构 `lib/theme/app_theme.dart` 和 `lib/screens/main_screen.dart`，完成 macOS 侧栏、标题栏、平板 Rail、手机底栏，并保留所有入口。

### 阶段 2：首页和日历

完成双层工作台、当前任务、能量、微时间轴、救援摘要、团队窗口和智能日历。

### 阶段 3：其余页面

统一微任务、团队、目标、复盘、个人、集成和设备页面的组件、状态和弹层。

### 阶段 4：同步和反馈

逐项验证按钮到 `DataService`、`RemoteDataService` 和本地兜底的映射；补全 401、409、422、501、离线和待同步状态。

### 阶段 5：验证和视觉 QA

完成响应式、键盘、语义、回归测试和截图检查，确认无溢出、无遮挡、无假成功。

## 8. 验收标准

- 桌面 1440x900、1024x768 和手机 390x844 均可用
- 侧栏、底部导航、日历视图、添加日程、删除确认、救援、团队权限、主题切换均有交互测试
- 每个页面覆盖 loading、empty、success、offline、validation error、401、409、422、501、undo
- 所有主操作具备明确反馈，接口预留不会显示成功
- 不引入未经批准的 UI 框架，不破坏已有业务服务和路由
- 通过 `flutter analyze`、`flutter test`、`dart format --set-exit-if-changed .`、`git diff --check`
- 交付报告列出真实测试结果、修改文件、接口边界、已知风险和截图路径

## 9. Agent 开发提示词

```text
你是资深 Flutter 产品设计工程师、交互工程师和前端架构师。

项目路径：
G:\study\c.C++\cproject\.dart\lib\Ruanchuang-main

请严格按照本设计文档执行前端二代重构：
docs/superpowers/specs/2026-08-31-apple-macos-frontend-redesign-design.md

目标：
- C 双层工作台
- A Apple 实用型视觉基线
- macOS 侧边栏工作区
- 个人效率优先，团队协作自然延伸
- 参考 Motion Sites 的版式节奏和微动效，但不复制营销型布局

开始前：
1. 执行 git status，保留工作区已有修改。
2. 阅读本设计文档和以下文件：
   lib/screens/main_screen.dart
   lib/screens/focus_page.dart
   lib/screens/smart_calendar_page.dart
   lib/screens/micro_task_page.dart
   lib/screens/team_page.dart
   lib/screens/goals_page.dart
   lib/screens/review_page.dart
   lib/screens/profile_page.dart
   lib/services/data_service.dart
   lib/services/composite_data_service.dart
   lib/services/remote_data_service.dart
   lib/theme/app_theme.dart
   backend/routers_*.py
3. 运行 flutter analyze 和 flutter test，保存基线结果。

硬性约束：
- 不改变 FastAPI、SQLite、DataService、CompositeDataService、调度算法、救援逻辑和本地优先策略。
- 不使用假数据掩盖远端不可用；501/预留接口必须显示真实待接入状态。
- 不新增第三方 UI 框架；优先 Material 3、CupertinoIcons 和现有组件。
- 禁止渐变背景、装饰性光球、营销型巨型标题、无限圆角和嵌套卡片。
- 可点击控件最小 44x44；桌面端支持键盘焦点和 Tooltip。
- 组件不得直接访问网络或数据库，服务调用必须经过页面控制器和 DataService。

按阶段完成：
阶段 1：令牌、macOS 侧栏、标题栏、平板 Rail、手机底栏。
阶段 2：首页双层工作台和智能日历。
阶段 3：微任务、团队、目标、复盘、个人、集成、设备。
阶段 4：按钮到已实现接口、本地兜底和错误状态映射。
阶段 5：响应式、可访问性、动效降级、回归测试和截图 QA。

必须验证的实现接口：
/auth/login /auth/register /auth/me
/schedule /schedule/replan
/emotion/current /emotion/checkins
/energy/current /energy/samples
/microtasks /goals
/team/members /team/calendars
/review/* /events /events/batch

必须保持预留边界：
/schedule/rescue/*
/team/conflicts
/team/golden-windows
/team/book-meeting
/goals/{goal_id}/schedule-next
/integrations/* /devices/* /ai/*

每个页面都要实现 loading、empty、success、offline、validation error、401、409、422、501 和 undo 状态。

验证命令：
flutter analyze
flutter test
dart format --set-exit-if-changed .
git diff --check

补充验证：
- 1440x900、1024x768、390x844
- 侧栏、底栏、日历切换、添加日程、删除确认、救援、团队权限、主题切换
- 回归测试：按钮点击无效果、预留接口误报成功、远端失败本地兜底

交付报告必须包含：
1. 修改文件列表
2. 组件和状态模型
3. 按钮到服务/接口映射
4. 测试命令及真实结果
5. 尚未实现的接口
6. 已知风险
7. 截图路径

停止规则：
- 接口模型不一致时停止并报告，不猜字段。
- 遇到预留接口时停止扩展后端，不伪造实现。
- 遇到现有用户修改冲突时保留修改并报告。
- 未完成验证前不得声称全部完成或后端已全部接通。
```
