import XCTest

/// 拆分（Split）工具在移动端的计划编辑与导出门控。
///
/// 与 macOS 侧栏式交互不同，iOS 的拆分页是「计划 / 原稿」两段切换 +
/// 可纵向滚动的编辑区（批量切分点输入 → 页面网格 → 文件命名）。
///
/// 重点覆盖切分点的选中与反选、批量输入、页面点击与输入框两条路径是否
/// 等价、非法输入校验，以及分段命名——这些是拆分工具最容易出错的地方。
final class BookletMakerMobileSplitUITests: BookletMakerMobileUITestCase {

    override func setUpWithError() throws {
        try super.setUpWithError()
        openSampleDocument()
        switchTool("overview.splitTool", expecting: "split.readingPicker")
    }

    /// 没有切分点时导出按钮禁用。
    ///
    /// 门控是这一层最重要的行为：按钮一直在那里，真正要验证的是
    /// 「还没给出有效切分点时导不出来」。
    func testExportDisabledWithoutCutPoints() {
        assertDisabled("split.export")
    }

    /// 点击页面可在该页之后添加切分点。
    ///
    /// 8 页示例文档点第 2 页应产生两个分段（1-2 / 3-8）。
    func testTappingPageAddsCutPoint() {
        XCTAssertTrue(scrollTo("split.page.2"), app.debugDescription)
        element("split.page.2").tap()
        assertSplitAfter("split.page.2")

        // 一个切分点把文档分成两段，导出门控应打开。
        assertEnabled("split.export")
    }

    /// 再次点击同一页应取消切分点。
    ///
    /// 反选能力是页面点击路径的核心：用户改主意时必须能把标记撤掉，
    /// 否则只能重新载入文档。
    func testTappingSamePageTogglesCutPointOff() {
        XCTAssertTrue(scrollTo("split.page.2"), app.debugDescription)
        element("split.page.2").tap()
        assertSplitAfter("split.page.2")

        // 每次都重新查询元素：切分点变化会触发视图重排，此前缓存的
        // `XCUIElement` 指向旧快照，第二次 tap 会落空——这正是本条最初
        // 稳定失败的原因。
        XCTAssertTrue(scrollTo("split.page.2"), app.debugDescription)
        element("split.page.2").tap()
        assertNotSplitAfter("split.page.2")
    }

    /// 多个切分点彼此独立。
    ///
    /// 三个切分点 → 四个分段。只记「最后一次点击」的实现会让前面的切分点
    /// 被静默丢弃，用户会拿到与预览不符的输出。
    func testMultipleCutPointsAreIndependent() {
        for page in [2, 4] {
            let cell = element("split.page.\(page)")
            XCTAssertTrue(scrollTo("split.page.\(page)"), "缺少第 \(page) 页")
            cell.tap()
        }

        assertSplitAfter("split.page.2")
        assertSplitAfter("split.page.4")
    }

    /// 批量输入框与页面点击两条路径等价。
    ///
    /// 输入「2 4」应与逐个点击第 2、4 页得到相同的分段结构——这是两条独立
    /// 代码路径，历史上出现过一边生效另一边失效的不对称。
    func testBatchInputMatchesPageTaps() {
        let input = element("split.cutPointInput")
        XCTAssertTrue(scrollTo("split.cutPointInput"), app.debugDescription)
        input.tap()
        input.typeText("2, 4")
        // 软键盘会挤走页面下方的单元格，先收起再断言。
        dismissKeyboard()

        assertSplitAfter("split.page.2")
        assertSplitAfter("split.page.4")
    }

    /// 非法输入给出校验提示，且导出门控保持关闭。
    ///
    /// 越界页码会走 `PDFSplitPlan.ValidationError.cutPointOutOfRange`，
    /// 文案由 `BookletLocalization.string(for:)` 从结构化 payload 重组，
    /// 实际输出形如 `Cut points must be between 1 and 7 (found 99).`
    /// （8 页文档的最大合法切分点是第 7 页之后——第 8 页之后切分没有意义）。
    func testInvalidInputShowsValidationAndKeepsExportDisabled() {
        let input = element("split.cutPointInput")
        XCTAssertTrue(scrollTo("split.cutPointInput"), app.debugDescription)
        input.tap()
        input.typeText("99")

        let banner = localizedText("Cut points must be between 1 and 7 (found 99).")
        XCTAssertTrue(
            banner.waitForExistence(timeout: 8),
            "越界页码应给出校验提示。\(app.debugDescription)"
        )

        // 输入非法时不得放行导出——否则会导出一份与预览不符的文件。
        assertDisabled("split.export")
    }

