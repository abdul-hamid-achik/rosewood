import Foundation
import Testing
@testable import Rosewood

struct ProcessRunnerTests {
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
