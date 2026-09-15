# Dart/Python 共享调度向量差异报告

本报告由 Dart runner 和 Python runner 实际执行生成；不使用断言替代运行结果。

- 场景总数：12
- matched：3
- mismatched：9
- invalid：0

## A 分类统计

- allowed_difference：0
- contract_error：0
- implementation_error：0
- pending_a_review：72

## 逐场景结果

### 001-fixed-conflict.json：mismatched

- A 分类：pending_a_review
- 原因：双端执行后确认固定块冲突消解和 canonical 顺序。
- 差异：
  - `python_vs_assertions` `taskOrder[0]`：expected="fixed-standup"；actual="focus"；分类=pending_a_review
  - `python_vs_assertions` `taskOrder[1]`：expected="focus"；actual="fixed-standup"；分类=pending_a_review
  - `python_vs_assertions` `timeBlocks.focus.hour`：expected=10；actual=8；分类=pending_a_review
  - `python_vs_assertions` `timeBlocks.quick.hour`：expected=11；actual=10；分类=pending_a_review
  - `dart_vs_assertions` `taskOrder[0]`：expected="fixed-standup"；actual="focus"；分类=pending_a_review
  - `dart_vs_assertions` `taskOrder[1]`：expected="focus"；actual="fixed-standup"；分类=pending_a_review
  - `dart_vs_assertions` `timeBlocks.focus.hour`：expected=10；actual=8；分类=pending_a_review
  - `dart_vs_assertions` `timeBlocks.quick.hour`：expected=11；actual=10；分类=pending_a_review

### 002-work-window.json：mismatched

- A 分类：pending_a_review
- 原因：确认任务只落在声明的工作窗口内。
- 差异：
  - `python_vs_assertions` `explanationCodes.length`：expected=1；actual=0；分类=pending_a_review
  - `dart_vs_assertions` `explanationCodes.length`：expected=1；actual=0；分类=pending_a_review

### 003-deadline-infeasible.json：mismatched

- A 分类：pending_a_review
- 原因：A 需要决定不可行截止应使用专用问题码还是 miss_due。
- 差异：
  - `python_vs_assertions` `explanationCodes.length`：expected=1；actual=0；分类=pending_a_review
  - `python_vs_assertions` `issues[0].code`：expected="deadline_infeasible"；actual="miss_due"；分类=pending_a_review
  - `python_vs_assertions` `issues[0].explanationCodes.length`：expected=1；actual=0；分类=pending_a_review
  - `dart_vs_assertions` `explanationCodes.length`：expected=1；actual=0；分类=pending_a_review
  - `dart_vs_assertions` `issues[0].code`：expected="deadline_infeasible"；actual="miss_due"；分类=pending_a_review
  - `dart_vs_assertions` `issues[0].explanationCodes.length`：expected=1；actual=0；分类=pending_a_review

### 004-dependency-blocked.json：mismatched

- A 分类：pending_a_review
- 原因：当前 PlanTask 兼容输入保留 dependsOn，但两端是否执行依赖约束待 A 判定。
- 差异：
  - `python_vs_assertions` `explanationCodes.length`：expected=1；actual=0；分类=pending_a_review
  - `python_vs_assertions` `issues[0].blockedBy.length`：expected=1；actual=0；分类=pending_a_review
  - `python_vs_assertions` `issues[0].code`：expected="dependency_blocked"；actual="no_slot"；分类=pending_a_review
  - `python_vs_assertions` `issues[0].explanationCodes.length`：expected=1；actual=0；分类=pending_a_review
  - `dart_vs_assertions` `explanationCodes.length`：expected=1；actual=0；分类=pending_a_review
  - `dart_vs_assertions` `issues[0].blockedBy.length`：expected=1；actual=0；分类=pending_a_review
  - `dart_vs_assertions` `issues[0].code`：expected="dependency_blocked"；actual="no_slot"；分类=pending_a_review
  - `dart_vs_assertions` `issues[0].explanationCodes.length`：expected=1；actual=0；分类=pending_a_review

### 005-low-energy-match.json：mismatched

- A 分类：pending_a_review
- 原因：确认低精力排序是否优先低负荷任务且不改变任务时长。
- 差异：
  - `dart_vs_python` `entries[0].durationMinutes`：expected=72；actual=60；分类=pending_a_review
  - `dart_vs_python` `entries[0].id`：expected="high-load"；actual="low-load"；分类=pending_a_review
  - `dart_vs_python` `entries[1].id`：expected="low-load"；actual="high-load"；分类=pending_a_review
  - `dart_vs_python` `entries[1].time.minute`：expected=12；actual=0；分类=pending_a_review
  - `python_vs_assertions` `explanationCodes.length`：expected=1；actual=0；分类=pending_a_review
  - `python_vs_assertions` `taskOrder[0]`：expected="low-load"；actual="high-load"；分类=pending_a_review
  - `python_vs_assertions` `taskOrder[1]`：expected="high-load"；actual="low-load"；分类=pending_a_review
  - `python_vs_assertions` `timeBlocks.high-load.durationMinutes`：expected=60；actual=72；分类=pending_a_review
  - `python_vs_assertions` `timeBlocks.high-load.hour`：expected=9；actual=8；分类=pending_a_review
  - `python_vs_assertions` `timeBlocks.low-load.hour`：expected=8；actual=9；分类=pending_a_review
  - `python_vs_assertions` `timeBlocks.low-load.minute`：expected=0；actual=12；分类=pending_a_review
  - `dart_vs_assertions` `explanationCodes.length`：expected=1；actual=0；分类=pending_a_review

### 006-rescue-strategies.json：mismatched

