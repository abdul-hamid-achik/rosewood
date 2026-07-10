import Foundation
import Testing
@testable import Rosewood

struct ProcessRunnerTests {
    @Test
    func executableResolverFindsToolOutsideMinimalGUIPath() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("rosewood-resolver-\(UUID().uuidString)", isDirectory: true)
        let executableURL = directoryURL.appendingPathComponent("rosewood-test-tool")
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try "#!/bin/sh\nexit 0\n".write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executableURL.path
        )
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let resolvedPath = ExecutableResolver.resolve(
            "rosewood-test-tool",
            environment: ["PATH": "/usr/bin:/bin"],
            additionalSearchDirectories: [directoryURL.path],
            loginShellLookup: { _, _ in nil }
        )

        #expect(resolvedPath == executableURL.path)
    }

    @Test
    func executableResolverBuildsDeduplicatedGUIAppPath() {
        let environment = ExecutableResolver.augmentedEnvironment(
            base: ["PATH": "/usr/bin:/custom/bin:/usr/bin", "ROSEWOOD_TEST": "preserved"],
            additionalSearchDirectories: ["~/tools", "/custom/bin"],
            homeDirectory: "/Users/rosewood"
        )
        let entries = environment["PATH"]?.split(separator: ":").map(String.init) ?? []

        #expect(entries.prefix(3) == ["/Users/rosewood/tools", "/custom/bin", "/usr/bin"])
        #expect(entries.filter { $0 == "/usr/bin" }.count == 1)
        #expect(entries.contains("/opt/homebrew/bin"))
        #expect(entries.contains("/Users/rosewood/.local/share/mise/shims"))
        #expect(environment["ROSEWOOD_TEST"] == "preserved")
    }

    @Test
    func executableResolverUsesValidatedLoginShellFallback() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("rosewood-shell-resolver-\(UUID().uuidString)", isDirectory: true)
        let executableURL = directoryURL.appendingPathComponent("shell-only-tool")
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try "#!/bin/sh\nexit 0\n".write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executableURL.path
        )
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let resolvedPath = ExecutableResolver.resolve(
            "shell-only-tool",
            environment: ["PATH": "/directory/that/does/not/exist"],
            loginShellLookup: { executable, environment in
                #expect(executable == "shell-only-tool")
                #expect(environment["PATH"]?.contains("/opt/homebrew/bin") == true)
                return executableURL.path
            }
        )

        #expect(resolvedPath == executableURL.path)
    }

    @Test
    func capturesStandardOutputAndErrorSeparately() throws {
        let result = try ProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "printf 'hello'; printf 'warn' >&2"]
        )

        #expect(result.terminationStatus == 0)
        #expect(result.stdout == "hello")
        #expect(result.stderr == "warn")
    }

    @Test
    func timesOutLongRunningProcess() {
        #expect(throws: ProcessRunnerError.timedOut(executable: "sh", timeout: 0.1)) {
            _ = try ProcessRunner.run(
                executableURL: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", "sleep 1"],
                timeout: 0.1
            )
        }
    }

    /// Regression: the spawned command exits immediately but leaves a backgrounded child holding
    /// the stdout pipe write-end open (the same fd-leak shape that an unrelated concurrent spawn
    /// can cause). `run` must return on the reader's grace period — NOT block until the background
    /// process exits — so a quick command can never hang on a leaked pipe.
    @Test
    func returnsPromptlyWhenAChildLeavesThePipeOpen() throws {
        let start = Date()
        let result = try ProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "sleep 30 & exit 0"]
        )
        let elapsed = Date().timeIntervalSince(start)

        #expect(result.terminationStatus == 0)
        // Must finish on the ~5s drain grace, well before the 30s background sleep.
        #expect(elapsed < 20)
    }
}
