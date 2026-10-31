# Dart/Python 共享调度向量差异报告

本报告由 Dart runner 和 Python runner 实际执行生成；不使用断言替代运行结果。

- 场景总数：13
- matched：13
- mismatched：0
- invalid：0

## A 分类统计

按场景统计：
- allowed_difference：3
- contract_error：7
- implementation_error：3
- pending_a_review：0

按差异条数统计：
- allowed_difference：0
- contract_error：0
- implementation_error：0
- pending_a_review：0

## 逐场景结果

### 001-fixed-conflict.json：matched

- A 分类：contract_error
- 原因：双端实际结果一致；固定日程只占用 09:00-10:00，不要求任务全部排在固定块之后，原断言错误要求 focus 从 10:00 开始。
- 差异：无

### 002-work-window.json：matched

- A 分类：contract_error
- 原因：双端必须把任务安排在 13:00-15:00 工作窗口内，并输出实际 priority/energy_fit；work_window 是场景标签，不是 v1 稳定解释码。
- 差异：无

### 003-deadline-infeasible.json：matched

- A 分类：contract_error
- 原因：两端均按现有 miss_due 语义输出；后端守则列出的稳定问题码没有 deadline_infeasible，原断言使用了未定义问题码和解释码。
- 差异：无

### 004-dependency-blocked.json：matched

- A 分类：contract_error
- 原因：原前置任务已成功排入，依赖已满足，剩余空间不足应为 no_slot；本用例改为缺失前置任务，明确验证 dependency_blocked 和真实 blockedBy，不把问题码当作解释码。
- 差异：无

### 005-low-energy-match.json：matched

- A 分类：implementation_error
- 原因：默认时长倍率按公开调优模型统一为 1.0；增加下午窗口以验证低精力的跨窗口匹配：高负荷任务选下午、低负荷任务留在上午，保持 due/priority/duration/id 稳定排序。
- 差异：无

### 006-rescue-strategies.json：matched

- A 分类：contract_error
- 原因：按当前三策略规则比较实际解释码，不使用未定义的策略解释码；截止策略不强制下午空档，恢复策略降低一档精力并对中负荷使用 1.05 倍率，恢复缓冲安排在合法下午空档。
- 差异：无

### 007-no-available-block.json：matched

- A 分类：contract_error
- 原因：当前双端均遵守空窗口硬约束，不安排任务；统一断言 v1 稳定问题码 no_slot，不使用未定义的 no_available_block 及同名解释码。
- 差异：无

### 008-overdue.json：matched

- A 分类：contract_error
- 原因：当前双端均输出 overdue 问题；解释码必须是稳定的 deadline_proximity，并保留计划 entry 的 priority/energy_fit，不把问题码当作解释码。
- 差异：无

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

### 012-boundary-time.json：matched

- A 分类：implementation_error
- 原因：修复 Dart 持久化高度的 15 分钟下限，保留 1 分钟真实时长；boundary_time 是覆盖标签，实际比较 deadline_proximity/priority 解释码。
- 差异：无

### 013-duration-rounding.json：matched

- A 分类：implementation_error
- 原因：低精力中负荷倍率 1.05 将 10 分钟变为 10.5 分钟；跨端统一按正数半分钟向上取整为 11 分钟，持久化时长不受视图最小高度影响。
- 差异：无

## 对齐门槛

存在 `pending_a_review`、invalid、未分类差异或未获允许的差异时，不能宣称 Dart/Python 已一致；未对齐前不得单独修改某一端生产算法来消除报告。
