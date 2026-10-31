# ICS 交换抽屉

## 需求与实现

ICS 交换以前是独立工作台页面，包含重复侧栏和顶部工具栏。路由因为找不到原生关闭控件而在页面左上角注入返回按钮，页面切换也没有复用抽屉动画。

- `integrations` 加入现有路由抽屉集合，复用背景保留、焦点管理、遮罩、Esc 以及可中断的进出场动画；默认返回智能日历。
- 移除该子界面的独立侧栏与工具栏，左上角关闭按钮放在抽屉内固定标题栏中，引用新增日程的共享关闭样式。
- 无外圈，仅鼠标悬停显示浅灰底色；焦点与鼠标移开都不会让底色常亮。
- **只加宽 ICS 交换抽屉**：通过该面板局部变量设置 1040px，并限制在视口宽度内；其他抽屉默认宽度继续为 480px，手机底部抽屉尺寸保持原状。
- ICS 在桌面和手机均从右侧滑入；内容根据抽屉自身宽度切换双列／单列，标题栏固定，内容独立滚动。
- 保留原有模板、编辑输入、预览以及导入动作，本轮不扩展解析与导出功能。

## 验证

- `node tools/check_web_sources.mjs`：98 个文件、25 个页面、275 处资源引用通过。
- `node --test tools/tests/stitch_release.test.mjs`：2 项通过。
- `node tools/check_stitch_drawers.mjs`：桌面 1440 × 900、手机 390 × 844，共 32 项通过。
- 覆盖 ICS 右侧滑入、1040px／手机适配、左上角关闭按钮、无重复侧栏与外部返回按钮、容器双列／单列、无水平溢出、动画逆转与文档复用。
- 验证实际日历 ICS 入口、模板编辑、导入请求仅发送一次且使用编辑后的内容、导入完成返回日历、Esc 和遮罩关闭；使用隔离 API fixture，不写真实账号数据。
- 其他五类路由抽屉桌面宽度仍为 480px，共享关闭按钮外观与悬停行为检查通过。
- 桌面／手机截图已人工查看：`build/drawer-qa/desktop-integrations.png`、`build/drawer-qa/mobile-integrations.png`。
- Impeccable detector 本轮运行一次，无匹配结果，但 HTML 解析依赖缺失，降级为正则扫描；视觉与交互结论基于浏览器检查。
- `git diff --check` 通过。

## 发布

已部署至 `http://8.133.250.216/`，版本 `ffa9be0468f354c7`。

- 公网运行 `node tools/check_stitch_drawers.mjs --url http://8.133.250.216/`，32 项通过；业务请求使用隔离 fixture，未写入真实数据。
- `/release.json` 为新版本且 `Cache-Control: no-store`；`/health` 返回 `ok: true`。
- 校验 102 个发布文件、Nginx 配置检查通过。
- 上一版本 `6516b2a84c28f40a`，回滚备份 `/opt/ruanchuang/web/backups/20261030T143140Z-ffa9be0468f354c7`。
