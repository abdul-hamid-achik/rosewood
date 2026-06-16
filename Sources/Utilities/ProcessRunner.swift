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
        // Mark the pipe fds close-on-exec so an unrelated CONCURRENT spawn can't inherit them
        // before its own exec and hold a write-end open — which would withhold EOF from our reader
        // and hang the drain (the root cause of intermittent CI test hangs under parallel spawns).
        // Our own child still receives stdout/stderr: Process dup2's the write fds onto 1/2 in the
        // child, and dup2 clears close-on-exec on the target.
        setCloseOnExec(stdoutPipe, stderrPipe)
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

    private static func setCloseOnExec(_ pipes: Pipe...) {
        for pipe in pipes {
            for handle in [pipe.fileHandleForReading, pipe.fileHandleForWriting] {
                let descriptor = handle.fileDescriptor
                let flags = fcntl(descriptor, F_GETFD)
                if flags != -1 {
                    _ = fcntl(descriptor, F_SETFD, flags | FD_CLOEXEC)
                }
            }
        }
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
            // Read in chunks with `read(upToCount:)` rather than `readDataToEndOfFile()`:
            // the latter raises an uncaught NSFileHandleOperationException (crashing the
            // process) when the read races with `closeFile()` or is interrupted. The Swift
            // API surfaces those as catchable errors instead.
            while true {
                guard let chunk = try? fileHandle.read(upToCount: 65_536), !chunk.isEmpty else {
                    break
                }
                accumulator.append(chunk)
            }
            semaphore.signal()
        }
    }

    func cancel() {
        fileHandle.closeFile()
    }

    /// Wait for the background reader to hit EOF, but never block indefinitely. EOF can be withheld
    /// when a pipe write-end stays open in another process — most often an unrelated concurrent
    /// `posix_spawn` that inherited this pipe's write fd before exec (fd leak across parallel
    /// spawns). Without a bound this turns a timed-out 2s command into an unbounded hang (the
    /// `run` loop already killed the child, yet `run` can't return). After a grace period we force
    /// the blocked `read(upToCount:)` to return by closing the handle, then collect what we have.
    func finish(forceCloseAfter timeout: TimeInterval = 5.0) -> Data {
        if semaphore.wait(timeout: .now() + timeout) == .timedOut {
            fileHandle.closeFile()
            semaphore.wait()
        }
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
