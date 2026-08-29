# WCLiquidGlass 2.1.10 → 2.1.11 变更记录

## 目的与范围

这份记录用于新对话接续开发时快速恢复上下文，描述从已发布的 `v2.1.10` 到当前 2.1.11 源码状态的实际变化。重点是两件事：

1. 移除旧的“通知圆角与液态”功能及其设置入口。
2. 保留“未读消息提示液态”，并处理它与 WCGlass 插件同时改写同一视图时的竞争；当前默认关闭该功能，以避免与 WCGlass 的实现叠加。

文档依据是 Git 的提交、文件差异和当前工作树，而不是根据版本号推测功能。当前核对结果：

| 项目 | 结果 |
| --- | --- |
| `v2.1.10` | tag 指向 `2996bd1`（2026-08-25），提交信息为 `fix: restore native menu auto-hide` |
| 当前 2.1.11 源码 | `47d390c`（2026-08-27），提交信息为 `release: remove WCGlass notification banner hooks` |
| Debian 控制文件 | `control` 的 `Version` 为 `2.1.11` |
| `v2.1.11` Git tag | 当前仓库没有该 tag；不要把“2.1.11”误写成已打 tag 的发布版本 |
| 当前分支 | `fix/crash-capture-coverage`；2.1.11 代码在此分支，不在 `origin/main` 的旧提交上 |

## 一句话结论

2.1.11 不是新增一个通知液态 UI，而是收缩功能边界：删除独立的通知圆角/液态页面和全部对应偏好项，继续使用未读消息提示适配，但把默认值固定为关闭，并在该适配开启时主动清理 WCGlass 注入的背景和 effect 子视图，再以一次受控的下一轮主线程刷新收敛状态。

## 相对 2.1.10 的精确差异

### 构建图与启动注册

| 文件 | 变化 | 影响 |
| --- | --- | --- |
| `Makefile` | 从 `WCLiquidGlass_FILES` 移除 `WCLiquidGlassMessageNotification.m` 与 `WCLiquidGlassMessageNotificationSettings.m` | 两个旧实现不再参与 Theos 编译和链接 |
| `Tweak.xm` | 移除 `WCLiquidGlassMessageNotification.h` 的 import；移除 `WCLiquidGlassInstallMessageNotificationHooks()` 注册调用 | 插件启动时不再安装通知圆角/液态 hook |
| `WCLiquidGlass.m` | 移除 `WCLiquidGlassMessageNotificationSettings.h` 的 import | 设置页不再依赖已删除的通知设置控制器 |
| `control` | `Version: 2.1.10` → `Version: 2.1.11` | Debian 包元数据进入 2.1.11 |

删除的源文件共四个：

- `WCLiquidGlassMessageNotification.h`（15 行）
- `WCLiquidGlassMessageNotification.m`（333 行）
- `WCLiquidGlassMessageNotificationSettings.h`（8 行）
- `WCLiquidGlassMessageNotificationSettings.m`（246 行）

这部分的总差异是 71 行新增、688 行删除；删除量大是因为完整移除了旧功能实现和设置页，而不是把实现隐藏起来继续运行。

### 设置主页的变化

`WCLiquidGlass.m` 的设置表格从第二个 section 的 7 行改为 6 行：

| 2.1.10 | 2.1.11 |
| --- | --- |
| 通讯录索引液态 | 通讯录索引液态 |
| 未读消息提示液态 | 未读消息提示液态 |
| 聊天输入工具栏 | 聊天输入工具栏 |
| 通知圆角与液态 | （删除） |
| 首页圆角与液态 | 首页圆角与液态 |

同时发生了三处配套调整：

- section footer 从“通知圆角与首页圆角可进入子页面继续调整”改为只描述“首页圆角可进入子页面继续调整”。
- `indexPath.row == 5` 现在直接打开首页圆角控制器；旧的 row 5 推送通知设置、row 6 推送首页设置的分支被删除。
- 用户在设置主页看不到已经不再安装的通知圆角/液态入口，避免出现点击后无功能或崩溃的死链接。

### 偏好项、默认值和迁移

`WCLiquidGlassPreferences.h/.m` 删除了以下四组 API 和 key：

| 删除项 | 用途（2.1.10） |
| --- | --- |
| `messageNotificationGlassEnabled` | 通知视图液态总开关 |
| `messageNotificationCornerRadius` | 通知视图圆角半径 |
| `messageNotificationPadding` | 通知视图内边距 |
| `messageNotificationGlassAppearance` | 通知视图的 clear/balanced/tinted 外观 |

配套删除包括：

- `registerDefaults` 中这四个 key 的默认注册；
- 对通知外观旧值的读取和迁移；
- getter/setter 声明和实现；
- 对应的偏好变更通知路径。

没有被删除的是 `unreadMessageTipGlassEnabled`。它仍然是独立开关，并且 2.1.11 的默认值为 `NO`。因此“禁用 WCGlass 的未读消息提示叠加”不是删除未读消息提示适配，而是让本插件默认不主动打开它；用户或其他代码显式开启时，下面的共存清理逻辑仍然生效。

