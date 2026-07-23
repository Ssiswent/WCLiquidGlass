---
title: "WCGlass 在 iOS 27 从聊天页返回时的过期分区闪退"
date: 2026-07-22
category: integration-issues
module: WCLiquidGlass WCGlass compatibility guard
problem_type: integration_issue
component: tooling
severity: critical
symptoms:
  - "仅在 iOS 27 且 WCGlass 启用液态分组并选择横向胶囊分组或全屏分组时复现"
  - "聊天输入框已有文字且键盘弹出时，通过导航栏按钮或全屏手势返回对话列表会导致微信闪退"
  - "刚注入后的第一次返回可能正常，第二次及后续返回更容易稳定复现"
  - "崩溃日志显示 UIIntelligenceSupport 在 UITableViewRowData 中访问已经无效的 section 2"
root_cause: async_timing
resolution_type: code_fix
related_components:
  - "WCGlass liquid grouping"
  - "UIIntelligenceSupport"
  - "UITableViewRowData"
  - "NewMainFrameViewController"
tags: [ios-27, wcglass, wechat-plugin, ui-intelligence, uikit, table-view, stale-section, runtime-hook]
---

# WCGlass 在 iOS 27 从聊天页返回时的过期分区闪退

## 问题归属

这是 **WCGlass 在 iOS 27 上的兼容性问题**，不是 WCLiquidGlass 环形菜单自身导致的闪退。

移除 WCLiquidGlass 后问题仍然存在；移除 WCGlass 后问题完全消失。进一步缩小范围后确认：只启用 WCGlass 的“液态分组”不会复现，启用“横向胶囊分组”或“全屏分组”后才进入风险条件。这两种布局都会改变对话列表的分组与全屏切换行为。

WCLiquidGlass 从 `1.5.29-rc1` 开始提供窄范围兼容 Hook，在不修改 WCGlass 可见 UI、不关闭键盘、不延迟返回动画的前提下规避该问题。导航栏按钮返回和全屏手势返回均已真机验证。

`1.5.31-rc1` 补全了开关边界：返回入口不再使用无条件 Logos Hook，而是与另外三个保护 Hook 一起按兼容开关动态安装。因此关闭开关并重启微信后，兼容层不会改变 `UINavigationController` 的 IMP 或其他插件的 Hook 顺序。

`1.5.33-rc1` 补全首次返回的时序缺口。一次真实闪退已经记录到“Hook 安装成功”，但没有记录到 `row guard begin`，说明返回前的键盘、输入框或页面生命周期条件可能在首次转场中漏掉风险窗口。新版本保留原有短时保护，同时在公开 `UITableView` API 的越界入口增加第二道不变量保护：只有对象能够确认是 `NewMainFrameViewController` 的真实列表且 section 已经越界时，才返回空结果。

## 完整复现步骤

1. 使用 iOS 27、微信 8.0.75，并加载 WCGlass。
2. 在 WCGlass 中启用“液态分组”。
3. 选择“横向胶囊分组”或“全屏分组”。
4. 进入一个输入框已有文字的聊天页。
5. 保持键盘弹出。
6. 点击左上角返回按钮，或使用全屏返回手势回到对话列表。
7. 重复进入和返回。刚注入插件后的第一次返回可能正常，第二次及之后更容易稳定复现；一旦状态形成，微信重启后的第一次返回也可能闪退。

补充边界：

- iOS 26 使用相同步骤不能复现。
- iOS 系统“英语（美国）”键盘是实测中的例外，其他系统键盘和第三方键盘可以复现。
- 输入框为空、键盘未弹出，或 WCGlass 未启用上述两种布局时，不属于已确认风险窗口。

## 关键崩溃证据

诊断版本捕获到如下顺序：

```text
WCGlassReturn stale row guard hooks installed
WCGlassReturn row guard begin sections=2
WCGlassReturn blocked stale row request section=2 sections=2

Exception Name: NSInternalInconsistencyException
Reason: request for rect of invalid section (2)
NSAssertFile: UITableViewRowData.m
NSAssertLine: 2159
```

当前列表只有两个 section，有效索引是 `0` 和 `1`，但 iOS 27 的 `UIIntelligenceSupport` 在返回动画中仍然查询 section `2`。崩溃栈在 UIKit 与 `UIIntelligenceSupport` 之间反复出现，最终由 `UITableViewRowData` 对无效 section 的断言触发。

据此得到的因果链是：

