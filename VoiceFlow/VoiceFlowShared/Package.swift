// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "VoiceFlowShared",
    platforms: [
        .iOS(.v17),
        // Only so `swift build` / `swift test` work on macOS CI; the product ships on iOS.
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "VoiceFlowShared",
            targets: ["VoiceFlowShared"]
        ),
        .executable(
            name: "AppGroupStoreSpike",
            targets: ["AppGroupStoreSpike"]
        )
    ],
    targets: [
        .target(name: "VoiceFlowShared"),
        .executableTarget(
            name: "AppGroupStoreSpike",
            dependencies: ["VoiceFlowShared"]
        ),
        .testTarget(
            name: "VoiceFlowSharedTests",
            dependencies: ["VoiceFlowShared"]
        )
    ]
)
