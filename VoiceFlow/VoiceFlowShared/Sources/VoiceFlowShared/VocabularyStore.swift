import Foundation

/// Vocabulary persisted as one JSON file in the App Group container.
/// The containing app manages entries; the keyboard reads them at dictation start and may add
/// suggestions it learned from post-edits.
public struct VocabularyStore {
    struct Payload: Codable {
        var version = 1
        var entries: [VocabularyEntry] = []
    }

    private let file: SharedJSONFileStore<Payload>
    private let now: () -> Date

    public init(directory: URL, now: @escaping () -> Date = { Date() }) {
        self.file = SharedJSONFileStore(
            fileURL: directory.appendingPathComponent("vocabulary.json"),
            defaultValue: Payload()
        )
        self.now = now
    }

    public static func appGroup() throws -> VocabularyStore {
        VocabularyStore(directory: try SharedContainer.storeDirectory())
    }

    public func entries() throws -> [VocabularyEntry] {
        try file.read().entries
    }

    /// Adds a term (and optionally what the recognizer hears instead) as an active entry.
    @discardableResult
    public func addManual(correction: String, heard: String = "") throws -> VocabularyEntry {
        let correction = correction.trimmingCharacters(in: .whitespacesAndNewlines)
        let heard = heard.trimmingCharacters(in: .whitespacesAndNewlines)
        return try file.update { payload in
            if let index = payload.entries.firstIndex(where: { $0.matches(heard: heard, correction: correction) }) {
                payload.entries[index].status = .active
                payload.entries[index].isEnabled = true
                return payload.entries[index]
            }
            let entry = VocabularyEntry(heard: heard, correction: correction, createdAt: now(), status: .active, source: .manual)
            payload.entries.append(entry)
            return entry
        }
    }

    /// Merges learned candidates. New pairs become suggestions; known suggestions count up;
    /// active and rejected pairs are left alone. Returns entries that are new or still suggested.
    @discardableResult
    public func addSuggestions(_ candidates: [VocabularyCandidate], source: VocabularySource) throws -> [VocabularyEntry] {
        guard !candidates.isEmpty else { return [] }
        return try file.update { payload in
            var touched: [VocabularyEntry] = []
            for candidate in candidates {
                if let index = payload.entries.firstIndex(where: { $0.matches(heard: candidate.heard, correction: candidate.correction) }) {
                    payload.entries[index].timesObserved += 1
                    if payload.entries[index].status == .suggested {
                        touched.append(payload.entries[index])
                    }
                    continue
                }
                let entry = VocabularyEntry(
                    heard: candidate.heard,
                    correction: candidate.correction,
                    createdAt: now(),
                    status: .suggested,
                    source: source
                )
                payload.entries.append(entry)
                touched.append(entry)
            }
            return touched
        }
    }

    public func save(_ entry: VocabularyEntry) throws {
        try file.update { payload in
            if let index = payload.entries.firstIndex(where: { $0.id == entry.id }) {
                payload.entries[index] = entry
            } else {
                payload.entries.append(entry)
            }
        }
    }

    public func setStatus(_ status: VocabularyStatus, for id: UUID) throws {
        try file.update { payload in
            guard let index = payload.entries.firstIndex(where: { $0.id == id }) else { return }
            payload.entries[index].status = status
            if status == .active {
                payload.entries[index].isEnabled = true
            }
        }
    }

    public func delete(id: UUID) throws {
        try file.update { payload in
            payload.entries.removeAll { $0.id == id }
        }
    }

    public func recordUse(of ids: [UUID]) throws {
        guard !ids.isEmpty else { return }
        let date = now()
        try file.update { payload in
            for index in payload.entries.indices where ids.contains(payload.entries[index].id) {
                payload.entries[index].useCount += 1
                payload.entries[index].lastUsedAt = date
            }
        }
    }
}

extension VocabularyEntry {
    func matches(heard: String, correction: String) -> Bool {
        self.heard.lowercased() == heard.lowercased() && self.correction == correction
    }
}
