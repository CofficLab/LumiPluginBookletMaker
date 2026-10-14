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

    /// 等待前台就绪且工作区装配完成。
    ///
    /// 供需要自定义启动参数（如注入测试夹具）的场景复用。
    func waitForForegroundAndWorkspace() {
        waitForForeground()
        waitForWorkspace()
    }

    /// 等待被测 App 成为前台应用；超时则明确失败。
    ///
    /// 与 `waitForForeground()` 的区别：这里把「等不到前台」当作失败抛出，
    /// 而不是静默继续。注入测试夹具会让启动变慢，随后的点击若在 App 尚未
    /// 到前台时发出，会得到「not foreground and does not allow background
    /// interaction」这类难以定位的报错——提前失败并给出诊断更省事。
    func waitForForegroundOrFail(
        timeout: TimeInterval = 40,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline,
              NSWorkspace.shared.frontmostApplication?.bundleIdentifier != Self.hostBundleID {
            Thread.sleep(forTimeInterval: 0.2)
        }
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Self.hostBundleID else {
            XCTFail(
                "被测 App 未在 \(Int(timeout))s 内成为前台。"
                    + "当前前台：\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "<none>")",
                file: file,
                line: line
            )
            return
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
    /// 两重稳健性处理：
    /// 1. 首击可能被 macOS 窗口激活竞态吞掉（只激活窗口不切换工具），
    ///    未出现目标视图时重试；
    /// 2. 元素存在但不可点击时（App 尚未真正前台）先激活再重试——否则
    ///    XCTest 直接报「not foreground and does not allow background
    ///    interaction」并放弃，不会给我们重试机会。
    func switchTool(_ identifier: String, expecting anchor: String, timeout: TimeInterval = 20) {
        let tool = element(identifier)
        XCTAssertTrue(
            tool.waitForExistence(timeout: timeout),
            "工具入口 \(identifier) 缺失。\(app.debugDescription)"
        )

        let target = element(anchor)
        for attempt in 0 ..< 3 {
            if attempt > 0 {
                app.activate()
                waitForForegroundOrFail()
                Thread.sleep(forTimeInterval: 1.0)
            }
            if tool.isHittable {
                tool.click()
                if target.waitForExistence(timeout: 6) {
                    return
                }
            } else {
                app.activate()
                Thread.sleep(forTimeInterval: 0.5)
            }
        }

        XCTFail("切换到 \(identifier) 后未出现 \(anchor)。\(app.debugDescription)")
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
