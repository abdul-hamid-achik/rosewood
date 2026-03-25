import Foundation
import Testing
@testable import Rosewood

struct WorkspaceSymbolIndexerTests {

    @Test
    func extractsSwiftTypeAndFunctionSymbols() {
        let fileURL = URL(fileURLWithPath: "/tmp/Alpha.swift")
        let contents = """
        struct AlphaSymbol {
            func alphaHelper() {}
        }
        """

        let symbols = WorkspaceSymbolIndexer.extractSymbols(
            from: contents,
            fileURL: fileURL,
            displayPath: "Alpha.swift",
            originalIndex: 0
        )

        #expect(symbols.map(\.name) == ["AlphaSymbol", "alphaHelper"])
        #expect(symbols.map(\.kind) == ["struct", "func"])
        #expect(symbols.map(\.line) == [1, 2])
    }

    @Test
    func extractsJavaScriptArrowFunctionSymbols() {
        let fileURL = URL(fileURLWithPath: "/tmp/app.ts")
        let contents = """
        const loadProject = async () => {
            return true
        }
        """

        let symbols = WorkspaceSymbolIndexer.extractSymbols(
            from: contents,
            fileURL: fileURL,
            displayPath: "app.ts",
            originalIndex: 0
        )

        #expect(symbols.count == 1)
        #expect(symbols.first?.name == "loadProject")
        #expect(symbols.first?.kind == "function")
        #expect(symbols.first?.column == 7)
    }

    @Test
    func shouldIndexOnlySupportedReasonableFiles() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let supportedURL = directoryURL.appendingPathComponent("Alpha.swift")
        let unsupportedURL = directoryURL.appendingPathComponent("notes.txt")
        let largeURL = directoryURL.appendingPathComponent("Large.swift")

        try "func alpha() {}\n".write(to: supportedURL, atomically: true, encoding: .utf8)
        try "hello\n".write(to: unsupportedURL, atomically: true, encoding: .utf8)
        try String(repeating: "a", count: 600_000).write(to: largeURL, atomically: true, encoding: .utf8)

        #expect(WorkspaceSymbolIndexer.shouldIndex(fileURL: supportedURL))
        #expect(!WorkspaceSymbolIndexer.shouldIndex(fileURL: unsupportedURL))
        #expect(!WorkspaceSymbolIndexer.shouldIndex(fileURL: largeURL))
    }
}
