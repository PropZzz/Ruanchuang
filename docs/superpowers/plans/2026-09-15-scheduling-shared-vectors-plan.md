# Dart/Python 共享调度测试向量实施计划

> **给执行代理：** 按任务逐项执行，使用 checkbox 跟踪状态。实现任何行为前先写失败测试并确认失败。

**目标：** 建立一套 Dart/Python 共同执行的 JSON 调度与救援向量，生成逐字段差异报告，并由 A 明确标记实现错误、契约错误或允许差异。

**架构：** 向量位于 `contracts/scheduling/v1/fixtures`，只描述共享输入、可观察断言和 A 的审查元数据。Python runner 直接调用当前后端纯函数；Flutter test runner 调用当前 Dart 服务；Python 比较器启动两端、规范化结果、输出 JSON/Markdown 报告。不会修改算法实现来配平结果。

**技术栈：** Python 3.10、pytest、Flutter/Dart 3.10、JSON、PowerShell 可执行的 subprocess。

---

### 任务 1：建立共享向量语料和契约测试

**文件：**
- 新建：`contracts/scheduling/v1/fixtures/*.json`
- 新建：`contracts/scheduling/v1/README.md`
- 新建：`backend/tests/test_shared_vector_schema.py`

- [ ] 先写 schema 测试：自动发现 fixture，要求唯一 `id`、`kind`、`request`、`assertions`、`review`，并要求 12 个场景标签全部存在。
- [ ] 运行 `python -m pytest backend/tests/test_shared_vector_schema.py -q`，确认在 fixture 未完成时按预期失败。
- [ ] 添加向量，至少覆盖 `fixed_conflict`、`work_window`、`deadline_infeasible`、`dependency_blocked`、`low_energy_match`、`rescue_strategies`、`no_available_block`、`overdue`、`apply_rollback`、`undo_restore`、`timeout`、`boundary_time`。
- [ ] 计划向量的断言字段固定为任务 id 顺序、`id -> {hour,minute,durationMinutes}` 时间块、问题码和解释码；救援向量固定比较三策略顺序、每个方案的时间块/问题码/解释码；事务向量固定比较最终状态不变量。
- [ ] 每个向量的 `review` 初始值明确写出：当前已知差异标为 `implementation_error` 或 `contract_error` 候选；尚未判断的标为 `pending_a_review`，不默认视为允许。
- [ ] 重新运行 schema 测试并执行 `git diff --check`。

### 任务 2：实现 Dart shared-vector runner

**文件：**
- 新建：`test/shared_vector_runner_test.dart`
- 新建：`test/support/shared_vector_runner.dart`
- 新建：`test/shared_vector_runner_contract_test.dart`

- [ ] 先写 runner 契约测试，验证 canonical 输出只含任务 id、时间、时长、来源、解释码，以及 issue code/taskId/blockedBy/explanationCodes；验证输出 marker 只出现一对。
- [ ] 运行 `flutter test test/shared_vector_runner_contract_test.dart -r compact`，确认缺少 runner 时失败。
- [ ] 以环境变量 `SHARED_VECTOR_FIXTURES_DIR` 发现 JSON；plan 调用 `HeuristicSchedulingEngine`，rescue 调用 `ScheduleRescueService`；不为当前实现不存在的依赖或解释码伪造结果。
- [ ] 对现有 `ScheduleRescuePersistence` 建立内存 writer/remove 适配器，执行 apply failure rollback 和 undo restore 向量；timeout 向量通过受控 future/超时函数记录 `timeout` 状态；边界向量调用现有截止校验并记录结果。
- [ ] 输出 `SHARED_VECTOR_RESULT_BEGIN`、一个 JSON payload、`SHARED_VECTOR_RESULT_END`；单 fixture 异常写入 invalid 记录并让测试失败。
- [ ] 运行 Dart runner 契约测试和全部 shared-vector runner 测试。

### 任务 3：实现 Python runner、比较器和分类

**文件：**
- 新建：`scripts/__init__.py`
- 新建：`scripts/scheduling_parity.py`
- 新建：`backend/tests/test_shared_vector_parity.py`

- [ ] 先写失败测试覆盖 marker 缺失/重复、canonical 字段差异、Dart fixture 缺失、review 分类保留和报告退出码。
- [ ] Python plan 直接调用 `backend.services_scheduling.plan_schedule`，rescue 直接调用 `backend.services_rescue.build_options`；副作用向量使用纯内存状态机，不改 SQLite 生产实现。
- [ ] 启动 `flutter test test/shared_vector_runner_test.dart -r compact`，传入 fixture 目录，严格解析 marker 和 process exit code。
- [ ] 比较 Dart/Python 观察值，再分别比较向量 assertions；忽略人类文案的 message，但不忽略任务顺序、时间块、问题码、解释码或最终状态。
- [ ] 分类仅从 fixture `review` 读取，允许 `implementation_error`、`contract_error`、`allowed_difference`、`pending_a_review`；出现 pending 或 invalid 时命令返回非零，不宣称一致。
- [ ] 生成 `reports/shared-vector-diff.json` 和 `reports/shared-vector-diff.md`，报告包含版本、命令、fixture 计数、逐字段差异和分类理由。

### 任务 4：双端回归与证据

**文件：**
- 新建：`reports/shared-vector-diff.json`
- 新建：`reports/shared-vector-diff.md`
- 修改：`contracts/scheduling/v1/README.md`

- [ ] 运行 `python scripts/scheduling_parity.py`，确认 Dart 和 Python 均实际执行所有向量，并保存非零/零退出状态和报告。
- [ ] 运行 `flutter test -r compact test/heuristic_scheduling_engine_test.dart test/schedule_rescue_service_test.dart test/schedule_rescue_persistence_test.dart test/urgent_deadline_test.dart`。
- [ ] 运行 `python -m pytest backend/tests -q`。
- [ ] 运行 `flutter analyze` 与 `git diff --check`；检查报告中 12 个场景均存在，所有差异均有 A 分类或明确 pending。
- [ ] 在中文 README 中记录运行命令、已知差异和“未对齐不得单端修改后宣称一致”的门槛。
