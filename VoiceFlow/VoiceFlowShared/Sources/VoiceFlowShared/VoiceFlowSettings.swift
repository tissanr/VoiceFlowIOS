import Foundation

public struct VoiceFlowSettings: Codable, Equatable, Sendable {
    public var localeMode: LocaleMode
    public var correctionLevel: CorrectionLevel
    public var autoCopyFallback: Bool
    public var preferOnDeviceSpeech: Bool
    public var allowLLMProcessing: Bool
    public var privacyMode: PrivacyMode
    /// Let the keyboard compare text it inserted with the user's later edit and suggest vocabulary.
    public var learnFromKeyboardEdits: Bool
    /// Recognition engine for dictation in the containing app. The keyboard always uses Apple Speech
    /// (Whisper models exceed the extension memory budget).
    public var speechEngine: SpeechEngineKind
    /// Whisper model used when `speechEngine == .whisper`.
    public var whisperModel: WhisperModelVariant

    public init(
        localeMode: LocaleMode = .automatic,
        correctionLevel: CorrectionLevel = .soft,
        autoCopyFallback: Bool = true,
        preferOnDeviceSpeech: Bool = true,
        allowLLMProcessing: Bool = false,
        privacyMode: PrivacyMode = .localOnly,
        learnFromKeyboardEdits: Bool = true,
        speechEngine: SpeechEngineKind = .apple,
        whisperModel: WhisperModelVariant = .largeV3Turbo
    ) {
        self.localeMode = localeMode
        self.correctionLevel = correctionLevel
        self.autoCopyFallback = autoCopyFallback
        self.preferOnDeviceSpeech = preferOnDeviceSpeech
        self.allowLLMProcessing = allowLLMProcessing
        self.privacyMode = privacyMode
        self.learnFromKeyboardEdits = learnFromKeyboardEdits
        self.speechEngine = speechEngine
        self.whisperModel = whisperModel
    }

    /// Tolerates settings saved by older builds: missing keys fall back to defaults.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = VoiceFlowSettings()
        localeMode = try container.decodeIfPresent(LocaleMode.self, forKey: .localeMode) ?? defaults.localeMode
        correctionLevel = try container.decodeIfPresent(CorrectionLevel.self, forKey: .correctionLevel) ?? defaults.correctionLevel
        autoCopyFallback = try container.decodeIfPresent(Bool.self, forKey: .autoCopyFallback) ?? defaults.autoCopyFallback
        preferOnDeviceSpeech = try container.decodeIfPresent(Bool.self, forKey: .preferOnDeviceSpeech) ?? defaults.preferOnDeviceSpeech
        allowLLMProcessing = try container.decodeIfPresent(Bool.self, forKey: .allowLLMProcessing) ?? defaults.allowLLMProcessing
        privacyMode = try container.decodeIfPresent(PrivacyMode.self, forKey: .privacyMode) ?? defaults.privacyMode
        learnFromKeyboardEdits = try container.decodeIfPresent(Bool.self, forKey: .learnFromKeyboardEdits) ?? defaults.learnFromKeyboardEdits
        // `try?`: an engine or model a future build removed falls back to the default instead of failing all settings.
        speechEngine = (try? container.decodeIfPresent(SpeechEngineKind.self, forKey: .speechEngine)) ?? defaults.speechEngine
        whisperModel = (try? container.decodeIfPresent(WhisperModelVariant.self, forKey: .whisperModel)) ?? defaults.whisperModel
    }

    public static let defaults = VoiceFlowSettings()
}

public enum LocaleMode: String, Codable, Equatable, CaseIterable, Sendable {
    case automatic
    case german
    case english
}

public enum CorrectionLevel: String, Codable, Equatable, CaseIterable, Sendable {
    case minimal
    case soft
    case medium
}

public enum PrivacyMode: String, Codable, Equatable, CaseIterable, Sendable {
    case localOnly
    case externalLLMAllowed
}

public enum SpeechEngineKind: String, Codable, Equatable, CaseIterable, Sendable {
    /// `SFSpeechRecognizer`, on-device when the locale supports it.
    case apple
    /// WhisperKit (Core ML), fully on-device. Containing app only.
    case whisper
}

/// WhisperKit model folders from `argmaxinc/whisperkit-coreml`. All are multilingual.
public enum WhisperModelVariant: String, Codable, Equatable, CaseIterable, Sendable {
    case base = "openai_whisper-base"
    case small = "openai_whisper-small"
    case largeV3Turbo = "openai_whisper-large-v3-v20240930_turbo_632MB"

    /// Approximate download size, for the settings UI.
    public var approximateSizeMB: Int {
        switch self {
        case .base: return 150
        case .small: return 480
        case .largeV3Turbo: return 632
        }
    }
}

extension WhisperModelVariant {
    public var displayName: String {
        switch self {
        case .base: return "Base"
        case .small: return "Small"
        case .largeV3Turbo: return "Large v3 Turbo"
        }
    }
}
