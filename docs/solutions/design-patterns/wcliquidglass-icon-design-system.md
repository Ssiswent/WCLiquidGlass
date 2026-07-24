---
title: WCLiquidGlass 固定图标设计与资源规范
date: 2026-07-23
category: design-patterns
module: WCLiquidGlass icon system
problem_type: design_pattern
component: tooling
severity: medium
applies_when:
  - 新增或调整 WCLiquidGlass 自有设置页图标时
  - 新增 WCLiquidGlass 自身动作入口时
tags: [ios, uikit, static-icon, png, svg, liquid-glass, settings-ui]
---

# WCLiquidGlass 固定图标设计与资源规范

## Scope

本规范只适用于 WCLiquidGlass 自己拥有的品牌、设置、诊断和管理图标。微信功能项继续通过 `WCLiquidGlassWeChatAssetImage` 读取微信主题素材；不得把微信素材重绘成自定义图标，也不要以自定义图标替换它们。

所有已确认图标均以固定透明 PNG 加载；SVG 仅作为可审阅、可再渲染的母版。这样真机显示不再依赖 Core Graphics 的运行时近似绘制，设计稿与插件资源是同一份几何来源。

## Core Language

图标使用“圆润、简约、可爱、具实体层次”的黑灰双色语言：

1. 主体是纯黑色的大圆角形体。
2. 后层或实体背面使用中性灰，不使用投影、渐变、高光或描边模拟层次。
3. 几何元素使用连续圆角、圆端和饱满比例；避免尖锐、过细、机械的线条。
4. 一个图标只保留 2 至 4 个有语义的结构，优先用前后层错位表达层次。
5. 图标背景保持透明；卡片、菜单玻璃和圆形按钮背景由宿主界面负责，图标本身不再绘制蓝色圆形或方形底板。
6. 所有图标必须在 28–32pt 下可辨识；深色模式使用 `Source/dark` 的独立 PNG 母版：`#f2f2f7` 前层与 `#8e8e93` 后层。不能对现有 PNG 施加 tint 或临时重绘。

## Brand Glyph

品牌图标是最终确定的“水母 / 悬浮菜单”轮廓：

1. 顶部是宽而低的纯黑圆顶，底缘保留终版中自然且不规则的轻微波浪起伏。
2. 圆顶右下有一个横向中浅灰圆角液态窗口，窗口完整嵌在黑色圆顶内，其右边缘被一个小黑缺口切开；这是结构窗口，不是眼睛或高光。
3. 圆顶右下方只有一条很薄的灰色后层底板，不能延伸成独立主体或超过圆顶主体的视觉厚度。
4. 下方只有三根短圆角触须：左黑、中央黑、右灰；三根视觉中心等间距且整体居中。中间触须垂直，左右触须只做很小幅度的外八。
5. 不加入脸部、文字、彩色、发光、边框、渐变或额外触须。

这个图标同时用于设置页品牌卡和“WCLiquidGlass 设置”动作入口，确保用户在环形菜单与设置页获得同一识别符号。

## Settings Icon Family

设置页图标用相同的黑灰实体语言，但可根据功能使用不同轮廓：

| 功能 | 图形语义 |
| --- | --- |
| 全局菜单 | 六颗规则圆周气泡与中心灰点；灰色后层沿每颗气泡的径向外扩，保持完整圆形轮廓 |
| 按钮大小 | 墨石小物：黑色前圆、灰色后圆与灰色内核 |
| 紧凑布局 | 四枚圆角卡片，带灰色后层 |
| 按钮与动作 | 墨石小物：三枚黑色圆点与三条灰色圆角操作条 |
| WCGlass 兼容修复 | 前后错位的盾牌与内层胶囊 |
| 完整崩溃采集 | 前后错位的圆角监视器与脉冲 |
| 崩溃日志 | 前后错位的圆角文档与圆形检视器 |
| 恢复 | 黑色前层回转箭头与灰色后层弧线 |

