//
//  KeyboardRecordingSpike.swift
//  VoiceFlowKeyboard
//
//  Phase 0 probe for microphone + Apple Speech viability inside the keyboard.
//

import AVFAudio
import Foundation
import MachO
import Speech

struct KeyboardRecordingSpikeSnapshot {
    var status: String
    var transcript: String
    var recentAudioEvents: [String]
    var peakResidentMemoryMB: Double
    var tapToEngineStartMS: Double?
    var tapToFirstAudioBufferMS: Double?
    var stopToFinalResultMS: Double?
    var isRecording: Bool
}

@MainActor
protocol KeyboardRecordingSpikeDelegate: AnyObject {
    func keyboardRecordingSpikeDidUpdate(_ snapshot: KeyboardRecordingSpikeSnapshot)
}

@MainActor
final class KeyboardRecordingSpike: @unchecked Sendable {
    weak var delegate: KeyboardRecordingSpikeDelegate?

    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var speechRecognizer: SFSpeechRecognizer?
    private var transcript = ""
    private var status = "Idle"
    private var peakResidentMemoryMB = currentResidentMemoryMB()
    private var tapTime: ContinuousClock.Instant?
    private var stopTime: ContinuousClock.Instant?
    private var tapToEngineStartMS: Double?
    private var tapToFirstAudioBufferMS: Double?
    private var stopToFinalResultMS: Double?
    private var firstAudioBufferObserved = false
    private var memoryTimer: Timer?
    private var inputTapInstalled = false
    private var speechActive = false
    private var audioSessionObservers: [NSObjectProtocol] = []
    private var recentAudioEvents: [String] = []

    init() {
        installAudioSessionObservers()
    }

    deinit {
        audioSessionObservers.forEach(NotificationCenter.default.removeObserver)
    }

    var isRecording: Bool {
        audioEngine.isRunning
    }

    @MainActor
    func currentSnapshot() -> KeyboardRecordingSpikeSnapshot {
        peakResidentMemoryMB = max(peakResidentMemoryMB, Self.currentResidentMemoryMB())
        return KeyboardRecordingSpikeSnapshot(
            status: status,
            transcript: transcript,
            recentAudioEvents: recentAudioEvents,
            peakResidentMemoryMB: peakResidentMemoryMB,
            tapToEngineStartMS: tapToEngineStartMS,
            tapToFirstAudioBufferMS: tapToFirstAudioBufferMS,
            stopToFinalResultMS: stopToFinalResultMS,
            isRecording: audioEngine.isRunning
        )
    }

    @MainActor
    func start(localeIdentifier: String = Locale.current.identifier) async {
        guard !audioEngine.isRunning else {
            update(status: "Already recording")
            return
        }

        resetRunState()
        update(status: "Requesting microphone permission")

        do {
            try await requestMicrophonePermission()
            try startAudioEngine()
            startMemorySampling()
            tapToEngineStartMS = elapsedMilliseconds(since: tapTime)
            update(status: "Audio recording. Attach Speech when ready.")
        } catch {
            cleanupAudio()
            update(status: "Start failed: \(error.localizedDescription)")
        }
    }

    @MainActor
    func attachSpeech(localeIdentifier: String = Locale.current.identifier) async {
        guard audioEngine.isRunning else {
            update(status: "Start audio before attaching Speech")
            return
        }

        guard !speechActive else {
            update(status: "Speech already attached")
            return
        }

        update(status: "Requesting Speech permission")

        do {
            try await requestSpeechPermission()
            try configureRecognition(localeIdentifier: localeIdentifier)
            update(status: "Speech attached")
        } catch {
            recognitionTask?.cancel()
            recognitionTask = nil
            recognitionRequest = nil
            speechActive = false
            update(status: "Speech failed: \(error.localizedDescription)")
        }
    }

    @MainActor
    func stop() {
        guard audioEngine.isRunning else {
            update(status: "Idle")
            return
        }

        stopTime = .now
        audioEngine.stop()
        removeInputTapIfNeeded()
        recognitionRequest?.endAudio()
        speechActive = false
        update(status: "Finalizing")
    }

    @MainActor
    func cancel() {
        recognitionTask?.cancel()
        cleanupAudio()
        update(status: "Cancelled")
    }

