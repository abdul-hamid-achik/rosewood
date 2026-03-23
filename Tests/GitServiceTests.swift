import Foundation
import Testing
@testable import Rosewood

struct GitServiceTests {
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

        let diff = await GitService().diff(for: changedFile, projectRoot: repositoryURL)

        #expect(diff?.path == "Tracked.swift")
        #expect(diff?.text.contains("-let tracked = 1") == true)
        #expect(diff?.text.contains("+let tracked = 2") == true)
        #expect(diff?.hunkCount == 1)
        #expect(diff?.additionCount == 1)
        #expect(diff?.deletionCount == 1)
        #expect(diff?.hunks.first?.rows.first?.leftText == "let tracked = 1")
        #expect(diff?.hunks.first?.rows.first?.rightText == "let tracked = 2")
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

        let hunk = try? #require(diff.hunks.first)
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
