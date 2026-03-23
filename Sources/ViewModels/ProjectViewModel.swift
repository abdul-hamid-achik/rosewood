import Foundation
import SwiftUI

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

@MainActor
final class ProjectViewModel: ObservableObject {
    enum SidebarMode {
        case explorer
        case search
        case debug
    }

    enum BottomPanelKind {
        case debugConsole
        case diagnostics
        case references
    }

    @Published var rootDirectory: URL?
    @Published var fileTree: [FileItem] = []
    @Published var openTabs: [EditorTab] = []
    @Published var selectedTabIndex: Int? = nil
    @Published var showCommandPalette: Bool = false
    @Published var showNewFileSheet: Bool = false
    @Published var showNewFolderSheet: Bool = false
    @Published var renameItem: FileItem? = nil
    @Published var commandPaletteQuery: String = ""
    @Published var pendingNewItemDirectory: URL? = nil
    @Published var sidebarMode: SidebarMode = .explorer
    @Published var projectSearchQuery: String = ""
    @Published var projectReplaceQuery: String = ""
    @Published var projectSearchResults: [ProjectSearchResult] = []
    @Published var showSettings: Bool = false
    @Published var debugConfigurations: [DebugConfiguration] = []
    @Published var selectedDebugConfigurationName: String?
    @Published var debugConfigurationError: String?
    @Published private(set) var bottomPanel: BottomPanelKind?
    @Published private(set) var isLoadingFileTree: Bool = false
    @Published private(set) var isSearchingProject: Bool = false
    @Published private(set) var isReplacingInProject: Bool = false
    @Published private(set) var breakpoints: [Breakpoint] = []
    @Published private(set) var debugSessionState: DebugSessionState = .idle
    @Published private(set) var debugConsoleEntries: [DebugConsoleEntry] = []
    @Published private(set) var debugStoppedFilePath: String?
    @Published private(set) var debugStoppedLine: Int?
    @Published private(set) var referenceResults: [ReferenceResult] = []

    var currentTabDiagnostics: [LSPDiagnostic] {
        guard let uri = selectedTab?.documentURI else { return [] }
        return lspService.diagnostics(for: uri)
    }

