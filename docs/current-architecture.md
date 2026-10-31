# 当前项目架构与目录边界

更新时间：2026-10-31。本文优先于历史设计导出、旧计划中的启动路径。

## 三个保留的运行入口

| 实现 | 维护位置 | 入口 / 命令 |
| --- | --- | --- |
| HTML/JS Web（线上桌面与移动端） | `web/` | `web/index.html`；`run_web_preview.bat` |
| Flutter 原生客户端 | `lib/`、`android/`、`ios/`、`windows/`、`macos/`、`linux/` | `lib/main.dart`；`flutter run -d <原生设备 ID>` |
| FastAPI + SQLite 后端 | `backend/` | `python -m uvicorn backend.main:app --host 127.0.0.1 --port 8000` |

Web 的 `web/stitch/router.js` 统一路由，`web/stitch/page-host.js` 保留页面文档和状态；`screens/`、`mobile/`、`components/` 都是当前实现。修改移动页面直接编辑 `web/stitch/mobile/`。
`web/stitch/actions.js` 根据显式动作标记分派 API 操作；专注页自己的 `data-focus-action` 由 `focus.js` 独占处理。日历渲染使用 `calendar.js`。形态决策见 [运行边界](superpowers/specs/2026-10-31-runtime-boundaries.md)。

`web/flutter_service_worker.js` 是用于注销旧 Flutter 缓存的迁移脚本，仍需发布，不能当作旧构建文件删除。

## 原生资源、数据与兼容层

- `assets/` 和 `stitch/assets/` 中由 `pubspec.yaml` 声明的图片、字体用于 Flutter。`stitch/` 不再是第二套 Web 前端。
- `test/`、`backend/tests/`、`tools/tests/`、`contracts/` 和 `scripts/` 保留测试、跨语言协议及调度校验链路。
- `backend/services_scheduling.py` 是当前兼容入口，委托 `backend/scheduling/`；不是第二套后端。
- `lib/services/mock_data_service.dart` 仍被原生客户端测试使用；不能按旧后端删除。
- `backend/data/`、`.appdata/` 为本地运行数据；SQLite、账户信息和业务数据不属于导出清理范围。
- 原生日历页面组合已有 `ScheduleTimeline` 和 `lib/widgets/calendar/` 的筛选、状态、ICS 组件，页面负责数据与持久化，组件通过参数和回调协作。
- 会话位于同一个 SQLite 数据库的 `auth_sessions`；`backend/settings.py` 管理有效期与 CORS，`deploy/database_maintenance.py` 管理备份恢复。

## 构建、校验与发布

```powershell
node tools/check_web_sources.mjs
node --test tools/tests/*.test.mjs
node tools/build_stitch_web.mjs
python -m pytest backend/tests -q
dart pub get --enforce-lockfile
flutter analyze --no-pub
flutter test --no-pub --reporter expanded
python scripts/scheduling_parity.py
```

浏览器验收使用现有 `tools/check_stitch_navigation.mjs`、`tools/check_stitch_release.mjs`；本机需已安装 Playwright，可通过 `PLAYWRIGHT_MODULE` 指向对应模块。

Web 构建输出为 `build/stitch-web/<内容版本>/`；压缩包为 `build/stitch-<内容版本>.tar.gz`。当前包可保留，过期 Web 输出可按版本清理。不要整个删除 `build/`，其中也有原生构建与验收证据。

标准部署脚本在 `deploy/deploy_web_release.py`。线上静态文件指向 `/opt/ruanchuang/web/current`，由版本目录原子切换；服务器保留上一版以便回滚。仓库清理不触碰服务器版本、后端进程或数据库。

## 已停用链路

根目录旧 `stitch/screens/`、`design/stitch-mobile/` 和对应导出、同步工具已删除。历史文档中提到这些路径时应视为当时的设计背景，不能照此启动或发布。清理明细与恢复位置见 `cleanup-2026-10-29.md`。
