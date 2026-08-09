---
title: WCLiquidGlass 设置页液态功能与左滑设置分组
date: 2026-08-09
category: design-patterns
module: WCLiquidGlass
tags: [ios, settings, liquid-glass, uikit, message-swipe]
---

# 设置页液态功能与左滑设置分组

主设置页只保留入口级选项：全局菜单开关、菜单样式，以及由菜单样式决定的布局选项。悬浮入口固定为统一尺寸；环形菜单显示“紧凑布局”；液态面板显示“面板菜单大小”和“悬浮按钮轨迹”。

“液态功能”是独立二级页面，集中管理全局液态效果、聊天时间条、长按菜单、通讯录索引、未读消息提示，并链接“通知圆角与液态”和“首页圆角与液态”两个已有配置页。

“左滑引用/复读”是独立二级页面，集中管理整行左滑开关和左滑菜单大小。它继续使用 `WCLiquidGlassMessageSwipe` 的运行时实现与主题图标，不在设置页复制运行时逻辑。

设置选择器和主要二级页面使用 UIKit 的 `UIModalPresentationPageSheet` + `UISheetPresentationController`：通过 `detents` 提供 medium/large 高度、`prefersGrabberVisible` 显示拖拽条、`preferredCornerRadius` 保持系统圆角。全局菜单和左滑菜单仍由 `UIMenu` 负责呈现，避免设置 UI 与运行时菜单实现耦合。
