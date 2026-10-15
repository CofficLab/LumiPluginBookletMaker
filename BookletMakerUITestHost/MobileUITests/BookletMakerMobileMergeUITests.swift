import XCTest

/// 合并（Merge）工具在移动端的文件列表、摘要与导出门控。
///
/// 移动端没有 macOS 侧栏那套独立面板，文件列表直接占据整个屏幕。
/// 重点覆盖：摘要随文件变化实时更新、导出按钮在 1 个文件时禁用 2 个时启用、
/// 文件重排与删除后摘要与门控同步刷新。
///
/// ## 关键设计决策
///
/// 宿主应用在启动时（onAppear）检查 `-SeedMergeQueue N` 参数，如果存在则延迟 1 秒后
/// 注入合并队列。feature 的 `importDocuments` 方法会检测到该参数并自动切换到合并工具，
/// 确保文档被正确加载为合并队列而不是单个文档。
///
/// 测试流程：
/// 1. 启动应用（传入 `-SeedMergeQueue N` 参数）
/// 2. 打开示例文档
/// 3. 切换到合并工具
/// 4. 等待 1.5 秒让宿主完成注入
/// 5. 断言合并队列内容
///
/// 文件注入通过宿主的 `-SeedMergeQueue N` 启动参数完成：iOS 上 `fileImporter`
/// 是系统面板，XCUITest 无法驱动，因此测试必须由宿主直接调用 feature 的
/// 导入接口预填充队列。
final class BookletMakerMobileMergeUITests: BookletMakerMobileUITestCase {

    override func setUpWithError() throws {
        // 不调用 super.setUpWithError()，避免默认启动导致欢迎页消失。
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        app = nil
    }

    /// 启动应用、打开示例文档、切换到合并工具，等待注入完成。
    private func launchAndPrepareMerge(arguments: [String] = []) {
        launchApp(language: "en", locale: "en_US", arguments: arguments)

        // 应用可能停在欢迎页（无参数）或文档就绪状态（有参数）。
        // 如果是欢迎页，先打开示例文档。
        let welcomeButton = element("welcome.useSample")
        if welcomeButton.waitForExistence(timeout: 3) {
            welcomeButton.tap()
            _ = element("overview.bookletTool").waitForExistence(timeout: 10)
        }

        // 切换到合并工具。宿主应用会在视图出现时自动注入队列。
        switchTool("overview.mergeTool", expecting: "merge.summary")

        // 等待注入完成（异步操作）。
        // 宿主在 onAppear 后延迟 1 秒注入，这里等待 1.5 秒确保注入完成。
        Thread.sleep(forTimeInterval: 1.5)
    }

    /// 文件列表与摘要同步反映宿主注入的文件。
    ///
    /// 宿主启动参数 `-SeedMergeQueue 3` 注入 3 份 PDF（页数 1、2、3），摘要
    /// 应为「3 files · 6 pages」。摘要不随队列变化而刷新是合并工具最常见的
    /// 回归——它依赖 `mergeDocuments` 的 `@Published` 与视图的绑定。
    func testSummaryReflectsSeededQueue() {
        launchAndPrepareMerge(arguments: ["-SeedMergeQueue", "3"])

        assertExists("merge.fileList")

        let summary = text(of: element("merge.summary"))
        XCTAssertTrue(
            summary.contains("3 files") && summary.contains("6 pages"),
            "摘要应反映 3 个文件共 6 页，实际为「\(summary)」。\(app.debugDescription)"
        )
    }

    /// 只有一个文件时导出禁用，两个及以上时启用。
    ///
    /// 合并必须至少两个文件才有意义——这是业务约束，不是技术限制。门控失效
    /// 会让用户点「Merge」后导出一份单文件 PDF，看起来像是合并功能坏了。
    func testExportGateRequiresAtLeastTwoFiles() {
        // 注入 1 个文件。
        launchAndPrepareMerge(arguments: ["-SeedMergeQueue", "1"])
        assertDisabled("merge.export")

        // 重新启动，注入 2 个文件。
        launchAndPrepareMerge(arguments: ["-SeedMergeQueue", "2"])
        assertEnabled("merge.export")
    }

    /// 空队列时导出禁用，摘要显示「0 files」。
    func testEmptyQueueDisablesExportAndShowsZeroSummary() {
        // 不传入 `-SeedMergeQueue`，应用停在欢迎页。
        launchAndPrepareMerge(arguments: [])

        assertDisabled("merge.export")

        let summary = text(of: element("merge.summary"))
        XCTAssertTrue(
            summary.contains("0 files"),
            "空队列摘要应显示 0 files，实际为「\(summary)」。\(app.debugDescription)"
        )
    }

