# 时序智配开发指引

目录和启动边界以 `docs/current-architecture.md` 为准；旧设计计划只提供历史背景。

## 当前实现

- 线上 Web：`web/` 中的 HTML/JS，入口 `web/index.html`，路由 `web/stitch/router.js`，持久页面宿主 `web/stitch/page-host.js`。
- 原生客户端：`lib/` 中的 Flutter/Dart，保留 Android、iOS、Windows、macOS、Linux 平台工程。
- 后端：`backend.main:app`，唯一的 FastAPI + SQLite 服务，同时服务两个客户端。
- `backend/services_scheduling.py` 是当前调度兼容入口；`backend/scheduling/` 是模块化实现，不是两套后端。

## 修改约束

- Web 桌面、移动和二级页面分别在 `web/stitch/screens/`、`web/stitch/mobile/`、`web/stitch/components/` 直接维护。
- 保持统一导航选中态、持久页面状态、可打断的切换动画与减少动态效果支持。
- `web/flutter_service_worker.js` 是旧缓存退役脚本，必须保留。
- `stitch/assets/` 只保留 Flutter 声明的图片和字体；删除资源前检查 `pubspec.yaml` 和 Dart 引用。
- 原生异步 UI 需检查 `mounted`；计时器与订阅须释放。沿用当前服务抽象，不把测试 mock 当作运行后端。
- 保护 SQLite、`.appdata/`、原生平台文件与 `.worktrees/` 内的未提交工作。
- 不从旧导出复制页面，不在 `build/` 中维护部署脚本，不把密码写入文件。

## 常用命令

```powershell
.\run_web_preview.bat
node tools/check_web_sources.mjs
node --test tools/tests/stitch_release.test.mjs
node tools/build_stitch_web.mjs
flutter analyze
flutter test
python -m pytest backend/tests -q
```

部署使用 `python deploy/deploy_web_release.py`；浏览器回归使用 `tools/check_stitch_navigation.mjs` 与 `tools/check_stitch_release.mjs`。具体环境要求见 `deploy/README.md`。
