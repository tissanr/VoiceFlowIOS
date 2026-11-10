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

    public init(
        localeMode: LocaleMode = .automatic,
        correctionLevel: CorrectionLevel = .soft,
        autoCopyFallback: Bool = true,
        preferOnDeviceSpeech: Bool = true,
        allowLLMProcessing: Bool = false,
        privacyMode: PrivacyMode = .localOnly,
        learnFromKeyboardEdits: Bool = true
    ) {
        self.localeMode = localeMode
        self.correctionLevel = correctionLevel
        self.autoCopyFallback = autoCopyFallback
        self.preferOnDeviceSpeech = preferOnDeviceSpeech
        self.allowLLMProcessing = allowLLMProcessing
        self.privacyMode = privacyMode
        self.learnFromKeyboardEdits = learnFromKeyboardEdits
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
