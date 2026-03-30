import AppKit
import Testing
@testable import Rosewood

@Suite(.serialized)
@MainActor
struct AppDelegateTests {
    @Test
    func menuHandlersPostExpectedNotifications() {
        let center = NotificationCenter()
        let delegate = AppDelegate(notificationCenter: center)

        let notifications: [Notification.Name] = [
            .handleNewFile,
            .handleNewWindow,
            .handleOpenFile,
            .handleOpenFolder,
            .handleSave,
            .handleSaveAs,
            .handleReopenClosedTab,
            .handleQuickOpen,
            .handleCommandPalette,
            .handleToggleProblems,
            .handleCloseTab,
            .handleFindInFile,
            .handleFindNext,
            .handleFindPrevious,
            .handleNextProblem,
            .handlePreviousProblem,
            .handleUseSelectionForFind,
            .handleShowReplace,
            .handleGoToLine,
            .handleProjectSearch,
            .handleSettings,
            .handleGoToDefinition,
            .handleFindReferences
        ]

        var received: [Notification.Name] = []
        let observers = notifications.map { name in
            center.addObserver(forName: name, object: nil, queue: nil) { notification in
                received.append(notification.name)
            }
        }
        defer {
            for observer in observers {
                center.removeObserver(observer)
            }
        }

        delegate.handleNewFile()
        delegate.handleNewWindow()
        delegate.handleOpenFile()
        delegate.handleOpenFolder()
        delegate.handleSave()
        delegate.handleSaveAs()
        delegate.handleReopenClosedTab()
        delegate.handleQuickOpen()
        delegate.handleCommandPalette()
        delegate.handleToggleProblems()
        delegate.handleCloseTab()
        delegate.handleFindInFile()
        delegate.handleFindNext()
        delegate.handleFindPrevious()
        delegate.handleNextProblem()
        delegate.handlePreviousProblem()
        delegate.handleUseSelectionForFind()
        delegate.handleShowReplace()
        delegate.handleGoToLine()
        delegate.handleProjectSearch()
        delegate.handleSettings()
        delegate.handleGoToDefinition()
        delegate.handleFindReferences()

        #expect(received == notifications)
    }

    @Test
    func appLifecycleDefaultsAreConfigured() {
        let delegate = AppDelegate()

        #expect(delegate.applicationShouldTerminateAfterLastWindowClosed(NSApp) == true)
        #expect(delegate.applicationSupportsSecureRestorableState(NSApp) == false)
    }

