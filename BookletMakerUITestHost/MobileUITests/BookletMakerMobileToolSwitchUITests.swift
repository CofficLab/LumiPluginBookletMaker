import XCTest

/// 三个 PDF 工具（booklet / split / merge）之间的切换行为。
///
/// 移动端的工具切换与 macOS 结构不同：macOS 是侧栏里换设置面板，iOS 是从
/// 文档概览页 `NavigationLink` **推入**工具页。因此这里验证的是
/// 「推入后工具页的锚点正确、返回后概览页完好」，而不是「设置面板同步」。
///
/// 概览页作为三个工具的共同父级，每次切换都必须先退回概览页——否则第二次
/// 点入口会点在已经处于栈顶的工具页里，锚点根本找不到。
final class BookletMakerMobileToolSwitchUITests: BookletMakerMobileUITestCase {

    override func setUpWithError() throws {
        try super.setUpWithError()
        openSampleDocument()
    }

    /// 三个工具入口都存在，且逐个进入后能看到各自工具页的专属锚点。
    ///
    /// 这条覆盖「工具入口与目标页的对应关系」——入口点得进去但落到错误的页，
    /// 或者某个入口缺失，都是真实的可用性缺陷。
    func testEveryToolEntryOpensItsOwnPage() {
        switchTool("overview.bookletTool", expecting: "booklet.readingPicker")
        assertExists("booklet.export")
        backToOverview()

        switchTool("overview.splitTool", expecting: "split.readingPicker")
        assertExists("split.export")
        assertNotExists("booklet.export")
        backToOverview()

        switchTool("overview.mergeTool", expecting: "merge.summary")
        assertExists("merge.addPDFs")
        assertNotExists("split.export")
    }

    /// 每个工具页的主操作按钮文案跟随工具变化。
    ///
    /// 这条专门防「切到合并工具却仍显示『Make Booklet』」这类回归。
    func testPrimaryActionTitleFollowsTool() {
        switchTool("overview.mergeTool", expecting: "merge.summary")
        XCTAssertTrue(
            localizedText("Merge").exists,
            "合并工具下主按钮应为「Merge」。\(app.debugDescription)"
        )
        XCTAssertFalse(
            localizedText("Make Booklet").exists,
            "合并工具下不应残留小册子导出文案。\(app.debugDescription)"
        )

        backToOverview()
        switchTool("overview.splitTool", expecting: "split.readingPicker")
        XCTAssertTrue(
            localizedText("Split").exists,
            "拆分工具下主按钮应为「Split」。\(app.debugDescription)"
        )
        XCTAssertFalse(
            localizedText("Merge").exists,
            "拆分工具下不应残留合并文案。\(app.debugDescription)"
        )

        backToOverview()
        switchTool("overview.bookletTool", expecting: "booklet.readingPicker")
        XCTAssertTrue(
            localizedText("Make Booklet").exists,
            "小册子工具下主按钮应为「Make Booklet」。\(app.debugDescription)"
        )
    }

    /// 内置示例文档使所有工具在无需文件选择器的前提下即可用。
    ///
    /// 这条覆盖「工具页在有文档时确实可操作」，而非空文档下的门控：
    /// 空文档的禁用态由各工具自己的套件验证。
    ///
    /// 这是 UI 测试覆盖其余交互路径的前提：iOS 上文件导入走
    /// `fileImporter`，其 `UIDocumentPickerViewController` 在 App 的 AX 树
    /// 之外运行，XCUITest 无法驱动。
    func testSampleDocumentEnablesEveryTool() {
        switchTool("overview.bookletTool", expecting: "booklet.readingPicker")
        assertEnabled("booklet.export")
        backToOverview()

        switchTool("overview.splitTool", expecting: "split.readingPicker")
        // 拆分页本身可达，且页面结构完整。导出按钮此刻应为禁用——
        // 示例文档虽已打开，但还没有任何切分点。
        assertExists("split.export")
        assertDisabled("split.export")
    }

    /// 从工具页返回概览页后，概览页仍然可用。
    ///
    /// 返回后若概览页已损坏，用户就再也进不去其他工具——这是导航栈上的
    /// 单向故障，比「返回失败」本身更严重。
    func testReturningFromToolRestoresOverview() {
        switchTool("overview.splitTool", expecting: "split.readingPicker")
        backToOverview()

        // 概览页完好：三个入口都还在，且能再次进入。
        assertExists("overview.bookletTool")
        assertExists("overview.splitTool")
        assertExists("overview.mergeTool")
        switchTool("overview.mergeTool", expecting: "merge.summary")
    }

    /// 关闭当前文档回到欢迎页。
    ///
    /// 走概览页右上角的文档菜单。这条覆盖「会话可以真正结束」——否则用户
    /// 一旦打开文件就再也回不到欢迎页，只能重启 App。
    func testClosingDocumentReturnsToWelcome() {
        assertNotExists("welcome.useSample")

        // 概览页的文档菜单位于导航栏右上角。
        let menuButton = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(menuButton.waitForExistence(timeout: 10), app.debugDescription)
        menuButton.tap()

        let closeItem = app.buttons["Close Current PDF"]
        XCTAssertTrue(closeItem.waitForExistence(timeout: 10), app.debugDescription)
        closeItem.tap()

        XCTAssertTrue(
            element("welcome.useSample").waitForExistence(timeout: 10),
            "关闭文档后未回到欢迎页。\(app.debugDescription)"
        )
    }
}