    @MainActor
    func recordLifecycleEvent(_ event: String) {
        appendAudioEvent(event)
        update(status: status)
    }

    @MainActor
    private func resetRunState() {
        cleanupAudio()
        transcript = ""
        status = "Idle"
        peakResidentMemoryMB = Self.currentResidentMemoryMB()
        tapTime = .now
        stopTime = nil
        tapToEngineStartMS = nil
        tapToFirstAudioBufferMS = nil
        stopToFinalResultMS = nil
        firstAudioBufferObserved = false
        speechActive = false
    }

    private func requestSpeechPermission() async throws {
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }

        guard speechStatus == .authorized else {
            throw SpikeError.speechPermissionDenied(speechStatus)
        }
    }

    private func requestMicrophonePermission() async throws {
        let microphoneGranted = await AVAudioApplication.requestRecordPermission()
        guard microphoneGranted else {
            throw SpikeError.microphonePermissionDenied
        }
    }

    private func configureRecognition(localeIdentifier: String) throws {
        let locale = Locale(identifier: localeIdentifier)
        guard let recognizer = SFSpeechRecognizer(locale: locale) else {
            throw SpikeError.recognizerUnavailable(localeIdentifier)
        }

        guard recognizer.isAvailable else {
            throw SpikeError.recognizerCurrentlyUnavailable(localeIdentifier)
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true

        speechRecognizer = recognizer
        recognitionRequest = request
        speechActive = true
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                self?.handleRecognition(result: result, error: error)
            }
        }
    }

    @MainActor
    private func startAudioEngine() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .record,
            mode: .measurement,
            options: [.allowBluetoothHFP]
        )
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)
        let outputFormat = inputNode.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0 || outputFormat.sampleRate > 0 else {
            throw SpikeError.invalidInputFormat
        }

        inputNode.installTap(onBus: 0, bufferSize: 1_024, format: nil) { [weak self] buffer, _ in
            Task { @MainActor [weak self] in
                self?.recognitionRequest?.append(buffer)
                self?.observeAudioBuffer()
            }
        }
        inputTapInstalled = true

        audioEngine.prepare()
        try audioEngine.start()
        appendAudioEvent("audio engine started")
    }

    @MainActor
    private func observeAudioBuffer() {
        guard !firstAudioBufferObserved else { return }
        firstAudioBufferObserved = true
        tapToFirstAudioBufferMS = elapsedMilliseconds(since: tapTime)
        update(status: "Recording")
    }

    @MainActor
    private func handleRecognition(result: SFSpeechRecognitionResult?, error: Error?) {
        if let result {
            transcript = result.bestTranscription.formattedString
            if result.isFinal {
                stopToFinalResultMS = elapsedMilliseconds(since: stopTime)
                cleanupAudio(deactivateSession: true)
                update(status: "Final result")
                return
            }
        }

        if let error {
            cleanupAudio(deactivateSession: true)
            update(status: "Recognition ended: \(error.localizedDescription)")
            return
        }

        update(status: status)
    }

    @MainActor
    private func startMemorySampling() {
        memoryTimer?.invalidate()
        memoryTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.sampleMemory()
            }
        }
    }

    @MainActor
    private func sampleMemory() {
        peakResidentMemoryMB = max(peakResidentMemoryMB, Self.currentResidentMemoryMB())
        update(status: status)
    }

    @MainActor
    private func cleanupAudio(deactivateSession: Bool = false) {
        memoryTimer?.invalidate()
        memoryTimer = nil
        if audioEngine.isRunning {
            audioEngine.stop()
            appendAudioEvent("audio engine stopped")
        }
        removeInputTapIfNeeded()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        speechActive = false
        if deactivateSession {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    @MainActor
    private func removeInputTapIfNeeded() {
        guard inputTapInstalled else { return }
        audioEngine.inputNode.removeTap(onBus: 0)
        inputTapInstalled = false
    }

    @MainActor
    private func update(status: String) {
        self.status = status
        peakResidentMemoryMB = max(peakResidentMemoryMB, Self.currentResidentMemoryMB())
        delegate?.keyboardRecordingSpikeDidUpdate(currentSnapshot())
    }

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
                let rawOptions = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt
                MainActor.assumeIsolated {
                    self?.handleAudioInterruption(rawType: rawType, rawOptions: rawOptions)
                }
            },
            center.addObserver(
                forName: AVAudioSession.routeChangeNotification,
                object: session,
                queue: .main
            ) { [weak self] notification in
                let rawReason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
                MainActor.assumeIsolated {
                    self?.handleRouteChange(rawReason: rawReason)
                }
            },
            center.addObserver(
                forName: AVAudioSession.mediaServicesWereLostNotification,
                object: session,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.appendAudioEvent("media services lost")
                    self?.cleanupAudio()
                    self?.update(status: "Audio services lost")
                }
            },
            center.addObserver(
                forName: AVAudioSession.mediaServicesWereResetNotification,
                object: session,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.appendAudioEvent("media services reset")
                    self?.update(status: "Audio services reset")
                }
            }
        ]
    }

    @MainActor
    private func handleAudioInterruption(rawType: UInt?, rawOptions: UInt?) {
        guard
            let rawType,
            let type = AVAudioSession.InterruptionType(rawValue: rawType)
        else {
            appendAudioEvent("interruption: unknown")
            update(status: status)
            return
        }

        switch type {
        case .began:
            appendAudioEvent("interruption began")
            cleanupAudio()
            update(status: "Interrupted")
        case .ended:
            let options = AVAudioSession.InterruptionOptions(rawValue: rawOptions ?? 0)
            appendAudioEvent(options.contains(.shouldResume) ? "interruption ended: should resume" : "interruption ended")
            update(status: "Interruption ended")
        @unknown default:
            appendAudioEvent("interruption: unknown type \(rawType)")
            update(status: status)
        }
    }

    @MainActor
    private func handleRouteChange(rawReason: UInt?) {
        let reason = rawReason.flatMap(AVAudioSession.RouteChangeReason.init(rawValue:))?.spikeDescription ?? "unknown"
        appendAudioEvent("route change: \(reason)")
        update(status: status)
    }

    @MainActor
    private func appendAudioEvent(_ event: String) {
        let timestamp = Self.eventTimestampFormatter.string(from: Date())
        recentAudioEvents.append("\(timestamp) \(event)")
        if recentAudioEvents.count > 5 {
            recentAudioEvents.removeFirst(recentAudioEvents.count - 5)
        }
    }

    private func elapsedMilliseconds(since start: ContinuousClock.Instant?) -> Double? {
        guard let start else { return nil }
        let duration = start.duration(to: .now)
        return Double(duration.components.seconds * 1_000) + Double(duration.components.attoseconds) / 1e15
    }

    private static func currentResidentMemoryMB() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), reboundPointer, &count)
            }
        }

        guard result == KERN_SUCCESS else { return 0 }
        return Double(info.resident_size) / 1_048_576.0
    }

    private static let eventTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

