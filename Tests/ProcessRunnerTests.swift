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
}
