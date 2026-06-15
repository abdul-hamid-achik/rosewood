import Foundation

/// Holds git display state extracted from ProjectViewModel so a git update re-renders only the git
/// consumers (e.g. the status-bar blame chip) instead of every view observing the app-wide view
/// model. The git OPERATIONS (refresh/blame/diff/stage) stay on ProjectViewModel as drivers and
/// write their results into this model — mirroring the ReferencesModel/DiagnosticsModel cuts.
///
/// First extracted member: `currentLineBlame`, which refreshes on every caret line change (debounced
/// `git blame`); keeping it on the view model made line navigation re-render the whole app.
@MainActor
final class GitModel: ObservableObject {
    @Published var currentLineBlame: GitBlameInfo?
}