private extension AVAudioSession.RouteChangeReason {
    var spikeDescription: String {
        switch self {
        case .unknown:
            "unknown"
        case .newDeviceAvailable:
            "new device available"
        case .oldDeviceUnavailable:
            "old device unavailable"
        case .categoryChange:
            "category change"
        case .override:
            "override"
        case .wakeFromSleep:
            "wake from sleep"
        case .noSuitableRouteForCategory:
            "no suitable route"
        case .routeConfigurationChange:
            "route configuration change"
        @unknown default:
            "unknown \(rawValue)"
        }
    }
}

private enum SpikeError: LocalizedError {
    case speechPermissionDenied(SFSpeechRecognizerAuthorizationStatus)
    case microphonePermissionDenied
    case recognizerUnavailable(String)
    case recognizerCurrentlyUnavailable(String)
    case invalidInputFormat

    var errorDescription: String? {
        switch self {
        case let .speechPermissionDenied(status):
            "Speech permission is \(status)"
        case .microphonePermissionDenied:
            "Microphone permission was denied"
        case let .recognizerUnavailable(localeIdentifier):
            "No speech recognizer for \(localeIdentifier)"
        case let .recognizerCurrentlyUnavailable(localeIdentifier):
            "Speech recognizer for \(localeIdentifier) is unavailable"
        case .invalidInputFormat:
            "Microphone input format is not ready"
        }
    }
}