1. WCGlass 的横向胶囊或全屏分组改变了对话列表的分区模型或视图层级。
2. 返回动画期间，iOS 27 的 `UIIntelligenceSupport` 仍持有或重新生成了指向 section `2` 的语义节点。
3. 此时真实列表已经稳定为两个 section，section `2` 已失效。
4. UIKit 先查询该 section 的行数，随后继续查询它的几何位置。
5. 几何查询进入 `UITableViewRowData` 后触发断言并终止进程。

“语义节点被跨转场保留”是根据首次可能正常、后续更易复现的行为作出的高概率推断；它不是对 `UIIntelligenceSupport` 私有实现的已验证结论。

## 走过的错误路径

### 隐藏无障碍元素

临时设置列表的 `accessibilityElementsHidden` 不能可靠清除已经存在的语义遍历状态，仍会出现过期 section 查询。

### 禁用 Writing Tools 或 Intelligence 相关功能

这类全局抑制没有命中 UIKit 的实际断言入口，范围过大且不能稳定解决问题。

### Hook 私有 `UITableViewRowData`

私有类和方法在当前运行时不可用或不稳定，并会把修复绑定到 UIKit 私有实现。应优先拦截收到错误请求的公开 `UITableView` API。

### 先收起键盘或延迟返回

延迟可以改变竞争窗口，但导航栏返回和手势返回都会明显变慢。恢复原生速度后闪退重新出现，说明这只是掩盖时序，不是修复错误访问。

### 使用页面快照遮挡转场

快照方案引入了黑屏、WCGlass 胶囊背景短暂消失、Liquid Glass 恢复延迟和底部搜索栏异常背景等严重 UI 回归。兼容修复不能替换 WCGlass 的实时视图层级。

### 冻结 section 数量

日志已经证明列表稳定报告 `sections=2`。问题不是数量变化，而是消费者仍在请求零基索引下无效的 section `2`。

### 只拦截 `numberOfRowsInSection:`

早期版本为越界 section 返回 `0` 后，`UIIntelligenceSupport` 仍继续调用 `rectForSection:2`，最终照样触发断言。空 section 必须在行数和几何两个维度上保持一致。

## 最终修复

在已确认的返回转场中，把过期 section 表示为一个“零行、零面积”的兼容占位：

- `numberOfRowsInSection:` 对越界 section 返回 `0`。
- `rectForSection:` 对同一个越界 section 返回 `CGRectZero`。

核心原则不是伪造新的 section，而是给语义遍历一个自洽的空结果，使它停止向 `UITableViewRowData` 继续请求无效几何。

```objc
if (WCLiquidGlassWCGlassRowGuardActive &&
    self == WCLiquidGlassWCGlassGuardedTableView) {
    NSInteger sectionCount = self.numberOfSections;
    if (section < 0 || section >= sectionCount) {
        return 0;
    }
}
return WCLiquidGlassOriginalTableViewNumberOfRows(self, selector, section);
```

```objc
if (WCLiquidGlassWCGlassRowGuardActive &&
    self == WCLiquidGlassWCGlassGuardedTableView) {
    NSInteger sectionCount = self.numberOfSections;
    if (section < 0 || section >= sectionCount) {
        return CGRectZero;
    }
}
return WCLiquidGlassOriginalTableViewRectForSection(self, selector, section);
```

目标列表从 `NewMainFrameViewController` 的 `getTableView` 获取，并以 `tableView` 作为兼容回退。只有结果确实是 `UITableView` 时才会成为被保护对象。

保护窗口从该控制器在一次已确认的风险返回中重新出现开始，在转场完成或取消时立即结束；没有转场协调器时，仅保留到下一次主线程 run loop。清理会同时移除激活标记、弱引用列表和 pending 状态。

## 为什么有效

`UIIntelligenceSupport` 对正在遍历的语义 section 需要一组自洽的表格响应：

- 零行表示没有子节点；
- 零矩形表示没有布局面积。

两者配合后，过期遍历会安全终止，不再让无效索引进入 `UITableViewRowData`。所有有效 section、其他 `UITableView`、非风险返回以及保护窗口之外的调用仍直接转发给 UIKit 原实现。

这比修改 `numberOfSections`、刷新 WCGlass 列表、创建快照、全局禁用系统能力或延迟导航更安全，因为它不改变 WCGlass 数据源和可见层级，也不影响原生返回速度。

### 首次返回的边界兜底

短时保护仍是首选路径，但不能把正确性完全建立在返回前的时序信号上。若某次首次返回没有进入短时保护，包装函数会先确认请求确实越界，再通过已缓存的列表弱引用、响应链或当前窗口控制器树确认对象身份。只有同时满足以下条件才会拦截：

