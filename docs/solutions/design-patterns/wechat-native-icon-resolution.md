---
title: 微信插件复用原生图标素材的解析与回退策略
date: 2026-07-17
category: design-patterns
module: WCLiquidGlass icon pipeline
problem_type: design_pattern
component: tooling
severity: medium
applies_when:
  - 为微信插件的导航入口或聊天工具复用微信原生图标时
  - 微信版本变化可能导致资源名称或内部视图层级变化时
tags: [ios, wechat-plugin, icon-assets, theme-manager, runtime-mapping]
---

# 微信插件复用原生图标素材的解析与回退策略

## Context

微信内置图标并不都能通过一个稳定的 `UIImage imageNamed:` 名称取得。部分素材由主题管理器按 SVG 名称和颜色生成，部分导航图标只能从当前 TabBar 的运行时对象中读取，而且不同微信版本可能使用不同资源名或私有属性。

## Guidance

以稳定的动作标识作为唯一业务入口，并为每个动作维护按优先级排列的微信资源候选名。当前映射集中在 [WCLiquidGlassPreferences.m](../../../WCLiquidGlassPreferences.m)，不要把资源名散落在设置页和悬浮菜单中。

解析顺序保持为：

1. 通过 `MMServiceCenter` 获取 `MMThemeManager`，依次尝试 `drawer_<资源名>` 和原始资源名的 `svgImageNamed:color:`。
2. 再依次尝试 `UIImage imageNamed:` 的 drawer 名称和原始名称。
3. 对 TabBar 动作，从微信私有 TabBar 按钮、系统 TabBar 子视图和 `UITabBarItem` 中按顺序提取图片。
4. 都失败时才使用动作目录中声明的 SF Symbol，最后使用 `questionmark.circle.fill` 兜底。

私有 selector 必须先经过 `respondsToSelector:`，动态调用包在 `@try/@catch` 中；递归提取图标需要限制深度。对应实现集中在 [WCLiquidGlassMenu.m](../../../WCLiquidGlassMenu.m)。

渲染模式应表达素材意图：微信彩色图片保留 `AlwaysOriginal`；需要跟随当前主题颜色的 TabBar 图标和 SF Symbol 使用 `AlwaysTemplate`。关闭图标和收起入口各自拥有独立候选名与最终回退，不复用业务动作图标。

## Why This Matters

单一硬编码资源名容易在微信升级后失效；统一候选映射和分层回退可以最大程度保持微信原生风格，同时避免插件因为缺少某个素材而显示空白按钮。

## When to Apply

- 新增环形菜单动作时，同时补充标题、SF Symbol 和微信资源候选名。
- 需要复用微信导航图标但找不到稳定资源名时，读取当前原生 TabBar 的实际图片。
- 新微信版本改变素材命名时，只调整集中映射，不改动视图代码。

## Examples

“搜索记录”优先尝试 `icons_filled_search` 和 `icons_outlined_search`；若微信当前版本不存在这两个资源，则自动退回 `magnifyingglass`。插件列表对多个实验室、插件、扩展和设置资源名按顺序尝试，以兼容不同主题和版本。

## Related

- [设置页的 Liquid Glass UI 结构](liquid-glass-settings-ui.md)
- [按当前页面过滤不可用动作](page-aware-action-filtering.md)

