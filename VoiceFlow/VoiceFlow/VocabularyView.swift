import SwiftUI
import VoiceFlowShared

struct VocabularyView: View {
    @Environment(AppModel.self) private var model
    @State private var isAdding = false
    @State private var editing: VocabularyEntry?

    var body: some View {
        NavigationStack {
            List {
                if !model.suggestions.isEmpty {
                    Section {
                        ForEach(model.suggestions) { entry in
                            SuggestionRow(entry: entry)
                        }
                    } header: {
                        Text("Suggestions")
                    } footer: {
                        Text("Learned from your corrections. Accept to use them when dictating.")
                    }
                }

                Section {
                    if model.activeEntries.isEmpty {
                        Text("No words yet. Add names, product terms, or jargon that dictation gets wrong.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(model.activeEntries) { entry in
                        Button {
                            editing = entry
                        } label: {
                            VocabularyRow(entry: entry)
                        }
                        .foregroundStyle(.primary)
                        .swipeActions {
                            Button("Delete", role: .destructive) { model.delete(entry) }
                        }
                    }
                } header: {
                    Text("Words")
                } footer: {
                    Text("Words are passed to speech recognition as hints. Entries with a “heard as” value are also replaced after recognition.")
                }

                if !model.rejectedEntries.isEmpty {
                    Section("Declined") {
                        DisclosureGroup("\(model.rejectedEntries.count) declined suggestions") {
                            ForEach(model.rejectedEntries) { entry in
                                VocabularyRow(entry: entry)
                                    .swipeActions {
                                        Button("Restore") { model.setStatus(.suggested, for: entry) }
                                        Button("Delete", role: .destructive) { model.delete(entry) }
                                    }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Words")
            .toolbar {
                Button {
                    isAdding = true
                } label: {
                    Label("Add Word", systemImage: "plus")
                }
            }
            .sheet(isPresented: $isAdding) {
                VocabularyEditor(entry: nil)
            }
            .sheet(item: $editing) { entry in
                VocabularyEditor(entry: entry)
            }
        }
    }
}

private struct VocabularyRow: View {
    let entry: VocabularyEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(entry.correction)
                .font(.body)
                .strikethrough(!entry.isEnabled)
            if entry.isCorrectionPair {
                Text("heard as “\(entry.heard)”")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(entry.isEnabled ? "" : "Disabled")
    }
}

private struct SuggestionRow: View {
    @Environment(AppModel.self) private var model
    let entry: VocabularyEntry

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(entry.heard) → \(entry.correction)")
                Text(entry.timesObserved > 1 ? "Seen \(entry.timesObserved) times" : "Seen once")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            Spacer()
            Button {
                model.setStatus(.rejected, for: entry)
            } label: {
                Image(systemName: "xmark.circle")
            }
            .accessibilityLabel("Decline")
            Button {
                model.setStatus(.active, for: entry)
            } label: {
                Image(systemName: "checkmark.circle.fill")
            }
            .accessibilityLabel("Accept")
        }
        .buttonStyle(.borderless)
        .font(.title3)
    }
}

private struct VocabularyEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let entry: VocabularyEntry?
    @State private var correction = ""
    @State private var heard = ""
    @State private var isEnabled = true

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Word or phrase", text: $correction)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } footer: {
                    Text("Spelled exactly as it should appear, e.g. “VoiceFlow”.")
                }
                Section {
                    TextField("Heard as (optional)", text: $heard)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } footer: {
                    Text("What dictation produces instead, e.g. “voice flow”. It is replaced automatically.")
                }
                if entry != nil {
                    Toggle("Enabled", isOn: $isEnabled)
                }
            }
            .navigationTitle(entry == nil ? "Add Word" : "Edit Word")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                        dismiss()
                    }
                    .disabled(correction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                correction = entry?.correction ?? ""
                heard = entry?.heard ?? ""
                isEnabled = entry?.isEnabled ?? true
            }
        }
    }

    private func save() {
        guard var entry else {
            model.addTerm(correction, heard: heard)
            return
        }
        entry.correction = correction.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.heard = heard.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.isEnabled = isEnabled
        model.save(entry)
    }
}
