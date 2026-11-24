import SwiftUI
import UIKit
import VoiceFlowParakeet
import VoiceFlowShared

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var appleModel = AppleSpeechModelStatus()
    private let parakeet = ParakeetModelStore.shared

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
                        Text("Automatic").tag(SpeechEngineKind.automatic)
                        Text("Apple (classic)").tag(SpeechEngineKind.appleClassic)
                        Text("Apple SpeechAnalyzer").tag(SpeechEngineKind.appleSpeechAnalyzer)
                        Text("Parakeet (app only)").tag(SpeechEngineKind.parakeet)
                    }
                    appleModelRow
                    parakeetRow
                } header: {
                    Text("Recognition engine")
                } footer: {
                    Text("Automatic uses Apple's newer on-device model (iOS 26) when it is installed, otherwise the classic recognizer. Parakeet runs only in this app; the keyboard falls back to Apple. All engines run on this device.")
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
    private var appleModelRow: some View {
        LabeledContent("Apple on-device model") {
            switch appleModel.state {
            case .checking:
                ProgressView()
            case .unavailable:
                Text("Needs iOS 26")
            case .unsupported:
                Text("Language not supported")
            case .installed:
                Text("Installed")
            case .notInstalled:
                Button("Install") {
                    appleModel.install(locale: AppleSpeechEngine.resolvedLocale(for: model.settings))
                }
            case .installing:
                ProgressView()
            }
        }
        .task(id: model.settings.localeMode) {
            await appleModel.refresh(locale: AppleSpeechEngine.resolvedLocale(for: model.settings))
        }
    }

    @ViewBuilder
    private var parakeetRow: some View {
        switch parakeet.state {
        case .notDownloaded:
            Button("Download Parakeet model (about \(ParakeetModelStore.approximateDownloadMegabytes) MB)") {
                parakeet.download()
            }
        case .downloading(let progress):
            LabeledContent("Downloading Parakeet") {
                ProgressView(value: progress)
                    .frame(maxWidth: 120)
            }
        case .downloaded:
            LabeledContent("Parakeet model", value: "Downloaded")
            Button("Delete Parakeet model", role: .destructive) {
                parakeet.deleteModels()
            }
        case .failed(let message):
            LabeledContent("Parakeet download failed", value: message)
            Button("Retry download") {
                parakeet.download()
            }
        }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<VoiceFlowSettings, Value>) -> Binding<Value> {
        Binding(
            get: { model.settings[keyPath: keyPath] },
            set: { newValue in model.update { $0[keyPath: keyPath] = newValue } }
        )
    }
}

/// Install state of the iOS 26 `SpeechTranscriber` model for the current dictation language.
@MainActor
@Observable
final class AppleSpeechModelStatus {
    enum State: Equatable {
        case checking, unavailable, unsupported, notInstalled, installing, installed
    }

    private(set) var state: State = .checking

    func refresh(locale: Locale) async {
        guard #available(iOS 26.0, *) else {
            state = .unavailable
            return
        }
        guard await SpeechAnalyzerEngine.supportedLocale(for: locale) != nil else {
            state = .unsupported
            return
        }
        state = await SpeechAnalyzerEngine.isReady(for: locale) ? .installed : .notInstalled
    }

    /// Apple's own system asset download, started only by the user.
    func install(locale: Locale) {
        guard #available(iOS 26.0, *) else { return }
        state = .installing
        Task {
            let installed = await SpeechAnalyzerEngine.installAssetsIfNeeded(for: locale)
            state = installed ? .installed : .notInstalled
        }
    }
}
