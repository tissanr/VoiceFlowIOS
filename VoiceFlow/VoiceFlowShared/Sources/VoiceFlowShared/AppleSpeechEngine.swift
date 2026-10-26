#if os(iOS)
import AVFAudio
import Foundation
import Speech

/// `SpeechEngine` backed by `SFSpeechRecognizer` + `AVAudioEngine`.
/// Used by the keyboard extension (primary flow) and the containing app (fallback flow).
@MainActor
public final class AppleSpeechEngine: SpeechEngine {
    public weak var delegate: SpeechEngineDelegate?

    private let settings: VoiceFlowSettings
    private let finalResultTimeout: Duration
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var speechRecognizer: SFSpeechRecognizer?
    private var inputTapInstalled = false
    private var isStopping = false
    private var latestText = ""
    private var localeIdentifier = ""
    private var recognitionMode: SpeechRecognitionMode = .onDevice
    private var startedAt: ContinuousClock.Instant?
    private var finalResultContinuation: CheckedContinuation<SpeechResult, Error>?
    private var finalResultTimeoutTask: Task<Void, Never>?
    /// Incremented per recording so late callbacks from a previous recognition task are ignored.
    private var sessionID = 0
    private var observers: [NSObjectProtocol] = []

    public init(settings: VoiceFlowSettings = .defaults, finalResultTimeout: Duration = .seconds(2)) {
        self.settings = settings
        self.finalResultTimeout = finalResultTimeout
        installObservers()
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
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
        guard await AVAudioApplication.requestRecordPermission() else {
            throw SpeechEngineError.microphonePermissionDenied
        }

        let speechStatus: SFSpeechRecognizerAuthorizationStatus
        if SFSpeechRecognizer.authorizationStatus() == .notDetermined {
            speechStatus = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status)
                }
            }
        } else {
            speechStatus = SFSpeechRecognizer.authorizationStatus()
        }

        guard speechStatus == .authorized else {
            throw SpeechEngineError.speechPermissionDenied
        }
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

        sessionID += 1
        let currentSessionID = sessionID
        recognitionRequest = request
        speechRecognizer = recognizer
        localeIdentifier = identifier
        recognitionMode = mode
        latestText = ""
        isStopping = false

        do {
            try startAudio(request: request, sessionID: currentSessionID)
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
        stopAudio()
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

    private func startAudio(request: SFSpeechAudioBufferRecognitionRequest, sessionID: Int) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [.duckOthers, .allowBluetoothHFP])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let inputNode = audioEngine.inputNode
        guard inputNode.outputFormat(forBus: 0).sampleRate > 0 else {
            throw SpeechEngineError.audioInputUnavailable
        }

        let onLevel: @Sendable (Float) -> Void = { [weak self] level in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.sessionID == sessionID, !self.isStopping else { return }
                    self.delegate?.speechEngine(self, didUpdateInputLevel: level)
                }
            }
        }

        inputNode.installTap(onBus: 0, bufferSize: 1_024, format: nil, block: Self.makeTapBlock(request: request, onLevel: onLevel))
        inputTapInstalled = true

        audioEngine.prepare()
        try audioEngine.start()
    }

    private func stopAudio() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }

        if inputTapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            inputTapInstalled = false
        }
    }

    /// Built outside the main actor: the tap runs on the realtime audio thread.
    private nonisolated static func makeTapBlock(
        request: SFSpeechAudioBufferRecognitionRequest,
        onLevel: @escaping @Sendable (Float) -> Void
    ) -> AVAudioNodeTapBlock {
        { buffer, _ in
            request.append(buffer)
            onLevel(normalizedLevel(of: buffer))
        }
    }

    private nonisolated static func normalizedLevel(of buffer: AVAudioPCMBuffer) -> Float {
        guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else {
            return 0
        }

        let frameCount = Int(buffer.frameLength)
        var sumOfSquares: Float = 0
        for index in 0..<frameCount {
            sumOfSquares += samples[index] * samples[index]
        }

        let rms = (sumOfSquares / Float(frameCount)).squareRoot()
        let decibels = 20 * log10(max(rms, 0.000_01))
        // Map roughly -50 dB (quiet room) ... 0 dB (clipping) onto 0 ... 1.
        return min(1, max(0, (decibels + 50) / 50))
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
        stopAudio()
        recognitionRequest = nil
        speechRecognizer = nil
        isStopping = false
        startedAt = nil
        // The keyboard must release the session before dismissal; let paused audio resume.
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func elapsedMilliseconds() -> Int {
        guard let startedAt else { return 0 }
        let duration = startedAt.duration(to: .now)
        return Int(duration.components.seconds * 1_000 + duration.components.attoseconds / 1_000_000_000_000_000)
    }

    // MARK: - Interruptions

    private func installObservers() {
        let center = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()

        observers = [
            center.addObserver(forName: AVAudioSession.interruptionNotification, object: session, queue: .main) { [weak self] notification in
                let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
                MainActor.assumeIsolated {
                    guard rawType.flatMap(AVAudioSession.InterruptionType.init(rawValue:)) == .began else { return }
                    self?.endUnexpectedly(.interrupted)
                }
            },
            center.addObserver(forName: AVAudioSession.mediaServicesWereLostNotification, object: session, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.endUnexpectedly(.audioInputUnavailable)
                }
            },
            // Route changes such as unplugging a headset stop the engine without an interruption.
            center.addObserver(forName: .AVAudioEngineConfigurationChange, object: audioEngine, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, !self.isStopping, !self.audioEngine.isRunning else { return }
                    self.endUnexpectedly(.interrupted)
                }
            }
        ]
    }
}
#endif
