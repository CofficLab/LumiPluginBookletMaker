import CoreGraphics
import Testing
@testable import BookletMakerCore

@Suite("BookletLayoutEngine")
struct BookletLayoutEngineTests {
    @Test("booklet fold maps four pages in print order")
    func fourPageBooklet() {
        let settings = BookletSettings(layout: .bookletFold)
        let sides = BookletLayoutEngine.buildOutputSides(inputPageCount: 4, settings: settings)

        #expect(sides.map(\.leftPage) == [4, 2])
        #expect(sides.map(\.rightPage) == [1, 3])
        #expect(sides.map(\.side) == [.front, .back])
    }

    @Test("signature fold preserves pages and pads each signature")
    func signatureFold() {
        let settings = BookletSettings(layout: .signatureFold, signaturePageCount: 8)
        let sides = BookletLayoutEngine.buildOutputSides(inputPageCount: 10, settings: settings)
        let printedPages = sides.flatMap { [$0.leftPage, $0.rightPage] }.filter { $0 > 0 }

        #expect(sides.count == 6)
        #expect(Set(printedPages) == Set(1...10))
        #expect(BookletLayoutEngine.signatureCount(inputPageCount: 10, pagesPerSignature: 8) == 2)
        #expect(Set(sides.map(\.signatureIndex)) == [0, 1])
    }

    @Test("geometry fits a source page without changing its aspect ratio")
    func fitRect() {
        let target = CGRect(x: 0, y: 0, width: 200, height: 100)
        let fitted = BookletLayoutEngine.fitRect(aspectRatio: 1, into: target)

        #expect(fitted.width == 100)
        #expect(fitted.height == 100)
        #expect(fitted.midX == target.midX)
        #expect(fitted.midY == target.midY)
    }
}
