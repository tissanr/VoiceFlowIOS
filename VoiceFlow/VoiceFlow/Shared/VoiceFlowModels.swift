//
//  VoiceFlowModels.swift
//  VoiceFlow
//
//  Shared models for App and Keyboard Extension.
//

import Foundation

public enum DictationState: String, Codable {
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

public enum KeyboardState: Codable, Equatable {
    case noSharedAccess
    case ready
    case hasPendingInsert(dictationID: UUID)
    case inserting
    case insertUnavailable(reason: InsertUnavailableReason)
}

public enum InsertUnavailableReason: String, Codable {
    case noPendingText
    case secureField
    case unsupportedKeyboardType
    case appDisallowsKeyboard
    case sharedStoreUnavailable
    case unknown
}

public struct PendingInsert: Codable, Equatable {
    public let dictationID: UUID
    public let text: String
    public let createdAt: Date
    public var consumedAt: Date?
    public var expiresAt: Date

    public init(dictationID: UUID, text: String, createdAt: Date = Date(), expiresAt: Date = Date().addingTimeInterval(600)) {
        self.dictationID = dictationID
        self.text = text
        self.createdAt = createdAt
        self.expiresAt = expiresAt
    }
    
    public var isExpired: Bool {
        return Date() > expiresAt
    }
}
