import Foundation

/// The postprocessing pipeline that turns recognized text into the text offered for insert.
/// See docs/specs/speech-and-postprocessing.md → Postprocessing pipeline.
///
/// Implemented: stage 1 (deterministic) = vocabulary correction pairs, then normalization.
/// Stage 2 (optional on-device LLM) and the guardrails plug in after stage 1 in Phase 2.3.
public enum PostProcessor {
    public struct Result: Equatable, Sendable {
        public var text: String
        /// Vocabulary entries whose correction pair was applied; callers bump their `useCount`.
        public var appliedEntryIDs: [UUID]
    }

    public static func process(_ rawText: String, vocabulary: [VocabularyEntry], level: CorrectionLevel) -> Result {
        let corrected = VocabularyCorrector.apply(vocabulary, to: rawText)
        let normalized = TextNormalizer.normalize(corrected.text, level: level)
        return Result(text: normalized, appliedEntryIDs: corrected.appliedEntryIDs)
    }
}
