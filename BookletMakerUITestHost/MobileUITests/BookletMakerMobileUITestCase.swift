import XCTest

/// BookletMaker 移动端 UI 测试基类。
///
/// 与 macOS 基类（`BookletMakerUITestCase`）是两套独立代码，不共享实现：
/// 两个平台的装配路径、导航结构、锚点体系与系统面板形态都不同，共用只会
/// 让两边都被迫写成平台分支的最小公倍数。这里只沿用同样的**约定**：
///
/// 1. **只用 `accessibilityIdentifier` 定位元素**，不用文案。标识随语言切换
///    保持稳定，文案则会被本地化改动打断。
/// 2. **断言状态而非存在性**。元素存在只说明渲染了，不代表功能可用；真正要
///    校验的是选中态、启用态、门控原因这些用户能感知的行为。
///
/// ## 与 macOS 基类的五处实质差异
///
/// 1. **无窗口前台等待**：macOS 需要 `NSWorkspace.frontmostApplication` 轮询，
///    因为首次点击会被窗口激活竞态吞掉；iOS 上 App 启动即为前台，没有这个竞态。
/// 2. **点击用 tap 而非 click**：`XCUIElement.click()` 在 iOS 上不存在。
/// 3. **必须滚动**：XCUITest 查询基于当前快照，元素不在视口内时行为与平台
///    相关（见下方两个滚动小节）。所有存在性断言都先滚动再判断。
/// 4. **语言注入方式不同**：macOS 用 `-AppleLanguages`；iOS 还需一并覆盖
///    `AppleLocale`，否则系统组件仍可能显示宿主语言。
/// 5. **系统面板形态不同**：macOS 的 `NSSavePanel` 挂在 `app.dialogs` 下可驱动；
///    iOS 的 `UIDocumentPickerViewController` / `UIActivityViewController` 在
///    App 的辅助功能树之外运行，XCUITest 既无法驱动也无法断言其结果。因此
///    导出与文件导入类断言在本平台不做，详见各测试文件的头部说明。
class BookletMakerMobileUITestCase: XCTestCase {
    var app: XCUIApplication!

    /// 被测宿主 App 的 bundle id。
    static let hostBundleID = "com.coffic.bookletmaker.mobile.testhost"

    /// 阶段指示器的数量，对应 `BookletStage.allCases`。
    static let stageCount = 6

    override func setUpWithError() throws {
        continueAfterFailure = false
        launchApp(language: "en", locale: "en_US")
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Launch

    /// 以指定语言启动宿主 App。
    ///
    /// 语言通过 `-AppleLanguages` / `-AppleLocale` 注入而非依赖 CI 主机设置，
    /// 使本地化测试在任何机器上结果一致。
    func launchApp(
        language: String,
        locale: String,
        arguments: [String] = []
    ) {
        app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(\(language))", "-AppleLocale", locale,
        ] + arguments
        app.launch()
    }

    // MARK: - Element Query

