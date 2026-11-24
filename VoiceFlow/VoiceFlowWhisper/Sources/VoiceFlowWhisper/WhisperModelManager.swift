#if os(iOS)
import Foundation
import Observation
import VoiceFlowShared
import WhisperKit

/// Owns the downloaded Whisper model and keeps one loaded `WhisperKit` instance for the app's lifetime.
///
/// Loading a Core ML model takes seconds (minutes on the very first launch while iOS specializes it for
/// the Neural Engine), so it must not happen per dictation. Containing app only.
@MainActor
@Observable
public final class WhisperModelManager {
    public enum State: Equatable, Sendable {
        case notDownloaded
        case downloading(progress: Double)
        /// Downloaded but not in memory.
        case downloaded
        case loading
        case ready
        case failed(String)
    }

    public private(set) var state: State = .notDownloaded
    public private(set) var variant: WhisperModelVariant
    @ObservationIgnored public private(set) var whisperKit: WhisperKit?
    @ObservationIgnored private var prepareTask: Task<Void, Never>?

    private let defaults: UserDefaults

    public init(variant: WhisperModelVariant, defaults: UserDefaults = .standard) {
        self.variant = variant
        self.defaults = defaults
        state = savedFolder(for: variant) == nil ? .notDownloaded : .downloaded
    }

    public var isReady: Bool { state == .ready }

    /// Switches the model. Unloads the current one; the new one loads on the next `prepare()`.
    public func select(_ variant: WhisperModelVariant) {
        guard variant != self.variant else { return }
        prepareTask?.cancel()
        prepareTask = nil
        whisperKit = nil
        self.variant = variant
        state = savedFolder(for: variant) == nil ? .notDownloaded : .downloaded
    }

    /// Downloads (first use only) and loads the model. Concurrent callers await the same work.
    public func prepare() async {
        if state == .ready { return }
        if let prepareTask {
            await prepareTask.value
            return
        }

        let task = Task { await self.downloadAndLoad(self.variant) }
        prepareTask = task
        await task.value
        if prepareTask == task { prepareTask = nil }
    }

    /// Frees memory; the files stay on disk.
    public func unload() {
        prepareTask?.cancel()
        prepareTask = nil
        whisperKit = nil
        state = savedFolder(for: variant) == nil ? .notDownloaded : .downloaded
    }

    /// Removes the downloaded files for the current variant.
    public func deleteDownload() {
        let folder = savedFolder(for: variant)
        unload()
        if let folder {
            try? FileManager.default.removeItem(at: folder)
        }
        defaults.removeObject(forKey: Self.folderKey(variant))
        state = .notDownloaded
    }

    // MARK: - Private

    private func downloadAndLoad(_ variant: WhisperModelVariant) async {
        do {
            let folder: URL
            if let saved = savedFolder(for: variant) {
                folder = saved
            } else {
                state = .downloading(progress: 0)
                folder = try await WhisperKit.download(variant: variant.rawValue) { progress in
                    let fraction = progress.fractionCompleted
                    Task { @MainActor [weak self] in
                        guard let self, self.variant == variant, case .downloading = self.state else { return }
                        self.state = .downloading(progress: fraction)
                    }
                }
                saveFolder(folder, for: variant)
            }

            guard variant == self.variant, !Task.isCancelled else { return }
            state = .loading
            let config = WhisperKitConfig(
                modelFolder: folder.path,
                verbose: false,
                logLevel: .error,
                prewarm: true,
                load: true,
                download: false
            )
            let kit = try await WhisperKit(config)
            guard variant == self.variant, !Task.isCancelled else { return }
            whisperKit = kit
            state = .ready
        } catch {
            guard variant == self.variant else { return }
            // A half-downloaded or deleted folder must not be reused on the next attempt.
            defaults.removeObject(forKey: Self.folderKey(variant))
            whisperKit = nil
            state = .failed(error.localizedDescription)
        }
    }

    private static func folderKey(_ variant: WhisperModelVariant) -> String {
        "whisper.modelFolder.\(variant.rawValue)"
    }

    /// Stored relative to the app home: the absolute container path changes across app updates.
    private func savedFolder(for variant: WhisperModelVariant) -> URL? {
        guard let relativePath = defaults.string(forKey: Self.folderKey(variant)) else { return nil }
        let url = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(relativePath, isDirectory: true)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private func saveFolder(_ folder: URL, for variant: WhisperModelVariant) {
        // Hundreds of MB that can be downloaded again: keep them out of iCloud / device backups.
        var backupFolder = folder
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? backupFolder.setResourceValues(values)

        let home = NSHomeDirectory()
        guard folder.path.hasPrefix(home) else { return }
        let relativePath = String(folder.path.dropFirst(home.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        defaults.set(relativePath, forKey: Self.folderKey(variant))
    }
}
#endif
