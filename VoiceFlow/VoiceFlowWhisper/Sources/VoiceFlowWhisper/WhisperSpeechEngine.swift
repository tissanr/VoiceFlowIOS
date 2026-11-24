#if os(iOS)
import AVFAudio
import Foundation
import VoiceFlowShared
import WhisperKit

/// On-device Whisper `SpeechEngine` for the containing app.
///
/// Records to a 16 kHz mono WAV file, then transcribes the whole file with WhisperKit on `stop()`.
/// There are no live partial results. Audio never leaves the device; the model comes from a
/// `WhisperModelManager` that has already downloaded and loaded it.
@MainActor
public final class WhisperSpeechEngine: SpeechEngine {
    public weak var delegate: SpeechEngineDelegate?
    /// Vocabulary terms passed to Whisper as a decoder prompt, which biases spelling of names and domain terms.
    public var contextualStrings: [String] = []

    private let settings: VoiceFlowSettings
    private let whisperKit: WhisperKit
    private var recorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var levelTimer: Timer?
    private var language: String?
    private var startedAt: Date?

    /// Whisper's prompt window is 224 tokens; keep the vocabulary prompt well inside it.
    private static let maxPromptTerms = 50

    public init(whisperKit: WhisperKit, settings: VoiceFlowSettings) {
        self.whisperKit = whisperKit
        self.settings = settings
    }

    public var isRecording: Bool {
        recorder != nil
    }

    // MARK: - SpeechEngine

    public func requestPermissions() async throws {
        guard await AVAudioApplication.requestRecordPermission() else {
            throw SpeechEngineError.microphonePermissionDenied
        }
    }

    public func start(locale: Locale) async throws {
        guard !isRecording else {
            throw SpeechEngineError.alreadyRecording
        }

        try await requestPermissions()

        guard !isRecording else {
            throw SpeechEngineError.alreadyRecording
        }

        // Automatic lets Whisper detect the language, which also copes better with German/English mixes.
        language = settings.localeMode == .automatic ? nil : locale.language.languageCode?.identifier

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dictation-\(UUID().uuidString)")
            .appendingPathExtension("wav")
        let recorderSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false
        ]

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .default, options: [.duckOthers, .allowBluetoothHFP])
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let recorder = try AVAudioRecorder(url: url, settings: recorderSettings)
            recorder.isMeteringEnabled = true
            guard recorder.record() else {
                throw SpeechEngineError.audioInputUnavailable
            }

            self.recorder = recorder
            recordingURL = url
            startedAt = Date()
            startLevelMetering()
        } catch {
            cleanup()
            throw SpeechEngineError.audioInputUnavailable
        }
    }

    /// Phone calls and Siri pause `AVAudioRecorder` automatically; `stop()` still transcribes what was captured.
    public func stop() async throws -> SpeechResult {
        guard let recorder, let recordingURL else {
            throw SpeechEngineError.notRecording
        }

        let durationMs = Int((Date().timeIntervalSince(startedAt ?? Date())) * 1_000)
        recorder.stop()
        self.recorder = nil
        stopLevelMetering()
        deactivateSession()

        defer {
            try? FileManager.default.removeItem(at: recordingURL)
            self.recordingURL = nil
        }

        let options = DecodingOptions(
            verbose: false,
            task: .transcribe,
            language: language,
            detectLanguage: language == nil,
            skipSpecialTokens: true,
            withoutTimestamps: true,
            promptTokens: promptTokens()
        )

        do {
            let results = try await whisperKit.transcribe(audioPath: recordingURL.path, decodeOptions: options)
            let text = results
                .map(\.text)
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            return SpeechResult(
                text: text,
                localeIdentifier: results.first?.language ?? language ?? "auto",
                durationMs: durationMs,
                isFinal: true,
                recognitionMode: .onDevice
            )
        } catch {
            throw SpeechEngineError.recognitionFailed(error.localizedDescription)
        }
    }

    public func cancel() {
        cleanup()
    }

    // MARK: - Helpers

    private func promptTokens() -> [Int]? {
        let terms = contextualStrings
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(Self.maxPromptTerms)
        guard !terms.isEmpty, let tokenizer = whisperKit.tokenizer else { return nil }
        // Leading space matches how Whisper tokenizes words mid-sentence.
        let tokens = tokenizer.encode(text: " " + terms.joined(separator: ", "))
            .filter { $0 < tokenizer.specialTokens.specialTokenBegin }
        return tokens.isEmpty ? nil : tokens
    }

    private func startLevelMetering() {
        levelTimer?.invalidate()
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let recorder = self.recorder else { return }
                recorder.updateMeters()
                // Map roughly -50 dB (quiet room) ... 0 dB onto 0 ... 1.
                let level = min(1, max(0, (recorder.averagePower(forChannel: 0) + 50) / 50))
                self.delegate?.speechEngine(self, didUpdateInputLevel: level)
            }
        }
    }

    private func stopLevelMetering() {
        levelTimer?.invalidate()
        levelTimer = nil
    }

    private func deactivateSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func cleanup() {
        recorder?.stop()
        recorder = nil
        stopLevelMetering()
        deactivateSession()
        if let recordingURL {
            try? FileManager.default.removeItem(at: recordingURL)
        }
        recordingURL = nil
        startedAt = nil
    }
}
#endif
