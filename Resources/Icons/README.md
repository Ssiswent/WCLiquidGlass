# WCLiquidGlass Icons

这里保存 WCLiquidGlass 自有图标的唯一母版与其打包资源。

- `Source`：可编辑母版。品牌只允许使用已确认的 `Brand.png`；其余图标使用 SVG。
- `Source/BrandAction.svg`：动作入口专用矢量母版。1024×1024 透明画布中保留约 660px 宽的品牌图形，用于匹配微信素材的视觉留白；运行时代码按目标尺寸直接绘制对应路径，不得用截图 PNG 缩放替代。
- `Rendered`：由母版生成的透明 PNG，供预览、像素核验与复制到安装布局使用。
- `layout/Library/Application Support/WCLiquidGlass/Icons`：随安装包提供的同名 PNG，便于检查安装内容。

修改顺序固定为：更新 `Source` → 重新渲染到 `Rendered` → 预览确认 → 同步到 `layout` 与嵌入资源源文件 → 构建并检查 `.deb`。dylib 使用构建时嵌入的同一批 PNG 字节，避免微信沙盒拒绝读取外部资源；不要在运行时代码中重绘或 tint 这些图标。

`BrandAction.svg` 可用 `librsvg` 的 `render-brand-action.zsh` 生成透明 PNG 预览，不能使用 Quick Look。插件运行时不加载该 PNG，而是在当前屏幕 scale 与目标尺寸上直接绘制相同路径，避免任何位图缩放。

详细的视觉语言、文件映射和验收项见 [图标设计与资源规范](../../docs/solutions/design-patterns/wcliquidglass-icon-design-system.md)。
