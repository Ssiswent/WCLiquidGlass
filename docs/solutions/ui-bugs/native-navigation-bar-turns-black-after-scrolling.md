---
title: "微信插件设置页滚动后原生导航栏变黑"
date: 2026-07-17
category: ui-bugs
module: WCLiquidGlass settings UI
problem_type: ui_bug
component: tooling
symptoms:
  - "插件设置页刚打开时导航栏正常，发生纵向滚动后顶部变成黑色"
  - "强制接管共享 UINavigationBar 后，导航栏从进入页面开始就保持黑色"
root_cause: logic_error
resolution_type: code_fix
severity: medium
tags: [ios, wechat-plugin, uikit, navigation-bar, table-view, theos]
---

# 微信插件设置页滚动后原生导航栏变黑

## Problem

WCLiquidGlass 的设置页使用 `UITableViewController` 和渐变 `backgroundView`。页面刚打开时顶部正常，但发生纵向滚动后，微信的原生导航栏会进入另一种显示状态并变黑，标题仍为黑色，导致视觉错误。最终修复已在 `1.3.11` 中由真机确认有效。

## Symptoms

- 只发生在插件自己的设置页内。
- 刚进入页面时正常，滚动后才出现。
- 主设置页和子设置页都可能受到相同背景处理方式的影响。
- 直接修改微信共享的 `UINavigationBar` 会把问题扩大成导航栏始终为黑色，并可能影响退出后的宿主页面。

## What Didn't Work

### 给不同导航状态配置相同的 appearance

曾尝试同时设置 `standardAppearance`、`scrollEdgeAppearance`、`compactAppearance` 和 `compactScrollEdgeAppearance`。这只是在覆盖导航栏的状态结果，没有处理页面底层透明背景，因此没有解决触发黑色背景的实际条件。

### 使用微信主题颜色强制构造导航栏

曾参考 WCPulse 为当前 `navigationItem` 构造 `UINavigationBarAppearance`。在当前主题组合下，导航栏最终颜色仍可能与插件的自定义渐变不一致。

### 直接接管共享 UINavigationBar

`1.3.10` 曾保存微信导航栏状态，再直接改写实际 `UINavigationBar` 的所有 appearance、背景色、透明度和 `barStyle`。这导致页面无论是否滚动都显示黑色，是一次错误回归。设置页不应修改宿主应用共享的导航栏对象。

## Solution

### 1. 完全交还系统原生导航栏

删除插件中的所有 `UINavigationBarAppearance`、`standardAppearance`、`scrollEdgeAppearance` 以及共享 `UINavigationBar` 改写逻辑。设置控制器只设置标题和按钮，不再设置导航栏颜色或滚动状态。

可以用下面的检查确认源码没有重新引入这类逻辑：

```sh
rg "UINavigationBarAppearance|standardAppearance|scrollEdgeAppearance|navigationBar\.backgroundColor" WCLiquidGlass.m
```

预期没有输出。

### 2. 为页面提供不透明的动态底色

渐变视图只负责视觉效果；`view` 和 `tableView` 本身必须有与渐变顶部一致的不透明动态颜色。当前实现位于 [`WCLiquidGlass.m`](../../../WCLiquidGlass.m)：

```objc
static UIColor *WCLiquidGlassBackdropBaseColor(void) {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        return WCLiquidGlassBackdropTopColor(traits);
    }];
}

static void WCLiquidGlassConfigureTableBackground(UITableViewController *controller) {
    UIColor *backgroundColor = WCLiquidGlassBackdropBaseColor();
    controller.view.backgroundColor = backgroundColor;
    controller.tableView.backgroundColor = backgroundColor;
    controller.tableView.backgroundView = [[WCLiquidGlassBackdropView alloc] init];
}
```

这段配置应用于三个设置控制器：

- `WCLiquidGlass`
- `WCLiquidGlassButtonEditorController`
- `WCLiquidGlassActionPickerController`

### 3. 保留渐变，但不要用透明色作为真实背景

错误写法：

```objc
self.tableView.backgroundColor = UIColor.clearColor;
self.tableView.backgroundView = [[WCLiquidGlassBackdropView alloc] init];
```

正确原则是：底层提供不透明动态颜色，上层 `backgroundView` 再绘制渐变。不要依赖渐变视图替代导航栏后方需要的真实背景。

## Why This Works

滚动会让系统导航栏在边缘状态与普通状态之间变化，并可能启用不透明或模糊背景。此前 `tableView.backgroundColor` 是透明色，导航栏后方缺少稳定的页面底色，最终透出了微信的黑色宿主背景。

现在 `view` 和 `tableView` 始终提供与插件渐变一致的不透明动态颜色。系统原生导航栏即使在滚动时改变显示状态，后方仍是正确的页面背景；插件不需要知道或干预导航栏当前使用哪一种 appearance。

对照本地二进制得到的实现差异：LiquidUI 1.33 的 `LUISettingsPageController` 同样继承 `UITableViewController`，会为 `view` 和 `tableView` 设置动态背景色，但不配置 `UINavigationBarAppearance`。这比强制复制宿主导航栏状态更适合作为微信插件设置页的实现方式。

## Prevention

- 使用系统导航控制器承载插件设置页时，默认不修改共享 `UINavigationBar`。
- `UITableViewController` 使用自定义 `backgroundView` 时，同时给 `view` 和 `tableView.backgroundColor` 设置不透明的动态底色。
- 视觉渐变、模糊或 Liquid Glass 效果应是装饰层，不能成为唯一背景层。
- 导航栏问题必须分别验证：首次进入、向下滚动、回到顶部、下拉回弹、进入子设置页、返回主设置页、退出插件页面。
- 如果问题只在滚动后出现，先检查透明背景和系统状态切换，不要先通过改写所有 appearance 压制症状。
- 每次构建后检查最终二进制，确保没有意外重新引入共享导航栏修改：

```sh
strings .theos/obj/WCLiquidGlass.dylib | rg "standardAppearance|scrollEdgeAppearance|wc_applyScopedNavigationAppearance"
```

预期没有输出。

## Related Issues

- 修复源码：[`WCLiquidGlass.m`](../../../WCLiquidGlass.m)
- 生效版本：[`control`](../../../control) 中的 `1.3.11`
- 对照插件：WCPulse 1.6-3、LiquidUI 1.33
