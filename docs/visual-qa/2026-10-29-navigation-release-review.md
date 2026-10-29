# 导航修复与发布复核


## 当前发布：连续叠化动效

版本 `fe80ebe02c34a877` 已部署并在线验证，替代下文 `b2008b5ffb562f54`。此前旧页面瞬间隐藏、新页面以完整不透明度位移 3px，仍产生硬切感。现在使用 180ms opacity 叠化，保持内容位置稳定，常驻桌面导航不参与动画。

中断时保存各图层当前透明度；新页面覆盖现有画面，点回已有图层时上层从当前透明度淡出。保留不透明底层以避免白闪。退出图层仍然 inert/aria-hidden、暂停页面活动，完成后清理动画与图层并释放次级页面；减少动态效果、后台标签和跨布局切换立即收束。

`tools/stitch_motion_checks.mjs` 在真实 Chromium 中以 10% 速度检验中点叠化、反向连续性与结束清理：旧实现红灯，新实现本地及线上均通过。完整 navigation/release 浏览器回归及 Node 2/2 发布测试通过。独立 reviewer 另验证三页连续切换后反向返回、次级页面延迟释放、动画中启用 reduced-motion，无剩余阻塞。慢速中间帧见 `build/navigation-motion-midpoint.png`。

生产版本、94 个文件 SHA-256、Nginx 配置与健康检查均通过。上一版 `stitch-b2008b5ffb562f54`；回滚记录 `/opt/ruanchuang/web/backups/20261029T060019Z-fe80ebe02c34a877`。


## 上一发布：保留页面的连续切换

版本 `b2008b5ffb562f54` 已部署到 http://8.133.250.216/ 。根因是旧路由每次重设单个 iframe.src；真实浏览器红灯测试记录微任务再次进入请求数为 2，且输入/滚动状态丢失。

实现采用最多 8 个主页面缓存和独立桌面导航/顶栏。冷加载保留当前内容，样式和字体就绪再切换；后续访问复用文档，内容区使用 140ms 位移过渡并支持减少动态效果。隐藏 iframe 保留布局尺寸以维持滚动位置，同时 inert/aria-hidden；隐藏专注页停止定时绘制，返回时按截止时间修正倒计时。手机/桌面缓存隔离，次级表单离开后释放。页面数据单独刷新，账号变化清理页面和设置弹窗；过期请求不再覆盖新账号的状态。

验证结果：

- Node 发布校验 2/2，Flutter Web 源码合同检查 8/8。
- `tools/check_stitch_navigation.mjs` 本地与 `--url http://8.133.250.216/` 均通过：8 个主页面热切换不新增文档请求、草稿与滚动保留、shell 实例不变、前进后退、减少动态效果、隐藏计时、跨断点、手机页面保留、迟到请求不抢导航、503 重试、保存刷新数据但不重载、账号切换关闭旧设置。
- 线上动作测试拦截所有写请求；日程保存和账号场景使用模拟响应，没有写入生产业务数据。
- `tools/check_stitch_release.mjs --url http://8.133.250.216/` 通过：实际清单匹配、旧缓存升级、旧 worker 清理、8 个主导航选中样式一致，复盘/诊断/日历无注入返回按钮。
- 独立 review 发现并修复跨断点外壳、旧账号设置残留、迟到救援页跳转、旧请求覆盖连接状态；复审无剩余阻塞项。
- 服务器 94 个文件 SHA-256 校验通过，Nginx 配置检查与后端健康检查正常。

当前目录 `/opt/ruanchuang/web/releases/stitch-b2008b5ffb562f54`；上一版 `stitch-dad87faa3a206291`；回滚记录 `/opt/ruanchuang/web/backups/20261029T054806Z-b2008b5ffb562f54`。线上截图保存在 `build/live-schedule.png`、`build/live-review.png`、`build/live-diagnostics.png`。

范围：保留状态适用于当前浏览器会话中的主页面；完整刷新、账号切换及缓存容量淘汰会重新加载。页面首次进入仍需加载，期间保留原内容。业务数据呈现沿用现有页面能力，本次没有改写后端。

## 智能日历选中样式补充修复

