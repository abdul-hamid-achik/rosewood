import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuItemValidation {
    var window: NSWindow!
    private var projectViewModel: ProjectViewModel!
    private let notificationCenter: NotificationCenter

    override init() {
        self.notificationCenter = .default
        super.init()
    }

    init(notificationCenter: NotificationCenter, projectViewModel: ProjectViewModel? = nil) {
        self.notificationCenter = notificationCenter
        self.projectViewModel = projectViewModel
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        ConfigurationService.shared.load()

        projectViewModel = ProjectViewModel()

        let contentView = ContentView()
            .environmentObject(projectViewModel)
            .environmentObject(ConfigurationService.shared)

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
        case #selector(handleFindInFile),
             #selector(handleFindNext),
             #selector(handleFindPrevious),
             #selector(handleUseSelectionForFind),
             #selector(handleShowReplace):
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

        viewMenu.addItem(withTitle: "Command Palette", action: #selector(handleCommandPalette), keyEquivalent: "P")

        let goMenuItem = NSMenuItem()
        mainMenu.addItem(goMenuItem)

        let goMenu = NSMenu(title: "Go")
        goMenuItem.submenu = goMenu

        let goToDefItem = NSMenuItem(title: "Go to Definition", action: #selector(handleGoToDefinition), keyEquivalent: "")
        goToDefItem.keyEquivalent = "\u{F704}" // F12
        goToDefItem.keyEquivalentModifierMask = []
        goMenu.addItem(goToDefItem)

        let findReferencesItem = NSMenuItem(title: "Find References", action: #selector(handleFindReferences), keyEquivalent: "")
        findReferencesItem.keyEquivalent = "\u{F704}" // F12
        findReferencesItem.keyEquivalentModifierMask = [.shift]
        goMenu.addItem(findReferencesItem)

        NSApp.mainMenu = mainMenu
    }

    @objc func handleNewFile() {
        notificationCenter.post(name: .handleNewFile, object: nil)
    }

    @objc func handleOpenFolder() {
        notificationCenter.post(name: .handleOpenFolder, object: nil)
    }

    @objc func handleSave() {
        notificationCenter.post(name: .handleSave, object: nil)
    }

    @objc func handleCommandPalette() {
        notificationCenter.post(name: .handleCommandPalette, object: nil)
    }

    @objc func handleCloseTab() {
        notificationCenter.post(name: .handleCloseTab, object: nil)
    }

    @objc func handleProjectSearch() {
        notificationCenter.post(name: .handleProjectSearch, object: nil)
    }

    @objc func handleFindInFile() {
        notificationCenter.post(name: .handleFindInFile, object: nil)
    }

    @objc func handleFindNext() {
        notificationCenter.post(name: .handleFindNext, object: nil)
    }

    @objc func handleFindPrevious() {
        notificationCenter.post(name: .handleFindPrevious, object: nil)
    }

    @objc func handleUseSelectionForFind() {
        notificationCenter.post(name: .handleUseSelectionForFind, object: nil)
    }

    @objc func handleShowReplace() {
        notificationCenter.post(name: .handleShowReplace, object: nil)
    }

    @objc func handleSettings() {
        notificationCenter.post(name: .handleSettings, object: nil)
    }

    @objc func handleGoToDefinition() {
        notificationCenter.post(name: .handleGoToDefinition, object: nil)
    }

    @objc func handleFindReferences() {
        notificationCenter.post(name: .handleFindReferences, object: nil)
    }
}

extension Notification.Name {
    static let handleFindInFile = Notification.Name("handleFindInFile")
    static let handleFindNext = Notification.Name("handleFindNext")
    static let handleFindPrevious = Notification.Name("handleFindPrevious")
    static let handleUseSelectionForFind = Notification.Name("handleUseSelectionForFind")
    static let handleShowReplace = Notification.Name("handleShowReplace")
    static let handleGoToDefinition = Notification.Name("handleGoToDefinition")
    static let handleFindReferences = Notification.Name("handleFindReferences")
    static let handleNewFile = Notification.Name("handleNewFile")
    static let handleOpenFolder = Notification.Name("handleOpenFolder")
    static let handleSave = Notification.Name("handleSave")
    static let handleCommandPalette = Notification.Name("handleCommandPalette")
    static let handleCloseTab = Notification.Name("handleCloseTab")
    static let handleProjectSearch = Notification.Name("handleProjectSearch")
    static let handleSettings = Notification.Name("handleSettings")
}
