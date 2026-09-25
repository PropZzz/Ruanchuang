# Ruanchuang Design System Stitch 导出

项目：`Ruanchuang Design System`
Stitch 项目 ID：`2037391297990000917`

每个屏幕目录包含：

- `index.html`：已本地化的页面代码，可直接从本地打开
- `hosted.html`：从 Stitch hosted URL 原样下载的 HTML
- `screen.json`：Stitch `get_screen` 返回的屏幕元数据、原始 HTML URL 和截图 URL
- `screenshot.png`：按 `screen.json` 原生像素尺寸从本地 HTML 渲染的高清截图
- `hosted-screenshot.png`：Stitch 提供的原始预览截图
- `asset-manifest.json`：该页面引用的远程资源与本地映射

公共资源位于 `stitch/assets/`：包括 Google Fonts、Material Symbols 字体、Tailwind CDN 脚本和页面图片。`index.html` 已将这些引用改写为相对路径；本地页面不再依赖网络资源。

`manifest.json` 保存 13 个画板的 Stitch ID、中文标题、原始托管 URL 与本地文件路径。

高清截图由本地化 HTML 按 `screen.json` 的原始像素尺寸离线渲染。重新拉取需要 Chrome 或 Chromium；可通过 `CHROME_PATH` 指定浏览器位置。原始 Stitch 预览图单独保存在 `hosted-screenshot.png`。

## 画板

| 目录 | 画板 |
| --- | --- |
| `smart-calendar` | 智能日历核心工作台 |
| `rescue-comparison` | 紧急任务三方案救援比较 |
| `focus` | 专注 Focus |
| `team` | 团队 Team |
| `microtasks` | 微任务 Microtasks |
| `profile` | 我的 Profile |
| `goals` | 目标与执行分解 Goals |
| `review` | 智能复盘与调度审计 Review |
| `integrations` | MCP 接入与智能解析 Integrations |
| `settings-drawer` | 设置抽屉与系统偏好 Settings Drawer |
| `bluetooth` | 蓝牙设备与传感器 Bluetooth |
| `emotion-energy` | 情绪与能量 Emotion & Energy |
| `diagnostics` | 系统诊断 Diagnostics |

## 重新拉取

在临时安装 `@google/stitch-sdk` 后运行：

```powershell
$env:STITCH_API_KEY = '你的 Stitch API key'
node tools/stitch_fetch.mjs stitch
```

脚本不会把 API key 写入文件或提交到 Git。
