import Foundation

public struct PendingInsert: Codable, Equatable, Sendable {
    public let dictationID: DictationID
    public let text: String
    public let createdAt: Date
    public var consumedAt: Date?
    public var expiresAt: Date
    public let generation: Int
    public let producedBy: ProducerSide

    public init(
        dictationID: DictationID,
        text: String,
        createdAt: Date = Date(),
        consumedAt: Date? = nil,
        expiresAt: Date? = nil,
        generation: Int,
        producedBy: ProducerSide
    ) {
        self.dictationID = dictationID
        self.text = text
        self.createdAt = createdAt
        self.consumedAt = consumedAt
        self.expiresAt = expiresAt ?? createdAt.addingTimeInterval(VoiceFlowConstants.pendingInsertTimeToLive)
        self.generation = generation
        self.producedBy = producedBy
    }

    public func isExpired(at date: Date = Date()) -> Bool {
        date >= expiresAt
    }
}

public enum ProducerSide: String, Codable, Equatable, Sendable {
    case keyboardExtension
    case containingApp
}
