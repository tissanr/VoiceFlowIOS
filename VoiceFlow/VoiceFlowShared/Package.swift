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
        )
    ],
    targets: [
        .target(name: "VoiceFlowShared"),
        .testTarget(
            name: "VoiceFlowSharedTests",
            dependencies: ["VoiceFlowShared"]
        )
    ]
)
