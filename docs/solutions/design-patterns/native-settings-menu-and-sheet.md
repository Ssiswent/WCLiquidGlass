---
title: 原生层级 UIMenu 与二级 Page Sheet 设置入口
date: 2026-08-11
category: design-patterns
module: WCLiquidGlass settings
tags: [ios, uikit, uimenu, pagesheet, liquid-glass]
---

# 原生层级 UIMenu 与二级 Page Sheet 设置入口

## 基线

设置页的菜单样式配置只使用 UIKit 的系统呈现路径。Sheet 本身使用系统默认背景和转场；内容
section 的 cell 使用 `UITableViewStyleInsetGrouped` 的原生 `UIBackgroundConfiguration`、分组圆角和裁剪规则，不额外添加整页背景。

## 层级 UIMenu

`UIMenu` 没有独立的全局 presenter，必须挂在实际的 `UIButton` 或 `UIBarButtonItem` 上。
插件使用一个尺寸为 1×1 的透明代理按钮接收整行命中，菜单的 source view 保持很小，避免整行出现
Liquid Glass 点击动画；右侧保留系统 disclosure arrow：

```objc
UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
button.menu = [self makeMenuStyleHierarchyMenu];
button.showsMenuAsPrimaryAction = YES;
[cell.contentView addSubview:button];
// button 约束到 cell 中央的 1×1 点，使菜单水平居中；代理按钮的命中范围覆盖 cell，但 source view 不覆盖整行。
cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
```

菜单树只包含普通 `UIMenu`、`UIAction` 和选择状态：

```objc
UIAction *ring = [UIAction actionWithTitle:@"环形菜单" image:nil identifier:nil handler:handler];
ring.state = selected ? UIMenuElementStateOn : UIMenuElementStateOff;

UIMenu *menu = [UIMenu menuWithTitle:@"菜单样式"
                               image:nil
                          identifier:nil
                             options:0
                            children:@[styleMenu, dependentMenu]];
```

选择 `环形菜单` 时显示紧凑布局选项；选择 `液态面板` 时显示面板菜单大小和悬浮按钮轨迹。
动作只写入现有偏好设置，不改运行时菜单内容和页面同步逻辑。系统负责菜单的布局、状态标记、
动画与收起。

## 二级 Sheet

需要持续编辑多个相关选项时，使用普通 `UITableViewController` 包装在导航控制器中，再以
`UIModalPresentationPageSheet` 呈现：

```objc
UITableViewController *content = [[WCLiquidGlassMenuStyleSettingsController alloc] init];
UINavigationController *navigationController =
    [[UINavigationController alloc] initWithRootViewController:content];
navigationController.modalPresentationStyle = UIModalPresentationPageSheet;
[presenter presentViewController:navigationController animated:YES completion:nil];
```

页面使用 `UITableViewStyleInsetGrouped` 的系统默认背景和分组样式，section cell 使用系统的
`[UIBackgroundConfiguration listGroupedCellConfiguration]`，蓝色
`checkmark.circle.fill` 作为选中状态，选择后只刷新表格，不主动关闭 Sheet。右上角使用系统
`UIBarButtonItemStyleDone` 的“完成”按钮关闭页面。
除标准 Page Sheet 的 medium/large detent 与 grabber 外，不添加整页材质、背景或自定义转场控制。

## 原生 Action Sheet

恢复默认、配置导入导出、日志清理和开关说明等短操作使用
`UIAlertControllerStyleActionSheet`。`sourceView` 与 `sourceRect` 必须来自实际触发的 cell、按钮或
开关；不能把整张 table 作为锚点，也不能退回居中的 `UIAlertControllerStyleAlert`。这样系统才能在
iOS 26+ 自动提供正确的 Liquid Glass 气泡位置、动画和转场，并在 iPad/横屏时保持安全的 popover 锚点。

配置备份通过系统分享面板导出 JSON；配置恢复通过系统文件选择器读取，并在写入偏好前校验固定格式、版本
和已知键。无效文件只显示信息 Action Sheet，不改变当前配置。

## `.29` 原生分组背景修复与 `.30` 归因追踪