    var currentTabDiagnosticCount: (errors: Int, warnings: Int) {
        guard let uri = selectedTab?.documentURI else { return (0, 0) }
        return lspService.diagnosticCount(for: uri)
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

    var isDebugPanelVisible: Bool {
        bottomPanel == .debugConsole
    }

    var isDiagnosticsPanelVisible: Bool {
        bottomPanel == .diagnostics
    }

    var isReferencesPanelVisible: Bool {
        bottomPanel == .references
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

    private let fileService: FileService
    private let sessionStore: UserDefaults
    private let sessionKey: String
    private let projectConfigPromptedRootsKey: String
    private let debugSelectedConfigurationsKey: String
    private let debugPanelVisibilityKey: String
    private var expandedDirectoryPaths: Set<String> = []
    private var autoSaveTask: Task<Void, Never>?
    private var reloadFileTreeTask: Task<Void, Never>?
    private var projectSearchTask: Task<Void, Never>?
    private var replaceInProjectTask: Task<Void, Never>?
    private let configService: ConfigurationService
    private let fileWatcher: FileWatcherService
    private let notificationCenter: NotificationCenter
    private let ui: ProjectViewModelUI
    private let lspService: LSPServiceProtocol
    private let breakpointStore: BreakpointStore
    private let debugConfigurationService: DebugConfigurationService
    private let debugSessionService: DebugSessionServiceProtocol
    private var settingsObserver: NSObjectProtocol?
    private var fileTreeLoadToken = UUID()
    private var projectSearchToken = UUID()
    private var replaceInProjectToken = UUID()

    convenience init() {
        self.init(
            fileService: .shared,
            sessionStore: .standard,
            sessionKey: "rosewood.session",
            configService: .shared,
            fileWatcher: .shared,
            notificationCenter: .default,
            ui: .live,
            lspService: LSPService.shared,
            breakpointStore: BreakpointStore(),
            debugConfigurationService: DebugConfigurationService(),
            debugSessionService: DebugSessionService.shared
        )
    }

    init(
        fileService: FileService,
        sessionStore: UserDefaults,
        sessionKey: String,
        configService: ConfigurationService,
        fileWatcher: FileWatcherService,
        notificationCenter: NotificationCenter,
        ui: ProjectViewModelUI,
        lspService: LSPServiceProtocol? = nil,
        breakpointStore: BreakpointStore = BreakpointStore(),
        debugConfigurationService: DebugConfigurationService = DebugConfigurationService(),
        debugSessionService: DebugSessionServiceProtocol? = nil
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
        self.ui = ui
        self.lspService = lspService ?? LSPService.shared
        self.breakpointStore = breakpointStore
        self.debugConfigurationService = debugConfigurationService
        self.debugSessionService = debugSessionService ?? DebugSessionService.shared
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
        setupNotificationObservers()
        restoreSession()
        reloadDebuggerState(resetConsole: false)
        installUITestEditorFixturesIfNeeded()

        if ProcessInfo.processInfo.environment["ROSEWOOD_UI_TEST_DEBUG_SIDEBAR"] == "1" {
            sidebarMode = .debug
        }
    }

    deinit {
        autoSaveTask?.cancel()
        reloadFileTreeTask?.cancel()
        projectSearchTask?.cancel()
        replaceInProjectTask?.cancel()
        if let settingsObserver {
            notificationCenter.removeObserver(settingsObserver)
        }
    }

    private func setupFileWatcher() {
        fileWatcher.onExternalFileChange = { [weak self] url in
            Task { @MainActor in
                self?.handleExternalFileChange(at: url)
            }
        }
    }

    private func setupNotificationObservers() {
        settingsObserver = notificationCenter.addObserver(
            forName: .handleSettings,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.showSettings = true
            }
        }
    }

    private func installUITestEditorFixturesIfNeeded() {
        let environment = ProcessInfo.processInfo.environment
        let shouldInstallContextMenuFixture = environment["ROSEWOOD_UI_TEST_CONTEXT_MENU_FIXTURE"] == "1"
        let shouldInstallDiagnosticsFixture = environment["ROSEWOOD_UI_TEST_DIAGNOSTICS_FIXTURE"] == "1"
        let shouldOpenDiagnosticsPanel = environment["ROSEWOOD_UI_TEST_OPEN_DIAGNOSTICS_PANEL"] == "1"
        let shouldInstallReferencesFixture = environment["ROSEWOOD_UI_TEST_REFERENCES_FIXTURE"] == "1"
        let shouldOpenReferencesPanel = environment["ROSEWOOD_UI_TEST_OPEN_REFERENCES_PANEL"] == "1"
        let shouldInstallFoldingFixture = environment["ROSEWOOD_UI_TEST_FOLDING_FIXTURE"] == "1"
        let shouldInstallMinimapFixture = environment["ROSEWOOD_UI_TEST_MINIMAP_FIXTURE"] == "1"
        guard shouldInstallContextMenuFixture
            || shouldInstallDiagnosticsFixture
            || shouldInstallReferencesFixture
            || shouldInstallFoldingFixture
            || shouldInstallMinimapFixture else {
            return
        }

        let fileManager = FileManager.default
        let fixtureFileName = shouldInstallDiagnosticsFixture ? "Alpha.txt" : "Alpha.swift"
        let rootURL = fileManager.temporaryDirectory.appendingPathComponent(
            "rosewood-ui-context-menu-\(UUID().uuidString)",
            isDirectory: true
        )
        let alphaURL = rootURL.appendingPathComponent(fixtureFileName)

        do {
            try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
            let alphaContents: String
            if shouldInstallFoldingFixture {
                alphaContents = """
                struct Example {
                    func greet() {
                        print("hi")
                    }
                }
                let done = true
                """
            } else if shouldInstallMinimapFixture {
                alphaContents = (1...240)
                    .map { line in
                        if line.isMultiple(of: 24) {
                            return "let minimapLine\(line) = \"This line is intentionally longer so the minimap widths vary \(line)\""
                        }
                        return "let minimapLine\(line) = \(line)"
                    }
                    .joined(separator: "\n")
            } else {
                alphaContents = "let alpha = 1\n"
            }
            try alphaContents.write(to: alphaURL, atomically: true, encoding: .utf8)
        } catch {
            return
        }

        fileWatcher.unwatchAll()
        rootDirectory = rootURL
        expandedDirectoryPaths = []
        openTabs = []
        selectedTabIndex = nil
        referenceResults = []
        pendingNewItemDirectory = nil
        projectSearchResults = []

        configService.setProjectRoot(rootURL)
        lspService.setProjectRoot(rootURL)
        reloadDebuggerState(resetConsole: true)
        reloadFileTree()

        openFile(at: alphaURL)
        if shouldInstallContextMenuFixture {
            openTabs.append(EditorTab())
            selectedTabIndex = 0
        }

        if shouldInstallDiagnosticsFixture, let uri = openTabs.first?.documentURI {
            lspService.injectDiagnosticsForTesting(
                uri: uri,
                diagnostics: [
                    LSPDiagnostic(
                        range: LSPRange(
                            start: LSPPosition(line: 0, character: 4),
                            end: LSPPosition(line: 0, character: 9)
                        ),
                        severity: .error,
                        source: "sourcekit-lsp",
                        message: "Cannot find 'alpha' in scope"
                    ),
                    LSPDiagnostic(
                        range: LSPRange(
                            start: LSPPosition(line: 0, character: 0),
                            end: LSPPosition(line: 0, character: 3)
                        ),
                        severity: .warning,
                        source: "sourcekit-lsp",
                        message: "Unused variable declaration"
                    )
                ]
            )

            if shouldOpenDiagnosticsPanel {
                bottomPanel = .diagnostics
            }
        }

        if shouldInstallReferencesFixture {
            let betaURL = rootURL.appendingPathComponent("Beta.txt")
            try? "let beta = alpha\n".write(to: betaURL, atomically: true, encoding: .utf8)
            referenceResults = [
                ReferenceResult(
                    location: LSPLocation(
                        uri: alphaURL.absoluteString,
                        range: LSPRange(
                            start: LSPPosition(line: 0, character: 4),
                            end: LSPPosition(line: 0, character: 9)
                        )
                    ),
                    fileURL: alphaURL,
                    path: relativeDisplayPath(for: alphaURL),
                    line: 1,
                    column: 5,
                    lineText: "let alpha = 1"
                ),
                ReferenceResult(
                    location: LSPLocation(
                        uri: betaURL.absoluteString,
                        range: LSPRange(
                            start: LSPPosition(line: 0, character: 11),
                            end: LSPPosition(line: 0, character: 16)
                        )
                    ),
                    fileURL: betaURL,
                    path: relativeDisplayPath(for: betaURL),
                    line: 1,
                    column: 12,
                    lineText: "let beta = alpha"
                )
            ]

            if shouldOpenReferencesPanel {
                bottomPanel = .references
            }
        }

        persistSession()
    }

    var selectedTab: EditorTab? {
        guard let index = selectedTabIndex, openTabs.indices.contains(index) else { return nil }
        return openTabs[index]
    }

    var hasUnsavedChanges: Bool {
        openTabs.contains(where: \.isDirty)
    }

    var commandPaletteActions: [CommandPaletteAction] {
        var actions: [CommandPaletteAction] = [
            CommandPaletteAction(id: "newFile", title: "New File", shortcut: "⌘N", category: "File") {
                self.createNewFile()
            },
            CommandPaletteAction(id: "openFolder", title: "Open Folder", shortcut: "⌘O", category: "File") {
                self.openFolder()
            },
            CommandPaletteAction(id: "save", title: "Save", shortcut: "⌘S", category: "File") {
                self.saveCurrentFile()
            }
        ]

        if let selectedTabIndex {
            actions.append(
                CommandPaletteAction(id: "closeTab", title: "Close Tab", shortcut: "⌘W", category: "File") {
                    _ = self.closeTab(at: selectedTabIndex)
                }
            )
        }

        if canFindReferences {
            actions.append(
                CommandPaletteAction(
                    id: "findReferences",
                    title: "Find References",
                    shortcut: "⇧F12",
                    category: "Go"
                ) {
                    self.notificationCenter.post(name: .handleFindReferences, object: nil)
                }
            )
        }

        if rootDirectory != nil && !configService.hasProjectConfig() {
            actions.append(
                CommandPaletteAction(
                    id: "createProjectConfig",
                    title: "Create Project Config",
                    shortcut: "",
                    category: "Project"
                ) {
                    self.createProjectConfig()
                }
            )
        }

        return actions.filter { action in
            commandPaletteQuery.isEmpty || action.title.localizedCaseInsensitiveContains(commandPaletteQuery)
        }
    }

    var filteredFiles: [FileItem] {
        guard !commandPaletteQuery.isEmpty else { return flatFileList }
        return flatFileList.filter { item in
            !item.isDirectory && item.name.localizedCaseInsensitiveContains(commandPaletteQuery)
        }
    }

    var flatFileList: [FileItem] {
        flattenFileTree(fileTree)
    }

    func openFolder() {
        guard prepareForSessionTransition(title: "Open Folder", message: "Do you want to save changes before opening a different folder?") else {
            return
        }

        guard let url = ui.openPanel(true, false, false) else { return }

        fileWatcher.unwatchAll()
        rootDirectory = url
        expandedDirectoryPaths = []
        openTabs = []
        selectedTabIndex = nil
        closeReferencesPanel()
        pendingNewItemDirectory = nil
        projectSearchResults = []

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
        persistSession()
    }

    func reloadFileTree() {
        reloadFileTreeTask?.cancel()
        fileTreeLoadToken = UUID()
        let token = fileTreeLoadToken

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
                let tree = try await fileService.loadDirectoryAsync(at: rootDirectory, expandedPaths: expandedPaths)
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

    func createProjectConfig() {
        if let rootDirectory {
            configService.setProjectRoot(rootDirectory)
        }

        do {
            try configService.createDefaultProjectConfig()
            reloadDebugConfigurations()
        } catch {
            ui.alert("Error", "Could not create project config: \(error.localizedDescription)", .warning)
        }
    }

    func openFile(at url: URL) {
        if let existingIndex = openTabs.firstIndex(where: { tab in
            guard let filePath = tab.filePath else { return false }
            return normalizedPath(for: filePath) == normalizedPath(for: url)
        }) {
            selectedTabIndex = existingIndex
            persistSession()
            return
        }

        do {
            let content = try fileService.readFile(at: url)
            openTabs.append(
                EditorTab(
                    filePath: url,
                    fileName: url.lastPathComponent,
                    content: content,
                    originalContent: content
                )
            )
            selectedTabIndex = openTabs.count - 1
            fileWatcher.watch(url: url)

            // Notify LSP service of document open
            let tab = openTabs[openTabs.count - 1]
            if let uri = tab.documentURI {
                lspService.documentOpened(uri: uri, language: tab.language, text: content)
            }

            persistSession()
        } catch {
            ui.alert("Error", "Could not open file: \(error.localizedDescription)", .warning)
        }
    }

    @discardableResult
    func closeTab(at index: Int, confirmUnsavedChanges: Bool = true) -> Bool {
        guard openTabs.indices.contains(index) else { return false }

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

        if let url = openTabs[index].filePath {
            fileWatcher.unwatch(url: url)
        }

        // Notify LSP service of document close
        if let uri = openTabs[index].documentURI {
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
        openTabs[selectedTabIndex].content = content
        openTabs[selectedTabIndex].isDirty = content != openTabs[selectedTabIndex].originalContent

        // Notify LSP service of document change
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
        openTabs[selectedTabIndex].cursorPosition = CursorPosition(line: line, column: column)
    }

    func toggleCommandPalette() {
        showCommandPalette.toggle()
        if showCommandPalette {
            commandPaletteQuery = ""
        }
    }

    func closeCommandPalette() {
        showCommandPalette = false
    }

    func showExplorerSidebar() {
        sidebarMode = .explorer
    }

    func showSearchSidebar() {
        sidebarMode = .search
        if !projectSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            performProjectSearch()
        }
    }

    func showDebugSidebar() {
        sidebarMode = .debug
    }

    func selectDebugConfiguration(named name: String) {
        guard debugConfigurations.contains(where: { $0.name == name }) else { return }
        selectedDebugConfigurationName = name
        persistDebugPreferences()
    }

    func toggleDebugPanel() {
        bottomPanel = isDebugPanelVisible ? nil : .debugConsole
        persistDebugPreferences()
    }

    func toggleDiagnosticsPanel() {
        bottomPanel = isDiagnosticsPanelVisible ? nil : .diagnostics
        persistDebugPreferences()
    }

    func openDiagnostic(_ diagnostic: LSPDiagnostic) {
        guard let selectedTabIndex, openTabs.indices.contains(selectedTabIndex) else { return }
        openTabs[selectedTabIndex].pendingLineJump = diagnostic.range.start.line + 1
        persistDebugPreferences()
    }

    func showReferences(_ locations: [LSPLocation]) {
        referenceResults = locations.compactMap(makeReferenceResult(for:)).sorted(by: compareReferenceResults)
        bottomPanel = .references
    }

    func closeReferencesPanel() {
        referenceResults = []
        if isReferencesPanelVisible {
            bottomPanel = nil
        }
    }

    func openReferenceResult(_ result: ReferenceResult) {
        openFile(at: result.fileURL)
        guard let selectedTabIndex, openTabs.indices.contains(selectedTabIndex) else { return }
        guard let selectedFilePath = openTabs[selectedTabIndex].filePath,
              normalizedPath(for: selectedFilePath) == normalizedPath(for: result.fileURL) else {
            return
        }
        openTabs[selectedTabIndex].pendingLineJump = result.line
    }

    func clearDebugConsole() {
        debugConsoleEntries = []
    }

    func startDebugging() {
        guard let rootDirectory else {
            ui.alert("No Folder Open", "Please open a folder first.", .warning)
            return
        }

        reloadDebugConfigurations()
        guard let configuration = selectedDebugConfiguration else {
            showDebugSidebar()
            ui.alert("No Debug Configuration", "Add a [debug] configuration to .rosewood.toml first.", .warning)
            return
        }

        guard prepareForSessionTransition(
            title: "Start Debugger",
            message: "Do you want to save changes before starting the debug session?"
        ) else {
            return
        }

        showDebugSidebar()
        bottomPanel = .debugConsole
        persistDebugPreferences()
        clearStoppedLocation()
        debugSessionState = .starting
        appendDebugConsole("Starting \"\(configuration.name)\"...", kind: .info)

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let result = try await self.debugSessionService.start(
                    configuration: configuration,
                    projectRoot: rootDirectory,
                    breakpoints: self.breakpoints
                )
                if result.executedPreLaunchTask {
                    self.appendDebugConsole("preLaunchTask completed successfully.", kind: .success)
                }
                self.appendDebugConsole("Found lldb-dap at \(result.adapterPath)", kind: .success)
                self.appendDebugConsole("Program ready at \(result.programPath)", kind: .success)
            } catch {
                let message = error.localizedDescription
                self.debugSessionState = .failed(message)
                self.clearStoppedLocation()
                self.appendDebugConsole(message, kind: .error)
                self.ui.alert("Debug Start Failed", message, .warning)
            }
        }
    }

