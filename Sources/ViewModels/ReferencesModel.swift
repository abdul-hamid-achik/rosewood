import Foundation

/// Holds "Find References" results, extracted from ProjectViewModel so the references panel
/// observes only this model. The building/navigation logic stays on ProjectViewModel (it
/// couples to file I/O, the editor, and the shared bottom panel) and writes results here.
@MainActor
final class ReferencesModel: ObservableObject {
    @Published var referenceResults: [ReferenceResult] = []
    /// True while a Find References request is in flight, so the panel can show a spinner
    /// immediately instead of appearing to do nothing until the language server responds.
    @Published var isSearching: Bool = false
}
