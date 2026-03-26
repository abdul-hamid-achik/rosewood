import Foundation
import SwiftUI
import Combine

struct ProjectViewModelUI {
    var openPanel: (_ canChooseDirectories: Bool, _ canChooseFiles: Bool, _ allowsMultipleSelection: Bool) -> URL?
    var alert: (_ title: String, _ message: String, _ style: NSAlert.Style) -> Void
    var confirm: (_ title: String, _ message: String, _ style: NSAlert.Style, _ buttons: [String]) -> NSApplication.ModalResponse

    static let live = ProjectViewModelUI(
        openPanel: { canChooseDirectories, canChooseFiles, allowsMultipleSelection in
            Extensions.openPanel(
                canChooseDirectories: canChooseDirectories,
                canChooseFiles: canChooseFiles,
                allowsMultipleSelection: allowsMultipleSelection
            )
        },
        alert: { title, message, style in
            Extensions.alert(title: title, message: message, style: style)
        },
        confirm: { title, message, style, buttons in
            Extensions.confirm(title: title, message: message, style: style, buttons: buttons)
        }
    )
}

struct ProjectReplacePreviewFile: Identifiable, Hashable {
    let fileURL: URL
    let fileName: String
    let displayPath: String
    let matchCount: Int

    var id: String {
        fileURL.standardizedFileURL.path
    }
}

struct ProjectReplacePreview: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let summary: String
    let searchQuery: String
    let searchOptions: ProjectSearchOptions
    let replacement: String
    let results: [ProjectSearchResult]
    let files: [ProjectReplacePreviewFile]

    var matchCount: Int {
        results.reduce(0) { partialResult, result in
            partialResult + result.matchCount
        }
    }

    var affectedFileURLs: [URL] {
        files.map(\.fileURL)
    }
}

struct ProjectReplaceFileSnapshot: Hashable {
    let fileURL: URL
    let originalContent: String
}

struct ProjectReplaceTransaction: Identifiable, Hashable {
    let id = UUID()
    let summary: String
    let searchQuery: String
    let replacement: String
    let replacementCount: Int
    let fileSnapshots: [ProjectReplaceFileSnapshot]

    var fileCount: Int {
        fileSnapshots.count
    }

    var affectedFileURLs: [URL] {
        fileSnapshots.map(\.fileURL)
    }
}

struct WorkspaceDiagnosticItem: Identifiable, Hashable {
    let fileURL: URL
    let displayPath: String
    let lineText: String
    let diagnostic: LSPDiagnostic

    var id: String {
        "\(fileURL.standardizedFileURL.path)|\(diagnostic.id)"
    }

    var lineNumber: Int {
        diagnostic.range.start.line + 1
    }

    var columnNumber: Int {
        diagnostic.range.start.character + 1
    }

    static func == (lhs: WorkspaceDiagnosticItem, rhs: WorkspaceDiagnosticItem) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

enum NavigableProblem {
    case current(LSPDiagnostic)
    case workspace(WorkspaceDiagnosticItem)
}

@MainActor
final class ProjectViewModel: ObservableObject {
    enum SidebarMode {
        case explorer
        case search
        case sourceControl
        case debug
        case docker
    }

    enum PaletteMode {
        case quickOpen
        case commandPalette
    }

    enum BottomPanelKind {
        case debugConsole
        case diagnostics
        case references
        case gitDiff
        case terminal
        case dockerLogs
    }

    enum DiagnosticsPanelScope {
        case currentFile
        case workspace
    }

    @Published var rootDirectory: URL?
    @Published var fileTree: [FileItem] = []
    @Published var openTabs: [EditorTab] = []
    @Published var selectedTabIndex: Int? = nil {
        didSet {
            refreshCurrentLineBlame()
            synchronizeActiveDiagnosticSelection()
        }
    }
    @Published private(set) var activePalette: PaletteMode?
    @Published var showNewFileSheet: Bool = false
    @Published var showNewFolderSheet: Bool = false
    @Published var renameItem: FileItem? = nil
    @Published var commandPaletteQuery: String = ""
    @Published var quickOpenQuery: String = ""
    @Published var pendingNewItemDirectory: URL? = nil
    @Published var sidebarMode: SidebarMode = .explorer {
        didSet {
            handleSidebarModeChange(from: oldValue)
        }
    }
    @Published var projectSearchQuery: String = "" {
        didSet {
            handleProjectSearchQueryChange(from: oldValue)
        }
    }
    @Published var projectReplaceQuery: String = "" {
        didSet {
            handleProjectReplaceQueryChange(from: oldValue)
        }
    }
    @Published var projectSearchCaseSensitive: Bool = false {
        didSet {
            handleProjectSearchOptionsChange(from: oldValue, to: projectSearchCaseSensitive)
        }
    }
    @Published var projectSearchWholeWord: Bool = false {
        didSet {
            handleProjectSearchOptionsChange(from: oldValue, to: projectSearchWholeWord)
        }
    }
    @Published var projectSearchUseRegex: Bool = false {
        didSet {
            handleProjectSearchOptionsChange(from: oldValue, to: projectSearchUseRegex)
        }
    }
    @Published var projectSearchIncludeGlob: String = "" {
        didSet {
            handleProjectSearchFilterChange(from: oldValue, to: projectSearchIncludeGlob)
        }
    }
    @Published var projectSearchExcludeGlob: String = "" {
        didSet {
            handleProjectSearchFilterChange(from: oldValue, to: projectSearchExcludeGlob)
        }
    }
    @Published var showHiddenFiles: Bool = false {
        didSet {
            handleShowHiddenFilesChange(from: oldValue)
        }
    }
    @Published var projectSearchResults: [ProjectSearchResult] = []
    @Published var activeProjectSearchResultID: String?
    @Published var collapsedProjectSearchGroupIDs: Set<String> = []
    @Published var selectedProjectSearchResultIDs: Set<String> = []
    @Published var projectReplacePreview: ProjectReplacePreview?
    @Published var lastProjectReplaceTransaction: ProjectReplaceTransaction?
    @Published var showSettings: Bool = false
    @Published private(set) var editorVisibleLineRange: ClosedRange<Int>?
    @Published var debugConfigurations: [DebugConfiguration] = []
    @Published var selectedDebugConfigurationName: String?
    @Published var debugConfigurationError: String?
    @Published var bottomPanel: BottomPanelKind?
    @Published private(set) var isLoadingFileTree: Bool = false
    @Published var isLoadingFile: Bool = false
    @Published var loadingFileProgress: Double?
    @Published var isSearchingProject: Bool = false
    @Published var isReplacingInProject: Bool = false
    @Published var breakpoints: [Breakpoint] = []
    @Published var debugSessionState: DebugSessionState = .idle
    @Published var debugConsoleEntries: [DebugConsoleEntry] = []
    @Published var debugStoppedFilePath: String?
    @Published var debugStoppedLine: Int?
    @Published var referenceResults: [ReferenceResult] = []
    @Published var gitRepositoryStatus: GitRepositoryStatus = .empty
    @Published var selectedGitDiff: GitDiffResult?
    @Published var selectedGitDiffPath: String?
    @Published var isGitDiffWorkspaceVisible: Bool = false
    @Published var currentLineBlame: GitBlameInfo?
    @Published var isRefreshingGitStatus: Bool = false
    @Published var isLoadingGitDiff: Bool = false
    @Published var activeCurrentDiagnosticID: String?
    @Published var activeWorkspaceDiagnosticID: String?
    @Published var diagnosticsPanelScope: DiagnosticsPanelScope = .currentFile
    
    // MARK: - Docker State
    @Published var dockerContainers: [DockerContainer] = []
    @Published var dockerImages: [DockerImage] = []
    @Published var dockerVolumes: [DockerVolume] = []
    @Published var dockerComposeProjects: [DockerComposeProject] = []
    @Published var dockerConnectionState: DockerConnectionState = .connecting
    @Published var isRefreshingDocker: Bool = false
    @Published var selectedDockerTab: DockerTab = .containers
    @Published var selectedContainer: DockerContainer?
    @Published var showDockerSettings: Bool = false
    
    // MARK: - Terminal State
    @Published var terminalSessions: [TerminalSession] = []
    @Published var currentTerminalSessionId: UUID?
    
    private var recentCommandPaletteActionIDs: [String] = []

    var currentTabDiagnostics: [LSPDiagnostic] {
        guard let uri = selectedTab?.documentURI else { return [] }
        return lspService.diagnostics(for: uri)
    }

    var currentTabDiagnosticCount: (errors: Int, warnings: Int) {
        guard let uri = selectedTab?.documentURI else { return (0, 0) }
        return lspService.diagnosticCount(for: uri)
    }

    var orderedCurrentTabDiagnostics: [LSPDiagnostic] {
        sortedCurrentDiagnostics()
    }

    var activeCurrentDiagnostic: LSPDiagnostic? {
        let diagnostics = orderedCurrentTabDiagnostics
        guard !diagnostics.isEmpty else { return nil }

        if let activeCurrentDiagnosticID,
           let diagnostic = diagnostics.first(where: { $0.id == activeCurrentDiagnosticID }) {
            return diagnostic
        }

        return inferredCurrentDiagnostic(in: diagnostics)
    }

    var activeCurrentDiagnosticIndex: Int? {
        guard let activeCurrentDiagnostic else { return nil }
        return orderedCurrentTabDiagnostics.firstIndex(of: activeCurrentDiagnostic)
    }

    var currentProblemPositionText: String? {
        switch diagnosticsPanelScope {
        case .currentFile:
            guard let activeCurrentDiagnosticIndex else { return nil }
            let total = orderedCurrentTabDiagnostics.count
            return "Problem \(activeCurrentDiagnosticIndex + 1) of \(total)"
        case .workspace:
            guard let activeWorkspaceDiagnosticIndex else { return nil }
            let total = orderedWorkspaceDiagnostics.count
            return "Problem \(activeWorkspaceDiagnosticIndex + 1) of \(total)"
        }
    }

    var workspaceDiagnosticCount: (errors: Int, warnings: Int) {
        orderedWorkspaceDiagnostics.reduce(into: (errors: 0, warnings: 0)) { partialResult, item in
            switch item.diagnostic.severity {
            case .error:
                partialResult.errors += 1
            case .warning:
                partialResult.warnings += 1
            default:
                break
            }
        }
    }

    var workspaceDiagnosticFileCount: Int {
        Set(orderedWorkspaceDiagnostics.map { normalizedPath(for: $0.fileURL) }).count
    }

    var canNavigateCurrentProblems: Bool {
        !currentTabDiagnostics.isEmpty
    }

    var hasWorkspaceDiagnostics: Bool {
        !orderedWorkspaceDiagnostics.isEmpty
    }

    var canNavigateProblems: Bool {
        switch diagnosticsPanelScope {
        case .currentFile:
            return canNavigateCurrentProblems
        case .workspace:
            return hasWorkspaceDiagnostics
        }
    }

    var canShowProblemsPanel: Bool {
        hasOpenFile || hasWorkspaceDiagnostics
    }

    var orderedWorkspaceDiagnostics: [WorkspaceDiagnosticItem] {
        lspService.diagnosticsByURI
            .compactMap { uri, diagnostics -> [WorkspaceDiagnosticItem]? in
                guard let fileURL = URL(string: uri), fileURL.isFileURL else { return nil }
                return diagnostics.map { diagnostic in
                    WorkspaceDiagnosticItem(
                        fileURL: fileURL,
                        displayPath: relativeDisplayPath(for: fileURL),
                        lineText: lineText(for: fileURL, lineNumber: diagnostic.range.start.line + 1),
                        diagnostic: diagnostic
                    )
                }
            }
            .flatMap { $0 }
            .sorted(by: compareWorkspaceDiagnostics)
    }

    var activeWorkspaceDiagnostic: WorkspaceDiagnosticItem? {
        let diagnostics = orderedWorkspaceDiagnostics
        guard !diagnostics.isEmpty else { return nil }

        if let activeWorkspaceDiagnosticID,
           let diagnostic = diagnostics.first(where: { $0.id == activeWorkspaceDiagnosticID }) {
            return diagnostic
        }

        return inferredWorkspaceDiagnostic(in: diagnostics)
    }

    var activeWorkspaceDiagnosticIndex: Int? {
        guard let activeWorkspaceDiagnostic else { return nil }
        return orderedWorkspaceDiagnostics.firstIndex(of: activeWorkspaceDiagnostic)
    }

    var activeProblemScrollID: String? {
        switch diagnosticsPanelScope {
        case .currentFile:
            return activeCurrentDiagnostic?.id
        case .workspace:
            return activeWorkspaceDiagnostic?.id
        }
    }

    var selectedDebugConfiguration: DebugConfiguration? {
        guard let selectedDebugConfigurationName else { return nil }
        return debugConfigurations.first { $0.name == selectedDebugConfigurationName }
    }

    var currentTabBreakpointLines: Set<Int> {
        guard let filePath = selectedTab?.filePath.map(normalizedPath(for:)) else { return [] }
        return Set(
            breakpoints
                .filter { $0.filePath == filePath && $0.isEnabled }
                .map(\.line)
        )
    }

    var currentExecutionLine: Int? {
        guard let filePath = selectedTab?.filePath.map(normalizedPath(for:)),
              filePath == debugStoppedFilePath else {
            return nil
        }
        return debugStoppedLine
    }

    var canNavigateBreakpoints: Bool {
        !breakpoints.isEmpty
    }

    var hasCurrentDebugStopLocation: Bool {
        debugStoppedFilePath != nil && debugStoppedLine != nil
    }

    var canOpenCurrentDebugStopLocation: Bool {
        hasCurrentDebugStopLocation
    }

    var isDebugPanelVisible: Bool {
        bottomPanel == .debugConsole
    }

    var isDiagnosticsPanelVisible: Bool {
        bottomPanel == .diagnostics
    }

    var isReferencesPanelVisible: Bool {
        bottomPanel == .references
    }

    var isGitDiffPanelVisible: Bool {
        bottomPanel == .gitDiff
    }

    var isGitDiffVisible: Bool {
        isGitDiffWorkspaceVisible || isGitDiffPanelVisible
    }

    var selectedGitChangedFile: GitChangedFile? {
        guard let selectedGitDiffPath else { return nil }
        return gitRepositoryStatus.changedFiles.first { $0.path == selectedGitDiffPath }
    }

    var selectedGitChangeIndex: Int? {
        guard let selectedGitChangedFile else { return nil }
        return gitRepositoryStatus.changedFiles.firstIndex(of: selectedGitChangedFile)
    }

    var selectedGitChangePositionText: String? {
        guard let selectedGitChangeIndex else { return nil }
        return "Change \(selectedGitChangeIndex + 1) of \(gitRepositoryStatus.changedFiles.count)"
    }

    var canShowPreviousGitChange: Bool {
        guard let selectedGitChangeIndex else { return false }
        return selectedGitChangeIndex > 0
    }

    var canShowNextGitChange: Bool {
        guard let selectedGitChangeIndex else { return false }
        return selectedGitChangeIndex < gitRepositoryStatus.changedFiles.count - 1
    }

    var selectedGitChangeReviewLabel: String? {
        guard isGitDiffWorkspaceVisible,
              let changedFile = selectedGitChangedFile,
              let selectedGitChangeIndex else {
            return nil
        }
        return "Reviewing \(changedFile.kind.displayName) \(selectedGitChangeIndex + 1)/\(gitRepositoryStatus.changedFiles.count)"
    }

    var canFindReferences: Bool {
        guard let selectedTab,
              selectedTab.documentURI != nil,
              selectedTab.language != "plaintext" else {
            return false
        }
        return lspService.serverAvailable(for: selectedTab.language)
    }

    var debugPrimaryActionTitle: String {
        switch debugSessionState {
        case .starting:
            return "Starting..."
        case .running, .paused, .stopping:
            return "Restart"
        case .idle, .failed:
            return "Start"
        }
    }

    var hasOpenFile: Bool {
        selectedTab != nil
    }

    var canAccessDebugControls: Bool {
        rootDirectory != nil && hasOpenFile
    }

    var canStartDebugging: Bool {
        canAccessDebugControls && !debugSessionState.isBusy
    }

    var canStopDebugging: Bool {
        canAccessDebugControls && debugSessionState != .idle
    }

    var hasProjectConfigFile: Bool {
        configService.hasProjectConfig()
    }

    func gitChange(for item: FileItem) -> GitChangedFile? {
        guard !item.isDirectory,
              let relativePath = gitRelativePath(for: item.path) else {
            return nil
        }
        return gitRepositoryStatus.changedFiles.first { $0.path == relativePath }
    }

    func gitChangedDescendantCount(for item: FileItem) -> Int {
        guard item.isDirectory,
              let relativePath = gitRelativePath(for: item.path) else {
            return gitChange(for: item) == nil ? 0 : 1
        }

        let prefix = relativePath + "/"
        return gitRepositoryStatus.changedFiles.reduce(into: 0) { count, changedFile in
            if changedFile.path.hasPrefix(prefix) {
                count += 1
            }
        }
    }

