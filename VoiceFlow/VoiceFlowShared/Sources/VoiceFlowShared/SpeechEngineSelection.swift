import Foundation

/// The user's recognizer preference, stored in `VoiceFlowSettings`.
/// Also stored in `DictationRecord.engine` as the engine that actually ran (never `automatic` there).
public enum SpeechEngineKind: String, Codable, Equatable, CaseIterable, Sendable {
    /// Best engine the current host can run right now (see `SpeechEngineSelection`).
    case automatic
    /// `SFSpeechRecognizer` (iOS 17+). Supports server recognition and custom language models.
    case appleClassic
    /// `SpeechAnalyzer` + `SpeechTranscriber` (iOS 26+), on-device only.
    case appleSpeechAnalyzer
    /// NVIDIA Parakeet via Core ML. Containing app only: far above the keyboard memory budget.
    case parakeet
    /// OpenAI Whisper via WhisperKit / Core ML (model chosen by `VoiceFlowSettings.whisperModel`).
    /// Containing app only.
    case whisper

    /// Raw value earlier builds wrote for `SFSpeechRecognizer`.
    static let legacyAppleRawValue = "apple"

    /// Tolerates values from earlier builds: `"apple"` decodes as `appleClassic`.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        if raw == Self.legacyAppleRawValue {
            self = .appleClassic
            return
        }
        guard let kind = SpeechEngineKind(rawValue: raw) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown speech engine \(raw)"))
        }
        self = kind
    }

    /// Short name for Settings, History, and the Dictate toolbar.
    public var displayName: String {
        switch self {
        case .automatic: return "Automatic"
        case .appleClassic: return "Apple Speech"
        case .appleSpeechAnalyzer: return "Apple SpeechAnalyzer"
        case .parakeet: return "Parakeet"
        case .whisper: return "Whisper"
        }
    }

    /// Engines that need a model bundled by the containing app and never run in the keyboard.
    public var isContainingAppOnly: Bool {
        self == .parakeet || self == .whisper
    }
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
    case whisper

    /// The value stored in `DictationRecord.engine`.
    public var kind: SpeechEngineKind {
        switch self {
        case .appleClassic: return .appleClassic
        case .appleSpeechAnalyzer: return .appleSpeechAnalyzer
        case .parakeet: return .parakeet
        case .whisper: return .whisper
        }
    }
}

/// What the host can run at the moment of dictation.
public struct SpeechEngineAvailability: Equatable, Sendable {
    /// iOS 26+, `SpeechTranscriber.isAvailable`, the locale is supported and its assets are installed.
    public var speechAnalyzerReady: Bool
    /// The containing app supplied an engine for the preferred app-only engine (Parakeet or Whisper).
    public var appEngineReady: Bool

    public init(speechAnalyzerReady: Bool, appEngineReady: Bool) {
        self.speechAnalyzerReady = speechAnalyzerReady
        self.appEngineReady = appEngineReady
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
        case .parakeet, .whisper:
            if host == .containingApp, availability.appEngineReady {
                return preference == .parakeet ? .parakeet : .whisper
            }
            // Keyboard, or models not available: best Apple engine instead.
            return availability.speechAnalyzerReady ? .appleSpeechAnalyzer : .appleClassic
        case .automatic:
            // Never picks an app-only engine: those need an explicit choice and a model download.
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
