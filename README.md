# WCLiquidGlass

独立的微信 Liquid Glass 全局环形菜单插件，不依赖 LiquidUI。

## 功能

- 使用不抢焦点的透明 `UIWindow`，在微信任意界面显示可拖动边缘入口。
- 使用 `UIGlassContainerEffect` 组合多个 `UIGlassEffect` 圆形按钮。
- iOS 16–25 自动降级为 `UIBlurEffect`。
- 复刻 53/60/66pt 圆形按钮、弧形扇出、1.5 倍选中缩放和弹簧动画。
- 使用渐变背景、原生玻璃卡片、标准导航栏与 iOS 26 Liquid Glass 按钮构建设置界面，旧系统自动降级。
- 支持新增、删除、排序和隐藏按钮，并可为每个槽位选择标签页、微信入口或聊天工具动作。
- 每次展开时按当前页面的实际能力过滤动作，不支持的按钮会暂时隐藏，进入支持页面后自动恢复。
- 收起状态固定使用微信“插件”猫咪图标，展开时显示关闭图标。
- 支持点击展开、长按滑动选择，以及拖动入口后自动吸附左右边缘。
- 提供两级崩溃诊断：默认低干扰采集 Objective-C 异常，可选完整原生崩溃采集；日志可在设置页查看、删除和系统分享。
- 诊断日志保存在微信沙盒 `Documents/WCLiquidGlass/Diagnostics/Crashes`，不主动记录聊天内容。
- 通过微信的 `WCPluginsMgr` 注册到插件列表，并传入设置控制器的类名字符串。

## 构建

```sh
export THEOS="$HOME/theos"
make clean package FINALPACKAGE=1
```

项目固定输出 rootless `iphoneos-arm64` 包，只包含 `arm64` 架构。
