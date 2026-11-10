import Foundation

/// Applies active correction pairs to recognized text and builds recognizer hints.
/// This is the deterministic correction-pair step of the postprocessing pipeline (stage 1).
public enum VocabularyCorrector {
    /// Apple recommends keeping `contextualStrings` short; more entries dilute the bias.
    public static let maxRecognitionHints = 100

    public struct Result: Equatable, Sendable {
        public var text: String
        public var appliedEntryIDs: [UUID]
    }

    public static func apply(_ entries: [VocabularyEntry], to text: String) -> Result {
        var output = text
        var applied: [UUID] = []

        // Longest phrases first so "voice flow app" wins over "voice flow".
        let pairs = entries
            .filter { $0.isApplied && $0.isCorrectionPair }
            .sorted { $0.heard.count > $1.heard.count }

        for entry in pairs {
            guard let regex = wholePhraseRegex(for: entry.heard) else { continue }
            let range = NSRange(output.startIndex..., in: output)
            let matches = regex.matches(in: output, range: range)
            guard !matches.isEmpty else { continue }

            for match in matches.reversed() {
                guard let matchRange = Range(match.range, in: output) else { continue }
                let matched = output[matchRange]
                output.replaceSubrange(matchRange, with: casedCorrection(entry.correction, matching: matched))
            }
            applied.append(entry.id)
        }

        return Result(text: output, appliedEntryIDs: applied)
    }

    /// Distinct terms for `SFSpeechRecognitionRequest.contextualStrings`, most used first.
    public static func recognitionHints(from entries: [VocabularyEntry], limit: Int = maxRecognitionHints) -> [String] {
        let ranked = entries
            .filter(\.isApplied)
            .sorted {
                if $0.useCount != $1.useCount { return $0.useCount > $1.useCount }
                return ($0.lastUsedAt ?? $0.createdAt) > ($1.lastUsedAt ?? $1.createdAt)
            }

        var seen = Set<String>()
        var hints: [String] = []
        for entry in ranked {
            let term = entry.correction.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !term.isEmpty, seen.insert(term.lowercased()).inserted else { continue }
            hints.append(term)
            if hints.count == limit { break }
        }
        return hints
    }

    static func wholePhraseRegex(for phrase: String) -> NSRegularExpression? {
        let words = phrase.split(whereSeparator: \.isWhitespace).map { NSRegularExpression.escapedPattern(for: String($0)) }
        guard !words.isEmpty else { return nil }
        let pattern = #"(?<![\p{L}\p{N}])"# + words.joined(separator: #"\s+"#) + #"(?![\p{L}\p{N}])"#
        return try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    /// Keeps sentence-start capitalization: "kubernetes" -> "Kubernetes" if the match was capitalized.
    static func casedCorrection(_ correction: String, matching matched: Substring) -> String {
        guard let matchedFirst = matched.first, matchedFirst.isUppercase,
              let first = correction.first, first.isLowercase
        else { return correction }
        return first.uppercased() + correction.dropFirst()
    }
}
