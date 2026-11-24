#if os(iOS)
import AVFAudio
import Foundation
import Speech

/// `SpeechEngine` backed by iOS 26 `SpeechAnalyzer` + `SpeechTranscriber`.
/// On-device only; the model is a system asset, so it adds no bundle size.
/// Used by both hosts; `SpeechEngineFactory` falls back to `AppleSpeechEngine` when it is not ready.
@available(iOS 26.0, *)
@MainActor
public final class SpeechAnalyzerEngine: SpeechEngine {
    public weak var delegate: SpeechEngineDelegate?
    /// Passed as `AnalysisContext.contextualStrings`. Whether `SpeechTranscriber` honors them is
    /// unverified (Phase 2.0); correction pairs in `PostProcessor` apply either way.
    public var contextualStrings: [String] = []

    private let finalResultTimeout: Duration
    private let capture = MicrophoneCapture()
    private var analyzer: SpeechAnalyzer?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?
    private var finalizeTask: Task<Void, Never>?
    private var finalResultTimeoutTask: Task<Void, Never>?
    private var finalResultContinuation: CheckedContinuation<SpeechResult, Error>?
    private var transcript = TranscriptAccumulator()
    private var localeIdentifier = ""
    private var startedAt: ContinuousClock.Instant?
    private var isActive = false
    private var isStopping = false
    /// Incremented per recording so late results from a previous analyzer are ignored.
    private var sessionID = 0

    public init(finalResultTimeout: Duration = .seconds(2)) {
        self.finalResultTimeout = finalResultTimeout
        capture.onInputLevel = { [weak self] level in
            guard let self, !self.isStopping else { return }
            self.delegate?.speechEngine(self, didUpdateInputLevel: level)
        }
        capture.onUnexpectedStop = { [weak self] error in
            self?.endUnexpectedly(error)
        }
    }

    public var isRecording: Bool { isActive }

    // MARK: - Readiness

    /// The `SpeechTranscriber` locale for `locale`, or nil if the model does not support it.
    public static func supportedLocale(for locale: Locale) async -> Locale? {
        guard SpeechTranscriber.isAvailable else { return nil }
        return await SpeechTranscriber.supportedLocale(equivalentTo: locale)
    }

    /// True when a dictation can start right away: supported locale with installed assets.
    /// Never downloads; the keyboard must not wait on a multi-megabyte asset download.
    public static func isReady(for locale: Locale) async -> Bool {
        guard let supported = await supportedLocale(for: locale) else { return false }
        let transcriber = SpeechTranscriber(locale: supported, preset: .progressiveTranscription)
        return await AssetInventory.status(forModules: [transcriber]) == .installed
    }

