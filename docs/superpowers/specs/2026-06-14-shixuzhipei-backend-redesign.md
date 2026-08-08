# 时序智配前后端重构设计稿

日期：2026-06-14

## 背景

当前项目是 Flutter 跨端应用，已经具备本地数据服务、日程、微任务、情绪、目标、团队协作、复盘、提醒、ICS 导入导出和若干启发式算法雏形。项目计划书要求的核心方向包括：认知适配型智能排程、情绪感知、微任务晶体化、团队共享可视化、智能复盘、多端协同和外部数据接入。

本次改造目标不是推倒重写，而是在保留现有功能基础上，补齐真正独立后端、完善接口、优化算法边界、重塑双端界面体验，并清理前端代码结构。

## 目标

1. 新增独立后端：使用 FastAPI + SQLite，提供完整 REST API。
2. Flutter 前端改为远程优先：优先调用后端，后端不可用时回退本地数据。
3. 保留双端完整基础功能：桌面/Web 和移动端都能访问日程、微任务、团队、目标、复盘、情绪、设置等核心能力。
4. 双端侧重点不同：桌面/Web 是规划主控台，移动端是快速捕获和执行入口。
5. 后端承载核心算法：智能排程、微任务晶体推荐、团队黄金窗口、复盘分析和调参逻辑集中在后端服务模块。
6. 前端界面更统一、更美观、更专业：减少页面割裂，统一视觉系统、卡片样式、响应式布局和交互反馈。

## 非目标

1. 不接入真实短信、邮件或第三方 OAuth 登录。
2. 不做复杂生产级权限体系，例如企业组织树、管理员后台和审计流。
3. 不训练真实深度学习模型；情绪识别先采用可解释规则和模拟外部传感器输入，预留模型接口。
4. 不引入大型状态管理框架，继续沿用现有 StatefulWidget + Service 层模式，降低改造风险。

## 总体架构

系统分为三层：

1. Flutter 前端
   - 保留现有跨端工程。
   - 新增 `ApiClient` 统一处理 HTTP 请求、错误、超时和 JSON 编解码。
   - 完善 `RemoteDataService`，让它真正实现 `DataService` 接口。
   - 使用 `CompositeDataService` 作为远程优先、本地兜底的数据门面。

2. FastAPI 后端
   - 新增 `backend/` 目录。
   - `main.py` 创建应用并注册路由。
   - `database.py` 管理 SQLite 连接和初始化。
   - `schemas.py` 定义 Pydantic 请求/响应模型。
   - `repositories/` 负责数据库读写。
   - `services/` 负责算法和业务逻辑。
   - `routers/` 暴露 REST API。

3. SQLite 数据库
   - 单文件数据库，默认保存到 `backend/data/shixuzhipei.db`。
   - 适合比赛演示、离线部署和本机调试。
   - 后续可以平滑迁移到 PostgreSQL。

## 前端双端设计

### 桌面/Web 主控台

桌面/Web 使用大屏工作台布局，重点展示规划、分析和协作：

1. 首页/专注页
   - 顶部显示今日状态：情绪、能量、当前任务、下一个任务。
   - 左侧是当前专注计时和任务详情。
   - 右侧是时间晶体推荐、今日风险提示和快速操作。

2. 智能日程页
   - 默认提供日视图，保留周/月/甘特图入口。
   - 支持手动模式和智能模式。
   - 智能模式调用后端 `/schedule/replan`。
   - 右侧面板显示排程理由、冲突、错过截止时间的任务和算法耗时。

3. 团队页
   - 展示团队成员日程热力图、黄金协作窗口、冲突检测和预约会议。
   - 桌面端优先使用横向时间轴和多列成员泳道。

4. 复盘页
   - 周报/月报用指标卡、趋势图、归因列表和行动建议呈现。
   - 显示调度参数如何被复盘结果影响，例如某类任务预估时长上调。

### 移动端执行入口

移动端保留所有功能入口，但交互更轻：

1. 底部导航仍保留五个主入口。
2. 专注页强调当前任务、倒计时、完成/暂停、情绪提醒。
3. 日程页默认显示今日和本周简化视图，复杂字段收进更多菜单。
4. 微任务页强调快速新增、导入清单、批量完成和一键安排。
5. 团队页以卡片和列表展示黄金窗口、成员状态、冲突结果。
6. 复盘和诊断从“我的”页进入，避免底部导航过载。

## 后端目录结构

