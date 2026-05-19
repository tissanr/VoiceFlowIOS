#if os(iOS)
import Foundation

/// Events emitted by a SpeechEngine during a recording session.
public enum SpeechEvent: Sendable {
    case partial(transcript: String)
    case final(transcript: String)
    case interrupted(partialTranscript: String?)
    case failed(Error)
}

/// Protocol for speech recognition engines. All methods run on the main actor.
@MainActor
public protocol SpeechEngine: AnyObject {
    /// Requests microphone and speech-recognition permissions.
    func requestPermissions() async throws

    /// Starts recording and recognition. Calls `onEvent` on the main actor as results arrive.
    func start(locale: Locale, onEvent: @escaping @MainActor (SpeechEvent) -> Void) async throws

    /// Signals end-of-audio. The final `.final` or `.failed` event arrives via `onEvent`.
    func stop()

    /// Cancels immediately and discards any partial transcript.
    func cancel()

    var isRecording: Bool { get }
}

public enum SpeechEngineError: LocalizedError {
    case microphonePermissionDenied
    case speechPermissionDenied
    case recognizerUnavailable(String)
    case recognizerCurrentlyUnavailable(String)
    case audioSessionFailed(String)
    case invalidInputFormat
    case alreadyRecording

    public var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return "Microphone permission was denied."
        case .speechPermissionDenied:
            return "Speech recognition permission was denied."
        case .recognizerUnavailable(let id):
            return "No speech recognizer is available for \(id)."
        case .recognizerCurrentlyUnavailable(let id):
            return "The speech recognizer for \(id) is currently unavailable."
        case .audioSessionFailed(let description):
            return "Audio session error: \(description)"
        case .invalidInputFormat:
            return "Microphone input format is not ready."
        case .alreadyRecording:
            return "Already recording."
        }
    }
}
#endif