    func isGitIgnored(_ item: FileItem) -> Bool {
        guard let relativePath = gitRelativePath(for: item.path) else {
            return false
        }

        for ignoredPath in normalizedIgnoredGitPaths {
            if relativePath == ignoredPath || relativePath.hasPrefix(ignoredPath + "/") {
                return true
            }
        }

        return false
    }

    let fileService: FileService
    let sessionStore: UserDefaults
    private let sessionKey: String
    private let projectConfigPromptedRootsKey: String
    let debugSelectedConfigurationsKey: String
    let debugPanelVisibilityKey: String
    var expandedDirectoryPaths: Set<String> = []
    private var autoSaveTask: Task<Void, Never>?
    private var reloadFileTreeTask: Task<Void, Never>?
    var projectSearchTask: Task<Void, Never>?
    var projectSearchDebounceTask: Task<Void, Never>?
    var replaceInProjectTask: Task<Void, Never>?
    let configService: ConfigurationService
    let fileWatcher: FileWatcherService
    private let notificationCenter: NotificationCenter
    private let commandDispatcher: AppCommandDispatcher
    let ui: ProjectViewModelUI
    let lspService: LSPServiceProtocol
    let breakpointStore: BreakpointStore
    let debugConfigurationService: DebugConfigurationService
    let debugSessionService: DebugSessionServiceProtocol
    let gitService: GitServiceProtocol
    private var settingsCommandCancellable: AnyCancellable?
    private var fileTreeLoadToken = UUID()
    var projectSearchToken = UUID()
    var replaceInProjectToken = UUID()
    var projectSearchResultsQuery = ""
    var projectSearchResultsOptions = ProjectSearchOptions()
    var gitStatusTask: Task<Void, Never>?
    var gitDiffTask: Task<Void, Never>?
    var gitBlameTask: Task<Void, Never>?
    var gitStatusToken = UUID()
    var gitDiffToken = UUID()
    var gitBlameToken = UUID()
    let projectSearchDebounceNanoseconds: UInt64
    private var quickOpenAccessSequence = 0
    private var quickOpenRecentAccessByPath: [String: Int] = [:]
    var cachedWorkspaceSymbols: [WorkspaceSymbolMatch]?
    var cachedWorkspaceSymbolRootPath: String?
    convenience init() {
        self.init(
            fileService: .shared,
            sessionStore: .standard,
            sessionKey: "rosewood.session",
            configService: .shared,
            fileWatcher: .shared,
            notificationCenter: .default,
            commandDispatcher: .shared,
            ui: .live,
            lspService: LSPService.shared,
            breakpointStore: BreakpointStore(),
            debugConfigurationService: DebugConfigurationService(),
            debugSessionService: DebugSessionService.shared,
            gitService: GitService.shared
        )
    }

    init(
        fileService: FileService,
        sessionStore: UserDefaults,
        sessionKey: String,
        configService: ConfigurationService,
        fileWatcher: FileWatcherService,
        notificationCenter: NotificationCenter,
        commandDispatcher: AppCommandDispatcher = .shared,
        ui: ProjectViewModelUI,
        lspService: LSPServiceProtocol? = nil,
        breakpointStore: BreakpointStore = BreakpointStore(),
        debugConfigurationService: DebugConfigurationService = DebugConfigurationService(),
        debugSessionService: DebugSessionServiceProtocol? = nil,
        gitService: GitServiceProtocol = GitService.shared,
        projectSearchDebounceNanoseconds: UInt64 = 250_000_000
    ) {
        self.fileService = fileService
        self.sessionStore = sessionStore
        self.sessionKey = sessionKey
        self.projectConfigPromptedRootsKey = "\(sessionKey).projectConfigPromptedRoots"
        self.debugSelectedConfigurationsKey = "\(sessionKey).debugSelectedConfigurations"
        self.debugPanelVisibilityKey = "\(sessionKey).debugPanelVisible"
        self.configService = configService
        self.fileWatcher = fileWatcher
        self.notificationCenter = notificationCenter
        self.commandDispatcher = commandDispatcher
        self.ui = ui
        self.lspService = lspService ?? LSPService.shared
        self.breakpointStore = breakpointStore
        self.debugConfigurationService = debugConfigurationService
        self.debugSessionService = debugSessionService ?? DebugSessionService.shared
        self.gitService = gitService
        self.projectSearchDebounceNanoseconds = projectSearchDebounceNanoseconds
        self.debugSessionService.setEventHandler { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleDebugSessionEvent(event)
            }
        }

        if ProcessInfo.processInfo.environment["ROSEWOOD_UI_TEST_RESET_SESSION"] == "1" {
            sessionStore.removeObject(forKey: sessionKey)
            sessionStore.removeObject(forKey: projectConfigPromptedRootsKey)
            sessionStore.removeObject(forKey: debugSelectedConfigurationsKey)
            sessionStore.removeObject(forKey: debugPanelVisibilityKey)
        }
        setupFileWatcher()
        setupCommandObservers()
        restoreSession()
        reloadDebuggerState(resetConsole: false)
        installUITestEditorFixturesIfNeeded()
        refreshGitState()

        if ProcessInfo.processInfo.environment["ROSEWOOD_UI_TEST_DEBUG_SIDEBAR"] == "1" {
            sidebarMode = .debug
        }
    }

    deinit {
        autoSaveTask?.cancel()
        reloadFileTreeTask?.cancel()
        projectSearchTask?.cancel()
        projectSearchDebounceTask?.cancel()
        replaceInProjectTask?.cancel()
        gitStatusTask?.cancel()
        gitDiffTask?.cancel()
        gitBlameTask?.cancel()
        settingsCommandCancellable?.cancel()
    }

    private func setupFileWatcher() {
        fileWatcher.onExternalFileChange = { [weak self] url in
            Task { @MainActor in
                self?.handleExternalFileChange(at: url)
            }
        }
    }

    private func setupCommandObservers() {
        settingsCommandCancellable = commandDispatcher.publisher
            .filter { $0 == .settings }
            .sink { [weak self] _ in
                self?.showSettings = true
            }
    }

    var selectedTab: EditorTab? {
        guard let index = selectedTabIndex, openTabs.indices.contains(index) else { return nil }
        return openTabs[index]
    }

    var selectedTabEncodingLabel: String? {
        selectedTab?.documentMetadata.encodingLabel
    }

    var selectedTabLineEndingLabel: String? {
        selectedTab?.documentMetadata.lineEnding.label
    }

    var editorStickyScopes: [EditorStickyScopeItem] {
        guard let selectedTab else { return [] }
        let focusLine = editorVisibleLineRange?.lowerBound ?? selectedTab.cursorPosition.line
        return EditorNavigationModel.stickyScopes(
            text: selectedTab.content,
            language: selectedTab.language,
            focusLine: max(focusLine, 1)
        )
    }

    var editorBreadcrumbs: [EditorBreadcrumbSegment] {
        guard let selectedTab else { return [] }
        return EditorNavigationModel.breadcrumbs(
            fileURL: selectedTab.filePath,
            rootURL: rootDirectory,
            text: selectedTab.content,
            language: selectedTab.language,
            visibleTopLine: editorVisibleLineRange?.lowerBound ?? 1,
            cursorLine: selectedTab.cursorPosition.line
        )
    }

    var hasUnsavedChanges: Bool {
        openTabs.contains(where: \.isDirty)
    }

    var showCommandPalette: Bool {
        activePalette == .commandPalette
    }

    var showQuickOpen: Bool {
        activePalette == .quickOpen
    }

    var quickOpenSectionTitle: String {
        quickOpenSections.first?.title ?? "Files"
    }

