# 前后端功能对齐与二级页面退出实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** 让现有可用按钮实际连接业务/后端能力，消除远端数据被旧本地缓存覆盖的问题，并保证所有二级页面可退出。

**Architecture:** 保持 Flutter 的 `DataService` / `CompositeDataService` 门面和 FastAPI 现有路由边界。把已有后端能力接进数据服务，明确保留真正依赖外部提供方的预留状态；主应用二级页面统一从主壳返回与 PopScope 状态退出。

**Tech Stack:** Flutter/Dart、flutter_test、FastAPI/Python、pytest、Nginx、Flutter Web release build。

---

### Task 1: 锁定远端优先和错误降级契约

**Files:**
- Modify: `lib/services/composite_data_service.dart`
- Test: `test/composite_data_service_test.dart`

- [ ] 为“远端读成功时不读本地并返回远端值”添加测试。
- [ ] 为“远端返回 401/409 时不读本地”添加测试。
- [ ] 为“远端网络不可用或 5xx 时读取本地”添加测试。
- [ ] 将默认策略改为远端优先，并保留现有写成功后本地缓存尽力同步语义。
- [ ] 运行 `flutter test test/composite_data_service_test.dart`，确认新增断言通过。

### Task 2: 接通已有远端业务能力

**Files:**
- Modify: `lib/services/data_service.dart`
- Modify: `lib/services/remote_data_service.dart`
- Modify: `lib/services/composite_data_service.dart`
- Modify: 依赖这些能力的页面及 `lib/screens/debug/diagnostics_page.dart`
- Test: `test/remote_data_service_test.dart`、`test/composite_data_service_test.dart`
- Modify: `deploy/nginx-ruanchuang.conf`
- Test: 对应 `backend/tests/test_*.py`

- [ ] 将可见动作逐项映射到已经存在的 FastAPI 路由：周/月复盘、目标下一步排程、微任务推荐/导入/批量操作、日程冲突/ICS、团队冲突/共同窗口、救援方案/应用/撤销/历史、用户资料更新、诊断与平台摘要。
- [ ] 为当前确实缺少服务端持久化的主题/语言偏好添加经过认证且按用户隔离的设置路由及 SQLite 持久化；收藏设备在设备接入前保持本地语义，不创建虚假设备绑定。
- [ ] 页面调用统一经 `AppServices.dataService`；请求/校验/权限错误保留原语义，只有离线/5xx 才使用本地兜底。
- [ ] 将 `/openapi.json`、`/docs`、`/redoc` 正确反代到 FastAPI，且不改变 Flutter SPA 回退规则。
- [ ] 使用 MockClient 验证 HTTP 方法、路径、查询参数、JSON 字段和错误传递；用 pytest 验证新增后端设置的认证、隔离和持久化。
- [ ] 运行受影响 Flutter 与后端测试。

### Task 3: 给未接入外部能力补齐诚实交互

**Files:**
- Modify: `lib/screens/profile_page.dart`
- Modify: `lib/screens/bluetooth_page.dart`
- Modify: `lib/screens/integrations_page.dart`
- Modify: `lib/screens/debug/diagnostics_page.dart`
- Test: 相关页面 widget tests

- [ ] 盘点页面所有已启用按钮、图标按钮和 tappable 行，确保其有回调且回调能成功、失败或显示明确预留状态。
- [ ] 蓝牙、通知及第三方集成在当前平台/部署不可用时显示状态说明和可关闭提示；不显示假成功。
- [ ] 对可在 Web 上运行但在原生平台不同的动作呈现一致且平台正确的状态。
- [ ] 用 widget tests 覆盖每类不可用动作的点击反馈和关闭操作。

### Task 4: 统一二级页面返回状态

**Files:**
- Modify: `lib/screens/main_screen.dart`
- Modify: 所有创建 `MainScreen(secondaryPage: ...)` 的调用点
- Test: `test/main_screen_shell_test.dart`

- [ ] 添加失败测试：二级页显示可访问的返回按钮，点击后恢复其所属主 tab。
- [ ] 添加失败测试：PopScope 系统返回先退出二级页，不误退出整个应用。
- [ ] 添加失败测试：切换 tab 后再返回不会重新显示旧二级页。
- [ ] 在 MainScreen 增加受控的二级页返回回调，次级壳用一致标题/返回操作调用它。
- [ ] 保证二级页中正常 Navigator 对话框/路由返回优先处理，避免返回手势误关主应用。
- [ ] 运行 `flutter test test/main_screen_shell_test.dart` 和相关次级页面布局测试。

### Task 5: 完整回归和 Web 构建

**Files:**
- Review: `git diff --check`、完整 diff、工作区状态
- Build: `build/web`

- [ ] 运行 `flutter analyze`。
- [ ] 运行 `flutter test -r compact`。
- [ ] 运行 `python -m pytest backend/tests -q`。
- [ ] 运行 `flutter build web --release --no-wasm-dry-run --dart-define=API_BASE_URL=http://8.133.250.216` 并验证产物中的 API 地址。
- [ ] 确认现有 `test/failures/` 用户文件未被修改。
- [ ] 检查完整 diff 和状态后提交并推送 `main` 到 `origin`；不直接改动线上服务器。
