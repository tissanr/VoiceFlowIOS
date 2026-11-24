import SwiftUI
import UIKit
import VoiceFlowShared
import VoiceFlowWhisper

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            Form {
                Section("Speech") {
                    Picker("Language", selection: binding(\.localeMode)) {
                        Text("Automatic").tag(LocaleMode.automatic)
                        Text("German").tag(LocaleMode.german)
                        Text("English").tag(LocaleMode.english)
                    }
                    Toggle("Prefer on-device recognition", isOn: binding(\.preferOnDeviceSpeech))
                }

                Section {
                    Picker("Engine", selection: binding(\.speechEngine)) {
                        Text("Apple Speech").tag(SpeechEngineKind.apple)
                        Text("Whisper (on-device)").tag(SpeechEngineKind.whisper)
                    }

                    if model.settings.speechEngine == .whisper {
                        Picker("Model", selection: binding(\.whisperModel)) {
                            ForEach(WhisperModelVariant.allCases, id: \.self) { variant in
                                Text("\(variant.displayName) · ~\(variant.approximateSizeMB) MB").tag(variant)
                            }
                        }
                        LabeledContent("Status", value: model.whisper.statusText)
                        whisperActions
                    }
                } header: {
                    Text("Recognition engine (in this app)")
                } footer: {
                    Text("Whisper runs entirely on this iPhone. The model is downloaded once from Hugging Face; your audio never leaves the device. Text appears after you tap Stop. The VoiceFlow keyboard always uses Apple Speech.")
                }

                Section {
                    Toggle("Learn from corrections in other apps", isOn: binding(\.learnFromKeyboardEdits))
                } header: {
                    Text("Learning")
                } footer: {
                    Text("When you fix dictated text and come back to the VoiceFlow keyboard, it compares your fix with what it inserted and suggests new words. Only text VoiceFlow inserted is compared, and nothing leaves your device.")
                }

                Section {
                    Button("Open iOS Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                } header: {
                    Text("Keyboard")
                } footer: {
                    Text("Add VoiceFlow under General › Keyboard › Keyboards and allow Full Access to dictate directly in the keyboard.")
                }

                if let url = model.lastOpenedURL {
                    Section("Diagnostics") {
                        LabeledContent("Last opened URL", value: url.absoluteString)
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }

    @ViewBuilder
    private var whisperActions: some View {
        switch model.whisper.state {
        case .notDownloaded, .failed:
            Button("Download and load model") {
                Task { await model.whisper.prepare() }
            }
        case .downloaded:
            Button("Load model") {
                Task { await model.whisper.prepare() }
            }
            Button("Delete download", role: .destructive) { model.whisper.deleteDownload() }
        case .downloading(let progress):
            ProgressView(value: progress)
        case .loading:
            ProgressView()
        case .ready:
            Button("Delete download", role: .destructive) { model.whisper.deleteDownload() }
        }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<VoiceFlowSettings, Value>) -> Binding<Value> {
        Binding(
            get: { model.settings[keyPath: keyPath] },
            set: { newValue in model.update { $0[keyPath: keyPath] = newValue } }
        )
    }
}
