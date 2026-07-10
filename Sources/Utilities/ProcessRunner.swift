import Foundation
import Darwin

/// Resolves command-line tools for a native macOS app. Apps launched from Finder/Dock inherit a
/// minimal environment rather than the PATH configured by the user's shell, so relying on
/// `/usr/bin/env <tool>` produces false "not installed" warnings for Homebrew, MacPorts, mise,
/// asdf, Cargo, and Nix installs.
enum ExecutableResolver {
    typealias LoginShellLookup = (_ executable: String, _ environment: [String: String]) -> String?

    static func resolve(
        _ executable: String,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        additionalSearchDirectories: [String] = [],
        homeDirectory: String = NSHomeDirectory(),
        isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) },
        loginShellLookup: LoginShellLookup? = nil
    ) -> String? {
        let normalizedExecutable = executable.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedExecutable.isEmpty,
              !normalizedExecutable.contains("\0"),
              !normalizedExecutable.contains(where: \.isNewline) else {
            return nil
        }

        if normalizedExecutable.contains("/") {
            let expandedPath = expandHome(in: normalizedExecutable, homeDirectory: homeDirectory)
            return isExecutable(expandedPath) ? expandedPath : nil
        }

        let resolvedEnvironment = augmentedEnvironment(
            base: environment,
            additionalSearchDirectories: additionalSearchDirectories,
            homeDirectory: homeDirectory
        )
        for directory in searchDirectories(
            environment: resolvedEnvironment,
            additionalSearchDirectories: [],
            homeDirectory: homeDirectory
        ) {
            let candidate = URL(fileURLWithPath: directory)
                .appendingPathComponent(normalizedExecutable)
                .standardizedFileURL.path
            if isExecutable(candidate) {
                return candidate
            }
        }

        let lookup = loginShellLookup ?? defaultLoginShellLookup
        guard let shellCandidate = lookup(normalizedExecutable, resolvedEnvironment) else {
            return nil
        }
        let expandedCandidate = expandHome(in: shellCandidate, homeDirectory: homeDirectory)
        return isExecutable(expandedCandidate) ? expandedCandidate : nil
    }

    /// Returns an environment whose PATH is useful for a GUI-launched macOS app while preserving
    /// every other inherited variable. The ordering is deterministic and duplicates are removed.
    static func augmentedEnvironment(
        base: [String: String] = ProcessInfo.processInfo.environment,
        additionalSearchDirectories: [String] = [],
        homeDirectory: String = NSHomeDirectory()
    ) -> [String: String] {
        var result = base
        result["PATH"] = searchDirectories(
            environment: base,
            additionalSearchDirectories: additionalSearchDirectories,
            homeDirectory: homeDirectory
        ).joined(separator: ":")
        return result
    }

    static func searchDirectories(
        environment: [String: String],
        additionalSearchDirectories: [String] = [],
        homeDirectory: String = NSHomeDirectory()
    ) -> [String] {
        let inheritedDirectories = (environment["PATH"] ?? "")
            .split(separator: ":", omittingEmptySubsequences: true)
            .map(String.init)

        var standardDirectories: [String] = []
        if let homebrewPrefix = environment["HOMEBREW_PREFIX"], !homebrewPrefix.isEmpty {
            standardDirectories.append(contentsOf: [
                URL(fileURLWithPath: homebrewPrefix).appendingPathComponent("bin").path,
                URL(fileURLWithPath: homebrewPrefix).appendingPathComponent("sbin").path
            ])
        }
        standardDirectories.append(contentsOf: [
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
            "/usr/local/sbin",
            "/opt/local/bin",
            "/opt/local/sbin",
            "\(homeDirectory)/bin",
            "\(homeDirectory)/.local/bin",
            "\(homeDirectory)/.cargo/bin",
            "\(homeDirectory)/.local/share/mise/shims",
            "\(homeDirectory)/.asdf/shims",
            "\(homeDirectory)/.nix-profile/bin",
            "/nix/var/nix/profiles/default/bin",
            "/run/current-system/sw/bin",
            "/Applications/Xcode.app/Contents/Developer/usr/bin",
            "/Library/Developer/CommandLineTools/usr/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ])

        return (additionalSearchDirectories + inheritedDirectories + standardDirectories)
            .map { expandHome(in: $0, homeDirectory: homeDirectory) }
            .reduce(into: [String]()) { directories, directory in
                guard !directory.isEmpty, !directories.contains(directory) else { return }
                directories.append(directory)
            }
    }

    private static func expandHome(in path: String, homeDirectory: String) -> String {
        if path == "~" {
            return homeDirectory
        }
        if path.hasPrefix("~/") {
            return URL(fileURLWithPath: homeDirectory)
                .appendingPathComponent(String(path.dropFirst(2)))
                .path
        }
        return path
    }

    private static func defaultLoginShellLookup(
        executable: String,
        environment: [String: String]
    ) -> String? {
        let configuredShell = environment["SHELL"] ?? "/bin/zsh"
        let supportedShellNames: Set<String> = ["zsh", "bash", "sh", "ksh"]
        let shellURL: URL
        if supportedShellNames.contains(URL(fileURLWithPath: configuredShell).lastPathComponent),
           FileManager.default.isExecutableFile(atPath: configuredShell) {
            shellURL = URL(fileURLWithPath: configuredShell)
        } else if FileManager.default.isExecutableFile(atPath: "/bin/zsh") {
            shellURL = URL(fileURLWithPath: "/bin/zsh")
        } else {
            shellURL = URL(fileURLWithPath: "/bin/sh")
        }

        var shellEnvironment = environment
        shellEnvironment["TERM"] = "dumb"
        shellEnvironment["NO_COLOR"] = "1"

        guard let result = try? ProcessRunner.run(
            executableURL: shellURL,
            // The executable is passed as positional parameter $1, never interpolated into shell
            // source, so names containing shell metacharacters cannot become code.
            arguments: ["-l", "-c", "command -v \"$1\"", "rosewood-resolver", executable],
            environment: shellEnvironment,
            timeout: 3.0
        ), result.terminationStatus == 0 else {
            return nil
        }

        // Startup files sometimes print status text. Accept only an absolute executable path.
        return result.stdout
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .last { $0.hasPrefix("/") && FileManager.default.isExecutableFile(atPath: $0) }
    }
}

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
