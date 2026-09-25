# Ruanchuang Design System Stitch 导出

项目：`Ruanchuang Design System`
Stitch 项目 ID：`2037391297990000917`

每个目录包含：

- `index.html`：Stitch 生成的页面代码
- `screenshot.png`：对应页面截图

`manifest.json` 保存 13 个画板的 Stitch ID、中文标题、托管 URL 与本地文件路径。

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
