import FluidAudio
import Foundation
import Observation

/// Owns the Parakeet Core ML models in the containing app's sandbox.
///
/// Network policy: FluidAudio is kept in offline mode except during a download the user started
/// explicitly from Settings. Nothing is fetched silently, and no audio or text leaves the device.
@MainActor
@Observable
public final class ParakeetModelStore {
    public enum State: Equatable, Sendable {
        case notDownloaded
        case downloading(progress: Double)
        case downloaded
        case failed(message: String)
    }

    /// Parakeet Ultra: post-trained TDT 0.6B v3, 25 European languages incl. German, iOS 17+.
    public static let modelVersion: AsrModelVersion = .ultra
    /// Approximate download size shown before the user starts the download.
    public static let approximateDownloadMegabytes = 650

    public static let shared = ParakeetModelStore()

    public private(set) var state: State = .notDownloaded

    @ObservationIgnored private var manager: AsrManager?
    @ObservationIgnored private var loadTask: Task<AsrManager, Error>?
    @ObservationIgnored private var downloadTask: Task<Void, Never>?

    public init() {
        ModelHub.offlineMode = true
        state = Self.modelsOnDisk ? .downloaded : .notDownloaded
    }

    public var isDownloaded: Bool {
        state == .downloaded
    }

    private static var cacheDirectory: URL {
        AsrModels.defaultCacheDirectory(for: modelVersion)
    }

    private static var modelsOnDisk: Bool {
        AsrModels.modelsExist(at: cacheDirectory, version: modelVersion)
    }

    /// User-initiated download from Hugging Face (FluidInference). The only network access.
    public func download() {
        guard downloadTask == nil, state != .downloaded else { return }
        state = .downloading(progress: 0)

        downloadTask = Task { [weak self] in
            ModelHub.offlineMode = false
            defer { ModelHub.offlineMode = true }
            do {
                _ = try await AsrModels.download(version: Self.modelVersion) { progress in
                    let fraction = progress.fractionCompleted
                    Task { @MainActor in
                        guard let self, case .downloading = self.state else { return }
                        self.state = .downloading(progress: fraction)
                    }
                }
                self?.state = Self.modelsOnDisk ? .downloaded : .failed(message: "Download incomplete")
            } catch {
                self?.state = .failed(message: error.localizedDescription)
            }
            self?.downloadTask = nil
        }
    }

    public func deleteModels() {
        downloadTask?.cancel()
        downloadTask = nil
        loadTask?.cancel()
        loadTask = nil
        manager = nil
        try? FileManager.default.removeItem(at: Self.cacheDirectory)
        state = .notDownloaded
    }

    /// Loads the models once (Core ML compile on first use can take several seconds) and keeps them.
    func loadedManager() async throws -> AsrManager {
        if let manager { return manager }
        if let loadTask { return try await loadTask.value }
        guard Self.modelsOnDisk else { throw AsrModelsError.modelNotFound("Parakeet", Self.cacheDirectory) }

        let task = Task { () throws -> AsrManager in
            let models = try await AsrModels.load(from: Self.cacheDirectory, version: Self.modelVersion)
            let manager = AsrManager(config: .default)
            try await manager.loadModels(models)
            return manager
        }
        loadTask = task
        do {
            let loaded = try await task.value
            manager = loaded
            loadTask = nil
            return loaded
        } catch {
            loadTask = nil
            throw error
        }
    }

    /// Starts loading in the background so the first dictation does not pay the compile cost.
    public func warmUp() {
        guard isDownloaded, manager == nil, loadTask == nil else { return }
        Task { _ = try? await loadedManager() }
    }
}
