// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LumiBookletMaker",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(
            name: "BookletMakerCore",
            targets: ["BookletMakerCore"]
        ),
    ],
    targets: [
        .target(
            name: "BookletMakerCore"
        ),
        .testTarget(
            name: "BookletMakerCoreTests",
            dependencies: ["BookletMakerCore"]
        ),
    ]
)
