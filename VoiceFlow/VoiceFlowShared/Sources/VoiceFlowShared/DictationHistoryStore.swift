import Foundation

/// Recent dictations, newest first, capped. Written by whoever produced the dictation
/// (keyboard or containing app); edited in the containing app to teach vocabulary.
public struct DictationHistoryStore {
    public static let defaultLimit = 100

    struct Payload: Codable {
        var version = 1
        var records: [DictationRecord] = []
    }

    private let file: SharedJSONFileStore<Payload>
    private let limit: Int

    public init(directory: URL, limit: Int = DictationHistoryStore.defaultLimit) {
        self.file = SharedJSONFileStore(
            fileURL: directory.appendingPathComponent("history.json"),
            defaultValue: Payload()
        )
        self.limit = limit
    }

    public static func appGroup() throws -> DictationHistoryStore {
        DictationHistoryStore(directory: try SharedContainer.storeDirectory())
    }

    public func records() throws -> [DictationRecord] {
        try file.read().records
    }

    public func upsert(_ record: DictationRecord) throws {
        try file.update { payload in
            if let index = payload.records.firstIndex(where: { $0.id == record.id }) {
                payload.records[index] = record
            } else {
                payload.records.insert(record, at: 0)
                if payload.records.count > limit {
                    payload.records.removeLast(payload.records.count - limit)
                }
            }
        }
    }

    public func delete(id: DictationID) throws {
        try file.update { payload in
            payload.records.removeAll { $0.id == id }
        }
    }

    public func deleteAll() throws {
        try file.write(Payload())
    }
}