后续版本 `dad87faa3a206291` 已部署，并替代下文首轮缓存修复版本。智能日历的导出模板仍携带 `text-on-primary-container`、`font-semibold` 和阴影，与共享选中样式同时存在；其选中项还缺少 `text-sm`。浏览器实测为灰绿色、16px/600 字重、40px 高。

现在先移除每份模板声明的旧 active preset，再应用共享样式。线上八个主导航页面逐项比对：白色文字与图标、`#163d3d` 背景、14px/500 字重、20px 行高、36px 项高、8px 圆角、8px 10px 内边距、无阴影，全部一致。比较等待颜色过渡完成，避免误把中间帧当成最终样式。

独立增量代码 review 无可执行问题。线上截图：`build/live-schedule.png`。92 个发布文件校验通过，后端健康检查正常。

当前目录：`/opt/ruanchuang/web/releases/stitch-dad87faa3a206291`。配置及前版本记录：`/opt/ruanchuang/web/backups/20261029T051814Z-dad87faa3a206291`。

## 首轮缓存修复记录

线上地址：http://8.133.250.216/

发布版本：`d3a321b6c234e16d`。线上 `/release.json` 与本地发布清单一致。

## 证据与根因

- 原导航逻辑把 review、diagnostics 作为 profile 的子页面，因此注入左上角返回按钮；各 HTML 导出页面的选中样式没有统一跟随当前路由。这部分由 `syncSidebarNavigation` 与路由层级修正解决。
- 本轮排查时，服务器返回的无版本 `stitch/router.js` 已与修复源码 SHA-256 一致，但入口引用仍是固定 URL，响应未设置 Cache-Control。本地旧 `build/web` 也未包含修复。
- 使用真实 Chromium HTTP 缓存复现：先访问旧版，服务端替换同 URL 的脚本，再次进入页面仍出现无高亮和返回按钮；服务端脚本请求计数不增加，确认浏览器复用了旧资源。
- 该复现证实发布与缓存策略可以导致同样症状；没有直接读取用户原浏览器缓存，不能把它当作用户设备上的取证。当前 HTTP IP 站点不能注册 service worker；旧 Flutter worker 的清理仅面向 localhost/HTTPS 历史安装。

## 修复

- `web/` 为唯一 Web 发布源；`tools/build_stitch_web.mjs` 生成独立、可校验的版本目录，避免上传过期 Flutter 产物。
- 入口引用 `stitch/router.<release>.js`，子页面参数使用相同版本。入口和清单禁止缓存，Stitch 资源要求重新验证。
- 遗留 Flutter worker 更新后注销，仅清理三个旧应用缓存；账户存储和其他缓存保留。
- 新目录完整校验后原子切换服务器 current 链接，保留旧版及 Nginx 配置供回滚。

## 验证与 review

- 独立代码 reviewer：无阻断或可执行缺陷。其指出的旧 worker 升级测试缺口已补充为“已注册旧 worker → 更新为注销脚本”的实际浏览器测试。
- `node --test tools/tests/stitch_release.test.mjs`：2/2 通过。
- `flutter test --no-pub test/web_stitch_pending_validation_test.dart --reporter expanded`：8/8 通过。
- `tools/check_stitch_release.mjs --url http://8.133.250.216/`：旧 HTTP 缓存复现、无需清缓存升级、旧 worker 迁移、数据保留和线上两个页面检查均通过。
- 线上截图：`build/live-review.png`、`build/live-diagnostics.png`（2048×1120），已目视检查对应导航高亮，左上角没有注入的返回按钮。
- 92 个发布文件的服务器 SHA-256 校验通过；外网再次核对入口、版本脚本、兼容脚本和 worker 的哈希一致。
- `/`、`/release.json`、`/flutter_service_worker.js` 返回 `Cache-Control: no-store`；路由脚本返回 `no-cache`；`/health` 返回 `ok: true`。

首次切换因 Nginx 新 worker 尚未提供缓存头而触发自动回滚；再次发布采用有界就绪检查，等待响应头和版本都正确后才完成验收。

当前目录：`/opt/ruanchuang/web/releases/stitch-d3a321b6c234e16d`

上一版本：`/opt/ruanchuang/web/releases/20261029T044524Z`

备份目录：`/opt/ruanchuang/web/backups/20261029T050359Z-d3a321b6c234e16d`
