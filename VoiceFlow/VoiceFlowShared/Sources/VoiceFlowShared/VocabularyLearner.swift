import Foundation

/// A correction the learner inferred from raw vs. edited text.
public struct VocabularyCandidate: Equatable, Hashable, Sendable {
    public var heard: String
    public var correction: String

    public init(heard: String, correction: String) {
        self.heard = heard
        self.correction = correction
    }
}

/// Infers correction pairs from what the recognizer produced and what the user turned it into.
///
/// Only short replacements that plausibly are *misrecognitions* are kept: up to three words on
/// either side, letters similar enough (or identical apart from spacing / case). Rewrites such as
/// "gestern" → "heute", pure insertions, deletions, punctuation, and sentence-start capitalization
/// are ignored. Results are suggestions; activating them is the user's decision.
public enum VocabularyLearner {
    public static let maxPhraseWords = 3
    public static let minimumSimilarity = 0.5

    public static func candidates(raw: String, corrected: String) -> [VocabularyCandidate] {
        let rawTokens = tokenize(raw)
        let correctedTokens = tokenize(corrected)
        guard !rawTokens.isEmpty, !correctedTokens.isEmpty else { return [] }

        var result: [VocabularyCandidate] = []
        for block in replacedBlocks(rawTokens.map(\.word), correctedTokens.map(\.word)) {
            let old = Array(rawTokens[block.old])
            let new = Array(correctedTokens[block.new])
            guard (1...maxPhraseWords).contains(old.count), (1...maxPhraseWords).contains(new.count) else { continue }

            let heard = old.map(\.word).joined(separator: " ")
            let correction = new.map(\.word).joined(separator: " ")
            guard isPlausibleMisrecognition(heard: heard, correction: correction) else { continue }

            if old.count == 1, new.count == 1, isSentenceCaseChange(heard, correction), old[0].startsSentence || new[0].startsSentence {
                continue
            }

            let candidate = VocabularyCandidate(heard: heard, correction: correction)
            if !result.contains(candidate) {
                result.append(candidate)
            }
        }
        return result
    }

    /// Finds the stretch of `context` that is the user's edited version of `inserted`.
    /// Returns `nil` when `inserted` is still present unchanged or nothing resembles it.
    public static func editedSegment(inserted: String, context: String) -> String? {
        let insertedTokens = tokenize(inserted).map(\.word)
        let contextTokens = tokenize(context).map(\.word)
        guard !insertedTokens.isEmpty, !contextTokens.isEmpty else { return nil }

        if contains(contextTokens, insertedTokens) {
            return nil
        }

        let count = insertedTokens.count
        let slack = max(2, count / 3)
        var best: (ratio: Double, range: Range<Int>)?

        for length in max(1, count - slack)...(count + slack) where length <= contextTokens.count {
            for start in 0...(contextTokens.count - length) {
                let window = Array(contextTokens[start..<(start + length)])
                let common = lcsLength(window.map(normalized), insertedTokens.map(normalized))
                let ratio = Double(common) / Double(max(window.count, count))
                // Ties go to the window closest in length (a dropped trailing word is not an edit),
                // then to the later one: the cursor usually sits right after our insertion.
                let distance = abs(length - count)
                let bestDistance = best.map { abs($0.range.count - count) } ?? Int.max
                if ratio > (best?.ratio ?? 0) || (ratio == best?.ratio && distance <= bestDistance) {
                    best = (ratio, start..<(start + length))
                }
            }
        }

        // Most words must survive; otherwise this is different text, not an edit of ours.
        guard let best, best.ratio >= 0.6 else { return nil }
        return contextTokens[best.range].joined(separator: " ")
    }

    // MARK: - Tokens

    struct Token: Equatable {
        var word: String
        var startsSentence: Bool
    }

    static func tokenize(_ text: String) -> [Token] {
        var tokens: [Token] = []
        var nextStartsSentence = true
        for piece in text.split(whereSeparator: \.isWhitespace) {
            let word = piece.trimmingCharacters(in: .punctuationCharacters.union(.symbols))
            if !word.isEmpty {
                tokens.append(Token(word: word, startsSentence: nextStartsSentence))
                nextStartsSentence = false
            }
            if let last = piece.last, ".!?".contains(last) {
                nextStartsSentence = true
            }
        }
        return tokens
    }

    static func normalized(_ word: String) -> String {
        word.lowercased()
    }

    // MARK: - Similarity

    static func isPlausibleMisrecognition(heard: String, correction: String) -> Bool {
        let a = letters(heard)
        let b = letters(correction)
        guard !a.isEmpty, !b.isEmpty, heard != correction else { return false }
        if a == b { return true } // spacing / case only: "voice flow" -> "VoiceFlow"
        return similarity(a, b) >= minimumSimilarity
    }

    static func isSentenceCaseChange(_ a: String, _ b: String) -> Bool {
        guard a != b, a.lowercased() == b.lowercased(), let first = a.first else { return false }
        let rest = a.dropFirst()
        return b == String(first).uppercased() + rest || b == String(first).lowercased() + rest
    }

    static func letters(_ text: String) -> [Character] {
        Array(text.lowercased().filter { $0.isLetter || $0.isNumber })
    }

    /// 1 - normalized Levenshtein distance.
    static func similarity(_ a: [Character], _ b: [Character]) -> Double {
        let distance = levenshtein(a, b)
        return 1 - Double(distance) / Double(max(a.count, b.count))
    }

    static func levenshtein(_ a: [Character], _ b: [Character]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        var current = Array(repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }

    // MARK: - Diff

    struct Block: Equatable {
        var old: Range<Int>
        var new: Range<Int>
    }

    /// Word-level LCS alignment; returns stretches where both sides changed.
    /// Exact (case-sensitive) comparison, so "voiceflow" -> "VoiceFlow" is a change.
    static func replacedBlocks(_ old: [String], _ new: [String]) -> [Block] {
        let table = lcsTable(old, new)
        var blocks: [Block] = []
        var i = 0, j = 0
        var blockStart: (Int, Int)?

        func closeBlock() {
            if let (si, sj) = blockStart, i > si, j > sj {
                blocks.append(Block(old: si..<i, new: sj..<j))
            }
            blockStart = nil
        }

        while i < old.count || j < new.count {
            if i < old.count, j < new.count, old[i] == new[j] {
                closeBlock()
                i += 1
                j += 1
                continue
            }
            if blockStart == nil {
                blockStart = (i, j)
            }
            if j < new.count, i == old.count || table[i][j + 1] >= table[i + 1][j] {
                j += 1
            } else {
                i += 1
            }
        }
        closeBlock()
        return blocks
    }

    /// `table[i][j]` = LCS length of `a[i...]` and `b[j...]`.
    static func lcsTable(_ a: [String], _ b: [String]) -> [[Int]] {
        var table = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        guard !a.isEmpty, !b.isEmpty else { return table }
        for i in stride(from: a.count - 1, through: 0, by: -1) {
            for j in stride(from: b.count - 1, through: 0, by: -1) {
                table[i][j] = a[i] == b[j] ? table[i + 1][j + 1] + 1 : max(table[i + 1][j], table[i][j + 1])
            }
        }
        return table
    }

    static func lcsLength(_ a: [String], _ b: [String]) -> Int {
        lcsTable(a, b)[0][0]
    }

    static func contains(_ haystack: [String], _ needle: [String]) -> Bool {
        guard needle.count <= haystack.count else { return false }
        for start in 0...(haystack.count - needle.count) where Array(haystack[start..<(start + needle.count)]) == needle {
            return true
        }
        return false
    }
}
