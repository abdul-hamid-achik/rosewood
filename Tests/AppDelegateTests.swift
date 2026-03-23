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
            .handleOpenFolder,
            .handleSave,
            .handleCommandPalette,
            .handleCloseTab,
            .handleFindInFile,
            .handleFindNext,
            .handleFindPrevious,
            .handleUseSelectionForFind,
            .handleShowReplace,
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
        delegate.handleOpenFolder()
        delegate.handleSave()
        delegate.handleCommandPalette()
        delegate.handleCloseTab()
        delegate.handleFindInFile()
        delegate.handleFindNext()
        delegate.handleFindPrevious()
        delegate.handleUseSelectionForFind()
        delegate.handleShowReplace()
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
        alert: { _, _, _ in },
        confirm: { _, _, _, _ in .alertFirstButtonReturn }
    )
}
