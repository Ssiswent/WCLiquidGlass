---
title: "Mac 在线卡片被遗留几何动画再次缩窄"
date: 2026-07-29
category: ui-bugs
module: WCLiquidGlass home corners
problem_type: ui_bug
component: tooling
symptoms:
  - "Mac 在线卡片的 model frame 已是目标宽度，但屏幕仍会短暂变窄"
  - "卡片恢复正常后还会在后续列表布局中再次缩窄"
root_cause: async_timing
resolution_type: code_fix
severity: medium
tags: [ios, wechat-plugin, wcglass, uikit, core-animation, table-view, mac-online]
---

# Mac 在线卡片被遗留几何动画再次缩窄

## Problem

首页 section 0 的 Mac 在线卡片目标宽度为 370pt。WCGlass 的列表布局在动画事务中先写入较窄的原生 frame 后，即使 WCLiquidGlass 立即恢复正确的 model frame，屏幕上的卡片仍会先缩窄、恢复，并可能在一次异步 `reloadData` 后重复。

## Symptoms

- 目标 `frame` 保持为 `x=16, width=370`，但 presentation layer 一度显示更小宽度。
- `UITableView`、父视图和 transform 均正常，只有 Cell、`contentView` 与玻璃层的 presentation geometry 不一致。

## What Didn't Work

只用 `performWithoutAnimation:` 恢复 frame 不足以解决问题。它不会取消 WCGlass 已经提交到 Core Animation 的 `position` 和 `bounds` 动画，因此 presentation layer 仍会执行旧动画。

## Solution

在 [`WCLiquidGlassHomeCorners.m`](../../../WCLiquidGlassHomeCorners.m) 中，对 Mac 在线卡片的 `cell.layer`、`contentView.layer` 和玻璃层仅移除遗留的 `position` / `bounds` 属性动画；其他动画不受影响。

```objc
if (isMacOnlineCard) {
    WCLiquidGlassHomeCornerRemoveGeometryAnimations(cell.layer);
    WCLiquidGlassHomeCornerRemoveGeometryAnimations(cell.contentView.layer);
    WCLiquidGlassHomeCornerRemoveGeometryAnimations(state.glassOverlay.layer);
}
```

辅助函数会递归检查 `CAAnimationGroup`，只移除 key path 为 `position`、`position.*`、`bounds` 或 `bounds.*` 的动画。该修复已随 1.7.7 真机验证。

问题定位完成后，专用的 Mac 在线几何采样已在 1.7.8 删除；通用的崩溃和当前页面层级诊断保留。

## Why This Works

Core Animation 分别维护 model layer 与 presentation layer。恢复 model frame 不会回滚已经提交的几何动画；删除这些特定动画后，presentation layer 会立即采用正确的 model geometry。范围限制在 Mac 在线卡片的三层，也避免干扰 WCGlass 的页面切换、透明度、transform 或圆角动画。

## Prevention

- 遇到 model frame 正确而视觉 geometry 错误时，先同时检查 presentation layer 和动画 key path。
- 不要使用 `removeAllAnimations`：它会误伤不相关的视觉或转场动画。
- 临时诊断确认根因后应删除，避免后续运行产生无用采样和诊断文件。

## Related Issues

- 已发布修复：[1.7.7 更新记录](../../../CHANGELOG.md)
