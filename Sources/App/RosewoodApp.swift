import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuItemValidation {
    var window: NSWindow!
    private var projectViewModel: ProjectViewModel!
    private let notificationCenter: NotificationCenter?
    private let commandDispatcher: AppCommandDispatcher
    private var pendingOpenURLs: [URL] = []

    override init() {
        self.notificationCenter = nil
        self.commandDispatcher = .shared
        super.init()
    }

    init(
        notificationCenter: NotificationCenter,
        projectViewModel: ProjectViewModel? = nil,
        commandDispatcher: AppCommandDispatcher = AppCommandDispatcher()
    ) {
        self.notificationCenter = notificationCenter
        self.commandDispatcher = commandDispatcher
        self.projectViewModel = projectViewModel
        super.init()
    }

    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        ConfigurationService.shared.load()

        if projectViewModel == nil {
            projectViewModel = ProjectViewModel()
        }

        let contentView = ContentView()
            .environmentObject(projectViewModel)
            .environmentObject(projectViewModel.commandPaletteViewModel)
            .environmentObject(ConfigurationService.shared)
            .environmentObject(commandDispatcher)

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.center()
        window.setFrameAutosaveName("RosewoodMainWindow")
        window.contentView = NSHostingView(rootView: contentView)
        window.title = "Rosewood"
        window.titlebarAppearsTransparent = false
        window.isRestorable = false
        window.delegate = self
        window.makeKeyAndOrderFront(nil)

        setupMainMenu()

        NSApp.activate(ignoringOtherApps: true)
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
        projectViewModel.canCloseWindow() ? .terminateNow : .terminateCancel
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        projectViewModel.canCloseWindow()
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
             #selector(handleGoToLine):
            return projectViewModel?.hasOpenFile ?? false
        default:
            return true
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
        fileMenu.addItem(withTitle: "Open Folder...", action: #selector(handleOpenFolder), keyEquivalent: "o")
        fileMenu.addItem(withTitle: "Quick Open...", action: #selector(handleQuickOpen), keyEquivalent: "p")
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(withTitle: "Save", action: #selector(handleSave), keyEquivalent: "s")
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(withTitle: "Close Tab", action: #selector(handleCloseTab), keyEquivalent: "w")

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

        NSApp.mainMenu = mainMenu
    }

    @objc func handleNewFile() {
        dispatch(.newFile, legacyNotification: .handleNewFile)
    }

    @objc func handleOpenFolder() {
        dispatch(.openFolder, legacyNotification: .handleOpenFolder)
    }

    @objc func handleSave() {
        dispatch(.save, legacyNotification: .handleSave)
    }

    @objc func handleQuickOpen() {
        dispatch(.quickOpen, legacyNotification: .handleQuickOpen)
    }

    @objc func handleCommandPalette() {
        dispatch(.commandPalette, legacyNotification: .handleCommandPalette)
    }

    @objc func handleToggleProblems() {
        dispatch(.toggleProblems, legacyNotification: .handleToggleProblems)
    }

    @objc func handleCloseTab() {
        dispatch(.closeTab, legacyNotification: .handleCloseTab)
    }

    @objc func handleProjectSearch() {
        dispatch(.projectSearch, legacyNotification: .handleProjectSearch)
    }

    @objc func handleFindInFile() {
        dispatch(.findInFile, legacyNotification: .handleFindInFile)
    }

    @objc func handleFindNext() {
        dispatch(.findNext, legacyNotification: .handleFindNext)
    }

    @objc func handleFindPrevious() {
        dispatch(.findPrevious, legacyNotification: .handleFindPrevious)
    }

    @objc func handleUseSelectionForFind() {
        dispatch(.useSelectionForFind, legacyNotification: .handleUseSelectionForFind)
    }

    @objc func handleShowReplace() {
        dispatch(.showReplace, legacyNotification: .handleShowReplace)
    }

    @objc func handleGoToLine() {
        dispatch(.goToLine, legacyNotification: .handleGoToLine)
    }

    @objc func handleSettings() {
        dispatch(.settings, legacyNotification: .handleSettings)
    }

    @objc func handleGoToDefinition() {
        dispatch(.goToDefinition, legacyNotification: .handleGoToDefinition)
    }

    @objc func handleFindReferences() {
        dispatch(.findReferences, legacyNotification: .handleFindReferences)
    }

    @objc func handleNextProblem() {
        dispatch(.nextProblem, legacyNotification: .handleNextProblem)
    }

    @objc func handlePreviousProblem() {
        dispatch(.previousProblem, legacyNotification: .handlePreviousProblem)
    }

    private func dispatch(_ command: AppCommand, legacyNotification: Notification.Name) {
        commandDispatcher.send(command)
        notificationCenter?.post(name: legacyNotification, object: nil)
    }

    @MainActor
    private func handleOpenRequests(_ urls: [URL]) {
        let fileURLs = urls.filter(\.isFileURL)
        guard !fileURLs.isEmpty else { return }

        guard let projectViewModel else {
            pendingOpenURLs.append(contentsOf: fileURLs)
            return
        }

        projectViewModel.openExternalItems(fileURLs)
    }

    @MainActor
    private func flushPendingOpenURLs() {
        guard !pendingOpenURLs.isEmpty else { return }
        let urls = pendingOpenURLs
        pendingOpenURLs.removeAll()
        projectViewModel.openExternalItems(urls)
    }
}

extension Notification.Name {
    static let handleFindInFile = Notification.Name("handleFindInFile")
    static let handleFindNext = Notification.Name("handleFindNext")
    static let handleFindPrevious = Notification.Name("handleFindPrevious")
    static let handleNextProblem = Notification.Name("handleNextProblem")
    static let handlePreviousProblem = Notification.Name("handlePreviousProblem")
    static let handleUseSelectionForFind = Notification.Name("handleUseSelectionForFind")
    static let handleShowReplace = Notification.Name("handleShowReplace")
    static let handleGoToLine = Notification.Name("handleGoToLine")
    static let handleGoToDefinition = Notification.Name("handleGoToDefinition")
    static let handleFindReferences = Notification.Name("handleFindReferences")
    static let handleNewFile = Notification.Name("handleNewFile")
    static let handleOpenFolder = Notification.Name("handleOpenFolder")
    static let handleSave = Notification.Name("handleSave")
    static let handleQuickOpen = Notification.Name("handleQuickOpen")
    static let handleCommandPalette = Notification.Name("handleCommandPalette")
    static let handleToggleProblems = Notification.Name("handleToggleProblems")
    static let handleCloseTab = Notification.Name("handleCloseTab")
    static let handleProjectSearch = Notification.Name("handleProjectSearch")
    static let handleSettings = Notification.Name("handleSettings")
}
