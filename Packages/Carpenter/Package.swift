// swift-tools-version: 6.2
import PackageDescription

let swiftSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .treatWarning("UnnecessaryEffectMarker", as: .error),
]

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
            swiftSettings: swiftSettings
        ),
        .target(
            name: "CarpenterKitTesting",
            dependencies: ["CarpenterKit"],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "CarpenterCloudKit",
            dependencies: ["CarpenterKit"],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "CarpenterKeychain",
            dependencies: ["CarpenterKit"],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "CarpenterUI",
            dependencies: ["CarpenterKit", "CarpenterMedia"],
            resources: [.process("Resources")],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "CarpenterApp",
            dependencies: ["CarpenterKit"],
            resources: [.process("Resources")],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "CarpenterMedia",
            dependencies: ["CarpenterKit"],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "CarpenterKitTests",
            dependencies: [
                "CarpenterKit", "CarpenterKitTesting", "CarpenterApp", "CarpenterUI",
                "CarpenterCloudKit", "CarpenterMedia",
            ],
            swiftSettings: swiftSettings
        ),
    ]
)
