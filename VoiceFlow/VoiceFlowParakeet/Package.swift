// swift-tools-version: 6.2

import PackageDescription

// Parakeet (NVIDIA, via FluidAudio / Core ML) for the containing app only.
// Never link this into VoiceFlowKeyboard: the model is far above the extension memory budget.
let package = Package(
    name: "VoiceFlowParakeet",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "VoiceFlowParakeet", targets: ["VoiceFlowParakeet"])
    ],
    dependencies: [
        .package(path: "../VoiceFlowShared"),
        // ASR only: no TTS, diarization, or NeMo text-normalization binary.
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.18.4", traits: [])
    ],
    targets: [
        .target(
            name: "VoiceFlowParakeet",
            dependencies: [
                "VoiceFlowShared",
                .product(name: "FluidAudio", package: "FluidAudio")
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
