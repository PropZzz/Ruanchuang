# 2026-10-31 项目收口验证

本轮从云端 main `44cb49f2ad65158217bc200c5a68592b6efecfea` 开始，工作分支为 `codex/baseline-closeout-20261031`。本轮最后一次 fetch 确认云端 main 未变化。本记录描述本地源码和隔离环境；云端 CI 以工作分支 PR 的实际 checks 为准，生产部署另行验收。

## 环境与复现

Windows，Flutter 3.38.7 / Dart 3.10.7、Python 3.13.5、Node 24.15.0。Python 使用隔离 venv 和 `backend/requirements.txt` 的固定依赖，含 psutil 7.2.2。Flutter 使用云端 `pubspec.lock`，锁文件未改；恢复依赖后检查使用 `--no-pub`。

```powershell
dart pub get --enforce-lockfile
flutter analyze --no-pub
flutter test --no-pub --reporter expanded
python -m pytest backend/tests -q
node --test tools/tests/*.test.mjs
node tools/check_web_sources.mjs
node tools/build_stitch_web.mjs
python scripts/scheduling_parity.py
python scripts/scheduling_benchmark.py --parity-report reports/shared-vector-diff.json
```

机器工具路径和原始日志位于忽略目录 `build/verification-2026-10-31/`；可提交的日志摘要、SHA-256 和变更源码快照见 [机器可读记录](../reports/verification/baseline-20261031.json)。本机 Dart pub 恢复避开了不必要的原生插件链接生成；未修改锁文件来适配机器。

## 实际结果

| 检查 | 云端原始基线 | 收口后本地结果 | 最终日志 |
| --- | --- | --- | --- |
| Flutter analyze | 无问题 | 无问题，3.9s | flutter-final-analyze2.log |
| Flutter 完整测试 | 333 通过 | 398 通过，23s；原视觉基线不变 | flutter-final-tests3.log |
| 后端全量 | 239 通过 | 连续两轮各 265 通过，32.38s / 19.69s | backend-final-run4.log / backend-final-run5.log |
| Node 单元/契约 | 30 通过 | 34 通过，0 失败 | node-final2.log |
| Web 资源 | 109 文件 / 295 引用 | 110 文件 / 296 引用、27 路由、7 原生资源声明通过 | check_web_sources 输出 |
| 调度共享向量 | 12 项，3 matched / 9 mismatched | 13 matched、0 mismatched/invalid/pending，Dart exit 0 | reports/shared-vector-diff.json |
| 基准 | 被一致性门禁阻断 | 最终 80 采样、0 超时、0 失败，exit 0 | benchmark-final.log |

后端最终存在 107 条 Starlette/httpx 等弃用提醒，未导致失败。后续依赖升级时处理，不以屏蔽提醒证明成功。

新增回归包含无效认证响应与失败登出、会话跨进程/到期/隔离/撤销、CORS 预检、WAL 恢复及失败回滚、真实 RSS、大结果进程队列、半分钟舍入/一分钟任务、日期跨年月底、6 个工作页面的 42 条失败恢复路径及个人中心部分数据刷新。原有登录、救援、复盘和截图断言保留。

## 失败与修复证据

- 首次对拍重复准备 Flutter 平台插件，在本机产生 12 invalid。runner 改为 `--no-pub` 后才记录到真实 3/9 差异；补齐原先丢弃的解释码和依赖，再按契约逐项修复。7 项契约断言、3 项实现修复理由保存在 fixture 中。
- 基准先 join、后读 Queue，大结果卡住 feeder；较早 `141912Z` 报告保留了 20 个假超时。现在先读取，再在同一预算内等待结束，大结果回归仍使用 1000ms。
- 首次冷加载 RSS 库发生在父进程分配追踪内，会消耗聚合用例的 100ms 预算。初始化移至追踪之前，阈值不变；之后取得连续两轮全量通过。
- 拆分时曾把 `.dart` 备份留在 build 导致 analyzer 扫描；已改为 `.dart.txt` 并重新验证，没有忽略真实代码。公开默认倍率对齐 1.0 后，旧测试改为显式 1.2，保留原 14:42 业务断言与自定义倍率覆盖。
- 新状态回归抓到个人中心刷新向 setState 返回 Future，已修复。微任务、团队、复盘错误改为持续的本页重试；浏览器回归抓到手机个人中心设置入口被共享壳隐藏，已补可见的显式导航入口。
- Windows venv Python launcher 的子进程占用 SQLite，曾掩盖浏览器测试原始错误。工具现在只停止自己创建的进程树，再清理自己的临时目录；原业务断言保留。

## 浏览器与发布物

使用本机已安装 Chrome，未下载浏览器。现有自动回归使用隔离安装的 playwright-core 1.64.1，通过 `PLAYWRIGHT_MODULE` 选择现有 Chrome；人工走查使用 agent-browser 独立会话。所有业务写入针对临时本地 SQLite。

| 工具 | 已验证内容 |
| --- | --- |
| check_stitch_navigation.mjs | 文档/草稿/滚动保留，八个热路由，竞态与重试，隐藏倒计时，账号隔离和移动断点 |
| check_stitch_release.mjs | 旧 Flutter 资源缓存退出、账户与业务数据保留、侧栏唯一选中 |
| check_stitch_drawers.mjs | 桌面/手机打开关闭、中途反向、焦点、背景状态、ICS 提交与热帧切换 |
| check_stitch_account_settings.mjs | 桌面/手机昵称编辑取消及持久化、设置加载保存、切换返回、真实登出撤销及再次登录 |
| check_stitch_schedule_create.mjs | 桌面/手机标签与主题、时长提醒、持久化、刷新及单次写入 |
| check_stitch_schedule_edit.mjs | 桌面/手机约束、字段保留、取消、刷新、读取失败重试及新建隔离 |
| check_stitch_calendar_import.mjs | 桌面/手机预览、取消零写入、原子确认、重复跳过、CSV/TSV/JSON/ICS/XLSX/XLS 课表、备注修改与刷新 |
| check_stitch_focus_regressions.mjs | 标签安全、隐藏页时间、暂停恢复、完成事件、已完成任务恢复及浮动日程 |

隔离账户还在浏览器完成注册；将保存文字改成“确认安排”、救援生成改成“计算可选安排”、采用按钮改成“确认使用 A”后，真实创建和救援采用均成功。最终 Web release 及哈希见机器可读记录；本轮未向生产写入业务数据或发布资源。

## 剩余外部验收

持久会话、明确 CORS、备份恢复、新 Linux 主机初始化、待配置 TLS 模板已入源码。本地恢复可还原业务数据并再次登录，Bash 语法及 workflow YAML 检查通过。

用户暂无域名，证书签发、目标主机 nginx -t、HTTP→HTTPS/HSTS 实测待配置。初始化脚本没有在目标 Linux 执行；备份定时任务、真实恢复演练、现有生产布局合入与回滚、原生安装包/真机仍需独立验收。历史身份分支保留理由见 [分支决定](identity-branch-decision-2026-10-31.md)。
