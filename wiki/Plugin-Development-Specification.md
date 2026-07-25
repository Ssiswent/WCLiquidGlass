# Plugin Development Specification

本页概括仓库内的开发规范 `docs/solutions/architecture-patterns/wcliquidglass-plugin-development-specification.md`。该文档是扩展 WCLiquidGlass 或基于它开发新微信插件时的契约来源；**运行源码优先于文档，文档优先于 README 和历史截图**。

## 不可破坏的设计原则

1. 运行源码是最终事实来源。
2. 微信私有 API 只能动态访问（`NSClassFromString` / `NSSelectorFromString` / `respondsToSelector:`）。
3. 能力检测必须无副作用——判断可用性时绝不执行动作。
4. 可用性判断与执行共享同一份 selector 映射。
5. 保存用户意图，过滤运行时投影：页面不支持只临时隐藏，不改持久化配置。
6. 动作标识符必须稳定，改名需显式迁移。
7. 悬浮层不抢占微信：非 key window，空白区域触摸穿透。
8. 不注册全屏或屏幕边缘手势。
9. 不修改共享导航栏外观。
10. 运行菜单保持纯图标，无文字与角标。
11. 原生能力优先，兼容回退必须存在（`UIGlassEffect` → material blur）。
12. 保持局部修改，不顺手重构或格式化既有代码。

## 职责边界

| 文件 | 唯一职责 | 不应放入 |
| --- | --- | --- |
| `Tweak.xm` | 注入生命周期、进程校验、插件列表注册 | 设置 UI、布局、动作业务 |
| `WCLiquidGlassPreferences.m` | 动作元数据、默认值、校验、迁移、通知 | 页面判断、视图布局 |
| `WCLiquidGlassMenu.m` | 图标解析、能力判断、动作执行、overlay、手势 | 设置页表格与编辑器 |
| `WCLiquidGlass.m` | 设置页、编辑器、选择器、设置页视觉 | 全局窗口、进程入口 |

## 新增动作的标准流程

1. 在 preferences header 增加稳定 identifier 常量。
2. 在动作目录增加标题、SF Symbol 兜底和分类。
3. 在 asset name 映射中加入已验证的微信主题图标候选。
4. 把动作加入动作选择器对应 section。
5. 为 selector 型动作加入统一 selector 映射；特殊动作增加独立路由。
6. 确认 capability 检测不执行任何动作。
7. 确认执行阶段复用同一 selector 映射。
8. 决定是否加入默认按钮；影响旧用户则加一次性迁移。
9. 在支持与不支持页面分别真机测试显示状态。
10. 测试浅色、深色、展开菜单与设置列表中的图标表现。

骨架示意：

```objc
NSString * const WCLGActionExample = @"example";

@{ @"identifier": WCLGActionExample, @"title": @"示例动作", @"symbol": @"sparkles" };

WCLGActionExample: @[ @"verified_wechat_asset_name" ];   // 图标候选

WCLGActionExample: @[ @"verifiedSelector:" ];            // 唯一 selector 映射
```

## 新增设置的标准流程

1. 定义默认值和持久化键。
2. 在 preferences 提供类型明确的 getter/setter 与边界校验。
3. setter 发出统一配置变更通知。
4. 在设置页用原生组件表达，遵循现有 card / token。
5. Manager 或 HostView 监听并无重启刷新。
6. `restoreDefaults` 必须清理该键。
7. 验证旧配置缺少新键时能正确使用默认值。

## 正反例

```objc
// 正确：页面不支持时只隐藏运行时按钮
NSArray *storedItems = WCLiquidGlassPreferences.buttonItems;
NSArray *visibleItems = FilterByCurrentPageCapability(storedItems);
```

```objc
// 错误：用执行结果判断可用性——探测阶段可能已经跳转或修改输入框
BOOL available = PerformActionAndSeeWhetherItWorked(action);
```

```objc
// 错误：微信复用 navigation controller 后会污染其他页面
self.navigationController.navigationBar.barStyle = UIBarStyleBlack;
```

## 私有 API 兼容层规范

- 先判断类存在，再判断实例响应 selector。
- 动态调用前校验参数形状；必要时用方法签名区分 `Class` 与字符串。
- 小范围 `@try/@catch`，失败后走下一回退。
- 多个候选 selector 按已验证优先级排列。
- 不长期强引用微信私有对象；页面切换或前后台切换后重新解析。
- 兼容失败只能隐藏单个动作或提示，不能导致菜单或微信崩溃。

## 基于本项目创建新插件

复用工程形状时必须逐项更名与隔离：Theos target、package identifier、plist 与过滤器、类前缀、通知名、preferences key 前缀、插件列表标题与 controller 类名字符串、manager singleton 与 window subclass、产物名称。**不要共享通知名或 `NSUserDefaults` 键**，否则两个插件会互相刷新或覆盖配置。

## 完成定义

编译打包成功；未重排无关代码；旧配置可读且迁移完成；能力过滤与执行映射一致；图标与 fallback 齐备；设置 UI 符合既有 token 与原生导航规则；真机通过验收矩阵；若改变架构契约则同步更新规范文档。

## 已知限制

- 微信私有类、selector、asset 名会随版本变化，编译期无法保证兼容。
- 主要依赖真机验收，没有私有环境的单元测试替身。
- overlay 只认一个前台 active scene；复杂多窗口需要重新定义所有权。
- 12 个按钮是经布局验证的产品边界，不是任意常量。

## 相关页面

- [Architecture Overview](Architecture-Overview)
- [Action Catalog and Configuration](Action-Catalog-and-Configuration)
- [Page-Aware Action Filtering and Execution](Page-Aware-Action-Filtering-and-Execution)
- [Layout Preview Tool](Layout-Preview-Tool)
- [Glossary](Glossary)
