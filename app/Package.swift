// swift-tools-version: 6.2
import Foundation
import PackageDescription
let testsPath = "Tests/NotProtonAppTests"
let payloadPath = "Sources/NotProtonApp/Resources/payload"
let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let hasTests = FileManager.default.fileExists(
    atPath: packageRoot.appendingPathComponent(testsPath).path)

// make app-payload stages the payload, so a checkout that has not been built does
// not have it. A declared resource that is missing is a build error, while an app
// missing the payload is a condition InstallPayload already reports.
let hasPayload = FileManager.default.fileExists(
    atPath: packageRoot.appendingPathComponent(payloadPath).path)
let package = Package(
    name: "NotProtonApp",
    platforms: [.macOS("26.0")],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
    ],
    targets: [
        .target(
            name: "NotProtonSettings",
            path: "Sources/NotProtonSettings",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "notproton-settings",
            dependencies: ["NotProtonSettings"],
            path: "Sources/notproton-settings",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "NotProtonApp",
            dependencies: [.product(name: "Sparkle", package: "Sparkle"), "NotProtonSettings"],
            path: "Sources/NotProtonApp",
            resources: (hasPayload ? [.copy("Resources/payload")] : []) + [
                .copy("Resources/payload.manifest"),
                .copy("Resources/valve-packages.manifest"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ] + (hasTests ? [
        .testTarget(
            name: "NotProtonAppTests",
            dependencies: ["NotProtonApp", "NotProtonSettings"],
            path: testsPath
        ),
    ] : [])
)
