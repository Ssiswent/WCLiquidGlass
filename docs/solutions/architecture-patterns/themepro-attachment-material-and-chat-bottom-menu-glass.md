# 素材仓附件素材与聊天底部菜单液态层

## 结论

素材仓（`德发素材仓.dylib`）的“附件素材”和“菜单素材”不是通过替换微信按钮、动作或控制器实现的，而是在微信原生视图完成布局后，修改背景层：

- `MMInputToolView` 是外层状态/生命周期入口；真正承载附件背景的视图是 `InputToolContainerView` 与 `SelectAttachmentView`。
- 正常输入栏（`InputToolViewBar`）不是附件背景宿主，不能因为它位于 `MMInputToolView` 内就一起替换，否则会改变输入框颜色和原生输入体验。
- `MMMenuContentView` 是消息长按菜单，使用另一套 `EnableMenuMaterial` / `SelectedMenuFolder` 配置。
- 附件功能单独读取 `EnableAttachmentMaterial` / `SelectedAttachmentFolder`。
- 两条路径都通过 `layoutSubviews` 生命周期反复收敛视图层级，因此菜单按钮、点击事件、原生尺寸和弹出关闭动画仍由微信负责。

## 二进制观察

从本地素材仓包的 arm64 slice 可以确认以下 Hook 目标：

1. `MMInputToolView`：检查附件面板状态并触发布局流程，但不应被当作正常输入栏的材质宿主。
2. `InputToolContainerView`：定位容器中的覆盖背景，隐藏原生背景，再建立一个带固定边距的背景视图并插入容器底部。
3. `SelectAttachmentView`：对真正显示的附件选择面板执行同类背景处理。
4. `MMMenuContentView`：独立处理消息长按菜单，不能把它和聊天底部附件面板混用。

实现中还出现了 `backgroundView`、`effectSubview`、`m_backgroundView`、`_menuItemContainerView` 等背景/容器标识，以及 `setBackgroundColor:`、`setEffect:`、`setImage:`、`insertSubview:atIndex:` 等调用。这说明素材仓的核心是“隐藏或替换覆盖背景 + 将素材视图放在内容后面”，而不是重建菜单。

## WCLiquidGlass 的独立实现

`WCLiquidGlassChatBottomMenu.m` 复用了这个稳定的生命周期边界，但完全不依赖素材仓：

- 只 Hook `InputToolContainerView` 与 `SelectAttachmentView` 的 `layoutSubviews`。
- 优先使用可见的 `SelectAttachmentView`，避免外层容器和内层面板叠加两层材质。
- 仅清除附件宿主背景以及覆盖整个面板的原生 `backgroundView` / `effectSubview` / 图片背景；正常 `InputToolViewBar`、按钮和内容子视图不改动。
- 按素材仓的原生槽位方式，插入一个独立 tag 的不可交互 `UIImageView` 到 `SelectAttachmentView` 的索引 0，或插入到 `InputToolContainerView` 原生背景图片的下方；Liquid Glass 作为该背景槽的子层，效果来自 WCLiquidGlass 的全局“透明 / 平衡 / 色调”设置。
- 背景槽本身保持透明，避免额外的纯色层覆盖系统玻璃或改变输入/附件内容的颜色；Liquid Glass 作为受保护的子层直接提供材质。
- 关闭开关或视图离开窗口时恢复已捕获的原生颜色、图片和 effect。
- 新增“聊天底部菜单液态”开关，默认开启；与“消息长按菜单液态”互相独立。

这样可以保留微信原生附件菜单的内容、按钮读取方式、布局、触摸和关闭动画，同时避免读取素材仓偏好、素材目录或依赖其运行时。