- 兼容开关已开启；
- 系统为 iOS 27 或以上；
- WCGlass 的 `WCLGHomeGroups` 类存在；
- 对象是 `NewMainFrameViewController` 的真实 `UITableView`；
- section 小于零或不小于当前 section 数量。

首次命中会记录：

```text
WCGlassReturn fallback section guard section=2 sections=2
```

这条日志用于区分“短时保护正常命中”和“首次时序漏判后由边界保护接管”。有效 section 不会进入控制器树识别，也不会改变 WCGlass 的布局或数据。

## 范围与性能约束

- **系统约束**：仅 iOS 27 及以上安装兼容 Hook。
- **插件约束**：只有检测到 WCGlass 的 `WCLGHomeGroups` 类才安装。
- **页面约束**：只有从受影响的 `BaseMsgContentViewController` 返回才可能进入风险状态。
- **输入约束**：键盘必须可见且当前聊天输入框必须非空。
- **对象约束**：只有当前 `NewMainFrameViewController` 的真实列表会收到兼容返回。
- **索引约束**：只有越界 section 被拦截，有效索引始终调用原实现。
- **时间约束**：保护只覆盖一次返回转场，结束或取消后立即清理。
- **数据约束**：不修改 WCGlass 数据源，不刷新列表，不修改 section 数量，不替换页面快照。

## 可关闭的兼容开关

设置页“兼容性”分区提供“WCGlass iOS 27 兼容修复”开关，默认开启。

- 开启时：如果 Hook 尚未安装，会按系统与 WCGlass 条件同时安装返回入口、列表生命周期、行数和几何保护 Hook，并立即生效。
- 关闭时：通过独立兼容性通知立即清除 pending 和活动保护状态，已安装包装函数只会直接转发到原实现；不会触发菜单重建。
- 关闭后重启微信：包括 `UINavigationController` 返回入口在内的四个兼容 Hook 都不会安装，便于 WCGlass 作者修复源问题后进行严格 A/B 验证。

运行时不强行恢复已经替换的 IMP，因为动态 unhook 容易破坏其他插件的 Hook 链。使用“立即旁路 + 下次启动不安装”是更安全的关闭语义。安装重试同时使用单一 pending 标记合并，避免连续切换开关时生成并行重试链。

越界查询只累计行数与矩形请求次数，并在保护窗口结束时写入一条汇总日志。不要在 `UITableView` 全局热路径中为每次请求格式化字符串和加锁写日志。

## 真机回归矩阵

| 环境 | WCGlass 配置 | 聊天状态 | 返回方式 | 预期 |
|---|---|---|---|---|
| iOS 27 | 液态分组 + 横向胶囊 | 键盘显示、输入非空 | 导航按钮 | 原生速度返回，不闪退 |
| iOS 27 | 液态分组 + 横向胶囊 | 键盘显示、输入非空 | 手势完成 | 动画正常，不闪退 |
| iOS 27 | 液态分组 + 横向胶囊 | 键盘显示、输入非空 | 手势取消 | 留在聊天页，保护状态清理 |
| iOS 27 | 液态分组 + 全屏分组 | 键盘显示、输入非空 | 按钮和手势 | 均不闪退 |
| iOS 27 | 仅液态分组 | 任意 | 按钮和手势 | 原始行为，无可见影响 |
| iOS 27 | 受影响布局 | 键盘显示、输入为空 | 按钮和手势 | 不进入风险状态 |
| iOS 27 | 受影响布局 | 键盘隐藏、输入非空 | 按钮和手势 | 不进入风险状态 |
| iOS 27 | 未安装 WCGlass | 任意 | 任意 | 不安装 Hook |
| iOS 26 | 任意 | 任意 | 任意 | 不安装 Hook |
| iOS 27 | 受影响布局 | 连续多次进入和返回 | 按钮和手势 | 第二次及后续无状态残留 |
| iOS 27 | 受影响布局、兼容开关关闭 | 风险条件 | 按钮和手势 | 兼容层不介入，用于验证 WCGlass 后续原生修复 |

每次调整兼容层后，还必须检查 WCGlass 的主页分组胶囊、好友置顶卡片、底部搜索栏、Liquid Glass 背景和交互式返回进度，确保没有闪烁、背景消失、黑屏或快照残留。

## 相关文档

- [WCLiquidGlass 插件开发规范](../architecture-patterns/wcliquidglass-plugin-development-specification.md)
- [两级崩溃诊断系统](../architecture-patterns/two-level-crash-diagnostics.md)
- [Liquid Glass 设置页设计](../design-patterns/liquid-glass-settings-ui.md)