```text
backend/
  main.py
  database.py
  schemas.py
  seed.py
  requirements.txt
  README.md
  data/
    shixuzhipei.db
  repositories/
    auth_repo.py
    schedule_repo.py
    microtask_repo.py
    team_repo.py
    review_repo.py
  routers/
    auth.py
    schedule.py
    microtasks.py
    emotion.py
    goals.py
    team.py
    review.py
    diagnostics.py
  services/
    scheduling.py
    microtask_crystals.py
    team_collab.py
    review_rules.py
    emotion_policy.py
    ics_codec.py
```

## 数据模型

首版 SQLite 表：

1. `users`
   - `id`, `account`, `display_name`, `password_hash`, `created_at`

2. `schedule_entries`
   - `id`, `user_id`, `day`, `title`, `tag`, `load`, `goal_id`, `goal_task_id`, `start_minute`, `duration_minutes`, `color`, `reminder_minutes_before`, `repeat`, `repeat_until`

3. `micro_tasks`
   - `id`, `user_id`, `title`, `tag`, `minutes`, `priority`, `requirement`, `done`, `created_at`, `updated_at`

4. `emotion_checkins`
   - `id`, `user_id`, `at`, `state`, `note`

5. `goals`
   - `id`, `user_id`, `title`, `due`, `priority`, `created_at`

6. `goal_tasks`
   - `id`, `goal_id`, `title`, `duration_minutes`, `load`, `tag`, `done`, `depends_on_json`

7. `team_members`
   - `id`, `owner_user_id`, `display_name`, `role`, `energy`, `permission`

8. `team_busy_blocks`
   - `id`, `member_id`, `day`, `title`, `tag`, `start_minute`, `duration_minutes`, `color`

9. `task_events`
   - `id`, `user_id`, `task_id`, `title`, `tag`, `load`, `at`, `type`, `planned_minutes`, `actual_minutes`, `energy`, `interruptions`, `reason`

10. `settings`
   - `user_id`, `theme_mode`, `locale`, `favorite_device_id`, `scheduling_tuning_json`

## API 设计

所有接口返回 JSON。首版使用简化 token：登录成功后返回 `token`，Flutter 后续请求放入 `Authorization: Bearer <token>`。比赛演示阶段 token 可由后端内存或 SQLite 存储，后续再升级 JWT。

### 基础

1. `GET /health`
   - 返回后端状态、数据库状态、版本号。

2. `GET /diagnostics/summary`
   - 返回数据量、最近算法耗时、最近导入导出结果。

### 认证

1. `POST /auth/register`
   - 注册并登录。

2. `POST /auth/login`
   - 登录。

3. `GET /auth/me`
   - 获取当前用户。

4. `POST /auth/logout`
   - 退出登录。

### 日程

1. `GET /schedule?from=YYYY-MM-DD&to=YYYY-MM-DD`
   - 查询区间日程。

2. `POST /schedule`
   - 新增日程。

3. `PUT /schedule/{id}`
   - 更新日程。

4. `DELETE /schedule/{id}`
   - 删除日程。

5. `POST /schedule/replan`
   - 根据任务、固定日程、情绪、能量和调参生成智能排程。

6. `POST /schedule/import-ics`
   - 导入 ICS 文本。

7. `GET /schedule/export-ics`
   - 导出 ICS 文本。

### 微任务

1. `GET /microtasks`
2. `POST /microtasks`
3. `PUT /microtasks/{id}`
4. `DELETE /microtasks/{id}`
5. `POST /microtasks/batch-complete`
6. `POST /microtasks/batch-schedule`
7. `POST /microtasks/recommend-crystals`
   - 返回适合插入空档的微任务推荐。

### 情绪与能量

1. `GET /emotion/current`
2. `POST /emotion/checkins`
3. `GET /emotion/checkins?day=YYYY-MM-DD`
4. `GET /emotion/care-alert`
   - 连续疲惫/烦躁时返回关怀建议。

### 目标

1. `GET /goals`
2. `POST /goals`
3. `PUT /goals/{id}`
4. `DELETE /goals/{id}`
5. `POST /goals/{id}/schedule-next`
   - 安排下一个未完成且依赖满足的目标任务。

### 团队

1. `GET /team/members`
2. `POST /team/members`
3. `PUT /team/members/{id}`
4. `DELETE /team/members/{id}`
5. `GET /team/calendars?day=YYYY-MM-DD`
6. `PUT /team/members/{id}/permission`
7. `POST /team/conflicts`
8. `POST /team/golden-windows`
9. `POST /team/book-meeting`

### 复盘

1. `POST /events`
   - 上报开始、完成、推迟、打断等事件。

2. `GET /review/weekly?week_start=YYYY-MM-DD`
   - 生成周报并回写调度参数。

3. `GET /review/monthly?month=YYYY-MM`
   - 生成月报。

## 后端算法

### 智能排程