    func stopDebugging() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.debugSessionService.stop()
        }
    }

    func toggleBreakpoint(line: Int) {
        guard let rootDirectory, let fileURL = selectedTab?.filePath else { return }
        breakpoints = breakpointStore.toggleBreakpoint(fileURL: fileURL, line: line, projectRoot: rootDirectory)
        syncActiveDebugBreakpoints()
    }

    func openBreakpoint(_ breakpoint: Breakpoint) {
        let fileURL = URL(fileURLWithPath: breakpoint.filePath)
        openFile(at: fileURL)
        if let selectedTabIndex, openTabs.indices.contains(selectedTabIndex) {
            openTabs[selectedTabIndex].pendingLineJump = breakpoint.line
        }
    }

    func removeBreakpoint(_ breakpoint: Breakpoint) {
        guard rootDirectory != nil else { return }
        breakpoints = breakpointStore.removeBreakpoint(breakpoint, for: rootDirectory)
        syncActiveDebugBreakpoints()
    }

    func performProjectSearch() {
        projectSearchTask?.cancel()
        projectSearchToken = UUID()
        let token = projectSearchToken

        guard let rootDirectory else {
            isSearchingProject = false
            projectSearchResults = []
            return
        }

        let trimmedQuery = projectSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            isSearchingProject = false
            projectSearchResults = []
            return
        }

        let normalizedRootPath = normalizedPath(for: rootDirectory)
        isSearchingProject = true

        projectSearchTask = Task { [weak self, fileService] in
            guard let self else { return }

            do {
                let results = try await fileService.searchProjectAsync(at: rootDirectory, query: trimmedQuery)
                guard !Task.isCancelled,
                      self.projectSearchToken == token,
                      self.rootDirectory.map(self.normalizedPath(for:)) == normalizedRootPath,
                      self.projectSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines) == trimmedQuery else {
                    return
                }
                self.projectSearchResults = results
                self.isSearchingProject = false
            } catch is CancellationError {
                guard self.projectSearchToken == token else { return }
                self.isSearchingProject = false
            } catch {
                guard self.projectSearchToken == token else { return }
                self.projectSearchResults = []
                self.isSearchingProject = false
            }
        }
    }

    func replaceAllProjectResults() {
        guard let rootDirectory else { return }

        let trimmedQuery = projectSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return }

        guard prepareForSessionTransition(
            title: "Replace in Project",
            message: "Do you want to save changes before replacing across the project?"
        ) else {
            return
        }

        let response = ui.confirm(
            "Replace All Matches?",
            "This will replace every current match for \"\(trimmedQuery)\" in the open folder.",
            .warning,
            ["Replace All", "Cancel"]
        )

        guard response == .alertFirstButtonReturn else { return }

        replaceInProjectTask?.cancel()
        replaceInProjectToken = UUID()
        let token = replaceInProjectToken
        let replacement = projectReplaceQuery
        let normalizedRootPath = normalizedPath(for: rootDirectory)
        isReplacingInProject = true

        replaceInProjectTask = Task { [weak self, fileService] in
            guard let self else { return }

            do {
                let summary = try await fileService.replaceInProjectAsync(
                    at: rootDirectory,
                    searchQuery: trimmedQuery,
                    replacement: replacement
                )
                guard self.replaceInProjectToken == token,
                      self.rootDirectory.map(self.normalizedPath(for:)) == normalizedRootPath else {
                    return
                }

                self.syncOpenTabs(with: summary.modifiedFiles)
                self.isReplacingInProject = false
                self.performProjectSearch()
                if summary.replacementCount > 0 {
                    self.ui.alert(
                        "Replace Complete",
                        "Replaced \(summary.replacementCount) match\(summary.replacementCount == 1 ? "" : "es") in \(summary.modifiedFiles.count) file\(summary.modifiedFiles.count == 1 ? "" : "s").",
                        .informational
                    )
                }
            } catch {
                guard self.replaceInProjectToken == token else { return }
                self.isReplacingInProject = false
                self.ui.alert("Error", "Could not replace matches: \(error.localizedDescription)", .warning)
            }
        }
    }

    func openSearchResult(_ result: ProjectSearchResult) {
        openFile(at: result.filePath)
        if let selectedTabIndex, openTabs.indices.contains(selectedTabIndex) {
            openTabs[selectedTabIndex].cursorPosition = CursorPosition(line: result.lineNumber, column: 1)
            openTabs[selectedTabIndex].pendingLineJump = result.lineNumber
        }
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
            let content = try fileService.readFile(at: url)
            openTabs[index].content = content
            openTabs[index].originalContent = content
            openTabs[index].isDirty = false
            persistSession()
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

    @discardableResult
    private func saveTab(at index: Int) -> Bool {
        guard openTabs.indices.contains(index), let url = openTabs[index].filePath else { return false }

        do {
            try fileService.writeFile(content: openTabs[index].content, to: url)
            openTabs[index].originalContent = openTabs[index].content
            openTabs[index].isDirty = false

            // Notify LSP service of document save
            if let uri = openTabs[index].documentURI {
                lspService.documentSaved(uri: uri, language: openTabs[index].language)
            }

            persistSession()
            return true
        } catch {
            ui.alert("Error", "Could not save file: \(error.localizedDescription)", .warning)
            return false
        }
    }

    private func prepareForSessionTransition(title: String, message: String) -> Bool {
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

    private func resolveUnsavedChanges(for indices: [Int], title: String, message: String) -> Bool {
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

    private func makeReferenceResult(for location: LSPLocation) -> ReferenceResult? {
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

    private func compareReferenceResults(_ lhs: ReferenceResult, _ rhs: ReferenceResult) -> Bool {
        if lhs.path != rhs.path {
            return lhs.path.localizedStandardCompare(rhs.path) == .orderedAscending
        }
        if lhs.line != rhs.line {
            return lhs.line < rhs.line
        }
        return lhs.column < rhs.column
    }

    private func lineText(for fileURL: URL, lineNumber: Int) -> String {
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

    private func relativeDisplayPath(for fileURL: URL) -> String {
        guard let rootDirectory else { return fileURL.lastPathComponent }
        let filePath = fileURL.path
        let rootPath = rootDirectory.path
        guard filePath.hasPrefix(rootPath + "/") else { return fileURL.path }
        return String(filePath.dropFirst(rootPath.count + 1))
    }

    private func syncOpenTabs(with fileURLs: [URL]) {
        let normalizedPaths = Set(fileURLs.map(normalizedPath(for:)))
        guard !normalizedPaths.isEmpty else { return }

        for index in openTabs.indices {
            guard let filePath = openTabs[index].filePath,
                  normalizedPaths.contains(normalizedPath(for: filePath)),
                  let content = try? fileService.readFile(at: filePath) else {
                continue
            }

            openTabs[index].content = content
            openTabs[index].originalContent = content
            openTabs[index].isDirty = false
        }
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

    private func persistSession() {
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
                    isDirty: tab.isDirty
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
            return EditorTab(
                filePath: URL(fileURLWithPath: tabState.filePath),
                fileName: tabState.fileName,
                content: tabState.content,
                originalContent: tabState.originalContent,
                isDirty: tabState.isDirty
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
    }

    private func reloadDebuggerState(resetConsole: Bool) {
        Task { @MainActor [weak self] in
            await self?.debugSessionService.stop()
        }
        loadBreakpoints()
        reloadDebugConfigurations()
        clearStoppedLocation()
        debugSessionState = .idle
        if resetConsole {
            debugConsoleEntries = []
        }
    }

    private func loadBreakpoints() {
        breakpoints = breakpointStore.breakpoints(for: rootDirectory)
    }

    private func reloadDebugConfigurations() {
        do {
            let configuration = try debugConfigurationService.loadProjectConfiguration(for: rootDirectory)
            debugConfigurationError = nil
            debugConfigurations = configuration.configurations

            let resolvedSelection = [
                selectedDebugConfigurationName,
                storedSelectedDebugConfigurationName(for: rootDirectory),
                configuration.defaultConfiguration,
                configuration.configurations.first?.name
            ]
                .compactMap { $0 }
                .first { candidate in
                    configuration.configurations.contains(where: { $0.name == candidate })
                }

            selectedDebugConfigurationName = resolvedSelection
            persistDebugPreferences()
        } catch {
            debugConfigurations = []
            selectedDebugConfigurationName = nil
            debugConfigurationError = error.localizedDescription
        }
    }

    private func appendDebugConsole(_ message: String, kind: DebugConsoleEntry.Kind) {
        debugConsoleEntries.append(DebugConsoleEntry(kind: kind, message: message))
    }

    private func handleDebugSessionEvent(_ event: DebugSessionEvent) {
        switch event {
        case let .output(kind, message):
            appendDebugConsole(message, kind: kind)
        case let .state(state):
            debugSessionState = state
            if case .idle = state {
                clearStoppedLocation()
            }
        case let .stopped(filePath, line, reason):
            debugStoppedFilePath = filePath.map { normalizedPath(for: URL(fileURLWithPath: $0)) }
            debugStoppedLine = line
            appendDebugConsole("Paused: \(reason)", kind: .warning)

            guard let filePath, let line else { return }
            let fileURL = URL(fileURLWithPath: filePath)
            openFile(at: fileURL)
            if let selectedTabIndex, openTabs.indices.contains(selectedTabIndex) {
                openTabs[selectedTabIndex].pendingLineJump = line
            }
        case .terminated:
            clearStoppedLocation()
            appendDebugConsole("Debug session terminated.", kind: .info)
        }
    }

    private func clearStoppedLocation() {
        debugStoppedFilePath = nil
        debugStoppedLine = nil
    }

    private func syncActiveDebugBreakpoints() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.debugSessionService.updateBreakpoints(self.breakpoints, projectRoot: self.rootDirectory)
        }
    }

    private func normalizedPath(for url: URL) -> String {
        url.standardizedFileURL.path
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

    private func storedSelectedDebugConfigurationName(for projectRoot: URL?) -> String? {
        guard let projectRoot else { return nil }
        let selections = sessionStore.dictionary(forKey: debugSelectedConfigurationsKey) as? [String: String] ?? [:]
        return selections[normalizedPath(for: projectRoot)]
    }

    private func persistDebugPreferences() {
        sessionStore.set(isDebugPanelVisible, forKey: debugPanelVisibilityKey)

        guard let rootDirectory, let selectedDebugConfigurationName else { return }

        var selections = sessionStore.dictionary(forKey: debugSelectedConfigurationsKey) as? [String: String] ?? [:]
        selections[normalizedPath(for: rootDirectory)] = selectedDebugConfigurationName
        sessionStore.set(selections, forKey: debugSelectedConfigurationsKey)
    }

    private var projectConfigPromptedRoots: Set<String> {
        Set(sessionStore.stringArray(forKey: projectConfigPromptedRootsKey) ?? [])
    }
}

struct ProjectSessionState: Codable, Equatable {
    let rootDirectoryPath: String?
    let expandedDirectoryPaths: [String]
    let openTabs: [ProjectSessionTabState]
    let selectedTabPath: String?
}

struct ProjectSessionTabState: Codable, Equatable {
    let filePath: String
    let fileName: String
    let content: String
    let originalContent: String
    let isDirty: Bool
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
    let action: () -> Void
}
