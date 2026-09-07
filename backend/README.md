# Ruanchuang Backend

独立 FastAPI + SQLite 后端，用于承接 Flutter 客户端的账号、日程、微任务和算法推荐接口。

## 安装依赖

在项目根目录 `Ruanchuang-main` 执行：

```powershell
python -m pip install -r backend/requirements.txt
```

## 启动服务

```powershell
python -m uvicorn backend.main:app --host 127.0.0.1 --port 8000 --reload
```

启动后可访问：

- `GET http://127.0.0.1:8000/health`
- `POST /auth/register`
- `POST /auth/login`
- `GET /auth/me`
- `GET|POST /schedule`
- `PUT|DELETE /schedule/{entry_id}`
- `POST /schedule/replan`
- `GET|POST /events`
- `POST /events/batch`
- `GET /review/weekly`
- `GET /review/monthly`
- `GET /review/rescue-history`
- `GET|PUT /review/tuning`
- `POST /review/tuning/apply`
- `GET|POST /microtasks`
- `PUT|DELETE /microtasks/{task_id}`
- `POST /microtasks/recommend-crystals`
- `GET /emotion/current`
- `POST|GET /emotion/checkins`
- `GET /emotion/care-alert`
- `GET /energy/current`
- `POST /energy/samples`
- `GET /energy/profile`
- `GET|POST /goals`
- `PUT|DELETE /goals/{goal_id}`
- `POST /goals/{goal_id}/tasks`
- `PUT /goals/{goal_id}/tasks/{task_id}`
- `GET|POST /team/members`
- `PUT|DELETE /team/members/{member_id}`
- `PUT /team/members/{member_id}/permission`
- `GET /team/calendars`

默认 SQLite 数据库文件保存在 `backend/data/shixuzhipei.db`。生产部署使用 `SHIXUZHIPEI_DB_PATH` 指向持久化数据目录。

当前已实现平台诊断、账号退出/昵称更新、ICS 导入导出、日程批量/冲突/救援、微任务批量操作、目标下一任务、团队冲突/黄金窗口/会议预约和基础 `/sync/*` 游标同步。

AI、设备、第三方集成、文件、推送和密码重置仍返回结构化 HTTP 501 `RESERVED_ENDPOINT`，直到对应外部服务或硬件完成接入。

## Flutter 连接后端

桌面或浏览器运行：

```powershell
flutter run --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

Android 模拟器运行时可以不传参数，客户端默认使用 `http://10.0.2.2:8000`；真机调试需要把 `API_BASE_URL` 改成电脑在同一局域网内的 IP。

客户端采用远程优先、本地兜底策略：后端可用时读写 REST API，同时同步本地；后端不可用时保留本地模式的基本功能。

## 验证

```powershell
python -m pytest backend/tests -q
flutter test -r compact
flutter analyze
```
