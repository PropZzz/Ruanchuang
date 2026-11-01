# 时序智配 | Temporal Intelligence Scheduler

> 面向高压知识工作者的日程崩溃救援与精力保护系统

## 当前源码与启动入口

- 线上 Web：`web/` 中的 HTML/JS；桌面、移动页面均在此维护。`web/index.html` 加载统一路由与持久页面宿主。
- 原生客户端：`lib/` 中的 Flutter/Dart；保留 Android、iOS、Windows、macOS、Linux 工程及其资源、测试。
- 后端：`backend/` 中唯一的 FastAPI + SQLite 服务，入口 `backend.main:app`，由 Web 和 Flutter 共用。
- 本地 Web：运行 `run_web_preview.bat`；它检查当前源码，不再从旧设计导出复制页面。
- Web 构建：`node tools/build_stitch_web.mjs`；发布：`python deploy/deploy_web_release.py`，通过交互提示输入 SSH 密码。
- 目录边界与验证命令见 [当前架构](docs/current-architecture.md)；旧导出清理记录见 [2026-10-29 清理记录](docs/cleanup-2026-10-29.md)。
- 2026-10-31 收口验证：Flutter analyze 无问题，Flutter **398 项**通过，后端连续两轮各 **265 项**通过，Node **34 项**通过，调度共享向量 **13/13** 一致。详见 [验证记录](docs/verification-2026-10-31.md) 和 [执行清单](docs/superpowers/plans/2026-10-31-project-closeout.md)。
- 2026-11-01 已向现有服务器部署持久会话、CORS、每日备份和旧库救援修复，后端扩展至 **267 项**测试；部署和恢复证据见 [生产验收](docs/production-acceptance-2026-11-01.md)。用户暂无正式域名，HTTPS 尚未启用。

---

## 比赛主线：可落实的日程救援闭环

1. 用户为紧急任务输入精确到日期和时间的截止点，系统拒绝已过期或不完整的输入。
2. 调度引擎生成三种可解释方案：优先截点、优先恢复时间、尽量少动原计划；每张卡片展示原因、代价和受影响任务。
3. 用户确认后，方案会持久化写入日程；撤销操作会恢复原排期，并保留可追溯的操作记录。
4. 周/月复盘页会展示日程救援的接受与撤销历史，帮助用户判断策略是否真正减少了计划崩溃。

## 数据可靠性

- 模拟周数据先在内存中完整构建，再通过一次批量操作持久化；写入失败不会留下部分模拟事件，也不会生成误导性的复盘报告。
- 远端批量事件写入由 SQLite 事务保护；本地存储会在保存失败时回滚快照。
- 远端救援采用与撤销在单个 SQLite 事务内完成：基线哈希校验通过后，日程写入、`rescue_accept:`/`rescue_undo:` 事件与撤销快照要么全部落库，要么全部回滚；快照 ID 支持撤销与复盘追溯。
- 只有远端不可用或网络/服务端暂时故障时才使用本地兜底。认证、校验、冲突和响应格式错误会明确返回，避免把错误数据当成空结果。

## 调度基准与性能证据

规则正确且 Dart/Python 跨语言结果一致后，先运行 parity，再采集调度性能：

```powershell
python scripts/scheduling_parity.py
python scripts/scheduling_benchmark.py --parity-report reports/shared-vector-diff.json
```

基准命令默认会先刷新 parity，并将新报告写入临时 `reports-dir` 后读取；即使
parity runner 返回非零，只要临时目录产生了新报告，也会保留该报告中的 mismatch
诊断并按门禁阻断。需要明确复用已有报告时使用
`python scripts/scheduling_benchmark.py --no-refresh-parity --parity-report reports/shared-vector-diff.json`；此报告可能已过期，脚本会提示 stale 风险。

