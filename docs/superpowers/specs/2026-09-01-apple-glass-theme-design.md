# Apple Utility 色彩与毛玻璃视觉优化设计

**状态**：设计草案，基于现有 Apple/macOS 工作台方向

**适用项目**：`Ruanchuang-main` Flutter 客户端（Android、iOS、Web、macOS、Windows、Linux）

## 1. 目标与范围

本轮以 Apple Design 的响应、空间层级、材质、可访问性和动效原则为依据，统一当前 Flutter 客户端的色彩与半透明材质，让工作台更有苹果系统气质，同时保持日程扫描、任务操作和状态反馈的清晰度。

保留：

- FastAPI、SQLite、`DataService`、`CompositeDataService` 与本地优先策略；
- 日程调度、三方案救援、确认、撤销、事件记录和已有路由；
- Focus、Schedule、Micro、Team、Goals、Review、Profile、Integrations、Bluetooth/Device 页面与既有业务回调。

本轮改变：

- 主题令牌的唯一来源和语义色映射；
- 结构性导航、工具栏、浮层的玻璃材质；
- 页面中硬编码的灰、蓝、紫、红等视觉值向语义令牌迁移；
- 材质出现、按压反馈、减少动画和减少透明度时的视觉表现。

## 2. 设计原则

1. **材质服务于层级**：内容卡片和时间轴保持实面；玻璃只表达浮在内容之上的结构性层。
2. **响应先于装饰**：按下立即反馈，拖动保持 1:1，面板动画从当前屏幕值接续并允许中途打断。
3. **颜色表达语义**：动作、品牌、恢复、压力、风险相互独立；颜色不是唯一状态编码。
4. **明暗成对设计**：浅色和深色各自保持对比度，不把白色透明层直接套在深色内容上。
5. **可降级且诚实**：减少透明度、减少动画、低端设备或不支持模糊时回退到实面，不改变布局与业务状态。

## 3. 颜色令牌

### 3.1 基础令牌

| 令牌 | 浅色 | 深色 | 用途 |
| --- | --- | --- | --- |
| `canvas` | `#F5F5F7` | `#111214` | 页面画布 |
| `surface` | `#FFFFFF` | `#1C1C1E` | 日程、任务、表单、指标内容 |
| `ink` | `#1D1D1F` | `#F5F5F7` | 主要文字和图标 |
| `secondary` | `#6E6E73` | `#98989D` | 辅助文字和非选中图标 |
| `brand` | `#163D3D` | `#A7D4C6` | 品牌标识、工作区标题 |
| `action` | `#007AFF` | `#0A84FF` | 主操作、链接、选中态、焦点环 |
| `recovery` | `#34C759` | `#30D158` | 能量恢复、完成、可用 |
| `pressure` | `#FF9F0A` | `#FF9F0A` | 截止、压力、待处理 |
| `risk` | `#FF3B30` | `#FF453A` | 冲突、失败、逾期 |
| `divider` | `#E5E5EA` | `#38383A` | 分隔线、边界 |

页面色调继续使用低饱和窗口色，但只作为画布层，不替代语义色：Focus、Schedule、Micro、Team、Profile 各自保持轻微区分，内容表面仍从 `surface` 令牌派生。

### 3.2 材质令牌

| 等级 | 使用位置 | 浅色背景 | 深色背景 | 模糊 | 阴影 |
| --- | --- | --- | --- | --- | --- |
| `canvas` | 页面根层 | 不透明 | 不透明 | 0 | 0 |
| `surface` | 内容卡片和时间轴 | 不透明 | 不透明 | 0 | 细边界 |
| `chrome` | 侧栏、标题栏、Rail、底栏 | `surface` 0.76 | `surface` 0.72 | 22 | 轻 |
| `overlay` | 弹层、救援摘要、上下文菜单 | `surface` 0.86 | `surface` 0.82 | 28 | 中 |

玻璃表面使用上沿 1px 高光和语义边界；不叠加多个浅色透明层。模态 `overlay` 使用 scrim，非阻塞浮动面板不使用 scrim。

## 4. 组件与平台行为

### 4.1 主题入口

- `lib/theme/app_theme.dart` 是颜色、排版、组件主题的 canonical source。
- `lib/ui/app_theme.dart` 保留现有断点和兼容 API，转而引用 canonical tokens，消除重复颜色定义。
- 所有页面优先使用 `Theme.of(context).colorScheme` 与 `AppThemeTokens`，业务模型携带的标签色仅用于标签本身。

### 4.2 `GlassSurface`

保留当前 `child`、内边距、圆角、模糊、透明度、色调、阴影和外边距参数，增加材质等级或等价的可选配置。为兼容现有调用，默认等级保持 `chrome`；内容组件必须显式传入 `surface`，浮层显式传入 `overlay`。

当 `MediaQuery.disableAnimations`、用户减少透明度设置、平台能力不足或性能保护开启时，组件回退到对应不透明表面，但保持相同圆角、边界、间距和语义树。

### 4.3 各平台

- 桌面宽屏：侧栏默认 264px 展开或 76px 窄栏；侧栏与标题栏为 `chrome`，内容区保持实面。
- 平板：紧凑 Rail 使用 `chrome`，主内容使用 `surface`；救援摘要可作为 `overlay` 展开。
- 手机：顶部状态栏和五项底栏使用 `chrome`，编辑/救援面板使用 `overlay` 并遵守安全区。
- Web：限制同时存在的模糊层数量，时间轴和长列表不使用大面积 `BackdropFilter`。
- Android/iOS/macOS/Windows/Linux：若系统或渲染器不支持模糊，使用实面回退，不改变功能。

## 5. 动效、输入与可访问性

- 按压反馈在 pointer-down/touch-down 发生，按压缩放约 100ms。
- 面板进入约 260ms、退出约 170ms；材质出现同时过渡透明度、模糊和轻微缩放。
- 手势组件从当前呈现值继续，释放时传递速度给弹簧；不锁定输入、不使用不可中断关键帧。
- `disableAnimations` 时使用短淡入；减少透明度时移除模糊但保留层级边界。
- 可交互控件命中区不小于 44dp；图标按钮必须有 Tooltip、语义标签和禁用原因；键盘焦点环使用 `action`。
- 文本正文不低于 12sp，计时和统计启用等宽数字；状态同时通过图标、文案或形状表达。

## 6. 实施分层

1. 主题令牌与兼容入口统一；补齐材质等级和降级策略。
2. `GlassSurface`、`MainScreen`、`WorkspaceStatusBar`、`RescueSummary`、`AuthDialog` 等结构性表面迁移到 `chrome`/`overlay`。
3. Focus、Schedule、Micro Task、Team、Goals、Review、Profile、Integrations、Bluetooth/Device 页面迁移硬编码视觉值到语义令牌。
4. 为明暗主题、减少动画、减少透明度、低性能回退和响应式断点补齐测试与截图基线。

不在本轮修改后端路由、数据库、调度算法、救援事务、事件记录、权限或预留接口语义。

## 7. 验收标准

- 1440x900、1024x768、390x844 下无横向溢出，底栏不遮挡内容，侧栏与内容边界稳定。
- 浅色、深色、减少动画、减少透明度和高对比模式下文字与状态可读。
- 玻璃只出现在结构性层，时间轴和长列表保持实面；不出现嵌套玻璃导致的灰雾。
- 主题切换、导航、日程视图、救援、确认/撤销、离线/错误/预留状态行为保持不变。
- 运行 `flutter analyze`、`flutter test`、`dart format --set-exit-if-changed .` 与 `git diff --check`；记录真实结果和截图路径。