    var quickOpenHelpText: String? {
        let trimmedQuery = quickOpenQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if let request = quickOpenFileLineRequest(from: trimmedQuery) {
            return "Open the best matching file and jump straight to line \(request.line)."
        }

        if trimmedQuery.hasPrefix(":") {
            return hasOpenFile
                ? "Jump in the current file with :line, like :42."
                : "Open a file first, then jump with :line, like :42."
        }

        if trimmedQuery.hasPrefix("#") {
            let symbolQuery = String(trimmedQuery.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
            return symbolQuery.isEmpty
                ? "Search symbols with #name. Current-file matches are ranked first."
                : "Current-file symbols stay ahead of workspace matches while you type."
        }

        guard trimmedQuery.hasPrefix("!") else { return nil }

        let problemQuery = quickOpenWorkspaceProblemQuery(from: trimmedQuery)
        if problemQuery.searchText.isEmpty {
            return "Use current/workspace and error/warning/info/hint to narrow problems fast."
        }

        return "Filter workspace problems by scope or severity while you type."
    }

    var quickOpenProblemFilterHints: [QuickOpenProblemFilterHint] {
        let trimmedQuery = quickOpenQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedQuery.hasPrefix("!") else { return [] }

        let problemQuery = quickOpenWorkspaceProblemQuery(from: trimmedQuery)

        return [
            QuickOpenProblemFilterHint(
                id: "current",
                token: "current",
                title: "Current",
                isActive: problemQuery.scope == .currentFile,
                kind: .scope(.currentFile)
            ),
            QuickOpenProblemFilterHint(
                id: "workspace",
                token: "workspace",
                title: "Workspace",
                isActive: problemQuery.scope == .workspace,
                kind: .scope(.workspace)
            ),
            QuickOpenProblemFilterHint(
                id: "error",
                token: "error",
                title: "Error",
                isActive: problemQuery.severity == .error,
                kind: .severity(.error)
            ),
            QuickOpenProblemFilterHint(
                id: "warning",
                token: "warning",
                title: "Warning",
                isActive: problemQuery.severity == .warning,
                kind: .severity(.warning)
            ),
            QuickOpenProblemFilterHint(
                id: "info",
                token: "info",
                title: "Info",
                isActive: problemQuery.severity == .information,
                kind: .severity(.information)
            ),
            QuickOpenProblemFilterHint(
                id: "hint",
                token: "hint",
                title: "Hint",
                isActive: problemQuery.severity == .hint,
                kind: .severity(.hint)
            )
        ]
    }

    var quickOpenEmptyStateText: String {
        let trimmedQuery = quickOpenQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedQuery.hasPrefix(":") {
            return hasOpenFile ? "No matching line jump." : "Open a file to jump to a line."
        }
        if trimmedQuery.hasPrefix("!") {
            let problemQuery = quickOpenWorkspaceProblemQuery(from: trimmedQuery)
            return hasWorkspaceDiagnostics
                ? quickOpenWorkspaceProblemEmptyStateText(for: problemQuery)
                : "No workspace problems are available right now."
        }
        if trimmedQuery.hasPrefix("#") {
            return trimmedQuery.count > 1 ? "No matching symbols." : "Type a symbol name after #."
        }
        if quickOpenFileLineRequest(from: trimmedQuery) != nil {
            return "No matching file for that line jump."
        }
        return "No matching files."
    }

    var commandPaletteScopeHints: [CommandPaletteScope] {
        let preferredOrder = ["File", "Go", "Search", "Edit", "Git"]
        let scopesByCategory = Dictionary(uniqueKeysWithValues: availableCommandPaletteScopes.map { ($0.category, $0) })

        return preferredOrder.compactMap { scopesByCategory[$0] }
    }

    var activeCommandPaletteScope: CommandPaletteScope? {
        commandPaletteQueryContext(for: commandPaletteQuery).scope
    }

    var commandPaletteHelpText: String {
        let context = commandPaletteQueryContext(for: commandPaletteQuery)

        if let scope = context.scope {
            if context.searchText.isEmpty {
                return "Scoped to \(scope.title) commands. Type to narrow further or remove \(scope.queryToken) to search everything."
            }
            return "Scoped to \(scope.title) commands."
        }

        if context.searchText.isEmpty {
            return "Use file:, go:, search:, edit:, or git: to narrow instantly."
        }

        return "Press Return to run the selected command."
    }

    var commandPaletteEmptyStateText: String {
        let context = commandPaletteQueryContext(for: commandPaletteQuery)

        if let scope = context.scope {
            if context.searchText.isEmpty {
                return "No \(scope.title.lowercased()) commands are available right now."
            }

            return "No matching \(scope.title.lowercased()) commands. Try removing \(scope.queryToken) or broadening the term."
        }

        return context.searchText.isEmpty
            ? "Start typing a command, or narrow with file:, go:, search:, edit:, or git:."
            : "No matching commands. Try file:, go:, search:, edit:, or git:."
    }

    var commandPaletteActions: [CommandPaletteAction] {
        var actions: [CommandPaletteAction] = [
            makeCommandPaletteAction(
                id: "newFile",
                title: "New File",
                shortcut: "⌘N",
                category: "File",
                aliases: ["create file", "new document", "touch file"]
            ) {
                self.createNewFile()
            },
            makeCommandPaletteAction(
                id: "openFolder",
                title: "Open Folder",
                shortcut: "⌘O",
                category: "File",
                aliases: ["open project", "open workspace", "open directory"]
            ) {
                self.openFolder()
            },
            makeCommandPaletteAction(
                id: "save",
                title: "Save",
                shortcut: "⌘S",
                category: "File",
                aliases: ["save file", "write file", "save document"]
            ) {
                self.saveCurrentFile()
            }
        ]

        if let selectedTabIndex {
            actions.append(
                makeCommandPaletteAction(
                    id: "closeTab",
                    title: "Close Tab",
                    shortcut: "⌘W",
                    category: "File",
                    aliases: ["close file", "close editor"]
                ) {
                    _ = self.closeTab(at: selectedTabIndex)
                }
            )

            if openTabs.count > 1 {
                actions.append(
                    makeCommandPaletteAction(
                        id: "closeOtherTabs",
                        title: "Close Other Tabs",
                        shortcut: "",
                        category: "File",
                        aliases: ["close others", "keep this tab only", "close other editors"]
                    ) {
                        self.closeOtherTabs(except: selectedTabIndex)
                    }
                )
            }

            if selectedTabIndex < openTabs.count - 1 {
                actions.append(
                    makeCommandPaletteAction(
                        id: "closeTabsToTheRight",
                        title: "Close Tabs to the Right",
                        shortcut: "",
                        category: "File",
                        aliases: ["close tabs right", "close right tabs", "close tabs on the right"]
                    ) {
                        self.closeTabsToTheRight(of: selectedTabIndex)
                    }
                )
            }
        }

        if !openTabs.isEmpty {
            actions.append(
                makeCommandPaletteAction(
                    id: "closeAllTabs",
                    title: "Close All Tabs",
                    shortcut: "",
                    category: "File",
                    aliases: ["close every tab", "close all editors", "close all files"]
                ) {
                    self.closeAllTabs()
                }
            )
        }

        if let selectedTab {
            actions.append(
                makeCommandPaletteAction(
                    id: "copyCurrentFilePath",
                    title: "Copy File Path",
                    shortcut: "",
                    category: "File",
                    aliases: ["copy path", "copy absolute path", "yank file path"]
                ) {
                    self.copyStringToPasteboard(self.copyFilePath(tab: selectedTab))
                }
            )

            if selectedTab.filePath != nil {
                actions.append(
                    makeCommandPaletteAction(
                        id: "revealCurrentFileInFinder",
                        title: "Reveal in Finder",
                        shortcut: "",
                        category: "File",
                        aliases: ["show in finder", "finder", "reveal file"]
                    ) {
                        self.revealInFinder(tab: selectedTab)
                    }
                )
            }

            if relativeFilePath(tab: selectedTab) != nil {
                actions.append(
                    makeCommandPaletteAction(
                        id: "copyCurrentRelativeFilePath",
                        title: "Copy Relative File Path",
                        shortcut: "",
                        category: "File",
                        aliases: ["copy relative path", "copy project path", "yank relative path"]
                    ) {
                        self.copyStringToPasteboard(self.relativeFilePath(tab: selectedTab))
                    }
                )
            }
        }

        if canFindReferences {
            actions.append(
                makeCommandPaletteAction(
                    id: "findReferences",
                    title: "Find References",
                    shortcut: "⇧F12",
                    category: "Go",
                    aliases: ["references", "find usages", "show references"]
                ) {
                    self.commandDispatcher.send(.findReferences)
                }
            )
        }

        if canNavigateProblems {
            actions.append(
                makeCommandPaletteAction(
                    id: "nextProblem",
                    title: "Next Problem",
                    shortcut: "",
                    category: "Go",
                    aliases: ["next diagnostic", "next error", "next warning"]
                ) {
                    self.openNextProblem()
                }
            )

            actions.append(
                makeCommandPaletteAction(
                    id: "previousProblem",
                    title: "Previous Problem",
                    shortcut: "",
                    category: "Go",
                    aliases: ["previous diagnostic", "previous error", "previous warning", "prev problem"]
                ) {
                    self.openPreviousProblem()
                }
            )
        }

        if canNavigateBreakpoints {
            actions.append(
                makeCommandPaletteAction(
                    id: "nextBreakpoint",
                    title: "Next Breakpoint",
                    shortcut: "",
                    category: "Go",
                    aliases: ["next break", "next debug breakpoint"]
                ) {
                    self.openNextBreakpoint()
                }
            )

            actions.append(
                makeCommandPaletteAction(
                    id: "previousBreakpoint",
                    title: "Previous Breakpoint",
                    shortcut: "",
                    category: "Go",
                    aliases: ["previous break", "prev breakpoint", "previous debug breakpoint"]
                ) {
                    self.openPreviousBreakpoint()
                }
            )
        }

        if hasOpenFile {
            actions.append(
                makeCommandPaletteAction(
                    id: "goToLine",
                    title: "Go to Line",
                    shortcut: "⌘L",
                    category: "Go",
                    aliases: ["line", "jump to line", "goto line"]
                ) {
                    self.beginGoToLine()
                }
            )
        }

        if hasWorkspaceDiagnostics {
            actions.append(
                makeCommandPaletteAction(
                    id: "goToProblem",
                    title: "Go to Problem in Workspace",
                    shortcut: "!",
                    category: "Go",
                    aliases: ["workspace problem", "problem search", "diagnostic search", "go to problem"]
                ) {
                    self.beginWorkspaceProblemSearch()
                }
            )
        }

        if rootDirectory != nil {
            actions.append(
                makeCommandPaletteAction(
                    id: "goToSymbol",
                    title: "Go to Symbol in Workspace",
                    shortcut: "#",
                    category: "Go",
                    aliases: ["workspace symbol", "symbol search", "symbols"]
                ) {
                    self.beginWorkspaceSymbolSearch()
                }
            )
        }

        if rootDirectory != nil && !configService.hasProjectConfig() {
            actions.append(
                makeCommandPaletteAction(
                    id: "createProjectConfig",
                    title: "Create Project Config",
                    shortcut: "",
                    category: "Project",
                    aliases: ["project config", "workspace config", ".rosewood.toml"]
                ) {
                    self.createProjectConfig()
                }
            )
        }

        if rootDirectory != nil {
            actions.append(
                makeCommandPaletteAction(
                    id: "showSourceControl",
                    title: "Show Source Control",
                    shortcut: "",
                    category: "View",
                    aliases: ["git", "scm", "version control", "source control"]
                ) {
                    self.showSourceControlSidebar()
                }
            )
        }

        actions.append(
            makeCommandPaletteAction(
                id: "showExplorer",
                title: "Show Explorer",
                shortcut: "",
                category: "View",
                aliases: ["explorer", "files sidebar", "project tree"]
            ) {
                self.showExplorerSidebar()
            }
        )

        actions.append(
            makeCommandPaletteAction(
                id: "showDebugSidebar",
                title: "Show Debug Sidebar",
                shortcut: "",
                category: "View",
                aliases: ["debug", "debugger", "breakpoints"]
            ) {
                self.showDebugSidebar()
            }
        )

        if canStartDebugging {
            actions.append(
                makeCommandPaletteAction(
                    id: "startDebugging",
                    title: "\(debugPrimaryActionTitle) Debugger",
                    shortcut: "",
                    category: "Debug",
                    aliases: ["start debugger", "run debugger", "debug session", "restart debugger"]
                ) {
                    self.startDebugging()
                }
            )
        }

        if hasCurrentDebugStopLocation {
            actions.append(
                makeCommandPaletteAction(
                    id: "openCurrentDebugStopLocation",
                    title: "Open Current Stop Location",
                    shortcut: "",
                    category: "Go",
                    aliases: ["current stop", "stopped location", "debug stop location"]
                ) {
                    self.openCurrentDebugStopLocation()
                }
            )
        }

        if canStopDebugging {
            actions.append(
                makeCommandPaletteAction(
                    id: "stopDebugging",
                    title: "Stop Debugger",
                    shortcut: "",
                    category: "Debug",
                    aliases: ["stop debugger", "end debug session", "reset debugger"]
                ) {
                    self.stopDebugging()
                }
            )
        }

        if canAccessDebugControls {
            actions.append(
                makeCommandPaletteAction(
                    id: isDebugPanelVisible ? "hideDebugConsole" : "showDebugConsole",
                    title: isDebugPanelVisible ? "Hide Debug Console" : "Show Debug Console",
                    shortcut: "",
                    category: "Debug",
                    aliases: ["debug console", "console", "show console", "hide console"]
                ) {
                    self.toggleDebugPanel()
                }
            )
        }

        if !debugConsoleEntries.isEmpty {
            actions.append(
                makeCommandPaletteAction(
                    id: "clearDebugConsole",
                    title: "Clear Debug Console",
                    shortcut: "",
                    category: "Debug",
                    aliases: ["clear console", "clear debugger output", "reset debug console"]
                ) {
                    self.clearDebugConsole()
                }
            )
        }

        if debugConfigurations.count > 1 {
            for configuration in debugConfigurations where configuration.name != selectedDebugConfigurationName {
                actions.append(
                    makeCommandPaletteAction(
                        id: "selectDebugConfiguration-\(commandPaletteIdentifierFragment(configuration.name))",
                        title: "Select Debug Configuration: \(configuration.name)",
                        shortcut: "",
                        category: "Debug",
                        aliases: [
                            "debug config \(configuration.name)",
                            "use debug config \(configuration.name)",
                            "switch debug configuration \(configuration.name)"
                        ]
                    ) {
                        self.selectDebugConfiguration(named: configuration.name)
                    }
                )
            }
        }

        if canShowProblemsPanel {
            actions.append(
                makeCommandPaletteAction(
                    id: isDiagnosticsPanelVisible ? "hideProblemsPanel" : "showProblemsPanel",
                    title: isDiagnosticsPanelVisible ? "Hide Problems" : "Show Problems",
                    shortcut: "",
                    category: "View",
                    aliases: ["diagnostics", "problems", "errors", "warnings"]
                ) {
                    self.toggleDiagnosticsPanel()
                }
            )

            if hasWorkspaceDiagnostics {
                actions.append(
                    makeCommandPaletteAction(
                        id: "showWorkspaceProblems",
                        title: "Show Workspace Problems",
                        shortcut: "",
                        category: "View",
                        aliases: ["workspace diagnostics", "workspace errors", "all problems"]
                    ) {
                        if !self.isDiagnosticsPanelVisible {
                            self.toggleDiagnosticsPanel()
                        }
                        self.setDiagnosticsPanelScope(.workspace)
                    }
                )
            }

            if hasOpenFile {
                actions.append(
                    makeCommandPaletteAction(
                        id: "showCurrentFileProblems",
                        title: "Show Current File Problems",
                        shortcut: "",
                        category: "View",
                        aliases: ["file diagnostics", "current problems", "current file errors"]
                    ) {
                        if !self.isDiagnosticsPanelVisible {
                            self.toggleDiagnosticsPanel()
                        }
                        self.setDiagnosticsPanelScope(.currentFile)
                    }
                )
            }
        }

        if !referenceResults.isEmpty {
            actions.append(
                makeCommandPaletteAction(
                    id: isReferencesPanelVisible ? "hideReferencesPanel" : "showReferencesPanel",
                    title: isReferencesPanelVisible ? "Hide References" : "Show References",
                    shortcut: "",
                    category: "View",
                    aliases: ["references panel", "usage results", "reference results"]
                ) {
                    self.toggleReferencesPanel()
                }
            )
        }

        if gitRepositoryStatus.isRepository {
            actions.append(
                makeCommandPaletteAction(
                    id: "refreshGitStatus",
                    title: "Refresh Git Status",
                    shortcut: "",
                    category: "Git",
                    aliases: ["git refresh", "reload git", "refresh source control"]
                ) {
                    self.refreshGitState()
                }
            )
        }

        if let selectedGitChangedFile {
            if canShowPreviousGitChange {
                actions.append(
                    makeCommandPaletteAction(
                        id: "showPreviousGitChange",
                        title: "Previous Changed File",
                        shortcut: "",
                        category: "Git",
                        aliases: ["previous change", "previous diff", "prev changed file"]
                    ) {
                        self.showPreviousGitChange()
                    }
                )
            }

            if canShowNextGitChange {
                actions.append(
                    makeCommandPaletteAction(
                        id: "showNextGitChange",
                        title: "Next Changed File",
                        shortcut: "",
                        category: "Git",
                        aliases: ["next change", "next diff", "next changed file"]
                    ) {
                        self.showNextGitChange()
                    }
                )
            }

            actions.append(
                makeCommandPaletteAction(
                    id: "openSelectedGitChangeInEditor",
                    title: "Open Selected Change in Editor",
                    shortcut: "",
                    category: "Git",
                    aliases: ["open change", "open diff file", "open selected change"]
                ) {
                    self.openSelectedGitChangeInEditor()
                }
            )

            actions.append(
                makeCommandPaletteAction(
                    id: "revealSelectedGitChangeInExplorer",
                    title: "Reveal Selected Change in Explorer",
                    shortcut: "",
                    category: "Git",
                    aliases: ["reveal change", "show change in explorer", "focus change in files"]
                ) {
                    self.revealSelectedGitChangeInExplorer()
                }
            )

            if selectedGitChangedFile.canStage {
                actions.append(
                    makeCommandPaletteAction(
                        id: "stageSelectedGitChange",
                        title: "Stage Selected Change",
                        shortcut: "",
                        category: "Git",
                        aliases: ["stage change", "git add", "stage file"]
                    ) {
                        self.stageSelectedGitChange()
                    }
                )
            }

            if selectedGitChangedFile.canUnstage {
                actions.append(
                    makeCommandPaletteAction(
                        id: "unstageSelectedGitChange",
                        title: "Unstage Selected Change",
                        shortcut: "",
                        category: "Git",
                        aliases: ["unstage change", "git reset", "remove from staged"]
                    ) {
                        self.unstageSelectedGitChange()
                    }
                )
            }

            if selectedGitChangedFile.canDiscard {
                actions.append(
                    makeCommandPaletteAction(
                        id: "discardSelectedGitChange",
                        title: "Discard Selected Change",
                        shortcut: "",
                        category: "Git",
                        aliases: ["discard change", "revert file", "throw away diff"]
                    ) {
                        self.discardSelectedGitChange()
                    }
                )
            }
        }

        if canUndoLastProjectReplace {
            actions.append(
                makeCommandPaletteAction(
                    id: "undoLastProjectReplace",
                    title: "Undo Last Project Replace",
                    shortcut: "",
                    category: "Edit",
                    aliases: ["undo replace", "revert replace", "undo project replace"]
                ) {
                    self.undoLastProjectReplace()
                }
            )
        }

        if rootDirectory != nil {
            actions.append(
                makeCommandPaletteAction(
                    id: "showProjectSearch",
                    title: "Find in Project",
                    shortcut: "⌘⇧F",
                    category: "Search",
                    aliases: ["find in files", "search project", "replace in project"]
                ) {
                    self.showSearchSidebar()
                }
            )
        }

        if canNavigateProjectSearchResults {
            actions.append(
                makeCommandPaletteAction(
                    id: "nextProjectSearchResult",
                    title: "Next Search Result",
                    shortcut: "⌘G",
                    category: "Search",
                    aliases: ["next match", "next result"]
                ) {
                    self.showNextProjectSearchResult()
                }
            )

            actions.append(
                makeCommandPaletteAction(
                    id: "previousProjectSearchResult",
                    title: "Previous Search Result",
                    shortcut: "⌘⇧G",
                    category: "Search",
                    aliases: ["previous match", "previous result", "prev result"]
                ) {
                    self.showPreviousProjectSearchResult()
                }
            )
        }

        if canCollapseProjectSearchGroups {
            actions.append(
                makeCommandPaletteAction(
                    id: "collapseSearchResults",
                    title: "Collapse Search Results",
                    shortcut: "",
                    category: "Search",
                    aliases: ["collapse results", "fold search results"]
                ) {
                    self.collapseAllProjectSearchGroups()
                }
            )
        }

        if canExpandProjectSearchGroups {
            actions.append(
                makeCommandPaletteAction(
                    id: "expandSearchResults",
                    title: "Expand Search Results",
                    shortcut: "",
                    category: "Search",
                    aliases: ["expand results", "unfold search results"]
                ) {
                    self.expandAllProjectSearchGroups()
                }
            )
        }

        let queryContext = commandPaletteQueryContext(for: commandPaletteQuery)
        let scopedActions = scopedCommandPaletteActions(actions, scope: queryContext.scope)
        return rankedCommandPaletteActions(scopedActions, query: queryContext.searchText)
    }

    var commandPaletteSections: [CommandPaletteSection] {
        let actions = commandPaletteActions
        guard !actions.isEmpty else { return [] }

        let queryContext = self.commandPaletteQueryContext(for: commandPaletteQuery)
        let normalizedQuery = queryContext.searchText
        let decorate: (CommandPaletteAction) -> CommandPaletteAction = { action in
            self.decoratedCommandPaletteAction(action, query: normalizedQuery)
        }

        if normalizedQuery.isEmpty {
            let recentActions = actions
                .filter { self.commandPaletteRecencyBoost(for: $0.id) > 0 }
                .prefix(5)
                .map(decorate)
            let recentIDs = Set(recentActions.map(\.id))
            let remainingActions = actions.filter { !recentIDs.contains($0.id) }
            var sections: [CommandPaletteSection] = []

            if !recentActions.isEmpty {
                sections.append(CommandPaletteSection(title: "Recent", actions: Array(recentActions)))
            }

            sections.append(contentsOf: self.commandPaletteCategorySections(for: remainingActions, query: normalizedQuery))
            return sections
        }

        let shouldGroupByCategory = self.commandPaletteShouldGroupByCategory(actions: actions, normalizedQuery: normalizedQuery)
        if shouldGroupByCategory {
            return self.commandPaletteCategorySections(for: actions, query: normalizedQuery)
        }

        return [
            CommandPaletteSection(
                title: queryContext.scope.map { "\($0.title) Commands" } ?? "Commands",
                actions: actions.map(decorate)
            )
        ]
    }

    var quickOpenSections: [QuickOpenSection] {
        let trimmedQuery = quickOpenQuery.trimmingCharacters(in: .whitespacesAndNewlines)

        if let request = quickOpenFileLineRequest(from: trimmedQuery) {
            let items = quickOpenFileLineItems(for: request)
            return items.isEmpty ? [] : [QuickOpenSection(title: "Lines", items: items)]
        }

        if trimmedQuery.hasPrefix(":") {
            let items = quickOpenLineJumpItems(for: trimmedQuery)
            return items.isEmpty ? [] : [QuickOpenSection(title: "Lines", items: items)]
        }

        if trimmedQuery.hasPrefix("!") {
            return quickOpenWorkspaceProblemSections(for: trimmedQuery)
        }

        if trimmedQuery.hasPrefix("#") {
            return quickOpenWorkspaceSymbolSections(for: trimmedQuery)
        }

        let fileItems = flatFileList.enumerated().compactMap { index, item in
            guard !item.isDirectory else { return nil }

            let displayPath = relativeDisplayPath(for: item.path)
            guard let score = quickOpenMatchScore(for: item, displayPath: displayPath, query: trimmedQuery) else {
                return nil
            }

            return QuickOpenItem(
                kind: .file(item),
                title: item.name,
                subtitle: displayPath,
                detailText: nil,
                iconName: item.iconName,
                badge: nil,
                score: score,
                originalIndex: index
            )
        }
        .sorted(by: compareQuickOpenItems)

        return fileItems.isEmpty ? [] : [QuickOpenSection(title: "Files", items: fileItems)]
    }

    var quickOpenItems: [QuickOpenItem] {
        quickOpenSections.flatMap(\.items)
    }

    private func makeCommandPaletteAction(
        id: String,
        title: String,
        shortcut: String,
        category: String,
        aliases: [String] = [],
        action: @escaping () -> Void
    ) -> CommandPaletteAction {
        CommandPaletteAction(
            id: id,
            title: title,
            shortcut: shortcut,
            category: category,
            aliases: aliases,
            detailText: nil,
            badge: nil
        ) {
            self.recordCommandPaletteActionAccess(id: id)
            action()
        }
    }

    func applyCommandPaletteScope(_ scope: CommandPaletteScope) {
        let context = commandPaletteQueryContext(for: commandPaletteQuery)

        if context.scope?.id == scope.id {
            commandPaletteQuery = context.searchText
            return
        }

        let suffix = context.searchText.isEmpty ? "" : " \(context.searchText)"
        commandPaletteQuery = "\(scope.queryToken)\(suffix)"
    }

    func applyQuickOpenProblemFilterHint(_ hint: QuickOpenProblemFilterHint) {
        let query = quickOpenWorkspaceProblemQuery(from: quickOpenQuery)
        var severity = query.severity
        var scope = query.scope

        switch hint.kind {
        case .scope(let targetScope):
            scope = scope == targetScope ? nil : targetScope
        case .severity(let targetSeverity):
            severity = severity == targetSeverity ? nil : targetSeverity
        }

        var parts: [String] = ["!"]
        if let scope {
            parts.append(scope.queryToken)
        }
        if let severity {
            parts.append(problemFilterToken(for: severity))
        }
        if !query.searchText.isEmpty {
            parts.append(query.searchText)
        }

        quickOpenQuery = parts.joined(separator: " ")
    }

    private func rankedCommandPaletteActions(_ actions: [CommandPaletteAction], query: String) -> [CommandPaletteAction] {
        let normalizedQuery = normalizedCommandPaletteSearchText(query)

        if normalizedQuery.isEmpty {
            return actions.sorted(by: compareCommandPaletteActions)
        }

        return actions
            .compactMap { action -> (action: CommandPaletteAction, score: Int)? in
                guard let score = commandPaletteMatchScore(for: action, query: normalizedQuery) else {
                    return nil
                }
                return (action, score + commandPaletteRecencyBoost(for: action.id))
            }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score {
                    return lhs.score > rhs.score
                }
                return compareCommandPaletteActions(lhs.action, rhs.action)
            }
            .map(\.action)
    }

