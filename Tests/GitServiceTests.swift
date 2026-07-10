import Foundation
import Testing
@testable import Rosewood

struct GitServiceTests {
    @Test
    func toolAvailableResolvesGitOutsideMinimalGUIPath() async throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("rosewood-git-resolver-\(UUID().uuidString)", isDirectory: true)
        let executableURL = directoryURL.appendingPathComponent("fake-git")
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try """
        #!/bin/sh
        test "$1" = "--version"
        """.write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executableURL.path
        )
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let service = GitService(
            gitBaseEnvironment: ["PATH": "/usr/bin:/bin"],
            gitAdditionalSearchPaths: [directoryURL.path],
            gitCommandName: "fake-git"
        )

        #expect(await service.toolAvailable())
    }

    @Test
    func repositoryStatusReturnsBranchAndChangedFiles() async throws {
        let repositoryURL = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }

        let trackedURL = repositoryURL.appendingPathComponent("Tracked.swift")
        let newFileURL = repositoryURL.appendingPathComponent("New.swift")

        try "let tracked = 2\n".write(to: trackedURL, atomically: true, encoding: .utf8)
        try "let fresh = true\n".write(to: newFileURL, atomically: true, encoding: .utf8)

        let status = await GitService().repositoryStatus(for: repositoryURL)

        #expect(status.isRepository)
        #expect(status.branchName == "main")
        #expect(status.changedFiles.count == 2)
        #expect(status.changedFiles.contains { $0.path == "Tracked.swift" && $0.kind == .modified })
        #expect(status.changedFiles.contains { $0.path == "New.swift" && $0.kind == .untracked })
        #expect(status.ignoredPaths.contains("Ignored.log"))
    }

    @Test
    func diffReturnsUnifiedPatchForChangedFile() async throws {
        let repositoryURL = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }

        let trackedURL = repositoryURL.appendingPathComponent("Tracked.swift")
        try "let tracked = 2\n".write(to: trackedURL, atomically: true, encoding: .utf8)

        let status = await GitService().repositoryStatus(for: repositoryURL)
        let changedFile = try #require(status.changedFiles.first { $0.path == "Tracked.swift" })

        let outcome = await GitService().diff(for: changedFile, projectRoot: repositoryURL)

        guard case .diff(let diff) = outcome else {
            Issue.record("expected a diff outcome, got \(outcome)")
            return
        }
        #expect(diff.path == "Tracked.swift")
        #expect(diff.text.contains("-let tracked = 1") == true)
        #expect(diff.text.contains("+let tracked = 2") == true)
        #expect(diff.hunkCount == 1)
        #expect(diff.additionCount == 1)
        #expect(diff.deletionCount == 1)
        #expect(diff.hunks.first?.rows.first?.leftText == "let tracked = 1")
        #expect(diff.hunks.first?.rows.first?.rightText == "let tracked = 2")
    }

    @Test
    func commitCreatesACommitFromStagedChanges() async throws {
        let repositoryURL = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }
        let service = GitService()

        // Modify a tracked file and stage it.
        try "let tracked = 99\n".write(to: repositoryURL.appendingPathComponent("Tracked.swift"), atomically: true, encoding: .utf8)
        let status = await service.repositoryStatus(for: repositoryURL)
        let changed = try #require(status.changedFiles.first { $0.path == "Tracked.swift" })
        _ = await service.stage(changedFile: changed, projectRoot: repositoryURL)

        let result = await service.commit(message: "Update tracked", projectRoot: repositoryURL)
        #expect(result.isSuccess)

        // After committing, the file is no longer a pending change.
        let after = await service.repositoryStatus(for: repositoryURL)
        #expect(after.changedFiles.contains { $0.path == "Tracked.swift" } == false)
    }

    @Test
    func commitFailsWhenNothingStaged() async throws {
        let repositoryURL = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }
        let service = GitService()

        // makeRepository leaves a clean tree (only an ignored file), so there is nothing to commit.
        let result = await service.commit(message: "Empty", projectRoot: repositoryURL)
        #expect(result.isSuccess == false)
    }

    @Test
    func commitRejectsEmptyMessage() async throws {
        let repositoryURL = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }
        let result = await GitService().commit(message: "   ", projectRoot: repositoryURL)
        #expect(result.isSuccess == false)
    }

    @Test
    func diffReturnsFailedOutsideAGitRepository() async throws {
        // A directory that is not inside any git repository can't resolve a repo root,
        // so the diff must report .failed rather than collapsing to a "no diff" outcome.
        let nonRepo = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: nonRepo, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: nonRepo) }

        let changedFile = GitChangedFile(
            path: "Whatever.swift",
            previousPath: nil,
            kind: .modified,
            indexStatus: " ",
            workingTreeStatus: "M"
        )
        let outcome = await GitService().diff(for: changedFile, projectRoot: nonRepo)
        #expect(outcome == .failed)
    }

    @Test
    func gitDiffParserAlignsRemovalAndAdditionBlocksSideBySide() {
        let diff = GitDiffResult(
            path: "Tracked.swift",
            text: """
            diff --git a/Tracked.swift b/Tracked.swift
            index 1111111..2222222 100644
            --- a/Tracked.swift
            +++ b/Tracked.swift
            @@ -1,3 +1,4 @@ Example
             struct Sample {
            -    let oldValue = 1
            -    let removeMe = true
            +    let newValue = 2
            +    let extra = true
                 }
            """
        )

        #expect(diff.hunkCount == 1)
        #expect(diff.additionCount == 2)
        #expect(diff.deletionCount == 2)

        let hunk = diff.hunks.first
        #expect(hunk?.rows.count == 4)
        #expect(hunk?.rows[0].leftKind == .context)
        #expect(hunk?.rows[1].leftText == "    let oldValue = 1")
        #expect(hunk?.rows[1].rightText == "    let newValue = 2")
        #expect(hunk?.rows[2].leftText == "    let removeMe = true")
        #expect(hunk?.rows[2].rightText == "    let extra = true")
        #expect(hunk?.rows[3].leftText == "    }")
        #expect(hunk?.rows[3].rightText == "    }")
    }

    @Test
    func blameReturnsCommitMetadataForCommittedLine() async throws {
        let repositoryURL = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }

        let trackedURL = repositoryURL.appendingPathComponent("Tracked.swift")
        let blame = await GitService().blame(for: trackedURL, line: 1, projectRoot: repositoryURL)

        #expect(blame?.author == "Rosewood Tests")
        #expect(blame?.summary == "Initial commit")
        #expect(blame?.isUncommitted == false)
    }

    @Test
    func stageAndUnstageUpdateRepositoryStatus() async throws {
        let repositoryURL = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }

        let trackedURL = repositoryURL.appendingPathComponent("Tracked.swift")
        try "let tracked = 2\n".write(to: trackedURL, atomically: true, encoding: .utf8)

        let service = GitService()
        let initialStatus = await service.repositoryStatus(for: repositoryURL)
        let changedFile = try #require(initialStatus.changedFiles.first { $0.path == "Tracked.swift" })

        let stageResult = await service.stage(changedFile: changedFile, projectRoot: repositoryURL)
        #expect(stageResult.isSuccess)

        let stagedStatus = await service.repositoryStatus(for: repositoryURL)
        let stagedFile = try #require(stagedStatus.changedFiles.first { $0.path == "Tracked.swift" })
        #expect(stagedFile.hasStagedChanges)
        #expect(stagedFile.hasUnstagedChanges == false)

        let unstageResult = await service.unstage(changedFile: stagedFile, projectRoot: repositoryURL)
        #expect(unstageResult.isSuccess)

        let unstagedStatus = await service.repositoryStatus(for: repositoryURL)
        let unstagedFile = try #require(unstagedStatus.changedFiles.first { $0.path == "Tracked.swift" })
        #expect(unstagedFile.hasStagedChanges == false)
        #expect(unstagedFile.hasUnstagedChanges)
    }

    @Test
    func discardRestoresModifiedFileContents() async throws {
        let repositoryURL = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }

        let trackedURL = repositoryURL.appendingPathComponent("Tracked.swift")
        try "let tracked = 2\n".write(to: trackedURL, atomically: true, encoding: .utf8)

        let service = GitService()
        let initialStatus = await service.repositoryStatus(for: repositoryURL)
        let changedFile = try #require(initialStatus.changedFiles.first { $0.path == "Tracked.swift" })

        let discardResult = await service.discard(changedFile: changedFile, projectRoot: repositoryURL)
        #expect(discardResult.isSuccess)

        let restoredText = try String(contentsOf: trackedURL, encoding: .utf8)
        let refreshedStatus = await service.repositoryStatus(for: repositoryURL)

        #expect(restoredText == "let tracked = 1\n")
        #expect(refreshedStatus.changedFiles.contains { $0.path == "Tracked.swift" } == false)
    }
    @Test
    func statusHasNoUpstreamWithoutRemote() async throws {
        let repo = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repo) }
        let status = await GitService().repositoryStatus(for: repo)
        #expect(status.hasRemote == false)
        #expect(status.upstreamBranch == nil)
        #expect(status.aheadCount == 0)
        #expect(status.behindCount == 0)
    }

    @Test
    func pushSetsUpstreamAndDeliversCommit() async throws {
        let repo = try makeRepository()
        let remote = try makeBareRemote()
        defer { try? FileManager.default.removeItem(at: repo); try? FileManager.default.removeItem(at: remote) }
        try runGit(["remote", "add", "origin", remote.path], in: repo)

        let service = GitService()
        let result = await service.push(projectRoot: repo)
        #expect(result.isSuccess)
        // The commit reached the remote, and tracking is now set.
        #expect(try runGitCapture(["rev-parse", "HEAD"], in: repo) == runGitCapture(["rev-parse", "main"], in: remote))
        let status = await service.repositoryStatus(for: repo)
        #expect(status.upstreamBranch == "origin/main")
        #expect(status.hasRemote)
        #expect(status.aheadCount == 0)
        #expect(status.behindCount == 0)
    }

    @Test
    func statusReportsAheadAfterLocalCommit() async throws {
        let repo = try makeRepository()
        let remote = try makeBareRemote()
        defer { try? FileManager.default.removeItem(at: repo); try? FileManager.default.removeItem(at: remote) }
        try runGit(["remote", "add", "origin", remote.path], in: repo)
        let service = GitService()
        _ = await service.push(projectRoot: repo)

        try "let tracked = 2\n".write(to: repo.appendingPathComponent("Tracked.swift"), atomically: true, encoding: .utf8)
        try runGit(["commit", "-am", "local change"], in: repo)

        let status = await service.repositoryStatus(for: repo)
        #expect(status.aheadCount == 1)
        #expect(status.behindCount == 0)
    }

    @Test
    func fetchThenPullFastForwardsFromAdvancedRemote() async throws {
        let repo = try makeRepository()
        let remote = try makeBareRemote()
        defer { try? FileManager.default.removeItem(at: repo); try? FileManager.default.removeItem(at: remote) }
        try runGit(["remote", "add", "origin", remote.path], in: repo)
        let service = GitService()
        _ = await service.push(projectRoot: repo)

        // Advance the remote from a separate clone.
        let clone = try makeClone(of: remote)
        defer { try? FileManager.default.removeItem(at: clone) }
        try "advanced\n".write(to: clone.appendingPathComponent("NewFile.txt"), atomically: true, encoding: .utf8)
        try runGit(["add", "NewFile.txt"], in: clone)
        try runGit(["commit", "-m", "remote advance"], in: clone)
        try runGit(["push"], in: clone)

        #expect(await service.fetch(projectRoot: repo).isSuccess)
        let afterFetch = await service.repositoryStatus(for: repo)
        #expect(afterFetch.behindCount == 1)
        #expect(afterFetch.aheadCount == 0)

        #expect(await service.pull(projectRoot: repo).isSuccess)
        let afterPull = await service.repositoryStatus(for: repo)
        #expect(afterPull.behindCount == 0)
    }

    @Test
    func pullFailsOnDivergence() async throws {
        let repo = try makeRepository()
        let remote = try makeBareRemote()
        defer { try? FileManager.default.removeItem(at: repo); try? FileManager.default.removeItem(at: remote) }
        try runGit(["remote", "add", "origin", remote.path], in: repo)
        let service = GitService()
        _ = await service.push(projectRoot: repo)

        let clone = try makeClone(of: remote)
        defer { try? FileManager.default.removeItem(at: clone) }
        try "remote\n".write(to: clone.appendingPathComponent("R.txt"), atomically: true, encoding: .utf8)
        try runGit(["add", "R.txt"], in: clone)
        try runGit(["commit", "-m", "remote"], in: clone)
        try runGit(["push"], in: clone)

        // Local diverges from the advanced remote.
        try "local\n".write(to: repo.appendingPathComponent("L.txt"), atomically: true, encoding: .utf8)
        try runGit(["add", "L.txt"], in: repo)
        try runGit(["commit", "-m", "local"], in: repo)
        _ = await service.fetch(projectRoot: repo)

        // --ff-only must refuse to merge a diverged history.
        #expect(await service.pull(projectRoot: repo).isSuccess == false)
    }

    @Test
    func pushFailsWithoutRemote() async throws {
        let repo = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repo) }
        #expect(await GitService().push(projectRoot: repo).isSuccess == false)
    }

    @Test
    func fetchFailsWithoutRemote() async throws {
        let repo = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repo) }
        #expect(await GitService().fetch(projectRoot: repo).isSuccess == false)
    }
}