“恢复默认”仍使用红色文字提示其危险性，但图标本身保持黑灰品牌体系，不额外引入红色图形。

## Resource Structure

`Resources/Icons` 是唯一的图标母版目录：

| 目录 | 用途 |
| --- | --- |
| `Resources/Icons/Source` | 品牌最终 PNG 与所有设置图标 SVG 母版；修改设计只能从这里开始 |
| `Resources/Icons/Rendered` | 由母版渲染的 400×400 透明 PNG，用于逐像素预览与打包前核验 |
| `layout/Library/Application Support/WCLiquidGlass/Icons` | 随 rootless `.deb` 安装、供安装内容核验的 PNG；文件名必须与 `Rendered` 完全一致 |

品牌母版为 `Source/Brand.png`，来自用户确认的截图原始像素；不得重新凭描述改绘、在线下载或替换为运行时代码图形。

`Source/BrandAction.svg` 是品牌在“按钮与动作”列表与环形菜单中的专用矢量母版：在 1024×1024 透明画布内保留约 660px 的图形主体。运行时代码使用同一组路径，在当前屏幕 scale 与实际目标尺寸上直接栅格化；它采用与微信主题 SVG 相同的按需矢量输出路径，避免截图 PNG 缩放造成的边缘锯齿与光学偏大问题。

Quick Look 会把 SVG 透明背景错误烘焙成白色，因此只允许 `librsvg` 的 `rsvg-convert` 用于生成预览 PNG。预览不参与运行时加载；动作入口必须走按需矢量绘制。

`docs/design-previews/final-svg` 中的历史文件只用于保留设计过程，不参与构建，也不能作为修改入口。

## Implementation Rules

1. `WCLiquidGlassSettingsIconImage` 与 `WCLiquidGlassBrandIconImage` 优先从构建时嵌入 dylib 的固定 PNG 字节创建图片，并以 `UIImageRenderingModeAlwaysOriginal` 返回；安装目录保留同一份 PNG 用于审计与包内容核验。
2. 微信进程可能无法读取 rootless 安装目录，因此不能只依赖 `/var/jb/Library/Application Support/...` 路径。嵌入资源是可靠显示路径，外部文件读取仅为异常回退。
3. 不在插件运行时使用 `Core Graphics`、`UIBezierPath` 或系统 tint 重绘任何自有图标；资源缺失应在打包检查中修复，而不是以近似图标回退。
4. 新图标先判断是否属于微信原生功能。属于微信功能则扩展主题素材映射；只属于本插件设置或管理功能时才增加到 `Resources/Icons`、嵌入资源映射与静态文件名映射。
5. SVG 采用 100×100 `viewBox`，透明背景，纯黑 `#050505` 前层与中性灰 `#b9b7b2` 后层；菜单的六枚前层圆心位于半径 28 的规则圆周，后层位于半径 34 的同一圆周。
6. 每次改动必须依次检查：SVG 总览、渲染 PNG、32pt 设置单元格、58pt 品牌卡和环形菜单中的“WCLiquidGlass 设置”入口；确认后再构建 `.deb`。
7. 品牌卡通过 `WCLiquidGlassBrandIconImage` 使用 `Brand.png` 并按 58pt 显示。动作列表与环形菜单入口必须使用 `BrandAction.svg` 的同组路径，在 28×28pt 槽位的当前屏幕 scale 上直接绘制；实际图形约 18pt，匹配微信素材的光学大小；不得用运行时缩小原始品牌 PNG 替代。
8. `UIListContentImageProperties.maximumSize` 只限制图片最大值，不保证标题起点。所有设置与动作列表必须同时指定 `reservedLayoutSize = 28×28pt`，使不同 SVG 或 PNG 的标题严格对齐。

## Related

- [微信原生图标解析与回退](wechat-native-icon-resolution.md)
- [微信插件设置页的 Liquid Glass UI 结构](liquid-glass-settings-ui.md)
- [插件开发架构规范](../architecture-patterns/wcliquidglass-plugin-development-specification.md)
