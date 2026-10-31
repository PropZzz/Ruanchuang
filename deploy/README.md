# Web 发布

2026-10-31 新增的后端持久会话、CORS、备份恢复和新主机初始化说明见 [生产准备](../docs/production-preparation-2026-10-31.md)。`bootstrap_backend.sh` 仅初始化新 Linux 主机；现有服务器继续先检查实际布局与备份，再按审查结果更新。用户暂无正式域名，TLS 模板尚未启用。本轮本地验证不等于生产部署。

`nginx-ruanchuang.conf` 将 Stitch Web 静态资源从 `/opt/ruanchuang/web/current` 提供到 HTTP 80，并把 FastAPI 路由代理到 `127.0.0.1:8000`。SQLite 不在 Web 根目录。

构建生产 Web：

```powershell
node tools/build_stitch_web.mjs
```

唯一发布源是 `web/`。脚本输出 `build/stitch-web/<release>/`，其中 `release.json` 记录发布版本、入口脚本和每个文件的 SHA-256。旧 Flutter Web 产物与设计页面导出已清理；`stitch/` 现在只保留 Flutter 原生资源，不能作为 Web 发布源。

标准发布命令（需要已安装 `paramiko`，且本机 SSH known_hosts 已有核验过的服务器公钥）：

```powershell
python deploy/deploy_web_release.py
```

脚本以自身位置定位项目，可从任意工作目录调用。SSH 密码仅通过交互提示输入；不要写入源码或文档。它完成构建、上传校验、Nginx 配置备份与检查、原子切换、健康检查以及失败回滚。发布日志写入 `build/deployment-result.txt`。不要把维护脚本存放在可清理的 `build/` 目录。

多人并行开发时可用 `python deploy/deploy_web_release.py --source-root <已审查的Web源码快照>` 发布隔离快照；应从当前线上版本建立并核对差异、在该快照上验收，再发布，避免混入其他未完成改动。构建脚本支持同名参数。默认仍从 `web/` 构建。

2026-10-30 日程约束后端增量发布使用 `python deploy/deploy_schedule_constraints.py`；仅检查线上布局用 `--inspect`。初次迁移基于本轮 Git HEAD 与工作树的差异，需在提交本轮改动前使用；后续互斥修正用 `--base-directory build/backend-exclusive-base`，基于修改前保存的本地源码快照合入，避免重复应用前轮迁移。它保留线上其他差异，先做隔离数据验证，随后备份源码和 SQLite、增量迁移、检查记录数和健康状态，失败恢复源码。备份在 `/opt/ruanchuang/backups/schedule-constraints-*`。部署会重启后端，旧内存令牌版本的会话会失效；迁移后新签发的有效会话可跨重启。此专用脚本不能替代通用后端发布流程。

发布前执行 `node tools/check_web_sources.mjs`；`web/stitch/mobile/` 与桌面页面同为当前源码，不能再用历史导出覆盖。当前目录职责见 `docs/current-architecture.md`。

2026-10-31 日程导入增量使用同一脚本的 `--change calendar-import --base-directory <修改前本地源码目录>`，覆盖五个经过合并的后端文件。若出现合并冲突，先人工核对，使用 `--resolved-directory <已审查合并目录>` 提供对应文件和同名 `.py.before` 服务器快照；服务器源码与该快照不一致时拒绝发布。此次记录及证据见 `docs/visual-qa/2026-10-31-calendar-import.md`，备份前缀为 `/opt/ruanchuang/backups/calendar-import-*`。不要用部署后的源码作为修改前基线重复应用此次迁移。

将本次输出完整上传到新的服务器 release 目录，验证文件 SHA-256，再原子切换 `/opt/ruanchuang/web/current` 符号链接。保留上一版目录用于回滚；不修改后端或数据库。发布时应用本目录的 Nginx 配置，先 `nginx -t` 再 reload。

入口 HTML 和版本清单使用 `Cache-Control: no-store`；路由脚本和页面宿主脚本采用内容版本文件名，子页面使用同一版本参数。旧 Flutter service worker 更新为注销脚本，只清理旧应用资源缓存，保留账户及本地业务数据。

验收必须访问实际线上地址：核对 `/release.json` 与本地版本一致，核对入口引用的脚本 SHA-256，然后用已有缓存的浏览器进入 `/#/review` 和 `/#/diagnostics`，确认唯一选中项和无左上角返回按钮。仅验证源码目录或无缓存浏览器不算发布成功。

服务器安全组需要允许 TCP 80。绑定正式域名后再配置 TLS，当前 IP 访问使用 HTTP。

连续切换回归：设置 PLAYWRIGHT_MODULE 指向已安装的 Playwright 运行时后，执行 `node tools/check_stitch_navigation.mjs --url http://8.133.250.216/`。该检查拦截生产 API 写请求；读取真实发布页面并验证文档复用、状态保留、竞态、账号隔离和移动端布局。
