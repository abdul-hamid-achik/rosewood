import Foundation
import Testing
@testable import Rosewood

struct FileServiceTests {
    @Test
    func loadDirectoryRestoresExpandedDirectories() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let childDirectory = rootURL.appendingPathComponent("Sources", isDirectory: true)
        let nestedFile = childDirectory.appendingPathComponent("main.swift")

        try FileManager.default.createDirectory(at: childDirectory, withIntermediateDirectories: true)
        try "print(\"hi\")".write(to: nestedFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let tree = FileService.shared.loadDirectory(at: rootURL, expandedPaths: [childDirectory.path])

        #expect(tree.count == 1)
        #expect(tree[0].name == "Sources")
        #expect(tree[0].isExpanded)
        #expect(tree[0].children.map(\.name) == ["main.swift"])
    }

    @Test
    func readFileFallsBackToDetectedEncoding() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("yml")
        let text = "name: cafe"
        let data = text.data(using: .isoLatin1)!

        FileManager.default.createFile(atPath: fileURL.path, contents: data)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        #expect(try FileService.shared.readFile(at: fileURL) == text)
    }

    @Test
    func loadDirectorySortsDirectoriesBeforeFilesRecursively() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let docsDirectory = rootURL.appendingPathComponent("Docs", isDirectory: true)
        let srcDirectory = rootURL.appendingPathComponent("Sources", isDirectory: true)
        let nestedDirectory = srcDirectory.appendingPathComponent("Nested", isDirectory: true)
        let readmeFile = rootURL.appendingPathComponent("README.md")
        let appFile = srcDirectory.appendingPathComponent("App.swift")
        let nestedFile = nestedDirectory.appendingPathComponent("Data.json")

        try FileManager.default.createDirectory(at: nestedDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: docsDirectory, withIntermediateDirectories: true)
        try "# Rosewood".write(to: readmeFile, atomically: true, encoding: .utf8)
        try "struct App {}".write(to: appFile, atomically: true, encoding: .utf8)
        try "{}".write(to: nestedFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let tree = FileService.shared.loadDirectory(
            at: rootURL,
            expandedPaths: [srcDirectory.path, nestedDirectory.path]
        )

        #expect(tree.map(\.name) == ["Docs", "Sources", "README.md"])
        #expect(tree[1].isExpanded)
        #expect(tree[1].children.map(\.name) == ["Nested", "App.swift"])
        #expect(tree[1].children[0].isExpanded)
        #expect(tree[1].children[0].children.map(\.name) == ["Data.json"])
    }

    @Test
    func searchProjectFindsMatchesAcrossNestedFiles() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sourcesDirectory = rootURL.appendingPathComponent("Sources", isDirectory: true)
        let docsDirectory = rootURL.appendingPathComponent("Docs", isDirectory: true)
        let swiftFile = sourcesDirectory.appendingPathComponent("Example.swift")
        let markdownFile = docsDirectory.appendingPathComponent("README.md")

        try FileManager.default.createDirectory(at: sourcesDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: docsDirectory, withIntermediateDirectories: true)
        try """
        struct Example {
            let value = "rosewood"
        }
        """.write(to: swiftFile, atomically: true, encoding: .utf8)
        try """
        # Rosewood
        Search me please.
        """.write(to: markdownFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let results = FileService.shared.searchProject(at: rootURL, query: "rosewood")

        #expect(results.count == 2)
        #expect(results.map(\.fileName) == ["Docs/README.md".components(separatedBy: "/").last!, "Example.swift"])
        #expect(results.map(\.lineNumber) == [1, 2])
    }

    @Test
    func searchProjectCapturesMatchColumnsAndPerLineMatchRanges() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let docsDirectory = rootURL.appendingPathComponent("Docs", isDirectory: true)
        let readmeFile = docsDirectory.appendingPathComponent("README.md")

        try FileManager.default.createDirectory(at: docsDirectory, withIntermediateDirectories: true)
        try "  rosewood and ROSEWOOD  ".write(to: readmeFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let results = FileService.shared.searchProject(at: rootURL, query: "rosewood")

        let result = try #require(results.first)
        #expect(results.count == 1)
        #expect(result.lineText == "rosewood and ROSEWOOD")
        #expect(result.columnNumber == 3)
        #expect(result.matchCount == 2)
        #expect(result.matchRanges == [
            ProjectSearchMatchRange(start: 0, length: 8),
            ProjectSearchMatchRange(start: 13, length: 8)
        ])
    }

    @Test
    func searchProjectRespectsCaseSensitivityWholeWordAndRegex() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = rootURL.appendingPathComponent("Example.swift")

        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try """
        let ROSEWOOD = 1
        let rosewood_1 = 2
        let rosewood = 3
        let rosewood42 = 4
        """.write(to: fileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let wholeWordResults = FileService.shared.searchProject(
            at: rootURL,
            query: "rosewood",
            options: ProjectSearchOptions(isWholeWord: true)
        )
        #expect(wholeWordResults.map(\.lineNumber) == [1, 3])

        let caseSensitiveWholeWordResults = FileService.shared.searchProject(
            at: rootURL,
            query: "rosewood",
            options: ProjectSearchOptions(isCaseSensitive: true, isWholeWord: true)
        )
        #expect(caseSensitiveWholeWordResults.map(\.lineNumber) == [3])

        let regexResults = FileService.shared.searchProject(
            at: rootURL,
            query: "rosewood\\d+",
            options: ProjectSearchOptions(isRegularExpression: true)
        )
        #expect(regexResults.map(\.lineNumber) == [4])
    }

    @Test
    func searchProjectRespectsPathFiltersAndSkipsBinaryAndLargeFiles() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sourcesDirectory = rootURL.appendingPathComponent("Sources", isDirectory: true)
        let docsDirectory = rootURL.appendingPathComponent("Docs", isDirectory: true)
        let sourceFile = sourcesDirectory.appendingPathComponent("Alpha.swift")
        let docsFile = docsDirectory.appendingPathComponent("Guide.md")
        let binaryFile = rootURL.appendingPathComponent("blob.bin")
        let largeFile = rootURL.appendingPathComponent("Large.txt")

        try FileManager.default.createDirectory(at: sourcesDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: docsDirectory, withIntermediateDirectories: true)
        try "let rosewood = 1\n".write(to: sourceFile, atomically: true, encoding: .utf8)
        try "rosewood docs\n".write(to: docsFile, atomically: true, encoding: .utf8)
        try Data([0x00, 0x72, 0x6F, 0x73, 0x65]).write(to: binaryFile)
        try String(repeating: "rosewood", count: 150_000).write(to: largeFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let filteredResults = FileService.shared.searchProject(
            at: rootURL,
            query: "rosewood",
            options: ProjectSearchOptions(includeGlob: "Sources/**/*.swift", excludeGlob: "Docs/**")
        )

        #expect(filteredResults.count == 1)
        #expect(filteredResults.first?.filePath.standardizedFileURL == sourceFile.standardizedFileURL)
    }

    @Test
    func replaceInProjectUpdatesNestedFilesAndCountsMatches() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let srcDirectory = rootURL.appendingPathComponent("Sources", isDirectory: true)
        let docsDirectory = rootURL.appendingPathComponent("Docs", isDirectory: true)
        let swiftFile = srcDirectory.appendingPathComponent("Example.swift")
        let markdownFile = docsDirectory.appendingPathComponent("Guide.md")

        try FileManager.default.createDirectory(at: srcDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: docsDirectory, withIntermediateDirectories: true)
        try """
        let rosewood = "rosewood"
        print(rosewood)
        """.write(to: swiftFile, atomically: true, encoding: .utf8)
        try "Rosewood loves rosewood.".write(to: markdownFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let summary = try FileService.shared.replaceInProject(
            at: rootURL,
            searchQuery: "rosewood",
            replacement: "cedar"
        )

        #expect(summary.replacementCount == 5)
        #expect(summary.modifiedFiles.count == 2)
        #expect(try FileService.shared.readFile(at: swiftFile).contains("cedar"))
        #expect(try FileService.shared.readFile(at: markdownFile).contains("cedar"))
    }

    @Test
    func replaceInFilesOnlyTouchesProvidedFiles() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let alphaFile = rootURL.appendingPathComponent("Alpha.swift")
        let betaFile = rootURL.appendingPathComponent("Beta.swift")

        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try "let alpha = \"alpha\"\n".write(to: alphaFile, atomically: true, encoding: .utf8)
        try "let alpha = \"alpha\"\n".write(to: betaFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let summary = try FileService.shared.replaceInFiles(
            at: [alphaFile],
            searchQuery: "alpha",
            replacement: "beta"
        )

        #expect(summary.replacementCount == 2)
        #expect(summary.modifiedFiles == [alphaFile])
        #expect(try FileService.shared.readFile(at: alphaFile).contains("beta"))
        #expect(try FileService.shared.readFile(at: betaFile).contains("alpha"))
    }

    @Test
    func replaceSearchResultsOnlyTouchesSelectedLines() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = rootURL.appendingPathComponent("Alpha.swift")

        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try """
        let rosewood = "rosewood"
        let keep = "rosewood"
        """.write(to: fileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let allResults = FileService.shared.searchProject(at: rootURL, query: "rosewood")
        let selectedResult = try #require(allResults.first { $0.lineNumber == 2 })

        let summary = try FileService.shared.replaceSearchResults(
            [selectedResult],
            searchQuery: "rosewood",
            replacement: "cedar"
        )

        #expect(summary.replacementCount == 1)
        #expect(summary.modifiedFiles == [fileURL])
        #expect(try FileService.shared.readFile(at: fileURL) == """
        let rosewood = "rosewood"
        let keep = "cedar"
        """)
    }
}
