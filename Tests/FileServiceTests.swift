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
}
