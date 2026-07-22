import Cocoa
import SwiftUI

private final class AppWindowContext {
    let sessionKey: String
    let window: NSWindow
    let projectViewModel: ProjectViewModel
    let commandDispatcher: AppCommandDispatcher
    let configService: ConfigurationService

    init(
        sessionKey: String,
        window: NSWindow,
        projectViewModel: ProjectViewModel,
        commandDispatcher: AppCommandDispatcher,
        configService: ConfigurationService
    ) {
        self.sessionKey = sessionKey
        self.window = window
        self.projectViewModel = projectViewModel
        self.commandDispatcher = commandDispatcher
        self.configService = configService
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuItemValidation {
    var window: NSWindow!
    private var projectViewModel: ProjectViewModel!
    private let notificationCenter: NotificationCenter?
    private let commandDispatcher: AppCommandDispatcher
    private let recentDocumentsStore: UserDefaults
    private let helpPresenter: (String, String) -> Void
    private var pendingOpenURLs: [URL] = []
    private var recentDocumentsObserver: NSObjectProtocol?
    private weak var openRecentMenu: NSMenu?
    private var windowContexts: [ObjectIdentifier: AppWindowContext] = [:]
    private var pendingInitialProjectViewModel: ProjectViewModel?
    private var pendingCrashWindowSessionKeys: Set<String> = []

    private static let recentDocumentsKey = "rosewood.recentDocuments"
    private static let crashWindowSessionKeysKey = "rosewood.crashWindowSessionKeys"
    private static let maxRecentDocuments = 10
    private static let defaultSessionKey = "rosewood.session"
    private static let helpMessage = """
    Rosewood is a native macOS code editor for project-based development.

    Use Cmd+P for Quick Open, Cmd+Shift+P for the Command Palette, Cmd+Shift+F for Find in Project, and Cmd+Shift+T to reopen the last closed tab.

    The status bar shows cursor position, Git and ripgrep availability, and language-server state for the current file.
    """
    private static let keyboardShortcutsMessage = """
    Cmd+O - Open File
    Cmd+Shift+O - Open Folder
    Cmd+P - Quick Open
    Cmd+Shift+P - Command Palette
    Cmd+Shift+F - Find in Project
    Cmd+Shift+T - Reopen Last Closed Tab
    Cmd+S - Save
    Cmd+Shift+S - Save As
    F12 - Go to Definition
    Shift+F12 - Find References
    """

    override init() {
        self.notificationCenter = nil
        self.commandDispatcher = .shared
        self.recentDocumentsStore = .standard
        self.helpPresenter = AppDelegate.defaultHelpPresenter
        super.init()
        configureRecentDocumentsObserver()
    }

    init(
        notificationCenter: NotificationCenter,
        projectViewModel: ProjectViewModel? = nil,
        commandDispatcher: AppCommandDispatcher = AppCommandDispatcher(),
        recentDocumentsStore: UserDefaults = .standard,
        helpPresenter: @escaping (String, String) -> Void = AppDelegate.defaultHelpPresenter
    ) {
        self.notificationCenter = notificationCenter
        self.commandDispatcher = commandDispatcher
        self.pendingInitialProjectViewModel = projectViewModel
        self.projectViewModel = projectViewModel
        self.recentDocumentsStore = recentDocumentsStore
        self.helpPresenter = helpPresenter
        super.init()
        configureRecentDocumentsObserver()
    }

    deinit {
        if let recentDocumentsObserver {
            effectiveNotificationCenter.removeObserver(recentDocumentsObserver)
        }
    }

    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        if ProcessInfo.processInfo.environment["ROSEWOOD_UI_TEST_RESET_SESSION"] == "1" {
            recentDocumentsStore.removeObject(forKey: Self.recentDocumentsKey)
            recentDocumentsStore.removeObject(forKey: Self.crashWindowSessionKeysKey)
        }

        if windowContexts.isEmpty {
            if let pendingInitialProjectViewModel {
                _ = makeWindowContext(
                    projectViewModel: pendingInitialProjectViewModel,
                    sessionKey: Self.defaultSessionKey,
                    makeKey: true
                )
                self.pendingInitialProjectViewModel = nil
            } else {
                let restoredSessionKeys = crashWindowSessionKeys.isEmpty
                    ? [Self.defaultSessionKey]
                    : crashWindowSessionKeys
                pendingCrashWindowSessionKeys = Set(restoredSessionKeys)
                for (index, sessionKey) in restoredSessionKeys.enumerated() {
                    _ = makeWindowContext(
                        sessionKey: sessionKey,
                        makeKey: index == restoredSessionKeys.count - 1
                    )
                    pendingCrashWindowSessionKeys.remove(sessionKey)
                }
                persistCrashWindowSessionKeys()
            }
        }

        HighlightService.shared.prewarm()

        DispatchQueue.main.async { [weak self] in
            self?.setupMainMenu()
        }

        if !isRunningUITests {
            NSApp.activate(ignoringOtherApps: true)
        }
        flushPendingOpenURLs()
    }

    @MainActor
    func application(_ application: NSApplication, open urls: [URL]) {
        handleOpenRequests(urls)
    }

    @MainActor
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        handleOpenRequests(filenames.map { URL(fileURLWithPath: $0) })
        sender.reply(toOpenOrPrint: .success)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let contexts = Array(windowContexts.values)
        Task { @MainActor in
            var approvedContexts: [AppWindowContext] = []
            for context in contexts {
                guard await context.projectViewModel.canCloseWindow() else {
                    for approvedContext in approvedContexts {
                        approvedContext.projectViewModel.resumeAfterCancelledSessionTransition()
                    }
                    NSApp.reply(toApplicationShouldTerminate: false)
                    return
                }
                approvedContexts.append(context)
            }
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Kill any live terminal shells on quit (PTY masters also close on process death as a
        // backstop). Runs only after applicationShouldTerminate allowed .terminateNow.
        TerminalProcessController.shared.terminateAll()
        // The registry exists only to reconstruct every window after an abnormal termination.
        // A clean quit has already resolved and cleared each window's recovery journal.
        recentDocumentsStore.removeObject(forKey: Self.crashWindowSessionKeysKey)
        pendingCrashWindowSessionKeys.removeAll()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if let context = windowContexts[ObjectIdentifier(sender)] {
            Task { @MainActor in
                if await context.projectViewModel.canCloseWindow() {
                    sender.close()
                }
            }
            return false
        }
        if let projectViewModel {
            Task { @MainActor in
                if await projectViewModel.canCloseWindow() {
                    sender.close()
                }
            }
            return false
        }
        return true
    }

    func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        updateActiveContext(for: window)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        windowContexts.removeValue(forKey: ObjectIdentifier(window))
        persistCrashWindowSessionKeys()
        if self.window === window {
            updateActiveContext(for: NSApp.keyWindow ?? Array(windowContexts.values).last?.window)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !flag else { return false }
        _ = makeWindowContext(sessionKey: nextWindowSessionKey(), makeKey: true)
        return true
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(handleFindReferences):
            return projectViewModel?.canFindReferences ?? false
        case #selector(handleNextProblem),
             #selector(handlePreviousProblem):
            return projectViewModel?.canNavigateProblems ?? false
        case #selector(handleFindNext),
             #selector(handleFindPrevious):
            return (projectViewModel?.hasOpenFile ?? false)
                || (projectViewModel?.canNavigateProjectSearchResults ?? false)
        case #selector(handleToggleProblems):
            return projectViewModel?.canShowProblemsPanel ?? false
        case #selector(handleFindInFile),
             #selector(handleUseSelectionForFind),
             #selector(handleShowReplace),
             #selector(handleToggleLineComment),
             #selector(handleMoveLineUp),
             #selector(handleMoveLineDown),
             #selector(handleDuplicateLine),
             #selector(handleDeleteLine),
             #selector(handleJoinLines),
             #selector(handleGoToLine):
            return projectViewModel?.hasOpenFile ?? false
        case #selector(handleSave),
             #selector(handleSaveAs),
             #selector(handleSaveAll),
             #selector(handleCloseTab):
            return projectViewModel?.hasOpenFile ?? false
        case #selector(handleNextTab),
             #selector(handlePreviousTab):
            return (projectViewModel?.openTabs.count ?? 0) > 1
        case #selector(handleGoToTab(_:)):
            return menuItem.tag <= (projectViewModel?.openTabs.count ?? 0)
        case #selector(handleReopenClosedTab):
            return projectViewModel?.canReopenClosedTab ?? false
        default:
            return true
        }
    }

    private var isRunningUITests: Bool {
        ProcessInfo.processInfo.environment.keys.contains { $0.hasPrefix("ROSEWOOD_UI_TEST_") }
    }

    private var activeWindowContext: AppWindowContext? {
        if let keyWindow = NSApp.keyWindow,
           let context = windowContexts[ObjectIdentifier(keyWindow)] {
            return context
        }

        if let window,
           let context = windowContexts[ObjectIdentifier(window)] {
            return context
        }

        return Array(windowContexts.values).last
    }

    private func nextWindowSessionKey() -> String {
        "\(Self.defaultSessionKey).window.\(UUID().uuidString)"
    }

    @MainActor
    @discardableResult
    private func makeWindowContext(
        projectViewModel providedProjectViewModel: ProjectViewModel? = nil,
        sessionKey: String,
        makeKey: Bool
    ) -> AppWindowContext {
        let dispatcher: AppCommandDispatcher
        let configService: ConfigurationService
        let projectViewModel: ProjectViewModel

        if let providedProjectViewModel {
            dispatcher = commandDispatcher
            configService = providedProjectViewModel.configService
            projectViewModel = providedProjectViewModel
        } else {
            dispatcher = AppCommandDispatcher()
            configService = ConfigurationService()
            configService.load()
            projectViewModel = ProjectViewModel(
                fileService: .shared,
                sessionStore: .standard,
                sessionKey: sessionKey,
                recoveryStore: .live(identifier: sessionKey),
                configService: configService,
                fileWatcher: FileWatcherService(),
                notificationCenter: effectiveNotificationCenter,
                commandDispatcher: dispatcher,
                ui: .live,
                lspService: LSPService(),
                breakpointStore: BreakpointStore(),
                debugConfigurationService: DebugConfigurationService(),
                debugSessionService: DebugSessionService(),
                gitService: GitService.shared
            )
        }

        let baseContentView = ContentView()
            .environmentObject(projectViewModel)
            .environmentObject(projectViewModel.commandPaletteViewModel)
            .environmentObject(projectViewModel.dockerModel)
            .environmentObject(projectViewModel.terminalModel)
            .environmentObject(projectViewModel.referencesModel)
            .environmentObject(projectViewModel.diagnosticsModel)
            .environmentObject(projectViewModel.gitModel)
            .environmentObject(projectViewModel.cursorDisplayModel)
            .environmentObject(projectViewModel.outlineModel)
            .environmentObject(projectViewModel.debugModel)
            .environmentObject(configService)
            .environmentObject(dispatcher)
        let contentView: AnyView
        if let lspService = projectViewModel.lspService as? LSPService {
            contentView = AnyView(baseContentView.environmentObject(lspService))
        } else {
            contentView = AnyView(baseContentView)
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.center()
        window.collectionBehavior.insert(.fullScreenPrimary)
        if sessionKey == Self.defaultSessionKey {
            window.setFrameAutosaveName("RosewoodMainWindow")
        }
        window.contentView = NSHostingView(rootView: contentView)
        window.title = "Rosewood"
        window.titlebarAppearsTransparent = false
        window.isRestorable = false
        window.delegate = self
        window.identifier = NSUserInterfaceItemIdentifier(sessionKey)

        let context = AppWindowContext(
            sessionKey: sessionKey,
            window: window,
            projectViewModel: projectViewModel,
            commandDispatcher: dispatcher,
            configService: configService
        )
        windowContexts[ObjectIdentifier(window)] = context
        persistCrashWindowSessionKeys()

        if makeKey {
            window.makeKeyAndOrderFront(nil)
        } else {
            window.orderFront(nil)
        }
        updateActiveContext(for: window)
        return context
    }

    private var crashWindowSessionKeys: [String] {
        let stored = recentDocumentsStore.stringArray(forKey: Self.crashWindowSessionKeysKey) ?? []
        var seen: Set<String> = []
        return stored.filter { key in
            let isRosewoodSession = key == Self.defaultSessionKey
                || key.hasPrefix(Self.defaultSessionKey + ".window.")
            guard isRosewoodSession, seen.insert(key).inserted else {
                return false
            }
            return true
        }
    }

    private func persistCrashWindowSessionKeys() {
        let liveKeys = Set(windowContexts.values.map(\.sessionKey))
        let keys = liveKeys.union(pendingCrashWindowSessionKeys).sorted()
        if keys.isEmpty {
            recentDocumentsStore.removeObject(forKey: Self.crashWindowSessionKeysKey)
        } else {
            recentDocumentsStore.set(keys, forKey: Self.crashWindowSessionKeysKey)
        }
    }

    @MainActor
    private func updateActiveContext(for window: NSWindow?) {
        guard let window,
              let context = windowContexts[ObjectIdentifier(window)] else {
            let fallbackContext = Array(windowContexts.values).last
            self.window = fallbackContext?.window
            projectViewModel = fallbackContext?.projectViewModel
            return
        }

        self.window = context.window
        projectViewModel = context.projectViewModel
    }

    @MainActor
    private func cloneCurrentWorkspace(from sourceContext: AppWindowContext?, into context: AppWindowContext) {
        guard let sourceContext else { return }

        if let rootDirectory = sourceContext.projectViewModel.rootDirectory {
            context.projectViewModel.openExternalItems([rootDirectory])
            if let selectedFile = sourceContext.projectViewModel.selectedTab?.filePath {
                context.projectViewModel.openFile(at: selectedFile)
            }
            return
        }

        if let selectedFile = sourceContext.projectViewModel.selectedTab?.filePath {
            context.projectViewModel.openExternalItems([selectedFile])
        }
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)

        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu

        appMenu.addItem(withTitle: "About Rosewood", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Settings...", action: #selector(handleSettings), keyEquivalent: ",")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit Rosewood", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let fileMenuItem = NSMenuItem()
        mainMenu.addItem(fileMenuItem)

        let fileMenu = NSMenu(title: "File")
        fileMenuItem.submenu = fileMenu

        fileMenu.addItem(withTitle: "New File", action: #selector(handleNewFile), keyEquivalent: "n")
        let newWindowItem = fileMenu.addItem(withTitle: "New Window", action: #selector(handleNewWindow), keyEquivalent: "N")
        newWindowItem.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(withTitle: "Open File...", action: #selector(handleOpenFile), keyEquivalent: "o")
        let openFolderItem = fileMenu.addItem(withTitle: "Open Folder...", action: #selector(handleOpenFolder), keyEquivalent: "O")
        openFolderItem.keyEquivalentModifierMask = [.command, .shift]
        let openRecentItem = NSMenuItem(title: "Open Recent", action: nil, keyEquivalent: "")
        let openRecentMenu = NSMenu(title: "Open Recent")
        openRecentItem.submenu = openRecentMenu
        fileMenu.addItem(openRecentItem)
        self.openRecentMenu = openRecentMenu
        rebuildOpenRecentMenu()
        fileMenu.addItem(withTitle: "Quick Open...", action: #selector(handleQuickOpen), keyEquivalent: "p")
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(withTitle: "Save", action: #selector(handleSave), keyEquivalent: "s")
        let saveAsItem = fileMenu.addItem(withTitle: "Save As...", action: #selector(handleSaveAs), keyEquivalent: "S")
        saveAsItem.keyEquivalentModifierMask = [.command, .shift]
        let saveAllItem = fileMenu.addItem(withTitle: "Save All", action: #selector(handleSaveAll), keyEquivalent: "s")
        saveAllItem.keyEquivalentModifierMask = [.command, .option]
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(withTitle: "Close Tab", action: #selector(handleCloseTab), keyEquivalent: "w")
        let reopenClosedTabItem = fileMenu.addItem(withTitle: "Reopen Last Closed Tab", action: #selector(handleReopenClosedTab), keyEquivalent: "T")
        reopenClosedTabItem.keyEquivalentModifierMask = [.command, .shift]

        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)

        let editMenu = NSMenu(title: "Edit")
        editMenuItem.submenu = editMenu

        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenu.addItem(NSMenuItem.separator())

        let toggleCommentItem = NSMenuItem(title: "Toggle Comment", action: #selector(handleToggleLineComment), keyEquivalent: "/")
        toggleCommentItem.keyEquivalentModifierMask = [.command]
        editMenu.addItem(toggleCommentItem)

        let moveLineUpItem = NSMenuItem(title: "Move Line Up", action: #selector(handleMoveLineUp), keyEquivalent: String(UnicodeScalar(NSUpArrowFunctionKey)!))
        moveLineUpItem.keyEquivalentModifierMask = [.option]
        editMenu.addItem(moveLineUpItem)

        let moveLineDownItem = NSMenuItem(title: "Move Line Down", action: #selector(handleMoveLineDown), keyEquivalent: String(UnicodeScalar(NSDownArrowFunctionKey)!))
        moveLineDownItem.keyEquivalentModifierMask = [.option]
        editMenu.addItem(moveLineDownItem)

        let duplicateLineItem = NSMenuItem(title: "Duplicate Line", action: #selector(handleDuplicateLine), keyEquivalent: "d")
        duplicateLineItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(duplicateLineItem)

        let deleteLineItem = NSMenuItem(title: "Delete Line", action: #selector(handleDeleteLine), keyEquivalent: "k")
        deleteLineItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(deleteLineItem)

        let joinLinesItem = NSMenuItem(title: "Join Lines", action: #selector(handleJoinLines), keyEquivalent: "j")
        joinLinesItem.keyEquivalentModifierMask = [.control, .shift]
        editMenu.addItem(joinLinesItem)
        editMenu.addItem(NSMenuItem.separator())

        let findMenuItem = NSMenuItem(title: "Find", action: nil, keyEquivalent: "")
        let findMenu = NSMenu(title: "Find")
        findMenuItem.submenu = findMenu

        let findItem = NSMenuItem(title: "Find...", action: #selector(handleFindInFile), keyEquivalent: "f")
        findItem.keyEquivalentModifierMask = [.command]
        findMenu.addItem(findItem)

        let replaceItem = NSMenuItem(title: "Replace...", action: #selector(handleShowReplace), keyEquivalent: "f")
        replaceItem.keyEquivalentModifierMask = [.command, .option]
        findMenu.addItem(replaceItem)

        findMenu.addItem(NSMenuItem.separator())

        let findNextItem = NSMenuItem(title: "Find Next", action: #selector(handleFindNext), keyEquivalent: "g")
        findNextItem.keyEquivalentModifierMask = [.command]
        findMenu.addItem(findNextItem)

        let findPreviousItem = NSMenuItem(title: "Find Previous", action: #selector(handleFindPrevious), keyEquivalent: "G")
        findPreviousItem.keyEquivalentModifierMask = [.command, .shift]
        findMenu.addItem(findPreviousItem)

        let useSelectionItem = NSMenuItem(title: "Use Selection for Find", action: #selector(handleUseSelectionForFind), keyEquivalent: "e")
        useSelectionItem.keyEquivalentModifierMask = [.command]
        findMenu.addItem(useSelectionItem)

        editMenu.addItem(findMenuItem)

        let projectSearchItem = NSMenuItem(title: "Find in Project", action: #selector(handleProjectSearch), keyEquivalent: "f")
        projectSearchItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(projectSearchItem)

        let viewMenuItem = NSMenuItem()
        mainMenu.addItem(viewMenuItem)

        let viewMenu = NSMenu(title: "View")
        viewMenuItem.submenu = viewMenu

        let commandPaletteItem = NSMenuItem(title: "Command Palette", action: #selector(handleCommandPalette), keyEquivalent: "P")
        commandPaletteItem.keyEquivalentModifierMask = [.command, .shift]
        viewMenu.addItem(commandPaletteItem)

        let problemsItem = NSMenuItem(title: "Show Problems", action: #selector(handleToggleProblems), keyEquivalent: "m")
        problemsItem.keyEquivalentModifierMask = [.command, .shift]
        viewMenu.addItem(problemsItem)

        let terminalItem = NSMenuItem(title: "Terminal", action: #selector(handleToggleTerminal), keyEquivalent: "`")
        terminalItem.keyEquivalentModifierMask = [.control]
        viewMenu.addItem(terminalItem)

        viewMenu.addItem(NSMenuItem.separator())

        let zoomInItem = NSMenuItem(title: "Zoom In", action: #selector(handleZoomIn), keyEquivalent: "=")
        zoomInItem.keyEquivalentModifierMask = [.command]
        viewMenu.addItem(zoomInItem)

        let zoomOutItem = NSMenuItem(title: "Zoom Out", action: #selector(handleZoomOut), keyEquivalent: "-")
        zoomOutItem.keyEquivalentModifierMask = [.command]
        viewMenu.addItem(zoomOutItem)

        let zoomResetItem = NSMenuItem(title: "Actual Size", action: #selector(handleZoomReset), keyEquivalent: "0")
        zoomResetItem.keyEquivalentModifierMask = [.command]
        viewMenu.addItem(zoomResetItem)

        viewMenu.addItem(NSMenuItem.separator())

        let fullScreenItem = NSMenuItem(title: "Enter Full Screen", action: #selector(handleToggleFullScreen), keyEquivalent: "f")
        fullScreenItem.keyEquivalentModifierMask = [.control, .command]
        viewMenu.addItem(fullScreenItem)

        viewMenu.addItem(NSMenuItem.separator())

        let nextTabItem = NSMenuItem(title: "Show Next Tab", action: #selector(handleNextTab), keyEquivalent: "]")
        nextTabItem.keyEquivalentModifierMask = [.command, .shift]
        viewMenu.addItem(nextTabItem)

        let previousTabItem = NSMenuItem(title: "Show Previous Tab", action: #selector(handlePreviousTab), keyEquivalent: "[")
        previousTabItem.keyEquivalentModifierMask = [.command, .shift]
        viewMenu.addItem(previousTabItem)

        let goToTabItem = NSMenuItem(title: "Go to Tab", action: nil, keyEquivalent: "")
        let goToTabMenu = NSMenu(title: "Go to Tab")
        goToTabItem.submenu = goToTabMenu
        for tabNumber in 1...9 {
            let item = NSMenuItem(
                title: "Tab \(tabNumber)",
                action: #selector(handleGoToTab(_:)),
                keyEquivalent: "\(tabNumber)"
            )
            item.keyEquivalentModifierMask = [.command]
            item.tag = tabNumber
            goToTabMenu.addItem(item)
        }
        viewMenu.addItem(goToTabItem)

        let goMenuItem = NSMenuItem()
        mainMenu.addItem(goMenuItem)

        let goMenu = NSMenu(title: "Go")
        goMenuItem.submenu = goMenu

        let goToLineItem = NSMenuItem(title: "Go to Line...", action: #selector(handleGoToLine), keyEquivalent: "l")
        goToLineItem.keyEquivalentModifierMask = [.command]
        goMenu.addItem(goToLineItem)

        let goToDefItem = NSMenuItem(title: "Go to Definition", action: #selector(handleGoToDefinition), keyEquivalent: "")
        goToDefItem.keyEquivalent = "\u{F704}" // F12
        goToDefItem.keyEquivalentModifierMask = []
        goMenu.addItem(goToDefItem)

        let findReferencesItem = NSMenuItem(title: "Find References", action: #selector(handleFindReferences), keyEquivalent: "")
        findReferencesItem.keyEquivalent = "\u{F704}" // F12
        findReferencesItem.keyEquivalentModifierMask = [.shift]
        goMenu.addItem(findReferencesItem)

        let nextProblemItem = NSMenuItem(title: "Next Problem", action: #selector(handleNextProblem), keyEquivalent: "")
        nextProblemItem.keyEquivalent = "\u{F70B}" // F8
        nextProblemItem.keyEquivalentModifierMask = []
        goMenu.addItem(nextProblemItem)

        let previousProblemItem = NSMenuItem(title: "Previous Problem", action: #selector(handlePreviousProblem), keyEquivalent: "")
        previousProblemItem.keyEquivalent = "\u{F70B}" // F8
        previousProblemItem.keyEquivalentModifierMask = [.shift]
        goMenu.addItem(previousProblemItem)

        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)

        let windowMenu = NSMenu(title: "Window")
        windowMenuItem.submenu = windowMenu
        NSApp.windowsMenu = windowMenu
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(NSMenuItem.separator())
        windowMenu.addItem(withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")

        let helpMenuItem = NSMenuItem()
        mainMenu.addItem(helpMenuItem)

        let helpMenu = NSMenu(title: "Help")
        helpMenuItem.submenu = helpMenu
        helpMenu.addItem(withTitle: "Rosewood Help", action: #selector(handleShowHelp), keyEquivalent: "")
        helpMenu.addItem(withTitle: "Keyboard Shortcuts", action: #selector(handleShowKeyboardShortcuts), keyEquivalent: "")

        NSApp.mainMenu = mainMenu
    }

    @objc func handleNewFile() {
        dispatch(.newFile)
    }

    @MainActor
    @objc func handleNewWindow() {
        let sourceContext = activeWindowContext
        let context = makeWindowContext(sessionKey: nextWindowSessionKey(), makeKey: true)
        cloneCurrentWorkspace(from: sourceContext, into: context)
        notificationCenter?.post(name: .handleNewWindow, object: nil)
    }

    @objc func handleOpenFile() {
        dispatch(.openFile)
    }

    @objc func handleOpenFolder() {
        dispatch(.openFolder)
    }

    @objc func handleSave() {
        dispatch(.save)
    }

    @objc func handleSaveAs() {
        dispatch(.saveAs)
    }

    @objc func handleSaveAll() {
        dispatch(.saveAll)
    }

    @objc func handleNextTab() {
        dispatch(.nextTab)
    }

    @objc func handlePreviousTab() {
        dispatch(.previousTab)
    }

    @objc func handleGoToTab(_ sender: NSMenuItem) {
        dispatch(.goToTab(sender.tag))
    }

    @objc func handleQuickOpen() {
        dispatch(.quickOpen)
    }

    @objc func handleCommandPalette() {
        dispatch(.commandPalette)
    }

    @objc func handleToggleProblems() {
        dispatch(.toggleProblems)
    }

    @objc func handleToggleTerminal() {
        dispatch(.toggleTerminal)
    }

    @objc func handleCloseTab() {
        dispatch(.closeTab)
    }

    @objc func handleReopenClosedTab() {
        dispatch(.reopenClosedTab)
    }

    @objc func handleProjectSearch() {
        dispatch(.projectSearch)
    }

    @objc func handleFindInFile() {
        dispatch(.findInFile)
    }

    @objc func handleToggleLineComment() {
        dispatch(.toggleLineComment)
    }

    @objc func handleMoveLineUp() {
        dispatch(.moveLineUp)
    }

    @objc func handleMoveLineDown() {
        dispatch(.moveLineDown)
    }

    @objc func handleDuplicateLine() {
        dispatch(.duplicateLine)
    }

    @objc func handleDeleteLine() {
        dispatch(.deleteLine)
    }

    @objc func handleJoinLines() {
        dispatch(.joinLines)
    }

    @objc func handleZoomIn() {
        dispatch(.zoomIn)
    }

    @objc func handleZoomOut() {
        dispatch(.zoomOut)
    }

    @objc func handleZoomReset() {
        dispatch(.zoomReset)
    }

    @objc func handleToggleFullScreen() {
        NSApp.keyWindow?.toggleFullScreen(nil)
    }

    @objc func handleFindNext() {
        dispatch(.findNext)
    }

    @objc func handleFindPrevious() {
        dispatch(.findPrevious)
    }

    @objc func handleUseSelectionForFind() {
        dispatch(.useSelectionForFind)
    }

    @objc func handleShowReplace() {
        dispatch(.showReplace)
    }

    @objc func handleGoToLine() {
        dispatch(.goToLine)
    }

    @objc func handleSettings() {
        dispatch(.settings)
    }

    @objc func handleShowHelp() {
        helpPresenter("Rosewood Help", Self.helpMessage)
    }

    @objc func handleShowKeyboardShortcuts() {
        helpPresenter("Keyboard Shortcuts", Self.keyboardShortcutsMessage)
    }

    @objc func handleGoToDefinition() {
        dispatch(.goToDefinition)
    }

    @objc func handleFindReferences() {
        dispatch(.findReferences)
    }

    @objc func handleNextProblem() {
        dispatch(.nextProblem)
    }

    @objc func handlePreviousProblem() {
        dispatch(.previousProblem)
    }

    @MainActor
    @objc func handleOpenRecentDocument(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        handleOpenRequests([URL(fileURLWithPath: path)])
    }

    @objc func handleClearRecentDocuments() {
        recentDocumentsStore.removeObject(forKey: Self.recentDocumentsKey)
        rebuildOpenRecentMenu()
    }

    private func dispatch(_ command: AppCommand) {
        (activeWindowContext?.commandDispatcher ?? commandDispatcher).send(command)
    }

    @MainActor
    private func handleOpenRequests(_ urls: [URL]) {
        let fileURLs = urls.filter(\.isFileURL)
        guard !fileURLs.isEmpty else { return }

        recordRecentDocuments(fileURLs)

        let targetContext = activeWindowContext ?? (projectViewModel == nil
            ? nil
            : makeWindowContext(
                projectViewModel: projectViewModel,
                sessionKey: Self.defaultSessionKey,
                makeKey: true
            ))
        guard let targetContext else {
            pendingOpenURLs.append(contentsOf: fileURLs)
            return
        }

        updateActiveContext(for: targetContext.window)
        targetContext.projectViewModel.openExternalItems(fileURLs)
    }

    @MainActor
    private func flushPendingOpenURLs() {
        guard !pendingOpenURLs.isEmpty else { return }
        let urls = pendingOpenURLs
        pendingOpenURLs.removeAll()
        handleOpenRequests(urls)
    }

    private var effectiveNotificationCenter: NotificationCenter {
        notificationCenter ?? .default
    }

    private func configureRecentDocumentsObserver() {
        recentDocumentsObserver = effectiveNotificationCenter.addObserver(
            forName: .projectDidOpenURLs,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            guard let urls = notification.object as? [URL] else { return }
            if Thread.isMainThread {
                self?.recordRecentDocuments(urls)
            } else {
                Task { @MainActor in
                    self?.recordRecentDocuments(urls)
                }
            }
        }
    }

    private func recordRecentDocuments(_ urls: [URL]) {
        let standardizedPaths = urls
            .map(\.standardizedFileURL.path)
            .filter { !$0.isEmpty }

        guard !standardizedPaths.isEmpty else { return }

        var recentPaths = recentDocumentsStore.stringArray(forKey: Self.recentDocumentsKey) ?? []
        for path in standardizedPaths.reversed() {
            recentPaths.removeAll { $0 == path }
            recentPaths.insert(path, at: 0)
        }
        recentPaths = Array(recentPaths.prefix(Self.maxRecentDocuments))
        recentDocumentsStore.set(recentPaths, forKey: Self.recentDocumentsKey)
        rebuildOpenRecentMenu()
    }

    private func recentDocumentURLs() -> [URL] {
        let recentPaths = recentDocumentsStore.stringArray(forKey: Self.recentDocumentsKey) ?? []
        return recentPaths.map { URL(fileURLWithPath: $0) }
    }

    private func rebuildOpenRecentMenu() {
        guard let openRecentMenu else { return }
        openRecentMenu.removeAllItems()

        let recentURLs = recentDocumentURLs().filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !recentURLs.isEmpty else {
            let emptyItem = NSMenuItem(title: "No Recent Items", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            openRecentMenu.addItem(emptyItem)
            return
        }

        for url in recentURLs {
            let item = NSMenuItem(title: url.lastPathComponent, action: #selector(handleOpenRecentDocument(_:)), keyEquivalent: "")
            item.target = self
            item.toolTip = url.path
            item.representedObject = url.path
            openRecentMenu.addItem(item)
        }

        openRecentMenu.addItem(NSMenuItem.separator())
        let clearItem = NSMenuItem(title: "Clear Menu", action: #selector(handleClearRecentDocuments), keyEquivalent: "")
        clearItem.target = self
        openRecentMenu.addItem(clearItem)
    }

    var recentDocumentURLsForTesting: [URL] {
        recentDocumentURLs()
    }

    var openWindowCountForTesting: Int {
        windowContexts.count
    }

    var crashWindowSessionKeysForTesting: [String] {
        crashWindowSessionKeys
    }

    func preservePendingCrashWindowSessionKeysForTesting(_ keys: [String]) {
        pendingCrashWindowSessionKeys = Set(keys)
        persistCrashWindowSessionKeys()
    }

    static var crashWindowSessionKeysDefaultsKeyForTesting: String {
        crashWindowSessionKeysKey
    }

    static var helpMessageForTesting: String {
        helpMessage
    }

    static var keyboardShortcutsMessageForTesting: String {
        keyboardShortcutsMessage
    }

    private static func defaultHelpPresenter(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

extension Notification.Name {
    static let handleNewWindow = Notification.Name("handleNewWindow")
    static let projectDidOpenURLs = Notification.Name("projectDidOpenURLs")
}
