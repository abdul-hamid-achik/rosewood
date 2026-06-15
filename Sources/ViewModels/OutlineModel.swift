import Foundation

/// Drives outline-sidebar refreshes without re-rendering the whole app. The current-file symbol
/// index is rebuilt off-main on a debounce after edits; that result previously nudged observers via
/// `ProjectViewModel.objectWillChange.send()`, re-rendering EVERY view ~4×/sec while typing just to
/// update the outline. The view model now bumps this child instead, so only OutlineSidebarView
/// (which observes it) re-renders and re-reads `currentFileSymbols`.
@MainActor
final class OutlineModel: ObservableObject {
    /// Bumped whenever the current file's symbol index changes; observers re-read the symbols.
    @Published var revision: Int = 0
}
