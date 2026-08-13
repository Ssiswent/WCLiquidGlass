---
title: "WCGlass 上游版本演进与可复用设计学习"
date: 2026-08-02
category: architecture-patterns
module: WCGlass upstream learning
problem_type: reverse_engineering
component: compatibility-and-ui-architecture
tags: [wcglass, liquid-glass, wechat-plugin, reverse-engineering, architecture, tab-bar, menu]
---

# WCGlass 上游版本演进与可复用设计学习

## 目的与边界

WCGlass 的更新通常同时包含功能、修复和历史功能的汇总说明。对 WCLiquidGlass 而言，最值得复用的是其**架构和交互策略**：优先保留微信原生业务、把视觉层隔离为可替换层、以状态机约束转场，再为旧系统保留显式降级路径。

本记录只依据本地二进制和已验证行为归纳设计原则，不复制 WCGlass 的私有实现或混淆后的代码。所有“新增”都以相邻版本二进制差异为准；更新日志中无法由差异确认的历史条目会明确标为“版本内存在，但无法证明是该小版本首次加入”。

## 3.0.2-4 的实测变更

比较 `WCGlass_3.0.2-1.dylib` 与 `WCGlass_3.0.2-4.dylib` 可确认，3.0.2-4 的核心增量集中在搜索框底栏的滚动收拢与 Liquid Glass 降级边界，而不是重写普通四个 Tab 的页面切换。

### 搜索框底栏滚动收拢

`WCLGSearchTabBarOverlay` 从 36 个 ivar / 126 个方法增长到 39 个 ivar / 133 个方法。新增的状态和方法包括：

- `scrollCollapsed`
- `scrollCollapseModeFrame`
- `scrollCollapseSearchFrame`
- `applyScrollCollapsedVisual:animated:`

同时新增 `WCLGTabBarScrollCollapseRegistry`，集中注册底栏、判断某个 scroll view 是否可驱动底栏，并观察滚动位置。

这说明它没有把滚动事件分散写进每一个页面，而是采用了：

1. 注册中心识别可驱动对象；
2. 首次布局时保存完整几何；
3. 滚动期间以 transform 和视觉状态收拢；
4. 恢复时回到保存的 frame；
5. 用 `performWithoutAnimation:` 避免布局提交和动画事务互相竞争。

这是值得沿用的模式。对于 WCLiquidGlass 将来需要随滚动收拢的视觉组件，应保存“原始几何 + 当前视觉态”，而不是在滚动回调里持续重写 Auto Layout 或 frame。

### 旧系统与磨砂降级

3.0.2-4 新增或扩展了以下配置边界：

- `forceLiquidGlassDisabled`
- `wclg_force_liquid_glass_disabled`
- `simulatedGlassView`
- `wclgGlassView`
- `wclgSimulatedGlassView`

这与更新日志中的“加入磨砂、完全关闭液态、旧系统适用”一致。可学习的要点是：真实系统玻璃和模拟玻璃应有独立对象及明确开关，不能把“系统不支持”混成透明度为零或半初始化的玻璃视图。这样才能避免材质、命中测试和转场状态相互污染。

### 对 WCLiquidGlass 的已知兼容关系

3.0.2-4 中 `WCLGSearchTabBarOverlay selectIndex:` 的主体指令形态与 3.0.2-1 保持一致；没有发现其将普通四个 Tab 的真实页面选择收敛到一次原生 `setSelectedIndex:`。

因此，WCLiquidGlass 的“底栏搜索框模式首次切换黑屏”兼容层仍然保留。它只在确认真实微信 TabController、普通四个 Tab 和无进行中事务时接管页面选择，仍是比替换 WCGlass 底栏更窄的修复范围。

## 上游更新日志的分类方法

WCGlass 3.0.2-4 的长更新日志包含三类信息：

| 类型 | 例子 | 对 WCLiquidGlass 的处理 |
| --- | --- | --- |
| 可从相邻二进制确认的新代码 | 搜索框底栏滚动收拢、Liquid Glass / 磨砂分支 | 记录为可复用架构模式。 |
| 当前版本确实包含但难以证明首次加入的能力 | 搜索框底栏卡片、上滑菜单、壁纸覆盖发现与我 | 作为交互方向记录，不按“3.0.2-4 新增”写入实现结论。 |
| 与 WCLiquidGlass 当前范围无关的业务功能 | QQ 分组、字体替换、TG 相册、红包颜色 | 不跟随移植；仅在未来用户明确提出相同需求时参考其分层方式。 |

这种分类避免把累计更新日志误当成逐小版本的精确变更，也能防止因为上游功能多而无意扩大 WCLiquidGlass 的职责。

## 可长期复用的原则

1. **原生业务优先。** 菜单动作、页面选择、数据源和关闭时机尽量仍由微信执行；插件只接管已确认稳定的视觉或兼容节点。
2. **一处状态源。** 滚动收拢、菜单显隐、选择事务都应有单一状态对象或注册中心，避免多个 view 各自猜测当前阶段。
3. **几何与视觉分离。** 保存原始 frame，以 transform、alpha、材质和圆角实现视觉过渡；不要在高频回调中不断改变逻辑布局。
4. **真实材质与模拟材质分开。** 系统 `UIGlassEffect` 可用时使用真实材质；不可用时走独立的磨砂实现和可见开关。
5. **兼容修复只收敛一次副作用。** 当问题是多条路径竞争时，保留上游的触感、高亮、收起动画等无害效果，只将真正的状态写入收敛到一次原生调用。

## 后续使用规则

未来新增类似“按钮展开为菜单”或“底栏随滚动变化”的功能时，先采用本文件的结构原则，再针对目标微信版本做最小运行时验证。不得仅依据 WCGlass 的更新日志推断 selector、动画参数或私有类关系；这些内容必须由当前二进制、诊断日志或真机行为再次确认。

## 相关文档

- [WCGlass 3.0.1 主页加号菜单与 iOS 27 返回修复分析](../integration-issues/wcglass-3.0.1-home-plus-menu-and-ios27-return.md)
- [WCGlass 底栏搜索框模式首次切换标签页黑屏](../integration-issues/wcglass-search-tab-bar-cold-start-black-screen.md)
- [WCGlass 在 iOS 27 从聊天页返回时的过期分区闪退](../integration-issues/wcglass-ios-27-stale-section-return-crash.md)
