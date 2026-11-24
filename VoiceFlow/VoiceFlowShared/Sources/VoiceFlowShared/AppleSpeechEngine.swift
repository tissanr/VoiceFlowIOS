#if os(iOS)
import AVFAudio
import Foundation
import Speech

/// `SpeechEngine` backed by `SFSpeechRecognizer` + `AVAudioEngine`.
/// Used by the keyboard extension (primary flow) and the containing app (fallback flow).
@MainActor
public final class AppleSpeechEngine: SpeechEngine {
    public weak var delegate: SpeechEngineDelegate?
    public var contextualStrings: [String] = []

    private let settings: VoiceFlowSettings
    private let finalResultTimeout: Duration
    private let capture = MicrophoneCapture()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var speechRecognizer: SFSpeechRecognizer?
    private var isStopping = false
    private var latestText = ""
    private var localeIdentifier = ""
    private var recognitionMode: SpeechRecognitionMode = .onDevice
    private var startedAt: ContinuousClock.Instant?
    private var finalResultContinuation: CheckedContinuation<SpeechResult, Error>?
    private var finalResultTimeoutTask: Task<Void, Never>?
    /// Incremented per recording so late callbacks from a previous recognition task are ignored.
    private var sessionID = 0

    public init(settings: VoiceFlowSettings = .defaults, finalResultTimeout: Duration = .seconds(2)) {
        self.settings = settings
        self.finalResultTimeout = finalResultTimeout
        capture.onInputLevel = { [weak self] level in
            guard let self, !self.isStopping else { return }
            self.delegate?.speechEngine(self, didUpdateInputLevel: level)
        }
        capture.onUnexpectedStop = { [weak self] error in
            self?.endUnexpectedly(error)
        }
    }

    /// True from `start` until the final result is delivered or the recording is torn down.
    public var isRecording: Bool {
        recognitionRequest != nil
    }

    public static func resolvedLocale(for settings: VoiceFlowSettings, currentLocale: Locale = .current) -> Locale {
        let supported = Set(SFSpeechRecognizer.supportedLocales().map(\.identifier))
        let identifier = SpeechLocaleResolver.localeIdentifier(
            for: settings.localeMode,
            currentLocale: currentLocale,
            supportedIdentifiers: supported
        )
        return Locale(identifier: identifier)
    }

    public static func capability(for localeIdentifier: String) -> SpeechLocaleCapability {
        let isListed = SFSpeechRecognizer.supportedLocales().contains {
            SpeechLocaleResolver.normalize($0.identifier) == localeIdentifier
        }
        let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier))

        return SpeechLocaleCapability(
            localeIdentifier: localeIdentifier,
            isSupported: isListed && recognizer != nil,
            isAvailable: recognizer?.isAvailable ?? false,
            supportsOnDeviceRecognition: recognizer?.supportsOnDeviceRecognition ?? false
        )
    }

    public func requestPermissions() async throws {
        try await SpeechPermissions.request(speechRecognition: true)
    }

    public func start(locale: Locale) async throws {
        guard !isRecording else {
            throw SpeechEngineError.alreadyRecording
        }

        let identifier = SpeechLocaleResolver.normalize(locale.identifier)
        let mode = try SpeechRecognitionPolicy.recognitionMode(
            for: Self.capability(for: identifier),
            settings: settings
        )

        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: identifier)) else {
            throw SpeechEngineError.localeUnsupported(identifier)
        }

        try await requestPermissions()

        // A second start may have raced in while permissions were pending.
        guard !isRecording else {
            throw SpeechEngineError.alreadyRecording
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        request.requiresOnDeviceRecognition = mode == .onDevice
        request.contextualStrings = Array(contextualStrings.prefix(VocabularyCorrector.maxRecognitionHints))

        sessionID += 1
        let currentSessionID = sessionID
        recognitionRequest = request
        speechRecognizer = recognizer
        localeIdentifier = identifier
        recognitionMode = mode
        latestText = ""
        isStopping = false

        do {
            try capture.start(bufferHandler: Self.makeBufferHandler(request: request))
        } catch {
            teardown()
            throw SpeechEngineError.audioInputUnavailable
        }

        startedAt = .now
        recognitionTask = recognizer.recognitionTask(
            with: request,
            resultHandler: Self.makeResultHandler(owner: self, sessionID: currentSessionID)
        )
    }

    public func stop() async throws -> SpeechResult {
        guard isRecording, !isStopping else {
            throw SpeechEngineError.notRecording
        }

        isStopping = true
        capture.stop()
        recognitionRequest?.endAudio()

        return try await withCheckedThrowingContinuation { continuation in
            finalResultContinuation = continuation
            let timeout = finalResultTimeout
            finalResultTimeoutTask = Task { [weak self] in
                try? await Task.sleep(for: timeout)
                guard !Task.isCancelled else { return }
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

    // MARK: - Audio

    /// Built outside the main actor: the tap runs on the realtime audio thread.
    private nonisolated static func makeBufferHandler(
        request: SFSpeechAudioBufferRecognitionRequest
    ) -> MicrophoneCapture.BufferHandler {
        { buffer in request.append(buffer) }
    }

    // MARK: - Recognition

    private nonisolated static func makeResultHandler(
        owner: AppleSpeechEngine,
        sessionID: Int
    ) -> (SFSpeechRecognitionResult?, Error?) -> Void {
        { [weak owner] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let errorMessage = error.map { $0.localizedDescription }

            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    owner?.handleRecognition(sessionID: sessionID, text: text, isFinal: isFinal, errorMessage: errorMessage)
                }
            }
        }
    }

    private func handleRecognition(sessionID: Int, text: String?, isFinal: Bool, errorMessage: String?) {
        guard sessionID == self.sessionID, isRecording else { return }

        if let text {
            latestText = text
            if !isStopping {
                delegate?.speechEngine(self, didUpdatePartialText: text)
            }
        }

        if isFinal {
            finish(isFinal: true)
            return
        }

        guard let errorMessage else { return }

        if isStopping {
            // e.g. "no speech detected" after endAudio: deliver whatever was recognized.
            finish(isFinal: false)
        } else {
            endUnexpectedly(.recognitionFailed(errorMessage))
        }
    }

    private func finish(isFinal: Bool) {
        guard let continuation = finalResultContinuation else { return }
        finalResultContinuation = nil

        let result = SpeechResult(
            text: latestText,
            localeIdentifier: localeIdentifier,
            durationMs: elapsedMilliseconds(),
            isFinal: isFinal,
            recognitionMode: recognitionMode
        )
        teardown()
        continuation.resume(returning: result)
    }

    private func endUnexpectedly(_ error: SpeechEngineError) {
        guard isRecording else { return }

        if isStopping {
            finish(isFinal: false)
            return
        }

        let partialText = latestText
        teardown()
        delegate?.speechEngine(self, didEndUnexpectedly: error, partialText: partialText)
    }

    private func teardown() {
        finalResultTimeoutTask?.cancel()
        finalResultTimeoutTask = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        capture.stop()
        recognitionRequest = nil
        speechRecognizer = nil
        isStopping = false
        startedAt = nil
        capture.deactivateSession()
    }

    private func elapsedMilliseconds() -> Int {
        guard let startedAt else { return 0 }
        let duration = startedAt.duration(to: .now)
        return Int(duration.components.seconds * 1_000 + duration.components.attoseconds / 1_000_000_000_000_000)
    }
}
#endif
