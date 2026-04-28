import XCTest
@testable import VoiceFlowShared

final class VoiceFlowSharedTests: XCTestCase {
    func testPendingInsertDefaultExpiryUsesTenMinuteTTL() {
        let createdAt = Date(timeIntervalSince1970: 100)
        let insert = PendingInsert(
            dictationID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            text: "Hello",
            createdAt: createdAt,
            generation: 1,
            producedBy: .containingApp
        )

        XCTAssertEqual(insert.expiresAt, createdAt.addingTimeInterval(600))
        XCTAssertFalse(insert.isExpired(at: createdAt.addingTimeInterval(599)))
        XCTAssertTrue(insert.isExpired(at: createdAt.addingTimeInterval(600)))
    }

    func testModelsRoundTripThroughCodable() throws {
        let record = DictationRecord(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            createdAt: Date(timeIntervalSince1970: 200),
            sourceLocale: "en-US",
            rawText: "hello world",
            processedText: "Hello world.",
            correctionLevel: .soft,
            durationMs: 1_500,
            wordCount: 2,
            accuracyRatio: 0.98,
            state: .readyForReview
        )

        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(DictationRecord.self, from: data)

        XCTAssertEqual(decoded, record)
    }

    func testSharedStoreWritesMonotonicPendingInserts() throws {
        let defaults = makeDefaults()
        let client = SharedStoreClient(defaults: defaults) {
            Date(timeIntervalSince1970: 1_002)
        }

        let first = try client.writePendingInsert(
            text: "First",
            dictationID: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            producedBy: .containingApp,
            createdAt: Date(timeIntervalSince1970: 1_000)
        )
        let second = try client.writePendingInsert(
            text: "Second",
            dictationID: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
            producedBy: .keyboardExtension,
            createdAt: Date(timeIntervalSince1970: 1_001)
        )

        XCTAssertEqual(first.generation, 1)
        XCTAssertEqual(second.generation, 2)
        XCTAssertEqual(client.currentGeneration(), 2)
        XCTAssertEqual(try client.pendingInsertForKeyboard()?.text, "Second")
    }

    func testSharedStoreRejectsNonIncreasingGeneration() throws {
        let defaults = makeDefaults()
        let client = SharedStoreClient(defaults: defaults)

        _ = try client.writePendingInsert(
            text: "First",
            dictationID: UUID(),
            producedBy: .containingApp
        )

        let staleInsert = PendingInsert(
            dictationID: UUID(),
            text: "Stale",
            generation: 1,
            producedBy: .containingApp
        )

        XCTAssertThrowsError(try client.writePendingInsert(staleInsert)) { error in
            XCTAssertEqual(error as? SharedStoreError, .nonIncreasingGeneration(attempted: 1, current: 1))
        }
    }

    func testSharedStoreConsumeCreatesTombstoneAndPreservesPayload() throws {
        let defaults = makeDefaults()
        let consumedAt = Date(timeIntervalSince1970: 2_000)
        let client = SharedStoreClient(defaults: defaults) { consumedAt }

        let pendingInsert = try client.writePendingInsert(
            text: "Insert me",
            dictationID: UUID(),
            producedBy: .keyboardExtension
        )

        try client.consumePendingInsert(generation: pendingInsert.generation)

        XCTAssertEqual(client.consumedGeneration(), pendingInsert.generation)
        XCTAssertNil(try client.pendingInsertForKeyboard())
        XCTAssertEqual(try client.readPendingInsertPayload()?.text, "Insert me")
        XCTAssertEqual(try client.readPendingInsertPayload()?.consumedAt, consumedAt)
    }

    func testSharedStoreIgnoresExpiredPendingInsert() throws {
        let defaults = makeDefaults()
        let client = SharedStoreClient(defaults: defaults) {
            Date(timeIntervalSince1970: 1_601)
        }

        _ = try client.writePendingInsert(
            text: "Expired",
            dictationID: UUID(),
            producedBy: .containingApp,
            createdAt: Date(timeIntervalSince1970: 1_000)
        )

        XCTAssertNil(try client.pendingInsertForKeyboard())
        XCTAssertEqual(client.currentGeneration(), 1)
        XCTAssertEqual(client.consumedGeneration(), 0)
    }

    func testSharedStoreReportsCorruptPayload() throws {
        let defaults = makeDefaults()
        let client = SharedStoreClient(defaults: defaults)
        defaults.set(Data("not-json".utf8), forKey: SharedStoreKey.pendingInsertPayload)
        defaults.set(1, forKey: SharedStoreKey.pendingInsertGeneration)

        XCTAssertThrowsError(try client.pendingInsertForKeyboard()) { error in
            guard case .payloadDecodeFailed = error as? SharedStoreError else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "VoiceFlowSharedTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
