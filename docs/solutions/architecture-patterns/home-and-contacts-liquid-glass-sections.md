---
title: WCLiquidGlass 主页与通讯录的液态圆角分区实现
date: 2026-07-28
category: architecture-patterns
module: WCLiquidGlass Home Corners
problem_type: architecture_pattern
component: tooling
severity: high
applies_when:
  - 修改首页圆角、会话卡片、通讯录卡片或它们的液态背景时
  - 处理 UITableView 复用、滚动或页面切换后出现的圆角、背景或点击错位问题时
tags: [wechat-plugin, liquid-glass, home-corners, contacts, table-view, section-background, avatar-clipping]
---

# WCLiquidGlass 主页与通讯录的液态圆角分区实现

## Context

“首页圆角”需要同时适配微信主页会话列表和通讯录。两者虽然都由 `UITableView` 驱动，但几何与复用约束不同：主页允许根据用户设置改变会话卡片的缩进、圆角和独立卡片间距；通讯录必须保持微信的原生 Cell 几何与命中测试，同时把连续的原生 section 视觉上组合为一张玻璃卡片。

该方案已经完成真机验证。主页连续会话 section 的效果是已确认的基线，后续不要为其它页面的问题改动它；通讯录头像圆角也必须保持对其他插件的兼容性。

## Guidance

### 1. 主页：连续会话使用“section 后方的一张玻璃”，不使用每行玻璃

主页会话列表的连续模式由 `WCLiquidGlassHomeCornerUpdateSectionGlassViews` 管理：它只为可见的连续 section 建立一个 `UIVisualEffectView`，并插入在第一个 Cell 的下方。玻璃框架来自该 section 第一行与最后一行的并集，四角使用同一半径裁切；原生 Cell 自身保持透明。

实现位置：[WCLiquidGlassHomeCorners.m](../../../WCLiquidGlassHomeCorners.m) 第 859 行。

这样做的结果是：

- 首、中、尾行在视觉上组成真正连续的一张卡片；中间不会产生分割线、重复圆角或灰黑色底板。
- 玻璃只渲染一次，滚动时不会给每个会话重复创建效果层。
- Cell 仍由微信的 TableView 管理，因此点击、长按、左右分组手势和复用行为保持原生坐标系。

主页可选“每条独立圆角卡片”。仅此模式允许使用 `homeCornerRadius`、`homeCardGap` 和逐行 `glassOverlay`；普通连续模式必须走 section 玻璃。`WCLiquidGlassHomeCornerUsesIndependentCard` 与 `WCLiquidGlassHomeCornerGapForCell` 是这条分流的唯一入口，见 [WCLiquidGlassHomeCorners.m](../../../WCLiquidGlassHomeCorners.m) 第 461 行。

用户修改独立卡片间距时，间距必须先加入原生 `heightForRowAtIndexPath:` 返回值，然后再把 Cell 在该增加的行高内上下各缩进一半。当前实现在 [WCLiquidGlassHomeCorners.m](../../../WCLiquidGlassHomeCorners.m) 第 478、555 行。不要在列表完成布局后单独移动 Cell，否则视觉位置和点击位置会分离。

### 2. 通讯录：固定 26pt 圆角，保留原生 Cell 几何

通讯录属于 `OtherTab` 角色。它固定使用 26pt 圆角，不跟随主页的半径、独立卡片开关或会话间距。Cell 不重新设置 frame；`WCLiquidGlassHomeCornerApplyCell` 在非主页角色下明确恢复并保留原始 frame，见 [WCLiquidGlassHomeCorners.m](../../../WCLiquidGlassHomeCorners.m) 第 571 行。

视觉分区由 `WCLiquidGlassHomeCornerVisualSectionRange` 合并：相邻 section 的原始行框架无间隙时，它们被视为同一连续视觉 section；真正需要间隔的 header 则保留 8pt。相关逻辑在 [WCLiquidGlassHomeCorners.m](../../../WCLiquidGlassHomeCorners.m) 第 778、506 行。

通讯录的 section 玻璃采用固定外边距：左侧 16pt，右侧预留 24pt 给 A–Z 索引栏，垂直方向扩展 8pt。见 [WCLiquidGlassHomeCorners.m](../../../WCLiquidGlassHomeCorners.m) 第 808 行。内部内容的边距只通过 `contentView` 与其稳定的内部容器修正，且会保存原始 frame，避免滚动或切页时叠加偏移。见 [WCLiquidGlassHomeCorners.m](../../../WCLiquidGlassHomeCorners.m) 第 642 行。

