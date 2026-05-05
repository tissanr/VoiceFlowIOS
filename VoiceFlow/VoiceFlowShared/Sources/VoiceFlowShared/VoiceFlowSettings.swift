import Foundation

public struct VoiceFlowSettings: Codable, Equatable, Sendable {
    public var localeMode: LocaleMode
    public var correctionLevel: CorrectionLevel
    public var autoCopyFallback: Bool
    public var preferOnDeviceSpeech: Bool
    public var allowLLMProcessing: Bool
    public var privacyMode: PrivacyMode

    public init(
        localeMode: LocaleMode = .automatic,
        correctionLevel: CorrectionLevel = .soft,
        autoCopyFallback: Bool = true,
        preferOnDeviceSpeech: Bool = true,
        allowLLMProcessing: Bool = false,
        privacyMode: PrivacyMode = .localOnly
    ) {
        self.localeMode = localeMode
        self.correctionLevel = correctionLevel
        self.autoCopyFallback = autoCopyFallback
        self.preferOnDeviceSpeech = preferOnDeviceSpeech
        self.allowLLMProcessing = allowLLMProcessing
        self.privacyMode = privacyMode
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
