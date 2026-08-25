# 原生液态面板悬浮按钮实现基线

本文档记录当前测试 App 已验证、并移植到插件液态面板路径的实现。它是后续修改
悬浮按钮或系统菜单前的行为基线；环形菜单不属于本文档范围。

## 唯一视图链路

液态面板只保留一条视图链路：

`WCLiquidGlassHostView` → `WCLiquidGlassNativeToolbar` → `UIBarButtonItem(menu:)` → `UIMenu`

不要再叠加自定义 `UIButton`、第二个透明命中层或独立的玻璃按钮。Toolbar 自己负责
命中和系统按压反馈，插件只同步菜单内容、位置和生命周期。

## 几何基线

- 正常位置只有一个计算入口：`wc_nativeToolbarVisibleFrameForLeft:`。
- 左侧正常位置的 `x` 为 `0`，右侧正常位置的 `x` 为 `bounds.width - diameter`。
- 半隐藏位置只把同一个按钮平移半个直径到屏幕外，不改变尺寸、透明度或图标。
- 点击半隐藏按钮恢复时复用正常 frame helper，并保留当前 `y`；不能跳到默认位置。
- 拖动松手时复用同一个 helper，只更新左右吸边和持久化的垂直位置。
- 拖动过程直接更新 Toolbar frame，`y` 受安全区限制；松手使用 0.58 秒、阻尼
  0.78 的系统弹簧动画。

## 交互生命周期

1. 点击 Toolbar 由系统 `UIMenu` 直接展开；不复制自定义菜单容器。
2. 点击正在半隐藏的按钮先恢复到同一正常吸边位置，再由 `UIBarButtonItem(menu:)`
   打开菜单。
3. 菜单关闭后或按钮无交互 0.5 秒，Toolbar 使用 0.28 秒平移进入半隐藏位置。
4. 拖动开始时读取 presentation layer 的当前 frame，移除进行中的动画，避免瞬移；
   拖动期间取消菜单关闭监测，松手完成吸边后重新开始空闲计时。
5. 菜单监测只用于判断系统菜单已打开并关闭，不参与菜单动画和按钮绘制。

## 修改边界

- 只修改 `WCLiquidGlassMenu.m` 中 native toolbar / native menu panel 路径时，必须
  保持 `menuStyle == Ring` 的 `anchorOrb`、`optionOrbs`、布局和动作代码不变。
- 不新增第二个按钮、透明遮罩或自定义命中代理；如需修复命中，优先修正
  `WCLiquidGlassNativeToolbar` 的现有 hit-test 链路。
- 不把安全区外边距重新加回正常 `x`；它会再次造成点击恢复和拖动吸边位置不一致。

## 验证清单

- 选择“液态面板”，确认屏幕上只有一个 Toolbar 按钮和一个系统菜单。
- 左右两侧分别测试：半隐藏点击恢复、正常状态点击、菜单关闭后 0.5 秒半隐藏。
- 从半隐藏状态直接拖动，确认接触瞬间不跳到默认位置，松手位置与点击恢复位置一致。
- 拖动过程中快速改变方向，确认没有跟随小圆点、重复按钮或透明遮罩。
- 选择“环形菜单”并重复基础操作，确认环形样式与布局未改变。

参考实现：

- 测试 App：`tools/LiquidGlassTransitionTest/LiquidGlassTransitionTest/LiquidPanelHostView.m`
- 插件实现：`WCLiquidGlassMenu.m` 的 `wc_nativeToolbar*` 和 `wc_*NativeMenu*` 方法
