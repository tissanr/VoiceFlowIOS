import Foundation
import Observation
import VoiceFlowParakeet
import VoiceFlowShared
import VoiceFlowWhisper

enum AppTab: Hashable {
    case dictate, history, words, settings
}

/// App-wide state over the App Group stores. Reloaded whenever the app becomes active,
/// because the keyboard writes history and suggestions while the app is in the background.
@Observable
final class AppModel {
    private(set) var vocabulary: [VocabularyEntry] = []
    private(set) var history: [DictationRecord] = []
    private(set) var settings: VoiceFlowSettings = .defaults
    var errorMessage: String?
    var selectedTab: AppTab = .dictate
    /// Shown in Settings so the Open Access spike can observe `voiceflow://` launches.
    var lastOpenedURL: URL?
    /// Long-lived so the Whisper model loads once, not per dictation.
    let whisper: WhisperModelManager

    private let vocabularyStore: VocabularyStore?
    private let historyStore: DictationHistoryStore?
    private let settingsStore: SettingsStore?

    init() {
        vocabularyStore = try? VocabularyStore.appGroup()
        historyStore = try? DictationHistoryStore.appGroup()
        settingsStore = try? SettingsStore.appGroup()
        let initialSettings = settingsStore?.load() ?? .defaults
        whisper = WhisperModelManager(variant: initialSettings.whisperModel)
        if vocabularyStore == nil || historyStore == nil || settingsStore == nil {
            errorMessage = "The shared App Group container is unavailable. Check the app's entitlements."
        }
        reload()
    }

    var suggestions: [VocabularyEntry] {
        vocabulary
            .filter { $0.status == .suggested }
            .sorted { ($0.timesObserved, $0.createdAt) > ($1.timesObserved, $1.createdAt) }
    }

    var activeEntries: [VocabularyEntry] {
        vocabulary
            .filter { $0.status == .active }
            .sorted { $0.correction.localizedCaseInsensitiveCompare($1.correction) == .orderedAscending }
    }

    var rejectedEntries: [VocabularyEntry] {
        vocabulary.filter { $0.status == .rejected }
    }

    func reload() {
        perform {
            vocabulary = try vocabularyStore?.entries() ?? []
            history = try historyStore?.records() ?? []
        }
        settings = settingsStore?.load() ?? .defaults
        whisper.select(settings.whisperModel)
    }

    /// Loads an already downloaded app-only model (Whisper / Parakeet) in the background so the first dictation starts quickly.
    /// Never starts a download on its own: that is an explicit user action in Settings.
    func warmUpSpeechEngine() async {
        switch settings.speechEngine {
        case .whisper:
            guard whisper.state == .downloaded else { return }
            await whisper.prepare()
        case .parakeet:
            ParakeetModelStore.shared.warmUp()
        default:
            break
        }
    }

    // MARK: - Vocabulary

    func addTerm(_ correction: String, heard: String) {
        guard !correction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        perform { try vocabularyStore?.addManual(correction: correction, heard: heard) }
    }

    func setStatus(_ status: VocabularyStatus, for entry: VocabularyEntry) {
        perform { try vocabularyStore?.setStatus(status, for: entry.id) }
    }

    func save(_ entry: VocabularyEntry) {
        perform { try vocabularyStore?.save(entry) }
    }

    func delete(_ entry: VocabularyEntry) {
        perform { try vocabularyStore?.delete(id: entry.id) }
    }

    // MARK: - Dictation

    /// Runs the postprocessing pipeline (correction pairs + normalization) on recognized text.
    func process(_ rawText: String) -> PostProcessor.Result {
        let result = PostProcessor.process(rawText, vocabulary: vocabulary, level: settings.correctionLevel)
        perform { try vocabularyStore?.recordUse(of: result.appliedEntryIDs) }
        return result
    }

    var recognitionHints: [String] {
        VocabularyCorrector.recognitionHints(from: vocabulary)
    }

    func saveDictation(_ record: DictationRecord) {
        perform { try historyStore?.upsert(record) }
    }

    /// Stores the user's edit and learns suggestions from it. Returns how many were found.
    @discardableResult
    func saveEdit(of record: DictationRecord, editedText: String) -> Int {
        var updated = record
        updated.editedText = editedText == record.processedText ? nil : editedText

        var learned = 0
        perform {
            try historyStore?.upsert(updated)
            let candidates = VocabularyLearner.candidates(raw: record.processedText, corrected: editedText)
            learned = try vocabularyStore?.addSuggestions(candidates, source: .historyEdit).count ?? 0
        }
        return learned
    }

    func deleteDictation(_ record: DictationRecord) {
        perform { try historyStore?.delete(id: record.id) }
    }

    // MARK: - Settings

    func update(_ change: (inout VoiceFlowSettings) -> Void) {
        var next = settings
        change(&next)
        do {
            try settingsStore?.save(next)
            settings = next
            whisper.select(next.whisperModel)
            if next.speechEngine != .whisper {
                // A loaded large Whisper model holds hundreds of MB; release it when not in use.
                whisper.unload()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func perform(_ body: () throws -> Void) {
        do {
            try body()
            vocabulary = try vocabularyStore?.entries() ?? vocabulary
            history = try historyStore?.records() ?? history
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

extension WhisperModelManager {
    /// Human-readable model state for Dictate and Settings.
    var statusText: String {
        switch state {
        case .notDownloaded:
            return "Not downloaded (about \(variant.approximateSizeMB) MB)"
        case .downloading(let progress):
            return "Downloading model… \(Int(progress * 100)) %"
        case .downloaded:
            return "Downloaded, not loaded"
        case .loading:
            return "Loading model… The first load after download can take a few minutes."
        case .ready:
            return "Ready"
        case .failed(let message):
            return "Failed: \(message)"
        }
    }
}