    /// Asks the system to download the on-device model for `locale` if it is supported but missing.
    /// Containing app only. Apple's own asset download, the same mechanism as on-device dictation.
    /// - Returns: true if the assets are installed afterwards.
    @discardableResult
    public static func installAssetsIfNeeded(for locale: Locale) async -> Bool {
        guard let supported = await supportedLocale(for: locale) else { return false }
        let transcriber = SpeechTranscriber(locale: supported, preset: .progressiveTranscription)
        switch await AssetInventory.status(forModules: [transcriber]) {
        case .installed:
            return true
        case .unsupported:
            return false
        case .supported, .downloading:
            do {
                if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                    try await request.downloadAndInstall()
                }
                return await AssetInventory.status(forModules: [transcriber]) == .installed
            } catch {
                return false
            }
        @unknown default:
            return false
        }
    }

    // MARK: - SpeechEngine

    public func requestPermissions() async throws {
        try await SpeechPermissions.request(speechRecognition: true)
    }

    public func start(locale: Locale) async throws {
        guard !isActive else { throw SpeechEngineError.alreadyRecording }

        let identifier = SpeechLocaleResolver.normalize(locale.identifier)
        guard let supported = await Self.supportedLocale(for: Locale(identifier: identifier)) else {
            throw SpeechEngineError.localeUnsupported(identifier)
        }

        try await requestPermissions()
        guard !isActive else { throw SpeechEngineError.alreadyRecording }

        let transcriber = SpeechTranscriber(locale: supported, preset: .progressiveTranscription)
        guard await AssetInventory.status(forModules: [transcriber]) == .installed else {
            throw SpeechEngineError.recognizerUnavailable(identifier)
        }

        sessionID += 1
        let currentSessionID = sessionID
        isActive = true
        isStopping = false
        transcript = TranscriptAccumulator()
        localeIdentifier = identifier

        do {
            let analyzer = SpeechAnalyzer(
                modules: [transcriber],
                options: SpeechAnalyzer.Options(priority: .userInitiated, modelRetention: .lingering)
            )
            self.analyzer = analyzer

            let hints = Array(contextualStrings.prefix(VocabularyCorrector.maxRecognitionHints))
            if !hints.isEmpty {
                let context = AnalysisContext()
                context.contextualStrings[.general] = hints
                try await analyzer.setContext(context)
            }

            try capture.activateSession()
            let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
                compatibleWith: [transcriber],
                considering: capture.inputFormat
            )
            try await analyzer.prepareToAnalyze(in: analyzerFormat)
            guard sessionID == currentSessionID, isActive else { throw SpeechEngineError.cancelled }

            let (stream, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
            inputContinuation = continuation
            resultsTask = Task { [weak self] in
                do {
                    for try await result in transcriber.results {
                        self?.handle(segment: String(result.text.characters), isFinal: result.isFinal, sessionID: currentSessionID)
                    }
                } catch {
                    self?.handleResultsError(error, sessionID: currentSessionID)
                }
            }

            try await analyzer.start(inputSequence: stream)
            guard sessionID == currentSessionID, isActive else { throw SpeechEngineError.cancelled }

            let converter = BufferConverter(target: analyzerFormat)
            try capture.start(bufferHandler: Self.makeBufferHandler(converter: converter, continuation: continuation))
            startedAt = .now
        } catch let error as SpeechEngineError {
            if sessionID == currentSessionID { teardown() }
            throw error
        } catch {
            if sessionID == currentSessionID { teardown() }
            throw SpeechEngineError.recognizerUnavailable(identifier)
        }
    }

    public func stop() async throws -> SpeechResult {
        guard isActive, !isStopping else { throw SpeechEngineError.notRecording }

        isStopping = true
        capture.stop()
        inputContinuation?.finish()

        let analyzer = self.analyzer
        let resultsTask = self.resultsTask
        let currentSessionID = sessionID

        return try await withCheckedThrowingContinuation { continuation in
            finalResultContinuation = continuation
            finalizeTask = Task { [weak self] in
                try? await analyzer?.finalizeAndFinishThroughEndOfInput()
                _ = await resultsTask?.result
                guard self?.sessionID == currentSessionID else { return }
                self?.finish(isFinal: true)
            }
            let timeout = finalResultTimeout
            finalResultTimeoutTask = Task { [weak self] in
                try? await Task.sleep(for: timeout)
                guard !Task.isCancelled, self?.sessionID == currentSessionID else { return }
                self?.finish(isFinal: false)
            }
        }
    }

    public func cancel() {
        let continuation = finalResultContinuation
        finalResultContinuation = nil
        teardown()
        continuation?.resume(throwing: SpeechEngineError.cancelled)
    }

    // MARK: - Results

    private func handle(segment: String, isFinal: Bool, sessionID: Int) {
        guard sessionID == self.sessionID, isActive else { return }
        transcript.apply(segment, isFinal: isFinal)
        if !isStopping {
            delegate?.speechEngine(self, didUpdatePartialText: transcript.text)
        }
    }

    private func handleResultsError(_ error: Error, sessionID: Int) {
        guard sessionID == self.sessionID, isActive, !(error is CancellationError) else { return }
        if isStopping {
            finish(isFinal: false)
        } else {
            endUnexpectedly(.recognitionFailed(error.localizedDescription))
        }
    }

    private func finish(isFinal: Bool) {
        guard let continuation = finalResultContinuation else { return }
        finalResultContinuation = nil

        let result = SpeechResult(
            text: transcript.text,
            localeIdentifier: localeIdentifier,
            durationMs: elapsedMilliseconds(),
            isFinal: isFinal,
            recognitionMode: .onDevice
        )
        teardown()
        continuation.resume(returning: result)
    }

    private func endUnexpectedly(_ error: SpeechEngineError) {
        guard isActive else { return }
        if isStopping {
            finish(isFinal: false)
            return
        }
        let partialText = transcript.text
        teardown()
        delegate?.speechEngine(self, didEndUnexpectedly: error, partialText: partialText)
    }

    private func teardown() {
        // Invalidate in-flight callbacks first.
        sessionID += 1
        finalResultTimeoutTask?.cancel()
        finalResultTimeoutTask = nil
        finalizeTask?.cancel()
        finalizeTask = nil
        resultsTask?.cancel()
        resultsTask = nil
        capture.stop()
        inputContinuation?.finish()
        inputContinuation = nil
        if let analyzer {
            Task { await analyzer.cancelAndFinishNow() }
        }
        analyzer = nil
        isActive = false
        isStopping = false
        startedAt = nil
        capture.deactivateSession()
    }

    private func elapsedMilliseconds() -> Int {
        guard let startedAt else { return 0 }
        let duration = startedAt.duration(to: .now)
        return Int(duration.components.seconds * 1_000 + duration.components.attoseconds / 1_000_000_000_000_000)
    }

    // MARK: - Audio

    /// Built outside the main actor: the tap runs on the realtime audio thread.
    private nonisolated static func makeBufferHandler(
        converter: BufferConverter,
        continuation: AsyncStream<AnalyzerInput>.Continuation
    ) -> MicrophoneCapture.BufferHandler {
        { buffer in
            guard let converted = converter.convert(buffer) else { return }
            continuation.yield(AnalyzerInput(buffer: converted))
        }
    }
}

/// Converts microphone buffers to the analyzer's format. Only used from the audio thread.
final class BufferConverter: @unchecked Sendable {
    private let target: AVAudioFormat?
    private var converter: AVAudioConverter?

    init(target: AVAudioFormat?) {
        self.target = target
    }

    func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let target, buffer.format != target else { return buffer }

        if converter == nil || converter?.inputFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: target)
            converter?.primeMethod = .none
        }
        guard let converter else { return nil }

        let ratio = target.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 1
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return nil }

        var consumed = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if consumed {
                inputStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            inputStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, error == nil, output.frameLength > 0 else { return nil }
        return output
    }
}
#endif
