# 成员 C 主路径截图基线（2026-09-21）

> 分支：`feature/member-c-mainpath-states`
> 范围：Focus 页、智能日历页（成员 C 主路径）

## 产出方式

- 由 `test/visual_baseline_test.dart` 生成/校验，路径：`test/goldens/visual_baseline/`。
- 智能日历页：pixel golden 基线（页面布局按日锚定，跨运行确定）。
- Focus 页：与当前时刻强相关（当前/后续任务划分随时间变化），采用结构化基线（五尺寸无溢出、关键状态组件存在），不做 pixel golden。
- 重新生成日历 golden：`flutter test test/visual_baseline_test.dart --update-goldens`。
- 回归校验：`flutter test test/visual_baseline_test.dart`（CI 可复现）。
- 数据来源：`MockDataService` + 注入的两条当日日程（09:00 深度工作 120 分钟、14:00 评审 60 分钟），非生产数据。

## 尺寸矩阵

| 尺寸 | Focus（结构断言） | 智能日历（golden） | 结论 |
| --- | --- | --- | --- |
| 375x812 | 通过 | calendar_375x812.png | 无横向溢出，无异常 |
| 390x844 | 通过 | calendar_390x844.png | 无横向溢出，无异常 |
| 720x900 | 通过 | calendar_720x900.png | 无异常 |
| 1024x768 | 通过 | calendar_1024x768.png | 无异常 |
| 1440x900 | 通过 | calendar_1440x900.png | 无异常 |

## 已知限制与未覆盖项

1. golden 使用测试字体（字形为方框），只能验证布局、溢出和状态结构，不能验证品牌字体与真实中文排版。
2. 截图为页面级（不含壳层导航）；壳层响应式由 `main_screen_shell_test.dart` / `responsive_layout_test.dart` 覆盖。
3. 深色模式、系统字体放大、离线网络三种组合状态未出图，仅有测试断言覆盖。
4. 真机/浏览器实测截图属发布验收（成员 E），本基线不能替代设备证据。
5. 旧的手动截图 `apple-glass-*.png` 为 2026-08-31 视觉稿留存，与本基线无关。
