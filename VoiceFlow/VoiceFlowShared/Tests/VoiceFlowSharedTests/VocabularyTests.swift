import XCTest
@testable import VoiceFlowShared

final class VocabularyLearnerTests: XCTestCase {
    func testLearnsMisrecognizedProductName() {
        let candidates = VocabularyLearner.candidates(
            raw: "Ich öffne jetzt voice flow auf dem Telefon.",
            corrected: "Ich öffne jetzt VoiceFlow auf dem Telefon."
        )
        XCTAssertEqual(candidates, [VocabularyCandidate(heard: "voice flow", correction: "VoiceFlow")])
    }

    func testLearnsPhoneticallySimilarTerm() {
        let candidates = VocabularyLearner.candidates(
            raw: "Wir deployen das auf Cuba Netis.",
            corrected: "Wir deployen das auf Kubernetes."
        )
        XCTAssertEqual(candidates, [VocabularyCandidate(heard: "Cuba Netis", correction: "Kubernetes")])
    }

    func testIgnoresRewritesInsertionsAndPunctuation() {
        XCTAssertEqual(VocabularyLearner.candidates(raw: "Wir treffen uns gestern", corrected: "Wir treffen uns heute"), [])
        XCTAssertEqual(VocabularyLearner.candidates(raw: "Wir treffen uns", corrected: "Wir treffen uns morgen früh"), [])
        XCTAssertEqual(VocabularyLearner.candidates(raw: "Hallo Welt", corrected: "Hallo, Welt!"), [])
    }

    func testIgnoresSentenceStartCapitalizationButKeepsInnerCaps() {
        XCTAssertEqual(VocabularyLearner.candidates(raw: "heute geht es los", corrected: "Heute geht es los"), [])
        XCTAssertEqual(
            VocabularyLearner.candidates(raw: "Mein neues iphone ist da", corrected: "Mein neues iPhone ist da"),
            [VocabularyCandidate(heard: "iphone", correction: "iPhone")]
        )
    }

    func testEditedSegmentFindsUserCorrectionInContext() {
        let segment = VocabularyLearner.editedSegment(
            inserted: "Bitte schick das an Herrn Meier",
            context: "Hallo Team. Bitte schick das an Herrn Maier"
        )
        XCTAssertEqual(segment, "Bitte schick das an Herrn Maier")
        XCTAssertNil(VocabularyLearner.editedSegment(inserted: "Bitte schick das", context: "Hallo. Bitte schick das"))
        XCTAssertNil(VocabularyLearner.editedSegment(inserted: "Bitte schick das an Herrn Meier", context: "Ganz anderer Text hier"))
    }
}

final class VocabularyCorrectorTests: XCTestCase {
    func testAppliesActivePairsOnWordBoundaries() {
        let pair = VocabularyEntry(heard: "voice flow", correction: "VoiceFlow")
        let result = VocabularyCorrector.apply([pair], to: "Voice  flow ist cool, voice flowers nicht.")
        XCTAssertEqual(result.text, "VoiceFlow ist cool, voice flowers nicht.")
        XCTAssertEqual(result.appliedEntryIDs, [pair.id])
    }

    func testSkipsSuggestedAndDisabledEntries() {
        let suggested = VocabularyEntry(heard: "meier", correction: "Maier", status: .suggested)
        let disabled = VocabularyEntry(heard: "kuba", correction: "Kubernetes", isEnabled: false)
        let result = VocabularyCorrector.apply([suggested, disabled], to: "meier und kuba")
        XCTAssertEqual(result.text, "meier und kuba")
        XCTAssertTrue(result.appliedEntryIDs.isEmpty)
    }

    func testCapitalizesAtSentenceStart() {
        let pair = VocabularyEntry(heard: "cube", correction: "kubectl")
        XCTAssertEqual(VocabularyCorrector.apply([pair], to: "Cube läuft").text, "Kubectl läuft")
    }

    func testRecognitionHintsAreDistinctActiveTermsByUse() {
        let entries = [
            VocabularyEntry(heard: "", correction: "Kubernetes", useCount: 1),
            VocabularyEntry(heard: "voice flow", correction: "VoiceFlow", useCount: 5),
            VocabularyEntry(heard: "voiceflo", correction: "voiceflow", useCount: 0),
            VocabularyEntry(heard: "", correction: "Maier", status: .suggested)
        ]
        XCTAssertEqual(VocabularyCorrector.recognitionHints(from: entries), ["VoiceFlow", "Kubernetes"])
    }
}

final class VocabularyStoreTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testSuggestionsMergeAndRespectRejections() throws {
        let store = VocabularyStore(directory: directory)
        let candidate = VocabularyCandidate(heard: "voice flow", correction: "VoiceFlow")

        let first = try store.addSuggestions([candidate], source: .keyboardEdit)
        XCTAssertEqual(first.first?.status, .suggested)

        try store.addSuggestions([candidate], source: .historyEdit)
        XCTAssertEqual(try store.entries().count, 1)
        XCTAssertEqual(try store.entries().first?.timesObserved, 2)

        try store.setStatus(.rejected, for: first[0].id)
        XCTAssertTrue(try store.addSuggestions([candidate], source: .keyboardEdit).isEmpty)
        XCTAssertEqual(try store.entries().first?.status, .rejected)
    }

    func testManualTermAndUseCountPersist() throws {
        let store = VocabularyStore(directory: directory)
        let entry = try store.addManual(correction: " Kubernetes ")
        try store.recordUse(of: [entry.id])

        let reloaded = try VocabularyStore(directory: directory).entries()
        XCTAssertEqual(reloaded.map(\.correction), ["Kubernetes"])
        XCTAssertEqual(reloaded.first?.useCount, 1)
        XCTAssertEqual(reloaded.first?.status, .active)
    }

    func testHistoryIsNewestFirstAndCapped() throws {
        let store = DictationHistoryStore(directory: directory, limit: 2)
        for text in ["a", "b", "c"] {
            try store.upsert(DictationRecord(sourceLocale: "de-DE", rawText: text, processedText: text, correctionLevel: .soft, durationMs: 0, wordCount: 1, state: .readyForReview))
        }
        XCTAssertEqual(try store.records().map(\.rawText), ["c", "b"])
    }

    func testSettingsDecodeToleratesMissingKeys() throws {
        let data = Data(#"{"localeMode":"german"}"#.utf8)
        let settings = try JSONDecoder().decode(VoiceFlowSettings.self, from: data)
        XCTAssertEqual(settings.localeMode, .german)
        XCTAssertTrue(settings.learnFromKeyboardEdits)
    }
}