    /// 按 `accessibilityIdentifier` 查找元素（首选方式）。
    func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(identifier: identifier)
            .firstMatch
    }

    /// 读取元素承载的文本，`value` 优先、`label` 兜底。
    func text(of element: XCUIElement) -> String {
        if let value = element.value as? String, !value.isEmpty { return value }
        return element.label
    }

    // MARK: - Scrolling (vertical)

    /// 纵向滚动直到目标锚点进入视口且可点击。
    ///
    /// ## 为什么必须显式滚动
    ///
    /// XCUITest 的元素查询基于**当前快照**，未渲染进屏幕的 `List` 行在 AX 树里
    /// 根本不存在——不是不可见，是不存在。因此概览页的「Merge PDF」入口
    /// （第三行）在 iPhone 尺寸下首屏放不下时，`exists` 恒为 `false`，
    /// 而界面本身完全正常。
    ///
    /// 这与 macOS 不同：桌面端侧栏固定铺开，锚点不会因尺寸而消失。直接照搬
    /// 桌面的「断言存在性」写法会在移动端产生假失败。
    ///
    /// ## 为什么对容器 `swipeUp()` 而不是坐标拖动
    ///
    /// 页面里存在嵌套滚动容器（预览区 `ScrollView` 套 `LazyVGrid`）。实测
    /// 坐标拖动会被外层容器吞掉——拖动前后目标元素的 frame 完全不变；而对
    /// 滚动容器本身调用 `swipeUp()` 则正常生效。因此统一走 `swipeUp()`，
    /// 滚过头时用 `swipeDown()` 回找。
    ///
    /// - Parameters:
    ///   - identifier: 目标锚点。
    ///   - forward: 首次滑动方向；滚过头时会自动反向回找。
    /// - Returns: 是否在超时内滚动到了目标。
    @discardableResult
    func scrollTo(
        _ identifier: String,
        forward: Bool = true,
        timeout: TimeInterval = 15
    ) -> Bool {
        let target = element(identifier)
        let deadline = Date().addingTimeInterval(timeout)
        var goingForward = forward

        while Date() < deadline {
            if target.exists && target.isHittable { return true }
            if target.exists && !target.isHittable {
                // 存在但被遮挡：多半滚过头了，反向回找。
                goingForward = !goingForward
            }
            swipeScrollView(forward: goingForward)
            Thread.sleep(forTimeInterval: 0.6)
        }
        return target.exists
    }

    /// 对当前最内层滚动容器执行一次滑动。
    ///
    /// 取 `boundBy: count - 1`：实测页面里外层与内层容器同时存在，最内层
    /// 才是承载目标内容的那一个。
    ///
    /// ## 键盘弹出时不要在这里滑动
    ///
    /// 切分点输入框获得焦点后，若目标元素落在键盘遮挡区（`exists == true`
    /// 但 `isHittable == false`），本方法会进入滑动重试——而在文本框上
    /// 向下滑是 iOS 的**撤销手势**，刚输入的内容会被静默清掉。实测输入
    /// 「2, 4」后触发一次滑动，页面标签就从 `split after this page`
    /// 变回 `no split`：看起来像功能坏了，实际是测试自己撤销了输入。
    ///
    /// 因此**读状态不需要滚动**：页面网格在键盘弹出时依然完整存在于 AX
    /// 树里（这正是 `.ignoresSafeArea(.keyboard)` 带来的），只读不点即可。
    /// 需要点击时，先 ``dismissKeyboard()``。
    private func swipeScrollView(forward: Bool) {
        let scrollViews = app.scrollViews
        guard scrollViews.count > 0 else {
            // 没有滚动容器时退回全窗口滑动。
            if forward { app.swipeUp() } else { app.swipeDown() }
            return
        }
        let innermost = scrollViews.element(boundBy: scrollViews.count - 1)
        if forward {
            innermost.swipeUp()
        } else {
            innermost.swipeDown()
        }
    }

    // MARK: - Scrolling (horizontal)

    /// 横向滚动直到目标锚点**完全落入窗口**。
    ///
    /// 阶段指示器（`stage.1` … `stage.6`）是一条横向 `ScrollView`。两个实测
    /// 出来的坑决定了这里的写法：
    ///
    /// 1. **越界元素依然 `exists`**：SwiftUI 的横向轨道会保留屏幕外元素的
    ///    快照——`stage.5` / `stage.6` 的 x 超出屏宽（402pt）却仍可查询到。
    ///    因此不能用 `exists` 判断是否需要滚动。
    /// 2. **越界元素不可点击**：点它会抛 "Activation point invalid and no
    ///    suggested hit points based on element frame"。必须先滚到元素几何上
    ///    完全落入窗口，再点击。
    ///
    /// 实现上先连续右滑回到轨道起点，再逐步左滑推进，每步检查目标是否已进入
    /// 窗口内侧。回到起点这一步是必要的：若沿用上一步遗留的滚动位置，
    /// `stage.1` 可能已被推到屏幕左侧之外而点击失败。
    ///
    /// - Returns: 是否在超时内把目标滚动到了可点击位置。
    @discardableResult
    func scrollHorizontallyTo(_ identifier: String, timeout: TimeInterval = 20) -> Bool {
        let target = element(identifier)
        let deadline = Date().addingTimeInterval(timeout)

        func isFullyVisible() -> Bool {
            guard target.exists else { return false }
            let frame = target.frame
            guard frame.width > 0, frame.height > 0 else { return false }
            let window = app.windows.element(boundBy: 0).frame
            // 留 2pt 余量，避免恰好贴边时命中判定失败。
            return frame.minX >= window.minX + 2
                && frame.maxX <= window.maxX - 2
        }

        func track() -> XCUIElement? {
            let scrollViews = app.scrollViews
            // 横向阶段轨道是最外层容器（索引 0），纵向内容区在内层。
            return scrollViews.count > 0 ? scrollViews.element(boundBy: 0) : nil
        }

        // 回到轨道起点：连续右滑，直到目标可见或滑不动。
        for _ in 0..<5 {
            if isFullyVisible() { return true }
            guard let track = track() else { break }
            track.swipeRight()
            Thread.sleep(forTimeInterval: 0.35)
        }

        // 从起点逐步向右推进。
        while Date() < deadline {
            if isFullyVisible() { return true }
            guard let track = track() else { break }
            track.swipeLeft()
            Thread.sleep(forTimeInterval: 0.45)
        }
        return isFullyVisible()
    }

    // MARK: - Keyboard

    /// 收起软键盘。
    ///
    /// 文本框获得焦点后软键盘占据屏幕下半部分，被它盖住的元素虽然仍在
    /// AX 树里（`exists == true`），但 `isHittable == false`，直接 tap 会
    /// 落到键盘上。页面已加 `.ignoresSafeArea(.keyboard)`，因此键盘弹出
    /// 时内容区依然完整、可以滚动——这里只需收起键盘即可恢复正常交互。
    func dismissKeyboard() {
        guard app.keyboards.count > 0 else { return }

        // 在 XCUITest 里收键盘最稳的三招，按可靠性依次尝试：
        //
        // 1. 点键盘上的「return」键：单行文本框（如切分点输入框）会提交并
        //    自动收起键盘；多行则插入换行，但对切分点这种纯数字输入无副作用。
        // 2. `XCUIKeyboardKey.return`：上面失败时的兜底，按键名发送。
        // 3. 点导航栏标题：SwiftUI 不会因点击空白收键盘，但解除焦点后键盘
        //    自身可能在几帧后收起。作为最后手段。
        //
        // 实测 SwiftUI 不会因点击分段控件或空白区域而收起键盘——那些都是
        // 早期尝试留下的注释，避免后人重走弯路。
        let returnKey = app.keys["Return"]
        if returnKey.exists {
            returnKey.tap()
        } else {
            // 部分键盘把 return 显示为其他标签（"Go"、"Done" 等），统一走
            // `XCUIKeyboardKey.return` 发送，XCUITest 会自行映射。
            app.typeText(XCUIKeyboardKey.return.rawValue)
        }

        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline, app.keyboards.count > 0 {
            Thread.sleep(forTimeInterval: 0.2)
        }
        Thread.sleep(forTimeInterval: 0.4)
    }

    // MARK: - Navigation

    /// 从文档概览页进入指定工具页。
    ///
    /// 移动端的工具入口是 `PDFDocumentOverviewView` 上的 `NavigationLink`，
    /// 因此「切换工具」实际是「点入口 + 等目标页出现」。每次都重新查询元素：
    /// 导航过程中旧快照会失效。
    func switchTool(
        _ identifier: String,
        expecting anchor: String,
        timeout: TimeInterval = 25,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let target = element(anchor)

        // 入口可能位于首屏之外，必须先滚动到它再点。
        guard scrollTo(identifier, timeout: timeout) else {
            XCTFail(
                "工具入口 \(identifier) 缺失或不可点击。\(app.debugDescription)",
                file: file, line: line
            )
            return
        }

        let deadline = Date().addingTimeInterval(timeout)
        var lastError: Error?
        while Date() < deadline {
            let tool = element(identifier)
            guard tool.exists else {
                swipeScrollView(forward: true)
                Thread.sleep(forTimeInterval: 0.6)
                continue
            }
            do {
                try tool.tap()
                if target.waitForExistence(timeout: 6) { return }
            } catch {
                // 元素在点击瞬间失效（页面切换导致）：记下来，稍后重试。
                lastError = error
            }
            Thread.sleep(forTimeInterval: 1.0)
        }

        let reason = lastError.map { "最后一次失败：\($0.localizedDescription)" } ?? ""
        XCTFail(
            "进入 \(identifier) 后未出现 \(anchor)。\(reason)\(app.debugDescription)",
            file: file, line: line
        )
    }

    /// 用内置示例 PDF 打开文档，停在文档概览页。
    ///
    /// 概览页是所有工具测试的共同起点：真实使用中用户先选文件，再从概览页
    /// 进入某个工具。示例文档是插件内置的，不需要文件选择器介入。
    func openSampleDocument(timeout: TimeInterval = 20) {
        let button = element("welcome.useSample")
        guard button.waitForExistence(timeout: timeout) else {
            XCTFail("欢迎页未在超时内出现。\(app.debugDescription)")
            return
        }
        button.tap()
        _ = element("overview.bookletTool").waitForExistence(timeout: timeout)
    }

    /// 返回文档概览页。
    ///
    /// 用导航栏的返回按钮：概览页始终是工具页的父级，因此从任何工具页
    /// 都能一次退回。找不到返回按钮说明已在概览页，直接返回。
    func backToOverview(file: StaticString = #filePath, line: UInt = #line) {
        let overview = element("overview.bookletTool")
        if overview.exists { return }

        // 第一个导航栏按钮即「返回」。
        let backButton = app.navigationBars.buttons.element(boundBy: 0)
        guard backButton.waitForExistence(timeout: 10) else {
            XCTFail(
                "既不在概览页，也找不到返回按钮。\(app.debugDescription)",
                file: file, line: line
            )
            return
        }
        backButton.tap()
        XCTAssertTrue(
            overview.waitForExistence(timeout: 10),
            "返回后未回到文档概览页。\(app.debugDescription)",
            file: file, line: line
        )
    }

    // MARK: - Assertions

    /// 断言元素处于启用态（可交互）。
    func assertEnabled(
        _ identifier: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard scrollTo(identifier) else {
            XCTFail("元素 \(identifier) 不存在。\(app.debugDescription)", file: file, line: line)
            return
        }
        XCTAssertTrue(
            element(identifier).isEnabled,
            "\(identifier) 应为启用态。\(app.debugDescription)",
            file: file, line: line
        )
    }

    /// 断言元素处于禁用态。
    ///
    /// 门控（能否导出）是这三套工具最核心的行为，比存在性重要得多：
    /// 按钮一直在那里，真正要验证的是「不该能导出时导出不了」。
    func assertDisabled(
        _ identifier: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard scrollTo(identifier) else {
            XCTFail("元素 \(identifier) 不存在。\(app.debugDescription)", file: file, line: line)
            return
        }
        XCTAssertFalse(
            element(identifier).isEnabled,
            "\(identifier) 应为禁用态。\(app.debugDescription)",
            file: file, line: line
        )
    }

    /// 断言元素存在（含必要的滚动）。
    ///
    /// 会先滚动查找再断言，因此调用方不必关心锚点是否落在首屏之外。
    func assertExists(
        _ identifier: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(
            scrollTo(identifier),
            "元素 \(identifier) 应存在（已滚动查找）。\(app.debugDescription)",
            file: file, line: line
        )
    }

    /// 断言元素不存在。
    func assertNotExists(
        _ identifier: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let target = element(identifier)
        XCTAssertFalse(
            target.exists,
            "元素 \(identifier) 不应存在。\(app.debugDescription)",
            file: file, line: line
        )
    }

    /// 断言匹配文案的元素存在，用于验证本地化结果（唯一允许用文案的场景）。
    func localizedText(_ value: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@ OR value == %@", value, value))
            .firstMatch
    }
}
