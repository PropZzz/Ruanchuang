# 服务器 Web 部署与预留接口完善设计

**状态：** 已确认，待实施

## 目标

将当前 Ruanchuang 项目的 FastAPI、SQLite 和 Flutter Web 部署到 `8.133.250.216`，网页通过 `http://8.133.250.216` 访问；补齐现有 SQLite 可以真实支持的服务器预留接口，让 Flutter 客户端在远端模式下具备可验证的批量、冲突、救援和协作闭环。

## 范围与边界

本轮实现以下服务器能力：

- 诊断摘要、兼容版本、服务器时间。
- 登出、资料更新；密码重置接口只返回明确的不可用状态，不伪造邮件或短信能力。
- ICS 导入/导出。
- 日程批量写入、冲突查询、救援方案生成、原子应用、撤销和历史。
- 微任务批量完成、批量安排、文本导入。
- 目标的下一个可执行任务安排。
- 团队冲突检测、共同空闲窗口推荐、会议预约。
- 同步状态和基于现有更新时间的拉取/推送基础协议，冲突仍要求显式解决。

以下能力保持结构化 `501 RESERVED_ENDPOINT`，并在响应中说明真实状态：AI 模型、穿戴/蓝牙设备、第三方 OAuth 集成、文件/对象存储、推送通知。没有外部提供方、设备或模型证据时，不把这些接口标记为成功。

## 架构

FastAPI 继续作为唯一业务 API，SQLite 文件固定保存于 `/opt/ruanchuang/data/shixuzhipei.db`，systemd 服务以 `ruanchuang` 用户运行在本机 `127.0.0.1:8000`。Nginx 监听 `0.0.0.0:80`，提供 `build/web` 静态资源，并将业务 API 路径反向代理到 FastAPI；Flutter Web 使用 `API_BASE_URL=http://8.133.250.216` 构建，从而只需要对外放行 TCP 80。

代码采用现有 router、schema、repository 和 service 分层。新增数据表只用于无法由现有模型表达的持久状态，并通过 `init_db` 幂等创建；所有查询和写入都强制使用当前用户过滤。救援 apply/undo、日程批量和同步推送使用单个 SQLite 事务，基线哈希或版本检查失败返回 409，禁止覆盖并发修改。

## 数据流

1. Web 或 Flutter 发送 Bearer token 和 JSON 请求到 Nginx。
2. Nginx 将 API 请求转发到 FastAPI；静态文件和 Flutter 路由回退到 `index.html`。
3. FastAPI 完成 Pydantic 校验、用户过滤、事务写入和结构化错误响应。
4. 成功的日程救援写入对应 `TaskEvent`，记录 `rescue_accept:<strategy>` 或 `rescue_undo:<strategy>`；同步接口返回游标、变更和冲突列表。
5. systemd 持久化服务和数据库目录，发布采用带时间戳的 release 与 `current` 符号链接，失败时切回上一 release。

## 错误与安全

- 保持现有 401、403、404、409、422 语义；请求格式错误不得转成本地空数据。
- 预留能力统一返回 `501`、`RESERVED_ENDPOINT`、路径和当前状态。
- Nginx 只公开 80；FastAPI 仅接受本机代理流量。SQLite、release 和 systemd 配置不暴露在 Web 根目录。
- 服务器没有域名和证书时使用 HTTP 交付；文档明确记录，绑定域名后再启用 TLS。
- 不在代码、Web 构建产物或 systemd 文件中保存 SSH 密码。

## 测试与验收

- 后端：为每个新增路由补 TestClient 测试，覆盖认证、用户隔离、成功、校验失败、冲突和事务回滚。
- Flutter：运行 `flutter analyze`、完整 `flutter test -r compact`，并使用公网 API 地址构建 Web。
- 部署：检查 release 与数据库哈希、systemd `active/enabled`、本机 `/health`、Nginx `/` 和 API 健康；从外部检查 `http://8.133.250.216/`、`/health` 和一个需要认证的 API 的 HTTP 状态。
- 外部验收前提：阿里云安全组必须放行 TCP 80；若未放行，报告服务本机健康但公网检查为阻断，不宣称网页可达。
