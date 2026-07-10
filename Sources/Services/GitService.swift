import Foundation

/// Outcome of loading a diff, so the UI can tell a real load FAILURE (repo can't be resolved /
/// git errored) apart from a legitimate empty diff (e.g. an empty untracked file) — both of
/// which previously collapsed to `nil` and rendered as "No diff available".
enum GitDiffOutcome: Equatable {
    case diff(GitDiffResult)
    case noChanges
    case failed
}

protocol GitServiceProtocol: AnyObject {
    func toolAvailable() async -> Bool
    func repositoryStatus(for projectRoot: URL?) async -> GitRepositoryStatus
    func diff(for changedFile: GitChangedFile, projectRoot: URL?) async -> GitDiffOutcome
    func blame(for fileURL: URL?, line: Int, projectRoot: URL?) async -> GitBlameInfo?
    func stage(changedFile: GitChangedFile, projectRoot: URL?) async -> GitOperationResult
    func unstage(changedFile: GitChangedFile, projectRoot: URL?) async -> GitOperationResult
    func discard(changedFile: GitChangedFile, projectRoot: URL?) async -> GitOperationResult
    func commit(message: String, projectRoot: URL?) async -> GitOperationResult
    func fetch(projectRoot: URL?) async -> GitOperationResult
    func pull(projectRoot: URL?) async -> GitOperationResult
    func push(projectRoot: URL?) async -> GitOperationResult
}

final class GitService: GitServiceProtocol {
    static let shared = GitService()

    private let gitBaseEnvironment: [String: String]
    private let gitAdditionalSearchPaths: [String]
    private let gitCommandName: String

    init(
        gitBaseEnvironment: [String: String] = ProcessInfo.processInfo.environment,
        gitAdditionalSearchPaths: [String] = [],
        gitCommandName: String = "git"
    ) {
        self.gitBaseEnvironment = gitBaseEnvironment
        self.gitAdditionalSearchPaths = gitAdditionalSearchPaths
        self.gitCommandName = gitCommandName
    }

    func toolAvailable() async -> Bool {
        await Task.detached(priority: .utility) { [self] in
            guard let executableURL = resolvedGitExecutableURL() else {
                return false
            }
            guard let result = try? ProcessRunner.run(
                executableURL: executableURL,
                arguments: ["--version"],
                environment: gitEnvironment(),
                timeout: 2.0
            ) else {
                return false
            }

            return result.terminationStatus == 0
        }.value
    }

    func repositoryStatus(for projectRoot: URL?) async -> GitRepositoryStatus {
        guard let projectRoot else {
            return .empty
        }

        return await Task.detached(priority: .utility) { [self] in
            guard let repositoryRoot = try? resolveRepositoryRoot(for: projectRoot) else {
                return .empty
            }

            let branchName = resolveBranchName(for: repositoryRoot)
            let parsedStatus = (try? loadRepositoryStatus(for: repositoryRoot)) ?? (.init(), [])
            let sync = resolveSyncStatus(for: repositoryRoot)
            return GitRepositoryStatus(
                repositoryRoot: repositoryRoot,
                branchName: branchName,
                changedFiles: parsedStatus.changedFiles,
                ignoredPaths: parsedStatus.ignoredPaths,
                upstreamBranch: sync.upstream,
                aheadCount: sync.ahead,
                behindCount: sync.behind,
                hasRemote: sync.hasRemote
            )
        }.value
    }

