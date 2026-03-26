import Foundation

// MARK: - Server Status

enum LSPServerStatus: Sendable {
    case starting
    case ready
    case failed(String)
    case unavailable
}

// MARK: - LSP Service Protocol (for testability)

@MainActor
protocol LSPServiceProtocol: AnyObject {
    var diagnosticsByURI: [String: [LSPDiagnostic]] { get }
    var serverStatus: [String: LSPServerStatus] { get }

    func setProjectRoot(_ url: URL?)
    func documentOpened(uri: String, language: String, text: String)
    func documentChanged(uri: String, language: String, text: String)
    func documentClosed(uri: String, language: String)
    func documentSaved(uri: String, language: String)
    func diagnostics(for uri: String) -> [LSPDiagnostic]
    func diagnosticCount(for uri: String) -> (errors: Int, warnings: Int)
    func completion(uri: String, language: String, position: LSPPosition) async -> [CompletionItem]
    func hover(uri: String, language: String, position: LSPPosition) async -> HoverResult?
    func definition(uri: String, language: String, position: LSPPosition) async -> [LSPLocation]
    func references(uri: String, language: String, position: LSPPosition) async -> [LSPLocation]
    func serverAvailable(for language: String) -> Bool
    func injectDiagnosticsForTesting(uri: String, diagnostics: [LSPDiagnostic])
    func shutdownAll() async
}

// MARK: - LSP Service

@MainActor
final class LSPService: ObservableObject, LSPServiceProtocol {
    static let shared = LSPService()

    @Published private(set) var diagnosticsByURI: [String: [LSPDiagnostic]] = [:]
    @Published private(set) var serverStatus: [String: LSPServerStatus] = [:]

    private var clients: [String: LSPClient] = [:]  // keyed by serverKey
    private var documentVersions: [String: Int] = [:]  // keyed by URI
    private var documentLanguages: [String: String] = [:]  // keyed by URI -> language
    private var currentRootURI: String?
    private var debounceTimers: [String: Task<Void, Never>] = [:]  // keyed by URI
    private var serverStartTasks: [String: Task<Void, Never>] = [:]  // keyed by serverKey

    private init() {}

    // MARK: - Testable init

    init(forTesting: Bool) {}

    // MARK: - Project Root

    func setProjectRoot(_ url: URL?) {
        let newRootURI = url?.absoluteString

        if newRootURI == currentRootURI { return }

        // Shutdown old servers if root changed
        if currentRootURI != nil {
            Task { await shutdownAll() }
        }

        currentRootURI = newRootURI
        diagnosticsByURI.removeAll()
        documentVersions.removeAll()
        documentLanguages.removeAll()
    }

    // MARK: - Document Sync

    func documentOpened(uri: String, language: String, text: String) {
        guard currentRootURI != nil else { return }
        guard language != "plaintext" else { return }

        documentVersions[uri] = 0
        documentLanguages[uri] = language

        let version = 0

        Task {
            let client = await ensureClient(for: language)
            await client?.didOpenDocument(uri: uri, languageId: language, version: version, text: text)
        }
    }

