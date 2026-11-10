import SwiftUI
import UIKit
import VoiceFlowShared

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

    private func binding<Value>(_ keyPath: WritableKeyPath<VoiceFlowSettings, Value>) -> Binding<Value> {
        Binding(
            get: { model.settings[keyPath: keyPath] },
            set: { newValue in model.update { $0[keyPath: keyPath] = newValue } }
        )
    }
}
