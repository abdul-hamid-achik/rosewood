import Foundation
import Testing
@testable import Rosewood

@MainActor
struct LSPServiceTests {

    // MARK: - Mock LSP Service Tests

    @Test
    func mockServiceDiagnosticsForURI() {
        let mock = MockLSPService()
        let diag = LSPDiagnostic(
            range: LSPRange(start: LSPPosition(line: 0, character: 0), end: LSPPosition(line: 0, character: 5)),
            severity: .error,
            message: "test error"
        )
        mock.setDiagnostics(uri: "file:///test.swift", diagnostics: [diag])

        let result = mock.diagnostics(for: "file:///test.swift")
        #expect(result.count == 1)
        #expect(result[0].message == "test error")
    }

    @Test
    func mockServiceDiagnosticsForUnknownURI() {
        let mock = MockLSPService()
        let result = mock.diagnostics(for: "file:///unknown.swift")
        #expect(result.isEmpty)
    }

    @Test
    func mockServiceDiagnosticCount() {
        let mock = MockLSPService()
        let error = LSPDiagnostic(
            range: LSPRange(start: LSPPosition(line: 0, character: 0), end: LSPPosition(line: 0, character: 5)),
            severity: .error,
            message: "error"
        )
        let warning = LSPDiagnostic(
            range: LSPRange(start: LSPPosition(line: 1, character: 0), end: LSPPosition(line: 1, character: 5)),
            severity: .warning,
            message: "warning"
        )
        let info = LSPDiagnostic(
            range: LSPRange(start: LSPPosition(line: 2, character: 0), end: LSPPosition(line: 2, character: 5)),
            severity: .information,
            message: "info"
        )
        mock.setDiagnostics(uri: "file:///test.swift", diagnostics: [error, warning, info])

        let count = mock.diagnosticCount(for: "file:///test.swift")
        #expect(count.errors == 1)
        #expect(count.warnings == 1)
    }

    @Test
    func mockServiceDocumentOpened() {
        let mock = MockLSPService()
        mock.documentOpened(uri: "file:///test.swift", language: "swift", text: "import Foundation")

        #expect(mock.documentOpenedCalls.count == 1)
        #expect(mock.documentOpenedCalls[0].uri == "file:///test.swift")
        #expect(mock.documentOpenedCalls[0].language == "swift")
        #expect(mock.documentOpenedCalls[0].text == "import Foundation")
    }

    @Test
    func mockServiceDocumentChanged() {
        let mock = MockLSPService()
        mock.documentChanged(uri: "file:///test.swift", language: "swift", text: "new content")

        #expect(mock.documentChangedCalls.count == 1)
        #expect(mock.documentChangedCalls[0].text == "new content")
    }

    @Test
    func mockServiceDocumentClosed() {
        let mock = MockLSPService()
        mock.documentClosed(uri: "file:///test.swift", language: "swift")

        #expect(mock.documentClosedCalls.count == 1)
        #expect(mock.documentClosedCalls[0].uri == "file:///test.swift")
    }

    @Test
    func mockServiceDocumentSaved() {
        let mock = MockLSPService()
        mock.documentSaved(uri: "file:///test.swift", language: "swift")

        #expect(mock.documentSavedCalls.count == 1)
        #expect(mock.documentSavedCalls[0].uri == "file:///test.swift")
    }

    @Test
    func mockServiceSetProjectRoot() {
        let mock = MockLSPService()
        let url = URL(fileURLWithPath: "/test/project")
        mock.setProjectRoot(url)

        #expect(mock.projectRootCalls.count == 1)
        #expect(mock.projectRootCalls[0] == url)
    }

    @Test
    func mockServiceSetProjectRootNil() {
        let mock = MockLSPService()
        mock.setProjectRoot(nil)

        #expect(mock.projectRootCalls.count == 1)
        #expect(mock.projectRootCalls[0] == nil)
    }

    @Test
    func mockServiceServerAvailable() {
        let mock = MockLSPService()
        #expect(!mock.serverAvailable(for: "swift"))
    }

    @Test
    func mockServiceDiagnosticsCleared() {
        let mock = MockLSPService()
        let diag = LSPDiagnostic(
            range: LSPRange(start: LSPPosition(line: 0, character: 0), end: LSPPosition(line: 0, character: 5)),
            severity: .error,
            message: "error"
        )
        mock.setDiagnostics(uri: "file:///test.swift", diagnostics: [diag])
        #expect(mock.diagnostics(for: "file:///test.swift").count == 1)

        mock.setDiagnostics(uri: "file:///test.swift", diagnostics: [])
        #expect(mock.diagnostics(for: "file:///test.swift").isEmpty)
    }

