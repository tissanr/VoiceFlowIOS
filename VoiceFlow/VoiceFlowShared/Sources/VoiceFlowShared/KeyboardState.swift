import Foundation

public enum KeyboardState: Codable, Equatable, Sendable {
    case noSharedAccess
    case ready
    case recording
    case transcribing
    case hasPendingInsert(DictationID)
    case inserting
    case insertUnavailable(reason: InsertUnavailableReason)
}

public enum InsertUnavailableReason: String, Codable, Equatable, Sendable {
    case noPendingText
    case secureField
    case unsupportedKeyboardType
    case appDisallowsKeyboard
    case sharedStoreUnavailable
    case openAccessRequired
    case unknown
}