输入：任务、固定日程、可用窗口、能量等级、情绪状态、复盘调参。

策略：

1. 将工作窗口转换为分钟区间。
2. 扣除固定日程和休息块。
3. 根据截止时间、优先级、认知负荷和能量状态排序任务。
4. 对候选空档打分：
   - 早截止优先。
   - 高能量时高负荷任务优先安排在上午或高效窗口。
   - 低能量时高负荷任务降权，低压力任务升权。
   - 复盘发现预估不足的标签自动放大时长。
5. 输出日程和问题列表。

### 微任务晶体推荐

输入：今日日程、微任务、工作窗口、当前时间、能量状态。

策略：

1. 计算空档区间。
2. 优先使用短空档。
3. 对微任务按匹配度、优先级、能量适配、剩余浪费时间打分。
4. 返回可一键插入的推荐项。

### 团队黄金窗口

输入：成员日程、共享权限、能量状态、会议时长、最少参与人数。

策略：

1. 对每个成员计算空闲区间。
2. 权限为 `none` 的成员不展示细节。
3. 能量低于门槛的成员不参与推荐，但仍参与冲突检查。
4. 按 5 分钟粒度扫描共同空闲区间。
5. 用参与人数、开始时间和冲突风险计算得分。

### 复盘分析

输入：任务事件。

输出：

1. 完成率。
2. 计划时长与实际时长。
3. 实际时长分布。
4. 延期归因：预估不足、打断、上下文切换、顺延、未知。
5. 行动建议。
6. 调度参数更新。

## 前端结构调整

1. 新增 `lib/services/api_client.dart`
   - 封装 baseUrl、token、GET/POST/PUT/DELETE、超时、错误对象。

2. 完善 `lib/services/remote_data_service.dart`
   - 实现全部 `DataService` 方法。
   - JSON 转换复用现有 model 的 `toJson/fromJson`。

3. 调整 `lib/services/app_services.dart`
   - 默认使用 `CompositeDataService(local: LocalDataService.instance, remote: RemoteDataService.instance, preferRemoteReads: true)`。
   - 如果后端不可用，自动回退本地。

4. 新增 `lib/config/app_config.dart`
   - Web 默认 `http://127.0.0.1:8000`。
   - Android 模拟器默认 `http://10.0.2.2:8000`。
   - Windows/桌面默认 `http://127.0.0.1:8000`。
   - 支持 `--dart-define=API_BASE_URL=...` 覆盖。

5. 页面优化
   - 抽取通用视觉组件：状态卡、指标卡、响应式内容容器、空状态、错误状态。
   - 修复已有中文乱码文本，优先从 `AppStrings` 读取。
   - 日程、团队、复盘页面减少超大单文件压力，逐步拆分局部组件。

## 测试与验收

### 后端

1. `python -m pytest`
2. `uvicorn main:app --reload`
3. 访问 `http://127.0.0.1:8000/docs`
4. smoke 流程：
   - 注册用户。
   - 新增日程。
   - 新增微任务。
   - 调用智能排程。
   - 上报完成事件。
   - 生成周报。
   - 创建团队成员。
   - 检测冲突和黄金窗口。

### 前端

1. `flutter analyze`
2. `flutter test`
3. `flutter run -d chrome --dart-define=API_BASE_URL=http://127.0.0.1:8000`
4. Android/Windows 验证时从真实项目根目录运行，不从插件缓存目录运行。
5. 断开后端后，确认本地兜底仍能展示基础数据。

## 风险与处理

1. 中文乱码
   - 当前部分文件已有乱码字符串。处理方式是将用户可见文本逐步迁移到 `AppStrings`，并用 UTF-8 保存。

2. 后端和 Flutter 模型不一致
   - 以现有 Flutter model 字段为第一版契约；后端 schema 尽量同名。

3. Android 模拟器访问本机后端失败
   - 使用 `10.0.2.2:8000`；真机需要替换为电脑局域网 IP。

4. 当前 git 工作区复杂
   - 实施时只改任务相关文件，不回退已有新增或修改。

5. 大页面维护困难
   - 首轮只做必要拆分，避免重构过深影响功能。

## 实施顺序

1. 后端脚手架和数据库初始化。
2. 后端核心 API：认证、日程、微任务、情绪。
3. 后端算法 API：排程、微任务晶体、团队黄金窗口、复盘。
4. Flutter `ApiClient` 和 `RemoteDataService`。
5. `AppServices` 切换为远程优先/本地兜底。
6. 桌面/Web 主控台界面优化。
7. 移动端响应式优化。
8. 修复中文乱码和交互细节。
9. 后端测试、Flutter 测试、端到端演示验证。
