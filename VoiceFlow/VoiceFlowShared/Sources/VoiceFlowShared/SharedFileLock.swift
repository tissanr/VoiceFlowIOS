import Darwin
import Foundation

/// Cross-process exclusive lock backed by `flock` on a file in the App Group container.
/// Shared by `SharedStoreClient` and the JSON file stores.
struct SharedStoreLock {
    let fileURL: URL

    func withExclusiveLock<T>(_ body: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let fileDescriptor = open(fileURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard fileDescriptor >= 0 else {
            throw SharedStoreError.lockUnavailable(path: fileURL.path, errnoCode: errno)
        }

        defer {
            close(fileDescriptor)
        }

        guard flock(fileDescriptor, LOCK_EX) == 0 else {
            throw SharedStoreError.lockUnavailable(path: fileURL.path, errnoCode: errno)
        }

        defer {
            flock(fileDescriptor, LOCK_UN)
        }

        return try body()
    }
}
