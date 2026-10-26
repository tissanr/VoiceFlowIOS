import Foundation

@MainActor
public protocol SpeechEngine: AnyObject {
    var delegate: SpeechEngineDelegate? { get set }
    var isRecording: Bool { get }

    func requestPermissions() async throws
    func start(locale: Locale) async throws
    func stop() async throws -> SpeechResult
    func cancel()
}

@MainActor
public protocol SpeechEngineDelegate: AnyObject {
    func speechEngine(_ engine: SpeechEngine, didUpdatePartialText text: String)
    func speechEngine(_ engine: SpeechEngine, didUpdateInputLevel level: Float)
    /// Recording ended without `stop()` (interruption, media-services loss, recognizer error).
    /// `partialText` is whatever was recognized before teardown so the caller never drops it silently.
    func speechEngine(_ engine: SpeechEngine, didEndUnexpectedly error: SpeechEngineError, partialText: String)
}

public struct SpeechResult: Equatable, Sendable {
    public let text: String
    public let localeIdentifier: String
    public let durationMs: Int
    public let isFinal: Bool
    public let recognitionMode: SpeechRecognitionMode

    public init(
        text: String,
        localeIdentifier: String,
        durationMs: Int,
        isFinal: Bool,
        recognitionMode: SpeechRecognitionMode
    ) {
        self.text = text
        self.localeIdentifier = localeIdentifier
        self.durationMs = durationMs
        self.isFinal = isFinal
        self.recognitionMode = recognitionMode
    }
}

public enum SpeechRecognitionMode: String, Codable, Equatable, Sendable {
    case onDevice
    case server
}

public struct SpeechLocaleCapability: Equatable, Sendable {
    public var localeIdentifier: String
    public var isSupported: Bool
    public var isAvailable: Bool
    public var supportsOnDeviceRecognition: Bool

    public init(
        localeIdentifier: String,
        isSupported: Bool,
        isAvailable: Bool,
        supportsOnDeviceRecognition: Bool
    ) {
        self.localeIdentifier = localeIdentifier
        self.isSupported = isSupported
        self.isAvailable = isAvailable
        self.supportsOnDeviceRecognition = supportsOnDeviceRecognition
    }
}

public enum SpeechEngineError: Error, Equatable, Sendable {
    case microphonePermissionDenied
    case speechPermissionDenied
    case localeUnsupported(String)
    case recognizerUnavailable(String)
    case localOnlyUnavailable(String)
    case audioInputUnavailable
    case alreadyRecording
    case notRecording
    case interrupted
    case cancelled
    case recognitionFailed(String)

    /// Whether retrying without changing settings or permissions can plausibly succeed.
    public var isRetryable: Bool {
        switch self {
        case .recognizerUnavailable, .audioInputUnavailable, .interrupted, .cancelled, .recognitionFailed, .alreadyRecording, .notRecording:
            return true
        case .microphonePermissionDenied, .speechPermissionDenied, .localeUnsupported, .localOnlyUnavailable:
            return false
        }
    }
}

public enum SpeechLocaleResolver {
    public static let germanDefault = "de-DE"
    public static let englishDefault = "en-US"

    /// Picks the recognizer locale for a `LocaleMode`.
    /// `supportedIdentifiers` uses BCP-47 style (`de-DE`); underscores are tolerated.
    public static func localeIdentifier(
        for mode: LocaleMode,
        currentLocale: Locale,
        supportedIdentifiers: Set<String>
    ) -> String {
        switch mode {
        case .german:
            return germanDefault
        case .english:
            return englishDefault
        case .automatic:
            break
        }

        let supported = Set(supportedIdentifiers.map(normalize))
        let current = normalize(currentLocale.identifier)

        if supported.contains(current) {
            return current
        }

        let language = current.split(separator: "-").first.map(String.init)?.lowercased()
        if language == "de", supported.contains(germanDefault) {
            return germanDefault
        }
        if language == "en", supported.contains(englishDefault) {
            return englishDefault
        }
        if let language, let match = supported.sorted().first(where: { $0.lowercased().hasPrefix(language + "-") }) {
            return match
        }

        return englishDefault
    }

    static func normalize(_ identifier: String) -> String {
        // Drop calendar / collation keywords such as `de_DE@calendar=gregorian`.
        let base = identifier.split(separator: "@").first.map(String.init) ?? identifier
        return base.replacingOccurrences(of: "_", with: "-")
    }
}

public enum SpeechRecognitionPolicy {
    /// Decides on-device vs. server recognition, or fails before any audio is captured.
    /// Never downgrades to server recognition when the user is in local-only mode.
    public static func recognitionMode(
        for capability: SpeechLocaleCapability,
        settings: VoiceFlowSettings
    ) throws -> SpeechRecognitionMode {
        guard capability.isSupported else {
            throw SpeechEngineError.localeUnsupported(capability.localeIdentifier)
        }

        guard capability.isAvailable else {
            throw SpeechEngineError.recognizerUnavailable(capability.localeIdentifier)
        }

        if capability.supportsOnDeviceRecognition, settings.preferOnDeviceSpeech || settings.privacyMode == .localOnly {
            return .onDevice
        }

        guard settings.privacyMode != .localOnly else {
            throw SpeechEngineError.localOnlyUnavailable(capability.localeIdentifier)
        }

        return .server
    }
}