### 3. 背景的唯一来源是玻璃层，所有原生底色必须透明

开启“液态背景”后，Cell 的 `backgroundView`、`backgroundColor`、`contentView.backgroundColor` 和微信重建的内部不透明背景都要被清理；表格 separator 也必须隐藏。连续模式不在 Cell 内添加玻璃，独立模式才使用 Cell 内的 `glassOverlay`。该分流和清理过程位于 [WCLiquidGlassHomeCorners.m](../../../WCLiquidGlassHomeCorners.m) 第 606、713 行。

这条边界是避免“刚打开很透明，滚动后又出现灰白或灰黑色底”的关键：如果透明 Cell 上仍残留任一微信原生背景，复用或滚动后的重写会和玻璃层混合，造成双状态与闪烁。

### 4. 通讯录头像只裁切稳定外层，绝不改内部图片层

`MMHeadImageView` 是微信联系人头像的稳定外层。通讯录处理只给这个外层标记并设置圆形裁剪，半径为自身较短边的一半；不递归重写 `MMUILongPressImageView`、隐藏的 `UIImageView` 或其它内部子层。见 [WCLiquidGlassHomeCorners.m](../../../WCLiquidGlassHomeCorners.m) 第 989 行。

微信及其它插件会在复用和滚动时重设内部图片层。为了保证首次进入、滚动和切页都稳定，`MMHeadImageView` 的 `layoutSubviews` 原实现执行后会再次应用外层裁剪；该 hook 只作用于先前被通讯录 Cell 标记的头像。见 [WCLiquidGlassHomeCorners.m](../../../WCLiquidGlassHomeCorners.m) 第 1015、1156 行。

这条限制同时保证：

- 通讯录头像不会随机在圆形和方形之间切换。
- 不会覆盖其它插件对内部图片、描边、徽标或加载层的处理。
- 主页、聊天页及不属于 `NewContactsItemCell` 的头像不会被此 hook 改写。

### 5. 刷新时序：原生布局先执行，插件更新必须可重复

所有 Cell hook 都先调用微信原来的 `layoutSubviews`，然后再应用本插件的状态。表格布局完成后再收集可见 Cell、更新玻璃 section。每次更新都会基于保存的 base frame / base content frame 判断是否已经应用过，避免把相同偏移重复累加。主要入口见 [WCLiquidGlassHomeCorners.m](../../../WCLiquidGlassHomeCorners.m) 第 926、972 行。

不要把刷新建立在固定延迟、滚动结束回调或一次性扫描上。页面首次展示、Cell 复用、主题切换、返回页面和偏好变更都会触发布局；实现必须在这些路径中保持幂等。

## Why This Matters

主页与通讯录曾出现过四类连锁问题：连续卡片被拆成每行圆角、背景被微信重写为灰白/灰黑、视觉和命中区域错位，以及通讯录头像被内部层竞争导致随机变方。上述结构将“几何、背景、材质、头像”分别交给最稳定的所有者：原生 TableView 管理命中和行几何，section 玻璃负责连续材质，透明 Cell 承载微信内容，`MMHeadImageView` 只负责最终头像裁切。

## When to Apply

- 在主页新增会话卡片效果、间距或玻璃样式时，先判断是连续 section 还是独立卡片，不能混用两条渲染路径。
- 在通讯录、发现或“我”页处理连续 section 时，优先复用 section 玻璃与透明 Cell 的模式；不要复用主页的 Cell frame 收缩逻辑。
- 出现滚动后背景变化、首次进入不一致或头像圆角丢失时，先检查原生布局后的背景写入与关联状态，而不是增加延迟重刷。

## Regression Checklist

1. 主页连续会话 section 在深浅色、滚动、切换分组和返回后始终是一张完整玻璃卡片，无分割线、无底板、无圆角断裂。
2. 主页独立卡片模式的间距只改变独立会话，点击会话、左右分组手势与视觉位置一致。
3. 通讯录“新的朋友”至“企业微信联系人”保持一个连续视觉 section，左右留出 16pt / 24pt，内部内容不越界且 A–Z 索引可用。
4. 通讯录首次进入、滚动和切页后，所有 `MMHeadImageView` 都保持圆形；其它插件处理的头像边框、徽标和内部效果仍存在。
5. 所有页面启用液态背景后，原生不透明背景与 separator 不会在滚动、复用或主题切换后重新出现。

## Related

- [德发首页圆角的逆向实现笔记](defa-home-corners-reverse-engineering.md)
- [WCLiquidGlass 插件架构与微信插件开发规范](wcliquidglass-plugin-development-specification.md)