    /// Local-only (no network): whether a remote exists, the current branch's upstream, and the
    /// ahead/behind commit counts. All defensive — missing upstream/detached HEAD yields nil/0/0.
    private func resolveSyncStatus(for repositoryRoot: URL) -> (upstream: String?, ahead: Int, behind: Int, hasRemote: Bool) {
        let remotes = (try? runGit(arguments: ["remote"], in: repositoryRoot, allowNonZeroExit: true))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hasRemote = !remotes.isEmpty

        let rawUpstream = (try? runGit(
            arguments: ["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}"],
            in: repositoryRoot,
            allowNonZeroExit: true
        ))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !rawUpstream.isEmpty, rawUpstream != "@{upstream}" else {
            return (nil, 0, 0, hasRemote)
        }

        // `git rev-list --left-right --count @{upstream}...HEAD` prints "<behind>\t<ahead>".
        let counts = (try? runGit(
            arguments: ["rev-list", "--left-right", "--count", "@{upstream}...HEAD"],
            in: repositoryRoot,
            allowNonZeroExit: true
        ))?.split(whereSeparator: { $0 == " " || $0 == "\t" || $0.isNewline }).compactMap { Int($0) } ?? []
        let behind = counts.count > 0 ? counts[0] : 0
        let ahead = counts.count > 1 ? counts[1] : 0
        return (rawUpstream, ahead, behind, hasRemote)
    }

