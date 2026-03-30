import Foundation
import Darwin

struct ProcessRunnerResult {
    let terminationStatus: Int32
    let stdoutData: Data
    let stderrData: Data

    var stdout: String {
        String(data: stdoutData, encoding: .utf8) ?? ""
    }

    var stderr: String {
        String(data: stderrData, encoding: .utf8) ?? ""
    }
}

enum ProcessRunnerError: LocalizedError, Equatable {
    case timedOut(executable: String, timeout: TimeInterval)
    case cancelled(executable: String)

    var errorDescription: String? {
        switch self {
        case .timedOut(let executable, let timeout):
            return "\(executable) timed out after \(timeout.formatted(.number.precision(.fractionLength(0...1)))) seconds."
        case .cancelled(let executable):
            return "\(executable) was cancelled."
        }
    }
}

enum ProcessRunner {
    static func run(
        executableURL: URL,
        arguments: [String] = [],
        currentDirectoryURL: URL? = nil,
        environment: [String: String]? = nil,
        timeout: TimeInterval? = nil,
        cancellationCheck: (() -> Bool)? = nil
    ) throws -> ProcessRunnerResult {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let stdoutReader = PipeReader(pipe: stdoutPipe)
        let stderrReader = PipeReader(pipe: stderrPipe)

        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectoryURL
        process.environment = environment
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            stdoutReader.cancel()
            stderrReader.cancel()
            throw error
        }

        let executableName = executableURL.lastPathComponent
        let timeoutDate = timeout.map { Date().addingTimeInterval($0) }

        while process.isRunning {
            if cancellationCheck?() == true {
                terminate(process)
                _ = stdoutReader.finish()
                _ = stderrReader.finish()
                throw ProcessRunnerError.cancelled(executable: executableName)
            }

            if let timeoutDate, Date() >= timeoutDate {
                terminate(process)
                _ = stdoutReader.finish()
                _ = stderrReader.finish()
                throw ProcessRunnerError.timedOut(executable: executableName, timeout: timeout ?? 0)
            }

            Thread.sleep(forTimeInterval: 0.05)
        }

        let stdoutData = stdoutReader.finish()
        let stderrData = stderrReader.finish()

        return ProcessRunnerResult(
            terminationStatus: process.terminationStatus,
            stdoutData: stdoutData,
            stderrData: stderrData
        )
    }

    private static func terminate(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()
        if !process.waitUntilExitIfRunning(timeout: 1.0) {
            kill(process.processIdentifier, SIGKILL)
            _ = process.waitUntilExitIfRunning(timeout: 1.0)
        }
    }
}

private final class DataAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ fragment: Data) {
        lock.lock()
        data.append(fragment)
        lock.unlock()
    }

    func snapshot() -> Data {
        lock.lock()
        let snapshot = data
        lock.unlock()
        return snapshot
    }
}

private final class PipeReader: @unchecked Sendable {
    private let accumulator = DataAccumulator()
    private let semaphore = DispatchSemaphore(value: 0)
    private let fileHandle: FileHandle

    init(pipe: Pipe) {
        fileHandle = pipe.fileHandleForReading

        DispatchQueue.global(qos: .userInitiated).async { [accumulator, semaphore, fileHandle] in
            let data = fileHandle.readDataToEndOfFile()
            accumulator.append(data)
            semaphore.signal()
        }
    }

    func cancel() {
        fileHandle.closeFile()
    }

    func finish() -> Data {
        semaphore.wait()
        return accumulator.snapshot()
    }
}

private extension Process {
    @discardableResult
    func waitUntilExitIfRunning(timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }

        return !isRunning
    }
}