只有 parity 报告满足 `mismatched=0`、`invalid=0`、`pending_a_review=0`，且 Dart
运行 `returncode=0` 时，基准脚本才会采集测量数据。2026-10-31 当前结果为
`total=13`、`matched=13`、`mismatched=0`、`invalid=0`，新增半分钟舍入回归；
解释码和阻塞依赖来自双端真实输出。修复与断言审查见 [契约说明](contracts/scheduling/v1/README.md)。
门禁不满足时仍生成 `status=blocked`、退出码 `2`，不产生性能测量。

基准默认覆盖任务数量 `10/50/100/200`，`seed=20260916`，预热 `2` 次、采样
`10` 次、超时 `1000ms`。每次运行在 `reports/benchmarks` 生成带时间戳的 JSON
和 Markdown 报告，记录任务数量、规划耗时（包括 P50/P95/P99）、
`peakMemoryBytes`（`tracemalloc` 调用期间的 Python 分配增量估计）、
`peakRssBytes`（Windows 使用 `psutil.peak_wset`；Linux 使用 `resource.ru_maxrss`，
统一为字节）、`rssSource`、`rssScope`，以及 `timeout`、`failure`、
`degraded` 与各策略指标。普通业务 issues 只描述调度问题，不等于
`degraded` 降级状态。

[最新本地基准](reports/benchmarks/scheduling-benchmark-20261031T152150Z.md) 的 80 个采样
均成功，超时和失败均为 0。200 项任务的 plan P95 为 14.511ms、三策略 rescue P95
为 41.854ms。这是固定种子、本机 Python 和分配追踪下的结果，不代表生产吞吐或
其他算法的比较结论。RSS 是含解释器、导入开销的进程生命周期高水位；
`peakMemoryBytes` 才是调用期间的 Python 分配增量估计。两者不能混用。

超时调用中，可 pickle 的调用使用可终止的 process；不可 pickle 的调用回退到
daemon thread。thread 超时会立即返回并标记 `timeoutUncancellable=true`，因此不能
作为调用已取消或无污染的超时证据。

## 🧠 项目简介

时序智配是一套本地优先的智能日程调度系统。它聚焦一个真实且高频的问题：
当临时任务、会议延期或状态下降打乱原计划时，系统能否给出有解释的重排方案，
让用户在截止时间、恢复时间和计划稳定性之间做出选择。

---

## 🚀 核心价值

- ⏱️ **状态适配**：根据任务优先级、认知负荷、时间窗口和当前能量安排任务
- 🧭 **日程救援**：突发任务进入后生成三种可解释的重排策略
- ↩️ **用户可控**：接受方案前可比较权衡，接受后支持撤销，不强行覆盖日程
- 📈 **执行闭环**：记录任务事件，为复盘和后续策略调整提供证据

---

## 🏗️ 系统架构

输入层 → 调度层 → 解释与确认层 → 执行层 → 事件复盘层


- **输入层**：日程、任务、工作窗口、用户主动填写的能量状态
- **调度层**：启发式调度引擎与日程救援服务
- **解释与确认层**：展示每个方案的原因、代价、移动任务数和恢复缓冲
- **执行层**：本地持久化、远程 REST API、提醒与撤销
- **事件复盘层**：记录接受、撤销、完成和延期等任务事件


## 🎯 应用场景

- 📚 学习规划：考试周临时任务插入后的复习计划保护
- 🧑‍💻 开发任务调度：线上故障、客户需求和会议延期后的日程救援
- 🧑‍🤝‍🧑 团队协作：在共享边界内减少排会和冲突协调成本
- 🧘 个人精力保护：在疲劳或连续被打断时保留恢复缓冲

---

## 📊 项目亮点

- ✅ 把“日程被打乱后怎么办”做成可演示、可测试的核心流程
- ✅ 三种策略对应明确取舍：保截止时间、保恢复时间、少改原计划
- ✅ 本地优先，后端不可用时仍能完成核心日程操作
- ✅ 事件记录让每次调度选择都能进入复盘，而不是只留下结果

---

## 🔥 一句话总结

> 日程被打乱时，先把选择权交还给人，再让系统负责计算代价。

---

⭐⭐⭐
