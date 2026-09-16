# 调度基准与性能证据设计

## 目标

为当前 Python/Dart 调度实现建立可重复、可审计的性能基线，记录任务数量、规划耗时、超时行为、三种救援策略结果、失败与降级情况。基准结果只用于性能证据，不改变调度规则，也不为 Go、Rust 或 C++ 重写预设结论。

## 前置门禁

基准命令默认先执行共享向量 parity 检查，并读取其机器报告。只有 parity 报告的 `summary.mismatched` 或 `summary.invalid` 大于 `0`、`pending_a_review` 计数大于 `0`，或 Dart 的 `invalid` 不为 `false`/`returncode` 不为 `0` 时，基准才会写出 `status: blocked` 的报告，记录阻断原因和 parity 摘要，然后以非零状态退出；不会把未对齐实现的耗时发布为可比较基线。用户可在 parity 全部通过后运行同一命令获得 `status: completed` 报告。

## 运行矩阵

- 运行时：Python `SchedulerCore`/`build_options`，以及可用时通过一个明确输出协议启动的 Dart runner。
- 任务规模：默认 `10, 50, 100, 200` 项，另支持 `--task-count` 重复指定；200 项对应后端守则建议的单日真实规模。
- 规划：每个运行时、每个规模、固定随机种子生成相同的单日任务、工作窗口、固定块和能量输入，执行预热轮后执行指定测量轮。
- 救援：对每个规模执行 `protectDeadline`、`protectRecovery`、`minimizeChanges`，记录每策略的计划状态、entry 数、issue 数、hard issue 数、移动任务数、恢复分钟数和推荐标记。
- 超时：默认使用受控的规划预算；每次调用都记录是否超时、预算毫秒和实际耗时。超时不能被吞掉或计为成功。

## 报告契约

每次运行在 `reports/benchmarks/scheduling-benchmark-<UTC timestamp>.json` 和对应 Markdown 文件中写入完整报告。JSON 至少包含：

- `schemaVersion`、`status`、`command`、`startedAt`、`finishedAt`、`seed`；
- `gate`：parity 状态、摘要、阻断原因；
- `runs`：runtime、taskCount、warmups、samples、P50/P95/P99、min/max、timeoutCount、failureCount、degradedCount、`peakMemoryBytes`、`peakRssBytes` 和 `rssSource`；其中 `peakMemoryBytes` 是 `tracemalloc` 调用期间的 Python 分配增量估计，`peakRssBytes` 当前为 `null`/未采集，不能当作 RSS 测量值；
- `strategies`：taskCount、strategy、success/failure/timeout/degraded 计数、entry/issue/hardIssue/moved/recovery 指标和结果摘要；
- `errors`：运行时、规模、策略、阶段、异常类型和消息。

耗时分位数使用排序后的样本线性插值，统一以毫秒和整数微秒精度记录；`peakMemoryBytes` 使用 `tracemalloc` 记录调用期间的 Python 分配增量估计，`peakRssBytes` 当前不采集并保持 `null`。`rssSource` 使用 `unavailable` 表示 RSS 不可用；若未来复用父进程峰值，应标记为 `parentPeakMemoryBytes`，不得声称其为当前运行的 RSS。降级只统计明确返回的降级状态或 fallback 标记，不能把普通业务 issue 误报为降级。

## 失败与可复现性

输入生成只使用标准库和固定种子，任务 id、排序和时间窗口确定性稳定。单个样本失败会保留错误并继续同一矩阵的其他样本；进程级启动失败或超时会标记该 runtime 不可用。报告始终写出，退出码在 parity 阻断、基准失败或缺少可比较样本时为非零。脚本不覆盖已有报告。

## 测试与非目标

先为门禁、分位数、确定性输入、超时/失败分类、策略摘要和报告写 pytest 失败测试，再实现最小基准模块。测试使用短矩阵和注入的时钟/runner，不启动真实 Flutter。真实运行命令另行验证 parity、Python 全量测试和（环境具备时）Dart runner。

本设计不重写 `backend/scheduling`、Dart `SchedulerCore`、REST API、持久化或救援事务；不把 benchmark 结果转化为语言迁移决策，迁移仍需后续基于完成状态报告和跨语言一致性证据评审。
