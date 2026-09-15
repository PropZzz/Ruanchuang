# Dart/Python 共享调度向量差异报告

本报告由 Dart runner 和 Python runner 实际执行生成；不使用断言替代运行结果。

- 场景总数：12
- matched：3
- mismatched：9
- invalid：0

## A 分类统计

按场景统计：
- allowed_difference：3
- contract_error：3
- implementation_error：6
- pending_a_review：0

按差异条数统计：
- allowed_difference：0
- contract_error：16
- implementation_error：56
- pending_a_review：0

## 逐场景结果

### 001-fixed-conflict.json：mismatched

- A 分类：contract_error
- 原因：双端实际结果一致；固定日程只占用 09:00-10:00，不要求任务全部排在固定块之后，原断言错误要求 focus 从 10:00 开始。
- 差异：
  - `python_vs_assertions` `taskOrder[0]`：expected="fixed-standup"；actual="focus"；分类=contract_error
  - `python_vs_assertions` `taskOrder[1]`：expected="focus"；actual="fixed-standup"；分类=contract_error
  - `python_vs_assertions` `timeBlocks.focus.hour`：expected=10；actual=8；分类=contract_error
  - `python_vs_assertions` `timeBlocks.quick.hour`：expected=11；actual=10；分类=contract_error
  - `dart_vs_assertions` `taskOrder[0]`：expected="fixed-standup"；actual="focus"；分类=contract_error
  - `dart_vs_assertions` `taskOrder[1]`：expected="focus"；actual="fixed-standup"；分类=contract_error
  - `dart_vs_assertions` `timeBlocks.focus.hour`：expected=10；actual=8；分类=contract_error
  - `dart_vs_assertions` `timeBlocks.quick.hour`：expected=11；actual=10；分类=contract_error

### 002-work-window.json：mismatched

- A 分类：contract_error
- 原因：双端均把任务安排在 13:00-17:00 工作窗口内；work_window 不是现有稳定解释码，原断言的解释码要求超出契约。
- 差异：
  - `python_vs_assertions` `explanationCodes.length`：expected=1；actual=0；分类=contract_error
  - `dart_vs_assertions` `explanationCodes.length`：expected=1；actual=0；分类=contract_error

### 003-deadline-infeasible.json：mismatched

- A 分类：contract_error
- 原因：两端均按现有 miss_due 语义输出；后端守则列出的稳定问题码没有 deadline_infeasible，原断言使用了未定义问题码和解释码。
- 差异：
  - `python_vs_assertions` `explanationCodes.length`：expected=1；actual=0；分类=contract_error
  - `python_vs_assertions` `issues[0].code`：expected="deadline_infeasible"；actual="miss_due"；分类=contract_error
  - `python_vs_assertions` `issues[0].explanationCodes.length`：expected=1；actual=0；分类=contract_error
  - `dart_vs_assertions` `explanationCodes.length`：expected=1；actual=0；分类=contract_error
  - `dart_vs_assertions` `issues[0].code`：expected="deadline_infeasible"；actual="miss_due"；分类=contract_error
  - `dart_vs_assertions` `issues[0].explanationCodes.length`：expected=1；actual=0；分类=contract_error

### 004-dependency-blocked.json：mismatched

- A 分类：implementation_error
- 原因：后端守则明确要求 dependency_blocked 和 blockedBy；当前 Dart/Python 都忽略 dependsOn，实际输出 no_slot/空 blockedBy，属于两端尚未实现契约。
- 差异：
  - `python_vs_assertions` `explanationCodes.length`：expected=1；actual=0；分类=implementation_error
  - `python_vs_assertions` `issues[0].blockedBy.length`：expected=1；actual=0；分类=implementation_error
  - `python_vs_assertions` `issues[0].code`：expected="dependency_blocked"；actual="no_slot"；分类=implementation_error
  - `python_vs_assertions` `issues[0].explanationCodes.length`：expected=1；actual=0；分类=implementation_error
  - `dart_vs_assertions` `explanationCodes.length`：expected=1；actual=0；分类=implementation_error
  - `dart_vs_assertions` `issues[0].blockedBy.length`：expected=1；actual=0；分类=implementation_error
  - `dart_vs_assertions` `issues[0].code`：expected="dependency_blocked"；actual="no_slot"；分类=implementation_error
  - `dart_vs_assertions` `issues[0].explanationCodes.length`：expected=1；actual=0；分类=implementation_error

