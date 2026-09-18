// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Carpenter",
    defaultLocalization: "en",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "CarpenterKit", targets: ["CarpenterKit"]),
        .library(name: "CarpenterKitTesting", targets: ["CarpenterKitTesting"]),
        .library(name: "CarpenterUI", targets: ["CarpenterUI"]),
        .library(name: "CarpenterKeychain", targets: ["CarpenterKeychain"]),
        .library(name: "CarpenterCloudKit", targets: ["CarpenterCloudKit"]),
        .library(name: "CarpenterApp", targets: ["CarpenterApp"]),
        .library(name: "CarpenterMedia", targets: ["CarpenterMedia"]),
    ],
    targets: [
        .target(
            name: "CarpenterKit",
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "CarpenterKitTesting",
            dependencies: ["CarpenterKit"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "CarpenterCloudKit",
            dependencies: ["CarpenterKit"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "CarpenterKeychain",
            dependencies: ["CarpenterKit"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "CarpenterUI",
            dependencies: ["CarpenterKit", "CarpenterMedia"],
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "CarpenterApp",
            dependencies: ["CarpenterKit"],
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "CarpenterMedia",
            dependencies: ["CarpenterKit"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "CarpenterKitTests",
            dependencies: [
                "CarpenterKit", "CarpenterKitTesting", "CarpenterApp", "CarpenterUI",
                "CarpenterCloudKit", "CarpenterMedia",
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