    private func scopedCommandPaletteActions(
        _ actions: [CommandPaletteAction],
        scope: CommandPaletteScope?
    ) -> [CommandPaletteAction] {
        guard let scope else { return actions }
        let normalizedScopeCategory = normalizedCommandPaletteSearchText(scope.category)
        return actions.filter { normalizedCommandPaletteSearchText($0.category) == normalizedScopeCategory }
    }

    private func compareCommandPaletteActions(_ lhs: CommandPaletteAction, _ rhs: CommandPaletteAction) -> Bool {
        let lhsRecency = commandPaletteRecencyBoost(for: lhs.id)
        let rhsRecency = commandPaletteRecencyBoost(for: rhs.id)

        if lhsRecency != rhsRecency {
            return lhsRecency > rhsRecency
        }

        let categoryComparison = lhs.category.localizedStandardCompare(rhs.category)
        if categoryComparison != .orderedSame {
            return categoryComparison == .orderedAscending
        }

        return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }

    private func decoratedCommandPaletteAction(_ action: CommandPaletteAction, query: String) -> CommandPaletteAction {
        let aliasMatch = commandPaletteMatchingAlias(for: action, query: query)
        let recentBadge = query.isEmpty && commandPaletteRecencyBoost(for: action.id) > 0 ? "Recent" : nil

        return CommandPaletteAction(
            id: action.id,
            title: action.title,
            shortcut: action.shortcut,
            category: action.category,
            aliases: action.aliases,
            detailText: aliasMatch.map { "Alias: \($0)" },
            badge: recentBadge,
            action: action.action
        )
    }

    private func commandPaletteCategorySections(for actions: [CommandPaletteAction], query: String) -> [CommandPaletteSection] {
        let grouped = Dictionary(grouping: actions, by: \.category)

        return grouped.keys
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .compactMap { category in
                guard let categoryActions = grouped[category], !categoryActions.isEmpty else { return nil }
                return CommandPaletteSection(
                    title: category,
                    actions: categoryActions.map { decoratedCommandPaletteAction($0, query: query) }
                )
            }
    }

    private func commandPaletteShouldGroupByCategory(actions: [CommandPaletteAction], normalizedQuery: String) -> Bool {
        guard actions.count > 4 else { return false }
        let categories = Set(actions.map(\.category))
        guard categories.count > 1 else { return false }
        return normalizedQuery.count < 4 || commandPaletteSearchTerms(fromNormalizedText: normalizedQuery).count <= 1
    }

    private func commandPaletteMatchingAlias(for action: CommandPaletteAction, query: String) -> String? {
        guard !query.isEmpty else { return nil }

        return action.aliases.first { alias in
            let normalizedAlias = normalizedCommandPaletteSearchText(alias)
            if normalizedAlias == query || normalizedAlias.hasPrefix(query) || normalizedAlias.contains(query) {
                return true
            }

            let queryTerms = commandPaletteSearchTerms(fromNormalizedText: query)
            let aliasTerms = commandPaletteSearchTerms(fromNormalizedText: normalizedAlias)
            if !queryTerms.isEmpty && commandPaletteWordPrefixMatch(words: aliasTerms, queryTerms: queryTerms) {
                return true
            }

            return false
        }
    }

    private func commandPaletteMatchScore(for action: CommandPaletteAction, query: String) -> Int? {
        let normalizedTitle = normalizedCommandPaletteSearchText(action.title)
        let normalizedCategory = normalizedCommandPaletteSearchText(action.category)
        let normalizedAliases = action.aliases.map(normalizedCommandPaletteSearchText)
        let queryTerms = commandPaletteSearchTerms(fromNormalizedText: query)
        let condensedQuery = condensedCommandPaletteSearchText(query)
        let titleWords = commandPaletteSearchTerms(fromNormalizedText: normalizedTitle)
        var bestScore: Int?

        func consider(_ score: Int?) {
            guard let score else { return }
            bestScore = max(bestScore ?? .min, score)
        }

        if normalizedTitle == query {
            consider(1_700)
        }

        if normalizedAliases.contains(query) {
            consider(1_660)
        }

        if normalizedTitle.hasPrefix(query) {
            consider(1_560)
        }

        if normalizedAliases.contains(where: { $0.hasPrefix(query) }) {
            consider(1_520)
        }

        if !queryTerms.isEmpty, commandPaletteWordPrefixMatch(words: titleWords, queryTerms: queryTerms) {
            consider(1_460)
        }

        if !queryTerms.isEmpty,
           normalizedAliases.contains(where: {
               commandPaletteWordPrefixMatch(
                   words: commandPaletteSearchTerms(fromNormalizedText: $0),
                   queryTerms: queryTerms
               )
           }) {
            consider(1_420)
        }

        if normalizedTitle.contains(query) {
            consider(1_340)
        }

        if normalizedAliases.contains(where: { $0.contains(query) }) {
            consider(1_300)
        }

        if !queryTerms.isEmpty && queryTerms.allSatisfy({ normalizedTitle.contains($0) }) {
            consider(1_260 + min(queryTerms.count * 10, 40))
        }

        if !queryTerms.isEmpty && normalizedAliases.contains(where: { alias in
            queryTerms.allSatisfy { alias.contains($0) }
        }) {
            consider(1_220 + min(queryTerms.count * 10, 40))
        }

        if normalizedCategory.contains(query) {
            consider(1_100)
        }

        if !condensedQuery.isEmpty {
            let titleInitialism = commandPaletteInitialism(forWords: titleWords)
            if titleInitialism.hasPrefix(condensedQuery) {
                consider(1_060)
            }

            let aliasInitialismScore = normalizedAliases
                .map { commandPaletteInitialism(forWords: commandPaletteSearchTerms(fromNormalizedText: $0)) }
                .contains { $0.hasPrefix(condensedQuery) }
            if aliasInitialismScore {
                consider(1_020)
            }

            consider(commandPaletteFuzzyScore(haystack: condensedCommandPaletteSearchText(normalizedTitle), query: condensedQuery))
            consider(
                normalizedAliases
                    .compactMap { commandPaletteFuzzyScore(haystack: condensedCommandPaletteSearchText($0), query: condensedQuery) }
                    .max()
                    .map { $0 - 20 }
            )
        }

        return bestScore
    }

