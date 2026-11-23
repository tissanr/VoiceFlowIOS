import XCTest
@testable import VoiceFlowShared

final class TextNormalizerTests: XCTestCase {
    func testCollapsesWhitespaceAndKeepsParagraphs() {
        XCTAssertEqual(
            TextNormalizer.normalize("  Hallo   Welt \t heute \n\n\n\n Zweiter  Absatz ", level: .minimal),
            "Hallo Welt heute\n\nZweiter Absatz"
        )
    }

    func testRemovesSpaceBeforePunctuation() {
        XCTAssertEqual(
            TextNormalizer.normalize("Hallo , wie geht es dir ? Gut !", level: .minimal),
            "Hallo, wie geht es dir? Gut!"
        )
    }

    func testCollapsesDuplicatedPunctuationButKeepsEllipsis() {
        XCTAssertEqual(TextNormalizer.normalize("Ja,, genau.. also...", level: .minimal), "Ja, genau. also...")
    }

    func testMinimalDoesNotTouchCapitalizationOrSpacingAfterPunctuation() {
        XCTAssertEqual(TextNormalizer.normalize("eins,zwei. drei", level: .minimal), "eins,zwei. drei")
    }

    func testSoftAddsSpaceAfterPunctuationButKeepsNumbersDomainsAndTimes() {
        XCTAssertEqual(
            TextNormalizer.normalize("eins,zwei;drei. Das kostet 3,5 Euro um 10:30 auf voiceflow.app", level: .soft),
            "eins, zwei; drei. Das kostet 3,5 Euro um 10:30 auf voiceflow.app"
        )
    }

    func testSoftCapitalizesSentenceStartsInsideText() {
        XCTAssertEqual(
            TextNormalizer.normalize("das ist gut. und das auch! wirklich? ja.", level: .soft),
            "das ist gut. Und das auch! Wirklich? Ja."
        )
    }

    func testSoftLeavesFirstLetterForInsertPlanner() {
        XCTAssertEqual(TextNormalizer.normalize("und dann noch das", level: .soft), "und dann noch das")
    }

    func testSoftDoesNotCapitalizeAfterAbbreviationsInitialsOrEllipsis() {
        XCTAssertEqual(
            TextNormalizer.normalize("Wir brauchen z.B. mehr Zeit, ca. drei Tage bzw. eine Woche", level: .soft),
            "Wir brauchen z.B. mehr Zeit, ca. drei Tage bzw. eine Woche"
        )
        XCTAssertEqual(TextNormalizer.normalize("Bitte an A. müller schicken", level: .soft), "Bitte an A. müller schicken")
        XCTAssertEqual(TextNormalizer.normalize("Also... vielleicht morgen", level: .soft), "Also... vielleicht morgen")
        XCTAssertEqual(TextNormalizer.normalize("Apples vs. oranges, e.g. fruit", level: .soft), "Apples vs. oranges, e.g. fruit")
    }

    func testMediumAddsTerminalPeriodOnlyWhenMissing() {
        XCTAssertEqual(TextNormalizer.normalize("Wir sehen uns morgen", level: .medium), "Wir sehen uns morgen.")
        XCTAssertEqual(TextNormalizer.normalize("Kommst du morgen?", level: .medium), "Kommst du morgen?")
        XCTAssertEqual(TextNormalizer.normalize("Wir sehen uns morgen", level: .soft), "Wir sehen uns morgen")
    }

    func testEmptyAndWhitespaceOnlyInput() {
        XCTAssertEqual(TextNormalizer.normalize("", level: .medium), "")
        XCTAssertEqual(TextNormalizer.normalize("   \n ", level: .medium), "")
    }

    func testNeverChangesWords() {
        let raw = "ich glaube das das stimmt , aber dass weiß ich nicht"
        let normalized = TextNormalizer.normalize(raw, level: .medium)
        let words: (String) -> [String] = { $0.lowercased().components(separatedBy: CharacterSet.letters.inverted).filter { !$0.isEmpty } }
        XCTAssertEqual(words(normalized), words(raw))
    }
}

final class PostProcessorTests: XCTestCase {
    func testAppliesCorrectionPairsThenNormalizes() {
        let entry = VocabularyEntry(heard: "cuba netis", correction: "Kubernetes")
        let result = PostProcessor.process("wir deployen auf cuba netis . das klappt", vocabulary: [entry], level: .soft)
        XCTAssertEqual(result.text, "wir deployen auf Kubernetes. Das klappt")
        XCTAssertEqual(result.appliedEntryIDs, [entry.id])
    }

    func testNoVocabularyStillNormalizes() {
        let result = PostProcessor.process("Hallo  Welt ,  wie geht's", vocabulary: [], level: .medium)
        XCTAssertEqual(result.text, "Hallo Welt, wie geht's.")
        XCTAssertEqual(result.appliedEntryIDs, [])
    }
}