### 005-low-energy-match.json：mismatched

- A 分类：implementation_error
- 原因：Dart 按低负荷优先且保持 60 分钟；Python 按高优先级先排并把 high 任务放大到 72 分钟，违反低精力匹配与跨端规则。
- 差异：
  - `dart_vs_python` `entries[0].durationMinutes`：expected=72；actual=60；分类=implementation_error
  - `dart_vs_python` `entries[0].id`：expected="high-load"；actual="low-load"；分类=implementation_error
  - `dart_vs_python` `entries[1].id`：expected="low-load"；actual="high-load"；分类=implementation_error
  - `dart_vs_python` `entries[1].time.minute`：expected=12；actual=0；分类=implementation_error
  - `python_vs_assertions` `explanationCodes.length`：expected=1；actual=0；分类=implementation_error
  - `python_vs_assertions` `taskOrder[0]`：expected="low-load"；actual="high-load"；分类=implementation_error
  - `python_vs_assertions` `taskOrder[1]`：expected="high-load"；actual="low-load"；分类=implementation_error
  - `python_vs_assertions` `timeBlocks.high-load.durationMinutes`：expected=60；actual=72；分类=implementation_error
  - `python_vs_assertions` `timeBlocks.high-load.hour`：expected=9；actual=8；分类=implementation_error
  - `python_vs_assertions` `timeBlocks.low-load.hour`：expected=8；actual=9；分类=implementation_error
  - `python_vs_assertions` `timeBlocks.low-load.minute`：expected=0；actual=12；分类=implementation_error
  - `dart_vs_assertions` `explanationCodes.length`：expected=1；actual=0；分类=implementation_error

### 006-rescue-strategies.json：mismatched

- A 分类：implementation_error
- 原因：三策略顺序一致，但 protectRecovery 的 Python 时长/时间块与 Dart 不同，源于 Python 低精力时长惩罚；同时保护截止时间的示例断言把非硬约束的下午空档写死，需后续另行修订契约。
- 差异：
  - `dart_vs_python` `strategies[1].entries[0].durationMinutes`：expected=32；actual=30；分类=implementation_error
  - `dart_vs_python` `strategies[1].entries[1].time.minute`：expected=32；actual=30；分类=implementation_error
  - `dart_vs_python` `strategies[1].entries[2].durationMinutes`：expected=63；actual=60；分类=implementation_error
  - `dart_vs_python` `strategies[1].entries[2].time.minute`：expected=2；actual=0；分类=implementation_error
  - `python_vs_assertions` `strategies[0].explanationCodes.length`：expected=1；actual=0；分类=implementation_error
  - `python_vs_assertions` `strategies[0].timeBlocks.review.hour`：expected=13；actual=10；分类=implementation_error
  - `python_vs_assertions` `strategies[0].timeBlocks.review.minute`：expected=30；actual=0；分类=implementation_error
  - `python_vs_assertions` `strategies[1].explanationCodes.length`：expected=1；actual=0；分类=implementation_error
  - `python_vs_assertions` `strategies[1].timeBlocks.deep.minute`：expected=30；actual=32；分类=implementation_error
  - `python_vs_assertions` `strategies[1].timeBlocks.review.durationMinutes`：expected=60；actual=63；分类=implementation_error
  - `python_vs_assertions` `strategies[1].timeBlocks.review.minute`：expected=0；actual=2；分类=implementation_error
  - `python_vs_assertions` `strategies[1].timeBlocks.urgent.durationMinutes`：expected=30；actual=32；分类=implementation_error
  - `python_vs_assertions` `strategies[2].explanationCodes.length`：expected=1；actual=0；分类=implementation_error
  - `dart_vs_assertions` `strategies[0].explanationCodes.length`：expected=1；actual=0；分类=implementation_error
  - `dart_vs_assertions` `strategies[0].timeBlocks.review.hour`：expected=13；actual=10；分类=implementation_error
  - `dart_vs_assertions` `strategies[0].timeBlocks.review.minute`：expected=30；actual=0；分类=implementation_error
  - `dart_vs_assertions` `strategies[1].explanationCodes.length`：expected=1；actual=0；分类=implementation_error
  - `dart_vs_assertions` `strategies[2].explanationCodes.length`：expected=1；actual=0；分类=implementation_error

