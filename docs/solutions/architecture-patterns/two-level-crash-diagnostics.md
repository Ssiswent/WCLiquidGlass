# 微信注入插件的统一日志采集

## 目标

WCLiquidGlass 默认启用尽可能详细的异常与崩溃采集，并在插件不主动读取聊天内容的前提下提供可分享的日志。最终文件保存在微信沙盒：

    Documents/WCLiquidGlass/Diagnostics/Crashes

Internal/PLCrashReporter 保存 PLCrashReporter 的 live 单槽文件，Internal/Pending 保存启动前原子移动出的唯一 staging `.plcrash` 文件；下次启动先移动现有 pending，再尽早安装采集器，随后在安全的 Objective-C 环境中逐个格式化 staging。只有最终文本成功写入后才删除对应 staging 文件；处理失败的 staging 会在同目录隔离为 `.failed`，保留取证且后续启动不自动重试。

## 启动与采集

- 主微信进程在 %ctor 中尽早启动日志器，目录准备完成后先把现有 `crashReportPath` 原子移动到 `Internal/Pending`，再立即创建并启用 PLCrashReporter；staging 文件使用唯一名称，避免覆盖未处理报告。
- PLCrashReporter 使用 PLCrashReporterSignalHandlerTypeMach、PLCrashReporterSymbolicationStrategyNone 和 shouldRegisterUncaughtExceptionHandler:YES，统一采集原生 Mach 异常与未捕获 Objective-C 异常。
- 调试器已附加时跳过启用，避免与调试器的 Mach handler 争用。
- 日志器随后处理 pending 报告、注册生命周期观察并裁剪到最多 20 份；这些步骤的失败写入 recent event，不以重复的可见提示打扰用户。`customData` 只在 enable 前设置一次，避免生命周期回调与崩溃写入并发。
- 如果 staging 移动失败，日志器会在 enable 前处理并清理 live pending；失败时保持禁用，绝不在 enable 后调用单槽 purge。
- staged 报告读取、解析、格式化、写入或清理失败时改名为唯一 `.failed` 文件；改名失败只记录 recent event。
- 页面层级诊断是同一日志列表中的安全手动记录，文件名使用 PageHierarchy-<timestamp>.txt。

PLCrashReporter 预编译库使用 WCLG_ 符号前缀。设备端不做本地符号化，保留线程、寄存器和 binary images 供离线分析。

## 文件命名与 UI

pending 报告根据 PLCrashReport.exceptionInfo 命名：

- Crash-<timestamp>-ObjectiveC.crash：Objective-C 异常。
- Crash-<timestamp>-Native.crash：原生 Mach 崩溃。
- PageHierarchy-<timestamp>.txt：页面层级诊断。

日志列表按文件名识别新旧类型；旧的 ObjectiveC、Full 文件继续按原语义显示，无法识别的历史文件显示“诊断日志”，不迁移或重写旧文件。设置入口和 Sheet 标题统一使用“日志”。

## 隐私与能力边界

日志可以包含崩溃堆栈、线程、寄存器、binary images、系统/设备/微信/WCLiquidGlass 版本、已加载注入 dylib 文件名、应用状态、进程运行时间和最近生命周期事件。日志器不主动读取聊天输入框、聊天文字、消息、联系人、账号、会话名称或媒体内容；页面层级诊断仍严格排除可见文本。系统生成的 crash reason 或对象描述可能带运行时上下文，崩溃报告不承诺对其脱敏，分享前应自行确认。

Mach/Objective-C 采集仍受进程启动时机和宿主环境限制，不能可靠承诺捕获 Jetsam、watchdog、用户强制结束、内核直接终止或其他进程先行接管 handler 的情况。注入点早于 %ctor 或构造函数执行前发生的崩溃也没有机会安装采集器，这是启动阶段的固有限制。

## 存储与维护

- 文件使用 NSFileProtectionCompleteUntilFirstUserAuthentication。
- 日志列表通过文件 URL 分享，不把整份大文件读入 UI。
- 支持单条删除；日志 Page Sheet 右上角使用系统 `UIBarButtonItem(menu:)`，菜单只显示带垃圾桶图标的“确认清空”，点击外部取消，不叠加 Alert 或 Action Sheet。删除前校验目标位于 Crashes 目录。
- 超过 20 份时按修改时间删除最旧文件。

## 发布检查

发布前应确认最终 dylib 存在 WCLG_PLCrashReporter，不存在未加前缀的 PLCrashReporter runtime class，并验证启动、pending 转换、日志命名、分享、删除和清空行为。

## Files

- WCLiquidGlassCrashLogger.h
- WCLiquidGlassCrashLogger.m
- WCLiquidGlassPreferences.h
- WCLiquidGlassPreferences.m
- WCLiquidGlass.m
- WCLiquidGlassHomeCorners.m
- Tweak.xm
