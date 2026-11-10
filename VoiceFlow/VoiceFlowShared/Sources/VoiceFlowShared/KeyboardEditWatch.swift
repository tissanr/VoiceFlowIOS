import Foundation

/// The last text the keyboard inserted, kept so the keyboard can notice the user's later
/// correction of it (made with another keyboard) when it becomes active again.
///
/// Persisted because iOS often terminates the extension while another keyboard is active.
/// Only text VoiceFlow itself inserted is compared; nothing else from the host field is stored.
public struct KeyboardEditWatch: Codable, Equatable, Sendable {
    public static let timeToLive: TimeInterval = 15 * 60

    public var dictationID: DictationID
    public var insertedText: String
    public var insertedAt: Date

    public init(dictationID: DictationID, insertedText: String, insertedAt: Date) {
        self.dictationID = dictationID
        self.insertedText = insertedText
        self.insertedAt = insertedAt
    }

    public func isExpired(at date: Date) -> Bool {
        date.timeIntervalSince(insertedAt) > Self.timeToLive
    }
}

public struct KeyboardEditWatchStore {
    struct Payload: Codable {
        var watch: KeyboardEditWatch?
    }

    private let file: SharedJSONFileStore<Payload>

    public init(directory: URL) {
        file = SharedJSONFileStore(fileURL: directory.appendingPathComponent("keyboard-edit-watch.json"), defaultValue: Payload())
    }

    public static func appGroup() throws -> KeyboardEditWatchStore {
        KeyboardEditWatchStore(directory: try SharedContainer.storeDirectory())
    }

    public func current() throws -> KeyboardEditWatch? {
        try file.read().watch
    }

    public func set(_ watch: KeyboardEditWatch?) throws {
        try file.write(Payload(watch: watch))
    }
}
