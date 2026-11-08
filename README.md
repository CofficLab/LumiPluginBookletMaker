# LumiPluginBookletMaker

📖 English | [中文版](README_zh.md)

Shared remote Booklet Maker package for Lumi and GameFactory.

## Products

This repository exports two products, corresponding to two layers of responsibility:

| Product | Target | Description |
|---------|--------|------|
| `BookletMakerCore` | `Sources/BookletMakerCore` | Pure domain logic: paper sizes, folding layout engine, split plans. No dependencies on Kernel / Providers / SwiftUI. |
| `PluginBookletMaker` | `Sources/PluginBookletMaker` | Plugin layer: `SuperPlugin` implementation + SwiftUI interface + PDF inspection/rendering/splitting/merging services. |

`BookletMakerCore` retains the semantics of the original repository name, so both hosts' existing `LumiBookletMaker` dependencies can migrate smoothly to this package.

## Host Injection Convention

This package serves two hosts with very different forms (Lumi's multi-plugin workbench and GameFactory's standalone app), so it **hardcodes no host-specific concepts** — everything is injected through `BookletMakerPlugin.init`.

### pluginID

```swift
public nonisolated static let defaultPluginID = "com.coffic.lumi.plugin.booklet-maker"

public init(
    id: String = BookletMakerPlugin.defaultPluginID,
    order: Int = 880,
    policy: PluginEnablePolicy = .disabledByDefault,
    onWorkspaceActivate: VisibilityHook? = nil,
    onWorkspaceDeactivate: VisibilityHook? = nil
)
```

- `id` determines `PluginMetadata.id` and the plugin data directory name; each host uses its own namespace, without interference.
- `order` / `policy` determine load order and enable policy.

### Chat Area Visibility

Lumi presents Booklet Maker as a workbench and needs to collapse the chat area when activated; GameFactory's Booklet Maker is a standalone app with no chat area concept. Hosts inject hooks as needed:

```swift
// Lumi
BookletMakerPlugin(
    id: "com.coffic.lumi.plugin.booklet-maker",
    onWorkspaceActivate: { chatProvider?.setVisible(false) },
    onWorkspaceDeactivate: { chatProvider?.setVisible(true) }
)

// GameFactory
BookletMakerPlugin(
    id: "com.coffic.bookletmaker.plugin.booklet-maker",
    policy: .required
)
```

Without hooks, the plugin still boots and switches layouts normally. See the same approach in `ToastSuperPlugin` for reference.

## Capability Scope

- Booklet imposition: simple fold, saddle stitch, folding signatures, outputting printable PDFs
- PDF splitting: export multiple files by cut points
- PDF merging: merge in a given order
- macOS: NSSavePanel / NSOpenPanel export; iOS: file selection and sharing

This package does **not** contribute tools to the Agent (`pdf_inspect` / `booklet_make` / `pdf_split` / `pdf_merge` / `booklet_preview`) or Skills. The Agent Tools and Skills directories from the original Lumi local package were removed during migration, to avoid introducing host-specific dependencies such as `KitAgentTool` / `ProviderToolManager` / `ProviderSkill`.

## Dependencies

All are remote packages, with no local path dependencies:

- `LumiKernel`
- `LumiProviders`
- `LumiUI`
- `LumiLocalization`
- `LumiLogging`

## Development

```sh
swift build
swift test
```

## Testing

This package includes three layers of tests, all inside the repository, verifiable without an external host project.

| Layer | Location | Count | How to run |
|---|---|---|---|
| Domain layer | `Tests/BookletMakerCoreTests` | swift-testing `@Suite` | `swift test` |
| Plugin layer | `Tests/PluginBookletMakerTests` | 115 XCTest items | `swift test` |
| UI layer | `BookletMakerUITestHost/UITests` | 40 XCUITest items | `xcodebuild test` |

### Unit Tests

```sh
swift test                                   # all
swift test --filter BookletMakerViewModelTests
swift test --enable-code-coverage
```

`BookletLocalizationCatalogTests` is the guard for the localization catalog, hardening four easily-silently-degraded rules into assertions: every key must have a non-empty translation in all five languages, placeholder counts must be consistent across languages and positional placeholders (`%1$@`) must be contiguous, every key referenced in code must exist in the catalog, and `sourceLanguage` must be `en`. Forgetting to maintain the xcstrings when adding new strings fails immediately, rather than waiting for a few untranslated English strings to appear in some language's UI.

### UI Tests

UI tests need a host app and the Xcode test runner, so they are embedded in the repository as an Xcode project (`project.yml` + XcodeGen generation), with no dependency on any host-specific private packages.

