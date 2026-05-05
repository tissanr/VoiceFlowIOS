import Foundation
import VoiceFlowShared

private enum SpikeError: Error, CustomStringConvertible {
    case missingArgument(String)
    case invalidArgument(String)
    case processFailed(role: String, status: Int32, output: String)
    case finalGenerationMismatch(expected: Int, actual: Int)
    case finalPayloadMismatch(expected: Int, actual: Int?)

    var description: String {
        switch self {
        case .missingArgument(let name):
            return "Missing argument: \(name)"
        case .invalidArgument(let message):
            return "Invalid argument: \(message)"
        case .processFailed(let role, let status, let output):
            return "\(role) exited with status \(status): \(output)"
        case .finalGenerationMismatch(let expected, let actual):
            return "Expected final generation \(expected), got \(actual)"
        case .finalPayloadMismatch(let expected, let actual):
            return "Expected final payload generation \(expected), got \(String(describing: actual))"
        }
    }
}

private struct ChildConfig {
    let role: String
    let suiteName: String
    let lockPath: String
    let iterations: Int
    let producer: ProducerSide
}

let arguments = CommandLine.arguments

do {
    if arguments.contains("--child") {
        try runChild(parseChildConfig(arguments))
    } else {
        try runParent()
    }
} catch {
    fputs("AppGroupStoreSpike failed: \(error)\n", stderr)
    exit(1)
}

private func runParent() throws {
    let suiteName = "VoiceFlow.AppGroupStoreSpike.\(UUID().uuidString)"
    let runDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("VoiceFlowAppGroupStoreSpike", isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let lockURL = runDirectory.appendingPathComponent("pending-insert.lock")
    try FileManager.default.createDirectory(at: runDirectory, withIntermediateDirectories: true)

    guard let defaults = UserDefaults(suiteName: suiteName) else {
        throw SharedStoreError.appGroupUnavailable(suiteName: suiteName)
    }

    defaults.removePersistentDomain(forName: suiteName)

    let writerCount = 4
    let readerCount = 4
    let writerIterations = 750
    let readerIterations = 1_500
    let executableURL = URL(fileURLWithPath: arguments[0])

    var processes: [(role: String, process: Process, output: Pipe)] = []

    for index in 0..<writerCount {
        let role = index.isMultiple(of: 2) ? "app-writer-\(index)" : "extension-writer-\(index)"
        let producer = index.isMultiple(of: 2) ? "containingApp" : "keyboardExtension"
        processes.append(try startChild(
            executableURL: executableURL,
            role: role,
            suiteName: suiteName,
            lockPath: lockURL.path,
            iterations: writerIterations,
            producer: producer
        ))
    }

    for index in 0..<readerCount {
        processes.append(try startChild(
            executableURL: executableURL,
            role: "keyboard-reader-\(index)",
            suiteName: suiteName,
            lockPath: lockURL.path,
            iterations: readerIterations,
            producer: "keyboardExtension"
        ))
    }

    for child in processes {
        child.process.waitUntilExit()
    }

    for child in processes where child.process.terminationStatus != 0 {
        let data = child.output.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        throw SpikeError.processFailed(
            role: child.role,
            status: child.process.terminationStatus,
            output: output
        )
    }

    let client = try SharedStoreClient(suiteName: suiteName, lockFileURL: lockURL)
    let expectedGeneration = writerCount * writerIterations
    let actualGeneration = client.currentGeneration()

    guard actualGeneration == expectedGeneration else {
        throw SpikeError.finalGenerationMismatch(expected: expectedGeneration, actual: actualGeneration)
    }

    let payload = try client.readPendingInsertPayload()
    guard payload?.generation == expectedGeneration else {
        throw SpikeError.finalPayloadMismatch(expected: expectedGeneration, actual: payload?.generation)
    }

    print("App Group store contention spike passed")
    print("suite: \(suiteName)")
    print("writers: \(writerCount), writer iterations: \(writerIterations)")
    print("readers: \(readerCount), reader iterations: \(readerIterations)")
    print("final generation: \(actualGeneration)")
    print("consumed generation: \(client.consumedGeneration())")
}

private func startChild(
    executableURL: URL,
    role: String,
    suiteName: String,
    lockPath: String,
    iterations: Int,
    producer: String
) throws -> (role: String, process: Process, output: Pipe) {
    let process = Process()
    let output = Pipe()
    process.executableURL = executableURL
    process.arguments = [
        "--child",
        "--role", role,
        "--suite", suiteName,
        "--lock", lockPath,
        "--iterations", "\(iterations)",
        "--producer", producer
    ]
    process.standardOutput = output
    process.standardError = output
    try process.run()
    return (role, process, output)
}

private func runChild(_ config: ChildConfig) throws {
    let client = try SharedStoreClient(
        suiteName: config.suiteName,
        lockFileURL: URL(fileURLWithPath: config.lockPath)
    )

    for index in 0..<config.iterations {
        if config.role.contains("writer") {
            _ = try client.writePendingInsert(
                text: "\(config.role)-\(index)",
                dictationID: UUID(),
                producedBy: config.producer
            )
        } else if let pendingInsert = try client.pendingInsertForKeyboard(), index.isMultiple(of: 11) {
            do {
                try client.consumePendingInsert(generation: pendingInsert.generation)
            } catch SharedStoreError.generationMismatch {
                // A writer can publish a newer generation between the keyboard's read
                // and its simulated consume. The client must refuse to tombstone it.
            }
        }

        if index.isMultiple(of: 25) {
            usleep(100)
        }
    }
}

private func parseChildConfig(_ arguments: [String]) throws -> ChildConfig {
    let role = try value(after: "--role", in: arguments)
    let suiteName = try value(after: "--suite", in: arguments)
    let lockPath = try value(after: "--lock", in: arguments)
    let iterationsText = try value(after: "--iterations", in: arguments)
    let producerText = try value(after: "--producer", in: arguments)

    guard let iterations = Int(iterationsText), iterations > 0 else {
        throw SpikeError.invalidArgument("iterations must be positive")
    }

    let producer: ProducerSide
    switch producerText {
    case "containingApp":
        producer = .containingApp
    case "keyboardExtension":
        producer = .keyboardExtension
    default:
        throw SpikeError.invalidArgument("unknown producer \(producerText)")
    }

    return ChildConfig(
        role: role,
        suiteName: suiteName,
        lockPath: lockPath,
        iterations: iterations,
        producer: producer
    )
}

private func value(after name: String, in arguments: [String]) throws -> String {
    guard let index = arguments.firstIndex(of: name) else {
        throw SpikeError.missingArgument(name)
    }

    let valueIndex = arguments.index(after: index)
    guard valueIndex < arguments.endIndex else {
        throw SpikeError.missingArgument(name)
    }

    return arguments[valueIndex]
}
