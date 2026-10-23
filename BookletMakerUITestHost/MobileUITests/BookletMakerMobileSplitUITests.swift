import XCTest

/// 拆分（Split）工具在移动端的计划编辑与导出门控。
///
/// iOS 的拆分页是「左右滑动浏览相邻两页 → 点中间的剪刀标记切分点」
/// （产品原型 `08-split-plan` / `08-split-plan-swipe`）。切分点标在两页
/// **之间**，因此标识符是 `split.boundary.<页码>`，含义是「在此页之后切」。
///
/// 重点覆盖切分点的选中与反选、滑动翻页、导出门控的双向行为。
final class BookletMakerMobileSplitUITests: BookletMakerMobileUITestCase {

    override func setUpWithError() throws {
        try super.setUpWithError()
        // 主线是「首页工具卡 → 引导页 → 工作台」，没有概览页这一层。
        openSampleDocument(tool: "split")
    }

    /// 没有切分点时导出按钮禁用。
    ///
    /// 门控是这一层最重要的行为：按钮一直在那里，真正要验证的是
    /// 「还没给出有效切分点时导不出来」。
    func testExportDisabledWithoutCutPoints() {
        assertDisabled("split.export")
    }

    /// 点剪刀标记可在该页之后添加切分点。
    ///
    /// 8 页示例文档在第 2 页之后切分，应产生两个分段（1-2 / 3-8）。
    func testTappingScissorsAddsCutPoint() {
        XCTAssertTrue(scrollTo("split.boundary.1"), app.debugDescription)
        element("split.boundary.1").tap()
        assertSplitAfter("split.boundary.1")

        // 一个切分点把文档分成两段，导出门控应打开。
        assertEnabled("split.export")
    }

    /// 再次点击同一处应取消切分点。
    ///
    /// 反选能力是切分点交互的核心：用户改主意时必须能把标记撤掉，
    /// 否则只能重新载入文档。
    func testTappingSameScissorsTogglesCutPointOff() {
        XCTAssertTrue(scrollTo("split.boundary.1"), app.debugDescription)
        element("split.boundary.1").tap()
        assertSplitAfter("split.boundary.1")

        // 每次都重新查询元素：切分点变化会触发视图重排，此前缓存的
        // `XCUIElement` 指向旧快照，第二次 tap 会落空——这正是本条最初
        // 稳定失败的原因。
        XCTAssertTrue(scrollTo("split.boundary.1"), app.debugDescription)
        element("split.boundary.1").tap()
        assertNotSplitAfter("split.boundary.1")

        // 切分点撤掉后导出应重新禁用。
        assertDisabled("split.export")
    }

    /// 多个切分点彼此独立。
    ///
    /// 只记「最后一次点击」的实现会让前面的切分点被静默丢弃，用户会拿到
    /// 与预览不符的输出。
    func testMultipleCutPointsAreIndependent() {
        for page in [1, 3] {
            XCTAssertTrue(scrollTo("split.boundary.\(page)"), "缺少第 \(page) 页后的切分点")
            element("split.boundary.\(page)").tap()
        }

        assertSplitAfter("split.boundary.1")
        assertSplitAfter("split.boundary.3")
    }

    /// 最后一个页面之后不能切分。
    ///
    /// 在最后一页之后切分会产出一个空文件；按钮应当被禁用而不是让用户
    /// 点出空结果。
    func testBoundaryAfterLastPageIsDisabled() {
        // 8 页文档，最后一页是第 8 页。
        XCTAssertTrue(scrollTo("split.boundary.8"), app.debugDescription)
        assertDisabled("split.boundary.8")
    }

    /// 分段摘要随切分点变化，如实反映分段结构。
    func testSummaryReflectsSegmentCount() {
        XCTAssertTrue(
            element("split.summary").waitForExistence(timeout: 10),
            "拆分页缺少结果摘要。\(app.debugDescription)"
        )

        XCTAssertTrue(scrollTo("split.boundary.1"))
        element("split.boundary.1").tap()

        XCTAssertTrue(
            waitForSummary(to: "8 pages → 2 files"),
            "一个切分点后摘要应为「8 pages → 2 files」，"
                + "实际为「\(text(of: element("split.summary")))」。\(app.debugDescription)"
        )
        assertEnabled("split.export")
    }

    // MARK: - Helpers

    /// 判断某处是否处于「在此页之后切分」状态。
    ///
    /// 读 accessibilityLabel：它由 `PDFSplitPlanEditorView` 显式拼成
    /// 「Split after page N」/「Remove split after page N」，是切分状态的
    /// 直接来源。轮询直到达到期望值，或超时返回 false。
    ///
    /// 必须把「期望状态」显式传进来：只等 `split after` 的话，取消切分点
    /// 的用例会立刻因读到 `remove` 而拿到 false——断言看似通过，实际
    /// 什么都没验证。
    private func waitForSplitState(
        of identifier: String,
        equals expected: Bool,
        timeout: TimeInterval = 5
    ) -> Bool {
        // 先滚动定位：页面预览是横向滑动的，目标切分点可能不在视口内，
        // 不滚动就读不到 label。滚动只在轮询之外做，避免两者互相打断。
        _ = scrollTo(identifier, timeout: timeout)

        let deadline = Date().addingTimeInterval(timeout)
        let splitLabel = "split after page"
        let removeLabel = "remove split after page"
        while Date() < deadline {
            let label = element(identifier).label.lowercased()
            if label.contains(removeLabel) {
                if !expected { return true }
            } else if label.contains(splitLabel) {
                if expected { return true }
            }
            Thread.sleep(forTimeInterval: 0.3)
        }
        return false
    }

    /// 便捷断言：某处应处于「在此页之后切分」状态。
    private func assertSplitAfter(
        _ identifier: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(
            waitForSplitState(of: identifier, equals: true),
            "切分状态不符，实际 label 为「\(element(identifier).label)」。\(app.debugDescription)",
            file: file, line: line
        )
    }

    /// 便捷断言：某处不应处于切分状态。
    private func assertNotSplitAfter(
        _ identifier: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(
            waitForSplitState(of: identifier, equals: false),
            "切分状态不符，实际 label 为「\(element(identifier).label)」。\(app.debugDescription)",
            file: file, line: line
        )
    }

    /// 等待摘要文本变成期望值。
    private func waitForSummary(
        to expected: String,
        timeout: TimeInterval = 8
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if text(of: element("split.summary")) == expected { return true }
            Thread.sleep(forTimeInterval: 0.3)
        }
        return false
    }
}
