# LumiPluginBookletMaker

Lumi 与 GameFactory 共享的 Booklet Maker 远程包。

## Products

本仓库导出两个 product，对应两层职责：

| Product | Target | 说明 |
|---------|--------|------|
| `BookletMakerCore` | `Sources/BookletMakerCore` | 纯领域逻辑：纸张尺寸、折页布局引擎、拆分计划。不依赖 Kernel / Providers / SwiftUI。 |
| `PluginBookletMaker` | `Sources/PluginBookletMaker` | 插件层：`SuperPlugin` 实现 + SwiftUI 界面 + PDF 检查/渲染/拆分/合并服务。 |

`BookletMakerCore` 保留原有仓库名对应的语义，两个宿主现有的 `LumiBookletMaker` 依赖可平滑迁移到本包。

## 宿主注入约定

本包同时服务两个形态差异很大的宿主（Lumi 的多插件工作台、GameFactory 的独立 App），
因此**不硬编码任何宿主专属概念**，全部通过 `BookletMakerPlugin.init` 注入。

### pluginID

```swift
public nonisolated static let defaultPluginID = "com.coffic.lumi.plugin.booklet-maker"

public init(
    id: String = BookletMakerPlugin.defaultPluginID,
    order: Int = 880,
    policy: PluginEnablePolicy = .disabledByDefault,
    onWorkspaceActivate: VisibilityHook? = nil,
    onWorkspaceDeactivate: VisibilityHook? = nil
)
```

- `id` 决定 `PluginMetadata.id` 与插件数据目录名，两个宿主各用各的命名空间，互不干扰。
- `order` / `policy` 决定加载顺序与启用策略。

### 聊天区显隐

Lumi 把 Booklet Maker 作为工作台展示，激活时需收起聊天区；GameFactory 的
Booklet Maker 是独立 App，没有聊天区概念。宿主按需注入钩子：

```swift
// Lumi
BookletMakerPlugin(
    id: "com.coffic.lumi.plugin.booklet-maker",
    onWorkspaceActivate: { chatProvider?.setVisible(false) },
    onWorkspaceDeactivate: { chatProvider?.setVisible(true) }
)

// GameFactory
BookletMakerPlugin(
    id: "com.coffic.bookletmaker.plugin.booklet-maker",
    policy: .required
)
```

不传钩子时插件照常启动与切换布局。详见 `ToastSuperPlugin` 的同类做法。

## 能力范围

- 小册子拼版：简单对折、骑马钉、折页签名，输出可打印 PDF
- PDF 拆分：按切点导出多个文件
- PDF 合并：按给定顺序合并
- macOS：NSSavePanel / NSOpenPanel 导出；iOS：文件选择与分享

本包**不**向 Agent 贡献工具（`pdf_inspect` / `booklet_make` / `pdf_split` / `pdf_merge` /
`booklet_preview`）与 Skill。原 Lumi 本地包中的 Agent Tools 与 Skills 目录已在迁移时移除，
以避免引入 `KitAgentTool` / `ProviderToolManager` / `ProviderSkill` 等宿主专属依赖。

## 依赖

全部为远程包，无本地路径依赖：

- `LumiKernel`
- `LumiProviders`
- `LumiUI`
- `LumiLocalization`
- `LumiLogging`

## Development

```sh
swift build
swift test
```

## Testing

The package ships two test targets, matching the two products:

| Test target | Scope | Framework |
|---|---|---|
| `BookletMakerCoreTests` | Layout engine, paper / settings / split plans — pure domain logic | swift-testing (`@Suite` / `@Test`) |
| `PluginBookletMakerTests` | Plugin assembly, view model, PDF services, mobile workspace | XCTest |

The `BookletMakerCoreTests` target covers the imposition engine, paper size and
layout-mode models, booklet settings, and the split-plan parser. The
`PluginBookletMakerTests` target covers `BookletMakerPlugin` registration
(rail, content, docs, toolbar, activity bar, storage bridge), the view model,
the PDF inspector / merger / splitter, the demo PDF provider, and the
thumbnailer.

Run with code coverage:

```sh
swift test --enable-code-coverage
```

UI tests live in the host app — see `BookletMakerUITests` in the GameFactory
workspace. They are not part of this SPM package because UI testing requires a
host app target and an Xcode test runner.
