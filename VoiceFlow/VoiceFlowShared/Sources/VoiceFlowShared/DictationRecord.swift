import Foundation

public typealias DictationID = UUID

public struct DictationRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: DictationID
    public let createdAt: Date
    public var sourceLocale: String
    public var rawText: String
    public var processedText: String
    public var correctionLevel: CorrectionLevel
    public var durationMs: Int
    public var wordCount: Int
    public var accuracyRatio: Double?
    public var state: DictationState
    public var insertedAt: Date?
    /// The user's corrected version, set when they edit the dictation in History.
    public var editedText: String?

    public init(
        id: DictationID = DictationID(),
        createdAt: Date = Date(),
        sourceLocale: String,
        rawText: String,
        processedText: String,
        correctionLevel: CorrectionLevel,
        durationMs: Int,
        wordCount: Int,
        accuracyRatio: Double? = nil,
        state: DictationState,
        insertedAt: Date? = nil,
        editedText: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.sourceLocale = sourceLocale
        self.rawText = rawText
        self.processedText = processedText
        self.correctionLevel = correctionLevel
        self.durationMs = durationMs
        self.wordCount = wordCount
        self.accuracyRatio = accuracyRatio
        self.state = state
        self.insertedAt = insertedAt
        self.editedText = editedText
    }

    /// The best available text: the user's edit, else the postprocessed text.
    public var finalText: String {
        editedText ?? processedText
    }
}

public enum DictationState: String, Codable, Equatable, Sendable {
    case idle
    case requestingPermissions
    case recording
    case transcribing
    case processing
    case readyForReview
    case pendingInsert
    case inserted
    case failed
}
