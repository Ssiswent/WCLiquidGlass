---
title: "WCGlass 3.0.1 主页加号菜单液态与 iOS 27 返回修复分析"
date: 2026-08-02
category: integration-issues
module: WCGlass 3.0.1 upstream analysis
problem_type: reverse_engineering
component: home-plus-menu-and-navigation
tags: [wcglass, liquid-glass, home-plus-menu, ios-27, navigation, reverse-engineering]
---

# WCGlass 3.0.1 主页加号菜单液态与 iOS 27 返回修复分析

## 样本与版本边界

本次下载并归档的样本为：

```text
WCGlass_3.0.1.dylib
SHA-256: 6268968c7faf4500c57a32c0317bef3b6543835309e4cdec6197c0b5ac579054
```

基线为本地已有的 `WCGlass_2.9.6-8.dylib`。3.0.1 相比基线新增四个可见 Objective-C 类：

- `WCLGFontSettingsViewController`
- `WCLGHomeGroupsPreviewReturnHandler`
- `WCLGMeProfileHeaderWrapperView`
- `WCLGQQGroupTitleControl`

同时新增主页加号菜单相关偏好和动作 selector：

- `homePlusMenuLiquidEnabled`
- `homePlusMenuMarkAllReadEnabled`
- `plusMenuMiniProgramEntryEnabled`
- `wclg_home_plus_menu_liquid_enabled`
- `wclg_home_plus_menu_mark_all_read_enabled`
- `wclg_markAllReadFromRightTopMenu`
- `wclg_openMiniProgramFromRightTopMenu`
- `showRightTopMenuBtn`

这些证据与 3.0.1 的“主页加号菜单重写液态、一键已读、小程序开关”更新说明相互吻合。

## 主页加号菜单液态：实际架构

### 结论

WCGlass 3.0.1 的方案不是重新实现一份独立的加号菜单内容，而是**在微信原生右上角菜单入口上做视觉接管**。二进制中可以确认它安装了 `MSHookMessageEx` Hook，并包含 `showRightTopMenuBtn`、原生菜单显示和自定义菜单动作相关 selector。

因此，这个效果的关键不是“从一个新窗口缩放出一张卡片”，而是：让原来的加号按钮、原来的菜单内容、原来的关闭与命中逻辑继续存在，只在原生生命周期中改变菜单承载和玻璃呈现。

### 已确认的链路

静态代码可确认以下执行结构：

1. 先同时检查总 Liquid Glass 状态和“主页加号菜单液态”开关；任一条件不满足时直接调用微信原实现。
2. 在开启条件满足时，定位当前主页右上角菜单的原生宿主对象。
3. 通过 Objective-C associated object 为宿主保存菜单状态、已处理标记和临时上下文，避免同一个菜单在展示、重入和关闭时被重复改造。
4. 在受控的重入窗口调用原菜单路径，继续让微信创建内容、处理点击、外部点击关闭及原有菜单生命周期。
5. 菜单视图附着后，将视觉修饰放到主线程异步提交，避免和微信本轮布局、弹出事务相互抢占。
6. 一键已读和小程序入口通过独立 action selector 接入原菜单体系，而不是替换既有菜单的内容读取方式。

这正是它的动画能保持“按钮—菜单”视觉连续性的基础：来源按钮与目标菜单均在同一个原生交互链中，而不是两个无关联的覆盖窗口。

### WCLiquidGlass 的公开运行时对应实现

WCLiquidGlass 1.9.2 将这项可验证的结构原则用于可选“液态面板”：独立圆形锚点与圆角面板作为同一 `UIGlassContainerEffect` 的 sibling 真实玻璃表面，先冻结悬浮按钮当前 presentation frame，面板从同一 frame 液态扩散到图标加标题的动作网格，完成后才把同一位置交接为关闭锚点；收起时沿相同 frame 反向收拢，再恢复原加号。它仍自行维护动作过滤、路由和覆盖窗口，不访问 WCGlass，也不宣称使用了其未公开的阻尼或私有实现。

### 材质与动画的可确认范围

3.0.1 二进制保留并使用系统 `UIGlassEffect` / `UIGlassContainerEffect` 的运行时能力，并包含 `animateShowInView:`。结合真机表现，可以确认它优先让原生菜单显示路径和系统玻璃共同驱动开合，而不是只做 `scale + fade` 的独立动画。

但二进制经过混淆，无法可靠还原为“某个固定时长、阻尼、圆角插值参数”。因此，后续 WCLiquidGlass 只能学习以下可证明的原则，不能把不存在证据的具体参数伪装为结论：

- 来源按钮和目标菜单必须共享同一次原生展示 / 关闭事务；
- 菜单内容应由原生路径创建，视觉层在内容附着后再介入；
- 每个宿主只维护一次状态，关闭时必须释放关联状态，防止闪回或二次展示；
- 真实系统玻璃可用时让 `UIGlassEffect` / `UIGlassContainerEffect` 参与，不能用单一截图、遮罩或线性缩放伪造；
- 关闭必须走与展示相同的原生生命周期，不能只移除覆盖层。

