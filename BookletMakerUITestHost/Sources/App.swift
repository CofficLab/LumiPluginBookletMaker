import SwiftUI
import KernelCore
import LumiLocalizationKit
import LumiUI
import ProviderActivityBar
import ProviderContentView
import ProviderDocsView
import ProviderRailView
import ProviderRootView
import ProviderStorage
import ProviderTheme
import ProviderToolbar
import PluginBookletMaker

/// 最小宿主 App，仅用于 UI 测试。
///
/// 装配顺序与真实宿主（GameFactory 的 `BookletMakerApp`）一致：
/// **注册 Provider → 启动插件 → 组装视图**。插件 `onBoot` 会向 Rail 注册
/// tab、向 ContentView 注入内容区，任何一步提前都会导致界面缺少对应区域。
@main
struct BookletMakerTestHostApp: App {
    @StateObject private var container = TestHostContainer()

    var body: some Scene {
        WindowGroup {
            Group {
                if let layout = container.layout {
                    layout
                        .onAppear {
                            // 激活放在 onAppear：此时布局已挂载，
                            // ActivityBar 的激活闭包能正确设置 Rail 可见性。
                            container.activatePlugin()
                        }
                } else {
                    ProgressView()
                        .accessibilityIdentifier("host.loading")
                }
            }
            .frame(minWidth: 900, minHeight: 600)
        }
        .defaultSize(width: 1200, height: 800)
    }
}

/// 测试宿主容器：装配 Provider、启动插件、产出根布局。
@MainActor
final class TestHostContainer: ObservableObject {
    @Published var layout: TestHostRootLayout?

    private let kernel = KernelCoreContainer()
    private let plugin = BookletMakerPlugin(
        // 宿主专属命名空间，与 GameFactory / Lumi 一致，
        // 保证插件数据目录独立于共享包的默认值。
        id: "com.coffic.bookletmaker.plugin.booklet-maker",
        policy: .required
    )

    private var toolbar: (any ToolbarProviding)?
    private var activityBar: (any ActivityBarProviding)?
    private var rail: (any RailViewProviding)?
    private var contentView: (any ContentViewProviding)?

    init() {
        Task { @MainActor in
            setupProviders()
            bootPlugin()
            buildLayout()
        }
    }

    // MARK: - Assembly

    /// 注册 UI 测试所需的 Provider。
    ///
    /// 与真实宿主的差异：真实宿主还会装配 CommandProviding（系统菜单）与
    /// 设置侧栏插件。UI 测试不覆盖菜单路径，省略以避免依赖宿主专属包。
    private func setupProviders() {
        do {
            try kernel.registerProvider((any ActivityBarProviding).self, DefaultActivityBarProviding())
            try kernel.registerProvider((any RailViewProviding).self, DefaultRailViewProviding(visibleCategories: [.design]))
            try kernel.registerProvider((any RootViewProviding).self, DefaultRootViewProviding())
            try kernel.registerProvider((any ContentViewProviding).self, DefaultContentViewProviding())
            try kernel.registerProvider((any ToolbarProviding).self, DefaultToolbarProviding())
            try kernel.registerProvider((any DocsViewProviding).self, DefaultDocsViewProviding())
            try kernel.registerProvider((any ThemeProviding).self, DefaultThemeProviding())

            // Storage 指向临时目录：UI 测试不应污染用户真实数据目录，
            // 每次启动用 UUID 隔离，测试之间互不干扰。
            let storageRoot = FileManager.default.temporaryDirectory
                .appendingPathComponent("BookletMakerUITest-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: storageRoot, withIntermediateDirectories: true)
            try kernel.registerProvider((any StorageProviding).self, DefaultStorageProvider(dataRootDirectory: storageRoot))
        } catch {
            assertionFailure("Failed to setup providers: \(error)")
            print("Failed to setup providers: \(error)")
        }
    }

    private func bootPlugin() {
        do {
            try plugin.onBoot(kernel: kernel)
        } catch {
            assertionFailure("Failed to boot plugin: \(error)")
            print("Failed to boot plugin: \(error)")
        }
    }

    /// 解析各 Provider 并产出根布局。必须晚于插件启动。
    private func buildLayout() {
        guard kernel.resolveProvider((any RootViewProviding).self) != nil else {
            assertionFailure("RootViewProviding not registered")
            return
        }
        toolbar = kernel.resolveProvider((any ToolbarProviding).self)
        activityBar = kernel.resolveProvider((any ActivityBarProviding).self)
        rail = kernel.resolveProvider((any RailViewProviding).self)
        contentView = kernel.resolveProvider((any ContentViewProviding).self)
        layout = TestHostRootLayout(
            toolbar: toolbar,
            activityBar: activityBar,
            rail: rail,
            contentView: contentView
        )
    }

    // MARK: - Activation

    /// 激活 BookletMaker 的 ActivityBar 条目。
    ///
    /// 与真实宿主一致地走 `ActivityBarItem` 的 activation 闭包——它负责设置
    /// Rail 可见分类与可见 tab、宽度档位、工具栏标题，这些正是 UI 测试要验证的。
    func activatePlugin() {
        activityBar?.activateItem(id: "\(plugin.id).entry")
    }
}
