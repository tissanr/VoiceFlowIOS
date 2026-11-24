import XCTest
@testable import VoiceFlowShared

final class SpeechEngineSelectionTests: XCTestCase {
    private let allReady = SpeechEngineAvailability(speechAnalyzerReady: true, parakeetReady: true)
    private let noneReady = SpeechEngineAvailability(speechAnalyzerReady: false, parakeetReady: false)

    private func resolve(
        _ preference: SpeechEngineKind,
        host: SpeechEngineHost = .containingApp,
        availability: SpeechEngineAvailability,
        settings: VoiceFlowSettings = .defaults
    ) -> ResolvedSpeechEngine {
        SpeechEngineSelection.resolve(preference: preference, settings: settings, host: host, availability: availability)
    }

    func testAutomaticPrefersSpeechAnalyzerWhenReady() {
        XCTAssertEqual(resolve(.automatic, availability: allReady), .appleSpeechAnalyzer)
        XCTAssertEqual(resolve(.automatic, host: .keyboardExtension, availability: allReady), .appleSpeechAnalyzer)
    }

    func testAutomaticFallsBackToClassicWhenAnalyzerNotReady() {
        XCTAssertEqual(resolve(.automatic, availability: noneReady), .appleClassic)
    }

    func testAutomaticKeepsClassicWhenUserWantsServerRecognition() {
        let settings = VoiceFlowSettings(preferOnDeviceSpeech: false, privacyMode: .externalLLMAllowed)
        XCTAssertEqual(resolve(.automatic, availability: allReady, settings: settings), .appleClassic)
    }

    func testAutomaticNeverPicksParakeet() {
        XCTAssertNotEqual(resolve(.automatic, availability: allReady), .parakeet)
    }

    func testClassicIsAlwaysHonored() {
        XCTAssertEqual(resolve(.appleClassic, availability: allReady), .appleClassic)
    }

    func testExplicitSpeechAnalyzerFallsBackWhenNotReady() {
        XCTAssertEqual(resolve(.appleSpeechAnalyzer, availability: allReady), .appleSpeechAnalyzer)
        XCTAssertEqual(resolve(.appleSpeechAnalyzer, availability: noneReady), .appleClassic)
    }

    func testParakeetRunsOnlyInContainingApp() {
        XCTAssertEqual(resolve(.parakeet, host: .containingApp, availability: allReady), .parakeet)
        XCTAssertEqual(resolve(.parakeet, host: .keyboardExtension, availability: allReady), .appleSpeechAnalyzer)
    }

    func testParakeetWithoutModelsFallsBackToBestAppleEngine() {
        let analyzerOnly = SpeechEngineAvailability(speechAnalyzerReady: true, parakeetReady: false)
        XCTAssertEqual(resolve(.parakeet, availability: analyzerOnly), .appleSpeechAnalyzer)
        XCTAssertEqual(resolve(.parakeet, availability: noneReady), .appleClassic)
    }

    func testSettingsDecodeWithoutEngineDefaultsToAutomatic() throws {
        let data = Data(#"{"localeMode":"german"}"#.utf8)
        let settings = try JSONDecoder().decode(VoiceFlowSettings.self, from: data)
        XCTAssertEqual(settings.speechEngine, .automatic)
        XCTAssertEqual(settings.localeMode, .german)
    }

    func testSettingsDecodeWithUnknownEngineDefaultsToAutomatic() throws {
        let data = Data(#"{"speechEngine":"someFutureEngine"}"#.utf8)
        let settings = try JSONDecoder().decode(VoiceFlowSettings.self, from: data)
        XCTAssertEqual(settings.speechEngine, .automatic)
    }

    func testSettingsRoundTripEngine() throws {
        let original = VoiceFlowSettings(speechEngine: .parakeet)
        let decoded = try JSONDecoder().decode(VoiceFlowSettings.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(decoded.speechEngine, .parakeet)
    }
}

final class TranscriptAccumulatorTests: XCTestCase {
    func testVolatileSegmentsReplaceEachOther() {
        var transcript = TranscriptAccumulator()
        transcript.apply("Hallo", isFinal: false)
        transcript.apply("Hallo Welt", isFinal: false)
        XCTAssertEqual(transcript.text, "Hallo Welt")
    }

    func testFinalSegmentsAppendAndClearVolatile() {
        var transcript = TranscriptAccumulator()
        transcript.apply("Hallo Wel", isFinal: false)
        transcript.apply("Hallo Welt.", isFinal: true)
        XCTAssertEqual(transcript.text, "Hallo Welt.")
        transcript.apply("Wie geht", isFinal: false)
        XCTAssertEqual(transcript.text, "Hallo Welt. Wie geht")
        transcript.apply(" Wie geht es dir?", isFinal: true)
        XCTAssertEqual(transcript.text, "Hallo Welt. Wie geht es dir?")
        XCTAssertEqual(transcript.volatileText, "")
    }

    func testEmptySegmentsDoNotAddSpaces() {
        var transcript = TranscriptAccumulator()
        transcript.apply("", isFinal: true)
        transcript.apply("Ja", isFinal: true)
        transcript.apply("  ", isFinal: false)
        XCTAssertEqual(transcript.text, "Ja")
    }
}
