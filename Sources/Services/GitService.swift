import Foundation

protocol GitServiceProtocol: AnyObject {
    func repositoryStatus(for projectRoot: URL?) async -> GitRepositoryStatus
    func diff(for changedFile: GitChangedFile, projectRoot: URL?) async -> GitDiffResult?
    func blame(for fileURL: URL?, line: Int, projectRoot: URL?) async -> GitBlameInfo?
    func stage(changedFile: GitChangedFile, projectRoot: URL?) async -> GitOperationResult
    func unstage(changedFile: GitChangedFile, projectRoot: URL?) async -> GitOperationResult
    func discard(changedFile: GitChangedFile, projectRoot: URL?) async -> GitOperationResult
}

final class GitService: GitServiceProtocol {
    static let shared = GitService()

    init() {}

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
            return GitRepositoryStatus(
                repositoryRoot: repositoryRoot,
                branchName: branchName,
                changedFiles: parsedStatus.changedFiles,
                ignoredPaths: parsedStatus.ignoredPaths
            )
        }.value
    }

    func diff(for changedFile: GitChangedFile, projectRoot: URL?) async -> GitDiffResult? {
        guard let projectRoot else {
            return nil
        }

        return await Task.detached(priority: .utility) { [self] in
            guard let repositoryRoot = try? resolveRepositoryRoot(for: projectRoot) else {
                return nil
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
            guard !trimmed.isEmpty else { return nil }
            return GitDiffResult(path: changedFile.path, text: trimmed)
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
                try FileManager.default.removeItem(at: targetURL)
            } else {
                _ = try self.runGit(arguments: ["restore", "--", changedFile.path], in: repositoryRoot)
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
        allowNonZeroExit: Bool = false
    ) throws -> String {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + arguments
        process.currentDirectoryURL = workingDirectory
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.environment = (ProcessInfo.processInfo.environment).merging([
            "GIT_PAGER": "cat"
        ]) { _, newValue in
            newValue
        }

        try process.run()
        process.waitUntilExit()

        let stdout = String(
            data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        let stderr = String(
            data: stderrPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""

        if process.terminationStatus != 0 && !allowNonZeroExit {
            throw GitServiceError.commandFailed(stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return stdout
    }
}

enum GitServiceError: LocalizedError {
    case invalidRepositoryRoot
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidRepositoryRoot:
            return "Git did not return a repository root."
        case .commandFailed(let message):
            return message.isEmpty ? "Git command failed." : message
        }
    }
}
