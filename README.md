# WCLiquidGlass

独立的微信 Liquid Glass 全局环形菜单插件。

## 功能

- 使用不抢焦点的透明 `UIWindow`，在微信任意界面显示可拖动边缘入口。
- 使用 `UIGlassContainerEffect` 组合多个 `UIGlassEffect` 圆形按钮。
- iOS 16–25 自动降级为 `UIBlurEffect`。
- 支持 53/60/66pt 圆形按钮、弧形扇出、1.5 倍选中缩放和弹簧动画。
- 使用渐变背景、原生玻璃卡片、标准导航栏与 iOS 26 Liquid Glass 按钮构建设置界面，旧系统自动降级。
- 支持新增、删除、排序和隐藏按钮，并可为每个槽位选择标签页、微信入口或聊天工具动作。
- 每次展开时按当前页面的实际能力过滤动作，不支持的按钮会暂时隐藏，进入支持页面后自动恢复。
- 可在聊天输入区顶部显示原生玻璃工具栏，复用“按钮与动作”的配置并随多行输入、引用内容和键盘转场平滑跟随。
- 收起状态固定使用微信“插件”猫咪图标，展开时显示关闭图标。
- 支持点击展开、长按滑动选择，以及拖动入口后自动吸附左右边缘。
- 提供可开关的 WCGlass iOS 27 兼容修复：在液态分组的横向胶囊或全屏分组场景下，避免聊天页键盘弹出且输入框非空时返回对话列表闪退；开关切换后立即生效。
- 提供两级崩溃诊断：默认低干扰采集 Objective-C 异常，可选完整原生崩溃采集；日志可在设置页查看、删除和系统分享。
- 诊断日志保存在微信沙盒 `Documents/WCLiquidGlass/Diagnostics/Crashes`，不主动记录聊天内容。
- 通过微信的 `WCPluginsMgr` 注册到插件列表，并传入设置控制器的类名字符串。

## 架构

插件以 dylib 形式注入微信进程：`%ctor` 完成初始化，`WCLiquidGlassManager` 单例在微信之上叠加一层不抢焦点的透明 `UIWindow` 来承载环形菜单和聊天工具栏，所有按钮动作都通过 Objective-C 运行时反射调用微信自身的方法，插件本身不实现任何微信业务逻辑。

### 启动与注入

`%ctor` 先确认宿主是微信（`com.tencent.xin`），随后同步启动崩溃日志与默认配置，再把建窗、装 hook、注册插件页的工作放到主线程执行；`WCPluginsMgr` 与 UIKit 方法在启动早期可能尚未就绪，因此两处注册/挂钩都带定时重试。微信自有类用 Logos `%hook` 静态挂钩，UIKit 与对话列表相关方法则用 `MSHookMessageEx` 在开关打开时动态挂钩。

```mermaid
flowchart TD
  L["dyld 加载 WCLiquidGlass.dylib"] --> C["%ctor：校验 bundleId 为 com.tencent.xin"]
  C --> CL["WCLiquidGlassCrashLogger start：接管未捕获异常，可选启用完整原生崩溃采集"]
  C --> PD["WCLiquidGlassPreferences registerDefaults：写入默认按钮与开关"]
  C --> OB["注册通知观察：键盘显隐、App 激活、兼容开关变更"]
  C --> MQ["dispatch_async 到主线程"]
  MQ --> HK["MSHookMessageEx 安装 iOS 27 兼容 hooks，类未就绪时最多重试 10 次"]
  MQ --> MG["WCLiquidGlassManager start：建立覆盖层窗口并加载配置"]
  MQ --> RG["向 WCPluginsMgr 注册设置页，未就绪时最多重试 15 次"]
  HOOKS["Logos %hook：MMInputToolView / BaseMsgContentViewController / MMTextView / MMGrowTextView"] -. "转发页面生命周期与输入事件" .-> MG
```

### 运行时结构

覆盖层窗口的 `windowLevel` 高于系统弹窗，`canBecomeKeyWindow` 返回 `NO`，`hitTest:` 命中窗口自身时返回 `nil`，因此除按钮区域外的触摸全部透传给微信，键盘焦点也不会被抢走。菜单内容与工具栏位置来自三条输入：本地配置、微信页面 hook 回调，以及键盘和输入框的实时几何信息。