    func diff(for changedFile: GitChangedFile, projectRoot: URL?) async -> GitDiffOutcome {
        guard let projectRoot else {
            return .failed
        }

        return await Task.detached(priority: .utility) { [self] in
            guard let repositoryRoot = try? resolveRepositoryRoot(for: projectRoot) else {
                return .failed
            }

            let diffText: String
            if changedFile.kind == .untracked {
                let fileURL = repositoryRoot.appendingPathComponent(changedFile.path)
                diffText = (try? runGit(
                    arguments: [
                        "diff",
                        "--no-index",
                        "--no-ext-diff",
                        "--",
                        "/dev/null",
                        fileURL.path
                    ],
                    in: repositoryRoot,
                    allowNonZeroExit: true
                )) ?? ""
            } else {
                let staged = (try? runGit(
                    arguments: ["diff", "--cached", "--no-ext-diff", "--", changedFile.path],
                    in: repositoryRoot,
                    allowNonZeroExit: true
                )) ?? ""
                let unstaged = (try? runGit(
                    arguments: ["diff", "--no-ext-diff", "--", changedFile.path],
                    in: repositoryRoot,
                    allowNonZeroExit: true
                )) ?? ""
                diffText = [staged, unstaged]
                    .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                    .joined(separator: staged.isEmpty || unstaged.isEmpty ? "" : "\n")
            }

            let trimmed = diffText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return .noChanges }
            return .diff(GitDiffResult(path: changedFile.path, text: trimmed))
        }.value
    }

    func blame(for fileURL: URL?, line: Int, projectRoot: URL?) async -> GitBlameInfo? {
        guard let projectRoot, let fileURL, line > 0 else {
            return nil
        }

        return await Task.detached(priority: .utility) { [self] in
            guard let repositoryRoot = try? resolveRepositoryRoot(for: projectRoot) else {
                return nil
            }

            let relativePath = relativePath(for: fileURL, repositoryRoot: repositoryRoot)
            let output = try? runGit(
                arguments: [
                    "blame",
                    "-L", "\(line),\(line)",
                    "--line-porcelain",
                    "--",
                    relativePath
                ],
                in: repositoryRoot
            )
            guard let output else { return nil }
            return parseBlame(output)
        }.value
    }

    func stage(changedFile: GitChangedFile, projectRoot: URL?) async -> GitOperationResult {
        await mutateRepository(projectRoot: projectRoot) { [self] repositoryRoot in
            _ = try self.runGit(arguments: ["add", "--", changedFile.path], in: repositoryRoot)
            return .success
        }
    }

    func unstage(changedFile: GitChangedFile, projectRoot: URL?) async -> GitOperationResult {
        await mutateRepository(projectRoot: projectRoot) { [self] repositoryRoot in
            _ = try self.runGit(arguments: ["restore", "--staged", "--", changedFile.path], in: repositoryRoot)
            return .success
        }
    }

    func discard(changedFile: GitChangedFile, projectRoot: URL?) async -> GitOperationResult {
        await mutateRepository(projectRoot: projectRoot) { [self] repositoryRoot in
            if changedFile.kind == .untracked {
                let targetURL = repositoryRoot.appendingPathComponent(changedFile.path)
                // Discarding an untracked file moves it to the Trash so it stays recoverable.
                try FileManager.default.trashItem(at: targetURL, resultingItemURL: nil)
            } else {
                _ = try self.runGit(arguments: ["restore", "--", changedFile.path], in: repositoryRoot)
            }
            return .success
        }
    }

    func commit(message: String, projectRoot: URL?) async -> GitOperationResult {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .failure("Enter a commit message.")
        }
        return await mutateRepository(projectRoot: projectRoot) { [self] repositoryRoot in
            // Commits the currently staged changes; git exits non-zero (→ .failure) if nothing is staged.
            _ = try self.runGit(arguments: ["commit", "-m", trimmed], in: repositoryRoot)
            return .success
        }
    }

    func fetch(projectRoot: URL?) async -> GitOperationResult {
        await mutateRepository(projectRoot: projectRoot) { [self] repositoryRoot in
            // `git fetch` with no remote is a silent no-op (exits 0), so precheck explicitly.
            let remotes = (try self.runGit(arguments: ["remote"], in: repositoryRoot, allowNonZeroExit: true))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !remotes.isEmpty else {
                return .failure("No remote repository configured.")
            }
            _ = try self.runGit(arguments: ["fetch", "--prune"], in: repositoryRoot, timeout: 60)
            return .success
        }
    }

    func pull(projectRoot: URL?) async -> GitOperationResult {
        await mutateRepository(projectRoot: projectRoot) { [self] repositoryRoot in
            let upstream = (try? self.runGit(
                arguments: ["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}"],
                in: repositoryRoot,
                allowNonZeroExit: true
            ))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !upstream.isEmpty, upstream != "@{upstream}" else {
                return .failure("No upstream branch configured. Push first to set one.")
            }
            // --ff-only is the only fully safe non-interactive pull: divergence aborts cleanly
            // (exit non-zero → .failure) with no half-finished merge/rebase left behind.
            _ = try self.runGit(arguments: ["pull", "--ff-only"], in: repositoryRoot, timeout: 60)
            return .success
        }
    }

    func push(projectRoot: URL?) async -> GitOperationResult {
        await mutateRepository(projectRoot: projectRoot) { [self] repositoryRoot in
            let branch = (try self.runGit(arguments: ["branch", "--show-current"], in: repositoryRoot))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !branch.isEmpty else {
                return .failure("Cannot push in detached HEAD state.")
            }
            let upstream = (try? self.runGit(
                arguments: ["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}"],
                in: repositoryRoot,
                allowNonZeroExit: true
            ))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if upstream.isEmpty || upstream == "@{upstream}" {
                _ = try self.runGit(arguments: ["push", "-u", "origin", branch], in: repositoryRoot, timeout: 60)
            } else {
                _ = try self.runGit(arguments: ["push"], in: repositoryRoot, timeout: 60)
            }
            return .success
        }
    }

    private func resolveRepositoryRoot(for projectRoot: URL) throws -> URL {
        let output = try runGit(
            arguments: ["rev-parse", "--show-toplevel"],
            in: projectRoot
        )
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw GitServiceError.invalidRepositoryRoot
        }
        return URL(fileURLWithPath: trimmed).standardizedFileURL
    }

    private func resolveBranchName(for repositoryRoot: URL) -> String? {
        if let branch = try? runGit(
            arguments: ["branch", "--show-current"],
            in: repositoryRoot
        ).trimmingCharacters(in: .whitespacesAndNewlines),
           !branch.isEmpty {
            return branch
        }

        if let detached = try? runGit(
            arguments: ["rev-parse", "--short", "HEAD"],
            in: repositoryRoot
        ).trimmingCharacters(in: .whitespacesAndNewlines),
           !detached.isEmpty {
            return "detached@\(detached)"
        }

        return nil
    }

    private func loadRepositoryStatus(for repositoryRoot: URL) throws -> (changedFiles: [GitChangedFile], ignoredPaths: Set<String>) {
        let output = try runGit(
            arguments: ["status", "--ignored", "--porcelain=v1"],
            in: repositoryRoot
        )

        var changedFiles: [GitChangedFile] = []
        var ignoredPaths = Set<String>()

        for line in output.split(whereSeparator: \.isNewline).map(String.init) {
            if let ignoredPath = parseIgnoredPath(line) {
                ignoredPaths.insert(ignoredPath)
                continue
            }

            if let changedFile = parseChangedFile(line) {
                changedFiles.append(changedFile)
            }
        }

        changedFiles.sort { lhs, rhs in
            lhs.path.localizedStandardCompare(rhs.path) == .orderedAscending
        }

        return (changedFiles, ignoredPaths)
    }

    private func parseIgnoredPath(_ line: String) -> String? {
        guard line.count >= 3 else { return nil }
        let xStatus = line[line.startIndex]
        let yStatus = line[line.index(after: line.startIndex)]
        guard xStatus == "!" && yStatus == "!" else { return nil }

        let pathStart = line.index(line.startIndex, offsetBy: 3)
        let rawPath = String(line[pathStart...]).trimmingCharacters(in: .whitespaces)
        return rawPath.isEmpty ? nil : rawPath
    }

    private func parseChangedFile(_ line: String) -> GitChangedFile? {
        guard line.count >= 3 else { return nil }
        let xStatus = line[line.startIndex]
        let yStatus = line[line.index(after: line.startIndex)]

        if xStatus == "!" && yStatus == "!" {
            return nil
        }

        let pathStart = line.index(line.startIndex, offsetBy: 3)
        let rawPath = String(line[pathStart...]).trimmingCharacters(in: .whitespaces)
        guard !rawPath.isEmpty else { return nil }

        let previousPath: String?
        let path: String
        if rawPath.contains(" -> "), xStatus == "R" || yStatus == "R" || xStatus == "C" || yStatus == "C" {
            let parts = rawPath.components(separatedBy: " -> ")
            previousPath = parts.dropLast().joined(separator: " -> ")
            path = parts.last ?? rawPath
        } else {
            previousPath = nil
            path = rawPath
        }

        return GitChangedFile(
            path: path,
            previousPath: previousPath,
            kind: changeKind(indexStatus: xStatus, workingTreeStatus: yStatus),
            indexStatus: xStatus,
            workingTreeStatus: yStatus
        )
    }

    private func changeKind(indexStatus: Character, workingTreeStatus: Character) -> GitChangeKind {
        if indexStatus == "?" && workingTreeStatus == "?" {
            return .untracked
        }

        if [indexStatus, workingTreeStatus].contains("U")
            || (indexStatus == "A" && workingTreeStatus == "A")
            || (indexStatus == "D" && workingTreeStatus == "D") {
            return .conflicted
        }

        if [indexStatus, workingTreeStatus].contains("R") {
            return .renamed
        }

        if [indexStatus, workingTreeStatus].contains("C") {
            return .copied
        }

        if [indexStatus, workingTreeStatus].contains("A") {
            return .added
        }

        if [indexStatus, workingTreeStatus].contains("D") {
            return .deleted
        }

        return .modified
    }

    private func parseBlame(_ output: String) -> GitBlameInfo? {
        let lines = output.split(whereSeparator: \.isNewline).map(String.init)
        guard let header = lines.first?.split(separator: " ").first.map(String.init), !header.isEmpty else {
            return nil
        }

        var author = "Unknown"
        var summary = ""
        var authoredDate: Date?

        for line in lines {
            if line.hasPrefix("author ") {
                author = String(line.dropFirst("author ".count))
            } else if line.hasPrefix("author-time ") {
                let rawValue = String(line.dropFirst("author-time ".count))
                if let seconds = TimeInterval(rawValue) {
                    authoredDate = Date(timeIntervalSince1970: seconds)
                }
            } else if line.hasPrefix("summary ") {
                summary = String(line.dropFirst("summary ".count))
            }
        }

        let shortCommitHash = header == String(repeating: "0", count: 40)
            ? "Working Tree"
            : String(header.prefix(8))

        return GitBlameInfo(
            commitHash: header,
            shortCommitHash: shortCommitHash,
            author: author,
            summary: summary.isEmpty ? "No commit summary" : summary,
            authoredDate: authoredDate
        )
    }

    private func relativePath(for fileURL: URL, repositoryRoot: URL) -> String {
        let filePath = fileURL.standardizedFileURL.path
        let rootPath = repositoryRoot.standardizedFileURL.path
        guard filePath.hasPrefix(rootPath + "/") else {
            return filePath
        }
        return String(filePath.dropFirst(rootPath.count + 1))
    }

    private func mutateRepository(
        projectRoot: URL?,
        mutation: @escaping (URL) throws -> GitOperationResult
    ) async -> GitOperationResult {
        guard let projectRoot else {
            return .failure("Open a repository before running Git actions.")
        }

        return await Task.detached(priority: .utility) { [self] in
            do {
                let repositoryRoot = try resolveRepositoryRoot(for: projectRoot)
                return try mutation(repositoryRoot)
            } catch {
                return .failure(error.localizedDescription)
            }
        }.value
    }

    private func runGit(
        arguments: [String],
        in workingDirectory: URL,
        allowNonZeroExit: Bool = false,
        timeout: TimeInterval? = nil
    ) throws -> String {
        guard let executableURL = resolvedGitExecutableURL() else {
            throw GitServiceError.toolUnavailable
        }

        // GIT_TERMINAL_PROMPT=0 + SSH BatchMode make network ops (push/pull/fetch) fail fast on
        // missing credentials instead of blocking on an interactive prompt.
        let environment = gitEnvironment().merging([
            "GIT_PAGER": "cat",
            "GIT_TERMINAL_PROMPT": "0",
            "GIT_SSH_COMMAND": "ssh -oBatchMode=yes -oStrictHostKeyChecking=accept-new"
        ]) { _, newValue in
            newValue
        }

        let result = try ProcessRunner.run(
            executableURL: executableURL,
            arguments: arguments,
            currentDirectoryURL: workingDirectory,
            environment: environment,
            timeout: timeout
        )

        if result.terminationStatus != 0 && !allowNonZeroExit {
            throw GitServiceError.commandFailed(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return result.stdout
    }

    private func resolvedGitExecutableURL() -> URL? {
        guard let executablePath = ExecutableResolver.resolve(
            gitCommandName,
            environment: gitBaseEnvironment,
            additionalSearchDirectories: gitAdditionalSearchPaths,
            homeDirectory: gitHomeDirectory
        ) else {
            return nil
        }
        return URL(fileURLWithPath: executablePath)
    }

    private func gitEnvironment() -> [String: String] {
        ExecutableResolver.augmentedEnvironment(
            base: gitBaseEnvironment,
            additionalSearchDirectories: gitAdditionalSearchPaths,
            homeDirectory: gitHomeDirectory
        )
    }

    private var gitHomeDirectory: String {
        guard let configuredHome = gitBaseEnvironment["HOME"], !configuredHome.isEmpty else {
            return NSHomeDirectory()
        }
        return configuredHome
    }
}

enum GitServiceError: LocalizedError {
    case invalidRepositoryRoot
    case toolUnavailable
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidRepositoryRoot:
            return "Git did not return a repository root."
        case .toolUnavailable:
            return "Git executable could not be resolved."
        case .commandFailed(let message):
            return message.isEmpty ? "Git command failed." : message
        }
    }
}