    func documentChanged(uri: String, language: String, text: String) {
        guard currentRootURI != nil else { return }
        guard language != "plaintext" else { return }

        let version = (documentVersions[uri] ?? 0) + 1
        documentVersions[uri] = version

        // Adaptive debounce: longer for larger files
        debounceTimers[uri]?.cancel()
        let delay: UInt64
        if text.count > 100000 {
            delay = 1_000_000_000  // 1 second for huge files
        } else if text.count > 10000 {
            delay = 500_000_000    // 500ms for large files
        } else {
            delay = 300_000_000    // 300ms for normal files
        }
        
        debounceTimers[uri] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            guard let self else { return }
            let client = await self.ensureClient(for: language)
            await client?.didChangeDocument(uri: uri, version: version, text: text)
        }
    }

    func documentClosed(uri: String, language: String) {
        guard language != "plaintext" else { return }

        debounceTimers[uri]?.cancel()
        debounceTimers.removeValue(forKey: uri)
        documentVersions.removeValue(forKey: uri)
        documentLanguages.removeValue(forKey: uri)
        diagnosticsByURI.removeValue(forKey: uri)

        Task {
            let client = existingClient(for: language)
            await client?.didCloseDocument(uri: uri)
        }
    }

    func documentSaved(uri: String, language: String) {
        guard language != "plaintext" else { return }

        Task {
            let client = existingClient(for: language)
            await client?.didSaveDocument(uri: uri)
        }
    }

    // MARK: - Diagnostics

    func diagnostics(for uri: String) -> [LSPDiagnostic] {
        diagnosticsByURI[uri] ?? []
    }

    func diagnosticCount(for uri: String) -> (errors: Int, warnings: Int) {
        let diags = diagnostics(for: uri)
        let errors = diags.filter { $0.severity == .error }.count
        let warnings = diags.filter { $0.severity == .warning }.count
        return (errors, warnings)
    }

    // MARK: - Feature Requests

    func completion(uri: String, language: String, position: LSPPosition) async -> [CompletionItem] {
        guard let client = existingClient(for: language) else { return [] }
        do {
            let list = try await client.completion(uri: uri, position: position)
            return list.items
        } catch {
            return []
        }
    }

    func hover(uri: String, language: String, position: LSPPosition) async -> HoverResult? {
        guard let client = existingClient(for: language) else { return nil }
        return try? await client.hover(uri: uri, position: position)
    }

    func definition(uri: String, language: String, position: LSPPosition) async -> [LSPLocation] {
        guard let client = existingClient(for: language) else { return [] }
        return (try? await client.definition(uri: uri, position: position)) ?? []
    }

    func references(uri: String, language: String, position: LSPPosition) async -> [LSPLocation] {
        guard let client = existingClient(for: language) else { return [] }
        return (try? await client.references(uri: uri, position: position, includeDeclaration: false)) ?? []
    }

    // MARK: - Server Status

    func serverAvailable(for language: String) -> Bool {
        guard let config = LSPServerRegistry.configFor(language: language) else { return false }
        if case .ready = serverStatus[config.serverKey] { return true }
        return false
    }

    func injectDiagnosticsForTesting(uri: String, diagnostics: [LSPDiagnostic]) {
        diagnosticsByURI[uri] = diagnostics
    }

    // MARK: - Shutdown

    func shutdownAll() async {
        for (_, task) in serverStartTasks {
            task.cancel()
        }
        serverStartTasks.removeAll()

        for (_, task) in debounceTimers {
            task.cancel()
        }
        debounceTimers.removeAll()

        for (_, client) in clients {
            await client.shutdown()
        }
        clients.removeAll()
        serverStatus.removeAll()
    }

    // MARK: - Client Management

    private func ensureClient(for language: String) async -> LSPClient? {
        guard let config = LSPServerRegistry.configFor(language: language) else { return nil }
        let serverKey = config.serverKey

        // Return existing client if already running
        if let existing = clients[serverKey] {
            return existing
        }

        // Don't try to start if we already know it's unavailable
        if case .unavailable = serverStatus[serverKey] { return nil }
        if case .failed = serverStatus[serverKey] { return nil }

        // Start server
        return await startServer(config: config)
    }

    private func existingClient(for language: String) -> LSPClient? {
        guard let config = LSPServerRegistry.configFor(language: language) else { return nil }
        return clients[config.serverKey]
    }

    private func startServer(config: LSPServerConfig) async -> LSPClient? {
        let serverKey = config.serverKey

        // Resolve server binary path
        guard let serverPath = LSPServerRegistry.resolveServerPath(for: config) else {
            serverStatus[serverKey] = .unavailable
            return nil
        }

        guard let rootURI = currentRootURI else { return nil }

        serverStatus[serverKey] = .starting

        do {
            let client = try LSPClient.spawn(
                language: config.languageId,
                serverConfig: config,
                serverPath: serverPath,
                rootURI: rootURI
            )

            // Set up diagnostics callback
            let weakSelf = Weak(self)
            await client.setOnDiagnostics { [weakSelf] uri, diagnostics in
                Task { @MainActor in
                    weakSelf.value?.handleDiagnostics(uri: uri, diagnostics: diagnostics)
                }
            }

            try await client.start()

            clients[serverKey] = client
            serverStatus[serverKey] = .ready
            return client
        } catch {
            serverStatus[serverKey] = .failed(error.localizedDescription)
            return nil
        }
    }

    private func handleDiagnostics(uri: String, diagnostics: [LSPDiagnostic]) {
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 100_000_000)
            guard let self = self else { return }
            await MainActor.run {
                self.diagnosticsByURI[uri] = diagnostics
            }
        }
    }
}

