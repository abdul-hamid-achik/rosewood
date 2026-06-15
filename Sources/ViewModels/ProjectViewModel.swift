import Foundation
import SwiftUI
import Combine

struct ProjectViewModelUI {
    var openPanel: (_ canChooseDirectories: Bool, _ canChooseFiles: Bool, _ allowsMultipleSelection: Bool) -> URL?
    var openPanelURLs: (_ canChooseDirectories: Bool, _ canChooseFiles: Bool, _ allowsMultipleSelection: Bool) -> [URL]
    var savePanel: (_ defaultName: String, _ allowedTypes: [String]?) -> URL?
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
        openPanelURLs: { canChooseDirectories, canChooseFiles, allowsMultipleSelection in
            Extensions.openPanelURLs(
                canChooseDirectories: canChooseDirectories,
                canChooseFiles: canChooseFiles,
                allowsMultipleSelection: allowsMultipleSelection
            )
        },
        savePanel: { defaultName, allowedTypes in
            Extensions.savePanel(defaultName: defaultName, allowedTypes: allowedTypes)
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
    // Preserve the file's original encoding and line endings so undo restores bytes
    // faithfully instead of forcing UTF-8/LF.
    var metadata: FileDocumentMetadata = .utf8LF
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
            && lhs.diagnostic == rhs.diagnostic
            && lhs.lineText == rhs.lineText
            && lhs.displayPath == rhs.displayPath
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

enum NavigableProblem {
    case current(LSPDiagnostic)
    case workspace(WorkspaceDiagnosticItem)
}

private struct EditorStickyScopeCacheKey: Equatable {
    let filePath: String
    let documentVersion: Int
    let language: String
    let focusLine: Int
}

private struct EditorBreadcrumbCacheKey: Equatable {
    let filePath: String
    let rootPath: String?
    let documentVersion: Int
    let language: String
    let visibleTopLine: Int
    let cursorLine: Int
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

    enum BottomPanelKind {
        case debugConsole
        case diagnostics
        case references
        case gitDiff
        case terminal
        case dockerLogs
    }

    // Diagnostics scope/selection state lives on `diagnosticsModel`; this typealias keeps
    // existing `ProjectViewModel.DiagnosticsPanelScope` references source-compatible.
    typealias DiagnosticsPanelScope = DiagnosticsModel.DiagnosticsPanelScope

    @Published var rootDirectory: URL?
    @Published var fileTree: [FileItem] = []
    @Published private(set) var workspaceFileURLs: [URL] = []
    @Published var openTabs: [EditorTab] = []
    @Published var selectedTabIndex: Int? = nil {
        didSet {
            editorVisibleLineRange = nil
            isEditorNavigationChromeReady = false
            isOutlineSidebarDataReady = false
            isStatusBarDetailsReady = false
            editorNavigationChromeTask?.cancel()
            outlineSidebarDataTask?.cancel()
            statusBarDetailTask?.cancel()
            cursorPositionDebounceTask?.cancel()
            cursorPositionDebounceTask = nil
            pendingCursorLineChange = false
            invalidateCurrentTabBreakpointCache()
            invalidateEditorNavigationCaches()
            refreshCurrentLineBlame()
            pushDiagnosticsContext()

            if selectedTabIndex != nil {
                scheduleStatusBarDetailActivation()
            }
        }
    }
    @Published var showNewFileSheet: Bool = false
    @Published var showNewFolderSheet: Bool = false
    @Published var renameItem: FileItem? = nil
    @Published var quickOpenQuery: String = ""
    @Published var quickOpenActive: Bool = false
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
    /// Non-nil when the current query is an invalid regular expression (Regex toggle on),
    /// so the UI can distinguish a pattern typo from a legitimately empty result.
    @Published var projectSearchRegexError: String?
    @Published var activeProjectSearchResultID: String?
    @Published var collapsedProjectSearchGroupIDs: Set<String> = []
    @Published var selectedProjectSearchResultIDs: Set<String> = []
    @Published var projectReplacePreview: ProjectReplacePreview?
    @Published var lastProjectReplaceTransaction: ProjectReplaceTransaction?
    @Published var showSettings: Bool = false
    @Published private(set) var editorVisibleLineRange: ClosedRange<Int>?
    @Published private(set) var isEditorNavigationChromeReady: Bool = false
    @Published private(set) var isOutlineSidebarDataReady: Bool = false
    @Published private(set) var isStatusBarDetailsReady: Bool = false
    @Published var debugConfigurations: [DebugConfiguration] = []
    @Published var selectedDebugConfigurationName: String?
    @Published var debugConfigurationError: String?
    @Published var bottomPanel: BottomPanelKind?
    @Published private(set) var isLoadingFileTree: Bool = false
    @Published var isLoadingFile: Bool = false
    @Published var loadingFileProgress: Double?
    @Published var isSearchingProject: Bool = false
    @Published var isReplacingInProject: Bool = false
    @Published var breakpoints: [Breakpoint] = [] {
        didSet {
            invalidateCurrentTabBreakpointCache()
        }
    }
    @Published var debugSessionState: DebugSessionState = .idle
    @Published var debugConsoleEntries: [DebugConsoleEntry] = []
    @Published var debugStoppedFilePath: String?
    @Published var debugStoppedLine: Int?
    // referencesModel.referenceResults moved to `referencesModel` (a child ObservableObject) so the references
    // panel observes only that; the building/navigation logic below still writes into it.
    @Published var gitRepositoryStatus: GitRepositoryStatus = .empty {
        didSet {
            rebuildGitCaches()
        }
    }
    @Published var selectedGitDiff: GitDiffResult?
    @Published var selectedGitDiffPath: String?
    @Published var isGitDiffWorkspaceVisible: Bool = false
    @Published var currentLineBlame: GitBlameInfo?
    @Published var isRefreshingGitStatus: Bool = false
    @Published var isLoadingGitDiff: Bool = false
    @Published var isGitToolAvailable: Bool = true
    @Published var isRipgrepToolAvailable: Bool = true
    // Diagnostics selection/scope state lives on `diagnosticsModel` (see the forwarders below).

    // MARK: - Docker State
    // Docker state lives on `dockerModel` (a child ObservableObject injected separately) so
    // Docker refreshes only re-render the Docker views, not every view observing this model.

    // MARK: - Terminal State
    // Terminal session state lives on `terminalModel` (a child ObservableObject injected
    // separately) so terminal changes only re-render the terminal panel.

    // MARK: - Diagnostics (forwarders)
    // Diagnostics selection/scope state and the derived diagnostic views live on `diagnosticsModel`
    // (a child ObservableObject injected separately) so an LSP diagnostics push re-renders only the
    // diagnostics consumers. These forwarders keep existing call sites/tests unchanged; perf-critical
    // views observe `diagnosticsModel` directly.

    var activeCurrentDiagnosticID: String? {
        get { diagnosticsModel.activeCurrentDiagnosticID }
        set { diagnosticsModel.activeCurrentDiagnosticID = newValue }
    }

    var activeWorkspaceDiagnosticID: String? {
        get { diagnosticsModel.activeWorkspaceDiagnosticID }
        set { diagnosticsModel.activeWorkspaceDiagnosticID = newValue }
    }

    var diagnosticsPanelScope: DiagnosticsPanelScope {
        get { diagnosticsModel.diagnosticsPanelScope }
        set { diagnosticsModel.diagnosticsPanelScope = newValue }
    }

    var currentTabDiagnostics: [LSPDiagnostic] { diagnosticsModel.currentTabDiagnostics }

    var currentTabDiagnosticCount: (errors: Int, warnings: Int) { diagnosticsModel.currentTabDiagnosticCount }

    var orderedCurrentTabDiagnostics: [LSPDiagnostic] { diagnosticsModel.orderedCurrentTabDiagnostics }

    var activeCurrentDiagnostic: LSPDiagnostic? { diagnosticsModel.activeCurrentDiagnostic }

    var activeCurrentDiagnosticIndex: Int? { diagnosticsModel.activeCurrentDiagnosticIndex }

    var currentProblemPositionText: String? { diagnosticsModel.currentProblemPositionText }

    var workspaceDiagnosticCount: (errors: Int, warnings: Int) { diagnosticsModel.workspaceDiagnosticCount }

    var workspaceDiagnosticFileCount: Int { diagnosticsModel.workspaceDiagnosticFileCount }

    var canNavigateCurrentProblems: Bool { diagnosticsModel.canNavigateCurrentProblems }

    var hasWorkspaceDiagnostics: Bool { diagnosticsModel.hasWorkspaceDiagnostics }

    var canNavigateProblems: Bool { diagnosticsModel.canNavigateProblems }

    var canShowProblemsPanel: Bool {
        hasOpenFile || diagnosticsModel.hasWorkspaceDiagnostics
    }

    var orderedWorkspaceDiagnostics: [WorkspaceDiagnosticItem] { diagnosticsModel.orderedWorkspaceDiagnostics }

    var activeWorkspaceDiagnostic: WorkspaceDiagnosticItem? { diagnosticsModel.activeWorkspaceDiagnostic }

    var activeWorkspaceDiagnosticIndex: Int? { diagnosticsModel.activeWorkspaceDiagnosticIndex }

    var activeProblemScrollID: String? { diagnosticsModel.activeProblemScrollID }

    var selectedDebugConfiguration: DebugConfiguration? {
        guard let selectedDebugConfigurationName else { return nil }
        return debugConfigurations.first { $0.name == selectedDebugConfigurationName }
    }

    var currentTabBreakpointLines: Set<Int> {
        guard let filePath = selectedTab?.filePath.map(normalizedPath(for:)) else { return [] }
        if cachedCurrentTabBreakpointLinesPath == filePath {
            return cachedCurrentTabBreakpointLines
        }

        let lines = Set(
            breakpoints
                .filter { $0.filePath == filePath && $0.isEnabled }
                .map(\.line)
        )
        cachedCurrentTabBreakpointLinesPath = filePath
        cachedCurrentTabBreakpointLines = lines
        return lines
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

    /// True when at least one open document could be served by a language server, so offering
    /// a "restart" recovery action makes sense (e.g. after a server crash leaves it `.failed`).
    var canRestartLanguageServers: Bool {
        openTabs.contains { $0.contentType.isText && $0.language != "plaintext" }
    }

    /// Shut the language servers down and re-open the current documents so they respawn. The
    /// only recovery path when a server crashes or wedges (servers stay `.failed` otherwise).
    func restartLanguageServers() {
        let documentsToReopen: [(uri: String, language: String, text: String)] = openTabs.compactMap { tab in
            guard tab.contentType.isText, let uri = tab.documentURI, tab.language != "plaintext" else { return nil }
            return (uri, tab.language, tab.content)
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.lspService.shutdownAll()
            for document in documentsToReopen {
                self.lspService.documentOpened(uri: document.uri, language: document.language, text: document.text)
            }
        }

        NotificationManager.shared.show(NotificationItem(
            type: .info,
            title: "Restarting Language Server",
            message: "Reinitializing language tooling for open files.",
            duration: 2.0
        ))
    }

    var canReopenClosedTab: Bool {
        !recentlyClosedTabs.isEmpty
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
        return gitChangedFileByPath[relativePath]
    }

    func gitChangedDescendantCount(for item: FileItem) -> Int {
        guard item.isDirectory,
              let relativePath = gitRelativePath(for: item.path) else {
            return gitChange(for: item) == nil ? 0 : 1
        }

        return gitChangedDescendantCountByDirectoryPath[relativePath] ?? 0
    }

    func isGitIgnored(_ item: FileItem) -> Bool {
        guard let relativePath = gitRelativePath(for: item.path) else {
            return false
        }

        for ignoredPath in normalizedIgnoredGitPathsCache {
            if relativePath == ignoredPath || relativePath.hasPrefix(ignoredPath + "/") {
                return true
            }
        }

        return false
    }

    var gitChangeSections: [GitChangeSectionGroup] {
        cachedGitChangeSections
    }

    func gitChangeIndex(for changedFile: GitChangedFile) -> Int {
        gitChangeIndexByPath[changedFile.path] ?? 0
    }

    let fileService: FileService
    let sessionStore: UserDefaults
    private let sessionKey: String
    private let projectConfigPromptedRootsKey: String
    let debugSelectedConfigurationsKey: String
    let debugPanelVisibilityKey: String
    var expandedDirectoryPaths: Set<String> = []
    private var childrenLoadTokens: [String: UUID] = [:]
    private var autoSaveTask: Task<Void, Never>?
    private var reloadFileTreeTask: Task<Void, Never>?
    private var reloadWorkspaceFilesTask: Task<Void, Never>?
    private var sessionPersistenceTask: Task<Void, Never>?
    private var editorNavigationChromeTask: Task<Void, Never>?
    private var outlineSidebarDataTask: Task<Void, Never>?
    private var statusBarDetailTask: Task<Void, Never>?
    private var cursorPositionDebounceTask: Task<Void, Never>?
    private var pendingCursorLineChange: Bool = false
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
    let commandPaletteViewModel: CommandPaletteViewModel
    let dockerModel: DockerModel
    let terminalModel: TerminalModel
    let referencesModel: ReferencesModel
    // `lazy` so its dependency closures can capture self (built on first access, post-init).
    lazy var diagnosticsModel: DiagnosticsModel = DiagnosticsModel(
        lspService: lspService,
        normalize: { [weak self] in self?.normalizedPath(for: $0) ?? $0.standardizedFileURL.path },
        displayPathProvider: { [weak self] in self?.relativeDisplayPath(for: $0) ?? $0.lastPathComponent },
        lineProvider: { [weak self] url, line in self?.lineText(for: url, lineNumber: line) ?? "" }
    )
    private var fileTreeLoadToken = UUID()
    private var workspaceFilesLoadToken = UUID()
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
    private var recentCommandPaletteActionIDs: [String] = []
    var workspaceSymbolIndexTask: Task<Void, Never>?
    var workspaceSymbolIndexToken = UUID()
    var cachedWorkspaceSymbols: [WorkspaceSymbolMatch]?
    var cachedWorkspaceSymbolRootPath: String?
    var cachedWorkspaceSymbolsByPath: [String: [WorkspaceSymbolMatch]] = [:]
    var workspaceSymbolUpdateTask: Task<Void, Never>?
    let workspaceSymbolUpdateDebounceNanoseconds: UInt64 = 250_000_000
    // cachedWorkspaceDiagnostics now lives on `diagnosticsModel`.
    private var cachedFileLineContents: [String: [String]] = [:]
    private var stickyScopeCacheKey: EditorStickyScopeCacheKey?
    private var stickyScopeCache: [EditorStickyScopeItem] = []
    private var breadcrumbCacheKey: EditorBreadcrumbCacheKey?
    private var breadcrumbCache: [EditorBreadcrumbSegment] = []
    private var gitChangedFileByPath: [String: GitChangedFile] = [:]
    private var gitChangedDescendantCountByDirectoryPath: [String: Int] = [:]
    private var gitChangeIndexByPath: [String: Int] = [:]
    private var cachedGitChangeSections: [GitChangeSectionGroup] = []
    private var normalizedIgnoredGitPathsCache: [String] = []
    var presentedDependencyWarningIDs: Set<String> = []
    private var recentlyClosedTabs: [EditorTab] = []
    private var cachedCurrentTabBreakpointLinesPath: String?
    private var cachedCurrentTabBreakpointLines: Set<Int> = []
    private let sessionPersistenceDebounceNanoseconds: UInt64
    private let editorNavigationChromeDebounceNanoseconds: UInt64
    private let outlineSidebarDataDebounceNanoseconds: UInt64
    private let statusBarDetailDebounceNanoseconds: UInt64
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
            gitService: GitService.shared,
            sessionPersistenceDebounceNanoseconds: 1_000_000_000,
            editorNavigationChromeDebounceNanoseconds: 650_000_000,
            outlineSidebarDataDebounceNanoseconds: 1_100_000_000,
            statusBarDetailDebounceNanoseconds: 1_100_000_000
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
        projectSearchDebounceNanoseconds: UInt64 = 250_000_000,
        sessionPersistenceDebounceNanoseconds: UInt64 = 1_000_000_000,
        editorNavigationChromeDebounceNanoseconds: UInt64 = 650_000_000,
        outlineSidebarDataDebounceNanoseconds: UInt64 = 1_100_000_000,
        statusBarDetailDebounceNanoseconds: UInt64 = 1_100_000_000
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
        self.sessionPersistenceDebounceNanoseconds = sessionPersistenceDebounceNanoseconds
        self.editorNavigationChromeDebounceNanoseconds = editorNavigationChromeDebounceNanoseconds
        self.outlineSidebarDataDebounceNanoseconds = outlineSidebarDataDebounceNanoseconds
        self.statusBarDetailDebounceNanoseconds = statusBarDetailDebounceNanoseconds
        self.commandPaletteViewModel = CommandPaletteViewModel(commandDispatcher: commandDispatcher)
        self.dockerModel = DockerModel()
        self.terminalModel = TerminalModel(configService: configService)
        self.referencesModel = ReferencesModel()
        self.gitRepositoryStatus = .empty
        self.debugSessionService.setEventHandler { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleDebugSessionEvent(event)
            }
        }
        // DiagnosticsModel now owns the LSP diagnostics-change handler. Touch the lazy child so it
        // is created at startup (registering that handler) and seed its initial editor context.
        pushDiagnosticsContext()

        if ProcessInfo.processInfo.environment["ROSEWOOD_UI_TEST_RESET_SESSION"] == "1" {
            sessionStore.removeObject(forKey: sessionKey)
            sessionStore.removeObject(forKey: projectConfigPromptedRootsKey)
            sessionStore.removeObject(forKey: debugSelectedConfigurationsKey)
            sessionStore.removeObject(forKey: debugPanelVisibilityKey)
        }
        setupFileWatcher()
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
        reloadWorkspaceFilesTask?.cancel()
        workspaceSymbolIndexTask?.cancel()
        sessionPersistenceTask?.cancel()
        editorNavigationChromeTask?.cancel()
        outlineSidebarDataTask?.cancel()
        statusBarDetailTask?.cancel()
        projectSearchTask?.cancel()
        projectSearchDebounceTask?.cancel()
        replaceInProjectTask?.cancel()
        gitStatusTask?.cancel()
        gitDiffTask?.cancel()
        gitBlameTask?.cancel()
    }

    private func setupFileWatcher() {
        fileWatcher.onExternalFileChange = { [weak self] url in
            Task { @MainActor in
                self?.handleExternalFileChange(at: url)
            }
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

    var isEditorNavigationModelReady: Bool {
        guard let selectedTab else { return false }
        return editorVisibleLineRange != nil || selectedTab.pendingLineJump != nil
    }

    var editorStickyScopes: [EditorStickyScopeItem] {
        guard isEditorNavigationModelReady else { return [] }
        guard let selectedTab, let selectedFilePath = selectedTab.filePath else { return [] }
        let focusLine = editorVisibleLineRange?.lowerBound ?? selectedTab.cursorPosition.line
        let cacheKey = EditorStickyScopeCacheKey(
            filePath: normalizedPath(for: selectedFilePath),
            documentVersion: selectedTab.documentVersion,
            language: selectedTab.language,
            focusLine: max(focusLine, 1)
        )
        if stickyScopeCacheKey == cacheKey {
            return stickyScopeCache
        }

        let scopes = EditorNavigationModel.stickyScopes(
            text: selectedTab.content,
            language: selectedTab.language,
            focusLine: cacheKey.focusLine
        )
        stickyScopeCacheKey = cacheKey
        stickyScopeCache = scopes
        return scopes
    }

    var editorBreadcrumbs: [EditorBreadcrumbSegment] {
        guard isEditorNavigationModelReady else { return [] }
        guard let selectedTab, let selectedFilePath = selectedTab.filePath else { return [] }
        let cacheKey = EditorBreadcrumbCacheKey(
            filePath: normalizedPath(for: selectedFilePath),
            rootPath: rootDirectory.map(normalizedPath(for:)),
            documentVersion: selectedTab.documentVersion,
            language: selectedTab.language,
            visibleTopLine: editorVisibleLineRange?.lowerBound ?? 1,
            cursorLine: selectedTab.cursorPosition.line
        )
        if breadcrumbCacheKey == cacheKey {
            return breadcrumbCache
        }

        let breadcrumbs = EditorNavigationModel.breadcrumbs(
            fileURL: selectedTab.filePath,
            rootURL: rootDirectory,
            text: selectedTab.content,
            language: selectedTab.language,
            visibleTopLine: cacheKey.visibleTopLine,
            cursorLine: cacheKey.cursorLine
        )
        breadcrumbCacheKey = cacheKey
        breadcrumbCache = breadcrumbs
        return breadcrumbs
    }

    var hasUnsavedChanges: Bool {
        openTabs.contains(where: \.isDirty)
    }

    var showCommandPalette: Bool {
        commandPaletteViewModel.activePalette == .commandPalette
    }

    var showQuickOpen: Bool {
        commandPaletteViewModel.activePalette == .quickOpen
    }

    var commandPaletteQuery: String {
        get { commandPaletteViewModel.commandPaletteQuery }
        set { commandPaletteViewModel.commandPaletteQuery = newValue }
    }

    var quickOpenSectionTitle: String {
        quickOpenSections.first?.title ?? "Files"
    }

    var quickOpenHelpText: String? {
        let trimmedQuery = quickOpenQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return nil }

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

        if trimmedQuery.hasPrefix("!") {
            return "Filter workspace problems by scope or severity while you type."
        }

        return "Search files, jump with :line, symbols with #name, or problems with !."
    }

    var quickOpenProblemFilterHints: [QuickOpenProblemFilterHint] {
        let trimmedQuery = quickOpenQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedQuery.hasPrefix("!") else { return [] }

        let query = quickOpenWorkspaceProblemQuery(from: trimmedQuery)
        var hints: [QuickOpenProblemFilterHint] = [
            QuickOpenProblemFilterHint(
                id: "current",
                token: "current",
                title: "Current File",
                isActive: query.scope == .currentFile,
                kind: .scope(.currentFile)
            ),
            QuickOpenProblemFilterHint(
                id: "workspace",
                token: "workspace",
                title: "Workspace",
                isActive: query.scope == .workspace,
                kind: .scope(.workspace)
            )
        ]

        let severityHints: [(DiagnosticSeverity, String)] = [
            (.error, "Errors"),
            (.warning, "Warnings"),
            (.information, "Info"),
            (.hint, "Hints")
        ]

        hints.append(contentsOf: severityHints.map { severity, title in
            QuickOpenProblemFilterHint(
                id: problemFilterToken(for: severity),
                token: problemFilterToken(for: severity),
                title: title,
                isActive: query.severity == severity,
                kind: .severity(severity)
            )
        })

        return hints
    }

    var quickOpenEmptyStateText: String {
        let trimmedQuery = quickOpenQuery.trimmingCharacters(in: .whitespacesAndNewlines)

        if let request = quickOpenFileLineRequest(from: trimmedQuery) {
            return "No matching files for line \(request.line)."
        }

        if trimmedQuery.hasPrefix(":") {
            return hasOpenFile ? "No matching line jump." : "Open a file first to jump to a line."
        }

        if trimmedQuery.hasPrefix("#") {
            return rootDirectory == nil ? "Open a folder to search workspace symbols." : "No matching symbols."
        }

        if trimmedQuery.hasPrefix("!") {
            return quickOpenWorkspaceProblemEmptyStateText(for: quickOpenWorkspaceProblemQuery(from: trimmedQuery))
        }

        return rootDirectory == nil ? "Open a folder to search files." : "No matching files."
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

        if configService.settings.docker.enableDockerIntegration {
            actions.append(
                makeCommandPaletteAction(
                    id: "showDockerSidebar",
                    title: "Show Docker Sidebar",
                    shortcut: "",
                    category: "View",
                    aliases: ["docker", "containers", "compose", "show docker"]
                ) {
                    self.sidebarMode = .docker
                    self.dockerModel.refreshDockerState()
                }
            )
        }

        actions.append(
            makeCommandPaletteAction(
                id: "toggleTerminal",
                title: bottomPanel == .terminal ? "Hide Terminal" : "Show Terminal",
                shortcut: "⌃`",
                category: "View",
                aliases: ["terminal", "shell", "console", "open terminal", "toggle terminal"]
            ) {
                self.toggleTerminalPanel()
            }
        )

        if canRestartLanguageServers {
            actions.append(
                makeCommandPaletteAction(
                    id: "restartLanguageServers",
                    title: "Restart Language Server",
                    shortcut: "",
                    category: "View",
                    aliases: ["restart lsp", "reload language server", "restart language server", "fix language tooling"]
                ) {
                    self.restartLanguageServers()
                }
            )
        }

        actions.append(
            makeCommandPaletteAction(
                id: "openSettings",
                title: "Open Settings",
                shortcut: "⌘,",
                category: "View",
                aliases: ["settings", "preferences", "configuration"]
            ) {
                self.showSettings = true
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

        if !referencesModel.referenceResults.isEmpty {
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

        let queryContext = commandPaletteQueryContext(for: commandPaletteViewModel.commandPaletteQuery)
        let scopedActions = scopedCommandPaletteActions(actions, scope: queryContext.scope)
        return rankedCommandPaletteActions(scopedActions, query: queryContext.searchText)
    }

    var commandPaletteSections: [CommandPaletteSection] {
        let query = commandPaletteViewModel.commandPaletteQuery
        let queryContext = commandPaletteQueryContext(for: query)
        let actions = commandPaletteActions

        guard !actions.isEmpty else { return [] }

        if queryContext.scope == nil, queryContext.searchText.isEmpty {
            let recentActions = recentCommandPaletteActionIDs
                .compactMap { actionID in actions.first(where: { $0.id == actionID }) }

            var sections: [CommandPaletteSection] = []
            if !recentActions.isEmpty {
                sections.append(
                    CommandPaletteSection(
                        title: "Recent",
                        actions: recentActions.map { decoratedCommandPaletteAction($0, query: query) }
                    )
                )
            }

            let remainingActions = actions.filter { action in
                !recentActions.contains(where: { $0.id == action.id })
            }
            sections.append(contentsOf: commandPaletteCategorySections(for: remainingActions, query: query))
            return sections
        }

        if commandPaletteShouldGroupByCategory(actions: actions, normalizedQuery: queryContext.searchText) {
            return commandPaletteCategorySections(for: actions, query: query)
        }

        let title = queryContext.searchText.isEmpty ? "Commands" : "Top Matches"
        return [
            CommandPaletteSection(
                title: title,
                actions: actions.map { decoratedCommandPaletteAction($0, query: query) }
            )
        ]
    }

    var commandPaletteHelpText: String {
        let context = commandPaletteQueryContext(for: commandPaletteViewModel.commandPaletteQuery)
        if let scope = context.scope {
            return context.searchText.isEmpty
                ? "Scoped to \(scope.title) commands. Type to narrow the list."
                : "Scoped to \(scope.title) commands."
        }

        return "Type to search commands or use a scope chip to narrow results."
    }

    var commandPaletteScopeHints: [CommandPaletteScope] {
        availableCommandPaletteScopes
    }

    var activeCommandPaletteScope: CommandPaletteScope? {
        commandPaletteQueryContext(for: commandPaletteViewModel.commandPaletteQuery).scope
    }

    var commandPaletteEmptyStateText: String {
        if let scope = activeCommandPaletteScope {
            return "No matching \(scope.title.lowercased()) commands."
        }

        return "No matching commands."
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

        let fileItems = availableWorkspaceFileURLs.enumerated().compactMap { index, fileURL in
            let item = quickOpenFileItem(for: fileURL)
            let displayPath = relativeDisplayPath(for: fileURL)
            guard let score = quickOpenMatchScore(for: fileURL, fileName: item.name, displayPath: displayPath, query: trimmedQuery) else {
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
        let context = commandPaletteQueryContext(for: commandPaletteViewModel.commandPaletteQuery)

        if context.scope?.id == scope.id {
            commandPaletteViewModel.commandPaletteQuery = context.searchText
            return
        }

        let suffix = context.searchText.isEmpty ? "" : " \(context.searchText)"
        commandPaletteViewModel.commandPaletteQuery = "\(scope.queryToken)\(suffix)"
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

    var availableWorkspaceFileURLs: [URL] {
        if !workspaceFileURLs.isEmpty {
            return workspaceFileURLs
        }

        return flatFileList.compactMap { item in
            item.isDirectory ? nil : item.path
        }
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
        diagnosticsModel.isActiveDiagnostic(diagnostic)
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

    func openFiles() {
        let urls = ui.openPanelURLs(false, true, true)
        guard !urls.isEmpty else { return }
        openExternalItems(urls)
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

    private func recordRecentlyOpenedURLs(_ urls: [URL]) {
        let standardizedURLs = urls
            .map(\.standardizedFileURL)
            .filter(\.isFileURL)
        guard !standardizedURLs.isEmpty else { return }

        notificationCenter.post(name: .projectDidOpenURLs, object: standardizedURLs)
    }

    private func recentlyClosedTabSnapshot(from tab: EditorTab, discardedUnsavedChanges: Bool) -> EditorTab? {
        if discardedUnsavedChanges {
            if tab.contentType.isText, let filePath = tab.filePath {
                var restoredTab = tab
                restoredTab.filePath = filePath.standardizedFileURL
                restoredTab.content = tab.originalContent
                restoredTab.isDirty = false
                restoredTab.documentVersion = 0
                return restoredTab
            }

            return nil
        }

        var snapshot = tab
        if let filePath = snapshot.filePath {
            snapshot.filePath = filePath.standardizedFileURL
        }
        return snapshot
    }

    private func openFolder(at url: URL) {
        fileWatcher.unwatchAll()
        rootDirectory = url
        expandedDirectoryPaths = []
        openTabs = []
        recentlyClosedTabs = []
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
        recordRecentlyOpenedURLs([url])
    }

    func reloadFileTree() {
        reloadFileTreeTask?.cancel()
        reloadWorkspaceFilesTask?.cancel()
        fileTreeLoadToken = UUID()
        workspaceFilesLoadToken = UUID()
        let token = fileTreeLoadToken
        let workspaceToken = workspaceFilesLoadToken
        invalidateWorkspaceSymbolCache()

        guard let rootDirectory else {
            isLoadingFileTree = false
            fileTree = []
            workspaceFileURLs = []
            persistSession()
            return
        }

        let expandedPaths = expandedDirectoryPaths
        let normalizedRootPath = normalizedPath(for: rootDirectory)
        isLoadingFileTree = true
        workspaceFileURLs = []

        reloadWorkspaceFilesTask = Task { [weak self, fileService] in
            guard let self else { return }

            do {
                let files = try await fileService.projectFilesAsync(
                    at: rootDirectory,
                    includeHidden: self.showHiddenFiles
                )
                guard !Task.isCancelled,
                      self.workspaceFilesLoadToken == workspaceToken,
                      self.rootDirectory.map(self.normalizedPath(for:)) == normalizedRootPath else {
                    return
                }
                self.workspaceFileURLs = files.sorted {
                    let lhsPath = self.relativeDisplayPath(for: $0)
                    let rhsPath = self.relativeDisplayPath(for: $1)
                    let lhsKey = FileService.naturalSortKey(for: lhsPath)
                    let rhsKey = FileService.naturalSortKey(for: rhsPath)
                    if lhsKey != rhsKey {
                        return lhsKey < rhsKey
                    }
                    return lhsPath < rhsPath
                }
                self.invalidateWorkspaceSymbolCache()
                self.cachedWorkspaceSymbolRootPath = normalizedRootPath
                self.scheduleWorkspaceSymbolIndexRefresh()

                let workspaceLanguages = Set(files.map { EditorTab.languageFromExtension($0.pathExtension.lowercased()) })
                    .filter { $0 != "plaintext" }
                Task.detached(priority: .utility) {
                    LSPServerRegistry.prewarmServerPaths(for: workspaceLanguages)
                }
            } catch is CancellationError {
                guard self.workspaceFilesLoadToken == workspaceToken else { return }
            } catch {
                guard self.workspaceFilesLoadToken == workspaceToken else { return }
                self.workspaceFileURLs = []
            }
        }

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
            
            // Show success notification
            NotificationManager.shared.show(NotificationItem(
                type: .success,
                title: "File Created",
                message: "\(name) created successfully",
                duration: 2.0
            ))
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
            
            // Show success notification
            NotificationManager.shared.show(NotificationItem(
                type: .success,
                title: "Folder Created",
                message: "\(name) created successfully",
                duration: 2.0
            ))
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
            recordRecentlyOpenedURLs([url])
            return
        }

        do {
            isLoadingFile = true
            loadingFileProgress = 0.0
            invalidateCachedFileContent(for: url)
            
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
            invalidateEditorNavigationCaches()
            persistSession()
            isLoadingFile = false
            loadingFileProgress = nil
            recordRecentlyOpenedURLs([url])
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

    func selectNextTab() {
        guard !openTabs.isEmpty, let current = selectedTabIndex else { return }
        selectTab(at: (current + 1) % openTabs.count)
    }

    func selectPreviousTab() {
        guard !openTabs.isEmpty, let current = selectedTabIndex else { return }
        selectTab(at: (current - 1 + openTabs.count) % openTabs.count)
    }

    func selectTab(at index: Int) {
        guard openTabs.indices.contains(index) else { return }
        dismissGitDiffWorkspace()
        selectedTabIndex = index
        // Restore the caret to where it was when this tab was last active (the single reused
        // text view otherwise keeps the previous tab's clamped selection).
        if openTabs[index].contentType.isText {
            openTabs[index].pendingLineJump = openTabs[index].cursorPosition.line
        }
        if let filePath = openTabs[index].filePath {
            recordQuickOpenAccess(for: filePath)
        }
        persistSession()
    }

    @discardableResult
    func closeTab(at index: Int, confirmUnsavedChanges: Bool = true) -> Bool {
        guard openTabs.indices.contains(index) else { return false }
        let shouldCloseGitDiff = isGitDiffWorkspaceVisible && selectedTabIndex == index
        var discardedUnsavedChanges = false

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
                discardedUnsavedChanges = true
                break
            default:
                return false
            }
        }

        guard let recentlyClosedTab = recentlyClosedTabSnapshot(
            from: openTabs[index],
            discardedUnsavedChanges: discardedUnsavedChanges
        ) else {
            if let url = openTabs[index].filePath {
                fileWatcher.unwatch(url: url)
            }

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

        recentlyClosedTabs.append(recentlyClosedTab)
        if recentlyClosedTabs.count > 20 {
            recentlyClosedTabs.removeFirst(recentlyClosedTabs.count - 20)
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

    func reopenLastClosedTab() {
        guard let tab = recentlyClosedTabs.popLast() else { return }

        if let fileURL = tab.filePath?.standardizedFileURL,
           let existingIndex = openTabs.firstIndex(where: { existingTab in
               guard let existingPath = existingTab.filePath else { return false }
               return normalizedPath(for: existingPath) == normalizedPath(for: fileURL)
           }) {
            selectedTabIndex = existingIndex
            revealInExplorer(fileURL)
            recordQuickOpenAccess(for: fileURL)
            recordRecentlyOpenedURLs([fileURL])
            persistSession()
            return
        }

        openTabs.append(tab)
        selectedTabIndex = openTabs.count - 1

        if let fileURL = tab.filePath?.standardizedFileURL {
            fileWatcher.watch(url: fileURL)
            revealInExplorer(fileURL)
            recordQuickOpenAccess(for: fileURL)
            recordRecentlyOpenedURLs([fileURL])
        }

        let reopenedTab = openTabs[openTabs.count - 1]
        if reopenedTab.contentType.isText, let uri = reopenedTab.documentURI {
            lspService.documentOpened(uri: uri, language: reopenedTab.language, text: reopenedTab.content)
        }

        invalidateEditorNavigationCaches()
        refreshCurrentLineBlame()
        persistSession()
    }

    func saveCurrentFile() {
        guard let selectedTabIndex else { return }
        _ = saveTab(at: selectedTabIndex)
    }

    func saveCurrentFileAs() {
        guard let selectedTabIndex, openTabs.indices.contains(selectedTabIndex) else { return }
        guard openTabs[selectedTabIndex].contentType.isText else { return }

        let currentURL = openTabs[selectedTabIndex].filePath
        let defaultName = currentURL?.lastPathComponent ?? openTabs[selectedTabIndex].fileName
        let allowedTypes = currentURL.flatMap { url in
            url.pathExtension.isEmpty ? nil : [url.pathExtension]
        }

        guard let destinationURL = ui.savePanel(defaultName, allowedTypes) else { return }
        _ = saveTab(at: selectedTabIndex, destinationURL: destinationURL)
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
        invalidateWorkspaceDiagnosticsCache()
        if let fileURL = openTabs[selectedTabIndex].filePath {
            invalidateCachedFileContent(for: fileURL)
            // Debounced + off-main so whole-document symbol extraction doesn't run on every keystroke.
            scheduleWorkspaceSymbolCacheUpdate(for: fileURL, contents: content)
        }
        invalidateEditorNavigationCaches()

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

        scheduleSessionPersistence()
    }

    func updateCursorPosition(line: Int, column: Int) {
        guard let selectedTabIndex, openTabs.indices.contains(selectedTabIndex) else { return }
        let previousLine = openTabs[selectedTabIndex].cursorPosition.line
        openTabs[selectedTabIndex].cursorPosition = CursorPosition(line: line, column: column)
        pushDiagnosticsContext()
        if previousLine != line {
            pendingCursorLineChange = true
        }

        // `refreshCurrentLineBlame` spawns a `git blame` subprocess; debounce so that
        // holding an arrow key or fast typing doesn't fork dozens of processes.
        cursorPositionDebounceTask?.cancel()
        cursorPositionDebounceTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: 200_000_000)
            } catch {
                return
            }
            guard let self, !Task.isCancelled else { return }
            self.cursorPositionDebounceTask = nil
            if self.pendingCursorLineChange {
                self.pendingCursorLineChange = false
                self.refreshCurrentLineBlame()
            }
        }
    }

    func updateEditorVisibleLineRange(startLine: Int, endLine: Int) {
        guard startLine > 0, endLine >= startLine else {
            editorVisibleLineRange = nil
            isEditorNavigationChromeReady = false
            editorNavigationChromeTask?.cancel()
            return
        }

        editorVisibleLineRange = startLine...endLine
        scheduleEditorNavigationChromeActivation()
    }

    func jumpToLineInSelectedTab(_ line: Int) {
        guard let selectedTabIndex, openTabs.indices.contains(selectedTabIndex) else { return }
        let targetLine = max(line, 1)
        updateCursorPosition(line: targetLine, column: 1)
        openTabs[selectedTabIndex].pendingLineJump = targetLine
    }

    func toggleQuickOpen() {
        if commandPaletteViewModel.activePalette == .quickOpen {
            closeCommandPalette()
        } else {
            quickOpenActive = true
            quickOpenQuery = ""
            commandPaletteViewModel.showQuickOpen()
        }
    }

    func beginGoToLine() {
        guard hasOpenFile else { return }
        quickOpenActive = true
        let currentLine = max(selectedTab?.cursorPosition.line ?? 1, 1)
        quickOpenQuery = ":\(currentLine)"
        commandPaletteViewModel.showQuickOpen()
    }

    func beginWorkspaceSymbolSearch() {
        guard rootDirectory != nil else { return }
        quickOpenActive = true
        quickOpenQuery = "#"
        commandPaletteViewModel.showQuickOpen()
    }

    func beginWorkspaceProblemSearch() {
        guard hasWorkspaceDiagnostics else { return }
        quickOpenActive = true
        quickOpenQuery = "!"
        commandPaletteViewModel.showQuickOpen()
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
            let targetLine = max(line, 1)
            updateCursorPosition(line: targetLine, column: 1)
            openTabs[selectedTabIndex].pendingLineJump = targetLine
        case .symbol(let symbol):
            openFile(at: symbol.fileURL)
            guard let selectedTabIndex, openTabs.indices.contains(selectedTabIndex) else { return }
            let targetLine = max(symbol.line, 1)
            updateCursorPosition(line: targetLine, column: 1)
            openTabs[selectedTabIndex].pendingLineJump = targetLine
        case .problem(let diagnostic):
            openWorkspaceDiagnostic(diagnostic)
        }
    }

    func executeCommandPaletteAction(_ action: CommandPaletteAction) {
        action.action()
        if commandPaletteViewModel.activePalette == .commandPalette {
            closeCommandPalette()
        }
    }

    func toggleCommandPalette() {
        if commandPaletteViewModel.activePalette == .commandPalette {
            closeCommandPalette()
            return
        }

        quickOpenActive = false
        commandPaletteViewModel.commandPaletteQuery = ""
        commandPaletteViewModel.showCommandPalette()
    }

    func closeCommandPalette() {
        quickOpenActive = false
        commandPaletteViewModel.closePalette()
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

    /// Pushes the active tab/cursor context into `diagnosticsModel` so it can derive the active
    /// diagnostic without a back-reference to this view model. Called on tab switch and caret moves;
    /// the model absorbs no-op cursor moves, so this stays cheap on the hot caret path.
    func pushDiagnosticsContext() {
        diagnosticsModel.updateContext(
            documentURI: selectedTab?.documentURI,
            normalizedFilePath: selectedTab?.filePath.map(normalizedPath(for:)),
            cursorLine: selectedTab?.cursorPosition.line ?? 1,
            cursorColumn: selectedTab?.cursorPosition.column ?? 1
        )
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
        let standardizedURL = url.standardizedFileURL
        guard let tabIndex = openTabs.firstIndex(where: {
            $0.filePath?.standardizedFileURL == standardizedURL
        }) else { return }

        // Skip if the on-disk content already matches what we have — coalesced watcher
        // events and lingering self-writes can fire spuriously.
        if let onDisk = try? fileService.readDocument(at: url).content,
           onDisk == openTabs[tabIndex].content {
            if onDisk != openTabs[tabIndex].originalContent {
                openTabs[tabIndex].originalContent = onDisk
                openTabs[tabIndex].isDirty = false
            }
            return
        }

        if openTabs[tabIndex].isDirty {
            // The buffer has unsaved edits — never silently discard them.
            let response = ui.confirm(
                "File Changed on Disk",
                "\(url.lastPathComponent) was changed by another program, but you have unsaved changes. "
                    + "Reloading will discard your edits.",
                .warning,
                ["Keep My Changes", "Reload and Discard"]
            )
            if response == .alertSecondButtonReturn {
                reloadTab(at: tabIndex)
            }
        } else {
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
            invalidateCachedFileContent(for: url)
            invalidateWorkspaceDiagnosticsCache()
            invalidateEditorNavigationCaches()
            persistSession()
            refreshGitState()
            refreshCurrentLineBlame()
        } catch {
            ui.alert("Error", "Could not reload file: \(error.localizedDescription)", .warning)
        }
    }

    func deleteItem(_ item: FileItem) {
        let affectedIndices = affectedTabIndices(for: item.path, includeDescendants: item.isDirectory)

        // Always confirm before deleting — even clean/closed files — since this acts on
        // the file tree directly. Files go to the Trash, so this is recoverable.
        let kind = item.isDirectory ? "folder" : "file"
        let confirmation = ui.confirm(
            "Move \u{201C}\(item.name)\u{201D} to Trash?",
            item.isDirectory
                ? "The folder and everything inside it will be moved to the Trash."
                : "The \(kind) will be moved to the Trash.",
            .warning,
            ["Move to Trash", "Cancel"]
        )
        guard confirmation == .alertFirstButtonReturn else { return }

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

        guard shouldBeExpanded, item.isDirectory, rootDirectory != nil else { return }
        loadChildrenAsync(for: item.path, targetPath: targetPath)
    }

    private func loadChildrenAsync(for url: URL, targetPath: String) {
        let expandedPaths = expandedDirectoryPaths
        let includeHidden = showHiddenFiles
        let token = UUID()
        childrenLoadTokens[targetPath] = token

        Task { [weak self, fileService] in
            guard let self else { return }
            do {
                let children = try await fileService.loadDirectoryAsync(
                    at: url,
                    expandedPaths: expandedPaths,
                    includeHidden: includeHidden
                )
                guard !Task.isCancelled else { return }
                guard self.childrenLoadTokens[targetPath] == token else { return }
                guard self.expandedDirectoryPaths.contains(targetPath) else { return }
                self.fileTree = self.replaceChildren(in: self.fileTree, targetPath: targetPath, with: children)
                self.childrenLoadTokens.removeValue(forKey: targetPath)
            } catch {
                // The folder may have been deleted or become unreadable; leave the
                // existing in-memory children in place rather than blowing them away.
            }
        }
    }

    private func replaceChildren(in items: [FileItem], targetPath: String, with newChildren: [FileItem]) -> [FileItem] {
        items.map { item in
            let itemPath = normalizedPath(for: item.path)
            if itemPath == targetPath {
                var updated = item
                updated.children = newChildren
                updated.isExpanded = true
                return updated
            } else if !item.children.isEmpty {
                var updated = item
                updated.children = replaceChildren(in: item.children, targetPath: targetPath, with: newChildren)
                return updated
            }
            return item
        }
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

        if sidebarMode == .docker {
            dockerModel.refreshDockerState()
            return
        }

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
        availableWorkspaceFileURLs.enumerated().compactMap { index, fileURL in
            let item = quickOpenFileItem(for: fileURL)
            let displayPath = relativeDisplayPath(for: fileURL)
            guard let score = quickOpenMatchScore(for: fileURL, fileName: item.name, displayPath: displayPath, query: request.fileQuery) else {
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

    private func quickOpenFileItem(for fileURL: URL) -> FileItem {
        FileItem(name: fileURL.lastPathComponent, path: fileURL, isDirectory: false)
    }

    private func quickOpenMatchScore(for fileURL: URL, fileName: String, displayPath: String, query: String) -> Int? {
        let normalizedFileName = fileName.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let normalizedDisplayPath = displayPath.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let normalizedQuery = query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let openTabBoost = quickOpenOpenTabBoost(for: fileURL)
        let recencyBoost = quickOpenRecencyBoost(for: fileURL)
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
    private func saveTab(at index: Int, destinationURL: URL? = nil) -> Bool {
        guard openTabs.indices.contains(index) else { return false }
        guard openTabs[index].contentType.isText else { return true }

        let previousURL = openTabs[index].filePath?.standardizedFileURL
        let previousLanguage = openTabs[index].language
        let resolvedURL = (destinationURL ?? previousURL)?.standardizedFileURL
        guard let url = resolvedURL else { return false }
        let didChangeURL = previousURL != url

        do {
            // Suppress the watcher event our own atomic write will trigger on `url`.
            fileWatcher.suppressSelfWrite(for: url)
            try fileService.writeDocument(content: openTabs[index].content, metadata: openTabs[index].documentMetadata, to: url)

            if didChangeURL {
                if let previousURL {
                    fileWatcher.unwatch(url: previousURL)
                    invalidateCachedFileContent(for: previousURL)
                    invalidateWorkspaceSymbolCache(for: previousURL)
                    lspService.documentClosed(uri: previousURL.absoluteString, language: previousLanguage)
                }

                openTabs[index].filePath = url
                openTabs[index].fileName = url.lastPathComponent
                fileWatcher.watch(url: url)

                if let uri = openTabs[index].documentURI {
                    lspService.documentOpened(uri: uri, language: openTabs[index].language, text: openTabs[index].content)
                }
            } else {
                // The atomic write replaced the inode; re-establish the watch so future
                // external edits to this file are still detected.
                fileWatcher.rewatch(url: url)
            }

            openTabs[index].originalContent = openTabs[index].content
            openTabs[index].isDirty = false

            if openTabs[index].contentType.isText, let uri = openTabs[index].documentURI {
                lspService.documentSaved(uri: uri, language: openTabs[index].language)
            }

            invalidateCachedFileContent(for: url)
            updateWorkspaceSymbolCache(for: url, contents: openTabs[index].content)
            invalidateWorkspaceDiagnosticsCache()

            if let rootDirectory {
                let normalizedRootPath = normalizedPath(for: rootDirectory)
                let newPath = normalizedPath(for: url)
                let previousPath = previousURL.map(normalizedPath(for:))
                if newPath.hasPrefix(normalizedRootPath + "/") || previousPath?.hasPrefix(normalizedRootPath + "/") == true {
                    reloadFileTree()
                }
            }

            persistSession()
            refreshGitState()
            refreshCurrentLineBlame()

            // Routine saves (⌘S and autosave) are silent — like VS Code/Zed — since the tab's
            // dirty indicator already reflects the result and a banner on every autosave tick
            // is noise. Only the infrequent Save-As (new location) gets a confirmation.
            if didChangeURL {
                NotificationManager.shared.show(NotificationItem(
                    type: .success,
                    title: "File Saved As",
                    message: "\(openTabs[index].fileName) saved successfully",
                    duration: 2.0
                ))
            }

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

    // URL-based variants for the file tree (which works with FileItem.path, not EditorTab).
    func revealInFinder(url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func absoluteFilePath(for url: URL) -> String {
        url.path
    }

    func relativeFilePath(for url: URL) -> String? {
        guard let root = rootDirectory else { return nil }
        let filePath = url.path
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
        let normalizedFilePath = normalizedPath(for: fileURL)
        if let openTab = openTabs.first(where: {
            guard let filePath = $0.filePath else { return false }
            return normalizedPath(for: filePath) == normalizedFilePath
        }) {
            let lines = openTab.content.components(separatedBy: .newlines)
            guard lines.indices.contains(max(lineNumber - 1, 0)) else { return "" }
            return lines[max(lineNumber - 1, 0)].trimmingCharacters(in: .whitespaces)
        }

        let lines: [String]
        if let cachedLines = cachedFileLineContents[normalizedFilePath] {
            lines = cachedLines
        } else {
            guard let contents = try? fileService.readFile(at: fileURL) else { return "" }
            let cachedLines = contents.components(separatedBy: .newlines)
            cachedFileLineContents[normalizedFilePath] = cachedLines
            lines = cachedLines
        }

        guard lines.indices.contains(max(lineNumber - 1, 0)) else { return "" }
        return lines[max(lineNumber - 1, 0)].trimmingCharacters(in: .whitespaces)
    }

    func relativeDisplayPath(for fileURL: URL) -> String {
        guard let rootDirectory else { return fileURL.lastPathComponent }
        let filePath = normalizedPath(for: fileURL)
        let rootPath = normalizedPath(for: rootDirectory)
        guard filePath.hasPrefix(rootPath + "/") else { return fileURL.path }
        return String(filePath.dropFirst(rootPath.count + 1))
    }

    private func updateOpenTabPaths(moving oldURL: URL, to newURL: URL, includeDescendants: Bool) {
        for index in openTabs.indices {
            guard let filePath = openTabs[index].filePath else { continue }

            if filePath.path == oldURL.path {
                fileWatcher.unwatch(url: filePath)
                rebindLSPDocument(at: index, movingTo: newURL)
                openTabs[index].filePath = newURL
                openTabs[index].fileName = newURL.lastPathComponent
                fileWatcher.watch(url: newURL)
                continue
            }

            guard includeDescendants, filePath.path.hasPrefix(oldURL.path + "/") else { continue }

            let suffix = filePath.path.dropFirst(oldURL.path.count)
            let updatedURL = URL(fileURLWithPath: newURL.path + suffix)
            fileWatcher.unwatch(url: filePath)
            rebindLSPDocument(at: index, movingTo: updatedURL)
            openTabs[index].filePath = updatedURL
            openTabs[index].fileName = updatedURL.lastPathComponent
            fileWatcher.watch(url: updatedURL)
        }

        if let selectedTabIndex, !openTabs.indices.contains(selectedTabIndex) {
            self.selectedTabIndex = openTabs.isEmpty ? nil : 0
        }
    }

    /// Notify the language server that an open document moved, so language features keep
    /// working for the renamed buffer instead of pointing at a phantom old URI. Must be
    /// called before `openTabs[index].filePath` is updated to the new location.
    private func rebindLSPDocument(at index: Int, movingTo newURL: URL) {
        guard openTabs.indices.contains(index), openTabs[index].contentType.isText else { return }
        guard let oldURI = openTabs[index].documentURI else { return }
        let oldLanguage = openTabs[index].language
        let newLanguage = EditorTab.languageFromExtension((newURL.pathExtension as NSString).lowercased)
        lspService.documentClosed(uri: oldURI, language: oldLanguage)
        lspService.documentOpened(uri: newURL.absoluteString, language: newLanguage, text: openTabs[index].content)
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
        sessionPersistenceTask?.cancel()
        sessionPersistenceTask = nil
        let session = ProjectSessionState(
            rootDirectoryPath: rootDirectory.map(normalizedPath(for:)),
            expandedDirectoryPaths: Array(expandedDirectoryPaths).sorted(),
            openTabs: openTabs.compactMap { tab in
                guard let filePath = tab.filePath else { return nil }
                return ProjectSessionTabState(
                    filePath: normalizedPath(for: filePath),
                    fileName: tab.fileName,
                    cursorLine: tab.cursorPosition.line,
                    cursorColumn: tab.cursorPosition.column,
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

    private func scheduleSessionPersistence() {
        sessionPersistenceTask?.cancel()
        sessionPersistenceTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: self?.sessionPersistenceDebounceNanoseconds ?? 0)
            } catch {
                return
            }

            guard let self, !Task.isCancelled else { return }
            self.persistSession()
        }
    }

    private func scheduleEditorNavigationChromeActivation() {
        guard editorVisibleLineRange != nil, selectedTab != nil else {
            isEditorNavigationChromeReady = false
            isOutlineSidebarDataReady = false
            editorNavigationChromeTask?.cancel()
            outlineSidebarDataTask?.cancel()
            return
        }

        if isEditorNavigationChromeReady {
            return
        }

        editorNavigationChromeTask?.cancel()
        editorNavigationChromeTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: self?.editorNavigationChromeDebounceNanoseconds ?? 0)
            } catch {
                return
            }

            guard let self,
                  !Task.isCancelled,
                  self.editorVisibleLineRange != nil,
                  self.selectedTab != nil else {
                return
            }

            self.isEditorNavigationChromeReady = true
        }
    }

    func requestOutlineSidebarData() {
        guard isEditorNavigationChromeReady, selectedTab != nil else {
            isOutlineSidebarDataReady = false
            outlineSidebarDataTask?.cancel()
            return
        }

        if isOutlineSidebarDataReady {
            return
        }

        outlineSidebarDataTask?.cancel()
        outlineSidebarDataTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: self?.outlineSidebarDataDebounceNanoseconds ?? 0)
            } catch {
                return
            }

            guard let self,
                  !Task.isCancelled,
                  self.isEditorNavigationChromeReady,
                  self.selectedTab != nil else {
                return
            }

            self.isOutlineSidebarDataReady = true
        }
    }

    func suspendOutlineSidebarData() {
        outlineSidebarDataTask?.cancel()
        isOutlineSidebarDataReady = false
    }

    private func scheduleStatusBarDetailActivation() {
        guard selectedTab != nil else {
            isStatusBarDetailsReady = false
            statusBarDetailTask?.cancel()
            return
        }

        if isStatusBarDetailsReady {
            return
        }

        statusBarDetailTask?.cancel()
        statusBarDetailTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: self?.statusBarDetailDebounceNanoseconds ?? 0)
            } catch {
                return
            }

            guard let self, !Task.isCancelled, self.selectedTab != nil else { return }
            self.isStatusBarDetailsReady = true
        }
    }

    // The LSP diagnostics-change handler now lives on `diagnosticsModel`, which republishes on
    // itself instead of the app-wide view model. This delegating shim stays because non-LSP edits
    // (open/reload/save) still invalidate the workspace cache through the view model.
    private func invalidateWorkspaceDiagnosticsCache() {
        diagnosticsModel.invalidateWorkspaceDiagnosticsCache()
    }

    private func invalidateCachedFileContent(for fileURL: URL) {
        cachedFileLineContents.removeValue(forKey: normalizedPath(for: fileURL))
    }

    private func invalidateCurrentTabBreakpointCache() {
        cachedCurrentTabBreakpointLinesPath = nil
        cachedCurrentTabBreakpointLines = []
    }

    private func invalidateEditorNavigationCaches() {
        stickyScopeCacheKey = nil
        stickyScopeCache = []
        breadcrumbCacheKey = nil
        breadcrumbCache = []
    }

    private func rebuildGitCaches() {
        gitChangedFileByPath = Dictionary(uniqueKeysWithValues: gitRepositoryStatus.changedFiles.map { ($0.path, $0) })
        gitChangeIndexByPath = Dictionary(uniqueKeysWithValues: gitRepositoryStatus.changedFiles.enumerated().map { ($0.element.path, $0.offset) })
        normalizedIgnoredGitPathsCache = gitRepositoryStatus.ignoredPaths.map { ignoredPath in
            ignoredPath.hasSuffix("/") ? String(ignoredPath.dropLast()) : ignoredPath
        }
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
            switch contentType {
            case .text:
                guard let document = try? fileService.readDocument(at: fileURL) else { return nil }
                return EditorTab(
                    filePath: fileURL,
                    fileName: tabState.fileName,
                    content: document.content,
                    originalContent: document.content,
                    cursorPosition: restoredCursorPosition(for: tabState),
                    documentMetadata: document.metadata,
                    contentType: contentType
                )
            case .image, .binary(.hex):
                return EditorTab(
                    filePath: fileURL,
                    fileName: tabState.fileName,
                    cursorPosition: restoredCursorPosition(for: tabState),
                    documentMetadata: restoredDocumentMetadata(for: tabState),
                    contentType: contentType,
                    fileData: try? fileService.readFileAsData(at: fileURL)
                )
            case .binary, .excluded:
                return EditorTab(
                    filePath: fileURL,
                    fileName: tabState.fileName,
                    cursorPosition: restoredCursorPosition(for: tabState),
                    documentMetadata: restoredDocumentMetadata(for: tabState),
                    contentType: contentType
                )
            }
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

        // Restore the caret in the active tab on launch (the editor only jumps to a saved
        // position when pendingLineJump is set).
        if let selectedTabIndex, openTabs[selectedTabIndex].contentType.isText {
            openTabs[selectedTabIndex].pendingLineJump = openTabs[selectedTabIndex].cursorPosition.line
        }

        refreshGitState()
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

    private func restoredCursorPosition(for tabState: ProjectSessionTabState) -> CursorPosition {
        CursorPosition(
            line: max(tabState.cursorLine ?? 1, 1),
            column: max(tabState.cursorColumn ?? 1, 1)
        )
    }

    private func restoredDocumentMetadata(for tabState: ProjectSessionTabState) -> FileDocumentMetadata {
        FileDocumentMetadata(
            encoding: String.Encoding(rawValue: tabState.encodingRawValue ?? String.Encoding.utf8.rawValue),
            encodingLabel: tabState.encodingLabel ?? String.Encoding.utf8.displayLabel,
            lineEnding: LineEndingStyle(rawValue: tabState.lineEndingRawValue ?? LineEndingStyle.lf.rawValue) ?? .lf
        )
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
