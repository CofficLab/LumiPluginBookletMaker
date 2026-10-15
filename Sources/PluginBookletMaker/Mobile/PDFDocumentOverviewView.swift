#if os(iOS)
import SwiftUI

/// 文档概览：已打开文件的根页面。展示文件信息与三个工具入口；
/// 菜单提供文件信息、更换 PDF、关闭当前 PDF（帮助与关于在 T6 接入）。
struct PDFDocumentOverviewView: View {
    @ObservedObject var feature: BookletMakerMobileFeature
    let onOpenPDF: () -> Void

    private var viewModel: BookletMakerViewModel { feature.viewModel }

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    thumbnail
                    VStack(alignment: .leading, spacing: 4) {
                        Text(feature.documentName)
                            .font(.headline)
                            .lineLimit(2)
                        Text(pageCountText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("overview.documentInfo")
            }

            Section {
                NavigationLink(value: MobileWorkspaceState.Tool.booklet) {
                    toolRow(
                        title: BookletLocalization.string("Make Booklet"),
                        subtitle: BookletLocalization.string("Reorder pages for folded binding"),
                        systemImage: "book.closed"
                    )
                }
                .accessibilityIdentifier("overview.bookletTool")

                NavigationLink(value: MobileWorkspaceState.Tool.split) {
                    toolRow(
                        title: BookletLocalization.string("Split PDF"),
                        subtitle: splitSubtitle,
                        systemImage: "scissors"
                    )
                }
                .accessibilityIdentifier("overview.splitTool")

                NavigationLink(value: MobileWorkspaceState.Tool.merge) {
                    toolRow(
                        title: BookletLocalization.string("Merge PDF"),
                        subtitle: BookletLocalization.string("Combine multiple PDFs in order"),
                        systemImage: "arrow.triangle.merge"
                    )
                }
                .accessibilityIdentifier("overview.mergeTool")
            }
        }
        .navigationTitle(BookletLocalization.string("Document"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Section {
                        Label(feature.documentName, systemImage: "doc")
                        Label(pageCountText, systemImage: "number")
                        if let size = firstPageSizeText {
                            Label(size, systemImage: "ruler")
                        }
                        if feature.isDemo {
                            Label(BookletLocalization.string("Sample"), systemImage: "book")
                        }
                    }

                    Divider()

                    Button {
                        onOpenPDF()
                    } label: {
                        Label(BookletLocalization.string("Replace PDF…"), systemImage: "arrow.triangle.2.circlepath")
                    }

                    NavigationLink {
                        BookletHelpMobileView()
                    } label: {
                        Label(BookletLocalization.string("Help"), systemImage: "questionmark.circle")
                    }

                    Button(role: .destructive) {
                        feature.closeDocument()
                    } label: {
                        Label(BookletLocalization.string("Close Current PDF"), systemImage: "xmark.circle")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel(BookletLocalization.string("Document menu"))
            }
        }
        .navigationDestination(for: MobileWorkspaceState.Tool.self) { tool in
            ToolDestination(tool: tool, feature: feature, onOpenPDF: onOpenPDF)
        }
        .overlay(alignment: .top) {
            if let message = feature.sessionErrorMessage {
                sessionErrorBanner(message)
            }
        }
    }

    private var thumbnail: some View {
        PDFDocumentPageView(
            documentURL: feature.documentPreviewURL,
            pageNumber: 1
        )
        .frame(width: 56, height: 56 / viewModel.currentDocument.pageAspectRatio)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
        .accessibilityHidden(true)
    }

    private var pageCountText: String {
        BookletLocalization.string("%lld pages", Int64(feature.pageCount))
    }

    private var splitSubtitle: String {
        feature.pageCount >= 2
            ? BookletLocalization.string("Split after chosen pages into multiple files")
            : BookletLocalization.string("At least 2 pages are required")
    }

    private var firstPageSizeText: String? {
        let size = viewModel.currentDocument.info.firstPageSize
        guard size.width > 0, size.height > 0 else { return nil }
        return String(format: "%.0f × %.0f pt", size.width, size.height)
    }

    private func toolRow(title: String,
                         subtitle: String,
                         systemImage: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .frame(width: 32, height: 32)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func sessionErrorBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(message)
                .font(.subheadline)
            Spacer()
            Button {
                feature.dismissSessionError()
            } label: {
                Image(systemName: "xmark")
            }
            .accessibilityLabel(BookletLocalization.string("Dismiss"))
        }
        .padding(12)
        .background(.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }
}

/// 工具页的导航目的地。
///
/// ## 为什么必须同步 `selectedTool`
///
/// `BookletMakerMobileFeature.makeContentView()` 按 `workspace.selectedTool`
/// 决定渲染哪个工具页，而该值初值是 `.booklet`。若不先把导航值写进去，点
/// 「Merge PDF」推进去的会是小册子页——入口可点、页面与所点工具不符，
/// 三个工具入口实际只剩一个可用。
///
/// `selectedTool` 的 setter 走 `selectTool(_:)`，它要求 phase 为 `.ready` 或
/// `.resultReady`；概览页正处在这两个状态，因此同步赋值不会被门控挡下。
///
/// 赋值放在 `body` 求值期而非 `onAppear`：后者晚一帧执行，而同一帧里
/// `makeContentView()` 已经被求值过一次，拿到的是旧工具。
private struct ToolDestination: View {
    let tool: MobileWorkspaceState.Tool
    @ObservedObject var feature: BookletMakerMobileFeature
    let onOpenPDF: () -> Void

    var body: some View { destination }

    /// 经 `AnyView` 收敛，让同步赋值与视图构造处在不同的表达式里。
    ///
    /// 直接在 `body` 里先赋值再 `return` 会让 SwiftUI 的 `some View` 推导
    /// 走进编译器缺陷（failed to produce diagnostic），因此把赋值收进一个
    /// 返回具体类型的函数。
    private var destination: AnyView {
        let content = makeToolPage()
        return content
    }

    private func makeToolPage() -> AnyView {
        // 导航值用内部枚举 `MobileWorkspaceState.Tool`，feature 的公开
        // `selectedTool` 用 `BookletMakerMobileFeature.Tool`——两者一一对应
        // 但不是同一类型，需要显式映射。
        feature.selectedTool = switch tool {
        case .booklet: .booklet
        case .split: .split
        case .merge: .merge
        }
        return AnyView(
            feature.makeContentView(onOpenPDF: onOpenPDF)
                .navigationBarTitleDisplayMode(.inline)
                // 工具变化时强制重建，避免复用上一个工具的页面状态。
                .id(tool)
        )
    }
}
#endif
