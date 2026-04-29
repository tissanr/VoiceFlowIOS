// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "VoiceFlowShared",
    platforms: [
        .iOS(.v17)
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
