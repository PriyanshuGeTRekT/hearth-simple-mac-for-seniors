// swift-tools-version: 6.0
import PackageDescription

let v5: [SwiftSetting] = [.swiftLanguageMode(.v5)]

let package = Package(
    name: "Hearth",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "HearthCore", targets: ["HearthCore"]),
        .executable(name: "Hearth", targets: ["Hearth"]),
    ],
    targets: [
        .target(name: "HearthCore", swiftSettings: v5),
        .executableTarget(name: "Hearth", dependencies: ["HearthCore"], swiftSettings: v5),
        .testTarget(name: "HearthCoreTests", dependencies: ["HearthCore"], swiftSettings: v5),
    ]
)
