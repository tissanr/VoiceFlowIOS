import Foundation

/// One vocabulary item. Two shapes:
/// - a **term** (`heard` empty): a word VoiceFlow should recognize, passed to the recognizer as a hint;
/// - a **correction pair** (`heard` set): text the recognizer tends to produce, replaced by `correction`.
/// Both feed `correction` into recognition hints.
public struct VocabularyEntry: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var heard: String
    public var correction: String
    public var isEnabled: Bool
    public var createdAt: Date
    public var lastUsedAt: Date?
    public var useCount: Int
    public var status: VocabularyStatus
    public var source: VocabularySource
    /// How often this correction was observed. Suggestions seen repeatedly rank first.
    public var timesObserved: Int

    public init(
        id: UUID = UUID(),
        heard: String,
        correction: String,
        isEnabled: Bool = true,
        createdAt: Date = Date(),
        lastUsedAt: Date? = nil,
        useCount: Int = 0,
        status: VocabularyStatus = .active,
        source: VocabularySource = .manual,
        timesObserved: Int = 1
    ) {
        self.id = id
        self.heard = heard
        self.correction = correction
        self.isEnabled = isEnabled
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
        self.useCount = useCount
        self.status = status
        self.source = source
        self.timesObserved = timesObserved
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        heard = try container.decode(String.self, forKey: .heard)
        correction = try container.decode(String.self, forKey: .correction)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        lastUsedAt = try container.decodeIfPresent(Date.self, forKey: .lastUsedAt)
        useCount = try container.decodeIfPresent(Int.self, forKey: .useCount) ?? 0
        status = try container.decodeIfPresent(VocabularyStatus.self, forKey: .status) ?? .active
        source = try container.decodeIfPresent(VocabularySource.self, forKey: .source) ?? .manual
        timesObserved = try container.decodeIfPresent(Int.self, forKey: .timesObserved) ?? 1
    }

    public var isCorrectionPair: Bool {
        !heard.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Active entries are applied to recognition and postprocessing.
    public var isApplied: Bool {
        status == .active && isEnabled
    }
}

public enum VocabularyStatus: String, Codable, Equatable, CaseIterable, Sendable {
    /// Learned automatically; waits for the user to accept or reject it.
    case suggested
    /// Used for recognition hints and correction.
    case active
    /// Declined by the user; kept so the same pair is not suggested again.
    case rejected
}

public enum VocabularySource: String, Codable, Equatable, CaseIterable, Sendable {
    /// Added by hand in the containing app.
    case manual
    /// Learned from an edit in the containing app's history.
    case historyEdit
    /// Learned from a post-edit the keyboard noticed after inserting dictated text.
    case keyboardEdit
}
