---
title: ThemePro 等价素材文件保护
date: 2026-08-01
category: integration-issues
module: WCLiquidGlassMaterialFileProtection
problem_type: compatibility
component: filesystem
severity: high
tags: [ios, wechat, themepro, sandbox, material-protection, hook]
---

# ThemePro 等价素材文件保护

## 问题

微信会通过 `MMDiskUsageScaner` 周期性扫描沙盒，删除它判定为未知的文件。目录本身通常仍然存在，但 PNG、SVG 等素材文件可能被清理。ThemePro 即使没有开启可见主题功能，也会持续安装一组磁盘扫描与文件管理 Hook，因此能够避免这类素材丢失。

## 实现边界

WCLiquidGlass 保留 ThemePro 已验证的原始语义，不扩展为全沙盒白名单：

1. `MMDiskUsageScaner startWithScanConfig:` 在保护开启时，将未知文件删除、删除上报和空文件夹删除设为关闭。
2. `MMDiskUsageScanConfig` 的三个对应 setter 在保护开启时强制向原实现传入 `NO`。
3. `NSFileManager removeItemAtPath:error:` 命中 ThemePro 的 12 条原始路径片段时跳过删除并返回 `YES`。
4. `NSFileManager filesystemItemMoveOperation:shouldMoveItemAtPath:toPath:` 仅检查来源路径；命中 ThemePro 的 11 条原始路径片段时跳过原实现并返回 `NO`。
5. 未命中的路径、开关关闭后的调用以及 ThemePro 自有资源工作状态全部继续使用原实现。

保护匹配使用 `containsString:`，所以目标目录下的多层子目录和文件无需逐层登记；只要完整路径中包含受保护片段，就会沿用相同处理。

## 跨进程开关

Hook 同时安装到 `com.tencent.xin` 与 `com.tencent.xin.sharetimeline`。开关值固定写入微信主偏好域，并通过 Darwin 通知让两个进程刷新内存缓存，避免分享时间线进程使用自己的 `standardUserDefaults` 域而遗漏关闭操作。

文件删除与移动属于高频全局路径。Hook 只读取原子缓存，不在每次调用时访问 `NSUserDefaults`；设置发生变化时才重新读取一次偏好。开关默认开启，关闭后两个进程都恢复微信原始扫描和文件操作行为。

## 不应改变的规则

- 不把用户自定义目录自动加入匹配列表。
- 不检查移动目标路径，继续只检查来源路径。
- 不把被拦截的删除改成错误；命中时仍返回 `YES`。
- 不修改 ThemePro 原有的路径片段与大小写。
- 不让素材保护模块启动 WCLiquidGlass 的 UI、菜单或其它主页 Hook。
