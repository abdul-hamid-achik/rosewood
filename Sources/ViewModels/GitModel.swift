import Foundation

/// Holds git display state extracted from ProjectViewModel so a git update re-renders only the git
/// consumers (status bar, source-control sidebar, diff panel, file-tree decorations) instead of every
/// view observing the app-wide view model. The git OPERATIONS (refresh/blame/diff/stage) stay on
/// ProjectViewModel as drivers and write their results into this model — mirroring the
/// ReferencesModel/DiagnosticsModel cuts.
///
/// `currentLineBlame` was the first member (line-navigation blame). Stage 2 adds the git status/diff
/// display cluster + its derived caches, so a save-triggered `refreshGitState()` (autosave is on by
/// default) re-renders only git consumers, not the whole app.
@MainActor
final class GitModel: ObservableObject {
    @Published var currentLineBlame: GitBlameInfo?

    /// The whole-repository status. Its didSet rebuilds the derived lookup caches (moved here with it
    /// so the trigger is preserved automatically once drivers write through the view model forwarder).
    @Published var gitRepositoryStatus: GitRepositoryStatus = .empty {
        didSet {
            rebuildGitCaches()
        }
    }
    @Published var selectedGitDiff: GitDiffResult?
    @Published var selectedGitDiffPath: String?
    /// True when the selected change's diff couldn't be loaded (vs. a legitimate empty diff),
    /// so the diff panel can show a real error state instead of "No diff available".
    @Published var gitDiffLoadFailed: Bool = false
    /// Draft commit message bound to the Source Control commit box; cleared after a successful commit.
    @Published var commitMessage: String = ""
    @Published var isRefreshingGitStatus: Bool = false
    @Published var isLoadingGitDiff: Bool = false
    @Published var isGitToolAvailable: Bool = true

    // Derived caches (NON-@Published; read through the methods below, never observed directly).
    private var gitChangedFileByPath: [String: GitChangedFile] = [:]
    private var gitChangedDescendantCountByDirectoryPath: [String: Int] = [:]
    private var gitChangeIndexByPath: [String: Int] = [:]
    private var cachedGitChangeSections: [GitChangeSectionGroup] = []
    private var ignoredPathSet: Set<String> = []

    var gitChangeSections: [GitChangeSectionGroup] {
        cachedGitChangeSections
    }

    func gitChangeIndex(for changedFile: GitChangedFile) -> Int {
        gitChangeIndexByPath[changedFile.path] ?? 0
    }

    /// Cache lookups keyed by an ALREADY-RESOLVED repository-relative path. The FileItem→relative-path
    /// resolution stays on the view model (it needs the repository root + path normalization); these
    /// just do the pure dictionary lookups against the caches that live here.
    func gitChange(forRelativePath relativePath: String) -> GitChangedFile? {
        gitChangedFileByPath[relativePath]
    }

    func gitChangedDescendantCount(forRelativePath relativePath: String) -> Int {
        gitChangedDescendantCountByDirectoryPath[relativePath] ?? 0
    }

    func isGitIgnored(relativePath: String) -> Bool {
        if ignoredPathSet.contains(relativePath) { return true }
        var current = relativePath
        while let lastSlash = current.lastIndex(of: "/") {
            current = String(current[current.startIndex..<lastSlash])
            if ignoredPathSet.contains(current) { return true }
        }
        return false
    }

    private func rebuildGitCaches() {
        gitChangedFileByPath = Dictionary(uniqueKeysWithValues: gitRepositoryStatus.changedFiles.map { ($0.path, $0) })
        gitChangeIndexByPath = Dictionary(uniqueKeysWithValues: gitRepositoryStatus.changedFiles.enumerated().map { ($0.element.path, $0.offset) })
        ignoredPathSet = Set(gitRepositoryStatus.ignoredPaths.map { ignoredPath in
            ignoredPath.hasSuffix("/") ? String(ignoredPath.dropLast()) : ignoredPath
        })
        cachedGitChangeSections = GitChangeSection.allCases.compactMap { section in
            let files = gitRepositoryStatus.changedFiles.filter { $0.section == section }
            guard !files.isEmpty else { return nil }
            return GitChangeSectionGroup(section: section, files: files)
        }

        var descendantCounts: [String: Int] = [:]
        for changedFile in gitRepositoryStatus.changedFiles {
            let components = changedFile.path.split(separator: "/").map(String.init)
            guard components.count > 1 else { continue }

            var currentPath = ""
            for component in components.dropLast() {
                currentPath = currentPath.isEmpty ? component : currentPath + "/" + component
                descendantCounts[currentPath, default: 0] += 1
            }
        }
        gitChangedDescendantCountByDirectoryPath = descendantCounts
    }
}