private func makeBareRemote() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("rosewood-git-remote-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    try runGit(["init", "--bare", "--initial-branch=main"], in: url)
    return url
}

private func makeClone(of remote: URL) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("rosewood-git-clone-\(UUID().uuidString)", isDirectory: true)
    try runGit(["clone", remote.path, url.path], in: FileManager.default.temporaryDirectory)
    // Identity is mandatory — the clone must not depend on ambient global git config (CI has none).
    try runGit(["config", "user.name", "Rosewood Clone"], in: url)
    try runGit(["config", "user.email", "clone@example.com"], in: url)
    return url
}

@discardableResult
private func runGitCapture(_ arguments: [String], in workingDirectory: URL) throws -> String {
    let process = Process()
    let stdoutPipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["git"] + arguments
    process.currentDirectoryURL = workingDirectory
    process.standardOutput = stdoutPipe
    process.standardError = Pipe()
    try process.run()
    process.waitUntilExit()
    return (String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

private func makeRepository() throws -> URL {
    let repositoryURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("rosewood-git-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: repositoryURL, withIntermediateDirectories: true)

    try runGit(["init", "--initial-branch=main"], in: repositoryURL)
    try runGit(["config", "user.name", "Rosewood Tests"], in: repositoryURL)
    try runGit(["config", "user.email", "rosewood@example.com"], in: repositoryURL)

    let trackedURL = repositoryURL.appendingPathComponent("Tracked.swift")
    let gitignoreURL = repositoryURL.appendingPathComponent(".gitignore")
    try "Ignored.log\n".write(to: gitignoreURL, atomically: true, encoding: .utf8)
    try "let tracked = 1\n".write(to: trackedURL, atomically: true, encoding: .utf8)

    try runGit(["add", "Tracked.swift", ".gitignore"], in: repositoryURL)
    try runGit(["commit", "-m", "Initial commit"], in: repositoryURL)
    try "ignore me\n".write(to: repositoryURL.appendingPathComponent("Ignored.log"), atomically: true, encoding: .utf8)

    return repositoryURL
}

private func runGit(_ arguments: [String], in workingDirectory: URL) throws {
    let process = Process()
    let stderrPipe = Pipe()

    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["git"] + arguments
    process.currentDirectoryURL = workingDirectory
    process.standardError = stderrPipe

    try process.run()
    process.waitUntilExit()

    if process.terminationStatus != 0 {
        let stderr = String(
            data: stderrPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        throw GitServiceError.commandFailed(stderr.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
