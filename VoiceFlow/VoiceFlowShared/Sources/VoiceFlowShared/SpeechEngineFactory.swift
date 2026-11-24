#if os(iOS)
import Foundation

/// Builds the engine for one dictation from the user's preference and what the host can run.
@MainActor
public enum SpeechEngineFactory {
    /// Builds a Parakeet engine if its models are ready. Supplied by the containing app only;
    /// the keyboard never links the Parakeet package.
    public typealias ParakeetProvider = @MainActor () -> SpeechEngine?

    public static func makeEngine(
        settings: VoiceFlowSettings,
        locale: Locale,
        host: SpeechEngineHost,
        parakeet: ParakeetProvider? = nil
    ) async -> (engine: SpeechEngine, kind: ResolvedSpeechEngine) {
        let parakeetEngine = host == .containingApp && settings.speechEngine == .parakeet ? parakeet?() : nil

        var analyzerReady = false
        if settings.speechEngine != .appleClassic, #available(iOS 26.0, *) {
            analyzerReady = await SpeechAnalyzerEngine.isReady(for: locale)
        }

        let resolved = SpeechEngineSelection.resolve(
            preference: settings.speechEngine,
            settings: settings,
            host: host,
            availability: SpeechEngineAvailability(
                speechAnalyzerReady: analyzerReady,
                parakeetReady: parakeetEngine != nil
            )
        )

        switch resolved {
        case .parakeet:
            if let parakeetEngine {
                return (parakeetEngine, .parakeet)
            }
        case .appleSpeechAnalyzer:
            if #available(iOS 26.0, *) {
                return (SpeechAnalyzerEngine(), .appleSpeechAnalyzer)
            }
        case .appleClassic:
            break
        }
        return (AppleSpeechEngine(settings: settings), .appleClassic)
    }
}
#endif
