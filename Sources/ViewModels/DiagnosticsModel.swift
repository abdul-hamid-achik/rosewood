import Foundation

/// Owns diagnostics selection/scope state and the derived diagnostic views, extracted from
/// ProjectViewModel so an LSP diagnostics push (frequent while typing/compiling) re-renders only
/// the diagnostics consumers (editor gutter, status bar, problems panel) instead of every view
/// observing the app-wide view model.
///
/// The diagnostic DATA lives in LSPService. This model reads it via the injected `lspService`,
/// owns the LSP diagnostics-change handler, and learns the active document/cursor from context
/// the view model PUSHES in (it holds no back-reference to ProjectViewModel — avoiding a cycle).
/// File-system/path helpers are supplied as closures for the same reason.
@MainActor
final class DiagnosticsModel: ObservableObject {
    enum DiagnosticsPanelScope {
        case currentFile
        case workspace
    }

    private let lspService: LSPServiceProtocol
    private let normalize: (URL) -> String
    private let displayPathProvider: (URL) -> String
    private let lineProvider: (URL, Int) -> String

    init(
        lspService: LSPServiceProtocol,
        normalize: @escaping (URL) -> String,
        displayPathProvider: @escaping (URL) -> String,
        lineProvider: @escaping (URL, Int) -> String
    ) {
        self.lspService = lspService
        self.normalize = normalize
        self.displayPathProvider = displayPathProvider
        self.lineProvider = lineProvider
    }
}