```sh
brew install xcodegen          # one-time
./generate-ui-test-project.sh  # generates BookletMakerUITests.xcodeproj
xcodebuild test \
  -project BookletMakerUITests.xcodeproj \
  -scheme BookletMakerUITests \
  -destination 'platform=macOS'
```

`BookletMakerTestHost` is a minimal host app that assembles in the same order as the real host (GameFactory's `BookletMakerApp`): **register Providers → boot plugins → assemble views**. This order must not be reversed: the plugin's `onBoot` registers tabs with the Rail and injects content into the ContentView; assembling views early would leave these areas in an empty state.

Coverage:

| Suite | Coverage |
|---|---|
| `BookletMakerBookletUITests` | four preview stage switches, pre-binding paper list, paper/layout/slider/switch interactions, padding switch forced disabled in book-fold layout, anchors stable across languages |
| `BookletMakerSplitUITests` | cut point selection and deselection, independent multi-cut-points, export gating flips with validity, page-click and sidebar-input paths equivalent, invalid input validation, segment renaming |
| `BookletMakerMergeUITests` | empty queue and export disabled, summary faithfully reflects queue size, mutually exclusive with booklet settings |
| `BookletMakerMergeQueueUITests` | sorting after queue injection (both directions), boundary button disabling, deletion, export gating changes, returning to empty state after clearing |
| `BookletMakerExportPanelUITests` | export panels for the three tools, save/cancel, replace confirmation, UI restoration after panel close |
| `BookletMakerToolSwitchUITests` | sidebar settings and main button copy sync after switching between the three tools |
| `BookletMakerLocalizationUITests` | en / zh-Hans / zh-Hant copy, and unchanged anchor structure after language switch |

#### Two conventions for writing UI tests

1. **Locate elements only via `accessibilityIdentifier`, not copy** — copy changes with localization; identifiers do not. The only exception is `BookletMakerLocalizationUITests`, where using copy is precisely to verify the copy itself.
2. **Assert state, not existence**: an element's existence only means it rendered; what really needs verification is selected state, enabled state, and gating reasons.

#### The form of system panels (save / choose folder) in XCUITest

Export uses `NSSavePanel.runModal()` / `NSOpenPanel.runModal()`; in practice there are a few counterintuitive points:

| Phenomenon | Correct approach |
|---|---|
| The panel hangs under `app.dialogs`, **not** `app.sheets`, nor `app.windows` | `app.dialogs.matching(identifier:)` |
| The panel title is not exposed to XCUITest (`label` is empty, no StaticText children) | Distinguish by identifier instead: `save-panel` / `open-panel` |
| Both panel types' confirm buttons are called `OKButton` | Cannot distinguish panel type by it |
| When the target file already exists, a "replace?" sheet stacks on top | `confirmReplaceIfPresent()`, button is `action-button-1` |
| Querying the underlying UI while the panel is open reports `still interrupting` | Assert after `waitForModalPanelToClose()` |

In addition: the test host **does not enable the sandbox**, while the XCUITest runner has its own sandbox and is isolated from the host process. Therefore export artifacts are written to a directory designated by the host, which the runner can neither read nor clean up — in test mode the host pre-selects its own temporary directory for the panel, to avoid dumping files into the user's folders.

#### On verifying export artifacts

UI tests do **not** assert the content of exported files: artifacts are indeed written correctly, but the runner has no permission to read them, and artifact correctness (page count, segments, file names) is covered by `BookletMakerViewModelTests`. UI tests are only responsible for "the interaction chain runs through completely".

#### An easy pitfall

**Do not put `accessibilityIdentifier` on container views.** SwiftUI pushes ancestors' identifiers down to every leaf element, causing all anchors inside the container to be overwritten by the same value and become unlocatable. This package once made `split.cutPoint.*`, `split.summary`, and `merge.insufficientHint` all fail because of this. If you need to determine whether a region appears, take the anchor on a **leaf element** inside the region.

#### Known differences

The test host uses the public `DefaultRootViewProviding` and assembles the root layout itself, while the real host uses its own root view implementation. The test host does **not** assemble `CommandProviding` and the settings sidebar plugin, so settings-window-related UI is not covered by this suite — that capability comes from host-side packages and cannot be self-verified by the plugin repository.

### iOS UI Tests

The iOS-side UI tests cover the mobile standalone architecture (`BookletMakerMobileRootView` mounted directly, without going through the Kernel Provider). The test project shares `BookletMakerUITests.xcodeproj` with macOS, but the target and host app are completely independent.

```sh
# generate the project (if not already generated)
./generate-ui-test-project.sh

# run iOS UI tests
xcodebuild test \
  -project BookletMakerUITests.xcodeproj \
  -scheme BookletMakerMobileUITests \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

#### Five substantive differences between iOS and macOS tests

1. **No window foreground waiting**: macOS needs `NSWorkspace.frontmostApplication` polling, because the first click can be swallowed by a window-activation race; on iOS the app is foregrounded at launch, so there is no such race.
2. **Tap instead of click**: `XCUIElement.click()` does not exist on iOS.
3. **Scrolling is mandatory**: XCUITest queries are based on the current snapshot; elements beyond the first screen do not exist in the AX tree (not invisible, but **nonexistent**). All existence assertions scroll first, then judge.
4. **Different language injection**: macOS uses `-AppleLanguages`; iOS must also override `AppleLocale`, otherwise system components may still display the host language.
5. **Different system panel forms**: macOS's `NSSavePanel` hangs under `app.dialogs` and can be driven; iOS's `UIDocumentPickerViewController` / `UIActivityViewController` run outside the app's accessibility tree, and XCUITest can neither drive them nor assert their results.

#### iOS test coverage

| Suite | Coverage | Status |
|---|---|---|
| `BookletMakerMobileToolSwitchUITests` | welcome page → overview page → tool page navigation, content correctness after tool switching, closing document back to welcome page | ✅ 5/5 |
| `BookletMakerMobileBookletUITests` | six-stage indicator switching, parameter panel controls, padding switch gating, imposition preview page order, summary text | ✅ 9/9 |
| `BookletMakerMobileSplitUITests` | cut point tap add/remove, batch input, invalid input validation, summary changes with cut points, segment switching | ✅ 9/9 |
| `BookletMakerMobileMergeUITests` | empty queue gating, summary text | ⚠️ 1/6 |

The other 5 merge tests involve queue injection (`-SeedMergeQueue N`), which currently has a timing issue: the host app injects with a delay in `onAppear`, but the timing of tool switching and injection completion is hard to synchronize precisely. The empty queue test passes, verifying the gating logic is correct. Complete merge queue tests need further debugging of the host injection logic or a different test approach (e.g., adding files via manual UI operations, but iOS `fileImporter` cannot be driven by XCUITest).

#### Key technical points for iOS tests

**Scroll handling**: the iOS test base class provides `scrollTo()` and `scrollHorizontallyTo()` methods, automatically handling the visibility issue of off-screen elements. The stage indicator is a horizontal `ScrollView`; only the first two items are within the first screen, the rest need horizontal scrolling.

**Keyboard handling**: after a text field gains focus, the soft keyboard occupies the lower half of the screen, pushing content below out of the hittable area. The test base class's `dismissKeyboard()` collapses the keyboard by tapping the navigation bar title, avoiding impact on subsequent assertions.

**Anchor design**: the iOS-side anchors follow prefixes such as `overview.*` / `booklet.*` / `split.*` / `merge.*` / `welcome.*` / `params.*` / `stage.*`, which do not overlap with the macOS-side anchor system. All anchors are placed on leaf elements, avoiding SwiftUI's identifier push-down issue.

**Selected state assertion**: SwiftUI incorrectly reports `isSelected == true` for elements clipped by a horizontal track. The stage switching tests instead assert "the content presented by that stage" rather than "selected state", working around the trait reporting defect.

#### iOS host assembly

`BookletMakerMobileTestHostApp` mounts `BookletMakerMobileRootView(feature:)` directly, without going through Kernel Provider assembly. This is completely different from the macOS host's "register Providers → boot plugins → assemble views" order, reflecting the architectural characteristics of the iOS standalone app.

Merge queue tests inject test PDFs via the `-SeedMergeQueue N` launch argument. The host app detects this argument and calls `feature.importDocuments(from:)`, which detects the argument and automatically switches to the merge tool, ensuring documents are correctly loaded as a merge queue rather than a single document.

#### Known limitations

1. **Merge queue injection timing**: the host injects with a 1-second delay after `onAppear`, but the timing of tests switching to the merge tool is uncertain, so injection may occur before or after the tool switch. Currently only the empty queue test passes stably.
2. **File picker cannot be automated**: iOS's `fileImporter` presents the system file picker, which XCUITest cannot drive. Therefore all tests requiring file imports rely on host injection or sample documents.
3. **Export panel tests missing**: iOS exports go through `UIActivityViewController` (share sheet) or `fileExporter` (system save dialog), both running outside the app process and unassertable by XCUITest. The correctness of the export chain is covered by unit tests (`BookletMakerViewModelTests`).

