import SwiftUI
import UIKit
import VoiceFlowShared
import VoiceFlowWhisper

/// In-app dictation with the user's vocabulary. Also the place to try new words
/// without setting up the keyboard.
struct DictationView: View {
    @Environment(AppModel.self) private var model
    @State private var controller = DictationController()

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                ScrollView {
                    Text(displayText)
                        .font(.title3)
                        .foregroundStyle(controller.phase == .idle ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding()
                }
                .frame(maxHeight: .infinity)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))

                if case .finished(let result) = controller.phase, !result.appliedCorrections.isEmpty {
                    Label("\(result.appliedCorrections.count) word(s) corrected from your list", systemImage: "text.badge.checkmark")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if controller.phase == .recording {
                    ProgressView(value: Double(controller.inputLevel))
                        .accessibilityLabel("Input level")
                }

                controls
            }
            .padding()
            .navigationTitle("Dictate")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Text(model.settings.speechEngine == .whisper ? "Whisper" : "Apple")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Recognition engine: \(model.settings.speechEngine == .whisper ? "Whisper" : "Apple Speech")")
                }
            }
            .task { await model.warmUpSpeechEngine() }
        }
    }

    private var displayText: String {
        switch controller.phase {
        case .idle:
            return controller.errorText ?? "Tap the microphone and speak. Words from your list are recognized better."
        case .preparingModel:
            return model.whisper.statusText
        case .recording:
            if controller.partialText.isEmpty {
                // Whisper transcribes after Stop, so there is no live text to show.
                return model.settings.speechEngine == .whisper ? "Listening… (text appears after Stop)" : "Listening…"
            }
            return controller.partialText
        case .transcribing:
            return controller.partialText.isEmpty ? "Transcribing…" : controller.partialText
        case .finished(let result):
            return result.text
        }
    }

    @ViewBuilder
    private var controls: some View {
        switch controller.phase {
        case .idle:
            Button {
                controller.start(model: model)
            } label: {
                Label("Dictate", systemImage: "mic.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

        case .recording:
            HStack {
                Button("Cancel", role: .cancel) { controller.cancel() }
                    .buttonStyle(.bordered)
                Button {
                    controller.stop(model: model)
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .controlSize(.large)

        case .preparingModel:
            VStack(spacing: 12) {
                if case .downloading(let progress) = model.whisper.state {
                    ProgressView(value: progress)
                } else {
                    ProgressView()
                }
                Button("Cancel", role: .cancel) { controller.cancel() }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
            }

        case .transcribing:
            ProgressView()

        case .finished(let result):
            HStack {
                Button("Copy") { UIPasteboard.general.string = result.text }
                    .buttonStyle(.bordered)
                Button("Correct") { model.selectedTab = .history }
                    .buttonStyle(.bordered)
                Button {
                    controller.reset()
                } label: {
                    Label("New", systemImage: "mic.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .controlSize(.large)
        }
    }
}

@Observable
final class DictationController: SpeechEngineDelegate {
    struct Result: Equatable {
        var text: String
        var appliedCorrections: [UUID]
    }

    enum Phase: Equatable {
        case idle
        /// Downloading or loading the Whisper model before recording can start.
        case preparingModel
        case recording
        case transcribing
        case finished(Result)
    }

    private(set) var phase: Phase = .idle
    private(set) var partialText = ""
    private(set) var inputLevel: Float = 0
    private(set) var errorText: String?

    @ObservationIgnored private var engine: SpeechEngine?
    @ObservationIgnored private var engineKind: SpeechEngineKind = .apple
    @ObservationIgnored private weak var model: AppModel?

    func start(model: AppModel) {
        errorText = nil
        partialText = ""
        self.model = model
        let settings = model.settings
        engineKind = settings.speechEngine

        Task {
            do {
                let engine = try await makeEngine(for: settings, model: model)
                engine.delegate = self
                engine.contextualStrings = model.recognitionHints
                self.engine = engine
                phase = .recording
                try await engine.start(locale: AppleSpeechEngine.resolvedLocale(for: settings))
            } catch SpeechEngineError.cancelled {
                reset()
            } catch {
                fail(error)
            }
        }
    }

    private func makeEngine(for settings: VoiceFlowSettings, model: AppModel) async throws -> SpeechEngine {
        switch settings.speechEngine {
        case .apple:
            return AppleSpeechEngine(settings: settings)
        case .whisper:
            if !model.whisper.isReady {
                phase = .preparingModel
                await model.whisper.prepare()
                // The user tapped Cancel while the model was loading.
                guard phase == .preparingModel else { throw SpeechEngineError.cancelled }
            }
            guard let kit = model.whisper.whisperKit else {
                if case .failed(let message) = model.whisper.state {
                    throw SpeechEngineError.recognizerUnavailable("Whisper (\(message))")
                }
                throw SpeechEngineError.cancelled
            }
            return WhisperSpeechEngine(whisperKit: kit, settings: settings)
        }
    }

    func stop(model: AppModel) {
        guard let engine else { return }
        phase = .transcribing
        Task {
            do {
                let speech = try await engine.stop()
                finish(text: speech.text, localeIdentifier: speech.localeIdentifier, durationMs: speech.durationMs, model: model)
            } catch SpeechEngineError.cancelled {
                reset()
            } catch {
                fail(error)
            }
        }
    }

    func cancel() {
        engine?.cancel()
        reset()
    }

    func reset() {
        engine = nil
        partialText = ""
        inputLevel = 0
        phase = .idle
    }

    private func finish(text: String, localeIdentifier: String, durationMs: Int, model: AppModel) {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else {
            errorText = "No speech was recognized. Try again a little closer to the microphone."
            reset()
            return
        }

        let processed = model.process(raw)
        model.saveDictation(DictationRecord(
            sourceLocale: localeIdentifier,
            rawText: raw,
            processedText: processed.text,
            correctionLevel: model.settings.correctionLevel,
            durationMs: durationMs,
            wordCount: processed.text.split(whereSeparator: \.isWhitespace).count,
            state: .readyForReview,
            engine: engineKind
        ))
        engine = nil
        phase = .finished(Result(text: processed.text, appliedCorrections: processed.appliedEntryIDs))
    }

    private func fail(_ error: Error) {
        engine?.cancel()
        reset()
        errorText = Self.message(for: error)
    }

    static func message(for error: Error) -> String {
        switch error as? SpeechEngineError {
        case .microphonePermissionDenied:
            return "Microphone access is off. Turn it on in iOS Settings › VoiceFlow."
        case .speechPermissionDenied:
            return "Speech recognition is off. Turn it on in iOS Settings › VoiceFlow."
        case .localOnlyUnavailable:
            return "On-device recognition is not available for this language. Allow server recognition in Settings or pick another language."
        case .localeUnsupported(let locale), .recognizerUnavailable(let locale):
            return "Speech recognition is not available for \(locale) right now."
        default:
            return "Dictation stopped: \(error.localizedDescription)"
        }
    }

    // MARK: SpeechEngineDelegate

    func speechEngine(_ engine: SpeechEngine, didUpdatePartialText text: String) {
        partialText = text
    }

    func speechEngine(_ engine: SpeechEngine, didUpdateInputLevel level: Float) {
        inputLevel = level
    }

    func speechEngine(_ engine: SpeechEngine, didEndUnexpectedly error: SpeechEngineError, partialText: String) {
        errorText = Self.message(for: error)
        // Never drop recognized text: keep what was heard before the interruption.
        if let model, !partialText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            finish(text: partialText, localeIdentifier: AppleSpeechEngine.resolvedLocale(for: model.settings).identifier, durationMs: 0, model: model)
        } else {
            reset()
        }
    }
}