    @Test
    func findReferencesMenuValidationTracksProjectState() throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = rootURL.appendingPathComponent("Alpha.swift")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try "let alpha = 1\n".write(to: fileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let configURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("toml")
        defer { try? FileManager.default.removeItem(at: configURL) }

        let lspService = MockLSPService()
        let viewModel = ProjectViewModel(
            fileService: FileService(),
            sessionStore: makeDefaults(),
            sessionKey: "app-delegate-menu-validation",
            configService: ConfigurationService(userConfigURL: configURL),
            fileWatcher: FileWatcherService(),
            notificationCenter: NotificationCenter(),
            ui: .test,
            lspService: lspService
        )

        viewModel.rootDirectory = rootURL
        viewModel.openFile(at: fileURL)

        let delegate = AppDelegate(notificationCenter: NotificationCenter(), projectViewModel: viewModel)
        let item = NSMenuItem(title: "Find References", action: #selector(AppDelegate.handleFindReferences), keyEquivalent: "")

        #expect(delegate.validateMenuItem(item) == false)

        lspService.setServerStatus(language: "swift", status: .ready)
        #expect(delegate.validateMenuItem(item) == true)
    }

    @Test
    func inFileFindMenuValidationTracksOpenFileState() {
        let viewModel = ProjectViewModel(
            fileService: FileService(),
            sessionStore: makeDefaults(),
            sessionKey: "app-delegate-find-validation",
            configService: ConfigurationService(
                userConfigURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension("toml")
            ),
            fileWatcher: FileWatcherService(),
            notificationCenter: NotificationCenter(),
            ui: .test
        )

        let delegate = AppDelegate(notificationCenter: NotificationCenter(), projectViewModel: viewModel)
        let item = NSMenuItem(title: "Find...", action: #selector(AppDelegate.handleFindInFile), keyEquivalent: "")

        #expect(delegate.validateMenuItem(item) == false)

        viewModel.openTabs = [EditorTab()]
        viewModel.selectedTabIndex = 0

        #expect(delegate.validateMenuItem(item) == true)
    }

    @Test
    func goToLineMenuValidationTracksOpenFileState() {
        let viewModel = ProjectViewModel(
            fileService: FileService(),
            sessionStore: makeDefaults(),
            sessionKey: "app-delegate-go-to-line-validation",
            configService: ConfigurationService(
                userConfigURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension("toml")
            ),
            fileWatcher: FileWatcherService(),
            notificationCenter: NotificationCenter(),
            ui: .test
        )

        let delegate = AppDelegate(notificationCenter: NotificationCenter(), projectViewModel: viewModel)
        let item = NSMenuItem(title: "Go to Line...", action: #selector(AppDelegate.handleGoToLine), keyEquivalent: "")

        #expect(delegate.validateMenuItem(item) == false)

        viewModel.openTabs = [EditorTab()]
        viewModel.selectedTabIndex = 0

        #expect(delegate.validateMenuItem(item) == true)
    }

    @Test
    func reopenClosedTabMenuValidationTracksViewModelState() {
        let viewModel = ProjectViewModel(
            fileService: FileService(),
            sessionStore: makeDefaults(),
            sessionKey: "app-delegate-reopen-tab-validation",
            configService: ConfigurationService(
                userConfigURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension("toml")
            ),
            fileWatcher: FileWatcherService(),
            notificationCenter: NotificationCenter(),
            ui: .test
        )

        viewModel.openTabs = [EditorTab(fileName: "Sample.swift")]
        viewModel.selectedTabIndex = 0
        _ = viewModel.closeTab(at: 0, confirmUnsavedChanges: false)

        let delegate = AppDelegate(notificationCenter: NotificationCenter(), projectViewModel: viewModel)
        let item = NSMenuItem(title: "Reopen Last Closed Tab", action: #selector(AppDelegate.handleReopenClosedTab), keyEquivalent: "")

        #expect(delegate.validateMenuItem(item) == true)

        viewModel.reopenLastClosedTab()
        #expect(delegate.validateMenuItem(item) == false)
    }

    @Test
    func problemsMenuValidationTracksCurrentFileDiagnostics() throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = rootURL.appendingPathComponent("Alpha.swift")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try "let alpha = 1\n".write(to: fileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let configURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("toml")
        defer { try? FileManager.default.removeItem(at: configURL) }

        let lspService = MockLSPService()
        let viewModel = ProjectViewModel(
            fileService: FileService(),
            sessionStore: makeDefaults(),
            sessionKey: "app-delegate-problems-validation",
            configService: ConfigurationService(userConfigURL: configURL),
            fileWatcher: FileWatcherService(),
            notificationCenter: NotificationCenter(),
            ui: .test,
            lspService: lspService
        )

        let delegate = AppDelegate(notificationCenter: NotificationCenter(), projectViewModel: viewModel)
        let toggleItem = NSMenuItem(title: "Show Problems", action: #selector(AppDelegate.handleToggleProblems), keyEquivalent: "")
        let nextItem = NSMenuItem(title: "Next Problem", action: #selector(AppDelegate.handleNextProblem), keyEquivalent: "")

        #expect(delegate.validateMenuItem(toggleItem) == false)
        #expect(delegate.validateMenuItem(nextItem) == false)

        viewModel.rootDirectory = rootURL
        viewModel.openFile(at: fileURL)

        #expect(delegate.validateMenuItem(toggleItem) == true)
        #expect(delegate.validateMenuItem(nextItem) == false)

        let uri = try #require(viewModel.selectedTab?.documentURI)
        lspService.setDiagnostics(
            uri: uri,
            diagnostics: [
                LSPDiagnostic(
                    range: LSPRange(
                        start: LSPPosition(line: 0, character: 4),
                        end: LSPPosition(line: 0, character: 9)
                    ),
                    severity: .error,
                    message: "Cannot find 'alpha' in scope"
                )
            ]
        )

        #expect(delegate.validateMenuItem(nextItem) == true)
    }

    @Test
    func findNextMenuValidationAllowsVisibleProjectSearchNavigation() async throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let alphaURL = rootURL.appendingPathComponent("Alpha.swift")
        let betaURL = rootURL.appendingPathComponent("Beta.swift")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try "let alpha = 1\n".write(to: alphaURL, atomically: true, encoding: .utf8)
        try "let beta = alpha\n".write(to: betaURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let configURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("toml")
        defer { try? FileManager.default.removeItem(at: configURL) }

        let viewModel = ProjectViewModel(
            fileService: FileService(),
            sessionStore: makeDefaults(),
            sessionKey: "app-delegate-search-navigation-validation",
            configService: ConfigurationService(userConfigURL: configURL),
            fileWatcher: FileWatcherService(),
            notificationCenter: NotificationCenter(),
            ui: .test
        )

        viewModel.rootDirectory = rootURL
        viewModel.projectSearchQuery = "alpha"
        viewModel.showSearchSidebar()

        while viewModel.isSearchingProject || viewModel.orderedProjectSearchResults.count != 2 {
            try await Task.sleep(for: .milliseconds(10))
        }

        let delegate = AppDelegate(notificationCenter: NotificationCenter(), projectViewModel: viewModel)
        let item = NSMenuItem(title: "Find Next", action: #selector(AppDelegate.handleFindNext), keyEquivalent: "")

        #expect(delegate.validateMenuItem(item) == true)
    }

    @Test
    func openFilesForwardsDirectoriesToProjectViewModel() throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let configURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("toml")
        defer { try? FileManager.default.removeItem(at: configURL) }

        let viewModel = ProjectViewModel(
            fileService: FileService(),
            sessionStore: makeDefaults(),
            sessionKey: "app-delegate-open-files",
            configService: ConfigurationService(userConfigURL: configURL),
            fileWatcher: FileWatcherService(),
            notificationCenter: NotificationCenter(),
            ui: .test
        )

        let delegate = AppDelegate(notificationCenter: NotificationCenter(), projectViewModel: viewModel)
        delegate.application(NSApp, openFiles: [rootURL.path])

        #expect(viewModel.rootDirectory?.standardizedFileURL.path == rootURL.standardizedFileURL.path)
    }

    @Test
    func openFilesRecordsRecentDocuments() throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let configURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("toml")
        defer { try? FileManager.default.removeItem(at: configURL) }

        let defaults = makeDefaults()
        let viewModel = ProjectViewModel(
            fileService: FileService(),
            sessionStore: makeDefaults(),
            sessionKey: "app-delegate-open-files-recents",
            configService: ConfigurationService(userConfigURL: configURL),
            fileWatcher: FileWatcherService(),
            notificationCenter: NotificationCenter(),
            ui: .test
        )

        let delegate = AppDelegate(
            notificationCenter: NotificationCenter(),
            projectViewModel: viewModel,
            recentDocumentsStore: defaults
        )
        delegate.application(NSApp, openFiles: [rootURL.path])

        #expect(delegate.recentDocumentURLsForTesting.map(\.standardizedFileURL.path) == [rootURL.standardizedFileURL.path])
    }

    @Test
    func recentDocumentNotificationUpdatesRecentList() throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let center = NotificationCenter()
        let delegate = AppDelegate(notificationCenter: center, recentDocumentsStore: makeDefaults())
        center.post(name: .projectDidOpenURLs, object: [rootURL])

        #expect(delegate.recentDocumentURLsForTesting.map(\.standardizedFileURL.path) == [rootURL.standardizedFileURL.path])
    }

    @Test
    func openRecentDocumentForwardsToProjectViewModel() throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let configURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("toml")
        defer { try? FileManager.default.removeItem(at: configURL) }

        let viewModel = ProjectViewModel(
            fileService: FileService(),
            sessionStore: makeDefaults(),
            sessionKey: "app-delegate-open-recent",
            configService: ConfigurationService(userConfigURL: configURL),
            fileWatcher: FileWatcherService(),
            notificationCenter: NotificationCenter(),
            ui: .test
        )

        let delegate = AppDelegate(notificationCenter: NotificationCenter(), projectViewModel: viewModel)
        let item = NSMenuItem(title: rootURL.lastPathComponent, action: #selector(AppDelegate.handleOpenRecentDocument(_:)), keyEquivalent: "")
        item.representedObject = rootURL.path

        delegate.handleOpenRecentDocument(item)

        #expect(viewModel.rootDirectory?.standardizedFileURL.path == rootURL.standardizedFileURL.path)
    }

    @Test
    func helpActionsUseInjectedPresenter() {
        var presented: [(String, String)] = []
        let delegate = AppDelegate(
            notificationCenter: NotificationCenter(),
            helpPresenter: { title, message in
                presented.append((title, message))
            }
        )

        delegate.handleShowHelp()
        delegate.handleShowKeyboardShortcuts()

        #expect(presented.count == 2)
        #expect(presented[0].0 == "Rosewood Help")
        #expect(presented[0].1 == AppDelegate.helpMessageForTesting)
        #expect(presented[1].0 == "Keyboard Shortcuts")
        #expect(presented[1].1 == AppDelegate.keyboardShortcutsMessageForTesting)
    }
}

@MainActor
private func makeDefaults() -> UserDefaults {
    let suiteName = "rosewood.appdelegate.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

private extension ProjectViewModelUI {
    static let test = ProjectViewModelUI(
        openPanel: { _, _, _ in nil },
        openPanelURLs: { _, _, _ in [] },
        savePanel: { _, _ in nil },
        alert: { _, _, _ in },
        confirm: { _, _, _, _ in .alertFirstButtonReturn }
    )
}
