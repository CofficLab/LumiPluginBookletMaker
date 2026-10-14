import XCTest

/// BookletMaker 插件 UI 测试基类。
///
/// 统一处理启动、macOS 窗口激活竞态与锚点查询，让各测试文件只关心被测行为。
///
/// 两条关键约定：
/// 1. **只用 `accessibilityIdentifier` 定位元素**，不用文案。标识随语言切换保持
///    稳定，文案则会被本地化改动打断。
/// 2. **断言状态而非存在性**。元素存在只说明渲染了，不代表功能可用；真正要
///    校验的是选中态、启用态、门控原因这些用户能感知的行为。
class BookletMakerUITestCase: XCTestCase {
    var app: XCUIApplication!

    /// 被测宿主 App 的 bundle id，用于等待其真正成为前台应用。
    private static let hostBundleID = "com.coffic.bookletmaker.testhost"

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
    func launchApp(language: String, locale: String) {
        app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(\(language))", "-AppleLocale", locale,
            "-ApplePersistenceIgnoreState", "YES",
        ]
        app.launch()
        #if os(macOS)
        waitForForeground()
        waitForWorkspace()
        #endif
    }

    #if os(macOS)
    /// 等待被测 App 成为前台应用。
    ///
    /// `activate()` 是异步的：App 未到前台时，对窗口内控件的首次点击只会把
    /// 窗口激活而不送达控件（交互静默失败）。必须等到真正 frontmost。
    private func waitForForeground() {
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline,
              NSWorkspace.shared.frontmostApplication?.bundleIdentifier != Self.hostBundleID {
            Thread.sleep(forTimeInterval: 0.2)
        }
    }

    /// 等待插件工作区完成装配并激活。
    ///
    /// 以侧栏工具入口作为「装配完成」的信号：只有插件 `onBoot` 注册了
    /// ActivityBar 条目、且激活闭包跑完（Rail/工具栏就绪）后它才会出现。
    func waitForWorkspace() {
        let tool = element("overview.bookletTool")
        XCTAssertTrue(
            tool.waitForExistence(timeout: 30),
            "插件工作区未在超时内完成装配。\(app.debugDescription)"
        )
    }
    #endif

    // MARK: - Element Query

    /// 按 `accessibilityIdentifier` 查找元素（首选方式）。
    func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(identifier: identifier)
            .firstMatch
    }

    /// 断言元素处于某状态，比较 `value` 与 `label` 两个属性。
    ///
    /// macOS AX 树里 StaticText 的文本走 `value`，Button 的走 `label`，
    /// 同一个 `.accessibilityValue` 修饰符落到不同控件上暴露的属性也不同，
    /// 因此两个属性都要检查。
    func hasValue(_ element: XCUIElement, _ expected: String, timeout: TimeInterval = 5) -> Bool {
        let predicate = NSPredicate(format: "value == %@ OR label == %@", expected, expected)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    /// 读取元素承载的文本，`value` 优先、`label` 兜底。
    func text(of element: XCUIElement) -> String {
        if let value = element.value as? String, !value.isEmpty { return value }
        return element.label
    }

    /// 点击工具入口，并等待切换后的目标视图出现。
    ///
    /// 首击可能被 macOS 窗口激活竞态吞掉（只激活窗口不切换工具），
    /// 因此未出现目标视图时重试一次。
    func switchTool(_ identifier: String, expecting anchor: String, timeout: TimeInterval = 15) {
        let tool = element(identifier)
        XCTAssertTrue(
            tool.waitForExistence(timeout: timeout),
            "工具入口 \(identifier) 缺失。\(app.debugDescription)"
        )
        tool.click()

        let target = element(anchor)
        if !target.waitForExistence(timeout: 5) {
            tool.click()
        }
        XCTAssertTrue(
            target.waitForExistence(timeout: timeout),
            "切换到 \(identifier) 后未出现 \(anchor)。\(app.debugDescription)"
        )
    }

    /// 断言工具入口处于选中态。
    func assertSelected(_ identifier: String, file: StaticString = #filePath, line: UInt = #line) {
        let tool = element(identifier)
        XCTAssertTrue(
            hasValue(tool, "selected"),
            "工具 \(identifier) 应为选中态。\(app.debugDescription)",
            file: file,
            line: line
        )
    }

    /// 断言匹配文案的元素存在，用于验证本地化结果（唯一允许用文案的场景）。
    func localizedText(_ value: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@ OR value == %@", value, value))
            .firstMatch
    }
}
