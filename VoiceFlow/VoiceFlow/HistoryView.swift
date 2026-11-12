import SwiftUI
import VoiceFlowShared

struct HistoryView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            List {
                if model.history.isEmpty {
                    Text("Dictations from the keyboard and this app appear here. Correct a dictation to teach VoiceFlow new words.")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.history) { record in
                    NavigationLink(value: record.id) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(record.finalText)
                                .lineLimit(2)
                            HStack {
                                Text(record.createdAt.formatted(.relative(presentation: .named)))
                                if record.editedText != nil {
                                    Text("· corrected")
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions {
                        Button("Delete", role: .destructive) { model.deleteDictation(record) }
                    }
                }
            }
            .navigationTitle("History")
            .navigationDestination(for: DictationID.self) { id in
                if let record = model.history.first(where: { $0.id == id }) {
                    HistoryDetailView(record: record)
                }
            }
        }
    }
}

private struct HistoryDetailView: View {
    @Environment(AppModel.self) private var model
    let record: DictationRecord

    @State private var draft = ""
    @State private var learnedMessage: String?
    @State private var learnedCount = 0
    @FocusState private var isEditing: Bool

    var body: some View {
        Form {
            Section {
                TextEditor(text: $draft)
                    .frame(minHeight: 140)
                    .focused($isEditing)
                    // Users type exact spellings here; autocorrect would "fix" names back.
                    .autocorrectionDisabled()
            } header: {
                Text("Text")
            } footer: {
                Text("Fix misrecognized words and save. VoiceFlow suggests them for your word list.")
            }

            if let learnedMessage {
                Section {
                    Label(learnedMessage, systemImage: "lightbulb")
                    if learnedCount > 0 {
                        Button("Review suggestions") { model.selectedTab = .words }
                    }
                }
            }

            Section("Recognized") {
                Text(record.rawText)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                LabeledContent("Language", value: record.sourceLocale)
                LabeledContent("Duration", value: Duration.milliseconds(record.durationMs).formatted(.units(allowed: [.seconds])))
            }

            Section {
                Button("Copy Text") { UIPasteboard.general.string = draft }
            }
        }
        .navigationTitle("Dictation")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button("Save") {
                isEditing = false
                let count = model.saveEdit(of: record, editedText: draft)
                learnedCount = count
                learnedMessage = count == 0
                    ? "Saved. No new words found in this correction."
                    : "Saved. \(count) new suggestion(s) for your word list."
            }
            .disabled(draft == record.finalText)
        }
        .onAppear { draft = record.finalText }
    }
}
