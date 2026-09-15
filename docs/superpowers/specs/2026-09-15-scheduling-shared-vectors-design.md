# Dart/Python 共享调度测试向量设计

## 目标

建立一套由 Dart 和 Python 都执行的 JSON 调度/救援测试向量，比较任务顺序、时间块、问题码和解释码，并为每个差异保留 A 的判定和证据。执行结果不自动改写向量，也不修改任一端算法来隐藏差异。

## 契约

向量位于 `contracts/scheduling/v1/fixtures/*.json`。每个文件包含：

- `schemaVersion`、`id`、`kind`、`tags`；
- `request`（plan 或 rescue 的共享输入）；
- `assertions`，描述任务顺序、时间块、问题码和解释码的契约期望；
- `review`，由 A 维护，包含差异分类（`implementation_error`、`contract_error` 或 `allowed_difference`）和理由。

计划输出统一为只读 canonical 视图：`entries` 只保留 id、时间、时长、来源和解释码，`issues` 只保留 code、taskId、blockedBy 和解释码。颜色、文案和持久化字段不参与跨语言等价比较，但原始问题消息仍保留在诊断数据中。

向量覆盖固定日程冲突、工作窗口、不可行截止、依赖阻塞、低精力任务、三种救援策略、无可用块、逾期、应用失败回滚、撤销恢复和超时/边界时间。事务向量定义最终状态不变量（原计划是否保留、撤销后是否精确恢复、是否报告 timeout），不伪造不存在的算法输出。

## 执行协议

- Python：`scripts/scheduling_parity.py` 读取所有 fixture，直接调用现有 `plan_schedule`/`build_options`，并执行纯内存的回滚/撤销适配器。
- Dart：`test/shared_vector_runner_test.dart` 由 Flutter test 启动，调用现有 Dart 调度和救援服务，将 canonical 结果写入 runner 输出标记之间。
- 比较器：先比较 Dart/Python 的同一字段，再比较两者与契约 assertions；差异按 fixture、runtime、field 定位，附 `review` 分类。缺少 A 判定时状态为 `pending_a_review`。
- 报告：`reports/shared-vector-diff.json`（机器可读）和 `reports/shared-vector-diff.md`（人读），即使存在差异也写出完整报告；命令在有 invalid 或未允许差异时返回非零。

## 非目标

本次不重写 Dart/Python 排序、依赖、解释码或事务实现，不合并 `member-a` 分支的算法收敛提交，不把现有单端测试通过表述为跨语言一致。

## 验收

运行 `python scripts/scheduling_parity.py` 必须分别启动 Python 和 Flutter/Dart，发现并执行全部向量，输出逐字段差异和 A 分类。另行运行现有 Dart/Python 回归测试，确认共享 runner 没有改变生产代码行为。
