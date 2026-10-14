import SwiftUI
import KernelCore
import ProviderActivityBar
import ProviderRailView
import ProviderRootView
import ProviderContentView
import ProviderToolbar
import ProviderStorage
import ProviderDocsView
import PluginBookletMaker

/// 最小宿主 App，仅用于 UI 测试
@main
struct BookletMakerTestHostApp: App {
    @StateObject private var container = TestHostContainer()

    var body: some Scene {
        WindowGroup {
            if let rootView = container.rootView {
                rootView
                    .onAppear {
                        // 激活插件
                        container.activatePlugin()
                    }
            } else {
                ProgressView()
            }
        }
        #if os(macOS)
        .defaultSize(width: 1200, height: 800)
        #endif
    }
}

/// 测试宿主容器
@MainActor
final class TestHostContainer: ObservableObject {
    @Published var rootView: AnyView?
    private let kernel = KernelCoreContainer()
    private let plugin = BookletMakerPlugin()

    init() {
        Task { @MainActor in
            setupKernel()
            bootPlugin()
        }
    }

    private func setupKernel() {
        // 注册 Provider
        do {
            try kernel.registerProvider((any ActivityBarProviding).self, DefaultActivityBarProviding())
            try kernel.registerProvider((any RailViewProviding).self, DefaultRailViewProviding(visibleCategories: [.chat, .design]))
            try kernel.registerProvider((any RootViewProviding).self, DefaultRootViewProviding())
            try kernel.registerProvider((any ContentViewProviding).self, DefaultContentViewProviding())
            try kernel.registerProvider((any ToolbarProviding).self, DefaultToolbarProviding())
            try kernel.registerProvider((any DocsViewProviding).self, DefaultDocsViewProviding())
            
            // Storage
            let storageRoot = FileManager.default.temporaryDirectory
                .appendingPathComponent("BookletMakerUITest-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: storageRoot, withIntermediateDirectories: true)
            try kernel.registerProvider((any StorageProviding).self, DefaultStorageProvider(dataRootDirectory: storageRoot))
        } catch {
            print("Failed to setup kernel: \(error)")
        }
        
        // 获取 RootView
        if let rootProvider = kernel.resolveProvider((any RootViewProviding).self) {
            rootView = rootProvider.makeRootView()
        }
    }

    private func bootPlugin() {
        try? plugin.onBoot(kernel: kernel)
    }

    func activatePlugin() {
        if let activityBar = kernel.resolveProvider((any ActivityBarProviding).self) {
            let entryID = "\(plugin.id).entry"
            activityBar.activateItem(id: entryID)
        }
    }
}
