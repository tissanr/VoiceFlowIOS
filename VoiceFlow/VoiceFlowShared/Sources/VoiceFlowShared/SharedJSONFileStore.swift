import Foundation

/// A small Codable value persisted as one JSON file, guarded by a cross-process file lock.
///
/// Used for vocabulary, dictation history, and the keyboard edit watch. Reads and writes are
/// whole-file and atomic, so an extension killed mid-write never leaves a torn file behind.
/// Intended for small payloads (tens of KB), not bulk data.
public struct SharedJSONFileStore<Value: Codable> {
    public let fileURL: URL
    private let lock: SharedStoreLock
    private let defaultValue: () -> Value

    public init(fileURL: URL, defaultValue: @escaping @autoclosure () -> Value) {
        self.fileURL = fileURL
        self.lock = SharedStoreLock(fileURL: fileURL.appendingPathExtension("lock"))
        self.defaultValue = defaultValue
    }

    public func read() throws -> Value {
        try lock.withExclusiveLock {
            try readUnlocked()
        }
    }

    /// Read-modify-write under the lock. The mutated value is written back atomically.
    @discardableResult
    public func update<T>(_ body: (inout Value) throws -> T) throws -> T {
        try lock.withExclusiveLock {
            var value = try readUnlocked()
            let result = try body(&value)
            try writeUnlocked(value)
            return result
        }
    }

    public func write(_ value: Value) throws {
        try lock.withExclusiveLock {
            try writeUnlocked(value)
        }
    }

    private func readUnlocked() throws -> Value {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return defaultValue()
        }

        let data = try Data(contentsOf: fileURL)
        do {
            return try Self.decoder.decode(Value.self, from: data)
        } catch {
            throw SharedStoreError.payloadDecodeFailed(error)
        }
    }

    private func writeUnlocked(_ value: Value) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try Self.encoder.encode(value)
        try data.write(to: fileURL, options: .atomic)
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

public enum SharedContainer {
    /// Root of the App Group container, or `nil` when the entitlement is missing.
    public static func url(appGroupIdentifier: String = VoiceFlowConstants.appGroupIdentifier) -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
    }

    /// Directory holding VoiceFlow's JSON stores inside the App Group container.
    public static func storeDirectory(appGroupIdentifier: String = VoiceFlowConstants.appGroupIdentifier) throws -> URL {
        guard let root = url(appGroupIdentifier: appGroupIdentifier) else {
            throw SharedStoreError.appGroupUnavailable(suiteName: appGroupIdentifier)
        }
        return root.appendingPathComponent("Stores", isDirectory: true)
    }
}
