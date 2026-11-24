#if os(iOS)
import AVFAudio
import FluidAudio
import Foundation
import VoiceFlowShared

/// `SpeechEngine` backed by Parakeet (Core ML, via FluidAudio). Containing app only.
///
/// Batch mode: audio is buffered while recording and transcribed on `stop()`, so there are no
/// partial results. Vocabulary is not passed to the model; `PostProcessor` correction pairs
/// apply to the result as for every engine.
@MainActor
public final class ParakeetSpeechEngine: SpeechEngine {
    public weak var delegate: SpeechEngineDelegate?
    /// Ignored: Parakeet TDT has no prompt. CTC keyword boosting is a possible follow-up.
    public var contextualStrings: [String] = []

    private let store: ParakeetModelStore
    private let capture = MicrophoneCapture()
    private var samples: SampleCollector?
    private var localeIdentifier = ""
    private var startedAt: ContinuousClock.Instant?
    private var isStopping = false
    private var sessionID = 0

    /// Returns nil when the models are not downloaded, so the factory falls back to Apple.
    public static func makeIfReady(store: ParakeetModelStore = .shared) -> ParakeetSpeechEngine? {
        store.isDownloaded ? ParakeetSpeechEngine(store: store) : nil
    }

    init(store: ParakeetModelStore) {
        self.store = store
        capture.onInputLevel = { [weak self] level in
            guard let self, !self.isStopping else { return }
            self.delegate?.speechEngine(self, didUpdateInputLevel: level)
        }
        capture.onUnexpectedStop = { [weak self] error in
            self?.endUnexpectedly(error)
        }
    }

    public var isRecording: Bool { samples != nil }

    public func requestPermissions() async throws {
        try await SpeechPermissions.request(speechRecognition: false)
    }

    public func start(locale: Locale) async throws {
        guard !isRecording else { throw SpeechEngineError.alreadyRecording }

        let identifier = SpeechLocaleResolver.normalize(locale.identifier)
        guard Self.language(for: identifier) != nil else {
            throw SpeechEngineError.localeUnsupported(identifier)
        }

        try await requestPermissions()
        guard !isRecording else { throw SpeechEngineError.alreadyRecording }

        // Load (or compile) the models while the microphone warms up.
        store.warmUp()

        sessionID += 1
        let collector = SampleCollector()
        samples = collector
        localeIdentifier = identifier
        isStopping = false

        do {
            try capture.start(bufferHandler: Self.makeBufferHandler(collector: collector))
        } catch {
            teardown()
            throw SpeechEngineError.audioInputUnavailable
        }
        startedAt = .now
    }

    public func stop() async throws -> SpeechResult {
        guard let collector = samples, !isStopping else { throw SpeechEngineError.notRecording }

        isStopping = true
        capture.stop()
        capture.deactivateSession()
        let currentSessionID = sessionID
        let durationMs = elapsedMilliseconds()
        let language = Self.language(for: localeIdentifier)
        let identifier = localeIdentifier

        do {
            let manager = try await store.loadedManager()
            let (audio, sampleRate) = collector.drain()
            let resampled = try AudioConverter().resample(audio, from: sampleRate)
            let text: String
            if resampled.isEmpty {
                text = ""
            } else {
                var decoderState = TdtDecoderState.make(decoderLayers: await manager.decoderLayerCount)
                let result = try await manager.transcribe(resampled, decoderState: &decoderState, language: language)
                text = result.text
            }
            guard sessionID == currentSessionID else { throw SpeechEngineError.cancelled }
            teardown()
            return SpeechResult(
                text: text,
                localeIdentifier: identifier,
                durationMs: durationMs,
                isFinal: true,
                recognitionMode: .onDevice
            )
        } catch let error as SpeechEngineError {
            if sessionID == currentSessionID { teardown() }
            throw error
        } catch {
            guard sessionID == currentSessionID else { throw SpeechEngineError.cancelled }
            teardown()
            throw SpeechEngineError.recognitionFailed(error.localizedDescription)
        }
    }

    public func cancel() {
        teardown()
    }

    // MARK: - Private

    static func language(for identifier: String) -> Language? {
        let code = identifier.split(separator: "-").first.map { String($0).lowercased() } ?? ""
        return Language(rawValue: code)
    }

    private func endUnexpectedly(_ error: SpeechEngineError) {
        guard isRecording, !isStopping else { return }
        // Batch engine: nothing recognized yet, so there is no partial text to hand back.
        teardown()
        delegate?.speechEngine(self, didEndUnexpectedly: error, partialText: "")
    }

    private func teardown() {
        sessionID += 1
        capture.stop()
        capture.deactivateSession()
        samples = nil
        isStopping = false
        startedAt = nil
    }

    private func elapsedMilliseconds() -> Int {
        guard let startedAt else { return 0 }
        let duration = startedAt.duration(to: .now)
        return Int(duration.components.seconds * 1_000 + duration.components.attoseconds / 1_000_000_000_000_000)
    }

    /// Built outside the main actor: the tap runs on the realtime audio thread.
    private nonisolated static func makeBufferHandler(collector: SampleCollector) -> MicrophoneCapture.BufferHandler {
        { buffer in collector.append(buffer) }
    }
}

/// Collects mono float samples from the audio thread.
final class SampleCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [Float] = []
    private var sampleRate: Double = 16_000

    func append(_ buffer: AVAudioPCMBuffer) {
        guard let channel = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
        let chunk = UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength))
        lock.lock()
        sampleRate = buffer.format.sampleRate
        samples.append(contentsOf: chunk)
        lock.unlock()
    }

    func drain() -> (samples: [Float], sampleRate: Double) {
        lock.lock()
        defer { lock.unlock() }
        let result = (samples, sampleRate)
        samples = []
        return result
    }
}
#endif
