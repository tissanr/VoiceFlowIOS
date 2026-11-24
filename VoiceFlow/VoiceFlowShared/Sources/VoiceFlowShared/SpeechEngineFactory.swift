#if os(iOS)
import Foundation

/// Builds the engine for one dictation from the user's preference and what the host can run.
@MainActor
public enum SpeechEngineFactory {
    /// Builds the app-only engine (`parakeet` or `whisper`) the user picked. Supplied by the containing
    /// app only; the keyboard never links those packages.
    /// Returns nil when the engine is not available (falls back to Apple); throws to surface a failure
    /// the user should see (e.g. a model that fails to load after they chose it).
    public typealias AppEngineProvider = @MainActor (SpeechEngineKind) async throws -> SpeechEngine?

    public static func makeEngine(
        settings: VoiceFlowSettings,
        locale: Locale,
        host: SpeechEngineHost,
        appEngine: AppEngineProvider? = nil
    ) async throws -> (engine: SpeechEngine, kind: ResolvedSpeechEngine) {
        var appOnlyEngine: SpeechEngine?
        if host == .containingApp, settings.speechEngine.isContainingAppOnly, let appEngine {
            appOnlyEngine = try await appEngine(settings.speechEngine)
        }

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
                appEngineReady: appOnlyEngine != nil
            )
        )

        switch resolved {
        case .parakeet, .whisper:
            if let appOnlyEngine {
                return (appOnlyEngine, resolved)
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