### 对 WCLiquidGlass 的使用准则

将来出现“某个原生按钮展开成菜单 / 小弹窗”的需求时，优先使用下列顺序：

1. 找到微信原始展示 selector；
2. 保留原实现来生成真实内容和处理真实关闭；
3. 在同一宿主对象上保存轻量状态；
4. 等目标视图进入层级后再应用玻璃承载和形变；
5. 展开与关闭均以同一状态机清理；
6. 未满足运行时条件时完整回退原实现。

这与“完整自定义一套菜单”不同。只有当微信原生菜单无法提供所需内容、触发或关闭语义时，才考虑独立实现。

## iOS 27 输入框非空返回闪退：与 WCLiquidGlass 的区别

### WCGlass 3.0.1 的证据

3.0.1 新增 `WCLGHomeGroupsPreviewReturnHandler`，并引入以下与返回流程直接相关的符号：

- `returnToGroupsMenu`
- `onBackButtonClicked:`
- `popToRootViewControllerAnimated:`
- `isInTransition` / `setIsInTransition:`

因此可以确认 WCGlass 处理的是**主页分组预览 / 返回导航的事务状态**：用单独的 return handler 和转场中标记，避免在返回路径中重复进入或在不稳定阶段继续执行导航操作。

未在 3.0.1 的新增代码证据中发现与 WCLiquidGlass 相同的 `UITableView numberOfRowsInSection:` / `rectForSection:` 越界保护。仅凭更新日志，不能断言 WCGlass 已经覆盖所有 iOS 27 过期 section 情况。

### WCLiquidGlass 的修复

WCLiquidGlass 针对的是另一层、另一个已经有崩溃日志证实的错误：iOS 27 的 `UIIntelligenceSupport` 在返回转场中请求了已经不存在的 `section 2`，最终触发 `UITableViewRowData` 断言。

它在极窄的风险窗口内对同一张真实首页列表返回自洽的空结果：

- `numberOfRowsInSection:` 返回 `0`；
- `rectForSection:` 返回 `CGRectZero`；
- 仅拦截越界 section；
- 不刷新列表、不改数据源、不延迟转场。

### 比较结论

| 维度 | WCGlass 3.0.1 | WCLiquidGlass |
| --- | --- | --- |
| 修复层级 | 返回导航 / 分组预览状态机 | 表格越界请求的边界保护 |
| 主要证据 | 新增 return handler 与 `isInTransition` | 已捕获 `section 2` 越界及 UIKit 断言日志 |
| 作用方式 | 控制或串行化返回链路 | 让错误的消费者得到零行、零面积的安全结果 |
| 可见行为 | 保持分组预览返回过程稳定 | 不改可见列表或原生返回速度 |
| 关系 | 可能减少触发风险 | 覆盖已证实的最终崩溃入口 |

两者可以同时存在，且不能仅因为 WCGlass 3.0.1 的更新说明就移除 WCLiquidGlass 的兼容层。若未来需要判断上游是否已经完全修复，应在 iOS 27、横向胶囊 / 全屏分组、输入框非空且键盘可见的条件下，关闭 WCLiquidGlass 的兼容开关做真机 A/B；确认不再出现越界诊断后再考虑下线。

## 其他 3.0.1 更新的学习归档

| 更新项 | 二进制记录 | 可学习方向 |
| --- | --- | --- |
| QQ 分组颜色、字体大小 | 新增 `WCLGQQGroupTitleControl` | 配置项与渲染控件分离，避免把字体和颜色判断散落在列表 Hook。 |
| 原生底栏图标改色重写 | 相关配置与图标处理路径扩展 | 图标读取、动态颜色和选中态应走同一主题解析层。 |
| 头像手势复制 wxid | 增加动作入口 | 附加手势只做动作路由，不复制资料页业务。 |
| 换字体，兼容卡片 / 公众号 | 新增 `WCLGFontSettingsViewController` | 全局字体替换必须有页面白名单与回退，而不是无差别替换 `UIFont`。 |
| 启动页壁纸、设置页颜色 | 新增主题背景 / 设置主题配置 | 主题值应由单一配置源发布变更通知，让已显示页面主动刷新。 |
| 顶栏渐隐、底栏图标改色修复 | 现有视觉模块修正 | 动画与主题刷新必须同时覆盖 trait / 颜色模式切换，而不是只在首次布局写入。 |

## 相关文档

- [WCGlass 上游版本演进与可复用设计学习](../architecture-patterns/wcglass-upstream-evolution-learning.md)
- [WCGlass 在 iOS 27 从聊天页返回时的过期分区闪退](wcglass-ios-27-stale-section-return-crash.md)
- [WCGlass 底栏搜索框模式首次切换标签页黑屏](wcglass-search-tab-bar-cold-start-black-screen.md)
