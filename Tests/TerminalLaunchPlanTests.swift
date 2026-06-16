import Foundation
import Testing
@testable import Rosewood

/// Pure, headless-safe tests for terminal process-launch construction. The rendered terminal / live
/// PTY can't be asserted without a window, so all launch logic lives in TerminalLaunchPlan and is
/// tested here. Arguments are an argv array (no shell string), so the key safety property is that
/// ids/paths pass through verbatim as single arguments — no quoting/injection.
struct TerminalLaunchPlanTests {
    private let env = ["PATH": "/usr/bin:/bin", "HOME": "/Users/test"]
    private let home = "/Users/test"

    @Test
    func localSessionRunsLoginShellInWorkingDirectory() {
        let plan = TerminalLaunchPlan.make(
            for: .local(shell: "/bin/zsh"),
            workingDirectory: URL(fileURLWithPath: "/tmp/project"),
            defaultShell: "/bin/bash",
            dockerPath: nil,
            baseEnvironment: env,
            homeDirectory: home
        )
        #expect(plan.executable == "/bin/zsh")
        #expect(plan.args == ["-l"])
        #expect(plan.currentDirectory == "/tmp/project")
    }

    @Test
    func localSessionFallsBackToHomeAndDefaultShell() {
        let plan = TerminalLaunchPlan.make(
            for: .local(shell: ""),
            workingDirectory: nil,
            defaultShell: "/bin/bash",
            dockerPath: nil,
            baseEnvironment: env,
            homeDirectory: home
        )
        #expect(plan.executable == "/bin/bash")
        #expect(plan.currentDirectory == "/Users/test")
    }

    @Test
    func dockerExecUsesAbsoluteDockerPathAndArgvArray() {
        let plan = TerminalLaunchPlan.make(
            for: .dockerExec(containerId: "abc123", user: nil),
            workingDirectory: URL(fileURLWithPath: "/tmp/project"),
            defaultShell: "/bin/zsh",
            dockerPath: "/opt/homebrew/bin/docker",
            baseEnvironment: env,
            homeDirectory: home
        )
        #expect(plan.executable == "/opt/homebrew/bin/docker")
        #expect(plan.args == ["exec", "-it", "abc123", "sh", "-c", "exec ${SHELL:-/bin/sh}"])
        #expect(plan.currentDirectory == "/tmp/project")
    }

    @Test
    func dockerExecInsertsUserFlagWhenProvided() {
        let plan = TerminalLaunchPlan.make(
            for: .dockerExec(containerId: "abc123", user: "root"),
            workingDirectory: nil,
            defaultShell: "/bin/zsh",
            dockerPath: "/usr/local/bin/docker",
            baseEnvironment: env,
            homeDirectory: home
        )
        #expect(plan.args == ["exec", "-it", "-u", "root", "abc123", "sh", "-c", "exec ${SHELL:-/bin/sh}"])
    }

    @Test
    func composeRunsFromProjectDirectory() {
        let plan = TerminalLaunchPlan.make(
            for: .dockerComposeExec(projectPath: URL(fileURLWithPath: "/work/app"), service: "web", user: nil),
            workingDirectory: URL(fileURLWithPath: "/somewhere/else"),
            defaultShell: "/bin/zsh",
            dockerPath: "/usr/local/bin/docker",
            baseEnvironment: env,
            homeDirectory: home
        )
        #expect(plan.executable == "/usr/local/bin/docker")
        #expect(plan.args == ["compose", "exec", "web", "sh", "-c", "exec ${SHELL:-/bin/sh}"])
        // Compose resolves its file relative to cwd, so cwd must be the project dir, not workingDirectory.
        #expect(plan.currentDirectory == "/work/app")
    }

    @Test
    func argvDeliversMetacharactersVerbatimWithoutQuoting() {
        // A container id with shell metacharacters must arrive as ONE argv element, not be parsed
        // by a shell (the whole point of using argv instead of `sh -lc "…"`).
        let nasty = "evil; rm -rf / $(whoami)"
        let plan = TerminalLaunchPlan.make(
            for: .dockerExec(containerId: nasty, user: nil),
            workingDirectory: nil,
            defaultShell: "/bin/zsh",
            dockerPath: "/usr/local/bin/docker",
            baseEnvironment: env,
            homeDirectory: home
        )
        #expect(plan.args.contains(nasty))
        // No element wraps it in quotes or splits it.
        #expect(plan.args.filter { $0.contains("evil") }.count == 1)
    }

    @Test
    func environmentForcesCapableTerminalAndPreservesInherited() {
        let result = TerminalLaunchPlan.buildEnvironment(base: ["PATH": "/usr/bin", "FOO": "bar"])
        #expect(result.contains("TERM=xterm-256color"))
        #expect(result.contains("COLORTERM=truecolor"))
        #expect(result.contains("PATH=/usr/bin"))
        #expect(result.contains("FOO=bar"))
        // Sorted for determinism.
        #expect(result == result.sorted())
    }

    @Test
    func resolveDockerPathPrefersStandardLocationsThenPathThenNil() {
        // First existing standard candidate wins.
        #expect(
            TerminalLaunchPlan.resolveDockerPath(
                fileExists: { $0 == "/opt/homebrew/bin/docker" },
                pathEnvironment: nil
            ) == "/opt/homebrew/bin/docker"
        )
        // Falls back to scanning PATH.
        #expect(
            TerminalLaunchPlan.resolveDockerPath(
                fileExists: { $0 == "/custom/bin/docker" },
                pathEnvironment: "/custom/bin:/other"
            ) == "/custom/bin/docker"
        )
        // Nil when docker is nowhere.
        #expect(
            TerminalLaunchPlan.resolveDockerPath(
                fileExists: { _ in false },
                pathEnvironment: "/usr/bin"
            ) == nil
        )
    }
}