    private func normalizedCommandPaletteSearchText(_ text: String) -> String {
        text
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var availableCommandPaletteScopes: [CommandPaletteScope] {
        [
            CommandPaletteScope(id: "file", title: "File", category: "File", queryToken: "file:", aliases: ["file", "files", "f"]),
            CommandPaletteScope(id: "go", title: "Go", category: "Go", queryToken: "go:", aliases: ["go", "goto", "g"]),
            CommandPaletteScope(id: "search", title: "Search", category: "Search", queryToken: "search:", aliases: ["search", "find", "s"]),
            CommandPaletteScope(id: "edit", title: "Edit", category: "Edit", queryToken: "edit:", aliases: ["edit", "e"]),
            CommandPaletteScope(id: "debug", title: "Debug", category: "Debug", queryToken: "debug:", aliases: ["debug", "dbg", "run"]),
            CommandPaletteScope(id: "git", title: "Git", category: "Git", queryToken: "git:", aliases: ["git", "scm"]),
            CommandPaletteScope(id: "project", title: "Project", category: "Project", queryToken: "project:", aliases: ["project", "workspace", "p"]),
            CommandPaletteScope(id: "view", title: "View", category: "View", queryToken: "view:", aliases: ["view", "panel", "v"])
        ]
    }

    private func commandPaletteQueryContext(for query: String) -> CommandPaletteQueryContext {
        let normalizedQuery = normalizedCommandPaletteSearchText(query)
        guard let separatorIndex = normalizedQuery.firstIndex(of: ":") else {
            return CommandPaletteQueryContext(scope: nil, searchText: normalizedQuery)
        }

        let scopeToken = String(normalizedQuery[..<separatorIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let scope = availableCommandPaletteScopes.first(where: { $0.aliases.contains(scopeToken) }) else {
            return CommandPaletteQueryContext(scope: nil, searchText: normalizedQuery)
        }

        let searchStart = normalizedQuery.index(after: separatorIndex)
        let searchText = String(normalizedQuery[searchStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return CommandPaletteQueryContext(scope: scope, searchText: searchText)
    }

    private func condensedCommandPaletteSearchText(_ text: String) -> String {
        normalizedCommandPaletteSearchText(text)
            .filter { $0.isLetter || $0.isNumber }
    }

    private func commandPaletteIdentifierFragment(_ text: String) -> String {
        let normalized = normalizedCommandPaletteSearchText(text)
        let collapsed = normalized
            .split { !$0.isLetter && !$0.isNumber }
            .joined(separator: "-")
        return collapsed.isEmpty ? "item" : collapsed
    }

    private func commandPaletteSearchTerms(fromNormalizedText text: String) -> [String] {
        text.split { character in
            !character.isLetter && !character.isNumber
        }
        .map(String.init)
    }

    private func commandPaletteWordPrefixMatch(words: [String], queryTerms: [String]) -> Bool {
        guard !words.isEmpty, !queryTerms.isEmpty else { return false }
        var wordIndex = 0

        for term in queryTerms {
            guard let matchIndex = words[wordIndex...].firstIndex(where: { $0.hasPrefix(term) }) else {
                return false
            }
            wordIndex = words.index(after: matchIndex)
        }

        return true
    }

    private func commandPaletteInitialism(forWords words: [String]) -> String {
        String(words.compactMap(\.first))
    }

    private func commandPaletteFuzzyScore(haystack: String, query: String) -> Int? {
        guard !haystack.isEmpty, !query.isEmpty else { return nil }
        var searchIndex = haystack.startIndex
        var matched = 0
        var gapPenalty = 0

        for character in query {
            guard let matchIndex = haystack[searchIndex...].firstIndex(of: character) else {
                return nil
            }

            gapPenalty += haystack.distance(from: searchIndex, to: matchIndex)
            matched += 1
            searchIndex = haystack.index(after: matchIndex)
        }

        return max(900 - gapPenalty * 8 - max(0, haystack.count - matched) * 2, 700)
    }

    private func commandPaletteRecencyBoost(for actionID: String) -> Int {
        guard let index = recentCommandPaletteActionIDs.firstIndex(of: actionID) else {
            return 0
        }

        return max(220 - index * 24, 40)
    }

    private func recordCommandPaletteActionAccess(id: String) {
        recentCommandPaletteActionIDs.removeAll { $0 == id }
        recentCommandPaletteActionIDs.insert(id, at: 0)
        recentCommandPaletteActionIDs = Array(recentCommandPaletteActionIDs.prefix(8))
    }

    var flatFileList: [FileItem] {
        flattenFileTree(fileTree)
    }

    var groupedProjectSearchResults: [ProjectSearchFileGroup] {
        let groupedResults = Dictionary(grouping: projectSearchResults, by: { normalizedPath(for: $0.filePath) })

        return groupedResults.values.compactMap { results in
            guard let firstResult = results.first else { return nil }
            let sortedResults = results.sorted { lhs, rhs in
                if lhs.lineNumber == rhs.lineNumber {
                    return lhs.columnNumber < rhs.columnNumber
                }
                return lhs.lineNumber < rhs.lineNumber
            }

            let fileURL = firstResult.filePath
            return ProjectSearchFileGroup(
                filePath: fileURL,
                fileName: fileURL.lastPathComponent,
                displayPath: relativeDisplayPath(for: fileURL),
                results: sortedResults
            )
        }
        .sorted { lhs, rhs in
            lhs.displayPath.localizedStandardCompare(rhs.displayPath) == .orderedAscending
        }
    }

    var visibleGroupedProjectSearchResults: [ProjectSearchFileGroup] {
        groupedProjectSearchResults.filter { !collapsedProjectSearchGroupIDs.contains($0.id) }
    }

    var projectSearchMatchCount: Int {
        projectSearchResults.reduce(0) { partialResult, result in
            partialResult + result.matchCount
        }
    }

    var orderedProjectSearchResults: [ProjectSearchResult] {
        visibleGroupedProjectSearchResults.flatMap(\.results)
    }

    var selectedProjectSearchResults: [ProjectSearchResult] {
        projectSearchResults.filter { selectedProjectSearchResultIDs.contains($0.id) }
    }

    var activeProjectSearchResult: ProjectSearchResult? {
        orderedProjectSearchResults.first { $0.id == activeProjectSearchResultID }
    }

    var selectedProjectSearchMatchCount: Int {
        selectedProjectSearchResults.reduce(0) { partialResult, result in
            partialResult + result.matchCount
        }
    }

    var projectSearchFileCount: Int {
        groupedProjectSearchResults.count
    }

    var visibleProjectSearchResultCount: Int {
        orderedProjectSearchResults.count
    }

    var visibleProjectSearchFileCount: Int {
        visibleGroupedProjectSearchResults.count
    }

    var projectSearchVisibilitySummary: String {
        "\(visibleProjectSearchResultCount) visible result\(visibleProjectSearchResultCount == 1 ? "" : "s") in \(visibleProjectSearchFileCount) file\(visibleProjectSearchFileCount == 1 ? "" : "s")"
    }

    var selectedProjectSearchFileCount: Int {
        Set(selectedProjectSearchResults.map { normalizedPath(for: $0.filePath) }).count
    }

    var canReplaceProjectSearchResults: Bool {
        let trimmedQuery = projectSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedQuery.isEmpty
            && !isSearchingProject
            && !isReplacingInProject
            && projectSearchResultsQuery == trimmedQuery
            && projectSearchResultsOptions == currentProjectSearchOptions
            && !projectSearchResults.isEmpty
    }

    var replaceAllProjectResultsTitle: String {
        guard canReplaceSelectedProjectSearchResults else { return "Replace Selected" }
        return "Replace Selected (\(selectedProjectSearchMatchCount))"
    }

    var canReplaceSelectedProjectSearchResults: Bool {
        canReplaceProjectSearchResults && !selectedProjectSearchResults.isEmpty
    }

    var canApplyProjectReplacePreview: Bool {
        projectReplacePreview != nil && !isReplacingInProject
    }

    var canUndoLastProjectReplace: Bool {
        lastProjectReplaceTransaction != nil && !isReplacingInProject && projectReplacePreview == nil
    }

    var canNavigateProjectSearchResults: Bool {
        sidebarMode == .search && !orderedProjectSearchResults.isEmpty
    }

    var canCollapseProjectSearchGroups: Bool {
        groupedProjectSearchResults.contains { !collapsedProjectSearchGroupIDs.contains($0.id) }
    }

    var canExpandProjectSearchGroups: Bool {
        groupedProjectSearchResults.contains { collapsedProjectSearchGroupIDs.contains($0.id) }
    }

    var undoLastProjectReplaceTitle: String {
        guard let lastProjectReplaceTransaction else { return "Undo Last Replace" }
        return "Undo Last Replace (\(lastProjectReplaceTransaction.replacementCount))"
    }

    func isProjectSearchResultSelected(_ result: ProjectSearchResult) -> Bool {
        selectedProjectSearchResultIDs.contains(result.id)
    }

    func isProjectSearchGroupCollapsed(_ group: ProjectSearchFileGroup) -> Bool {
        collapsedProjectSearchGroupIDs.contains(group.id)
    }

    func isActiveProjectSearchResult(_ result: ProjectSearchResult) -> Bool {
        activeProjectSearchResultID == result.id
    }

    func setActiveProjectSearchResult(_ result: ProjectSearchResult) {
        guard orderedProjectSearchResults.contains(result) else { return }
        activeProjectSearchResultID = result.id
    }

    func moveActiveProjectSearchResult(_ direction: Int) {
        let results = orderedProjectSearchResults
        guard !results.isEmpty else {
            activeProjectSearchResultID = nil
            return
        }

        guard direction != 0 else { return }

        if let activeProjectSearchResult,
           let currentIndex = results.firstIndex(of: activeProjectSearchResult) {
            let nextIndex = (currentIndex + direction + results.count) % results.count
            activeProjectSearchResultID = results[nextIndex].id
        } else {
            activeProjectSearchResultID = direction > 0 ? results.first?.id : results.last?.id
        }
    }

    func openActiveProjectSearchResult() {
        guard let activeProjectSearchResult else { return }
        openSearchResult(activeProjectSearchResult)
    }

    func isActiveDiagnostic(_ diagnostic: LSPDiagnostic) -> Bool {
        activeCurrentDiagnostic?.id == diagnostic.id
    }

    func showNextProjectSearchResult() {
        guard canNavigateProjectSearchResults else { return }
        moveActiveProjectSearchResult(1)
        openActiveProjectSearchResult()
    }

    func showPreviousProjectSearchResult() {
        guard canNavigateProjectSearchResults else { return }
        moveActiveProjectSearchResult(-1)
        openActiveProjectSearchResult()
    }

    func toggleProjectSearchGroupCollapsed(_ group: ProjectSearchFileGroup) {
        guard groupedProjectSearchResults.contains(group) else { return }

        if collapsedProjectSearchGroupIDs.contains(group.id) {
            collapsedProjectSearchGroupIDs.remove(group.id)
        } else {
            collapsedProjectSearchGroupIDs.insert(group.id)
        }

        normalizeProjectSearchVisibilityState()
    }

    func collapseAllProjectSearchGroups() {
        collapsedProjectSearchGroupIDs = Set(groupedProjectSearchResults.map(\.id))
        normalizeProjectSearchVisibilityState()
    }

    func expandAllProjectSearchGroups() {
        collapsedProjectSearchGroupIDs.removeAll()
        normalizeProjectSearchVisibilityState()
    }

    func isProjectSearchGroupFullySelected(_ group: ProjectSearchFileGroup) -> Bool {
        !group.results.isEmpty && group.results.allSatisfy { isProjectSearchResultSelected($0) }
    }

    func toggleProjectSearchResultSelection(_ result: ProjectSearchResult) {
        guard projectSearchResults.contains(result) else { return }
        clearProjectReplacePreview()

        if selectedProjectSearchResultIDs.contains(result.id) {
            selectedProjectSearchResultIDs.remove(result.id)
        } else {
            selectedProjectSearchResultIDs.insert(result.id)
        }
    }

    func toggleProjectSearchGroupSelection(_ group: ProjectSearchFileGroup) {
        guard groupedProjectSearchResults.contains(group) else { return }
        clearProjectReplacePreview()

        let shouldSelect = !isProjectSearchGroupFullySelected(group)
        for result in group.results {
            if shouldSelect {
                selectedProjectSearchResultIDs.insert(result.id)
            } else {
                selectedProjectSearchResultIDs.remove(result.id)
            }
        }
    }

    func openFolder() {
        guard prepareForSessionTransition(title: "Open Folder", message: "Do you want to save changes before opening a different folder?") else {
            return
        }

        guard let url = ui.openPanel(true, false, false) else { return }
        openFolder(at: url)
    }

    func openExternalItems(_ urls: [URL]) {
        let existingURLs = urls
            .map(\.standardizedFileURL)
            .filter { FileManager.default.fileExists(atPath: $0.path) }

        guard !existingURLs.isEmpty else { return }
        guard prepareForSessionTransition(title: "Open", message: "Do you want to save changes before opening this item?") else {
            return
        }

        let directoryURLs = existingURLs.filter(isDirectory)
        if let directoryURL = directoryURLs.first {
            openFolder(at: directoryURL)

            let normalizedRootPath = normalizedPath(for: directoryURL)
            for fileURL in existingURLs where !isDirectory(fileURL) {
                let normalizedFilePath = normalizedPath(for: fileURL)
                guard normalizedFilePath.hasPrefix(normalizedRootPath + "/") else { continue }
                openFile(at: fileURL)
            }
            return
        }

        let fileURLs = existingURLs.filter { !isDirectory($0) }
        guard let firstFileURL = fileURLs.first else { return }

        openFolder(at: firstFileURL.deletingLastPathComponent())
        for fileURL in fileURLs {
            openFile(at: fileURL)
        }
    }

    private func openFolder(at url: URL) {
        fileWatcher.unwatchAll()
        rootDirectory = url
        expandedDirectoryPaths = []
        openTabs = []
        selectedTabIndex = nil
        closeReferencesPanel()
        pendingNewItemDirectory = nil
        clearProjectSearchResults()

        configService.setProjectRoot(url)
        lspService.setProjectRoot(url)
        reloadDebuggerState(resetConsole: true)

        if shouldPromptToCreateProjectConfig(for: url) {
            let response = ui.confirm(
                "Create Project Config?",
                "Would you like to create a .rosewood.toml file for project-specific settings?",
                .warning,
                ["Create", "Skip"]
            )
            markProjectConfigPromptHandled(for: url)
            if response == .alertFirstButtonReturn {
                createProjectConfig()
            }
        }

        reloadFileTree()
        refreshGitState()
        persistSession()
    }

    func reloadFileTree() {
        reloadFileTreeTask?.cancel()
        fileTreeLoadToken = UUID()
        let token = fileTreeLoadToken
        invalidateWorkspaceSymbolCache()

        guard let rootDirectory else {
            isLoadingFileTree = false
            fileTree = []
            persistSession()
            return
        }

        let expandedPaths = expandedDirectoryPaths
        let normalizedRootPath = normalizedPath(for: rootDirectory)
        isLoadingFileTree = true

        reloadFileTreeTask = Task { [weak self, fileService] in
            guard let self else { return }

            do {
                let tree = try await fileService.loadDirectoryAsync(
                    at: rootDirectory,
                    expandedPaths: expandedPaths,
                    includeHidden: self.showHiddenFiles
                )
                guard !Task.isCancelled,
                      self.fileTreeLoadToken == token,
                      self.rootDirectory.map(self.normalizedPath(for:)) == normalizedRootPath else {
                    return
                }
                self.fileTree = tree
                self.isLoadingFileTree = false
            } catch is CancellationError {
                guard self.fileTreeLoadToken == token else { return }
                self.isLoadingFileTree = false
            } catch {
                guard self.fileTreeLoadToken == token else { return }
                self.fileTree = []
                self.isLoadingFileTree = false
            }
        }
    }

    func createNewFile() {
        guard let rootDirectory else {
            ui.alert("No Folder Open", "Please open a folder first.", .warning)
            return
        }

        pendingNewItemDirectory = rootDirectory
        showNewFileSheet = true
    }

    func createNewFile(named name: String, in directory: URL? = nil) {
        let targetDirectory = directory ?? pendingNewItemDirectory ?? rootDirectory
        guard let targetDirectory else { return }

        do {
            let fileURL = try fileService.createFile(named: name, in: targetDirectory)
            pendingNewItemDirectory = nil
            reloadFileTree()
            openFile(at: fileURL)
            refreshGitState()
        } catch {
            ui.alert("Error", "Could not create file: \(error.localizedDescription)", .warning)
        }
    }

    func createNewFolder(named name: String, in directory: URL? = nil) {
        let targetDirectory = directory ?? pendingNewItemDirectory ?? rootDirectory
        guard let targetDirectory else { return }

        do {
            let folderURL = try fileService.createDirectory(named: name, in: targetDirectory)
            pendingNewItemDirectory = nil
            expandedDirectoryPaths.insert(normalizedPath(for: folderURL))
            reloadFileTree()
            persistSession()
        } catch {
            ui.alert("Error", "Could not create folder: \(error.localizedDescription)", .warning)
        }
    }

    func openFile(at url: URL, preservingGitDiffWorkspace: Bool = false) {
        if !preservingGitDiffWorkspace {
            dismissGitDiffWorkspace()
        }

        if let existingIndex = openTabs.firstIndex(where: { tab in
            guard let filePath = tab.filePath else { return false }
            return normalizedPath(for: filePath) == normalizedPath(for: url)
        }) {
            selectedTabIndex = existingIndex
            revealInExplorer(url)
            recordQuickOpenAccess(for: url)
            persistSession()
            return
        }

        do {
            isLoadingFile = true
            loadingFileProgress = 0.0
            
            let fileHandling = configService.settings.fileHandling
            let contentType = fileService.detectContentType(at: url, settings: fileHandling)

            switch contentType {
            case .text:
                let document = try fileService.readDocument(at: url)
                openTabs.append(
                    EditorTab(
                        filePath: url,
                        fileName: url.lastPathComponent,
                        content: document.content,
                        originalContent: document.content,
                        documentMetadata: document.metadata,
                        contentType: contentType
                    )
                )
            case .image:
                let data = try fileService.readFileAsData(at: url)
                openTabs.append(
                    EditorTab(
                        filePath: url,
                        fileName: url.lastPathComponent,
                        documentMetadata: .utf8LF,
                        contentType: contentType,
                        fileData: data
                    )
                )
            case .binary(let viewer):
                let data = viewer == .hex ? try fileService.readFileAsData(at: url) : nil
                openTabs.append(
                    EditorTab(
                        filePath: url,
                        fileName: url.lastPathComponent,
                        documentMetadata: .utf8LF,
                        contentType: contentType,
                        fileData: data
                    )
                )
            case .excluded(let reason):
                ui.alert("Unsupported File", excludedContentMessage(for: reason, fileURL: url, settings: fileHandling), .warning)
                isLoadingFile = false
                loadingFileProgress = nil
                return
            }

            selectedTabIndex = openTabs.count - 1
            revealInExplorer(url)
            fileWatcher.watch(url: url)

            let tab = openTabs[openTabs.count - 1]
            if tab.contentType.isText, let uri = tab.documentURI {
                lspService.documentOpened(uri: uri, language: tab.language, text: tab.content)
            }

            recordQuickOpenAccess(for: url)
            persistSession()
            isLoadingFile = false
            loadingFileProgress = nil
        } catch {
            ui.alert("Error", "Could not open file: \(error.localizedDescription)", .warning)
            isLoadingFile = false
            loadingFileProgress = nil
        }
    }

    private func excludedContentMessage(
        for reason: ExcludedReason,
        fileURL: URL,
        settings: AppSettings.FileHandling
    ) -> String {
        switch reason {
        case .tooLarge:
            return "\(fileURL.lastPathComponent) exceeds the configured size limit. Adjust File Handling settings if you want to allow larger files."
        case .binary:
            return "\(fileURL.lastPathComponent) appears to be binary and cannot be opened as editable text."
        case .excludedExtension:
            return "\(fileURL.lastPathComponent) uses an excluded binary extension. Open it externally or change File Handling settings to allow it."
        }
    }

    private func sessionContentTypeKind(for contentType: ContentType) -> String {
        switch contentType {
        case .text:
            return "text"
        case .image:
            return "image"
        case .binary:
            return "binary"
        case .excluded:
            return "excluded"
        }
    }

    private func sessionContentTypeDetail(for contentType: ContentType) -> String? {
        switch contentType {
        case .text(let isLarge):
            return isLarge ? "large" : "normal"
        case .image(let format):
            return format.rawValue
        case .binary(let viewer):
            switch viewer {
            case .hex: return "hex"
            case .external: return "external"
            case .placeholder: return "placeholder"
            }
        case .excluded(let reason):
            switch reason {
            case .tooLarge: return "tooLarge"
            case .binary: return "binary"
            case .excludedExtension: return "excludedExtension"
            }
        }
    }

    private func restoredContentType(for tabState: ProjectSessionTabState, fileURL: URL) -> ContentType {
        switch tabState.contentTypeKind {
        case "text":
            return .text(isLarge: tabState.contentTypeDetail == "large")
        case "image":
            return .image(format: ImageFormat(rawValue: tabState.contentTypeDetail ?? "png") ?? .png)
        case "binary":
            let viewer: BinaryViewer
            switch tabState.contentTypeDetail {
            case "hex": viewer = .hex
            case "external": viewer = .external
            default: viewer = .placeholder
            }
            return .binary(viewer: viewer)
        case "excluded":
            let reason: ExcludedReason
            switch tabState.contentTypeDetail {
            case "binary": reason = .binary
            case "excludedExtension": reason = .excludedExtension
            default: reason = .tooLarge
            }
            return .excluded(reason: reason)
        default:
            return fileService.detectContentType(at: fileURL, settings: configService.settings.fileHandling)
        }
    }

    func selectTab(at index: Int) {
        guard openTabs.indices.contains(index) else { return }
        dismissGitDiffWorkspace()
        selectedTabIndex = index
        if let filePath = openTabs[index].filePath {
            recordQuickOpenAccess(for: filePath)
        }
        persistSession()
    }

    @discardableResult
    func closeTab(at index: Int, confirmUnsavedChanges: Bool = true) -> Bool {
        guard openTabs.indices.contains(index) else { return false }
        let shouldCloseGitDiff = isGitDiffWorkspaceVisible && selectedTabIndex == index

        if confirmUnsavedChanges && openTabs[index].isDirty {
            let response = ui.confirm(
                "Close \(openTabs[index].fileName)?",
                "This file has unsaved changes.",
                .warning,
                ["Save", "Discard Changes", "Cancel"]
            )

            switch response {
            case .alertFirstButtonReturn:
                guard saveTab(at: index) else { return false }
            case .alertSecondButtonReturn:
                break
            default:
                return false
            }
        }

        if shouldCloseGitDiff {
            closeGitDiffPanel()
        }

        if let url = openTabs[index].filePath {
            fileWatcher.unwatch(url: url)
        }

        // Notify LSP service of document close
        if openTabs[index].contentType.isText, let uri = openTabs[index].documentURI {
            lspService.documentClosed(uri: uri, language: openTabs[index].language)
        }

        openTabs.remove(at: index)

        if openTabs.isEmpty {
            selectedTabIndex = nil
        } else if let selectedTabIndex {
            if selectedTabIndex == index {
                self.selectedTabIndex = min(index, openTabs.count - 1)
            } else if selectedTabIndex > index {
                self.selectedTabIndex = selectedTabIndex - 1
            }
        }

        persistSession()
        return true
    }

    func saveCurrentFile() {
        guard let selectedTabIndex else { return }
        _ = saveTab(at: selectedTabIndex)
    }

    @discardableResult
    func saveAllTabs(indices: [Int]? = nil) -> Bool {
        let indicesToSave = (indices ?? Array(openTabs.indices)).sorted()
        for index in indicesToSave where openTabs.indices.contains(index) && openTabs[index].isDirty {
            guard saveTab(at: index) else { return false }
        }
        return true
    }

    func updateTabContent(_ content: String) {
        guard let selectedTabIndex, openTabs.indices.contains(selectedTabIndex) else { return }
        guard openTabs[selectedTabIndex].contentType.isText else { return }
        openTabs[selectedTabIndex].content = content
        openTabs[selectedTabIndex].isDirty = content != openTabs[selectedTabIndex].originalContent
        invalidateWorkspaceSymbolCache()

        openTabs[selectedTabIndex].documentVersion += 1
        if let uri = openTabs[selectedTabIndex].documentURI {
            lspService.documentChanged(
                uri: uri,
                language: openTabs[selectedTabIndex].language,
                text: content
            )
        }

        if configService.settings.editor.autoSaveEnabled {
            scheduleAutoSave()
        }

        persistSession()
    }

    func updateCursorPosition(line: Int, column: Int) {
        guard let selectedTabIndex, openTabs.indices.contains(selectedTabIndex) else { return }
        let previousLine = openTabs[selectedTabIndex].cursorPosition.line
        openTabs[selectedTabIndex].cursorPosition = CursorPosition(line: line, column: column)
        synchronizeActiveDiagnosticSelection()
        if previousLine != line {
            refreshCurrentLineBlame()
        }
    }

    func updateEditorVisibleLineRange(startLine: Int, endLine: Int) {
        guard startLine > 0, endLine >= startLine else {
            editorVisibleLineRange = nil
            return
        }

        editorVisibleLineRange = startLine...endLine
    }

    func jumpToLineInSelectedTab(_ line: Int) {
        guard let selectedTabIndex, openTabs.indices.contains(selectedTabIndex) else { return }
        let targetLine = max(line, 1)
        updateCursorPosition(line: targetLine, column: 1)
        openTabs[selectedTabIndex].pendingLineJump = targetLine
    }

    func toggleQuickOpen() {
        if activePalette == .quickOpen {
            activePalette = nil
            return
        }

        activePalette = .quickOpen
        quickOpenQuery = ""
    }

    func beginGoToLine() {
        guard hasOpenFile else { return }
        activePalette = .quickOpen
        let currentLine = max(selectedTab?.cursorPosition.line ?? 1, 1)
        quickOpenQuery = ":\(currentLine)"
    }

    func beginWorkspaceSymbolSearch() {
        guard rootDirectory != nil else { return }
        activePalette = .quickOpen
        quickOpenQuery = "#"
    }

    func beginWorkspaceProblemSearch() {
        guard hasWorkspaceDiagnostics else { return }
        activePalette = .quickOpen
        quickOpenQuery = "!"
    }

    func executeQuickOpenItem(_ item: QuickOpenItem) {
        switch item.kind {
        case .file(let file):
            openFile(at: file.path)
        case .lineJump(let fileURL, _, _, let line):
            if let fileURL {
                openFile(at: fileURL)
            }
            guard let selectedTabIndex, openTabs.indices.contains(selectedTabIndex) else { return }
            openTabs[selectedTabIndex].pendingLineJump = line
        case .symbol(let symbol):
            openFile(at: symbol.fileURL)
            guard let selectedTabIndex, openTabs.indices.contains(selectedTabIndex) else { return }
            openTabs[selectedTabIndex].pendingLineJump = symbol.line
        case .problem(let diagnostic):
            openWorkspaceDiagnostic(diagnostic)
        }
    }

    func executeCommandPaletteAction(_ action: CommandPaletteAction) {
        let previousPalette = activePalette
        action.action()

        if activePalette == previousPalette {
            closeCommandPalette()
        }
    }

    func toggleCommandPalette() {
        if activePalette == .commandPalette {
            activePalette = nil
            return
        }

        activePalette = .commandPalette
        commandPaletteQuery = ""
    }

    func closeCommandPalette() {
        activePalette = nil
    }

    func showExplorerSidebar() {
        sidebarMode = .explorer
    }

    func showSearchSidebar() {
        let wasShowingSearch = sidebarMode == .search
        sidebarMode = .search
        if wasShowingSearch,
           !projectSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            performProjectSearch()
        }
    }

    func showSourceControlSidebar() {
        sidebarMode = .sourceControl
        refreshGitState()
    }

    func showDebugSidebar() {
        sidebarMode = .debug
    }

    func toggleShowHiddenFiles() {
        showHiddenFiles.toggle()
    }

    private func copyStringToPasteboard(_ value: String?) {
        guard let value, !value.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
    }

    private func sortedCurrentDiagnostics() -> [LSPDiagnostic] {
        currentTabDiagnostics.sorted { lhs, rhs in
            let lhsPosition = diagnosticSortPosition(for: lhs)
            let rhsPosition = diagnosticSortPosition(for: rhs)
            if lhsPosition.line != rhsPosition.line {
                return lhsPosition.line < rhsPosition.line
            }
            if lhsPosition.column != rhsPosition.column {
                return lhsPosition.column < rhsPosition.column
            }
            let lhsSeverity = lhs.severity?.rawValue ?? Int.max
            let rhsSeverity = rhs.severity?.rawValue ?? Int.max
            if lhsSeverity != rhsSeverity {
                return lhsSeverity < rhsSeverity
            }
            return lhs.message.localizedCaseInsensitiveCompare(rhs.message) == .orderedAscending
        }
    }

    func diagnosticSortPosition(for diagnostic: LSPDiagnostic) -> (line: Int, column: Int) {
        (diagnostic.range.start.line, diagnostic.range.start.character)
    }

    private func compareWorkspaceDiagnostics(_ lhs: WorkspaceDiagnosticItem, _ rhs: WorkspaceDiagnosticItem) -> Bool {
        if lhs.displayPath != rhs.displayPath {
            return lhs.displayPath.localizedStandardCompare(rhs.displayPath) == .orderedAscending
        }

        if lhs.lineNumber != rhs.lineNumber {
            return lhs.lineNumber < rhs.lineNumber
        }

        if lhs.columnNumber != rhs.columnNumber {
            return lhs.columnNumber < rhs.columnNumber
        }

        let lhsSeverity = lhs.diagnostic.severity?.rawValue ?? Int.max
        let rhsSeverity = rhs.diagnostic.severity?.rawValue ?? Int.max
        if lhsSeverity != rhsSeverity {
            return lhsSeverity < rhsSeverity
        }

        return lhs.diagnostic.message.localizedCaseInsensitiveCompare(rhs.diagnostic.message) == .orderedAscending
    }

    func currentProblemReferencePosition() -> (line: Int, column: Int) {
        let currentLine = max((selectedTab?.cursorPosition.line ?? 1) - 1, 0)
        let currentColumn = max((selectedTab?.cursorPosition.column ?? 1) - 1, 0)
        return (line: currentLine, column: currentColumn)
    }

    func inferredCurrentDiagnostic(in diagnostics: [LSPDiagnostic]) -> LSPDiagnostic? {
        guard !diagnostics.isEmpty else { return nil }
        let currentPosition = currentProblemReferencePosition()
        return diagnostics.last(where: { diagnostic in
            let position = diagnosticSortPosition(for: diagnostic)
            return position.line < currentPosition.line
                || (position.line == currentPosition.line && position.column <= currentPosition.column)
        }) ?? diagnostics.first
    }

    func inferredWorkspaceDiagnostic(in diagnostics: [WorkspaceDiagnosticItem]) -> WorkspaceDiagnosticItem? {
        guard !diagnostics.isEmpty else { return nil }

        if let selectedFilePath = selectedTab?.filePath.map(normalizedPath(for:)) {
            let sameFileDiagnostics = diagnostics.filter { normalizedPath(for: $0.fileURL) == selectedFilePath }
            if !sameFileDiagnostics.isEmpty {
                let currentPosition = currentProblemReferencePosition()
                return sameFileDiagnostics.last(where: { diagnostic in
                    let position = (line: diagnostic.lineNumber - 1, column: diagnostic.columnNumber - 1)
                    return position.line < currentPosition.line
                        || (position.line == currentPosition.line && position.column <= currentPosition.column)
                }) ?? sameFileDiagnostics.first
            }
        }

        return diagnostics.first
    }

    func synchronizeActiveDiagnosticSelection() {
        activeCurrentDiagnosticID = inferredCurrentDiagnostic(in: orderedCurrentTabDiagnostics)?.id
        activeWorkspaceDiagnosticID = inferredWorkspaceDiagnostic(in: orderedWorkspaceDiagnostics)?.id
    }

    private func navigatedBreakpoint(step: Int) -> Breakpoint? {
        let sortedBreakpoints = sortedNavigableBreakpoints()
        guard !sortedBreakpoints.isEmpty else { return nil }

        let currentFilePath = selectedTab?.filePath.map(normalizedPath(for:))
        let currentLine = max(selectedTab?.cursorPosition.line ?? 1, 1)

        if step >= 0 {
            return sortedBreakpoints.first(where: { breakpoint in
                guard let currentFilePath else { return true }
                let breakpointPath = normalizedPath(for: breakpoint.fileURL)
                return breakpointPath.localizedStandardCompare(currentFilePath) == .orderedDescending
                    || (breakpointPath == currentFilePath && breakpoint.line > currentLine)
            }) ?? sortedBreakpoints.first
        }

        return sortedBreakpoints.last(where: { breakpoint in
            guard let currentFilePath else { return true }
            let breakpointPath = normalizedPath(for: breakpoint.fileURL)
            return breakpointPath.localizedStandardCompare(currentFilePath) == .orderedAscending
                || (breakpointPath == currentFilePath && breakpoint.line < currentLine)
        }) ?? sortedBreakpoints.last
    }

    private func sortedNavigableBreakpoints() -> [Breakpoint] {
        breakpoints
            .filter(\.isEnabled)
            .sorted { lhs, rhs in
                let lhsPath = normalizedPath(for: lhs.fileURL)
                let rhsPath = normalizedPath(for: rhs.fileURL)
                if lhsPath != rhsPath {
                    return lhsPath.localizedStandardCompare(rhsPath) == .orderedAscending
                }
                return lhs.line < rhs.line
            }
    }

    func removeBreakpoint(_ breakpoint: Breakpoint) {
        guard rootDirectory != nil else { return }
        breakpoints = breakpointStore.removeBreakpoint(breakpoint, for: rootDirectory)
        syncActiveDebugBreakpoints()
    }

    func clearPendingLineJump() {
        guard let selectedTabIndex, openTabs.indices.contains(selectedTabIndex) else { return }
        openTabs[selectedTabIndex].pendingLineJump = nil
    }

    private func scheduleAutoSave() {
        autoSaveTask?.cancel()
        let delayInNanoseconds = UInt64(configService.settings.editor.autoSaveDelay * 1_000_000_000)
        autoSaveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: delayInNanoseconds)
            guard !Task.isCancelled else { return }
            self?.autoSaveAllDirtyTabs()
        }
    }

    private func autoSaveAllDirtyTabs() {
        autoSaveTask = nil
        for index in openTabs.indices where openTabs[index].isDirty {
            _ = saveTab(at: index)
        }
    }

    private func handleExternalFileChange(at url: URL) {
        guard let tabIndex = openTabs.firstIndex(where: { $0.filePath == url }) else { return }

        let response = ui.confirm(
            "File Changed",
            "\(url.lastPathComponent) was changed externally. Reload?",
            .warning,
            ["Reload", "Ignore"]
        )

        if response == .alertFirstButtonReturn {
            reloadTab(at: tabIndex)
        }
    }

    private func reloadTab(at index: Int) {
        guard openTabs.indices.contains(index), let url = openTabs[index].filePath else { return }

        do {
            let fileHandling = configService.settings.fileHandling
            let contentType = fileService.detectContentType(at: url, settings: fileHandling)

            switch contentType {
            case .text:
                let document = try fileService.readDocument(at: url)
                openTabs[index].content = document.content
                openTabs[index].originalContent = document.content
                openTabs[index].documentMetadata = document.metadata
                openTabs[index].fileData = nil
            case .image:
                openTabs[index].content = ""
                openTabs[index].originalContent = ""
                openTabs[index].fileData = try fileService.readFileAsData(at: url)
                openTabs[index].documentMetadata = .utf8LF
            case .binary(let viewer):
                openTabs[index].content = ""
                openTabs[index].originalContent = ""
                openTabs[index].fileData = viewer == .hex ? try fileService.readFileAsData(at: url) : nil
                openTabs[index].documentMetadata = .utf8LF
            case .excluded(let reason):
                ui.alert("Unsupported File", excludedContentMessage(for: reason, fileURL: url, settings: fileHandling), .warning)
                return
            }

            openTabs[index].isDirty = false
            openTabs[index].contentType = contentType
            persistSession()
            refreshGitState()
            refreshCurrentLineBlame()
        } catch {
            ui.alert("Error", "Could not reload file: \(error.localizedDescription)", .warning)
        }
    }

    func deleteItem(_ item: FileItem) {
        let affectedIndices = affectedTabIndices(for: item.path, includeDescendants: item.isDirectory)
        guard resolveUnsavedChanges(
            for: affectedIndices,
            title: "Delete \(item.name)?",
            message: "Deleting this item will close any open tabs for it."
        ) else {
            return
        }

        do {
            try fileService.delete(at: item.path)
            pruneExpandedDirectoryPaths(removingDescendantsOf: item.path)
            breakpoints = breakpointStore.removeBreakpoints(
                inside: item.path,
                includeDescendants: item.isDirectory,
                for: rootDirectory
            )
            syncActiveDebugBreakpoints()
            closeTabs(at: affectedIndices, confirmUnsavedChanges: false)
            reloadFileTree()
            refreshGitState()
            persistSession()
        } catch {
            ui.alert("Error", "Could not delete: \(error.localizedDescription)", .warning)
        }
    }

    func renameItem(_ item: FileItem, to newName: String) {
        do {
            let newURL = try fileService.rename(from: item.path, to: newName)
            updateExpandedDirectoryPaths(moving: item.path, to: newURL)
            updateOpenTabPaths(moving: item.path, to: newURL, includeDescendants: item.isDirectory)
            breakpoints = breakpointStore.moveBreakpoints(
                from: item.path,
                to: newURL,
                includeDescendants: item.isDirectory,
                for: rootDirectory
            )
            syncActiveDebugBreakpoints()
            reloadFileTree()
            refreshGitState()
            persistSession()
        } catch {
            ui.alert("Error", "Could not rename: \(error.localizedDescription)", .warning)
        }
    }

    func duplicateItem(_ item: FileItem) {
        do {
            let newURL = try fileService.duplicate(at: item.path)
            reloadFileTree()
            openFile(at: newURL)
            refreshGitState()
        } catch {
            ui.alert("Error", "Could not duplicate: \(error.localizedDescription)", .warning)
        }
    }

    func toggleExpand(_ item: FileItem) {
        let targetPath = normalizedPath(for: item.path)
        let shouldBeExpanded = !item.isExpanded

        fileTree = toggleExpansion(in: fileTree, targetPath: targetPath, shouldExpand: shouldBeExpanded)

        if shouldBeExpanded {
            expandedDirectoryPaths.insert(targetPath)
        } else {
            expandedDirectoryPaths = expandedDirectoryPaths.filter { $0 != targetPath && !$0.hasPrefix(targetPath + "/") }
        }

        persistSession()
    }

    private func toggleExpansion(in items: [FileItem], targetPath: String, shouldExpand: Bool) -> [FileItem] {
        items.map { item in
            let itemPath = normalizedPath(for: item.path)
            if itemPath == targetPath {
                var updatedItem = item
                updatedItem.isExpanded = shouldExpand
                return updatedItem
            } else if !item.children.isEmpty {
                let updatedChildren = toggleExpansion(in: item.children, targetPath: targetPath, shouldExpand: shouldExpand)
                var updatedItem = item
                updatedItem.children = updatedChildren
                return updatedItem
            }
            return item
        }
    }

    func canCloseWindow() -> Bool {
        prepareForSessionTransition(title: "Quit Rosewood", message: "Do you want to save changes before closing the window?")
    }

    private func flattenFileTree(_ items: [FileItem]) -> [FileItem] {
        var result: [FileItem] = []
        for item in items {
            if !item.isDirectory {
                result.append(item)
            }
            result.append(contentsOf: flattenFileTree(item.children))
        }
        return result
    }

    private func handleSidebarModeChange(from oldValue: SidebarMode) {
        guard oldValue != sidebarMode else { return }

        if sidebarMode != .search {
            projectSearchDebounceTask?.cancel()
            return
        }

        let trimmedQuery = projectSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard rootDirectory != nil, !trimmedQuery.isEmpty else { return }
        performProjectSearch()
    }

    private func quickOpenLineJumpItems(for query: String) -> [QuickOpenItem] {
        guard let request = quickOpenLineJumpRequest(from: query),
              let selectedTab else {
            return []
        }

        let fileURL = selectedTab.filePath
        let displayPath = fileURL.map(relativeDisplayPath(for:)) ?? selectedTab.fileName
        return [
            QuickOpenItem(
                kind: .lineJump(
                    fileURL: fileURL,
                    fileName: selectedTab.fileName,
                    displayPath: displayPath,
                    line: request.line
                ),
                title: "Go to Line \(request.line)",
                subtitle: displayPath,
                detailText: nil,
                iconName: "text.line.first.and.arrowtriangle.forward",
                badge: "Line",
                score: 1_300,
                originalIndex: 0
            )
        ]
    }

    private func quickOpenFileLineItems(for request: QuickOpenFileLineRequest) -> [QuickOpenItem] {
        flatFileList.enumerated().compactMap { index, item in
            guard !item.isDirectory else { return nil }

            let displayPath = relativeDisplayPath(for: item.path)
            guard let score = quickOpenMatchScore(for: item, displayPath: displayPath, query: request.fileQuery) else {
                return nil
            }

            return QuickOpenItem(
                kind: .lineJump(
                    fileURL: item.path,
                    fileName: item.name,
                    displayPath: displayPath,
                    line: request.line
                ),
                title: "\(item.name):\(request.line)",
                subtitle: displayPath,
                detailText: nil,
                iconName: item.iconName,
                badge: "Line",
                score: score + 140,
                originalIndex: index
            )
        }
        .sorted(by: compareQuickOpenItems)
    }

    private func quickOpenWorkspaceSymbolSections(for query: String) -> [QuickOpenSection] {
        let symbolQuery = String(query.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !symbolQuery.isEmpty else { return [] }

        let currentFilePath = selectedTab?.filePath.map(normalizedPath(for:))
        let symbolItems = workspaceSymbols()
            .compactMap { quickOpenWorkspaceSymbolItem(for: $0, query: symbolQuery) }

        let currentFileItems = symbolItems
            .filter { item in
                guard case .symbol(let symbol) = item.kind,
                      let currentFilePath else {
                    return false
                }
                return normalizedPath(for: symbol.fileURL) == currentFilePath
            }
            .sorted(by: compareQuickOpenItems)

        let workspaceItems = symbolItems
            .filter { item in
                guard case .symbol(let symbol) = item.kind,
                      let currentFilePath else {
                    return true
                }
                return normalizedPath(for: symbol.fileURL) != currentFilePath
            }
            .sorted(by: compareQuickOpenItems)

        var sections: [QuickOpenSection] = []
        if !currentFileItems.isEmpty {
            sections.append(QuickOpenSection(title: "Current File", items: currentFileItems))
        }
        if !workspaceItems.isEmpty {
            sections.append(
                QuickOpenSection(
                    title: currentFileItems.isEmpty ? "Symbols" : "Workspace",
                    items: workspaceItems
                )
            )
        }

        return sections
    }

    private func quickOpenWorkspaceProblemSections(for query: String) -> [QuickOpenSection] {
        let problemQuery = quickOpenWorkspaceProblemQuery(from: query)
        let currentFilePath = selectedTab?.filePath.map(normalizedPath(for:))
        let problemItems = orderedWorkspaceDiagnostics.enumerated()
            .compactMap { index, diagnostic in
                quickOpenWorkspaceProblemItem(
                    for: diagnostic,
                    query: problemQuery.searchText,
                    severityFilter: problemQuery.severity,
                    originalIndex: index
                )
            }

        let currentFileItems = problemItems
            .filter { item in
                guard case .problem(let diagnostic) = item.kind,
                      let currentFilePath else {
                    return false
                }
                return normalizedPath(for: diagnostic.fileURL) == currentFilePath
            }
            .sorted(by: compareQuickOpenItems)

        let workspaceItems = problemItems
            .filter { item in
                guard case .problem(let diagnostic) = item.kind,
                      let currentFilePath else {
                    return true
                }
                return normalizedPath(for: diagnostic.fileURL) != currentFilePath
            }
            .sorted(by: compareQuickOpenItems)

        switch problemQuery.scope {
        case .currentFile:
            return currentFileItems.isEmpty ? [] : [QuickOpenSection(title: "Current File", items: currentFileItems)]
        case .workspace:
            return workspaceItems.isEmpty ? [] : [QuickOpenSection(title: "Workspace", items: workspaceItems)]
        case nil:
            var sections: [QuickOpenSection] = []
            if !currentFileItems.isEmpty {
                sections.append(QuickOpenSection(title: "Current File", items: currentFileItems))
            }
            if !workspaceItems.isEmpty {
                sections.append(
                    QuickOpenSection(
                        title: currentFileItems.isEmpty ? "Problems" : "Workspace",
                        items: workspaceItems
                    )
                )
            }

            return sections
        }
    }

    private func quickOpenWorkspaceSymbolItem(for symbol: WorkspaceSymbolMatch, query: String) -> QuickOpenItem? {
        guard let score = quickOpenWorkspaceSymbolScore(for: symbol, query: query) else {
            return nil
        }

        return QuickOpenItem(
            kind: .symbol(symbol),
            title: symbol.name,
            subtitle: "\(symbol.displayPath):\(symbol.line)",
            detailText: symbol.lineText,
            iconName: symbol.iconName,
            badge: symbol.kindDisplayName,
            score: score,
            originalIndex: symbol.originalIndex
        )
    }

    private func quickOpenWorkspaceProblemItem(
        for diagnostic: WorkspaceDiagnosticItem,
        query: String,
        severityFilter: DiagnosticSeverity?,
        originalIndex: Int
    ) -> QuickOpenItem? {
        guard let score = quickOpenWorkspaceProblemScore(
            for: diagnostic,
            query: query,
            severityFilter: severityFilter
        ) else {
            return nil
        }

        return QuickOpenItem(
            kind: .problem(diagnostic),
            title: diagnostic.diagnostic.message,
            subtitle: "\(diagnostic.displayPath):\(diagnostic.lineNumber)",
            detailText: diagnostic.lineText,
            iconName: quickOpenWorkspaceProblemIconName(for: diagnostic.diagnostic.severity),
            badge: quickOpenWorkspaceProblemBadge(for: diagnostic.diagnostic.severity),
            score: score,
            originalIndex: originalIndex
        )
    }

    private func quickOpenLineJumpRequest(from query: String) -> QuickOpenLineJumpRequest? {
        guard query.hasPrefix(":") else { return nil }
        let linePortion = String(query.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let line = Int(linePortion), line > 0 else { return nil }
        return QuickOpenLineJumpRequest(line: line)
    }

    private func quickOpenFileLineRequest(from query: String) -> QuickOpenFileLineRequest? {
        guard !query.hasPrefix(":"),
              let separatorIndex = query.lastIndex(of: ":"),
              separatorIndex < query.index(before: query.endIndex) else {
            return nil
        }

        let fileQuery = String(query[..<separatorIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        let linePortion = String(query[query.index(after: separatorIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !fileQuery.isEmpty,
              let line = Int(linePortion),
              line > 0 else {
            return nil
        }

        return QuickOpenFileLineRequest(fileQuery: fileQuery, line: line)
    }

    private func quickOpenMatchScore(for item: FileItem, displayPath: String, query: String) -> Int? {
        let normalizedFileName = item.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let normalizedDisplayPath = displayPath.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let normalizedQuery = query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let openTabBoost = quickOpenOpenTabBoost(for: item.path)
        let recencyBoost = quickOpenRecencyBoost(for: item.path)
        let querySegments = normalizedQuery
            .split(whereSeparator: { $0 == "/" || $0 == "\\" || $0 == " " })
            .map(String.init)
            .filter { !$0.isEmpty }
        var bestScore: Int?

        guard !normalizedQuery.isEmpty else {
            return openTabBoost + recencyBoost
        }

        if normalizedFileName == normalizedQuery {
            bestScore = max(bestScore ?? .min, 1_000)
        }

        if normalizedFileName.hasPrefix(normalizedQuery) {
            bestScore = max(bestScore ?? .min, 860)
        }

        if normalizedFileName.contains(normalizedQuery) {
            bestScore = max(bestScore ?? .min, 720)
        }

        if normalizedDisplayPath == normalizedQuery {
            bestScore = max(bestScore ?? .min, 900)
        }

        if normalizedDisplayPath.hasPrefix(normalizedQuery) {
            bestScore = max(bestScore ?? .min, 640)
        }

        if normalizedDisplayPath.contains(normalizedQuery) {
            bestScore = max(bestScore ?? .min, 420)
        }

        if let pathSegmentScore = quickOpenPathSegmentScore(
            for: normalizedDisplayPath,
            querySegments: querySegments
        ) {
            bestScore = max(bestScore ?? .min, pathSegmentScore)
        }

        guard let bestScore else { return nil }
        return bestScore + openTabBoost + recencyBoost
    }

    private func quickOpenPathSegmentScore(for displayPath: String, querySegments: [String]) -> Int? {
        guard !querySegments.isEmpty else { return nil }
        let components = displayPath.split(separator: "/").map(String.init)
        guard !components.isEmpty else { return nil }

        var searchStart = 0
        var score = querySegments.count > 1 ? 420 : 0

        for querySegment in querySegments {
            var bestMatch: (index: Int, score: Int)?

            for index in searchStart..<components.count {
                let component = components[index]
                let componentScore: Int
                if component == querySegment {
                    componentScore = 210
                } else if component.hasPrefix(querySegment) {
                    componentScore = 170
                } else if component.contains(querySegment) {
                    componentScore = 120
                } else {
                    continue
                }

                if let bestMatch, bestMatch.score >= componentScore {
                    continue
                }

                bestMatch = (index, componentScore)
            }

            guard let bestMatch else { return nil }
            score += bestMatch.score
            score -= bestMatch.index * 6
            searchStart = bestMatch.index + 1
        }

        return score
    }

    private func quickOpenWorkspaceSymbolScore(for symbol: WorkspaceSymbolMatch, query: String) -> Int? {
        let normalizedName = symbol.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let normalizedPath = symbol.displayPath.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let normalizedQuery = query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let fileBoost = quickOpenOpenTabBoost(for: symbol.fileURL)
            + quickOpenRecencyBoost(for: symbol.fileURL)
            + quickOpenCurrentFileSymbolBoost(for: symbol.fileURL)

        guard !normalizedQuery.isEmpty else { return nil }

        if normalizedName == normalizedQuery {
            return 1_060 + fileBoost
        }

        if normalizedName.hasPrefix(normalizedQuery) {
            return 900 + fileBoost
        }

        if normalizedName.contains(normalizedQuery) {
            return 760 + fileBoost
        }

        if normalizedPath.contains(normalizedQuery) {
            return 420 + fileBoost
        }

        return nil
    }

    private func quickOpenWorkspaceProblemScore(
        for diagnostic: WorkspaceDiagnosticItem,
        query: String,
        severityFilter: DiagnosticSeverity?
    ) -> Int? {
        let normalizedQuery = query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let normalizedMessage = diagnostic.diagnostic.message
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let normalizedLineText = diagnostic.lineText
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let normalizedPath = diagnostic.displayPath
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let severityLabel = quickOpenWorkspaceProblemBadge(for: diagnostic.diagnostic.severity).lowercased()
        let fileBoost = quickOpenOpenTabBoost(for: diagnostic.fileURL)
            + quickOpenRecencyBoost(for: diagnostic.fileURL)
            + quickOpenCurrentFileProblemBoost(for: diagnostic.fileURL)
        let severityBoost = quickOpenWorkspaceProblemSeverityBoost(for: diagnostic.diagnostic.severity)

        if let severityFilter, diagnostic.diagnostic.severity != severityFilter {
            return nil
        }

        guard !normalizedQuery.isEmpty else {
            return severityBoost + fileBoost
        }

        if normalizedMessage == normalizedQuery {
            return 1_020 + severityBoost + fileBoost
        }

        if normalizedMessage.hasPrefix(normalizedQuery) {
            return 900 + severityBoost + fileBoost
        }

        if normalizedMessage.contains(normalizedQuery) {
            return 760 + severityBoost + fileBoost
        }

        if normalizedLineText.contains(normalizedQuery) {
            return 620 + severityBoost + fileBoost
        }

        if normalizedPath.contains(normalizedQuery) {
            return 520 + severityBoost + fileBoost
        }

        if severityLabel.contains(normalizedQuery) {
            return 440 + severityBoost + fileBoost
        }

        return nil
    }

    private func quickOpenWorkspaceProblemQuery(from query: String) -> WorkspaceProblemQuery {
        let trimmedQuery = String(query.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return WorkspaceProblemQuery(
                searchText: "",
                severity: nil,
                severityLabel: nil,
                scope: nil,
                scopeLabel: nil
            )
        }

        var severity: DiagnosticSeverity?
        var scope: WorkspaceProblemScope?
        var remainingComponents: [Substring] = []
        var parsingFilters = true

        for component in trimmedQuery.split(whereSeparator: \.isWhitespace) {
            let token = String(component).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)

            if parsingFilters, severity == nil, let matchedSeverity = workspaceProblemSeverity(for: token) {
                severity = matchedSeverity
                continue
            }

            if parsingFilters, scope == nil, let matchedScope = workspaceProblemScope(for: token) {
                scope = matchedScope
                continue
            }

            parsingFilters = false
            remainingComponents.append(component)
        }

        let remainingQuery = remainingComponents.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return WorkspaceProblemQuery(
            searchText: remainingQuery,
            severity: severity,
            severityLabel: severity.map { quickOpenWorkspaceProblemBadge(for: $0).lowercased() },
            scope: scope,
            scopeLabel: scope.map(\.emptyStateLabel)
        )
    }

    private func workspaceProblemSeverity(for token: String) -> DiagnosticSeverity? {
        switch token {
        case "error", "errors", "err":
            return .error
        case "warning", "warnings", "warn":
            return .warning
        case "info", "information":
            return .information
        case "hint", "hints":
            return .hint
        default:
            return nil
        }
    }

    private func workspaceProblemScope(for token: String) -> WorkspaceProblemScope? {
        switch token {
        case "current", "current-file", "currentfile", "here":
            return .currentFile
        case "workspace", "project", "all":
            return .workspace
        default:
            return nil
        }
    }

    private func problemFilterToken(for severity: DiagnosticSeverity) -> String {
        switch severity {
        case .error:
            return "error"
        case .warning:
            return "warning"
        case .information:
            return "info"
        case .hint:
            return "hint"
        }
    }

    private func quickOpenWorkspaceProblemEmptyStateText(for query: WorkspaceProblemQuery) -> String {
        let noun = query.severityLabel.map { "\($0)s" } ?? "problems"
        if let scopeLabel = query.scopeLabel {
            return "No matching \(scopeLabel) \(noun)."
        }
        return "No matching \(noun)."
    }

    private func quickOpenCurrentFileSymbolBoost(for fileURL: URL) -> Int {
        guard let currentFileURL = selectedTab?.filePath else { return 0 }
        return normalizedPath(for: currentFileURL) == normalizedPath(for: fileURL) ? 180 : 0
    }

    private func quickOpenCurrentFileProblemBoost(for fileURL: URL) -> Int {
        guard let currentFileURL = selectedTab?.filePath else { return 0 }
        return normalizedPath(for: currentFileURL) == normalizedPath(for: fileURL) ? 180 : 0
    }

    private func quickOpenWorkspaceProblemSeverityBoost(for severity: DiagnosticSeverity?) -> Int {
        switch severity {
        case .error:
            return 220
        case .warning:
            return 120
        case .information:
            return 60
        case .hint:
            return 30
        case nil:
            return 0
        }
    }

    private func quickOpenWorkspaceProblemBadge(for severity: DiagnosticSeverity?) -> String {
        switch severity {
        case .error:
            return "Error"
        case .warning:
            return "Warning"
        case .information:
            return "Info"
        case .hint:
            return "Hint"
        case nil:
            return "Problem"
        }
    }

    private func quickOpenWorkspaceProblemIconName(for severity: DiagnosticSeverity?) -> String {
        switch severity {
        case .error:
            return "xmark.octagon"
        case .warning:
            return "exclamationmark.triangle"
        case .information:
            return "info.circle"
        case .hint:
            return "lightbulb"
        case nil:
            return "exclamationmark.bubble"
        }
    }

    private func quickOpenOpenTabBoost(for fileURL: URL) -> Int {
        let normalizedFilePath = normalizedPath(for: fileURL)

        if let selectedTab,
           let selectedFilePath = selectedTab.filePath,
           normalizedPath(for: selectedFilePath) == normalizedFilePath {
            return 120
        }

        if openTabs.contains(where: {
            guard let filePath = $0.filePath else { return false }
            return normalizedPath(for: filePath) == normalizedFilePath
        }) {
            return 60
        }

        return 0
    }

    private func quickOpenRecencyBoost(for fileURL: URL) -> Int {
        let normalizedFilePath = normalizedPath(for: fileURL)
        guard let accessStamp = quickOpenRecentAccessByPath[normalizedFilePath] else { return 0 }
        let distance = max(quickOpenAccessSequence - accessStamp, 0)
        return max(0, 90 - min(distance, 8) * 10)
    }

    private func recordQuickOpenAccess(for fileURL: URL) {
        quickOpenAccessSequence += 1
        quickOpenRecentAccessByPath[normalizedPath(for: fileURL)] = quickOpenAccessSequence
    }

    private func compareQuickOpenItems(_ lhs: QuickOpenItem, _ rhs: QuickOpenItem) -> Bool {
        if lhs.score != rhs.score {
            return lhs.score > rhs.score
        }

        let pathComparison = lhs.subtitle.localizedStandardCompare(rhs.subtitle)
        if pathComparison != .orderedSame {
            return pathComparison == .orderedAscending
        }

        let titleComparison = lhs.title.localizedStandardCompare(rhs.title)
        if titleComparison != .orderedSame {
            return titleComparison == .orderedAscending
        }

        return lhs.originalIndex < rhs.originalIndex
    }

    @discardableResult
    private func saveTab(at index: Int) -> Bool {
        guard openTabs.indices.contains(index), let url = openTabs[index].filePath else { return false }
        guard openTabs[index].contentType.isText else { return true }

        do {
            try fileService.writeDocument(content: openTabs[index].content, metadata: openTabs[index].documentMetadata, to: url)
            openTabs[index].originalContent = openTabs[index].content
            openTabs[index].isDirty = false

            if openTabs[index].contentType.isText, let uri = openTabs[index].documentURI {
                lspService.documentSaved(uri: uri, language: openTabs[index].language)
            }

            persistSession()
            refreshGitState()
            refreshCurrentLineBlame()
            return true
        } catch {
            ui.alert("Error", "Could not save file: \(error.localizedDescription)", .warning)
            return false
        }
    }

    func prepareForSessionTransition(title: String, message: String) -> Bool {
        let dirtyIndices = openTabs.indices.filter { openTabs[$0].isDirty }
        guard !dirtyIndices.isEmpty else { return true }

        let response = ui.confirm(
            title,
            message,
            .warning,
            ["Save All", "Discard Changes", "Cancel"]
        )

        switch response {
        case .alertFirstButtonReturn:
            return saveAllTabs(indices: dirtyIndices)
        case .alertSecondButtonReturn:
            return true
        default:
            return false
        }
    }

    func resolveUnsavedChanges(for indices: [Int], title: String, message: String) -> Bool {
        let dirtyIndices = indices.filter { openTabs.indices.contains($0) && openTabs[$0].isDirty }
        guard !dirtyIndices.isEmpty else { return true }

        let response = ui.confirm(
            title,
            message,
            .warning,
            ["Save Affected Files", "Discard Changes", "Cancel"]
        )

        switch response {
        case .alertFirstButtonReturn:
            return saveAllTabs(indices: dirtyIndices)
        case .alertSecondButtonReturn:
            return true
        default:
            return false
        }
    }

    private func affectedTabIndices(for url: URL, includeDescendants: Bool) -> [Int] {
        openTabs.indices.filter { index in
            guard let filePath = openTabs[index].filePath else { return false }
            let normalizedFilePath = normalizedPath(for: filePath)
            let normalizedTargetPath = normalizedPath(for: url)
            if includeDescendants {
                return normalizedFilePath == normalizedTargetPath
                    || normalizedFilePath.hasPrefix(normalizedTargetPath + "/")
            }
            return normalizedFilePath == normalizedTargetPath
        }
    }

    private func closeTabs(at indices: [Int], confirmUnsavedChanges: Bool) {
        for index in indices.sorted(by: >) {
            _ = closeTab(at: index, confirmUnsavedChanges: confirmUnsavedChanges)
        }
    }

    func closeOtherTabs(except index: Int) {
        let indicesToClose = openTabs.indices.filter { $0 != index }
        closeTabs(at: Array(indicesToClose), confirmUnsavedChanges: true)
    }

    func closeAllTabs() {
        closeTabs(at: Array(openTabs.indices), confirmUnsavedChanges: true)
    }

    func closeTabsToTheRight(of index: Int) {
        let indicesToClose = openTabs.indices.filter { $0 > index }
        closeTabs(at: Array(indicesToClose), confirmUnsavedChanges: true)
    }

    func revealInFinder(tab: EditorTab) {
        guard let fileURL = tab.filePath else { return }
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }

    func copyFilePath(tab: EditorTab) -> String? {
        tab.filePath?.path
    }

    func relativeFilePath(tab: EditorTab) -> String? {
        guard let fileURL = tab.filePath, let root = rootDirectory else { return nil }
        let filePath = fileURL.path
        let rootPath = root.path
        guard filePath.hasPrefix(rootPath + "/") else { return filePath }
        return String(filePath.dropFirst(rootPath.count + 1))
    }

    func makeProjectReplaceTransaction(
        preview: ProjectReplacePreview,
        summary: ProjectReplaceSummary,
        snapshots: [ProjectReplaceFileSnapshot]
    ) -> ProjectReplaceTransaction? {
        guard summary.replacementCount > 0 else { return nil }

        let modifiedPaths = Set(summary.modifiedFiles.map(normalizedPath(for:)))
        let modifiedSnapshots = snapshots.filter { modifiedPaths.contains(normalizedPath(for: $0.fileURL)) }
        guard !modifiedSnapshots.isEmpty else { return nil }

        return ProjectReplaceTransaction(
            summary: preview.summary,
            searchQuery: preview.searchQuery,
            replacement: preview.replacement,
            replacementCount: summary.replacementCount,
            fileSnapshots: modifiedSnapshots
        )
    }

    func makeReferenceResult(for location: LSPLocation) -> ReferenceResult? {
        guard let fileURL = URL(string: location.uri), fileURL.isFileURL else { return nil }

        let line = location.range.start.line + 1
        let column = location.range.start.character + 1
        return ReferenceResult(
            location: location,
            fileURL: fileURL,
            path: relativeDisplayPath(for: fileURL),
            line: line,
            column: column,
            lineText: lineText(for: fileURL, lineNumber: line)
        )
    }

    func compareReferenceResults(_ lhs: ReferenceResult, _ rhs: ReferenceResult) -> Bool {
        if lhs.path != rhs.path {
            return lhs.path.localizedStandardCompare(rhs.path) == .orderedAscending
        }
        if lhs.line != rhs.line {
            return lhs.line < rhs.line
        }
        return lhs.column < rhs.column
    }

    func lineText(for fileURL: URL, lineNumber: Int) -> String {
        let contents: String?
        if let openTab = openTabs.first(where: {
            guard let filePath = $0.filePath else { return false }
            return normalizedPath(for: filePath) == normalizedPath(for: fileURL)
        }) {
            contents = openTab.content
        } else {
            contents = try? fileService.readFile(at: fileURL)
        }

        guard let contents else { return "" }
        let lines = contents.components(separatedBy: .newlines)
        guard lines.indices.contains(max(lineNumber - 1, 0)) else { return "" }
        return lines[max(lineNumber - 1, 0)].trimmingCharacters(in: .whitespaces)
    }

    func relativeDisplayPath(for fileURL: URL) -> String {
        guard let rootDirectory else { return fileURL.lastPathComponent }
        let filePath = fileURL.path
        let rootPath = rootDirectory.path
        guard filePath.hasPrefix(rootPath + "/") else { return fileURL.path }
        return String(filePath.dropFirst(rootPath.count + 1))
    }

    private func updateOpenTabPaths(moving oldURL: URL, to newURL: URL, includeDescendants: Bool) {
        for index in openTabs.indices {
            guard let filePath = openTabs[index].filePath else { continue }

            if filePath.path == oldURL.path {
                fileWatcher.unwatch(url: filePath)
                openTabs[index].filePath = newURL
                openTabs[index].fileName = newURL.lastPathComponent
                fileWatcher.watch(url: newURL)
                continue
            }

            guard includeDescendants, filePath.path.hasPrefix(oldURL.path + "/") else { continue }

            let suffix = filePath.path.dropFirst(oldURL.path.count)
            let updatedURL = URL(fileURLWithPath: newURL.path + suffix)
            fileWatcher.unwatch(url: filePath)
            openTabs[index].filePath = updatedURL
            openTabs[index].fileName = updatedURL.lastPathComponent
            fileWatcher.watch(url: updatedURL)
        }

        if let selectedTabIndex, !openTabs.indices.contains(selectedTabIndex) {
            self.selectedTabIndex = openTabs.isEmpty ? nil : 0
        }
    }

    private func pruneExpandedDirectoryPaths(removingDescendantsOf url: URL) {
        let normalized = normalizedPath(for: url)
        let prefix = normalized + "/"
        expandedDirectoryPaths = expandedDirectoryPaths.filter { path in
            path != normalized && !path.hasPrefix(prefix)
        }
    }

    private func updateExpandedDirectoryPaths(moving oldURL: URL, to newURL: URL) {
        let oldPath = normalizedPath(for: oldURL)
        let newPath = normalizedPath(for: newURL)
        let prefix = oldPath + "/"
        expandedDirectoryPaths = Set(expandedDirectoryPaths.map { path in
            guard path == oldPath || path.hasPrefix(prefix) else { return path }
            return newPath + path.dropFirst(oldPath.count)
        })
    }

    func revealActiveFileInExplorer() {
        guard let fileURL = selectedTab?.filePath else { return }
        revealInExplorer(fileURL)
        persistSession()
    }

    private func revealInExplorer(_ fileURL: URL) {
        guard let rootDirectory else { return }

        let rootStandardized = rootDirectory.standardizedFileURL
        let filePath = normalizedPath(for: fileURL)
        guard filePath.hasPrefix(rootStandardized.path + "/") else { return }

        var currentDirectory = fileURL.deletingLastPathComponent().standardizedFileURL
        while currentDirectory != rootStandardized, currentDirectory.path.hasPrefix(rootStandardized.path) {
            expandedDirectoryPaths.insert(normalizedPath(for: currentDirectory))
            currentDirectory.deleteLastPathComponent()
        }

        reloadFileTree()
    }

    func persistSession() {
        let session = ProjectSessionState(
            rootDirectoryPath: rootDirectory.map(normalizedPath(for:)),
            expandedDirectoryPaths: Array(expandedDirectoryPaths).sorted(),
            openTabs: openTabs.compactMap { tab in
                guard let filePath = tab.filePath else { return nil }
                return ProjectSessionTabState(
                    filePath: normalizedPath(for: filePath),
                    fileName: tab.fileName,
                    content: tab.content,
                    originalContent: tab.originalContent,
                    isDirty: tab.isDirty,
                    encodingRawValue: tab.documentMetadata.encodingRawValue,
                    encodingLabel: tab.documentMetadata.encodingLabel,
                    lineEndingRawValue: tab.documentMetadata.lineEnding.rawValue,
                    contentTypeKind: sessionContentTypeKind(for: tab.contentType),
                    contentTypeDetail: sessionContentTypeDetail(for: tab.contentType)
                )
            },
            selectedTabPath: selectedTab?.filePath.map(normalizedPath(for:))
        )

        guard let data = try? JSONEncoder().encode(session) else { return }
        sessionStore.set(data, forKey: sessionKey)
    }

    private func restoreSession() {
        bottomPanel = sessionStore.bool(forKey: debugPanelVisibilityKey) ? .debugConsole : nil

        guard let data = sessionStore.data(forKey: sessionKey),
              let session = try? JSONDecoder().decode(ProjectSessionState.self, from: data) else {
            return
        }

        if let rootDirectoryPath = session.rootDirectoryPath {
            let url = URL(fileURLWithPath: rootDirectoryPath)
            if FileManager.default.fileExists(atPath: url.path) {
                rootDirectory = url
            }
        }

        configService.setProjectRoot(rootDirectory)
        lspService.setProjectRoot(rootDirectory)

        expandedDirectoryPaths = Set(session.expandedDirectoryPaths.filter {
            FileManager.default.fileExists(atPath: $0)
        })
        reloadFileTree()

        openTabs = session.openTabs.compactMap { tabState in
            guard FileManager.default.fileExists(atPath: tabState.filePath) else { return nil }
            let fileURL = URL(fileURLWithPath: tabState.filePath)
            let contentType = restoredContentType(for: tabState, fileURL: fileURL)
            let fileData: Data?
            switch contentType {
            case .image, .binary(.hex):
                fileData = try? fileService.readFileAsData(at: fileURL)
            default:
                fileData = nil
            }

            return EditorTab(
                filePath: fileURL,
                fileName: tabState.fileName,
                content: contentType.isText ? tabState.content : "",
                originalContent: contentType.isText ? tabState.originalContent : "",
                isDirty: contentType.isText ? tabState.isDirty : false,
                documentMetadata: FileDocumentMetadata(
                    encoding: String.Encoding(rawValue: tabState.encodingRawValue ?? String.Encoding.utf8.rawValue),
                    encodingLabel: tabState.encodingLabel ?? String.Encoding.utf8.displayLabel,
                    lineEnding: LineEndingStyle(rawValue: tabState.lineEndingRawValue ?? LineEndingStyle.lf.rawValue) ?? .lf
                ),
                contentType: contentType,
                fileData: fileData
            )
        }
        for tab in openTabs {
            if let filePath = tab.filePath {
                fileWatcher.watch(url: filePath)
            }
        }

        if let selectedTabPath = session.selectedTabPath,
           let selectedIndex = openTabs.firstIndex(where: { $0.filePath.map(normalizedPath(for:)) == selectedTabPath }) {
            selectedTabIndex = selectedIndex
        } else {
            selectedTabIndex = openTabs.isEmpty ? nil : 0
        }

        refreshGitState()
    }

    private var normalizedIgnoredGitPaths: [String] {
        gitRepositoryStatus.ignoredPaths.map { ignoredPath in
            ignoredPath.hasSuffix("/") ? String(ignoredPath.dropLast()) : ignoredPath
        }
    }

    private func gitRelativePath(for fileURL: URL) -> String? {
        guard let repositoryRoot = gitRepositoryStatus.repositoryRoot else { return nil }
        let filePath = normalizedPath(for: fileURL)
        let rootPath = normalizedPath(for: repositoryRoot)
        guard filePath.hasPrefix(rootPath + "/") else { return nil }
        return String(filePath.dropFirst(rootPath.count + 1))
    }

    func normalizedPath(for url: URL) -> String {
        url.standardizedFileURL.path
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDirectory = ObjCBool(false)
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return isDirectory.boolValue
    }

    private func shouldPromptToCreateProjectConfig(for url: URL) -> Bool {
        guard !configService.hasProjectConfig() else { return false }
        return !projectConfigPromptedRoots.contains(normalizedPath(for: url))
    }

    private func markProjectConfigPromptHandled(for url: URL) {
        var promptedRoots = projectConfigPromptedRoots
        promptedRoots.insert(normalizedPath(for: url))
        sessionStore.set(Array(promptedRoots).sorted(), forKey: projectConfigPromptedRootsKey)
    }

    private var projectConfigPromptedRoots: Set<String> {
        Set(sessionStore.stringArray(forKey: projectConfigPromptedRootsKey) ?? [])
    }
}

struct ReferenceResult: Identifiable, Equatable {
    let location: LSPLocation
    let fileURL: URL
    let path: String
    let line: Int
    let column: Int
    let lineText: String

    var id: String {
        "\(location.uri):\(line):\(column)"
    }
}

struct CommandPaletteAction: Identifiable {
    let id: String
    let title: String
    let shortcut: String
    let category: String
    let aliases: [String]
    let detailText: String?
    let badge: String?
    let action: () -> Void
}

struct CommandPaletteSection: Identifiable {
    let title: String
    let actions: [CommandPaletteAction]

    var id: String {
        title
    }
}

struct CommandPaletteScope: Identifiable, Hashable {
    let id: String
    let title: String
    let category: String
    let queryToken: String
    let aliases: [String]
}

struct CommandPaletteQueryContext {
    let scope: CommandPaletteScope?
    let searchText: String
}

struct QuickOpenLineJumpRequest: Hashable {
    let line: Int
}

struct QuickOpenFileLineRequest: Hashable {
    let fileQuery: String
    let line: Int
}

struct WorkspaceProblemQuery: Hashable {
    let searchText: String
    let severity: DiagnosticSeverity?
    let severityLabel: String?
    let scope: WorkspaceProblemScope?
    let scopeLabel: String?
}

enum WorkspaceProblemScope: Hashable {
    case currentFile
    case workspace

    var queryToken: String {
        switch self {
        case .currentFile:
            return "current"
        case .workspace:
            return "workspace"
        }
    }

    var emptyStateLabel: String {
        switch self {
        case .currentFile:
            return "current-file"
        case .workspace:
            return "workspace"
        }
    }
}

enum QuickOpenProblemFilterKind: Hashable {
    case scope(WorkspaceProblemScope)
    case severity(DiagnosticSeverity)
}

struct QuickOpenProblemFilterHint: Identifiable, Hashable {
    let id: String
    let token: String
    let title: String
    let isActive: Bool
    let kind: QuickOpenProblemFilterKind
}

struct QuickOpenSection: Identifiable, Hashable {
    let title: String
    let items: [QuickOpenItem]

    var id: String {
        title
    }
}

struct QuickOpenItem: Identifiable, Hashable {
    enum Kind: Hashable {
        case file(FileItem)
        case lineJump(fileURL: URL?, fileName: String, displayPath: String, line: Int)
        case symbol(WorkspaceSymbolMatch)
        case problem(WorkspaceDiagnosticItem)
    }

    let kind: Kind
    let title: String
    let subtitle: String
    let detailText: String?
    let iconName: String
    let badge: String?
    let score: Int
    let originalIndex: Int

    var id: String {
        switch kind {
        case .file(let file):
            return file.id
        case .lineJump(let fileURL, let fileName, _, let line):
            let path = fileURL?.standardizedFileURL.path ?? fileName
            return "\(path):line:\(line)"
        case .symbol(let symbol):
            return symbol.id
        case .problem(let diagnostic):
            return diagnostic.id
        }
    }

    var file: FileItem? {
        guard case .file(let file) = kind else { return nil }
        return file
    }

    var displayPath: String {
        subtitle
    }
}

struct ProjectSearchFileGroup: Identifiable, Hashable {
    let filePath: URL
    let fileName: String
    let displayPath: String
    let results: [ProjectSearchResult]

    var id: String {
        filePath.standardizedFileURL.path
    }

    var matchCount: Int {
        results.reduce(0) { partialResult, result in
            partialResult + result.matchCount
        }
    }
}
