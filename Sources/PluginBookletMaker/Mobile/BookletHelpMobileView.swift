#if os(iOS)
import SwiftUI

/// 帮助与关于：操作指引、隐私说明与应用信息。
///
/// `onOpenGuide` 非空时，每个工具小节底部提供「再看一次引导」入口，
/// 让已经跳过首页引导的用户随时能重看。
struct BookletHelpMobileView: View {
    var onOpenGuide: ((BookletGuideKind) -> Void)?

    var body: some View {
        List {
            Section(BookletLocalization.string("Make a Booklet")) {
                Text(helpBookletText)
                    .font(.footnote)
                if let onOpenGuide {
                    guideButton(
                        BookletLocalization.string("View the booklet guide"),
                        kind: .booklet,
                        action: onOpenGuide
                    )
                }
            }

            Section(BookletLocalization.string("Split a PDF")) {
                Text(helpSplitText)
                    .font(.footnote)
                if let onOpenGuide {
                    guideButton(
                        BookletLocalization.string("View the split guide"),
                        kind: .split,
                        action: onOpenGuide
                    )
                }
            }

            Section(BookletLocalization.string("Merge PDFs")) {
                Text(helpMergeText)
                    .font(.footnote)
                if let onOpenGuide {
                    guideButton(
                        BookletLocalization.string("View the merge guide"),
                        kind: .merge,
                        action: onOpenGuide
                    )
                }
            }

            Section(BookletLocalization.string("Privacy")) {
                Text(privacyText)
                    .font(.footnote)
            }

            Section(BookletLocalization.string("About")) {
                LabeledContent(
                    BookletLocalization.string("App"),
                    value: "BookletMaker"
                )
                LabeledContent(
                    BookletLocalization.string("Version"),
                    value: versionString
                )
            }
        }
        .navigationTitle(BookletLocalization.string("Help"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func guideButton(
        _ title: String,
        kind: BookletGuideKind,
        action: @escaping (BookletGuideKind) -> Void
    ) -> some View {
        Button { action(kind) } label: {
            Label(title, systemImage: "play.rectangle")
                .font(.footnote.weight(.medium))
        }
        .buttonStyle(.plain)
        .foregroundStyle(BookletMobileStyle.accent)
        .accessibilityIdentifier("help.guide.\(kind.rawValue)")
    }

    private var helpBookletText: String {
        // key 必须是完整的单行字面量：字符串拼接会拆成多个片段 key，导致整句查不到翻译。
        BookletLocalization.string(
            "Open a PDF, choose Booklet, and the pages are reordered so two printed sides become one folded sheet. Pick your paper, review the print sides, then export and share the result."
        )
    }

    private var helpSplitText: String {
        BookletLocalization.string(
            "Open a PDF, choose Split PDF, and tap between pages to mark where the file should break. Name each part, then export and share the resulting PDFs."
        )
    }

    private var helpMergeText: String {
        BookletLocalization.string(
            "Choose Merge PDFs, add two or more files, drag them into the order you want, then merge them into a single PDF."
        )
    }

    private var privacyText: String {
        BookletLocalization.string(
            "BookletMaker processes every document locally on your device. No file content is uploaded or stored on any server."
        )
    }

    private var versionString: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(short) (\(build))"
    }
}
#endif