2026-08-11 真机验证确认：在 `.28` 及更早版本，菜单样式和液态功能 Sheet 的 cell 可能出现
`backgroundColor=clear`、`contentView.backgroundColor=nil`、`backgroundView=nil` 且
`backgroundConfiguration=nil`，所以原生 InsetGrouped section 看起来完全透明。测试 app 与插件的
两个 Sheet 控制器都使用同一套 `UITableViewStyleInsetGrouped` 和普通 `UITableViewCell` 创建路径，
因此问题不是 Sheet API 或 detent 的差异。

静态审计结果：插件没有 `UITableViewCell.appearance`、`UITableView.appearance` 或针对 Sheet 的背景清空 hook。
首页、按钮与动作、左滑引用/复读及其他普通二级设置页的 grouped cell 也统一使用
`[UIBackgroundConfiguration listGroupedCellConfiguration]`；`WCLiquidGlassStyleCardCell` 只是这个原生配置的兼容入口，
不再清空 `backgroundConfiguration` 或自绘卡片材质。
`WCLiquidGlassHomeCorners` 对 Sheet 表格也会因 role guard 直接跳过。已加载的外部圆角/主题类 dylib
仍可能通过私有 cell hook 改写配置；仓库历史文档确认外部“首页圆角”类 tweak 曾挂钩多个
`UITableViewCell` 子类，但现有代码和诊断日志不足以唯一归因到某个 dylib。

`.29` 保留 UIKit 原生样式，只在 `cellForRowAtIndexPath:`、`willDisplayCell:` 和
`viewDidLayoutSubviews` 重新应用 `[UIBackgroundConfiguration listGroupedCellConfiguration]`。
这不是自绘背景，已在真机上验证收起/展开和选择前后的 section 均与测试 app 一致。

为完成归因，`.30` 曾在 `UITableViewCell setBackgroundConfiguration:` 上增加只读追踪，并让手动
页面层级诊断输出每个 cell 的 `backgroundConfiguration` 状态。该临时追踪已经完成使命并移除；
当前代码不安装全局 setter hook，也不再把 `backgroundConfiguration` 诊断字段写入层级报告。

### `.30` 真机日志结论

2026-08-11 的收起→展开日志中，每个菜单样式 Sheet cell 都出现了同一对调用：先是
`arg=nil`，调用栈只有 `UIKitCore > CoreFoundation`；随后才是
`arg=UIBackgroundConfiguration`，调用栈经过 `WCGlass_3.0.4-5.dylib`、
`WCLiquidGlass.dylib` 和 `WCLiquidGlassConfigureSettingsCell`。因此当前证据不支持
`WCGlass_3.0.4-5.dylib` 或插件代码直接清空背景；清空动作发生在 UIKit 的 cell 配置/复用或
Sheet 转场中，插件随后重新应用原生分组配置。

同一份展开后的页面层级最终显示所有 Sheet cell 均有
`backgroundConfiguration=UIBackgroundConfiguration` 和 `_UISystemBackgroundView`，说明
`.30` 的持续原生恢复没有留下透明状态。这里不继续追踪私有 UIKit setter 或添加延时/自绘背景，
避免把系统的短暂中间态变成新的行为依赖；若后续再次出现可见透明状态，再以首个
`arg=nil` 栈作为回归证据（届时临时恢复追踪即可）。

当前的菜单样式、液态功能和崩溃日志导出三个 Page Sheet，以及普通 grouped 设置页，都使用同一套原生恢复路径；
恢复动作仅在 cell 创建、显示和布局时应用 `[UIBackgroundConfiguration listGroupedCellConfiguration]`，
不改变页面外层背景、Sheet 背景、detent 或转场。

## 插件设置中的切换

“菜单样式设置”偏好保存当前入口：

- `层级 UIMenu`：显示单元格右侧系统按钮的层级菜单。
- `二级 Sheet`：点击“菜单样式”单元格打开二级 Page Sheet。

这项偏好只改变设置入口，不改变环形菜单、液态面板、菜单大小、悬浮按钮轨迹或菜单动作的
实际运行逻辑。

## 紧凑布局完整性

环形菜单的紧凑布局固定包含四个选项：双层月牙、流动 S 弧、宽扇形、花瓣环簇。
新增或恢复选项时，枚举、标题数组、Sheet 行数、UIMenu 子项和运行时布局必须同时更新，避免
设置页只显示部分选项。

测试 app 的“液态功能 Sheet · 仅界面对照”只复刻标题、分组、开关和入口，不连接任何插件偏好，
用于在真实系统 Page Sheet 中比较布局；测试开关不会产生实际效果。
