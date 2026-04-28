import Foundation

public struct VocabularyEntry: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var heard: String
    public var correction: String
    public var isEnabled: Bool
    public var createdAt: Date
    public var lastUsedAt: Date?
    public var useCount: Int

    public init(
        id: UUID = UUID(),
        heard: String,
        correction: String,
        isEnabled: Bool = true,
        createdAt: Date = Date(),
        lastUsedAt: Date? = nil,
        useCount: Int = 0
    ) {
        self.id = id
        self.heard = heard
        self.correction = correction
        self.isEnabled = isEnabled
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
        self.useCount = useCount
    }
}