### 007-no-available-block.json：mismatched

- A 分类：implementation_error
- 原因：无有效工作窗口时 Dart 报 no_slot，而 Python 私自回退到 08:00-20:00 并安排任务；该回退不符合工作窗口硬约束。原断言的 no_available_block 也应收敛为稳定 no_slot。
- 差异：
  - `dart_vs_python` `entries.length`：expected=1；actual=0；分类=implementation_error
  - `dart_vs_python` `issues.length`：expected=0；actual=1；分类=implementation_error
  - `python_vs_assertions` `explanationCodes.length`：expected=1；actual=0；分类=implementation_error
  - `python_vs_assertions` `issues.length`：expected=1；actual=0；分类=implementation_error
  - `python_vs_assertions` `taskOrder.length`：expected=0；actual=1；分类=implementation_error
  - `python_vs_assertions` `timeBlocks.none-task`：expected=null；actual={"durationMinutes": 30, "hour": 8, "minute": 0}；分类=implementation_error
  - `dart_vs_assertions` `explanationCodes.length`：expected=1；actual=0；分类=implementation_error
  - `dart_vs_assertions` `issues[0].code`：expected="no_available_block"；actual="no_slot"；分类=implementation_error
  - `dart_vs_assertions` `issues[0].explanationCodes.length`：expected=1；actual=0；分类=implementation_error

### 008-overdue.json：mismatched

- A 分类：implementation_error
- 原因：Python 输出 overdue，Dart 没有跨日逾期问题；后端守则明确要求 overdue，Dart 端缺少该约束检查。
- 差异：
  - `dart_vs_python` `issues.length`：expected=1；actual=0；分类=implementation_error
  - `python_vs_assertions` `explanationCodes.length`：expected=1；actual=0；分类=implementation_error
  - `python_vs_assertions` `issues[0].explanationCodes.length`：expected=1；actual=0；分类=implementation_error
  - `dart_vs_assertions` `explanationCodes.length`：expected=1；actual=0；分类=implementation_error
  - `dart_vs_assertions` `issues.length`：expected=1；actual=0；分类=implementation_error

### 009-apply-rollback.json：matched

- A 分类：allowed_difference
- 原因：Dart 内存 persistence 适配器与 Python 事务观察器均恢复原计划并保留 apply_failed；该向量无可观察差异。
- 差异：无

### 010-undo-restore.json：matched

- A 分类：allowed_difference
- 原因：Dart persistence 与 Python 撤销观察器均逐字段恢复原始快照；该向量无可观察差异。
- 差异：无

### 011-timeout.json：matched

- A 分类：allowed_difference
- 原因：两端均确定性报告 timeout、无部分写入并保留原计划；entryIds 等额外诊断字段不属于断言差异。
- 差异：无

### 012-boundary-time.json：mismatched

- A 分类：implementation_error
- 原因：Python 保留 1 分钟边界时长，Dart 的 ScheduleEntry 高度最小值把 1 分钟任务扩大为 15 分钟；这是 Dart 边界时长转换错误，boundary_time 解释码也尚未实现。
- 差异：
  - `dart_vs_python` `entries[0].durationMinutes`：expected=1；actual=15；分类=implementation_error
  - `python_vs_assertions` `explanationCodes.length`：expected=1；actual=0；分类=implementation_error
  - `dart_vs_assertions` `explanationCodes.length`：expected=1；actual=0；分类=implementation_error
  - `dart_vs_assertions` `timeBlocks.midnight.durationMinutes`：expected=1；actual=15；分类=implementation_error

## 对齐门槛

存在 `pending_a_review`、invalid、未分类差异或未获允许的差异时，不能宣称 Dart/Python 已一致；未对齐前不得单独修改某一端生产算法来消除报告。
