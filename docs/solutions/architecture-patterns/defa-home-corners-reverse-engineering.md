# 德发首页圆角 3.0.0：圆角与布局实现笔记

## 范围与证据

本笔记分析本地 `德发首页圆角.deb` 中的 `微信首页圆角.dylib`，版本为 `3.0.0`，仅用于兼容性学习；不复制其二进制代码或资源。

已确认的实现证据：

1. Dylib 同时包含 `arm64` 与 `arm64e` 架构，并注入 `com.tencent.xin` 的 WeChat 进程。
2. 它通过 `MSHookMessageEx` 对微信控制器、`UITableViewCell`、`MMMultiMenuTableViewCell`、`MMTableViewCell`、`MainFrameSectionFoldView`、`UITableViewCellContentView` 等对象挂钩。
3. 关键偏好键包括 `EnableHomeCellCorner`、`HomeCellIndent`、`HomeCellCornerRadius`、`HomeCellTopPinnedOffset`、`HomeCellTopNormalOffset`、`HomeCellVisiblePages`。

## 它的核心策略

### 1. 在原生 `setFrame:` 时修正 Cell 几何

最关键的 hook 是 `UITableViewCell setFrame:`。它不是等 Cell 已经布局完成后再改 `cell.frame`，而是在微信将行框架交给 UIKit 时就替换为目标框架：

```text
目标 x = 原始 x + 左右缩进
目标宽 = 原始宽 - 2 × 左右缩进
```

随后仍由原始 `setFrame:` 执行。这样 UIKit 后续的 `layoutSubviews`、内容视图布局、命中测试与动画坐标会共同基于新尺寸计算。

这解释了它在设置缩进/间距后仍能保持点击位置正确：它没有在显示完成后把 Cell 移到一个与 TableView 内部布局脱节的位置。

### 2. 用遮罩表达首、中、尾圆角

它在拿到 Cell 所属 table 与 index path 后，会读取当前 section 的行数，区分：

| 位置 | 遮罩角 |
| --- | --- |
| 单行 | 四角 |
| 首行 | 左上、右上 |
| 中间行 | 无圆角 |
| 尾行 | 左下、右下 |

然后以 Cell 的 `bounds` 生成 `UIBezierPath`，放入 `CAShapeLayer`，赋给 `cell.layer.mask`。半径会被限制为高度的一半以内，防止极矮行变形。

这是一种真正的连续卡片实现：首尾行各自只裁切应该裁切的两个角，中间行保持矩形，因此相邻行视觉上组成同一张卡片；它不是给每行都设置四角圆角。

### 3. 让“间距”进入原生行高/框架流程

该插件同时挂钩主页、通讯录、发现、我的等控制器的 `tableView:heightForRowAtIndexPath:`，并挂钩 header 的高度与视图。结合 `setFrame:` 的时点，间距和缩进都发生在原生 TableView 的布局链中，而不是修改 `contentSize` 或在滚动结束后补偿。

对 WCLiquidGlass 的启示：

1. 行高扩展承担间距的占位。
2. `setFrame:` 在原生布局阶段把 Cell 收缩到卡片尺寸。
3. 文字、图标和触摸区域随 UIKit 的后续布局同步更新。
4. 不应在 `layoutSubviews` 结束后再次挪动 Cell，避免视觉位置与点击位置不一致。

### 4. 背景稳定性靠“拦截原生重设”而不是只清一次

该插件专门挂钩 `MMMultiMenuTableViewCell setBackgroundColor:` 和 `traitCollectionDidChange:`，还会处理系统背景视图。这说明微信会在复用、滚动、主题变化或页面回退后重新写入 Cell 背景。

因此只在首次创建时清空背景不足以稳定视觉效果；需要在原生写入背景的入口处拦截，统一替换为插件希望的背景，再保持自定义材质层位于内容之下。

### 5. “我”页的文字居中不是靠事后平移

二进制中可见它挂钩 `WCTableViewCellLeftConfig` 的 `setTitle:`、`titleCenter`、`setTitleCenter:`、`setTitleColor:`、`titleNumberOfLines` 与 `setTitleNumberOfLines:`。

这表明它倾向于在微信配置 Cell 左侧内容时修正对齐参数，而不是等图标和文字已布局完成后分别改 frame。这样内容的垂直中心、动态副标题、附件箭头和 Cell 高度变化可以一起参与原生计算。

## WCLiquidGlass 的采用原则

1. 卡片框架只在 `setFrame:` 的原生时点收缩；后续渲染只更新圆角、材质和背景，不重新位移 Cell。
2. 主页会话区保留用户设置的圆角和间距；其他主标签页固定为 26pt 圆角、8pt 间距。
3. 顶部特殊行（例如 Mac 微信登录）作为独立卡片，固定 26pt 圆角，并清理其内部按钮容器的原生不透明底色。
4. 连续卡片使用首/中/尾角遮罩，不给中间项套四角圆角。
5. 对会在滚动中复写的 `MMMultiMenuTableViewCell` 背景进行入口级拦截，避免“初始透明、滚动后变灰白、朋友圈单独闪烁”的双状态问题。
6. 发现页禁用高亮态的放大/重叠反馈，但不拦截正常的 `didSelect` 导航。

## 回归检查清单

1. 调整主页间距后，点击会话、左右切换分组手势均与视觉位置一致。
2. “我”页每一行的图标、主标题、副标题和箭头在卡片垂直中心附近对齐。
3. Mac 微信登录行在首屏、滚动、返回后始终是 26pt 独立玻璃卡片。
4. 发现页朋友圈在点击、返回和上下滚动时不出现缩放、重影或背景闪烁。
5. 深色、浅色和三档“液态效果”切换时，背景只改变材质强度，不出现原生白底回写。
