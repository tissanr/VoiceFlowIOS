#if os(iOS)
import AVFAudio
import Foundation
import Speech

/// Production SpeechEngine implementation using AVAudioEngine + SFSpeechRecognizer.
@MainActor
public final class AppleSpeechEngine: SpeechEngine {
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var speechRecognizer: SFSpeechRecognizer?
    private var onEvent: (@MainActor (SpeechEvent) -> Void)?
    private var inputTapInstalled = false
    private var partialTranscript = ""
    private var audioSessionObservers: [NSObjectProtocol] = []

    public init() {
        installAudioSessionObservers()
    }

    deinit {
        audioSessionObservers.forEach(NotificationCenter.default.removeObserver)
    }

    public var isRecording: Bool { audioEngine.isRunning }

    public func requestPermissions() async throws {
        let micGranted = await AVAudioApplication.requestRecordPermission()
        guard micGranted else { throw SpeechEngineError.microphonePermissionDenied }

        let speechStatus: SFSpeechRecognizerAuthorizationStatus = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
        }
        guard speechStatus == .authorized else { throw SpeechEngineError.speechPermissionDenied }
    }

    public func start(locale: Locale, onEvent: @escaping @MainActor (SpeechEvent) -> Void) async throws {
        guard !audioEngine.isRunning else { throw SpeechEngineError.alreadyRecording }

        self.onEvent = onEvent
        partialTranscript = ""

        do {
            try activateAudioSession()
            try installInputTap()
            try configureRecognition(locale: locale)
            audioEngine.prepare()
            try audioEngine.start()
        } catch let error as SpeechEngineError {
            cleanupAudio(deactivateSession: true)
            throw error
        } catch {
            cleanupAudio(deactivateSession: true)
            throw SpeechEngineError.audioSessionFailed(error.localizedDescription)
        }
    }

    public func stop() {
        guard audioEngine.isRunning else { return }
        audioEngine.stop()
        removeInputTapIfNeeded()
        recognitionRequest?.endAudio()
        // .final or .failed will arrive via recognitionTask callback
    }

    public func cancel() {
        onEvent = nil
        partialTranscript = ""
        cleanupAudio(deactivateSession: true)
    }

    // MARK: - Audio setup

    private func activateAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: [.allowBluetoothHFP])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            throw SpeechEngineError.audioSessionFailed(error.localizedDescription)
        }
    }

    private func installInputTap() throws {
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)
        let outputFormat = inputNode.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0 || outputFormat.sampleRate > 0 else {
            throw SpeechEngineError.invalidInputFormat
        }

        inputNode.installTap(onBus: 0, bufferSize: 1_024, format: nil) { [weak self] buffer, _ in
            Task { @MainActor [weak self] in
                self?.recognitionRequest?.append(buffer)
            }
        }
        inputTapInstalled = true
    }

    private func configureRecognition(locale: Locale) throws {
        guard let recognizer = SFSpeechRecognizer(locale: locale) else {
            throw SpeechEngineError.recognizerUnavailable(locale.identifier)
        }
        guard recognizer.isAvailable else {
            throw SpeechEngineError.recognizerCurrentlyUnavailable(locale.identifier)
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true

        speechRecognizer = recognizer
        recognitionRequest = request
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                self?.handleRecognition(result: result, error: error)
            }
        }
    }

    private func handleRecognition(result: SFSpeechRecognitionResult?, error: Error?) {
        if let result {
            partialTranscript = result.bestTranscription.formattedString
            if result.isFinal {
                let transcript = partialTranscript
                cleanupAudio(deactivateSession: true)
                onEvent?(.final(transcript: transcript))
                onEvent = nil
                return
            } else {
                onEvent?(.partial(transcript: partialTranscript))
                return
            }
        }

        if let error {
            let partial = partialTranscript.isEmpty ? nil : partialTranscript
            cleanupAudio(deactivateSession: true)
            // Distinguish cancellation (benign) from real failures
            let nsError = error as NSError
            if nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 1110 {
                // No speech detected — treat as interrupted with no partial
                onEvent?(.interrupted(partialTranscript: nil))
            } else if nsError.code == 203 {
                // Recognition cancelled
                onEvent?(.interrupted(partialTranscript: partial))
            } else {
                onEvent?(.failed(error))
            }
            onEvent = nil
        }
    }

    // MARK: - Cleanup

    private func removeInputTapIfNeeded() {
        guard inputTapInstalled else { return }
        audioEngine.inputNode.removeTap(onBus: 0)
        inputTapInstalled = false
    }

    private func cleanupAudio(deactivateSession: Bool = false) {
        if audioEngine.isRunning { audioEngine.stop() }
        removeInputTapIfNeeded()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        speechRecognizer = nil
        if deactivateSession {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    // MARK: - Audio session notifications

    private func installAudioSessionObservers() {
        let center = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()

        audioSessionObservers = [
            center.addObserver(
                forName: AVAudioSession.interruptionNotification,
                object: session,
                queue: .main
            ) { [weak self] notification in
                let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
                MainActor.assumeIsolated { self?.handleInterruption(rawType: rawType) }
            },
            center.addObserver(
                forName: AVAudioSession.mediaServicesWereLostNotification,
                object: session,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    let partial = self?.partialTranscript
                    self?.cleanupAudio()
                    self?.onEvent?(.interrupted(partialTranscript: partial?.isEmpty == false ? partial : nil))
                    self?.onEvent = nil
                }
            }
        ]
    }

    private func handleInterruption(rawType: UInt?) {
        guard
            let rawType,
            let type = AVAudioSession.InterruptionType(rawValue: rawType),
            type == .began
        else { return }

        let partial = partialTranscript.isEmpty ? nil : partialTranscript
        cleanupAudio()
        onEvent?(.interrupted(partialTranscript: partial))
        onEvent = nil
    }
}
#endif