```mermaid
flowchart TD
  subgraph OVERLAY["插件覆盖层"]
    MGR["WCLiquidGlassManager（单例）"] --> WIN["WCLiquidGlassWindow：windowLevel = Alert + 1，canBecomeKeyWindow = NO，hitTest 命中自身则透传"]
    WIN --> HC["WCLiquidGlassHostController"]
    HC --> HV["WCLiquidGlassHostView：手势、布局与动作入口"]
    HV --> ANCHOR["anchorOrb：可拖动的边缘入口，空闲后自动半隐藏"]
    HV --> OPTS["glassContainer + optionOrbs：弧形/S 曲线扇出的环形菜单"]
    HV --> BAR["WCLiquidGlassChatToolbarView：贴在聊天输入区上方的玻璃工具栏"]
  end
  SET["WCLiquidGlass 设置控制器"] --> PREF["WCLiquidGlassPreferences（NSUserDefaults）"]
  PREF -. "PreferencesDidChange 通知" .-> MGR
  MGR -. "reload" .-> HV
  WXHOOK["微信页面 hooks：聊天页进出、输入框 layoutSubviews"] -. "refresh / hide / resume 工具栏" .-> MGR
  KB["键盘通知 + 输入框 frame 反射探测"] -. "跟随多行输入、引用内容与键盘转场" .-> HV
  HV -. "崩溃与关键事件" .-> LOG["WCLiquidGlassCrashLogger：写入沙盒 Documents/WCLiquidGlass/Diagnostics/Crashes"]
```

### 一次点击如何变成微信操作

插件不持有微信的业务对象，而是在每次展开时沿“当前可见控制器 → 聊天输入区 → 标签页控制器”查找能响应目标 selector 的对象：查得到就显示按钮，选中后用 `objc_msgSend` 调用；查不到就先隐藏按钮，实在无法执行时给出中文提示，而不是硬调用导致闪退。

```mermaid
sequenceDiagram
  participant U as 用户
  participant HV as WCLiquidGlassHostView
  participant AC as WCLiquidGlassCanPerformAction
  participant RT as Objective-C 运行时反射
  participant WX as 微信页面对象
  U->>HV: 点击入口，或长按后滑动选择
  HV->>AC: 逐个校验已配置槽位在当前页面是否可用
  AC->>RT: 查找目标：可见控制器 / 聊天输入区 / MMTabController
  RT-->>AC: 返回可响应对象或 nil
  AC-->>HV: 只保留本页支持的按钮
  HV->>HV: 按弧形或 S 曲线扇出布局，滑动时磁吸高亮并触发振动反馈
  U->>HV: 抬手确认选中
  HV->>RT: WCLiquidGlassPerformAction 派发动作
  RT->>WX: objc_msgSend 调用微信方法，或 push 对应控制器
  WX-->>U: 打开朋友圈、扫一扫、语音输入等原生功能
  Note over HV,WX: 未找到可用实现时只弹中文提示，不强行调用
```

## WCGlass iOS 27 兼容修复

该修复针对 WCGlass 在 iOS 27 上的特定兼容性闪退。

WCGlass 的“横向胶囊分组”和“全屏分组”并非仅改变主页视觉样式：它们会接管对话列表的分组状态、section header、会话筛选、横向切换和全屏展示。也就是说，微信主页的同一个对话列表会在原始列表、分组筛选后的列表及切换中的展示状态之间重建或重排。

当聊天页处于“键盘已弹出且输入框非空”的状态并返回对话列表时，iOS 27 的 `UIIntelligenceSupport` 会在页面转场中继续遍历或恢复此前记录的列表语义节点。该节点可能来自 WCGlass 分组切换前或切换中的列表结构，并保留了 section `2` 的访问路径；但此时真实对话列表已经恢复为仅有 section `0` 和 `1` 的结构。

因此，`UIIntelligenceSupport` 会继续向真实列表请求 section `2` 的行数和几何位置，最终在 `UITableViewRowData` 中触发无效 section 断言并导致微信闪退。普通“液态分组”未进入横向或全屏的列表切换路径，因此不具备这一触发条件；相同配置在 iOS 26 上也未观察到该问题。

WCLiquidGlass 的兼容开关仅在这个风险窗口内，对目标对话列表的越界 section 返回自洽的“零行、零面积”结果，使过期的语义遍历安全结束，不再进入 UIKit 的断言路径。该保护不修改 WCGlass 的可见 UI、数据源或 section 数量，不延迟导航返回，也不强制收起键盘；开关切换后立即生效。

```mermaid
sequenceDiagram
  participant N as UINavigationController
  participant M as NewMainFrameViewController
  participant T as UITableView
  participant S as UIIntelligenceSupport
  N->>N: popViewControllerAnimated: 判定风险窗口（iOS 27 + WCGlass 已加载 + 键盘弹出 + 输入框非空）
  N->>M: 返回对话列表
  M->>M: viewWillAppear: 对该列表开启越界 section 保护
  S->>T: 按过期语义节点请求 section 2 的行数与位置
  T-->>S: 越界 section 返回 0 行与 CGRectZero，绕开断言
  M->>M: 转场完成或取消后关闭保护，并记录拦截次数到诊断日志
```

## 构建

```sh
export THEOS="$HOME/theos"
make clean package FINALPACKAGE=1
```

项目固定输出 rootless `iphoneos-arm64` 包，只包含 `arm64` 架构。
