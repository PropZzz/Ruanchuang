# 客户端逐操作结果

本接口在现有 `DataService` 之外提供可选的页面适配入口。原有方法仍返回原值或抛出原异常；Composite 的两种调用方式共用执行路径。没有修改服务器字段、路由或事务。

## 使用方式

```dart
final operations = ServiceOperations(AppServices.dataService);
final result = await operations.read((service) => service.getGoals());
// ServiceSuccess: value、source、offline、fallbackCause。
// ServiceFailure: problem.kind、message、nextAction、cause、stackTrace。
```

每个callback只能执行一个数据操作，必须使用传入的service；不能闭包捕获另一个服务、复用已启动的Future、调用Composite自身、执行多个步骤或执行登录/退出。此接口不是事务协调器。直接Remote/Local服务也可使用；未知自定义实现的source为unknown，不猜测来源。

`read`/`write`是远端可适配的数据操作入口；收藏设备是现有显式本地偏好，使用 `operations.getFavoriteDevice()` / `operations.setFavoriteDevice(id)` 专用结果入口，保持与Composite原方法相同的本地路由（source=local、offline=false），不通过远端数据操作callback发起。直接RemoteDataService调用该能力仍返回501，不能将其当成离线兜底。

## 草稿

```dart
final saved = await operations.saveDraft(
  draft: formDraft,
  copy: (draft) => draft.deepCopy(), // mutable字段也必须复制
  save: (service, copy) => service.updateMicroTask(copy),
);
```

调用开始时复制草稿；每个远端/缓存/降级调用再取独立副本。`saved.draft` 保留供页面恢复或重试，服务不关闭表单、不修改原始草稿。copy是调用方负责的纯深复制；复制函数本身失败会抛错，写入尚未派发。页面只能在ServiceSuccess后结束保存流程；ServiceFailure保留草稿并显示可本地化的kind/message/nextAction。cause/stackTrace只用于诊断，不直接显示服务器正文。接口提供安全默认英文文案，中文页面按kind本地化；本PR不修改页面文案系统。

本PR提供草稿边界；既有页面尚未使用它，不能据此声称所有表单已解决丢草稿。后续各卡片PR负责接入、关闭保护和Widget失败恢复测试。

## 结果矩阵

| 实际结果 | 对外结果 | 自动本地兜底 |
|---|---|---|
| 远端成功（包括合法空集合） | success、source=remote | 不需要 |
| 显式guest/本地优先读取成功 | success、source=local、offline=false | 不是离线 |
| 断网/超时/HTTP500、502、503、504，本地成功 | success、source=local、offline=true、fallbackCause | 允许 |
| 401/403/409/422和其他4xx | failure，保留错误类别/原异常 | 禁止 |
| 501/未实现远端能力 | failure、reserved | 禁止 |
| 其他5xx、解析/契约错误 | failure、server/parsing/contract | 禁止 |
| 远端成功、缓存失败 | success、source=remote、cacheWarning；禁用后续陈旧缓存降级 | 不重复远端写入 |
| 本地兜底也失败 | failure，主因是本地失败，fallbackCause保留远端失败 | 不报成功 |

写入的4xx拒绝标记notSaved；超时、断网、5xx、解析失败可能发生在提交之后，保守标记unknown。离线本地写成功也保留remoteCommitUncertain，不能据此声称服务器一定未保存。提交结果未知时先刷新核对；需重试的创建操作使用既有稳定ID或幂等能力。没有新增队列、补偿、自动重试或同步协议。

logout不是数据写入兜底：RemoteDataService已有finally清token和身份，Composite现在保留网络/5xx诊断并在本地退出后重抛。身份/命名空间仍属于独立PR #3，本PR不声称解决其余身份隔离问题。两PR的Composite白名单和logout段会重叠，合并时须人工核对并重跑服务测试。
