import Foundation

/// A fully-resolved description of how to spawn a terminal's child process. Pure and deterministic
/// so it can be unit-tested without a real PTY: the controller feeds these fields straight into
/// SwiftTerm's `startProcess(executable:args:environment:currentDirectory:)`.
///
/// Arguments are passed as an argv array (NOT a `sh -lc "…"` string), so paths/ids containing
/// spaces or shell metacharacters are delivered verbatim to the executable — no shell parsing,
/// no quoting, no injection surface. Docker uses an absolute binary path (resolved like the rest
/// of the codebase) rather than trusting a GUI app's minimal PATH.
struct TerminalLaunchPlan: Equatable {
    let executable: String
    let args: [String]
    let environment: [String]
    let currentDirectory: String

    /// Inner shell command run inside a container: prefer the user's login shell, fall back to sh.
    static let containerShellCommand = ["sh", "-c", "exec ${SHELL:-/bin/sh}"]

    static func make(
        for type: TerminalSessionType,
        workingDirectory: URL?,
        defaultShell: String,
        dockerPath: String?,
        baseEnvironment: [String: String],
        homeDirectory: String
    ) -> TerminalLaunchPlan {
        let environment = buildEnvironment(base: baseEnvironment)
        let fallbackCwd = workingDirectory?.path ?? homeDirectory
        let docker = dockerPath ?? "docker"

        switch type {
        case .local(let shell):
            let resolvedShell = shell.isEmpty ? defaultShell : shell
            // A login shell so the user's profile (PATH, aliases, prompt) is loaded; the PTY makes
            // it interactive. cwd is set natively via startProcess — no `cd` injection.
            return TerminalLaunchPlan(
                executable: resolvedShell,
                args: ["-l"],
                environment: environment,
                currentDirectory: fallbackCwd
            )

        case .dockerExec(let containerId, let user):
            var args = ["exec", "-it"]
            if let user, !user.isEmpty { args += ["-u", user] }
            args.append(containerId)
            args += containerShellCommand
            return TerminalLaunchPlan(
                executable: docker,
                args: args,
                environment: environment,
                currentDirectory: fallbackCwd
            )

        case .dockerComposeExec(let projectPath, let service, let user):
            var args = ["compose", "exec"]
            if let user, !user.isEmpty { args += ["-u", user] }
            args.append(service)
            args += containerShellCommand
            // `docker compose` resolves the compose file relative to cwd, so run from the project dir.
            return TerminalLaunchPlan(
                executable: docker,
                args: args,
                environment: environment,
                currentDirectory: projectPath.path
            )
        }
    }

    /// Inherit the app's environment, then force a capable terminal type. Returns the
    /// `["KEY=VALUE", …]` array SwiftTerm expects (sorted for deterministic tests).
    static func buildEnvironment(base: [String: String]) -> [String] {
        var environment = base
        environment["TERM"] = "xterm-256color"
        environment["COLORTERM"] = "truecolor"
        return environment.map { "\($0.key)=\($0.value)" }.sorted()
    }

    /// Resolve an absolute docker binary path the same way DockerCLI does (a GUI-launched macOS app
    /// does not inherit the user's shell PATH, so the common install locations are probed first).
    static func resolveDockerPath(
        fileExists: (String) -> Bool,
        pathEnvironment: String?
    ) -> String? {
        let candidates = [
            "/usr/local/bin/docker",
            "/usr/bin/docker",
            "/opt/homebrew/bin/docker"
        ]
        for candidate in candidates where fileExists(candidate) {
            return candidate
        }
        for directory in (pathEnvironment ?? "").split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(directory)).appendingPathComponent("docker").path
            if fileExists(candidate) {
                return candidate
            }
        }
        return nil
    }
}