- A 分类：pending_a_review
- 原因：三种救援策略需要逐策略比较顺序、时间块、问题码和解释码。
- 差异：
  - `dart_vs_python` `strategies[1].entries[0].durationMinutes`：expected=32；actual=30；分类=pending_a_review
  - `dart_vs_python` `strategies[1].entries[1].time.minute`：expected=32；actual=30；分类=pending_a_review
  - `dart_vs_python` `strategies[1].entries[2].durationMinutes`：expected=63；actual=60；分类=pending_a_review
  - `dart_vs_python` `strategies[1].entries[2].time.minute`：expected=2；actual=0；分类=pending_a_review
  - `python_vs_assertions` `strategies[0].explanationCodes.length`：expected=1；actual=0；分类=pending_a_review
  - `python_vs_assertions` `strategies[0].timeBlocks.review.hour`：expected=13；actual=10；分类=pending_a_review
  - `python_vs_assertions` `strategies[0].timeBlocks.review.minute`：expected=30；actual=0；分类=pending_a_review
  - `python_vs_assertions` `strategies[1].explanationCodes.length`：expected=1；actual=0；分类=pending_a_review
  - `python_vs_assertions` `strategies[1].timeBlocks.deep.minute`：expected=30；actual=32；分类=pending_a_review
  - `python_vs_assertions` `strategies[1].timeBlocks.review.durationMinutes`：expected=60；actual=63；分类=pending_a_review
  - `python_vs_assertions` `strategies[1].timeBlocks.review.minute`：expected=0；actual=2；分类=pending_a_review
  - `python_vs_assertions` `strategies[1].timeBlocks.urgent.durationMinutes`：expected=30；actual=32；分类=pending_a_review
  - `python_vs_assertions` `strategies[2].explanationCodes.length`：expected=1；actual=0；分类=pending_a_review
  - `dart_vs_assertions` `strategies[0].explanationCodes.length`：expected=1；actual=0；分类=pending_a_review
  - `dart_vs_assertions` `strategies[0].timeBlocks.review.hour`：expected=13；actual=10；分类=pending_a_review
  - `dart_vs_assertions` `strategies[0].timeBlocks.review.minute`：expected=30；actual=0；分类=pending_a_review
  - `dart_vs_assertions` `strategies[1].explanationCodes.length`：expected=1；actual=0；分类=pending_a_review
  - `dart_vs_assertions` `strategies[2].explanationCodes.length`：expected=1；actual=0；分类=pending_a_review

### 007-no-available-block.json：mismatched

- A 分类：pending_a_review
- 原因：Python 当前会在空窗口回退到 08:00-20:00，需由 A 判定契约或实现归属。
- 差异：
  - `dart_vs_python` `entries.length`：expected=1；actual=0；分类=pending_a_review
  - `dart_vs_python` `issues.length`：expected=0；actual=1；分类=pending_a_review
  - `python_vs_assertions` `explanationCodes.length`：expected=1；actual=0；分类=pending_a_review
  - `python_vs_assertions` `issues.length`：expected=1；actual=0；分类=pending_a_review
  - `python_vs_assertions` `taskOrder.length`：expected=0；actual=1；分类=pending_a_review
  - `python_vs_assertions` `timeBlocks.none-task`：expected=null；actual={"durationMinutes": 30, "hour": 8, "minute": 0}；分类=pending_a_review
  - `dart_vs_assertions` `explanationCodes.length`：expected=1；actual=0；分类=pending_a_review
  - `dart_vs_assertions` `issues[0].code`：expected="no_available_block"；actual="no_slot"；分类=pending_a_review
  - `dart_vs_assertions` `issues[0].explanationCodes.length`：expected=1；actual=0；分类=pending_a_review

### 008-overdue.json：mismatched

- A 分类：pending_a_review
- 原因：确认跨日截止的逾期问题码在 Dart 和 Python 中是否一致。
- 差异：
  - `dart_vs_python` `issues.length`：expected=1；actual=0；分类=pending_a_review
  - `python_vs_assertions` `explanationCodes.length`：expected=1；actual=0；分类=pending_a_review
  - `python_vs_assertions` `issues[0].explanationCodes.length`：expected=1；actual=0；分类=pending_a_review
  - `dart_vs_assertions` `explanationCodes.length`：expected=1；actual=0；分类=pending_a_review
  - `dart_vs_assertions` `issues.length`：expected=1；actual=0；分类=pending_a_review

### 009-apply-rollback.json：matched

- A 分类：pending_a_review
- 原因：应用写入失败后必须恢复 before 快照，并保留原始错误。
- 差异：无

### 010-undo-restore.json：matched

- A 分类：pending_a_review
- 原因：撤销救援后计划必须逐字段恢复到接受救援前的快照。
- 差异：无

### 011-timeout.json：matched

- A 分类：pending_a_review
- 原因：超时适配器只比较状态不变量，不伪造不存在的调度输出。
- 差异：无

### 012-boundary-time.json：mismatched

- A 分类：pending_a_review
- 原因：比较 00:00 和 23:59 前最后可用分钟的边界处理与时长换算。
- 差异：
  - `dart_vs_python` `entries[0].durationMinutes`：expected=1；actual=15；分类=pending_a_review
  - `python_vs_assertions` `explanationCodes.length`：expected=1；actual=0；分类=pending_a_review
  - `dart_vs_assertions` `explanationCodes.length`：expected=1；actual=0；分类=pending_a_review
  - `dart_vs_assertions` `timeBlocks.midnight.durationMinutes`：expected=1；actual=15；分类=pending_a_review

## 对齐门槛

存在 `pending_a_review`、invalid、未分类差异或未获允许的差异时，不能宣称 Dart/Python 已一致；未对齐前不得单独修改某一端生产算法来消除报告。
