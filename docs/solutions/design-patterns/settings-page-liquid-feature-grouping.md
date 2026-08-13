---
title: WCLiquidGlass 设置页液态功能与左滑设置分组
date: 2026-08-09
category: design-patterns
module: WCLiquidGlass
tags: [ios, settings, liquid-glass, uikit, message-swipe]
---

# 设置页液态功能与左滑设置分组

主设置页只保留入口级选项：全局菜单开关、菜单样式，以及由菜单样式决定的布局选项。悬浮入口固定为统一尺寸；环形菜单显示“紧凑布局”；液态面板显示“面板菜单大小”和“悬浮按钮轨迹”。

“液态功能”是独立结构化设置页，集中管理全局液态效果、聊天时间条、长按菜单、通讯录索引、未读消息提示，并链接“通知圆角与液态”和“首页圆角与液态”两个已有配置页。

“左滑引用/复读”是普通二级页面，集中管理整行左滑开关和左滑菜单大小；“左滑菜单大小”使用小型 action sheet 选择。它继续使用 `WCLiquidGlassMessageSwipe` 的运行时实现与主题图标，不在设置页复制运行时逻辑。

只有内容较多、需要独立结构化浏览但不依赖长期编辑导航的页面使用 UIKit 的 `UIModalPresentationPageSheet` + `UISheetPresentationController`：液态功能页面保留原生 sheet；按钮与动作、左滑引用/复读、日志使用普通二级页面。Sheet 通过 `detents` 提供 medium/large 高度，并使用 `prefersGrabberVisible` 显示拖拽条。不要设置 `preferredCornerRadius`，让 iOS 26+ 使用系统默认的非对称卡片几何；当前 402×874 视口下，默认渲染约为左右 8pt 间距、底部约 8pt 间距、顶部圆角约 35pt、底部圆角约 51pt。这个几何来自系统 sheet 容器，不能用固定圆角或额外底部 inset 替代。

菜单样式、紧凑布局、面板菜单大小、悬浮按钮轨迹和左滑菜单大小都是短枚举选择，恢复使用 `UIAlertControllerStyleActionSheet`，并将触发单元格作为 `sourceView/sourceRect`。全局菜单和左滑菜单仍由 `UIMenu` 负责呈现，避免设置 UI 与运行时菜单实现耦合。
