# Scheduling Shared Vectors v1

这组 JSON 是 Dart 和 Python 调度实现共同读取的输入语料。fixture 只描述
可观察的计划、救援和事务状态，不携带任何一端的实现细节。每个文件都必须
包含 `schemaVersion`、`id`、`kind`、`tags`、`request`、`assertions` 和
`review`。

## 场景覆盖

当前语料覆盖以下标签：

`fixed_conflict`、`work_window`、`deadline_infeasible`、`dependency_blocked`、
`low_energy_match`、`rescue_strategies`、`no_available_block`、`overdue`、
`apply_rollback`、`undo_restore`、`timeout`、`boundary_time`、`duration_rounding`。
当前共 13 个共享向量。

## 请求类型

- `kind: plan`：`request` 使用 `SchedulingRequest` 的 JSON 形状：`day`、
  `tasks`、`windows`、`energy`、可选 `tuning` 和 `fixed`。
- `kind: rescue`：`request` 还包含 `urgentTask`、`currentEntries` 和
  `strategies`，可以直接映射 Python `build_options` 和 Dart
  `ScheduleRescueService.propose`。
- `kind: transaction`：`request` 描述内存事务适配器的 `before`、`after`、
  操作和可控失败点；不伪造生产 API 的返回值。
- `kind: boundary`：`request` 描述边界或超时输入；结果通过
  `assertions.finalState` 表达状态不变量。

## Canonical 断言

计划 fixture 的 `assertions` 固定包含：

- `taskOrder`：按时间排序的 entry id；
- `timeBlocks`：`id` 到 `{hour, minute, durationMinutes}` 的映射；
- `issues`：问题对象列表，每项包含 `code`、`taskId`、`blockedBy` 和
  `explanationCodes`；
- `explanationCodes`：不依赖人类语言的解释码列表。

救援 fixture 额外包含 `strategies`，顺序必须是
`protectDeadline`、`protectRecovery`、`minimizeChanges`。每个策略包含
`strategy`、`taskOrder`、`timeBlocks`、`issues` 和 `explanationCodes`。

事务和边界 fixture 不要求伪造计划输出，只要求
`assertions.finalState` 记录可比较的不变量，例如原计划是否保留、撤销后
是否精确恢复、是否报告 `timeout`。

颜色、标题、提示语和持久化字段不参与跨语言等价比较。问题码、任务顺序、
时间块、阻塞依赖和解释码必须比较；两端各自的原始消息可保留在诊断结果中。

## review 分类

`review.classification` 只能是 `implementation_error`、`contract_error`、
`allowed_difference` 或 `pending_a_review`，并且必须有非空 `reason`。初始
语料在 A 尚未完成双端执行和逐字段审查前使用 `pending_a_review`；不能把
未解释的差异预先标成允许差异。

## 运行门槛

```powershell
dart pub get --enforce-lockfile
python -m pytest backend/tests/test_shared_vector_schema.py -q
python scripts/scheduling_parity.py
```

先准备锁文件依赖，再执行 runner；runner 使用 `flutter test --no-pub`，避免每次对拍
重复触发本机平台插件准备。运行环境需能从 PATH 找到 Flutter。

调度基准默认会刷新 parity：使用临时 `reports-dir` 执行 runner，并在 runner 非零
但已生成新报告时保留该报告的 mismatch 诊断。若需复用已有报告，必须显式传入
`--no-refresh-parity --parity-report reports/shared-vector-diff.json`；已有报告可能
已过期，脚本会提示 stale 风险。

比较器必须分别执行 Dart 和 Python，输出逐 fixture、逐 runtime、逐字段的
差异报告。只要 `mismatched > 0`、`invalid > 0`、`pending_a_review > 0`、Dart
runner 的 `invalid` 为真或 `returncode != 0`，或存在未分类差异，就不能宣称
两端一致，也不能为了消除报告而单独修改某一端的生产算法。

## 性能基准门槛

性能基准必须在 parity 通过后运行：只有 `mismatched=0`、`invalid=0`、
`pending_a_review=0` 且 Dart `returncode=0`，才能采集调度测量。parity 未通过时，
基准报告使用 `status=blocked`，退出码为 `2`，并且不产生任何性能数据；
blocked 报告是门槛状态证据，不是性能结果。

