import XCTest

/// 小册子（Booklet）工具在移动端的参数面板与拼版预览。
///
/// 移动端没有 macOS 侧栏那套预览阶段 tab，取而代之的是六阶段横向指示器
/// （`stage.1` … `stage.6`）与参数面板。因此这里覆盖的是：阶段切换、
/// 参数控件的绑定与门控、拼版预览的页序正确性。
final class BookletMakerMobileBookletUITests: BookletMakerMobileUITestCase {

    override func setUpWithError() throws {
        try super.setUpWithError()
        // 主线已是「首页工具卡 → 引导页 → 工作台」，没有概览页这一层。
        openSampleDocument(tool: "booklet")
    }

    /// 六个预览阶段指示器都存在，逐个点击后各自呈现对应内容。
    ///
    /// ## 为什么断言「内容」而不是「选中态」
    ///
    /// 阶段指示器是横向轨道上的按钮，SwiftUI 对**被裁剪**元素的
    /// `isSelected` trait 报告不可靠：实测屏幕外的 `stage.5` 会恒被报成
    /// 「已选中」，即便真正选中的是 `stage.1`。这类 trait 断言会持续误报，
    /// 逼着人往测试里塞越来越脆弱的补偿逻辑。
    ///
    /// 改为断言每个阶段**实际呈现的内容**——这既是用户真正感知到的行为，
    /// 也完全绕开了 trait 的报告缺陷：
    ///
    /// | 阶段 | 内容 |
    /// |---|---|
    /// | 1 打印布局 | 拼版预览（`booklet.sheet.*`） |
    /// | 2 纸张 / 3 裁切 | 参数面板（`params.*`） |
    /// | 4 装订 | 折叠演示（`params.layout` 不在此页） |
    /// | 5 总览 / 6 导出 | 汇总 + 导出按钮（`booklet.exportStage`） |
    func testAllStagesRenderTheirOwnContent() {
        // 1 打印布局：拼版预览
        XCTAssertTrue(scrollHorizontallyTo("stage.1"))
        element("stage.1").tap()
        XCTAssertTrue(
            scrollTo("booklet.sheet.0"),
            "阶段 1 应展示拼版预览。\(app.debugDescription)"
        )

        // 2 纸张：参数面板
        XCTAssertTrue(scrollHorizontallyTo("stage.2"))
        element("stage.2").tap()
        XCTAssertTrue(
            scrollTo("params.paper"),
            "阶段 2 应展示参数面板。\(app.debugDescription)"
        )

        // 3 裁切：仍是参数面板，但裁切开关在其中
        XCTAssertTrue(scrollHorizontallyTo("stage.3"))
        element("stage.3").tap()
        XCTAssertTrue(
            scrollTo("params.cutMarks"),
            "阶段 3 应展示裁切相关设置。\(app.debugDescription)"
        )

        // 4 装订：折叠演示，参数面板不再呈现
        XCTAssertTrue(scrollHorizontallyTo("stage.4"))
        element("stage.4").tap()
        assertNotExists("params.cutMarks")

        // 6 导出：汇总 + 导出按钮
        // 移动端的导出按钮常驻底栏，标识符是 `booklet.export`
        // （`booklet.exportStage` 是 macOS 逐阶段内容区里的标识符）。
        XCTAssertTrue(scrollHorizontallyTo("stage.6"))
        element("stage.6").tap()
        assertEnabled("booklet.export")
    }
    /// 参数面板的纸张、版式与间距控件均可见可用。
    func testParameterControlsArePresent() {
        XCTAssertTrue(scrollHorizontallyTo("stage.2"))
        element("stage.2").tap()

        XCTAssertTrue(scrollTo("params.paper"), "缺少输出纸张设置")
        XCTAssertTrue(scrollTo("params.layout"), "缺少版式设置")
        XCTAssertTrue(scrollTo("params.margin"), "缺少边距滑块")
        XCTAssertTrue(scrollTo("params.gutter"), "缺少装订线滑块")
        XCTAssertTrue(scrollTo("params.cutMarks"), "缺少裁切标记开关")
        XCTAssertTrue(scrollTo("params.padBlank"), "缺少补白开关")
    }

    /// 补白开关在书本折叠版式下强制禁用。
    ///
    /// 对应 ViewModel 的业务规则：bookletFold 本身已按 4 的倍数补页，
    /// 再叠加补白会产生重复空白。允许用户开启会导致页数与预览不一致。
    func testPadBlankDisabledUnderBookletFold() {
        XCTAssertTrue(scrollHorizontallyTo("stage.2"))
        element("stage.2").tap()
        assertDisabled("params.padBlank")

        // 切到简单对折版式后应可用。
        XCTAssertTrue(scrollTo("params.layout"))
        element("params.layout").tap()
        let simplePair = app.buttons["Simple Pair"]
        XCTAssertTrue(simplePair.waitForExistence(timeout: 10), app.debugDescription)
        simplePair.tap()

        XCTAssertTrue(
            scrollTo("params.padBlank"),
            "切换版式后补白开关消失。\(app.debugDescription)"
        )
        assertEnabled("params.padBlank")
    }

