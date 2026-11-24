import Foundation

/// The user's recognizer preference, stored in `VoiceFlowSettings`.
public enum SpeechEngineKind: String, Codable, Equatable, CaseIterable, Sendable {
    /// Best engine the current host can run right now (see `SpeechEngineSelection`).
    case automatic
    /// `SFSpeechRecognizer` (iOS 17+). Supports server recognition and custom language models.
    case appleClassic
    /// `SpeechAnalyzer` + `SpeechTranscriber` (iOS 26+), on-device only.
    case appleSpeechAnalyzer
    /// NVIDIA Parakeet via Core ML. Containing app only: far above the keyboard memory budget.
    case parakeet
}

/// The process that records. The Keyboard Extension has a ~48 MB ceiling and must never load
/// bundled ASR models (see docs/specs/performance-and-memory.md).
public enum SpeechEngineHost: Equatable, Sendable {
    case keyboardExtension
    case containingApp
}

/// The engine that actually runs for one dictation.
public enum ResolvedSpeechEngine: Equatable, Sendable {
    case appleClassic
    case appleSpeechAnalyzer
    case parakeet
}

/// What the host can run at the moment of dictation.
public struct SpeechEngineAvailability: Equatable, Sendable {
    /// iOS 26+, `SpeechTranscriber.isAvailable`, the locale is supported and its assets are installed.
    public var speechAnalyzerReady: Bool
    /// Parakeet models are downloaded and the host may load them.
    public var parakeetReady: Bool

    public init(speechAnalyzerReady: Bool, parakeetReady: Bool) {
        self.speechAnalyzerReady = speechAnalyzerReady
        self.parakeetReady = parakeetReady
    }
}

public enum SpeechEngineSelection {
    /// Picks the engine for one dictation. Never fails: anything not ready falls back to
    /// `appleClassic`, which exists on every supported iOS version.
    public static func resolve(
        preference: SpeechEngineKind,
        settings: VoiceFlowSettings,
        host: SpeechEngineHost,
        availability: SpeechEngineAvailability
    ) -> ResolvedSpeechEngine {
        // SpeechAnalyzer and Parakeet are on-device only. If the user explicitly allows server
        // recognition and does not prefer on-device, keep the classic engine for `automatic`.
        let wantsServer = !settings.preferOnDeviceSpeech && settings.privacyMode != .localOnly

        switch preference {
        case .appleClassic:
            return .appleClassic
        case .appleSpeechAnalyzer:
            return availability.speechAnalyzerReady ? .appleSpeechAnalyzer : .appleClassic
        case .parakeet:
            if host == .containingApp, availability.parakeetReady {
                return .parakeet
            }
            // Keyboard, or models not downloaded: best Apple engine instead.
            return availability.speechAnalyzerReady ? .appleSpeechAnalyzer : .appleClassic
        case .automatic:
            guard !wantsServer else { return .appleClassic }
            return availability.speechAnalyzerReady ? .appleSpeechAnalyzer : .appleClassic
        }
    }
}

/// Joins the finalized and volatile segments a streaming recognizer reports.
/// Pure so it can be tested without the Speech framework.
public struct TranscriptAccumulator: Equatable, Sendable {
    public private(set) var finalizedText = ""
    public private(set) var volatileText = ""

    public init() {}

    /// Full text so far: finalized segments plus the latest volatile guess.
    public var text: String {
        Self.join(finalizedText, volatileText)
    }

    /// A final segment is appended and clears the volatile guess it replaces;
    /// a volatile segment replaces the previous volatile guess.
    public mutating func apply(_ segment: String, isFinal: Bool) {
        if isFinal {
            finalizedText = Self.join(finalizedText, segment)
            volatileText = ""
        } else {
            volatileText = segment
        }
    }

    static func join(_ head: String, _ tail: String) -> String {
        let trimmedTail = tail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTail.isEmpty else { return head }
        let trimmedHead = head.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHead.isEmpty else { return trimmedTail }
        return trimmedHead + " " + trimmedTail
    }
}
