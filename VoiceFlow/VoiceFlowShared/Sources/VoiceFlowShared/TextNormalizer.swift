import Foundation

/// Deterministic punctuation, whitespace, and capitalization cleanup (postprocessing stage 1).
///
/// Conservative by design: it only fixes formatting, never words. What runs depends on the
/// correction level:
/// - `minimal`: whitespace cleanup, no space before punctuation, duplicated `,` `;` `:` and `..` collapsed.
/// - `soft`: `minimal` + a space after `,` `;` `!` `?` and capitalized sentence starts inside the text.
/// - `medium`: `soft` + a terminal period when the text ends without punctuation.
///
/// The first letter of the text is deliberately left alone: whether it starts a sentence depends on
/// the text before the cursor, which `InsertContextPlanner` decides at insert time.
public enum TextNormalizer {
    public static func normalize(_ text: String, level: CorrectionLevel) -> String {
        var output = normalizeWhitespace(text)
        output = removeSpaceBeforePunctuation(output)
        output = collapseDuplicatedPunctuation(output)

        if level != .minimal {
            output = ensureSpaceAfterPunctuation(output)
            output = capitalizeSentenceStarts(output)
        }
        if level == .medium {
            output = ensureTerminalPunctuation(output)
        }
        return output
    }

    // MARK: - Whitespace

    /// Collapses runs of spaces / tabs, trims every line, and keeps at most one blank line.
    static func normalizeWhitespace(_ text: String) -> String {
        var output = replacing(#"[^\S\n]+"#, in: text, with: " ")
        output = replacing(#" *\n *"#, in: output, with: "\n")
        output = replacing(#"\n{3,}"#, in: output, with: "\n\n")
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Punctuation

    static func removeSpaceBeforePunctuation(_ text: String) -> String {
        replacing(#" +([,.;:!?)\]}»“”])"#, in: text, with: "$1")
    }

    static func collapseDuplicatedPunctuation(_ text: String) -> String {
        var output = replacing(#"([,;:])(?:\s*\1)+"#, in: text, with: "$1")
        // ".." is a typo, "..." is an ellipsis.
        output = replacing(#"(?<!\.)\.\.(?!\.)"#, in: output, with: ".")
        return output
    }

    /// `,` `;` `!` `?` directly followed by a letter get a space. `.` and `:` are skipped on
    /// purpose: they appear inside abbreviations, domains, and times (`z.B.`, `voiceflow.app`, `10:30`).
    /// Digits are skipped so decimal commas (`3,5`) stay intact.
    static func ensureSpaceAfterPunctuation(_ text: String) -> String {
        replacing(#"([,;!?])(?=\p{L})"#, in: text, with: "$1 ")
    }

    static func ensureTerminalPunctuation(_ text: String) -> String {
        guard let last = text.last, last.isLetter || last.isNumber else { return text }
        return text + "."
    }

    // MARK: - Capitalization

    /// Abbreviations that end with a period without ending the sentence (lowercased, no final period).
    static let abbreviations: Set<String> = [
        // German
        "bzw", "ca", "dr", "evtl", "fr", "ggf", "hr", "inkl", "nr", "prof", "str", "usw", "vgl", "zb", "zzgl",
        // English
        "approx", "dept", "eg", "etc", "ie", "mr", "mrs", "ms", "vs",
    ]

    /// Uppercases the first letter after `.` `!` `?` + whitespace, unless the period belongs to an
    /// abbreviation, a single letter (`A. Müller`), or an ellipsis.
    static func capitalizeSentenceStarts(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"([.!?])(\s+)(\p{Ll})"#) else { return text }
        var output = text
        let matches = regex.matches(in: output, range: NSRange(output.startIndex..., in: output))

        for match in matches.reversed() {
            guard let punctuationRange = Range(match.range(at: 1), in: output),
                  let letterRange = Range(match.range(at: 3), in: output)
            else { continue }

            if output[punctuationRange] == ".", !endsSentence(output[..<punctuationRange.lowerBound]) {
                continue
            }
            output.replaceSubrange(letterRange, with: output[letterRange].uppercased())
        }
        return output
    }

    /// Decides whether the period after `prefix` ends a sentence.
    private static func endsSentence(_ prefix: Substring) -> Bool {
        if prefix.hasSuffix(".") { return false } // ellipsis
        let token = prefix.split(whereSeparator: \.isWhitespace).last.map(String.init) ?? ""
        let letters = token.filter(\.isLetter)
        if token.contains(".") { return false }       // z.B, d.h, e.g
        if letters.count == 1, token.count == 1 { return false } // initials: "A. Müller"
        return !abbreviations.contains(letters.lowercased())
    }

    // MARK: - Helpers

    private static func replacing(_ pattern: String, in text: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        return regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
    }
}