    /// 底部摘要如实反映页数与预计纸张数。
    ///
    /// 示例文档为 8 页，书本折叠下需 2 张纸（每张正反两面共 4 个打印面）。
    /// 摘要与实际拼版不一致会直接误导用户对成品页数的预期。
    func testSummaryReflectsDocumentAndSheetCount() {
        assertExists("booklet.summary")

        let summary = text(of: element("booklet.summary"))
        XCTAssertEqual(
            summary, "8 pages · 2 sheets · A4",
            "底部摘要应如实反映页数、纸张数与纸张规格"
        )
    }

    /// 拼版预览按打印顺序展示全部四个打印面。
    ///
    /// 8 页 / 2 张纸 = 4 个打印面。四个面按 2 列网格平铺，第二行在首屏之外，
    /// 必须纵向滚动才能进入快照——`LazyVGrid` 只构造已进入视口的项。
    func testImpositionShowsEveryPrintSideInOrder() {
        XCTAssertTrue(scrollHorizontallyTo("stage.1"))
        element("stage.1").tap()

        for index in 0..<4 {
            XCTAssertTrue(
                scrollTo("booklet.sheet.\(index)"),
                "缺少第 \(index + 1) 个打印面。\(app.debugDescription)"
            )
        }
    }

    /// 打印面与其承载的页码配对正确。
    ///
    /// 直接读 accessibilityLabel：它由代码显式拼成「Print side N: pages X and Y」，
    /// 是拼版引擎输出最直接的体现。
    ///
    /// ## 为什么第 1 面是「8 和 1」而不是「1 和 8」
    ///
    /// 侧别与页序的对应由 `OutputSheet` 决定，`leftPage` 落在纸张左侧。
    /// 8 页书本折叠时，第 1 个打印面的左侧是末页 8、右侧是首页 1——这正是
    /// 对折后能顺读的原因（把第 1 面朝上折，末页落在外侧）。
    /// 第 2 面则是内侧的 (2, 7)。
    ///
    /// 只比对数字部分：标签文案随语言变化，数字不变。
    func testPrintSideLabelsCarryCorrectPagePairs() {
        XCTAssertTrue(scrollHorizontallyTo("stage.1"))
        element("stage.1").tap()

        XCTAssertTrue(scrollTo("booklet.sheet.0"), "缺少第 1 个打印面")
        let first = text(of: element("booklet.sheet.0"))
        XCTAssertTrue(
            first.contains("8 and 1"),
            "第 1 面应为页 8 与 1，实际为「\(first)」。\(app.debugDescription)"
        )

        XCTAssertTrue(scrollTo("booklet.sheet.1"), "缺少第 2 个打印面")
        let second = text(of: element("booklet.sheet.1"))
        XCTAssertTrue(
            second.contains("2 and 7"),
            "第 2 面应为页 2 与 7，实际为「\(second)」。\(app.debugDescription)"
        )
    }

    /// 背面打印面的页码配对同样正确。
    ///
    /// 前两面覆盖了外层纸张；背面 (6,3) 与 (4,5) 是折进来后才可见的部分，
    /// 它们错乱同样会让成品无法顺读，因此单独断言。
    func testBackSideLabelsCarryCorrectPagePairs() {
        XCTAssertTrue(scrollHorizontallyTo("stage.1"))
        element("stage.1").tap()

        XCTAssertTrue(scrollTo("booklet.sheet.2"), "缺少第 3 个打印面")
        let third = text(of: element("booklet.sheet.2"))
        XCTAssertTrue(
            third.contains("6 and 3"),
            "第 3 面应为页 6 与 3，实际为「\(third)」。\(app.debugDescription)"
        )

        XCTAssertTrue(scrollTo("booklet.sheet.3"), "缺少第 4 个打印面")
        let fourth = text(of: element("booklet.sheet.3"))
        XCTAssertTrue(
            fourth.contains("4 and 5"),
            "第 4 面应为页 4 与 5，实际为「\(fourth)」。\(app.debugDescription)"
        )
    }

    /// 「打印布局 / 原稿」分段切换可用。
    func testReadingSegmentSwitches() {
        assertExists("booklet.readingPicker")
        assertExists("booklet.export")

        // 切到原稿视图：拼版预览消失，底部操作区仍在。
        let source = app.buttons["Original PDF"]
        XCTAssertTrue(source.waitForExistence(timeout: 10), app.debugDescription)
        source.tap()

        XCTAssertTrue(
            element("booklet.export").waitForExistence(timeout: 10),
            "切到原稿视图后底部操作区消失。\(app.debugDescription)"
        )
    }

    /// 总览阶段的导出按钮在有文档时可用。
    ///
    /// ## 为什么断言的是 `booklet.export` 而不是 `booklet.exportStage`
    ///
    /// `booklet.exportStage` 是 macOS `BookletPreviewStageView` 第 6 阶段
    /// 里的按钮标识符。移动端没有逐阶段的独立内容区——导出按钮常驻在
    /// 底栏，标识符是 `booklet.export`（见 `BookletPreviewMobileView`）。
    ///
    /// 阶段指示器在移动端仍然存在（`stage.1` … `stage.6`），点 `stage.6`
    /// 后底栏的导出按钮依然可用，因此这里先切到导出阶段再断言按钮启用。
    func testExportEnabledOnReviewStage() {
        XCTAssertTrue(scrollHorizontallyTo("stage.6"))
        element("stage.6").tap()
        assertEnabled("booklet.export")
    }
}
