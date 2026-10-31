# 生产准备与恢复操作

本轮已在源码中完成 SQLite 持久化会话和显式 CORS。线上切换与真实 Linux 主机安装仍需独立验收。用户暂无正式域名，证书签发与 HTTPS 上线保留待配置。

## 运行配置

示例为 `deploy/backend.env.example`。`SHIXUZHIPEI_DB_PATH` 必须位于持久化目录；会话与用户数据保存在同一个数据库。默认会话有效期 604800 秒。登录和注册返回的 Bearer token 形状保持不变；数据库仅保存 token 的 SHA-256 摘要。

`SHIXUZHIPEI_CORS_ORIGINS` 为逗号分隔的明确 HTTP(S) origin，默认包含现有 IP 和 5353 本地预览。增加其他端口或域名需要显式配置；不能填写 `*`、URL 路径或凭据。首次从内存令牌版本迁移后需要重新登录，之后有效会话可跨进程重启。

## 备份与恢复

以下路径是操作示例，执行前替换为实际数据库和备份目录。工具使用 SQLite backup API，包含 WAL 中已提交的数据；输出完整性和每张业务表计数，不输出账号内容。

```text
python deploy/database_maintenance.py inspect /opt/ruanchuang/data/shixuzhipei.db
python deploy/database_maintenance.py backup /opt/ruanchuang/data/shixuzhipei.db --directory /opt/ruanchuang/backups
```

恢复时停止实际后端服务，使用备份命令输出的完整文件名：

```text
sudo systemctl stop ruanchuang.service
python deploy/database_maintenance.py restore /opt/ruanchuang/backups/实际备份文件.sqlite3 --database /opt/ruanchuang/data/shixuzhipei.db --backup-directory /opt/ruanchuang/backups
sudo systemctl start ruanchuang.service
```

工具先验证输入备份，再备份当前数据库；恢复后比较完整性和表计数，失败时恢复操作前备份。恢复回到备份时点，包括该时点的会话和退出状态；需要强制全部重新登录时，应在服务停止期间清空恢复数据库的 `auth_sessions` 表。

可以将备份命令配置为目标主机的定时任务，使用实际服务用户、虚拟环境 Python 和已核验的源码路径；定时任务执行日志及实际恢复演练需在目标主机记录。本地测试已经覆盖 WAL、日程、用户、持久会话和恢复后的再次登录。

## 新机器初始化

目标主机需有 Linux/systemd、Git、Python 3.10+ 及 venv 支持。准备干净、已审查的 Git checkout 后执行：

```text
sudo bash deploy/bootstrap_backend.sh /绝对路径/已审查仓库 /opt/ruanchuang
```

脚本创建按 Git 提交号命名的 release、隔离 Python 环境、低权限服务用户、私有数据目录、受保护配置及单 worker systemd 服务，最后检查 `/health`。已有 `ruanchuang.service` 时拒绝初始化；当前生产服务器应继续按已有布局检查、备份、合并差异和回滚流程更新。该初始化脚本不配置 Web、Nginx、域名或证书。

## HTTPS 模板

`deploy/nginx-ruanchuang-tls.conf.example` 为待配置模板，保留现有 Web/API 路由及发布目录。正式域名解析、证书文件存在、CORS 更新并通过 `nginx -t` 后，才能在目标主机启用。当前 HTTP 配置未替换；不能据此宣称线上已经支持 HTTPS。

模板在设置 Cache-Control 的 location 内也显式声明 HSTS，兼容 Nginx 的默认响应头继承规则；参见 [Nginx 官方说明](https://nginx.org/en/docs/http/ngx_http_headers_module.html#add_header)。本机只完成模板检查与 Bash 语法检查，尚未在目标 Linux 主机运行 `nginx -t` 或初始化服务。
