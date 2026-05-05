import Foundation
import Darwin

public struct SharedStoreClient {
    public static let defaultSuiteName = VoiceFlowConstants.appGroupIdentifier

    private let defaults: UserDefaults
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let now: () -> Date
    private let lock: SharedStoreLock
    private let suiteName: String?

    public init(
        suiteName: String = SharedStoreClient.defaultSuiteName,
        lockFileURL: URL? = nil,
        now: @escaping () -> Date = { Date() }
    ) throws {
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw SharedStoreError.appGroupUnavailable(suiteName: suiteName)
        }

        guard let resolvedLockFileURL = lockFileURL ?? Self.lockFileURL(suiteName: suiteName) else {
            throw SharedStoreError.appGroupUnavailable(suiteName: suiteName)
        }

        self.init(
            defaults: defaults,
            suiteName: suiteName,
            lockFileURL: resolvedLockFileURL,
            now: now
        )
    }

    public init(
        defaults: UserDefaults,
        lockFileURL: URL? = nil,
        now: @escaping () -> Date = { Date() }
    ) {
        self.init(defaults: defaults, suiteName: nil, lockFileURL: lockFileURL, now: now)
    }

    private init(
        defaults: UserDefaults,
        suiteName: String?,
        lockFileURL: URL?,
        now: @escaping () -> Date
    ) {
        self.defaults = defaults
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.now = now
        self.lock = SharedStoreLock(fileURL: lockFileURL ?? Self.temporaryLockFileURL(name: "default"))
        self.suiteName = suiteName
    }

    @discardableResult
    public func writePendingInsert(
        text: String,
        dictationID: DictationID,
        producedBy: ProducerSide,
        createdAt: Date? = nil
    ) throws -> PendingInsert {
        try lock.withExclusiveLock {
            synchronizeStore()
            let nextGeneration = int(forKey: SharedStoreKey.pendingInsertGeneration) + 1
            let createdAt = createdAt ?? now()
            let pendingInsert = PendingInsert(
                dictationID: dictationID,
                text: text,
                createdAt: createdAt,
                generation: nextGeneration,
                producedBy: producedBy
            )

            try writePendingInsertUnlocked(pendingInsert)
            return pendingInsert
        }
    }

    public func writePendingInsert(_ pendingInsert: PendingInsert) throws {
        try lock.withExclusiveLock {
            try writePendingInsertUnlocked(pendingInsert)
        }
    }

    private func writePendingInsertUnlocked(_ pendingInsert: PendingInsert) throws {
        synchronizeStore()
        let currentGeneration = int(forKey: SharedStoreKey.pendingInsertGeneration)
        guard pendingInsert.generation > currentGeneration else {
            throw SharedStoreError.nonIncreasingGeneration(
                attempted: pendingInsert.generation,
                current: currentGeneration
            )
        }

        let data = try encoder.encode(pendingInsert)
        set(data, forKey: SharedStoreKey.pendingInsertPayload)
        set(pendingInsert.generation, forKey: SharedStoreKey.pendingInsertGeneration)
        synchronizeStore()
    }

    public func pendingInsertForKeyboard() throws -> PendingInsert? {
        try lock.withExclusiveLock {
            synchronizeStore()
            let generation = int(forKey: SharedStoreKey.pendingInsertGeneration)
            let consumedGeneration = int(forKey: SharedStoreKey.pendingInsertConsumedGeneration)

            guard generation > consumedGeneration else {
                return nil
            }

            guard let pendingInsert = try readPendingInsertPayloadUnlocked() else {
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
    }

    public func consumePendingInsert(generation: Int, consumedAt: Date? = nil) throws {
        try lock.withExclusiveLock {
            synchronizeStore()
            let currentGeneration = int(forKey: SharedStoreKey.pendingInsertGeneration)
            guard generation == currentGeneration else {
                throw SharedStoreError.generationMismatch(
                    payloadGeneration: generation,
                    storedGeneration: currentGeneration
                )
            }

            var pendingInsert = try readPendingInsertPayloadUnlocked()
            pendingInsert?.consumedAt = consumedAt ?? now()

            if let pendingInsert {
                set(try encoder.encode(pendingInsert), forKey: SharedStoreKey.pendingInsertPayload)
            }

            set(generation, forKey: SharedStoreKey.pendingInsertConsumedGeneration)
            synchronizeStore()
        }
    }

    public func readPendingInsertPayload() throws -> PendingInsert? {
        try lock.withExclusiveLock {
            synchronizeStore()
            return try readPendingInsertPayloadUnlocked()
        }
    }

    private func readPendingInsertPayloadUnlocked() throws -> PendingInsert? {
        guard let data = data(forKey: SharedStoreKey.pendingInsertPayload) else {
            return nil
        }

        do {
            return try decoder.decode(PendingInsert.self, from: data)
        } catch {
            throw SharedStoreError.payloadDecodeFailed(error)
        }
    }

    public func currentGeneration() -> Int {
        (try? lock.withExclusiveLock {
            synchronizeStore()
            return int(forKey: SharedStoreKey.pendingInsertGeneration)
        }) ?? int(forKey: SharedStoreKey.pendingInsertGeneration)
    }

    public func consumedGeneration() -> Int {
        (try? lock.withExclusiveLock {
            synchronizeStore()
            return int(forKey: SharedStoreKey.pendingInsertConsumedGeneration)
        }) ?? int(forKey: SharedStoreKey.pendingInsertConsumedGeneration)
    }

    public func resetForTesting() {
        try? lock.withExclusiveLock {
            synchronizeStore()
            removeObject(forKey: SharedStoreKey.pendingInsertPayload)
            removeObject(forKey: SharedStoreKey.pendingInsertGeneration)
            removeObject(forKey: SharedStoreKey.pendingInsertConsumedGeneration)
            synchronizeStore()
        }
    }

    private func synchronizeStore() {
        if let suiteName {
            CFPreferencesAppSynchronize(suiteName as CFString)
        } else {
            defaults.synchronize()
        }
    }

    private func data(forKey key: String) -> Data? {
        if let value = preferencesValue(forKey: key) {
            return value as? Data
        }

        return defaults.data(forKey: key)
    }

    private func int(forKey key: String) -> Int {
        if let value = preferencesValue(forKey: key) {
            if let number = value as? NSNumber {
                return number.intValue
            }

            if let int = value as? Int {
                return int
            }
        }

        return defaults.integer(forKey: key)
    }

    private func set(_ data: Data, forKey key: String) {
        if let suiteName {
            CFPreferencesSetAppValue(key as CFString, data as CFData, suiteName as CFString)
        } else {
            defaults.set(data, forKey: key)
        }
    }

    private func set(_ int: Int, forKey key: String) {
        if let suiteName {
            CFPreferencesSetAppValue(key as CFString, NSNumber(value: int), suiteName as CFString)
        } else {
            defaults.set(int, forKey: key)
        }
    }

    private func removeObject(forKey key: String) {
        if let suiteName {
            CFPreferencesSetAppValue(key as CFString, nil, suiteName as CFString)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    private func preferencesValue(forKey key: String) -> Any? {
        guard let suiteName else {
            return nil
        }

        return CFPreferencesCopyAppValue(key as CFString, suiteName as CFString)
    }

    private static func lockFileURL(suiteName: String) -> URL? {
        guard let directory = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: suiteName)?
            .appendingPathComponent("Locks", isDirectory: true)
        else {
            return nil
        }

        return directory.appendingPathComponent("pending-insert.lock")
    }

    private static func temporaryLockFileURL(name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceFlowSharedStoreLocks", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
            .appendingPathComponent("pending-insert.lock")
    }
}

private struct SharedStoreLock {
    let fileURL: URL

    func withExclusiveLock<T>(_ body: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let fileDescriptor = open(fileURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard fileDescriptor >= 0 else {
            throw SharedStoreError.lockUnavailable(path: fileURL.path, errnoCode: errno)
        }

        defer {
            close(fileDescriptor)
        }

        guard flock(fileDescriptor, LOCK_EX) == 0 else {
            throw SharedStoreError.lockUnavailable(path: fileURL.path, errnoCode: errno)
        }

        defer {
            flock(fileDescriptor, LOCK_UN)
        }

        return try body()
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
    case lockUnavailable(path: String, errnoCode: Int32)

    public static func payloadDecodeFailed(_ error: Error) -> SharedStoreError {
        .payloadDecodeFailed(String(describing: error))
    }
}
