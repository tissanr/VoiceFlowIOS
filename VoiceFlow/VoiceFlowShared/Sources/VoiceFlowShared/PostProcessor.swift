import Foundation

/// Applies rule-based corrections to raw speech recognition output.
public struct PostProcessor: Sendable {
    public let correctionLevel: CorrectionLevel

    public init(correctionLevel: CorrectionLevel = .soft) {
        self.correctionLevel = correctionLevel
    }

    public func process(_ rawText: String) -> String {
        var text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return text }

        text = normalizeWhitespace(text)

        if correctionLevel == .soft || correctionLevel == .medium {
            text = removeSpaceBeforePunctuation(text)
        }

        return text
    }

    private func normalizeWhitespace(_ text: String) -> String {
        var result = text
        while result.contains("  ") {
            result = result.replacingOccurrences(of: "  ", with: " ")
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func removeSpaceBeforePunctuation(_ text: String) -> String {
        var result = text
        for mark in [",", ".", "!", "?", ":", ";"] {
            result = result.replacingOccurrences(of: " \(mark)", with: mark)
        }
        return result
    }
}
