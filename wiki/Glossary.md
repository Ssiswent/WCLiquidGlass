# Glossary

## 工程与打包

| 术语 | 含义 |
| --- | --- |
| Theos | 用于构建 iOS tweak 的开源构建系统，本项目通过 `$THEOS/makefiles/common.mk` 与 `tweak.mk` 构建 |
| Logos | Theos 的预处理语言，提供 `%hook`、`%orig`、`%ctor` 等指令，对应 `.xm` 源文件 |
| tweak | 注入到目标进程的 dylib，本项目注入微信（`com.tencent.xin`） |
| rootless | 不写入系统根目录的越狱方案，资源位于 `/var/jb`；由 `THEOS_PACKAGE_SCHEME = rootless` 指定 |
| rootful | 传统越狱布局，资源位于 `/Library`；运行时路径回退会同时尝试两者 |
| `%ctor` | dylib 加载时执行的构造函数，是插件的进程入口 |
| MSHookMessageEx | CydiaSubstrate 提供的运行时方法替换 API，用于按条件安装 iOS 27 兼容 hook |
| `control` | Debian 包元数据文件，`Version` 是版本的唯一来源 |
| `WCLIQUIDGLASS_VERSION` | 由 Makefile 从 `control` 抽取并注入的编译期宏 |

## 覆盖层

| 术语 | 含义 |
| --- | --- |
| overlay window | 覆盖在微信之上的 `WCLiquidGlassWindow`，level 为 `UIWindowLevelAlert + 1`，永不成为 key window |
| HostView | `WCLiquidGlassHostView`，承载锚点、动作 orb 与聊天工具栏的根视图 |
| 触摸穿透 | `hitTest:` 命中窗口自身时返回 `nil`，让触摸落到微信上 |
| anchor（锚点） | 常驻的收起态入口按钮，可拖动、吸边、闲置半隐藏 |
| orb | 环形菜单中的单个圆形按钮 |
| 磁吸选择 | 拖动时自动高亮距手指最近的 orb |
| 闲置半隐藏 | 静止 1.8 秒后锚点吸附到屏幕边缘只露出一半 |
| Liquid Glass | iOS 26 起的原生玻璃材质（`UIGlassEffect`），不可用时回退 `UIBlurEffect` |
| generation token | 用于作废过期延迟任务的计数标记 |

## 布局

| 术语 | 含义 |
| --- | --- |
| 双层月牙 | `DoubleCrescent`，内外两条同心弧，按钮数 ≥ 8 时启用 |
| 流动 S 弧 | `SCurve`，两段三次贝塞尔拼接、按弧长等距重采样 |
| 宽扇形 | `WideFan`，多层不同半径的扇形 |
| 花瓣环簇 | `PetalCluster`，环簇状排布 |
| 等弧长重采样 | 密集采样曲线并累计弧长，再按等长目标插值，保证按钮间距均匀 |
| 安全区适配 | 平移并在必要时缩小紧凑直径（最低约 40 pt），使所有 orb 落在安全区内 |
| 键盘边界 | 键盘顶部作为临时布局下边界，收起后恢复用户保存的位置 |

## 动作系统

| 术语 | 含义 |
| --- | --- |
| action identifier | 稳定的动作标识符，如 `plugins`、`search_records`；已发布后不得随意改名 |
| slot | 按钮槽位身份（`slot.<UUID>` 或固定值），决定排序与编辑身份，与 action 解耦 |
| 动作目录 | `WCLiquidGlassActionCatalog`，标题与 SF Symbol 兜底的唯一来源 |
| 能力检测 | `WCLiquidGlassCanPerformAction`，只做结构检查、无副作用 |
| 页面感知过滤 | 当前页面不支持的动作临时从菜单隐藏，不修改持久化配置 |
| 运行时投影 | 由持久配置按当前页面能力计算出的可见按钮集合 |
| 持续型切换动作 | 如语音转述，执行后菜单保持展开并显示激活描边 |
| selector 映射 | 动作到微信私有方法名的唯一映射，能力判断与执行共用 |
| asset 候选名 | 动作到微信主题素材名的候选列表，先试 `drawer_` 前缀 |

## 偏好与设置

| 术语 | 含义 |
| --- | --- |
| `WCLiquidGlassPreferencesDidChangeNotification` | 通用配置变更通知，Manager 与设置页共同监听 |
| `WCLiquidGlassWCGlassCompatibilityDidChangeNotification` | WCGlass 兼容开关专用通知 |
| 迁移 flag | 一次性布尔键，用于给旧用户补入新默认动作而不覆盖其排序 |
| `restoreDefaults` | 清除全部业务键与迁移 flag，并发出两个通知 |

## 诊断

| 术语 | 含义 |
| --- | --- |
| 基础级诊断 | 始终开启的 Objective-C 未捕获异常处理，链式调用上一个 handler |
| 完整级诊断 | 可选的 PLCrashReporter Mach 异常采集，需重启微信生效 |
| pending report | PLCrashReporter 在崩溃时写下、下次启动才转换为 `.crash` 的原始报告 |
| `WCLG_` 前缀 | vendored PLCrashReporter 的符号前缀，避免与宿主或其他插件的同名类冲突 |
| 生命周期事件 | 最近 30 条应用状态变化记录，随崩溃报告一并输出 |

## 兼容性

| 术语 | 含义 |
| --- | --- |
| WCGlass | 另一款微信插件，提供 `WCLGHomeGroups` 类；iOS 27 下与其共存时存在返回崩溃 |
| 行防护（row guard） | 返回主页面期间对越界 section 返回 0 / `CGRectZero` 的临时保护 |
| 越界 section | 请求的 section 索引 ≥ 当前 `numberOfSections` |
| dictation write depth | 线程局部计数，用于区分语音转述写入与手动键盘编辑 |

## 微信私有类型

| 名称 | 说明 |
| --- | --- |
| `WCPluginsMgr` | 微信插件管理器，通过 `registerControllerWithTitle:version:controller:` 注册设置入口 |
| `MMThemeManager` | 微信主题管理器，提供 `svgImageNamed:color:` |
| `MMServiceCenter` | 微信服务定位器，`getService:` 取得各类服务 |
| `BaseMsgContentViewController` | 聊天会话控制器基类 |
| `NewMainFrameViewController` | 微信主页面（会话列表）控制器 |
| `MMInputToolView` | 聊天输入工具条 |
| `MMGrowTextView` / `MMTextView` | 聊天输入文本控件 |

## 相关页面

- [Home](Home)
- [Architecture Overview](Architecture-Overview)
- [Plugin Development Specification](Plugin-Development-Specification)
