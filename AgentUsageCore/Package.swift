// swift-tools-version: 6.2
import PackageDescription

// AgentUsageCore holds everything that can be built and tested without Xcode:
// - AgentUsageCore: models, pace maths, colouring, display models and Snapshot files.
//   Foundation only, with no WidgetKit, AppKit or network code.
// - AgentUsageViews: the SwiftUI widget views, which only draw display models from the core.
// - AgentUsageHostKit: the host app's Accounts, Keychain, Providers, refresh loop and UI.
// - AgentUsageScreenshots: renders the real views with sample Accounts to docs/images/
//   (`scripts/screenshots.sh`). It isn't part of the app.
let package = Package(
    name: "AgentUsageCore",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "AgentUsageCore", targets: ["AgentUsageCore"]),
        .library(name: "AgentUsageViews", targets: ["AgentUsageViews"]),
        .library(name: "AgentUsageHostKit", targets: ["AgentUsageHostKit"]),
    ],
    targets: [
        .target(name: "AgentUsageCore"),
        .target(
            name: "AgentUsageViews",
            dependencies: ["AgentUsageCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .target(
            name: "AgentUsageHostKit",
            dependencies: ["AgentUsageCore", "AgentUsageViews"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "AgentUsageScreenshots",
            dependencies: ["AgentUsageCore", "AgentUsageViews", "AgentUsageHostKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(name: "AgentUsageCoreTests", dependencies: ["AgentUsageCore"]),
        .testTarget(
            name: "AgentUsageHostKitTests",
            dependencies: ["AgentUsageHostKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
