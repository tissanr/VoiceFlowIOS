#if os(iOS)
import AVFAudio
import Foundation
import Speech

/// Microphone capture shared by every `SpeechEngine`: audio session, input tap, level metering,
/// and interruption / route-change detection. Engines decide what to do with the buffers.
@MainActor
public final class MicrophoneCapture {
    /// Called on the realtime audio thread for every captured buffer. Must not block.
    public typealias BufferHandler = @Sendable (AVAudioPCMBuffer) -> Void

    /// Normalized input level 0...1, on the main actor.
    public var onInputLevel: ((Float) -> Void)?
    /// Capture stopped without `stop()`: interruption, media-services loss, or route change.
    public var onUnexpectedStop: ((SpeechEngineError) -> Void)?

    private let audioEngine = AVAudioEngine()
    private var tapInstalled = false
    private var observers: [NSObjectProtocol] = []
    /// Incremented per capture so late level callbacks from a previous capture are dropped.
    private var generation = 0
    public private(set) var isRunning = false

    public init() {
        installObservers()
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    /// Native microphone format. Valid after the audio session is active.
    public var inputFormat: AVAudioFormat {
        audioEngine.inputNode.outputFormat(forBus: 0)
    }

    /// Activates the record session. Separate from `start` so engines can read `inputFormat` first.
    public func activateSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [.duckOthers, .allowBluetoothHFP])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    public func start(bufferHandler: @escaping BufferHandler) throws {
        try activateSession()

        let inputNode = audioEngine.inputNode
        guard inputNode.outputFormat(forBus: 0).sampleRate > 0 else {
            throw SpeechEngineError.audioInputUnavailable
        }

        generation += 1
        let currentGeneration = generation
        let onLevel: @Sendable (Float) -> Void = { [weak self] level in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.isRunning, self.generation == currentGeneration else { return }
                    self.onInputLevel?(level)
                }
            }
        }

        inputNode.installTap(onBus: 0, bufferSize: 1_024, format: nil, block: Self.makeTapBlock(handler: bufferHandler, onLevel: onLevel))
        tapInstalled = true

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            stop()
            throw SpeechEngineError.audioInputUnavailable
        }
        isRunning = true
    }

    /// Stops the engine and removes the tap. The audio session stays active until `deactivateSession`.
    public func stop() {
        isRunning = false
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        if tapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
    }

    /// The keyboard must release the session before dismissal; lets paused audio resume.
    public func deactivateSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Built outside the main actor: the tap runs on the realtime audio thread.
    private nonisolated static func makeTapBlock(
        handler: @escaping BufferHandler,
        onLevel: @escaping @Sendable (Float) -> Void
    ) -> AVAudioNodeTapBlock {
        { buffer, _ in
            handler(buffer)
            onLevel(normalizedLevel(of: buffer))
        }
    }

    nonisolated static func normalizedLevel(of buffer: AVAudioPCMBuffer) -> Float {
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

    private func installObservers() {
        let center = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()

        observers = [
            center.addObserver(forName: AVAudioSession.interruptionNotification, object: session, queue: .main) { [weak self] notification in
                let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
                MainActor.assumeIsolated {
                    guard rawType.flatMap(AVAudioSession.InterruptionType.init(rawValue:)) == .began else { return }
                    self?.reportUnexpectedStop(.interrupted)
                }
            },
            center.addObserver(forName: AVAudioSession.mediaServicesWereLostNotification, object: session, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.reportUnexpectedStop(.audioInputUnavailable)
                }
            },
            // Route changes such as unplugging a headset stop the engine without an interruption.
            center.addObserver(forName: .AVAudioEngineConfigurationChange, object: audioEngine, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, !self.audioEngine.isRunning else { return }
                    self.reportUnexpectedStop(.interrupted)
                }
            }
        ]
    }

    private func reportUnexpectedStop(_ error: SpeechEngineError) {
        guard isRunning else { return }
        stop()
        onUnexpectedStop?(error)
    }
}

/// Microphone and speech-recognition authorization shared by the engines.
public enum SpeechPermissions {
    /// - Parameter speechRecognition: `SFSpeechRecognizer` / `SpeechAnalyzer` need speech-recognition
    ///   authorization; a bundled model (Parakeet) only needs the microphone.
    @MainActor
    public static func request(speechRecognition: Bool) async throws {
        guard await AVAudioApplication.requestRecordPermission() else {
            throw SpeechEngineError.microphonePermissionDenied
        }
        guard speechRecognition else { return }

        let status: SFSpeechRecognizerAuthorizationStatus
        if SFSpeechRecognizer.authorizationStatus() == .notDetermined {
            status = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status)
                }
            }
        } else {
            status = SFSpeechRecognizer.authorizationStatus()
        }

        guard status == .authorized else {
            throw SpeechEngineError.speechPermissionDenied
        }
    }
}
#endif
