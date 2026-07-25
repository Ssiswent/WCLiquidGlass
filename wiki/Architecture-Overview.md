# Architecture Overview

WCLiquidGlass 是单个 dylib，被注入微信进程后在宿主 UI 之上运行一层完全独立的覆盖窗口，并通过 Objective-C runtime 调用微信自身的私有方法来执行动作。它不修改微信的数据源、导航栈或视图层级（唯一例外是 iOS 27 兼容防护中对越界 section 的只读拦截）。

## 模块划分

| 文件 | 职责 |
| --- | --- |
| `Tweak.xm` | `%ctor` 引导、Logos hook、`WCPluginsMgr` 注册、WCGlass 返回防护、语音转述写入深度追踪 |
| `WCLiquidGlassMenu.m` | 布局算法、玻璃效果、图标解析、动作能力检测与执行、orb 视图、聊天工具栏、HostView/Window/Manager |
| `WCLiquidGlassPreferences.m` | 动作目录、微信 asset 候选名、`NSUserDefaults` 持久化、迁移 |
| `WCLiquidGlass.m` | 设置页、按钮编辑页、动作选择页、崩溃日志页 |
| `WCLiquidGlassCrashLogger.m` | 未捕获异常处理、事件环形记录、PLCrashReporter 集成、日志文件管理 |
| `WCLiquidGlassIconAssets.c` | 由渲染脚本生成的 PNG 字节数组 |

## 启动序列

```mermaid
sequenceDiagram
    participant Loader as "MobileSubstrate"
    participant Ctor as "%ctor"
    participant Logger as "WCLiquidGlassCrashLogger"
    participant Prefs as "WCLiquidGlassPreferences"
    participant Guard as "WCGlass 返回防护"
    participant Manager as "WCLiquidGlassManager"
    participant Plugins as "WCPluginsMgr"

    Loader->>Ctor: 加载 dylib
    Ctor->>Ctor: 校验 bundleIdentifier
    Ctor->>Logger: start
    Ctor->>Prefs: registerDefaults
    Ctor->>Guard: 主队列安装 hook（可重试 10 次）
    Ctor->>Manager: start
    Ctor->>Plugins: registerControllerWithTitle:version:controller:
    Plugins-->>Ctor: 失败则每秒重试，最多 15 次
```

## 运行时对象图

```mermaid
flowchart TD
    M["WCLiquidGlassManager 单例"] --> W["WCLiquidGlassWindow"]
    W --> HC["WCLiquidGlassHostController"]
    HC --> HV["WCLiquidGlassHostView"]
    HV --> GC["glassContainer: UIVisualEffectView"]
    GC --> AO["anchorOrb: WCLiquidGlassOrbView"]
    GC --> OO["optionOrbs: WCLiquidGlassOrbView 数组"]
    HV --> CT["WCLiquidGlassChatToolbarView"]
    HV --> DC["dismissControl 背景关闭区"]
    HV --> P["WCLiquidGlassPreferences.buttonItems"]
    HV --> C["WCLiquidGlassCanPerformAction 过滤"]
```

- `WCLiquidGlassManager` 是唯一入口，负责窗口生命周期、偏好变化重载与前后台响应。
- `WCLiquidGlassHostView` 承载所有交互，`hitTest:` 只在工具栏、orb 或展开态背景处返回视图。
- 详见 [WCLiquidGlassManager and Window Layer](WCLiquidGlassManager-and-Window-Layer)。

## 动作派发链

```mermaid
flowchart LR
    A["用户选中 orb 或工具栏按钮"] --> B["WCLiquidGlassPerformAction"]
    B --> C{"特殊路由?"}
    C -->|"设置/插件列表/语音转述/斗图助手"| D["专用处理"]
    C -->|"其他"| E["WCLiquidGlassSelectorsForAction"]
    E --> F["WCLiquidGlassActionTarget 搜索响应者"]
    F --> G{"找到目标?"}
    G -->|"是"| H["objc_msgSend 调用（@try 包裹）"]
    G -->|"否"| I["回退：按类名 push 控制器"]
    I --> J{"仍失败?"}
    J -->|"是"| K["中文错误提示 UIAlertController"]
```

完整规则见 [Page-Aware Action Filtering and Execution](Page-Aware-Action-Filtering-and-Execution)。

## 玻璃效果的降级策略

`WCLiquidGlassMakeEffect()` 优先使用运行时存在的 `UIGlassEffect`，否则回退 `UIBlurEffect`；`WCLiquidGlassMakeContainerEffect()` 在存在 `UIGlassContainerEffect` 时用 8 pt spacing 让相邻 orb 融合：

```objc
static UIVisualEffect *WCLiquidGlassMakeEffect(void) {
    Class glassClass = NSClassFromString(@"UIGlassEffect");
    SEL factorySelector = NSSelectorFromString(@"effectWithStyle:");
    if (glassClass != Nil && [glassClass respondsToSelector:factorySelector]) { ... }
    ...
}
```

因此在 iOS 16–25 上界面仍然可用，只是没有 Liquid Glass 融合效果。

## 设计约束

- 覆盖窗口不能成为 key window，不吞掉微信触摸。
- 所有微信私有调用都要先 `NSClassFromString` / `respondsToSelector:`，再用 `@try/@catch` 包裹。
- 能力检测阶段绝不执行动作，只判断目标是否存在。
- 兼容性失败只隐藏单个动作或弹出提示，不允许扩大成崩溃。

这些约束的完整表述见 [Plugin Development Specification](Plugin-Development-Specification)。

## 相关页面

- [Getting Started and Build System](Getting-Started-and-Build-System)
- [WeChat Runtime Hooks](WeChat-Runtime-Hooks)
- [iOS 27 Compatibility Guard](iOS-27-Compatibility-Guard)
- [Glossary](Glossary)
