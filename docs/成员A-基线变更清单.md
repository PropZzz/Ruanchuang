# 成员 A 基线变更清单

> 冻结日期：2026-09-14
> 执行分支：`member-a`
> 基线来源：`b03427b5db7145949a341430dd66c3e92a3dc720`
> 对照分支：`main`、`origin/main`

## 1. 基线状态

| 检查项 | 结果 | 说明 |
| --- | --- | --- |
| 当前分支 | `member-a` | 已从当前主线创建并切换 |
| `member-a` 与 `main` | 一致 | 两者均指向 `b03427b` |
| `member-a` 与 `origin/main` | 一致 | ahead 0、behind 0 |
| 已跟踪文件修改 | 无 | `git diff` 无输出 |
| 已跟踪文件删除 | 无 | 未发现删除项 |
| 未跟踪文件 | 1 个 | `docs/成员A工作清单.md` |
| 前端视觉改动 | 无 | 当前工作树未发现 |
| 后端行为改动 | 无 | 当前工作树未发现 |
| 资源改动 | 无 | 当前工作树未发现 |

分工文档中提到的“当前 `main` 相对 `origin/main` ahead 13”与本次实际 Git 状态不一致。本次冻结以 Git 实际状态为准，记录为文档基线信息过期，不把历史提交重新归类为当前未提交改动。

## 2. 当前变更清单

| 文件 | 类别 | 责任人 | 处理结论 | 风险与后续动作 |
| --- | --- | --- | --- | --- |
| `docs/成员A工作清单.md` | 文档 | 成员 A | 保留并提交 | 记录成员 A 的执行步骤、交付物和边界；不影响运行代码 |
| `docs/成员A-基线变更清单.md` | 文档 | 成员 A | 本次新增并提交 | 记录本次基线审计结果和提交拆分方案 |

## 3. 成员协作复核结论

由于当前工作树没有后端、Flutter、测试或资源改动，本次只需要记录以下结论：

- 成员 B：当前没有待复核的 Schema、数据库、路由或后端行为改动。
- 成员 C/D：当前没有待复核的 Flutter 页面、服务层或模型字段改动。
- 成员 E：应以 `b03427b` 和本次文档提交作为后续测试基线；测试输出仍需在进入 P1 前单独固化。

## 4. 提交拆分方案

本次只包含文档变更，不混入业务代码：

1. `docs: add member A work checklist`
2. `docs: freeze member A baseline inventory`

实际执行时，为便于回滚，将两份文档合并为一个文档基线提交：

```text
docs: freeze member A baseline
```

该提交只包含 `docs/成员A工作清单.md` 和 `docs/成员A-基线变更清单.md`。

## 5. 基线冻结后的下一步

1. 由成员 E 在该基线提交上运行 Flutter、后端和格式检查，并保存输出。
2. 由成员 A 与成员 B 评审 P1 远端救援事务契约。
3. 在 P1 契约锁定前，不开始大规模 `SchedulerCore` 重构。
4. 契约锁定后，再建立 Dart/Python 共享 JSON 测试向量。

## 6. 冻结门槛

- [x] 当前分支、HEAD 和远端关系已确认。
- [x] 所有当前未提交文件已列出并分类。
- [x] 每个当前变更都有责任人和去留结论。
- [x] 业务代码、资源和删除项没有混入本次文档提交。
- [x] 已规划可回滚的文档基线提交。
- [x] 三组基线测试已执行并记录结果。

## 7. 验证证据

以下命令均在 `member-a` 基线工作树执行：

```text
flutter analyze
```

结果：`No issues found!`

```text
flutter test -r compact
```

结果：`All tests passed!`，共 179 项测试通过。

```text
python -m pytest backend/tests -q
```

结果：`71 passed, 4 warnings`。警告均为依赖库弃用提示，没有测试失败。

```text
git diff HEAD^ HEAD --check
```

结果：通过，无空白错误。

## 8. P1 契约实施记录

基线之后，成员 A 在 `member-a` 分支完成了调度契约 v1 的第一阶段实施：

- 新增 `contracts/scheduling/v1/scheduling.schema.json` 和共享 fixtures。
- FastAPI `/schedule/replan` 使用严格请求/响应适配器；CRUD 的 `height` 存储格式保持不变。
- Dart 调度 adapter 输出 `schemaVersion`、日期-only `day`、UTC `Z` 时间和 `durationMinutes`。
- Dart/Python 启发式引擎统一了任务排序、依赖阻塞、硬截止处理和解释码。
- 公共接口文档和后端守则已更新。

本阶段最终验证：

```text
flutter analyze                  -> No issues found
flutter test -r compact          -> 188 tests passed
python -m pytest backend/tests -q -> 98 passed, 4 dependency deprecation warnings
git diff --check                 -> clean
```

## 9. 调度 parity、SchedulerCore 和救援评分实施记录

已完成：

- Python 编排器 `scripts/scheduling_parity.py` 会启动专用 Flutter runner，执行全部共享 fixture 并生成 `reports/scheduling-parity-2026-09-14.json`。
- Python 和 Dart 均有独立的 `SchedulerCore` 纯计算入口，原有服务/引擎接口保留为兼容门面。
- 三种救援策略使用 `contracts/scheduling/v1/rescue-strategies.json` 中的统一权重和 15 分钟恢复缓冲。
- 救援方案按硬问题数、加权分数和稳定策略顺序推荐，并返回 `score`、`scoreBreakdown`。

最终 parity 结果：2 个 fixture、2 个匹配、0 个差异、0 个无效项。

剩余范围：更细粒度 helper 模块拆分和生产规模性能基准不属于本次行为验收，后续单独排期。
