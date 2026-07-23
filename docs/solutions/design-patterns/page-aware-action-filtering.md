---
title: 按当前页面过滤不可用的环形菜单动作
date: 2026-07-17
category: design-patterns
module: WCLiquidGlass action routing
problem_type: design_pattern
component: tooling
severity: medium
applies_when:
  - 全局悬浮菜单包含只能在聊天页执行的动作时
  - 私有 API 的动作能力会随当前控制器和微信版本变化时
tags: [ios, wechat-plugin, runtime-capability, action-routing, context-menu]
---

# 按当前页面过滤不可用的环形菜单动作

## Context

全局悬浮菜单可以在微信任意页面展开，但照片、红包、转账、语音输入等动作只在拥有对应工具栏或控制器的页面可执行。点击后再提示“不支持”会让用户看到当前页面实际无法完成的选项。

## Guidance

用户保存的是稳定的按钮配置；菜单展示的是该配置在当前页面的临时投影。每次 `openMenu` 前重新加载，并依次过滤用户隐藏项、当前标签页动作和当前页面不支持的动作，不修改持久化配置。

能力检测必须无副作用：只在当前可见控制器、导航控制器、TabController、已知工具栏属性和当前视图树中查询 `respondsToSelector:`，不能通过试调用动作来判断。控制器入口则检查导航控制器与目标类是否存在。

selector 映射必须只有一个来源。能力检测和真正执行都读取同一个动作到 selector 的映射，避免新增动作时出现“显示规则认为可用，但执行规则找不到方法”的漂移。执行阶段仍保留失败处理，用于页面在菜单展开后切换或私有 API 初始化失败等竞态情况。

避免无意义扫描：空 selector 集合立即返回，非 TabBar 动作不提前查询 TabController。当前上限为少量环形按钮，因此按动作查找响应对象保持实现简单；若将来按钮数量显著增加，再考虑一次遍历构建能力集合。

## Why This Matters

页面能力驱动的过滤比按控制器类名维护白名单更能适应微信版本变化。配置不会丢失，用户进入支持页面后按钮会自动恢复，同时过滤逻辑不会误触发相机、支付或发送类动作。

## When to Apply

- 动作依赖聊天工具栏、输入控制器或特定页面对象时。
- 同一个插件入口在多个微信页面长期存在时。
- 私有类名不稳定，但动作 selector 仍可被运行时检测时。

## Examples

用户可以一直保留“红包”按钮；在非聊天页面展开菜单时该按钮不出现，进入聊天页面再次展开时自动恢复。对应能力检测、执行和菜单构建集中在 [WCLiquidGlassMenu.m](../../../WCLiquidGlassMenu.m)。

## Related

- [微信原生图标解析与回退](wechat-native-icon-resolution.md)
- [设置页的 Liquid Glass UI 结构](liquid-glass-settings-ui.md)