基准覆盖三种策略（`protectDeadline`、`protectRecovery`、`minimizeChanges`）和
任务规模 `10/50/100/200`，默认 `seed=20260916`、预热 `2` 次、采样 `10` 次、
超时 `1000ms`。带时间戳的 JSON/Markdown 报告位于 `reports/benchmarks`，应至少
记录任务数量、规划耗时 P50/P95/P99、`peakMemoryBytes`（`tracemalloc` 调用期间
的 Python 分配增量估计）、`peakRssBytes`（操作系统进程高水位）、
`rssSource`、`rssScope` 和 `rssSampleCount`，以及超时、失败、降级和各策略指标。Windows
固定使用 psutil 7.2.2 的 `peak_wset`；Linux 的 `ru_maxrss` 从 KiB 转换为字节；
其他不支持的计数器保留 `null/unavailable`，不以当前 RSS 冒充峰值。普通业务 `issues` 不等于
`degraded`；降级必须由调度运行状态明确记录。

可 pickle 的超时调用使用可终止的 process；不可 pickle 的调用回退到 daemon
thread。thread 超时会立即返回并标记 `timeoutUncancellable=true`，不能据此证明
调用已取消或没有后台污染。

在获得有效 parity 和可重复的基准数据之前，禁止以性能假设推动 Go、Rust 或
C++ 重写调度核心。

## 2026-10-31 复核与修复

当前报告 `reports/shared-vector-diff.json` / `.md`：13 matched，0 mismatched，
0 invalid，Dart returncode 0，pending review 0。7 项契约断言修正、3 项实现修复和
3 项同状态事务/边界用例的分类理由保存在各 fixture 的 `review.reason`。

- 固定日程只占用自身时段，任务可排在固定块之前；工作窗口不是解释码。
- 软截止延误使用 `miss_due` 和 `deadline_proximity`；逾期问题与解释码分开比较。
- 依赖阻塞用例现在包含真正缺失的前置任务。原用例的前置任务已成功安排，剩余空间
  不足应为 `no_slot`，不能把满足依赖的任务硬判为依赖阻塞。
- 无工作窗口时输出 `no_slot`；不发明默认回退窗口。救援断言按当前三策略规则审查。
- 公开调优默认值 `highLoadPenaltyWhenLowEnergy=1.0`。Python 私有 1.2 默认值已对齐；
  调用方仍可显式传 1.2，保留对应自定义倍率测试。
- 正数恰为半分钟时向上取整，10.5 分钟得到 11 分钟；两端一致。
- 1 分钟任务的持久时长仍是 1 分钟；视觉点击区域的最小尺寸由渲染层处理。
- 比较器与 Dart runner 保留实际 `explanationCodes` 和 `blockedBy`，不填空或忽略元数据。

最新基准为 `reports/benchmarks/scheduling-benchmark-20261031T152150Z.{json,md}`，
80 个采样、0 超时、0 失败，超时预算仍为 1000ms。较早的 `141912Z` 报告保留了
修复队列读取顺序前的假超时，不能作为成功基准引用。

## 历史：2026-09-15 A 判定

当时的实际运行（Python 3.10.11、Flutter 3.38.7/Dart 3.10.7）执行全部 12 个
fixture：`matched=3`、`mismatched=9`、`invalid=0`，命令因未获允许的差异返回
非零。[当时的主线报告](https://github.com/PropZzz/Ruanchuang/blob/44cb49f2ad65158217bc200c5a68592b6efecfea/reports/shared-vector-diff.md)
可从基线提交查看；当前同名报告已刷新，不再代表旧状态。

- `contract_error`：固定块前后顺序的过强断言、未定义的 `work_window`/
  `deadline_infeasible` 解释/问题码，以及把非硬约束空档写死的救援断言。
- `implementation_error`：依赖阻塞、低精力排序与时长、空窗口回退、逾期检查、
  Dart 边界时长和 Python/Dart protectRecovery 时长未对齐。
- `allowed_difference`：应用失败回滚、撤销恢复原计划、超时保留原计划；三项均
  在两端观察到相同最终状态。

这些是历史分类；本轮重新检查了实际依赖和空窗口语义，修正了其中的误归类。
