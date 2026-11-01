# 2026-11-01 生产部署与验收

## 已部署后端与备份

- 服务器：`8.133.250.216`，现有 `ruanchuang.service` / Nginx 布局继续使用。
- 后端：`bf05808d44e6bde45bae2b354a6c48e26441f157`，目录 `/opt/ruanchuang/releases/bf05808d44e6bde45bae2b354a6c48e26441f157`，`/opt/ruanchuang/current` 指向该目录。
- 每个新后端 release 使用独立 Python 环境；实际 Python 3.12.3，服务仍以 `ruanchuang` 用户运行。
- 复核时发现 `current` 符号链接与 systemd 的 Python release 不一致，变更来源未确认。已校正链接，并将 `WorkingDirectory` 和 `ExecStart` 同时固定到上述绝对目录，通过 `/proc/<pid>/cwd` 和真实业务请求确认加载的是修复后的源码。
- 会话有效期 7 天，CORS 为服务器 HTTP origin 和两个本地预览 origin。真实服务重启后，已签发会话和日程均保留；退出后 token 被拒绝。
- 原有 109 条日程、1 个用户和 8 条事件在迁移中保留；已有列的逐表内容摘要核对通过。验收使用独立临时账户，完成后只删除对应账户及其测试记录。
- 初次发布备份：`/opt/ruanchuang/backups/production-5317ed14adf7-20261101T031339Z`；兼容修复备份：`/opt/ruanchuang/backups/rescue-migration-20261101T032022Z`。
- 定时任务 `ruanchuang-backup.timer` 已启用：北京时间每天 03:00，加 0–10 分钟随机延迟；首次手动触发成功。备份在 `/opt/ruanchuang/data/backups`，目录 0700、文件 0600。
- 在服务器隔离副本执行备份恢复，SQLite 完整性及逻辑内容摘要均一致。备份保留在同一台服务器，尚未配置异地副本或自动清理。

## 真实验收发现及修复

1. **旧库救援快照迁移遗漏。** 原有 `rescue_snapshots` 缺少 `day / urgent_json / undone_at`；`after_json / updated_at` 为没有默认值的必填列。新建数据库的原 265 项测试没有覆盖这个结构，实际“采用方案”因此返回 500。现补充幂等加列，并显式写入旧表要求的字段，保留历史快照；新增两种旧表结构的采用/撤销回归。
2. **网页撤销入口缺失。** 桌面已有按钮缺少动作绑定，手机没有实际撤销按钮。现补齐两个显式入口；`tools/check_stitch_rescue.mjs` 使用隔离 FastAPI / SQLite，覆盖桌面和手机的生成、采用、刷新、撤销和历史查询。
3. **手机复盘页正文被挤窄。** 手机复用了桌面文档，隐藏侧栏后仍保留 260 像素占位。已取消手机端占位、调整正文内边距和控制栏换行，真实浏览器检查正文宽度及页面无横向溢出。
4. **日历截图受运行时间影响。** 桌面“下一项任务”使用系统当前时间，导致不同时间运行的云端截图不一致。日历支持注入显示时钟，截图测试固定到原有基准时间，另验证上午/晚间的下一项任务变化；未更新基准图片或放宽像素比较。

失败的采用请求没有留下半套日程或事件；验收账户已按准确 ID 清理。先前失败日志保留在本机被忽略的验证目录，不能将其视为成功证据。

## 验证结果

- 本地后端：267 通过；目标 Linux 服务器：267 通过。
- Flutter 静态分析通过，399 项测试通过；日历视觉回归与新增时钟测试通过，原有基准图片保持不变。
- Node：34 通过；Web 源码：110 文件、27 路由、296 引用通过。
- 隔离浏览器：桌面和手机均完成生成三方案、采用、刷新后撤销和历史查询。
- 生产 API：注册/登录、新建并读取日程、三方案、采用、撤销、复盘、CORS 白名单、匿名拒绝、真实服务重启后的登录保持、退出撤销均通过。
- Web 最终版本 `439e74200b59c811`，源码提交 `f6aa6e68ed320f8d0915ea40c9401b6427ded6b0`，于北京时间 2026-11-01 23:49 发布；115 个文件的摘要核对通过，`nginx -t` 和健康检查通过。此前版本 `151a5189331ff9e9` 保留在 release 目录，切换记录位于 `/opt/ruanchuang/web/backups/mobile-review-20261101T154923Z`。
- 生产桌面、手机浏览器均完成真实登录、新建日程、三方案、采用、撤销及复盘路由检查，无 API mock、无页面脚本异常；手机复盘页另检查正文宽度及无横向溢出。
- [本次修复 PR](https://github.com/PropZzz/Ruanchuang/pull/6) 的自动检查和 Windows 打包结果以实际 checks 为准。

## Windows 便携包

`.github/workflows/windows-package.yml` 使用 Flutter 3.38.7，在临时 Windows runner 构建 x64 Release，并包含应用依赖的 Visual C++ DLL；API 地址固定为 `http://8.133.250.216/api`。产物由 GitHub Actions 保留 14 天，可在 PR 的 Windows package 检查中下载。

提交 `678bca7` 的 [首次成功构建](https://github.com/PropZzz/Ruanchuang/actions/runs/41298839042) 已通过打包和隐藏进程启动检查。后续提交按同一工作流重新生成，以 PR 最终检查对应的产物为准。此检查仅证明进程持续运行 10 秒，没有替代人工交互验收、签名安装器或手机真机验收。

## 备份部署与恢复注意事项

`deploy/ruanchuang-backup.service` 和 `.timer` 记录实际定时任务配置。维护脚本安装在 `/opt/ruanchuang/maintenance/database_maintenance.py`，独立于后端 `current` 符号链接，代码回退不会使定时备份丢失脚本。更新安装后执行：

```sh
sudo systemd-analyze verify /etc/systemd/system/ruanchuang-backup.service /etc/systemd/system/ruanchuang-backup.timer
sudo systemctl daemon-reload
sudo systemctl start ruanchuang-backup.service
sudo systemctl enable --now ruanchuang-backup.timer
sudo systemctl list-timers --all ruanchuang-backup.timer
```

数据库恢复沿用 [备份恢复操作](production-preparation-2026-10-31.md)。执行恢复前先停止后端及备份 timer，并保存恢复前快照；完成后核对数据并重新启用二者。代码回退应保留当前数据库，不能用发布前备份直接覆盖发布后的新增业务数据。

旧版代码对新增会话表的兼容检查在服务器隔离副本完成，只验证启动、健康状态和原有行保留；没有在生产切回旧版进行整套业务验收。旧版不含本次快照写入修复，不应作为救援功能正常的证据。

## 仍需外部条件

- 用户暂无域名，HTTPS / 证书 / HSTS 尚未启用；本次保留现有 HTTP Nginx 配置。
- 本机缺少 Android SDK、Android 发布签名和 Windows C++ 工具链；Windows 便携包改由云端构建，真实交互验收与签名安装器另行记录。
- 未连接 Android / iOS 实体设备，移动浏览器视口测试不能替代真机安装和现场网络验收。

详细执行证据位于本机 `build/deployment-2026-11-01/`，含源码校验、服务器测试、发布、备份和浏览器记录；该目录不提交凭据、生产数据库或个人业务内容。
