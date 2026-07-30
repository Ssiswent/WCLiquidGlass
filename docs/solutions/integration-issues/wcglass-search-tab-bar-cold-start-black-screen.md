---
title: "WCGlass 底栏搜索框模式首次切换标签页黑屏"
date: 2026-07-30
category: integration-issues
module: WCLiquidGlass WCGlass search tab bar compatibility
problem_type: integration_issue
component: tab-switching
severity: high
symptoms:
  - "WCGlass 3.0.1 启用底栏搜索框模式后，冷启动首次在底栏切换微信、通讯录、发现或我，页面可能黑屏"
  - "仅加载 WCGlass 也会复现，说明问题不由 WCLiquidGlass 环形菜单引入"
  - "通过 WCLiquidGlass 环形菜单切换同一标签页不复现"
root_cause: competing_tab_selection_paths
resolution_type: narrow_runtime_hook
related_components:
  - "WCLGSearchTabBarOverlay"
  - "UITabBarController"
  - "WCGlass bottom search tab bar mode"
tags: [ios-27, wcglass, wechat-plugin, tab-bar, cold-start, black-screen, runtime-hook]
---

# WCGlass 底栏搜索框模式首次切换标签页黑屏

## 问题归属与范围

这是 WCGlass 3.0.1 的“底栏搜索框模式”在冷启动首次切换普通标签页时的兼容性问题。真机确认：即使不注入 WCLiquidGlass，WCGlass 仍会复现；相反，WCLiquidGlass 环形菜单直接切换微信原生 TabController 时不会复现。

本修复只接管 WCGlass `WCLGSearchTabBarOverlay` 的 `selectIndex:`。它不替换底栏搜索框、不改变菜单几何、材质、图标、触感或高亮样式，也不处理 WCGlass 的内部特殊选项。

## 已确认行为

WCGlass 的搜索框底栏在选择一个普通标签页时，会先更新自身的选择、高亮和菜单可见性，再沿自己的私有切换路径写入页面选中状态。冷启动阶段，目标页的懒加载、底栏自身回调和真实 TabController 的选中状态可能重叠，因此出现黑屏。

根因的准确私有调用栈无法从公开接口完整证明；“多重选中状态写入发生竞争”是由以下可重复对比得出的工程结论：

1. 环形菜单只调用真实 TabController 的 `setSelectedIndex:`，不出现黑屏；
2. 搜索框底栏经 WCGlass 原路径首次切换会出现黑屏；
3. 保留 WCGlass 的反馈、高亮和收起过程，但将实际页面切换收敛为一次 `setSelectedIndex:` 后，问题消失；
4. 移除 WCLiquidGlass 后仍复现，排除环形菜单及其图标读取逻辑。

## 最终修复

当且仅当以下条件同时满足时，兼容层接管一次选择：

- 运行时存在 `WCLGSearchTabBarOverlay` 和 `selectIndex:`；
- 当前索引是 0 至 3 的普通微信标签页；
- 能取得具有对应 `viewControllers` 的真实 TabController；
- 目标页不是当前已选中的页面；
- WCGlass 当前没有进行中的选择事务。

兼容层保持 WCGlass 原有的 `lightFeedback`、高亮刷新和菜单关闭动画，但实际页面只执行一次：

```objc
[tabController setSelectedIndex:index];
```

随后请求 overlay 布局，并在 0.26 秒后释放短暂的选择保护。若运行时对象尚未加载，安装最多延后重试 20 次，每次 0.5 秒；成功安装后不再重复 Hook。

以下情况一律继续调用 WCGlass 原实现：

- 重复点击当前标签页；
- 索引不在普通四个标签页范围内；
- 无法确认真实 TabController 或其控制器数量；
- WCGlass 已处于一次选择事务中；
- 执行兼容路径发生 Objective-C 异常。

这保证 WCGlass 的特殊入口和额外行为不会被误接管。

## 回归检查

| 场景 | 预期 |
|---|---|
| 冷启动，WCGlass 底栏搜索框模式，首次切换任意普通 Tab | 无黑屏，正常显示目标页 |
| 连续切换微信、通讯录、发现、我 | 每次只切换一次，无卡死或残留高亮 |
| 点击当前已选中的 Tab | 使用 WCGlass 原行为 |
| 从环形菜单切换 Tab | 保持原有稳定行为，不受该 Hook 影响 |
| 未加载 WCGlass | Hook 不安装，WCLiquidGlass 原功能不变 |
| WCGlass 内部特殊选项 | 使用 WCGlass 原行为 |

## 相关文档

- [WCGlass 在 iOS 27 从聊天页返回时的过期分区闪退](wcglass-ios-27-stale-section-return-crash.md)
- [WCLiquidGlass 插件开发规范](../architecture-patterns/wcliquidglass-plugin-development-specification.md)
