# Web 发布

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

发布前执行 `node tools/check_web_sources.mjs`；`web/stitch/mobile/` 与桌面页面同为当前源码，不能再用历史导出覆盖。当前目录职责见 `docs/current-architecture.md`。

将本次输出完整上传到新的服务器 release 目录，验证文件 SHA-256，再原子切换 `/opt/ruanchuang/web/current` 符号链接。保留上一版目录用于回滚；不修改后端或数据库。发布时应用本目录的 Nginx 配置，先 `nginx -t` 再 reload。

入口 HTML 和版本清单使用 `Cache-Control: no-store`；路由脚本和页面宿主脚本采用内容版本文件名，子页面使用同一版本参数。旧 Flutter service worker 更新为注销脚本，只清理旧应用资源缓存，保留账户及本地业务数据。

验收必须访问实际线上地址：核对 `/release.json` 与本地版本一致，核对入口引用的脚本 SHA-256，然后用已有缓存的浏览器进入 `/#/review` 和 `/#/diagnostics`，确认唯一选中项和无左上角返回按钮。仅验证源码目录或无缓存浏览器不算发布成功。

服务器安全组需要允许 TCP 80。绑定正式域名后再配置 TLS，当前 IP 访问使用 HTTP。

连续切换回归：设置 PLAYWRIGHT_MODULE 指向已安装的 Playwright 运行时后，执行 `node tools/check_stitch_navigation.mjs --url http://8.133.250.216/`。该检查拦截生产 API 写请求；读取真实发布页面并验证文档复用、状态保留、竞态、账号隔离和移动端布局。
