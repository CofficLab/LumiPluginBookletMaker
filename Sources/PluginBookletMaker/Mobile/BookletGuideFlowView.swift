#if os(iOS)
import SwiftUI

enum BookletGuideKind: String, Identifiable, Equatable {
    case booklet
    case split

    var id: String { rawValue }
}

struct BookletGuideFlowView: View {
    let kind: BookletGuideKind
    let initialPage: Int
    let onOpenPDF: () -> Void
    let onUseSample: () -> Void
    let onDismiss: () -> Void

    @State private var page: Int

    init(
        kind: BookletGuideKind,
        initialPage: Int = 1,
        onOpenPDF: @escaping () -> Void,
        onUseSample: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.kind = kind
        self.initialPage = initialPage
        self.onOpenPDF = onOpenPDF
        self.onUseSample = onUseSample
        self.onDismiss = onDismiss
        _page = State(initialValue: min(max(initialPage, 1), kind == .booklet ? 2 : 1))
    }

    private var isBooklet: Bool { kind == .booklet }
    private var stepCount: Int { isBooklet ? 6 : 3 }
    private var visibleStep: Int { isBooklet ? page : 1 }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                BookletMobileProgressView(current: visibleStep, total: stepCount)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

                Spacer(minLength: 18)
                illustration
                    .padding(.horizontal, 24)
                Spacer(minLength: 20)

                VStack(alignment: .leading, spacing: 9) {
                    Text(pageTitle)
                        .font(.title2.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(pageDescription)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: 560, alignment: .leading)
                .padding(.horizontal, 26)

                Spacer(minLength: 20)
                actionBar
            }
            .background(BookletMobileStyle.canvas.ignoresSafeArea())
            .navigationTitle(kindTitle)
            .navigationBarTitleDisplayMode(.inline)
        }
        .tint(BookletMobileStyle.accent)
        .interactiveDismissDisabled()
    }

    private var kindTitle: String {
        isBooklet
            ? BookletLocalization.string("Make a Booklet")
            : BookletLocalization.string("Split a PDF")
    }

    private var pageTitle: String {
        if !isBooklet { return BookletLocalization.string("Split a PDF into separate files") }
        return page == 1
            ? BookletLocalization.string("Turn a PDF into a folded booklet")
            : BookletLocalization.string("Ready to make your booklet?")
    }

    private var pageDescription: String {
        if !isBooklet {
            return BookletLocalization.string(
                "Mark page breaks in a document. Each range becomes a separate PDF you can share."
            )
        }
        return page == 1
            ? BookletLocalization.string(
                "Choose a PDF and the app will reorder its pages for double-sided printing. Fold the printed sheets to make a booklet."
            )
            : BookletLocalization.string(
                "Choose a PDF, check the paper and print layout, then export. For best results, test one sheet before printing the whole booklet."
            )
    }

    @ViewBuilder
    private var illustration: some View {
        if isBooklet {
            VStack(spacing: 12) {
                BookletPagePairIllustration(left: "1", right: "4", showsArrow: true)
                Label(BookletLocalization.string("Pages are reordered for printing"), systemImage: "arrow.left.arrow.right")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(BookletMobileStyle.accent)
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(BookletMobileStyle.accent)
                    .frame(width: 84, height: 70)
                    .background(BookletMobileStyle.softAccent, in: RoundedRectangle(cornerRadius: 16))
            }
        } else {
            VStack(spacing: 18) {
                HStack(spacing: 9) {
                    guidePage("1")
                    Image(systemName: "scissors")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(BookletMobileStyle.accent)
                    guidePage("2")
                    guidePage("3")
                }
                Image(systemName: "arrow.down")
                    .foregroundStyle(BookletMobileStyle.accent.opacity(0.65))
                HStack(spacing: 12) {
                    Label(BookletLocalization.string("PDF file 1"), systemImage: "doc.text")
                    Label(BookletLocalization.string("PDF file 2"), systemImage: "doc.text")
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(BookletMobileStyle.accent)
            }
            .frame(maxWidth: .infinity)
            .padding(22)
            .background(BookletMobileStyle.softAccent, in: RoundedRectangle(cornerRadius: 18))
        }
    }

    private func guidePage(_ number: String) -> some View {
        Text(number)
            .font(.headline)
            .foregroundStyle(BookletMobileStyle.paperInk)
            .frame(width: 52, height: 72)
            .background(.white, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(.black.opacity(0.12), lineWidth: 0.7))
            .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
    }

    @ViewBuilder
    private var actionBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    if isBooklet && page > 1 {
                        page = 1
                    } else {
                        onDismiss()
                    }
                } label: {
                    Label(
                        isBooklet && page > 1
                            ? BookletLocalization.string("Previous")
                            : BookletLocalization.string("Close"),
                        systemImage: isBooklet && page > 1 ? "chevron.left" : "xmark"
                    )
                }
                .buttonStyle(.bordered)

                if isBooklet && page == 1 {
                    Button { page = 2 } label: {
                        Label(BookletLocalization.string("Next"), systemImage: "arrow.right")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("guide.next")
                } else {
                    Button(action: onOpenPDF) {
                        Label(BookletLocalization.string("Open PDF"), systemImage: "folder")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("guide.openPDF")
                }
            }

            if !isBooklet || page > 1 {
                Button(action: onUseSample) {
                    Label(BookletLocalization.string("Use Sample PDF"), systemImage: "book")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("guide.useSample")
            }
        }
        .controlSize(.large)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
        .frame(maxWidth: 680)
        .frame(maxWidth: .infinity)
    }
}
#endif