// MARK: - Weak reference wrapper (for use in Sendable closures)

private final class Weak<T: AnyObject>: @unchecked Sendable {
    weak var value: T?
    init(_ value: T) { self.value = value }
}

// MARK: - Mock LSP Service (for testing)

@MainActor
final class MockLSPService: LSPServiceProtocol, ObservableObject {
    @Published private(set) var diagnosticsByURI: [String: [LSPDiagnostic]] = [:]
    @Published private(set) var serverStatus: [String: LSPServerStatus] = [:]

    private(set) var documentOpenedCalls: [(uri: String, language: String, text: String)] = []
    private(set) var documentChangedCalls: [(uri: String, language: String, text: String)] = []
    private(set) var documentClosedCalls: [(uri: String, language: String)] = []
    private(set) var documentSavedCalls: [(uri: String, language: String)] = []
    private(set) var projectRootCalls: [URL?] = []
    private(set) var referenceResultsByURI: [String: [LSPLocation]] = [:]
    private(set) var referencesCalls: [(uri: String, language: String, position: LSPPosition)] = []

    func setProjectRoot(_ url: URL?) {
        projectRootCalls.append(url)
    }

    func documentOpened(uri: String, language: String, text: String) {
        documentOpenedCalls.append((uri, language, text))
    }

    func documentChanged(uri: String, language: String, text: String) {
        documentChangedCalls.append((uri, language, text))
    }

    func documentClosed(uri: String, language: String) {
        documentClosedCalls.append((uri, language))
    }

    func documentSaved(uri: String, language: String) {
        documentSavedCalls.append((uri, language))
    }

    func diagnostics(for uri: String) -> [LSPDiagnostic] {
        diagnosticsByURI[uri] ?? []
    }

    func diagnosticCount(for uri: String) -> (errors: Int, warnings: Int) {
        let diags = diagnostics(for: uri)
        return (
            diags.filter { $0.severity == .error }.count,
            diags.filter { $0.severity == .warning }.count
        )
    }

    func completion(uri: String, language: String, position: LSPPosition) async -> [CompletionItem] { [] }
    func hover(uri: String, language: String, position: LSPPosition) async -> HoverResult? { nil }
    func definition(uri: String, language: String, position: LSPPosition) async -> [LSPLocation] { [] }
    func references(uri: String, language: String, position: LSPPosition) async -> [LSPLocation] {
        referencesCalls.append((uri, language, position))
        return referenceResultsByURI[uri] ?? []
    }

    func serverAvailable(for language: String) -> Bool {
        if case .ready = serverStatus[language] { return true }
        return false
    }

    func injectDiagnosticsForTesting(uri: String, diagnostics: [LSPDiagnostic]) {
        diagnosticsByURI[uri] = diagnostics
    }

    func shutdownAll() async {}

    // Test helpers
    func setDiagnostics(uri: String, diagnostics: [LSPDiagnostic]) {
        diagnosticsByURI[uri] = diagnostics
    }

    func setReferences(uri: String, locations: [LSPLocation]) {
        referenceResultsByURI[uri] = locations
    }

    func setServerStatus(language: String, status: LSPServerStatus) {
        serverStatus[language] = status
    }
}
