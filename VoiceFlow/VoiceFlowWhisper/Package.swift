// swift-tools-version: 5.9

import PackageDescription

// Whisper (WhisperKit / Core ML) for the containing app only.
// Never link this into VoiceFlowKeyboard: the models are far above the extension memory budget.
let package = Package(
    name: "VoiceFlowWhisper",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "VoiceFlowWhisper", targets: ["VoiceFlowWhisper"])
    ],
    dependencies: [
        .package(path: "../VoiceFlowShared"),
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", exact: "1.1.1")
    ],
    targets: [
        .target(
            name: "VoiceFlowWhisper",
            dependencies: [
                "VoiceFlowShared",
                .product(name: "WhisperKit", package: "WhisperKit")
            ]
        )
    ]
)
