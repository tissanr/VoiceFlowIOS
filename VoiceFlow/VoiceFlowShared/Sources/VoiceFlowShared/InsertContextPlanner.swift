import Foundation

public struct InsertContext: Equatable, Sendable {
    public let beforeInput: String?
    public let afterInput: String?

    public init(beforeInput: String?, afterInput: String?) {
        self.beforeInput = beforeInput
        self.afterInput = afterInput
    }
}

public struct PlannedInsert: Equatable, Sendable {
    public let text: String
    public let isSentenceStart: Bool
    public let addedLeadingSpace: Bool
    public let capitalizedFirstLetter: Bool
    public let removedDuplicateTerminalPunctuation: Bool
}

public enum InsertContextPlanner {
    public static func plan(text rawText: String, context: InsertContext) -> PlannedInsert {
        let trimmedText = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        let sentenceStart = isSentenceStart(beforeInput: context.beforeInput)
        var plannedText = sentenceStart ? capitalizeFirstLetter(in: trimmedText).text : trimmedText
        let capitalized = sentenceStart && plannedText != trimmedText
        let removedPunctuation = removeDuplicateTerminalPunctuation(
            from: &plannedText,
            afterInput: context.afterInput
        )
        let shouldLeadWithSpace = needsLeadingSpace(beforeInput: context.beforeInput, plannedText: plannedText)

        if shouldLeadWithSpace {
            plannedText = " " + plannedText
        }

        return PlannedInsert(
            text: plannedText,
            isSentenceStart: sentenceStart,
            addedLeadingSpace: shouldLeadWithSpace,
            capitalizedFirstLetter: capitalized,
            removedDuplicateTerminalPunctuation: removedPunctuation
        )
    }

    public static func isSentenceStart(beforeInput: String?) -> Bool {
        guard let beforeInput, !beforeInput.isEmpty else {
            return true
        }

        if beforeInput.last == "\n" {
            return true
        }

        return beforeInput.lastNonWhitespaceCharacter?.isSentenceBoundary ?? true
    }

    public static func needsLeadingSpace(beforeInput: String?, plannedText: String) -> Bool {
        guard
            let beforeInput,
            let lastBefore = beforeInput.last,
            !lastBefore.isWhitespace,
            !isSentenceStart(beforeInput: beforeInput),
            let firstPlanned = plannedText.first,
            !firstPlanned.isWhitespace,
            !firstPlanned.isLeadingPunctuation
        else {
            return false
        }

        return true
    }

    private static func capitalizeFirstLetter(in text: String) -> (text: String, changed: Bool) {
        guard let range = text.rangeOfCharacter(from: .letters) else {
            return (text, false)
        }

        let firstLetter = String(text[range]).localizedUppercase
        let result = text.replacingCharacters(in: range, with: firstLetter)
        return (result, result != text)
    }

    private static func removeDuplicateTerminalPunctuation(from text: inout String, afterInput: String?) -> Bool {
        guard
            let last = text.last,
            last.isTerminalPunctuation,
            let next = afterInput?.firstNonWhitespaceCharacter,
            next.isTerminalPunctuation
        else {
            return false
        }

        text.removeLast()
        return true
    }
}

private extension String {
    var firstNonWhitespaceCharacter: Character? {
        first { !$0.isWhitespace }
    }

    var lastNonWhitespaceCharacter: Character? {
        reversed().first { !$0.isWhitespace }
    }
}

private extension Character {
    var isSentenceBoundary: Bool {
        self == "." || self == "!" || self == "?" || self == ":" || self == "\n"
    }

    var isTerminalPunctuation: Bool {
        self == "." || self == "!" || self == "?"
    }

    var isLeadingPunctuation: Bool {
        isTerminalPunctuation || self == "," || self == ";" || self == ":" || self == ")"
    }
}