### 未读消息提示与 WCGlass 的共存处理

`WCLiquidGlassUnreadMessageTip.m` 是 2.1.11 的主要保留/增强部分。变化可以按执行顺序理解：

1. **识别视图来源**：新增 `class_getImageName(view.class)` 检查，类所在镜像路径包含 `/WCGlass_` 时认为该视图由 WCGlass 创建。
2. **清理竞争层**：递归扫描未读消息提示视图，删除 WCGlass 创建的子视图；插件自己维护的 `glassView` 会被排除，递归深度限制为 6 层。
3. **扩大背景视图识别**：原有 `bgButton`、`backgroundView`、`backgroundImageView`、`backgroundEffectView` 之外，增加 `wclgGlassView` 与 `_wclgGlassView` 两个命名候选。
4. **收集 effect 视图**：递归收集未读提示内部的 `UIVisualEffectView`，同样排除插件自己的 glass view，避免只压制最外层而留下 WCGlass 的内部材质层。
5. **更新前先清理**：每次 `WCLiquidGlassUnreadMessageTipUpdate` 先移除 WCGlass 子视图，然后才根据插件偏好恢复或压制背景。
6. **处理同一布局周期内的回灌**：在 hook 的 `layoutSubviews` 完成后，使用 `deferredUpdateScheduled` 只排队一次主线程异步更新；通过 weak view 避免延长视图生命周期。这样可以覆盖 WCGlass 在本轮 layout 后重新插入背景的情况，不使用持续 timer，也不添加全屏遮罩。

核心状态机可概括为：

```text
layoutSubviews
    └─ 立即移除 WCGlass 子视图
    └─ 收集并压制背景/effect 层
    └─ 最多排队一次 main-queue deferred update
          └─ 下一轮 layout 后再次收敛（若 WCGlass 回灌）
```

### “通知圆角与液态”与“未读消息提示液态”的边界

这两个名称在历史版本中容易混淆，2.1.11 的边界如下：

| 功能 | 2.1.10 | 2.1.11 |
| --- | --- | --- |
| 独立通知圆角/液态页面 | 有，含 333 行实现和 246 行设置页 | 完全删除，不再注册 hook、不再显示设置入口 |
| 未读消息提示液态 | 有独立开关和适配 | 保留；默认 `NO`，显式开启时执行 WCGlass 清理与延迟收敛 |
| WCGlass 同名/相邻材质层 | 可能与本插件叠加 | 通过来源识别、递归清理和一次 deferred update 处理竞争 |

因此新对话中如果用户说“通知液态已移除”，应理解为第一行；如果说“未读消息提示与 WCGlass 适配”，应理解为第二、三行，而不是把未读消息提示实现也删掉。

## 与既有历史的关系

`CHANGELOG.md` 目前顶部仍是 2.1.10 及更早条目，历史上已经记录过未读消息提示适配：

- 1.9.22 曾正式发布未读消息提示液态适配，并强调右侧延伸、只保留左圆角、隐藏原生整块背景、使用小型 effect view，而不是全屏层或持续 timer。
- 1.9.x 的预发布条目记录过 ThemeBox `msg_tip_bg`、几何位置和半径的迭代。

2.1.11 的实现延续这条“局部视图、小范围 effect、无持续 timer”的路线，同时增加 WCGlass 来源过滤。当前没有把本记录直接改写进旧 changelog，以免在未打 `v2.1.11` tag 的情况下制造错误的发布顺序；本文件是独立的 2.1.10→2.1.11 交接记录。

## 验证与限制

已核对：

- `git diff 2996bd1..47d390c --stat` 与上述 11 个变更文件；
- Theos `Makefile` 的源文件列表；
- `Tweak.xm` 和设置主页的注册/入口；
- 偏好 key、默认值、迁移和 getter/setter；
- `WCLiquidGlassUnreadMessageTip.m` 的来源识别、递归清理和 deferred update；
- `control` 的包版本。

本文件没有把“当前源码差异”冒充成一次新的模拟器或真机验证报告。若要重新打包，应先确认目标分支和精确的 2.1.11 二进制/dSYM，再执行构建、安装和未读消息提示/WCGlass 共存验证。当前工作树另有用户已有的 README、测试工具、`ipa/` 和文档改动，本次只新增本文件，不覆盖、不回滚这些内容。

## 新对话接续清单

1. 先确认是否仍以 `47d390c` 为 2.1.11 源码基线；不要直接以 `origin/main` 的旧提交替代。
2. 不要恢复 `WCLiquidGlassMessageNotification*` 四个已删除文件，除非用户明确要求重新引入该功能。
3. 修改未读消息提示时保留 WCGlass 来源识别、深度上限 6 和一次性 deferred update；不要改成持续定时器或全屏覆盖层。
4. 若需要发布，补充正式 `v2.1.11` tag、CHANGELOG 条目及与该 tag 一致的包/IPA 版本，并单独记录构建证据。