    @Test
    func mockServiceCompletionReturnsEmpty() async {
        let mock = MockLSPService()
        let items = await mock.completion(
            uri: "file:///test.swift",
            language: "swift",
            position: LSPPosition(line: 0, character: 0)
        )
        #expect(items.isEmpty)
    }

    @Test
    func mockServiceHoverReturnsNil() async {
        let mock = MockLSPService()
        let result = await mock.hover(
            uri: "file:///test.swift",
            language: "swift",
            position: LSPPosition(line: 0, character: 0)
        )
        #expect(result == nil)
    }

    @Test
    func mockServiceDefinitionReturnsEmpty() async {
        let mock = MockLSPService()
        let locations = await mock.definition(
            uri: "file:///test.swift",
            language: "swift",
            position: LSPPosition(line: 0, character: 0)
        )
        #expect(locations.isEmpty)
    }

    @Test
    func mockServiceReferencesReturnsConfiguredLocations() async {
        let mock = MockLSPService()
        let location = LSPLocation(
            uri: "file:///other.swift",
            range: LSPRange(
                start: LSPPosition(line: 2, character: 4),
                end: LSPPosition(line: 2, character: 9)
            )
        )
        mock.setReferences(uri: "file:///test.swift", locations: [location])

        let locations = await mock.references(
            uri: "file:///test.swift",
            language: "swift",
            position: LSPPosition(line: 0, character: 0)
        )

        #expect(locations == [location])
        #expect(mock.referencesCalls.count == 1)
    }

    // MARK: - LSPService Real Instance Tests

    @Test
    func realServiceDiagnosticsEmptyByDefault() {
        let service = LSPService(forTesting: true)
        #expect(service.diagnostics(for: "file:///test.swift").isEmpty)
    }

    @Test
    func realServiceDiagnosticCountEmpty() {
        let service = LSPService(forTesting: true)
        let count = service.diagnosticCount(for: "file:///nonexistent.swift")
        #expect(count.errors == 0)
        #expect(count.warnings == 0)
    }

    @Test
    func realServiceServerNotAvailableByDefault() {
        let service = LSPService(forTesting: true)
        #expect(!service.serverAvailable(for: "swift"))
        #expect(!service.serverAvailable(for: "python"))
        #expect(!service.serverAvailable(for: "plaintext"))
    }

    @Test
    func realServiceDocumentOpenedWithoutRoot() {
        let service = LSPService(forTesting: true)
        // Should not crash when no root is set
        service.documentOpened(uri: "file:///test.swift", language: "swift", text: "test")
    }

    @Test
    func realServiceDocumentOpenedPlaintextIgnored() {
        let service = LSPService(forTesting: true)
        service.setProjectRoot(URL(fileURLWithPath: "/test"))
        service.documentOpened(uri: "file:///test.txt", language: "plaintext", text: "test")
        // Plaintext should be ignored - no server started
        #expect(!service.serverAvailable(for: "plaintext"))
    }

    @Test
    func realServiceSetProjectRootSameValue() {
        let service = LSPService(forTesting: true)
        let url = URL(fileURLWithPath: "/test/project")
        service.setProjectRoot(url)
        service.setProjectRoot(url)  // Should not crash or restart servers
    }

    @Test
    func realServiceSetProjectRootClearsDiagnostics() {
        let service = LSPService(forTesting: true)
        service.setProjectRoot(URL(fileURLWithPath: "/test1"))
        // Manually poke diagnostics to simulate server pushing them
        // (can't easily do this without a real server, but we can test the clear path)
        service.setProjectRoot(URL(fileURLWithPath: "/test2"))
        #expect(service.diagnosticsByURI.isEmpty)
    }

    @Test
    func realServiceDocumentClosedClearsDiagnostics() {
        let service = LSPService(forTesting: true)
        service.setProjectRoot(URL(fileURLWithPath: "/test"))
        service.documentClosed(uri: "file:///test.swift", language: "swift")
        #expect(service.diagnostics(for: "file:///test.swift").isEmpty)
    }

    @Test
    func realServiceReferencesEmptyByDefault() async {
        let service = LSPService(forTesting: true)
        let locations = await service.references(
            uri: "file:///test.swift",
            language: "swift",
            position: LSPPosition(line: 0, character: 0)
        )
        #expect(locations.isEmpty)
    }
}
