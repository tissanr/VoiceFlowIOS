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
}
