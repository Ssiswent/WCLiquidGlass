# 微信注入插件的两级崩溃诊断

## 目标

WCLiquidGlass 在不记录聊天内容的前提下，为微信插件冲突和私有 API 闪退提供可分享的诊断文件。日志保存在微信沙盒：

```text
Documents/WCLiquidGlass/Diagnostics/Crashes
```

设置页只展示 `Crashes` 中的最终文本日志；`Internal` 保存 PLCrashReporter 的待处理数据，不暴露为用户日志。

## 为什么分为两级

微信可能同时注入多个 tweak。多个崩溃采集器争抢 BSD signal handler 或 Mach exception port 会改变崩溃链路，甚至让诊断功能成为新的冲突源，因此不能默认启用最侵入的采集方式。

### 第一级：基础诊断

- 始终开启。
- 链式注册 `NSSetUncaughtExceptionHandler`，先保存 Objective-C exception，再调用此前的 handler。
- 保存 exception name、reason、call stack、系统/微信/插件版本、最近生命周期事件和已加载注入 dylib 列表。
- 不接管 fatal BSD signals，不覆盖其他插件的 signal handler。

这一层低干扰，但无法完整捕获 C/C++ 崩溃、野指针、系统强杀、Jetsam 或 watchdog termination。

### 第二级：完整诊断

- 默认关闭，由用户在设置页开启，重启微信后生效。
- 使用带 `WCLG_` 独立符号前缀的 PLCrashReporter 静态库。
- 使用 Mach exception handler，保留现有 handler 的转发关系；调试器附加时不启用。
- 不进行设备端本地符号化，保留线程、寄存器、binary images 等原始信息供离线分析。
- pending report 在下次启动转换为 iOS 风格 `.crash` 文本，成功写入后才清理原始 pending data。

完整诊断仍无法承诺捕获 Jetsam、watchdog、用户强制结束进程或内核直接终止。Mach handler 也可能被宿主或其他插件先行处理，因此 UI 必须明确说明能力边界。

## 隐私与数据最小化

日志允许包含：

- 崩溃堆栈、线程、寄存器和 binary images。
- iOS、设备、微信和 WCLiquidGlass 版本。
- 已加载注入 dylib 的文件名。
- application state、process uptime 和最近生命周期事件。

日志禁止主动读取或写入：

- 聊天输入框和消息内容。
- 联系人、账号、会话名称和媒体内容。
- 插件偏好的具体业务值。

## 存储与生命周期

- 最终日志最多保留 20 份，按修改时间删除最旧文件。
- 使用 `NSFileProtectionCompleteUntilFirstUserAuthentication`，确保设备首次解锁后可在下一次启动处理 pending report。
- 日志列表通过文件 URL 分享，不把大日志完整读入 UI 内存。
- 支持单条左滑删除和确认后清空全部。
- 删除操作必须验证目标位于 `Crashes` 目录内，不能接受任意 URL。

## 注入环境的符号隔离

官方预编译 PLCrashReporter 使用 `PLCrashReporter` 等通用 Objective-C 类名。静态链接到 tweak 后，如果微信或另一个 tweak 已加载同名类，Objective-C runtime 的结果不可预测。

WCLiquidGlass 必须从官方源码重新编译并定义：

```text
PLCRASHREPORTER_PREFIX=WCLG_
```

发布前应检查最终 dylib：存在 `WCLG_PLCrashReporter`，不存在未加前缀的 `PLCrashReporter` runtime class。

## 验收清单

1. 默认设置下微信可正常启动，基础异常 handler 会调用原有 handler。
2. 完整采集开关重启微信后才改变 handler，不在运行中尝试卸载。
3. 调试器附加时完整采集自动跳过。
4. 人工 Objective-C exception 生成 `ObjectiveC.txt`，包含堆栈和 dylib 列表。
5. 完整模式 native crash 在下次启动生成 `Full.crash`，随后 pending report 被清理。
6. 日志列表数量、文件大小、日期、分享、单条删除和清空正确。
7. 超过 20 份时只删除最旧日志。
8. 日志不包含测试聊天文字。
9. 最终 dylib 仅包含 `WCLG_` 前缀的 PLCrashReporter 类。

## Files

- `WCLiquidGlassCrashLogger.h`
- `WCLiquidGlassCrashLogger.m`
- `WCLiquidGlassPreferences.m`
- `WCLiquidGlass.m`
- `Vendor/PLCrashReporter/README.md`
