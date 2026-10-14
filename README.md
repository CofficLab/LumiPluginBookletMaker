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

本包自带三层测试，全部在仓库内，无需外部宿主工程即可验证。

| 层 | 位置 | 数量 | 运行方式 |
|---|---|---|---|
| 领域层 | `Tests/BookletMakerCoreTests` | swift-testing `@Suite` | `swift test` |
| 插件层 | `Tests/PluginBookletMakerTests` | 115 项 XCTest | `swift test` |
| 界面层 | `BookletMakerUITestHost/UITests` | 40 项 XCUITest | `xcodebuild test` |

### 单元测试

```sh
swift test                                   # 全部
swift test --filter BookletMakerViewModelTests
swift test --enable-code-coverage
```

其中 `BookletLocalizationCatalogTests` 是本地化目录的守卫，把四条容易静默退化的
规则固化为断言：key 在全部五种语言下必须有非空译文、各语言占位符数量须一致且
定位占位符（`%1$@`）位置连续、代码里引用的每个 key 必须存在于目录、`sourceLanguage`
须为 `en`。新增文案时忘记维护 xcstrings 会立刻失败，而不是等到某个语种的界面
里出现一两句漏翻译的英文。

### 界面测试

界面测试需要宿主 App 与 Xcode test runner，因此以 Xcode 工程形式内嵌在仓库内
（`project.yml` + XcodeGen 生成），不依赖任何宿主专属的私有包。

```sh
brew install xcodegen          # 一次性
./generate-ui-test-project.sh  # 生成 BookletMakerUITests.xcodeproj
xcodebuild test \
  -project BookletMakerUITests.xcodeproj \
  -scheme BookletMakerUITests \
  -destination 'platform=macOS'
```

`BookletMakerTestHost` 是一个最小宿主 App，按真实宿主（GameFactory 的
`BookletMakerApp`）的顺序装配：**注册 Provider → 启动插件 → 组装视图**。
该顺序不可颠倒：插件 `onBoot` 会向 Rail 注册 tab、向 ContentView 注入内容区，
提前组装会让这些区域停留在空状态。

覆盖范围：

| 套件 | 覆盖 |
|---|---|
| `BookletMakerBookletUITests` | 四个预览阶段切换、装订前纸张列表、纸张/版式/滑块/开关交互、补白开关在书本折叠版式下强制禁用、锚点跨语言稳定 |
| `BookletMakerSplitUITests` | 切分点选中与反选、多切分点独立、导出门控随有效性翻转、页面点击与侧栏输入两条路径等价、非法输入校验、分段重命名 |
| `BookletMakerMergeUITests` | 空队列与导出禁用、汇总如实反映队列规模、与小册子设置互斥 |
| `BookletMakerMergeQueueUITests` | 队列注入后的排序（双向）、边界按钮禁用、删除、导出门控变化、删空回到空态 |
| `BookletMakerExportPanelUITests` | 三个工具的导出面板、保存/取消、替换确认、面板关闭后界面恢复 |
| `BookletMakerToolSwitchUITests` | 三工具切换后侧栏设置与主按钮文案同步 |
| `BookletMakerLocalizationUITests` | en / zh-Hans / zh-Hant 文案，以及切换语言后锚点结构不变 |

#### 编写界面测试时的两条约定

1. **只用 `accessibilityIdentifier` 定位元素**，不要用文案——文案随本地化变动，
   identifier 不会。唯一例外是 `BookletMakerLocalizationUITests`，那里用文案
   正是为了验证文案本身。
2. **断言状态而非存在性**：元素存在只说明渲染了，真正要校验的是选中态、
   启用态、门控原因。

#### 系统面板（保存 / 选择文件夹）在 XCUITest 里的形态

导出用 `NSSavePanel.runModal()` / `NSOpenPanel.runModal()`，实测有几个反直觉之处：

| 现象 | 正确做法 |
|---|---|
| 面板挂在 `app.dialogs` 下，**不是** `app.sheets`，也不是 `app.windows` | `app.dialogs.matching(identifier:)` |
| 面板标题不暴露给 XCUITest（`label` 为空、无 StaticText 子节点） | 改用 identifier 区分：`save-panel` / `open-panel` |
| 两种面板的确认按钮都叫 `OKButton` | 不能靠它区分面板类型 |
| 目标文件已存在时叠一个「是否替换」的 sheet | `confirmReplaceIfPresent()`，按钮为 `action-button-1` |
| 面板打开期间查询下层界面报 `still interrupting` | `waitForModalPanelToClose()` 后再断言 |

此外：测试宿主**不开沙盒**，而 XCUITest runner 自带沙盒且与宿主进程隔离。
因此导出产物写在宿主指定的目录里，runner 既读不到也清理不掉——测试模式
下宿主会把面板预选到自己的临时目录，避免往用户文件夹里丢文件。

#### 关于导出产物的校验

界面测试**不**断言导出文件的内容：产物确实被正确写出，但 runner 无权读取，
且产物正确性（页数、分段、文件名）由 `BookletMakerViewModelTests` 覆盖。
界面测试只负责「交互链路完整走通」。

#### 一个容易踩的坑

**不要给容器视图打 `accessibilityIdentifier`。** SwiftUI 会把祖先的 identifier
下推到每一个叶子元素，导致容器内部的锚点全部被同一值覆盖而无法定位。本包
曾因此让 `split.cutPoint.*`、`split.summary`、`merge.insufficientHint`
一度全部失效。若需要判断某个区域是否出现，请在区域内的**叶子元素**上取锚点。

#### 已知差异

测试宿主使用公开的 `DefaultRootViewProviding` 并自行拼装根布局，而真实宿主使用
自己的根视图实现。测试宿主**不**装配 `CommandProviding` 与设置侧栏插件，因此
设置窗口相关界面不在本套件覆盖范围内——该能力来自宿主侧包，插件仓库无法自证。

