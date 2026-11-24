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
        // Containing-app only: Whisper models far exceed the keyboard extension memory ceiling.
        .library(
            name: "VoiceFlowWhisper",
            targets: ["VoiceFlowWhisper"]
        ),
        .executable(
            name: "AppGroupStoreSpike",
            targets: ["AppGroupStoreSpike"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", exact: "1.1.1")
    ],
    targets: [
        .target(name: "VoiceFlowShared"),
        .target(
            name: "VoiceFlowWhisper",
            dependencies: [
                "VoiceFlowShared",
                .product(name: "WhisperKit", package: "WhisperKit")
            ]
        ),
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
