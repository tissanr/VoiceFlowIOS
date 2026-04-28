import Foundation

public struct SharedStoreClient {
    public static let defaultSuiteName = VoiceFlowConstants.appGroupIdentifier

    private let defaults: UserDefaults
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let now: () -> Date

    public init(
        suiteName: String = SharedStoreClient.defaultSuiteName,
        now: @escaping () -> Date = { Date() }
    ) throws {
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw SharedStoreError.appGroupUnavailable(suiteName: suiteName)
        }

        self.init(defaults: defaults, now: now)
    }

    public init(
        defaults: UserDefaults,
        now: @escaping () -> Date = { Date() }
    ) {
        self.defaults = defaults
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.now = now
    }

    @discardableResult
    public func writePendingInsert(
        text: String,
        dictationID: DictationID,
        producedBy: ProducerSide,
        createdAt: Date? = nil
    ) throws -> PendingInsert {
        let nextGeneration = defaults.integer(forKey: SharedStoreKey.pendingInsertGeneration) + 1
        let createdAt = createdAt ?? now()
        let pendingInsert = PendingInsert(
            dictationID: dictationID,
            text: text,
            createdAt: createdAt,
            generation: nextGeneration,
            producedBy: producedBy
        )

        try writePendingInsert(pendingInsert)
        return pendingInsert
    }

    public func writePendingInsert(_ pendingInsert: PendingInsert) throws {
        let currentGeneration = defaults.integer(forKey: SharedStoreKey.pendingInsertGeneration)
        guard pendingInsert.generation > currentGeneration else {
            throw SharedStoreError.nonIncreasingGeneration(
                attempted: pendingInsert.generation,
                current: currentGeneration
            )
        }

        let data = try encoder.encode(pendingInsert)
        defaults.set(data, forKey: SharedStoreKey.pendingInsertPayload)
        defaults.set(pendingInsert.generation, forKey: SharedStoreKey.pendingInsertGeneration)
    }

    public func pendingInsertForKeyboard() throws -> PendingInsert? {
        let generation = defaults.integer(forKey: SharedStoreKey.pendingInsertGeneration)
        let consumedGeneration = defaults.integer(forKey: SharedStoreKey.pendingInsertConsumedGeneration)

        guard generation > consumedGeneration else {
            return nil
        }

        guard let pendingInsert = try readPendingInsertPayload() else {
            return nil
        }

        guard pendingInsert.generation == generation else {
            throw SharedStoreError.generationMismatch(
                payloadGeneration: pendingInsert.generation,
                storedGeneration: generation
            )
        }

        guard !pendingInsert.isExpired(at: now()) else {
            return nil
        }

        return pendingInsert
    }

    public func consumePendingInsert(generation: Int, consumedAt: Date? = nil) throws {
        let currentGeneration = defaults.integer(forKey: SharedStoreKey.pendingInsertGeneration)
        guard generation == currentGeneration else {
            throw SharedStoreError.generationMismatch(
                payloadGeneration: generation,
                storedGeneration: currentGeneration
            )
        }

        var pendingInsert = try readPendingInsertPayload()
        pendingInsert?.consumedAt = consumedAt ?? now()

        if let pendingInsert {
            defaults.set(try encoder.encode(pendingInsert), forKey: SharedStoreKey.pendingInsertPayload)
        }

        defaults.set(generation, forKey: SharedStoreKey.pendingInsertConsumedGeneration)
    }

    public func readPendingInsertPayload() throws -> PendingInsert? {
        guard let data = defaults.data(forKey: SharedStoreKey.pendingInsertPayload) else {
            return nil
        }

        do {
            return try decoder.decode(PendingInsert.self, from: data)
        } catch {
            throw SharedStoreError.payloadDecodeFailed(error)
        }
    }

    public func currentGeneration() -> Int {
        defaults.integer(forKey: SharedStoreKey.pendingInsertGeneration)
    }

    public func consumedGeneration() -> Int {
        defaults.integer(forKey: SharedStoreKey.pendingInsertConsumedGeneration)
    }

    public func resetForTesting() {
        defaults.removeObject(forKey: SharedStoreKey.pendingInsertPayload)
        defaults.removeObject(forKey: SharedStoreKey.pendingInsertGeneration)
        defaults.removeObject(forKey: SharedStoreKey.pendingInsertConsumedGeneration)
    }
}

public enum SharedStoreKey {
    public static let pendingInsertPayload = "pendingInsert.payload"
    public static let pendingInsertGeneration = "pendingInsert.generation"
    public static let pendingInsertConsumedGeneration = "pendingInsert.consumedGen"
}

public enum SharedStoreError: Error, Equatable, Sendable {
    case appGroupUnavailable(suiteName: String)
    case nonIncreasingGeneration(attempted: Int, current: Int)
    case generationMismatch(payloadGeneration: Int, storedGeneration: Int)
    case payloadDecodeFailed(String)

    public static func payloadDecodeFailed(_ error: Error) -> SharedStoreError {
        .payloadDecodeFailed(String(describing: error))
    }
}
