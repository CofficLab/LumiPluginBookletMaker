#if os(iOS)
import SwiftUI

/// 拆分工具移动端页面：拆分计划与原稿阅读分段切换，
/// 底部为结果摘要与生成/取消操作。
struct PDFSplitMobileView: View {
    @ObservedObject var viewModel: BookletMakerViewModel
    let onExport: () -> Void

    @State private var readingSegment: ReadingSegment = .plan

    enum ReadingSegment: String, CaseIterable, Identifiable {
        case plan = "plan"
        case source = "source"

        var id: String { rawValue }

        var title: String {
            switch self {
            case .plan: BookletLocalization.string("Split Plan")
            case .source: BookletLocalization.string("Original PDF")
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker(BookletLocalization.string("View"), selection: $readingSegment) {
                ForEach(ReadingSegment.allCases) { segment in
                    Text(segment.title).tag(segment)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("split.readingPicker")
            .padding(.horizontal, 16)
            .padding(.top, 8)

            Divider()

            switch readingSegment {
            case .plan:
                PDFSplitPlanEditorView(viewModel: viewModel)
            case .source:
                SourcePDFReadingView(document: viewModel.currentDocument)
            }

            Divider()

            bottomBar
        }
        .navigationTitle(viewModel.currentDocument.baseFileName)
        // 关键：让整页忽略键盘安全区。
        //
        // 默认情况下 SwiftUI 会把键盘遮挡区域从安全区里扣掉，而底部
        // 操作栏高度固定、内容区又要让位给键盘，中间那块最终被压成 0 高
        // ——实测键盘弹出后 `ScrollView` 的 frame 高度为 0（内容仍有
        // 900+ pt），页面网格全部无法命中：用户输完切分点看不到任何反馈，
        // 也无法再点击页面增删切分点。忽略键盘安全区后内容区保持原高，
        // 滚动依然可用。
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        VStack(spacing: 8) {
            if viewModel.isBusy {
                busyView
            } else {
                HStack(spacing: 12) {
                    summaryText
                    Spacer()
                    Button(action: onExport) {
                        Label(BookletLocalization.string("Split"), systemImage: "scissors")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!viewModel.canExportSplit)
                    .accessibilityIdentifier("split.export")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    @ViewBuilder
    private var summaryText: some View {
        if viewModel.splitSegments.isEmpty {
            Text(BookletLocalization.string("Add at least one split"))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("split.summary")
        } else {
            Text(BookletLocalization.string(
                "%lld pages → %lld files",
                Int64(viewModel.currentDocument.pageCount),
                Int64(viewModel.splitSegments.count)
            ))
            .font(.footnote)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .accessibilityIdentifier("split.summary")
        }
    }

    private var busyView: some View {
        VStack(spacing: 8) {
            ProgressView(value: viewModel.progress)
            HStack {
                Text(viewModel.isCancelling
                     ? BookletLocalization.string("Cancelling…")
                     : BookletLocalization.string("Generating…"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
                if !viewModel.isCancelling {
                    Button(BookletLocalization.string("Cancel")) {
                        viewModel.cancel()
                    }
                    .font(.footnote)
                }
            }
        }
    }
}
#endif