    /// 文件重排后摘要与门控保持不变。
    ///
    /// 重排不应改变文件数量与总页数——这是 `moveMergeDocuments` 的不变式。
    /// 若重排意外触发删除或复制，摘要会变化，导出门控也可能失效。
    func testReorderDoesNotChangeSummaryOrGate() {
        launchAndPrepareMerge(arguments: ["-SeedMergeQueue", "3"])

        let before = text(of: element("merge.summary"))
        assertEnabled("merge.export")

        // 第一个文件向上拖动（在列表顶部无法再上移，因此向下拖第二个）。
        let secondFile = element("merge.file.1")
        if secondFile.exists {
            let thirdFile = element("merge.file.2")
            if thirdFile.exists {
                secondFile.press(forDuration: 0.5)
                thirdFile.adjust(toNormalizedSliderPosition: 0.3)
            }
        }

        // 重排后摘要应与之前完全一致。
        let after = text(of: element("merge.summary"))
        XCTAssertEqual(
            before, after,
            "重排不应改变摘要。\(app.debugDescription)"
        )
        assertEnabled("merge.export")
    }

    /// 删除一个文件后摘要减少，门控随队列规模变化。
    ///
    /// 删除通过 List 的 swipe action 触发：向左滑动文件行，点击「Remove」按钮。
    /// 这是 iOS 上最标准的删除交互，也是视图里 `swipeActions` 修饰符的直接体现。
    func testDeleteReducesSummaryAndMayDisableGate() {
        launchAndPrepareMerge(arguments: ["-SeedMergeQueue", "3"])

        assertExists("merge.file.0")
        let before = text(of: element("merge.summary"))
        XCTAssertTrue(before.contains("3 files"), "初始应有 3 个文件")

        // 向左滑动第一个文件触发删除。
        let firstFile = element("merge.file.0")
        firstFile.swipeLeft()

        // 删除按钮是 swipe action，AX 里表现为 Button。
        let removeButton = app.buttons["Remove"]
        XCTAssertTrue(
            removeButton.waitForExistence(timeout: 5),
            "左滑后应出现 Remove 按钮。\(app.debugDescription)"
        )
        removeButton.tap()

        // 等待摘要更新：删除是异步的，需轮询。
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            let current = text(of: element("merge.summary"))
            if current.contains("2 files") { break }
            Thread.sleep(forTimeInterval: 0.3)
        }

        let after = text(of: element("merge.summary"))
        XCTAssertTrue(
            after.contains("2 files") && after.contains("5 pages"),
            "删除一个文件后摘要应为 2 files · 5 pages，实际为「\(after)」。\(app.debugDescription)"
        )

        // 还剩 2 个文件，导出应仍可用。
        assertEnabled("merge.export")
    }

    /// 删除到只剩 1 个文件后导出禁用。
    ///
    /// 这是门控的边界条件：从 2 个删到 1 个，必须重新检查 `canExportMerge`。
    /// 若门控只在初始加载时检查一次，删除后仍会保持启用——用户能点 Merge 但
    /// 实际不会导出任何内容。
    func testDeleteDownToOneFileDisablesExport() {
        launchAndPrepareMerge(arguments: ["-SeedMergeQueue", "3"])

        // 先删到 2 个。
        let firstFile = element("merge.file.0")
        firstFile.swipeLeft()
        app.buttons["Remove"].tap()

        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if text(of: element("merge.summary")).contains("2 files") { break }
            Thread.sleep(forTimeInterval: 0.3)
        }

        // 再删一个，剩 1 个。
        let newFirst = element("merge.file.0")
        newFirst.swipeLeft()
        let remove = app.buttons["Remove"]
        XCTAssertTrue(
            remove.waitForExistence(timeout: 5),
            "第二次左滑后应出现 Remove 按钮。\(app.debugDescription)"
        )
        remove.tap()

        // 等待摘要更新到 1 个文件。
        while Date() < deadline {
            if text(of: element("merge.summary")).contains("1 file") { break }
            Thread.sleep(forTimeInterval: 0.3)
        }

        let summary = text(of: element("merge.summary"))
        XCTAssertTrue(
            summary.contains("1 file"),
            "删除到 1 个文件，实际为「\(summary)」。\(app.debugDescription)"
        )

        // 关键断言：只剩 1 个文件时导出必须禁用。
        assertDisabled("merge.export")
    }
}