    /// 清空切分点后导出重新禁用。
    ///
    /// 覆盖门控的「双向」：非法输入时禁用之外，合法的删除操作也要能让
    /// 门控回到禁用，否则用户删光切分点却仍能导出空结果。
    func testClearingCutPointsDisablesExportAgain() {
        let input = element("split.cutPointInput")
        XCTAssertTrue(scrollTo("split.cutPointInput"), app.debugDescription)
        input.tap()
        input.typeText("2")
        dismissKeyboard()
        assertEnabled("split.export")

        // 清空后键盘会再次弹出，导出按钮位于底部，先收起再断言门控。
        XCTAssertTrue(scrollTo("split.cutPointInput"), app.debugDescription)
        clearTextField(input)
        dismissKeyboard()
        assertDisabled("split.export")
    }

    /// 分段数量随切分点变化，摘要如实反映。
    func testSummaryReflectsSegmentCount() {
        let emptySummary = element("split.summary")
        XCTAssertTrue(
            emptySummary.waitForExistence(timeout: 10),
            "拆分页缺少结果摘要。\(app.debugDescription)"
        )
        // 无切分点时摘要如实反映「整份文档将作为一个文件输出」，而不是
        // 提示缺配置——文档已就绪，只是还没切。
        XCTAssertEqual(
            text(of: emptySummary), "8 pages \u{2192} 1 files",
            "无切分点时应输出为一个文件"
        )

        // 加一个切分点后摘要切换为「N 页 → M 个文件」。
        XCTAssertTrue(scrollTo("split.page.2"))
        element("split.page.2").tap()

        XCTAssertTrue(
            waitForSummary(to: "8 pages → 2 files"),
            "一个切分点后摘要应为「8 pages → 2 files」，实际为「\(text(of: element("split.summary")))」"
        )
        assertEnabled("split.export")
    }

    /// 「计划 / 原稿」分段切换可用。
    func testReadingSegmentSwitches() {
        assertExists("split.readingPicker")

        let source = app.buttons["Original PDF"]
        XCTAssertTrue(source.waitForExistence(timeout: 10), app.debugDescription)
        source.tap()

        // 切到原稿视图后，编辑区消失但底部摘要与导出按钮仍在。
        XCTAssertTrue(
            element("split.export").waitForExistence(timeout: 10),
            "切到原稿视图后底部操作区消失。\(app.debugDescription)"
        )
    }

    // MARK: - Helpers

    /// 清空一个文本框的全部内容。
    ///
    /// 先尝试系统的「全选 → 删除」；模拟器上菜单项不一定稳定出现，
    /// 因此回退到逐字退格。用 `typeText` 追加内容而非设置 `value`，
    /// 因为后者会绕过 SwiftUI 的 `Binding` 写入而不触发校验。
    private func clearTextField(_ field: XCUIElement, maxLength: Int = 12) {
        field.tap()
        if app.menuItems["Select All"].waitForExistence(timeout: 3) {
            app.menuItems["Select All"].tap()
            field.typeText(XCUIKeyboardKey.delete.rawValue)
            return
        }
        for _ in 0..<maxLength {
            field.typeText(XCUIKeyboardKey.delete.rawValue)
        }
    }

    /// 判断某页是否处于「在此页之后切分」状态。
    ///
    /// 读 accessibilityLabel：它由 `PDFSplitPlanEditorView` 显式拼成
    /// 「Page N, split after this page」/「Page N, no split after this page」，
    /// 是切分状态的直接来源。
    /// 轮询直到某页的切分状态达到期望值，或超时返回 false。
    ///
    /// 必须把「期望状态」显式传进来：只等 `split after` 的话，取消切分点
    /// 的用例会立刻因读到 `no split` 而拿到 false——断言看似通过，实际
    /// 什么都没验证。
    private func waitForSplitState(
        of identifier: String,
        equals expected: Bool,
        timeout: TimeInterval = 5
    ) -> Bool {
        // 先滚动定位：页面网格是 `LazyVGrid`，目标页可能不在视口内，
        // 不滚动就读不到 label。滚动只在轮询之外做，避免两者互相打断。
        _ = scrollTo(identifier, timeout: timeout)

        let deadline = Date().addingTimeInterval(timeout)
        let splitLabel = "split after this page"
        while Date() < deadline {
            let label = element(identifier).label
            // 「no split after this page」本身也包含 "split after this page"，
            // 因此必须先判否定式。
            if label.contains("no " + splitLabel) {
                if !expected { return true }
            } else if label.contains(splitLabel) {
                if expected { return true }
            }
            Thread.sleep(forTimeInterval: 0.3)
        }
        return false
    }

    /// 便捷断言：某页应处于「在此页之后切分」状态。
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

    /// 便捷断言：某页不应处于切分状态。
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
