---
title: 微信插件设置页的 Liquid Glass UI 结构
date: 2026-07-17
category: design-patterns
module: WCLiquidGlass settings UI
problem_type: design_pattern
component: tooling
severity: medium
applies_when:
  - 在微信插件列表中提供独立设置控制器时
  - 设置页需要兼容新系统 Liquid Glass 与旧系统材质效果时
tags: [ios, uikit, liquid-glass, settings-ui, dynamic-color, cards]
---

# 微信插件设置页的 Liquid Glass UI 结构

## Context

插件设置页既要融入微信现有导航栈，也要在浅色、深色和不同 iOS 版本中保持可读。直接修改共享 `UINavigationBarAppearance` 会污染退出后的其他微信页面，因此视觉设计应主要落在控制器内容区域。

## Guidance

设置控制器使用 `UITableViewStyleInsetGrouped` 保留系统交互、动态字体布局和返回手势。页面背景使用动态渐变 `backgroundView`，但不修改共享导航栏的 standard、scroll edge 或 compact appearance；导航栏相关经验见 [原生导航栏滚动变黑问题](../ui-bugs/native-navigation-bar-turns-black-after-scrolling.md)。

内容采用三层视觉结构：

1. 顶部品牌卡：`UIVisualEffectView`、28pt 连续圆角、50pt 品牌图标、标题、副标题和独立版本胶囊。
2. 功能分区：菜单、内容、维护使用简短分区标题和说明文字，避免把说明塞进单元格标题。
3. 分区卡片：同一 section 的首尾单元格分别裁切上、下连续圆角，动态白色或深色材质背景形成完整 card。

玻璃效果优先动态创建 `UIGlassEffect`，不可用时回退 `UIBlurEffectStyleSystemMaterial`。颜色使用 `labelColor`、`secondaryLabelColor`、`systemBlueColor`、`systemRedColor` 和动态 provider；不要写死仅适合浅色模式的文字或背景颜色。

中文字体优先使用 `PingFangSC-Regular` 与 `PingFangSC-Semibold`，不可用时退回系统字体。普通设置项使用原生 `UISwitch`、disclosure indicator、action sheet 和 alert，避免为标准交互重复制造自定义控件；日志 Page Sheet 的清空使用 `UIBarButtonItem(menu:)`，菜单只提供一个带垃圾桶图标的确认动作；菜单样式配置另外提供原生层级 `UIMenu` 与二级 `PageSheet` 两种入口，详见[原生层级 UIMenu 与二级 Page Sheet 设置入口](native-settings-menu-and-sheet.md)。

按钮与动作、左滑引用/复读等需要持续编辑或保留导航上下文的页面由宿主导航控制器 `pushViewController:` 进入，保留原生返回按钮；液态功能总览和崩溃日志等结构化浏览页使用系统 `UIModalPresentationPageSheet`。枚举选择优先使用 `UIAlertControllerStyleActionSheet`，不要为每个选项建立独立 sheet。按钮管理页把预览说明、当前按钮和管理动作分开；新增和恢复只保留一个入口，编辑状态使用表格原生排序与删除能力。

## Why This Matters

这种结构把品牌感限制在插件自己的内容区，同时复用 UIKit 的导航、可访问性和状态适配。旧系统可以自然降级，新系统获得玻璃材质，但不会把全局 appearance 泄漏到微信其他页面。

## When to Apply

- 新增插件设置主页或二级设置页时。
- 需要卡片化分区，同时保留系统表格行为时。
- 需要展示版本信息但不希望污染插件列表右侧版本格式时。

## Examples

当前主页在品牌卡中显示 `Version <版本号>`，插件列表本身只传递纯版本号；危险的“恢复默认设置”使用系统红色，普通配置项使用标签色，所有卡片和背景均随深浅色模式变化。实现位于 [WCLiquidGlass.m](../../../WCLiquidGlass.m)。

## Related

- [微信原生图标解析与回退](wechat-native-icon-resolution.md)
- [WCLiquidGlass 自绘图标设计规范](wcliquidglass-icon-design-system.md)
- [原生导航栏滚动变黑问题](../ui-bugs/native-navigation-bar-turns-black-after-scrolling.md)
