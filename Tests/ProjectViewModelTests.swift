import AppKit
import Foundation
import Testing
@testable import Rosewood

@Suite(.serialized)
@MainActor
struct ProjectViewModelTests {
    @Test
    func autoSavePersistsDirtyTabAfterDelay() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("swift")
        try "let value = 1\n".write(to: fileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let configURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("toml")
        defer { try? FileManager.default.removeItem(at: configURL) }

        let configService = ConfigurationService(userConfigURL: configURL)
        var settings = AppSettings.default
        settings.editor.autoSaveEnabled = true
        settings.editor.autoSaveDelay = 0.1
        configService.updateSettings(settings)

        let fileWatcher = FileWatcherService()
        let defaults = makeDefaults()
        let ui = TestProjectUI()
        let viewModel = makeViewModel(
            sessionStore: defaults,
            sessionKey: "autosave-test",
            configService: configService,
            fileWatcher: fileWatcher,
            ui: ui
        )
        fileWatcher.onExternalFileChange = nil

        viewModel.openFile(at: fileURL)
        viewModel.updateTabContent("let value = 2\n")

        try await waitUntil {
            (try? String(contentsOf: fileURL, encoding: .utf8)) == "let value = 2\n"
                && viewModel.openTabs.first?.isDirty == false
        }

        #expect(try String(contentsOf: fileURL, encoding: .utf8) == "let value = 2\n")
        #expect(viewModel.openTabs.first?.isDirty == false)
    }

    @Test
    func reloadFileTreePublishesLoadedItems() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sourcesDirectory = rootURL.appendingPathComponent("Sources", isDirectory: true)
        let fileURL = sourcesDirectory.appendingPathComponent("main.swift")

        try FileManager.default.createDirectory(at: sourcesDirectory, withIntermediateDirectories: true)
        try "print(\"hello\")".write(to: fileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let configURL = tempConfigURL()
        defer { try? FileManager.default.removeItem(at: configURL) }

        let viewModel = makeViewModel(
            sessionStore: makeDefaults(),
            sessionKey: "reload-tree-test",
            configService: ConfigurationService(userConfigURL: configURL),
            fileWatcher: FileWatcherService(),
            ui: TestProjectUI()
        )

        viewModel.rootDirectory = rootURL
        viewModel.reloadFileTree()

        try await waitUntil {
            !viewModel.fileTree.isEmpty && !viewModel.isLoadingFileTree
        }

        #expect(viewModel.fileTree.map(\.name) == ["Sources"])
        #expect(viewModel.fileTree.first?.children.map(\.name) == ["main.swift"])
    }

    @Test
    func performProjectSearchPublishesResultsAsynchronously() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let docsDirectory = rootURL.appendingPathComponent("Docs", isDirectory: true)
        let guideURL = docsDirectory.appendingPathComponent("Guide.md")

        try FileManager.default.createDirectory(at: docsDirectory, withIntermediateDirectories: true)
        try "Rosewood search target".write(to: guideURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let configURL = tempConfigURL()
        defer { try? FileManager.default.removeItem(at: configURL) }

        let viewModel = makeViewModel(
            sessionStore: makeDefaults(),
            sessionKey: "search-test",
            configService: ConfigurationService(userConfigURL: configURL),
            fileWatcher: FileWatcherService(),
            ui: TestProjectUI()
        )

        viewModel.rootDirectory = rootURL
        viewModel.projectSearchQuery = "rosewood"
        viewModel.performProjectSearch()

        try await waitUntil {
            !viewModel.projectSearchResults.isEmpty && !viewModel.isSearchingProject
        }

        #expect(viewModel.projectSearchResults.count == 1)
        #expect(viewModel.projectSearchResults.first?.filePath.standardizedFileURL.path == guideURL.standardizedFileURL.path)
    }

    @Test
    func reloadFileTreePrefersNewestRequestWhenPreviousLoadFinishesLater() async throws {
        let firstRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let secondRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        try FileManager.default.createDirectory(at: firstRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondRoot, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: firstRoot)
            try? FileManager.default.removeItem(at: secondRoot)
        }

        for index in 0..<20 {
            let fileURL = firstRoot.appendingPathComponent("Old\(index).swift")
            try "print(\(index))".write(to: fileURL, atomically: true, encoding: .utf8)
        }
        try "print(\"new\")".write(
            to: secondRoot.appendingPathComponent("Fresh.swift"),
            atomically: true,
            encoding: .utf8
        )

        let configURL = tempConfigURL()
        defer { try? FileManager.default.removeItem(at: configURL) }

        let fileService = FileService()
        fileService.directoryLoadDelayPerItemNanoseconds = 20_000_000

        let viewModel = makeViewModel(
            fileService: fileService,
            sessionStore: makeDefaults(),
            sessionKey: "reload-file-tree-race-test",
            configService: ConfigurationService(userConfigURL: configURL),
            fileWatcher: FileWatcherService(),
            ui: TestProjectUI()
        )

        viewModel.rootDirectory = firstRoot
        viewModel.reloadFileTree()
        viewModel.rootDirectory = secondRoot
        viewModel.reloadFileTree()

        try await waitUntil {
            viewModel.rootDirectory?.standardizedFileURL.path == secondRoot.standardizedFileURL.path &&
                viewModel.fileTree.map(\.name) == ["Fresh.swift"] &&
                !viewModel.isLoadingFileTree
        }

        #expect(viewModel.fileTree.map(\.name) == ["Fresh.swift"])
    }

    @Test
    func performProjectSearchPrefersNewestRequestWhenPreviousSearchFinishesLater() async throws {
        let firstRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let secondRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        try FileManager.default.createDirectory(at: firstRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondRoot, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: firstRoot)
            try? FileManager.default.removeItem(at: secondRoot)
        }

        for index in 0..<20 {
            let fileURL = firstRoot.appendingPathComponent("Alpha\(index).md")
            try "alpha match \(index)".write(to: fileURL, atomically: true, encoding: .utf8)
        }
        let betaURL = secondRoot.appendingPathComponent("Beta.md")
        try "beta target".write(to: betaURL, atomically: true, encoding: .utf8)

        let configURL = tempConfigURL()
        defer { try? FileManager.default.removeItem(at: configURL) }

        let fileService = FileService()
        fileService.projectSearchDelayPerFileNanoseconds = 20_000_000

        let viewModel = makeViewModel(
            fileService: fileService,
            sessionStore: makeDefaults(),
            sessionKey: "project-search-race-test",
            configService: ConfigurationService(userConfigURL: configURL),
            fileWatcher: FileWatcherService(),
            ui: TestProjectUI()
        )

        viewModel.rootDirectory = firstRoot
        viewModel.projectSearchQuery = "alpha"
        viewModel.performProjectSearch()

        viewModel.rootDirectory = secondRoot
        viewModel.projectSearchQuery = "beta"
        viewModel.performProjectSearch()

        try await waitUntil {
            !viewModel.isSearchingProject &&
                viewModel.projectSearchResults.count == 1 &&
                viewModel.projectSearchResults.first?.filePath.standardizedFileURL.path == betaURL.standardizedFileURL.path
        }

        #expect(viewModel.projectSearchResults.count == 1)
        #expect(viewModel.projectSearchResults.first?.filePath.standardizedFileURL.path == betaURL.standardizedFileURL.path)
        #expect(viewModel.projectSearchResults.first?.lineText == "beta target")
    }

    @Test
    func restoreSessionRegistersWatchersForOpenTabs() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("swift")
        try "print(\"hello\")".write(to: fileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let configURL = tempConfigURL()
        defer { try? FileManager.default.removeItem(at: configURL) }
        let fileWatcher = FileWatcherService()
        let defaults = makeDefaults()

        let session = ProjectSessionState(
            rootDirectoryPath: nil,
            expandedDirectoryPaths: [],
            openTabs: [
                ProjectSessionTabState(
                    filePath: fileURL.path,
                    fileName: fileURL.lastPathComponent,
                    content: "print(\"hello\")",
                    originalContent: "print(\"hello\")",
                    isDirty: false
                )
            ],
            selectedTabPath: fileURL.path
        )
        defaults.set(try JSONEncoder().encode(session), forKey: "restore-session-test")

        let viewModel = makeViewModel(
            sessionStore: defaults,
            sessionKey: "restore-session-test",
            configService: ConfigurationService(userConfigURL: configURL),
            fileWatcher: fileWatcher,
            ui: TestProjectUI()
        )

        #expect(viewModel.openTabs.count == 1)
        #expect(viewModel.selectedTab?.filePath == fileURL)
        #expect(fileWatcher.watchedURLs == Set([fileURL]))
    }

    @Test
    func restoreSessionAppliesProjectConfigSettings() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let projectConfigURL = rootURL.appendingPathComponent(".rosewood.toml")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        try configuration(fontSize: 21, autoSaveDelay: 0.4, autoSaveEnabled: false).write(
            to: projectConfigURL,
            atomically: true,
            encoding: .utf8
        )

        let configURL = tempConfigURL()
        defer { try? FileManager.default.removeItem(at: configURL) }

        let defaults = makeDefaults()
        let session = ProjectSessionState(
            rootDirectoryPath: rootURL.path,
            expandedDirectoryPaths: [],
            openTabs: [],
            selectedTabPath: nil
        )
        defaults.set(try JSONEncoder().encode(session), forKey: "restore-project-config-test")

        let configService = ConfigurationService(userConfigURL: configURL)
        _ = makeViewModel(
            sessionStore: defaults,
            sessionKey: "restore-project-config-test",
            configService: configService,
            fileWatcher: FileWatcherService(),
            ui: TestProjectUI()
        )

        #expect(configService.settings.editor.fontSize == 21)
        #expect(configService.settings.editor.autoSaveDelay == 0.4)
        #expect(configService.settings.editor.autoSaveEnabled == false)
    }

    @Test
    func renamingOpenFileMovesWatchedPath() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = rootURL.appendingPathComponent("Example.swift")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try "print(\"hello\")".write(to: fileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let configURL = tempConfigURL()
        defer { try? FileManager.default.removeItem(at: configURL) }

        let fileWatcher = FileWatcherService()
        let viewModel = makeViewModel(
            sessionStore: makeDefaults(),
            sessionKey: "rename-test",
            configService: ConfigurationService(userConfigURL: configURL),
            fileWatcher: fileWatcher,
            ui: TestProjectUI()
        )
        fileWatcher.onExternalFileChange = nil

        viewModel.openFile(at: fileURL)
        viewModel.renameItem(
            FileItem(name: fileURL.lastPathComponent, path: fileURL, isDirectory: false, children: [], isExpanded: false),
            to: "Renamed.swift"
        )

        let renamedURL = rootURL.appendingPathComponent("Renamed.swift")
        #expect(viewModel.openTabs.first?.filePath == renamedURL)
        #expect(fileWatcher.watchedURLs == Set([renamedURL]))
    }

    @Test
    func commandPaletteActionsFilterAndRunCreateFileAction() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let configURL = tempConfigURL()
        defer { try? FileManager.default.removeItem(at: configURL) }

        let viewModel = makeViewModel(
            sessionStore: makeDefaults(),
            sessionKey: "command-palette-test",
            configService: ConfigurationService(userConfigURL: configURL),
            fileWatcher: FileWatcherService(),
            ui: TestProjectUI()
        )

        viewModel.rootDirectory = rootURL
        viewModel.toggleCommandPalette()
        viewModel.commandPaletteQuery = "new"

        let actions = viewModel.commandPaletteActions
        #expect(actions.map(\.id) == ["newFile"])

        actions.first?.action()

        #expect(viewModel.showNewFileSheet == true)
        #expect(viewModel.pendingNewItemDirectory?.standardizedFileURL.path == rootURL.standardizedFileURL.path)

        viewModel.closeCommandPalette()
        #expect(viewModel.showCommandPalette == false)
    }

    @Test
    func commandPaletteOffersCreateProjectConfigAction() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let configURL = tempConfigURL()
        defer { try? FileManager.default.removeItem(at: configURL) }

        let ui = TestProjectUI()
        let viewModel = makeViewModel(
            sessionStore: makeDefaults(),
            sessionKey: "create-project-config-command-test",
            configService: ConfigurationService(userConfigURL: configURL),
            fileWatcher: FileWatcherService(),
            ui: ui
        )

        viewModel.rootDirectory = rootURL
        viewModel.commandPaletteQuery = "project config"

        let actions = viewModel.commandPaletteActions
        #expect(actions.map(\.id) == ["createProjectConfig"])

        actions.first?.action()

        #expect(FileManager.default.fileExists(atPath: rootURL.appendingPathComponent(".rosewood.toml").path))
        #expect(ui.alerts.isEmpty)
    }

    @Test
    func commandPaletteShowsFindReferencesOnlyWhenLSPIsReady() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = rootURL.appendingPathComponent("Alpha.swift")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try "let alpha = 1\n".write(to: fileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let configURL = tempConfigURL()
        defer { try? FileManager.default.removeItem(at: configURL) }

        let lspService = MockLSPService()
        let viewModel = makeViewModel(
            sessionStore: makeDefaults(),
            sessionKey: "find-references-command-test",
            configService: ConfigurationService(userConfigURL: configURL),
            fileWatcher: FileWatcherService(),
            ui: TestProjectUI(),
            lspService: lspService
        )

        viewModel.rootDirectory = rootURL
        viewModel.openFile(at: fileURL)

        #expect(!viewModel.commandPaletteActions.map(\.id).contains("findReferences"))

        lspService.setServerStatus(language: "swift", status: .ready)
        #expect(viewModel.commandPaletteActions.map(\.id).contains("findReferences"))
    }

    @Test
    func openFileSelectingExistingTabDoesNotDuplicateTab() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("swift")
        try "print(\"hello\")".write(to: fileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let configURL = tempConfigURL()
        defer { try? FileManager.default.removeItem(at: configURL) }

        let viewModel = makeViewModel(
            sessionStore: makeDefaults(),
            sessionKey: "open-file-dedup-test",
            configService: ConfigurationService(userConfigURL: configURL),
            fileWatcher: FileWatcherService(),
            ui: TestProjectUI()
        )

        viewModel.openFile(at: fileURL)
        viewModel.selectedTabIndex = nil
        viewModel.openFile(at: fileURL)

        #expect(viewModel.openTabs.count == 1)
        #expect(viewModel.selectedTabIndex == 0)
    }

    @Test
    func closeTabCancelsWhenUserRejectsDirtyClose() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("swift")
        try "print(\"before\")".write(to: fileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let configURL = tempConfigURL()
        defer { try? FileManager.default.removeItem(at: configURL) }

        let fileWatcher = FileWatcherService()
        let ui = TestProjectUI(confirmResponses: [.alertThirdButtonReturn])
        let viewModel = makeViewModel(
            sessionStore: makeDefaults(),
            sessionKey: "close-tab-cancel-test",
            configService: ConfigurationService(userConfigURL: configURL),
            fileWatcher: fileWatcher,
            ui: ui
        )

        viewModel.openFile(at: fileURL)
        viewModel.updateTabContent("print(\"dirty\")")

        let didClose = viewModel.closeTab(at: 0)

        #expect(didClose == false)
        #expect(viewModel.openTabs.count == 1)
        #expect(fileWatcher.watchedURLs == Set([fileURL]))
    }

    @Test
    func closeTabSavesDirtyFileWhenConfirmed() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("swift")
        try "print(\"before\")".write(to: fileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let configURL = tempConfigURL()
        defer { try? FileManager.default.removeItem(at: configURL) }

        let fileWatcher = FileWatcherService()
        let ui = TestProjectUI(confirmResponses: [.alertFirstButtonReturn])
        let viewModel = makeViewModel(
            sessionStore: makeDefaults(),
            sessionKey: "close-tab-save-test",
            configService: ConfigurationService(userConfigURL: configURL),
            fileWatcher: fileWatcher,
            ui: ui
        )

        viewModel.openFile(at: fileURL)
        viewModel.updateTabContent("print(\"after\")")

        let didClose = viewModel.closeTab(at: 0)

        #expect(didClose == true)
        #expect(viewModel.openTabs.isEmpty)
        #expect(fileWatcher.watchedURLs.isEmpty)
        #expect(try String(contentsOf: fileURL, encoding: .utf8) == "print(\"after\")")
    }

    @Test
    func replaceAllProjectResultsUpdatesOpenTabsAndRefreshesSearch() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = rootURL.appendingPathComponent("Example.swift")

        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try """
        let rosewood = "rosewood"
        print(rosewood)
        """.write(to: fileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let configURL = tempConfigURL()
        defer { try? FileManager.default.removeItem(at: configURL) }

        let ui = TestProjectUI(
            confirmResponses: [.alertFirstButtonReturn]
        )
        let viewModel = makeViewModel(
            sessionStore: makeDefaults(),
            sessionKey: "replace-flow-test",
            configService: ConfigurationService(userConfigURL: configURL),
            fileWatcher: FileWatcherService(),
            ui: ui
        )

        viewModel.rootDirectory = rootURL
        viewModel.openFile(at: fileURL)
        viewModel.projectSearchQuery = "rosewood"
        viewModel.projectReplaceQuery = "cedar"
        viewModel.performProjectSearch()

        try await waitUntil {
            viewModel.projectSearchResults.count == 2 && !viewModel.isSearchingProject
        }

        viewModel.replaceAllProjectResults()

        try await waitUntil {
            !viewModel.isReplacingInProject &&
                !viewModel.isSearchingProject &&
                viewModel.projectSearchResults.isEmpty &&
                viewModel.openTabs.first?.content.contains("cedar") == true
        }

        #expect(try String(contentsOf: fileURL, encoding: .utf8).contains("cedar"))
        #expect(viewModel.openTabs.first?.isDirty == false)
        #expect(ui.alerts.contains { $0.title == "Replace Complete" })
    }

    @Test
    func openFolderClearsWatchersAndLoadsNewRoot() async throws {
        let firstRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let secondRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let firstFile = firstRoot.appendingPathComponent("One.swift")
        let secondFile = secondRoot.appendingPathComponent("Two.swift")

        try FileManager.default.createDirectory(at: firstRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondRoot, withIntermediateDirectories: true)
        try "print(\"one\")".write(to: firstFile, atomically: true, encoding: .utf8)
        try "print(\"two\")".write(to: secondFile, atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(at: firstRoot)
            try? FileManager.default.removeItem(at: secondRoot)
        }

        let configURL = tempConfigURL()
        defer { try? FileManager.default.removeItem(at: configURL) }

        let fileWatcher = FileWatcherService()
        let ui = TestProjectUI(
            openPanelURLs: [firstRoot, secondRoot],
            confirmResponses: [.alertSecondButtonReturn, .alertSecondButtonReturn]
        )
        let viewModel = makeViewModel(
            sessionStore: makeDefaults(),
            sessionKey: "open-folder-test",
            configService: ConfigurationService(userConfigURL: configURL),
            fileWatcher: fileWatcher,
            ui: ui
        )

        viewModel.openFolder()
        try await waitUntil {
            viewModel.rootDirectory?.standardizedFileURL.path == firstRoot.standardizedFileURL.path &&
                viewModel.fileTree.map(\.name) == ["One.swift"] &&
                !viewModel.isLoadingFileTree
        }

        viewModel.openFile(at: firstFile)
        #expect(fileWatcher.watchedURLs == Set([firstFile]))

        viewModel.showReferences([
            LSPLocation(
                uri: firstFile.absoluteString,
                range: LSPRange(
                    start: LSPPosition(line: 0, character: 6),
                    end: LSPPosition(line: 0, character: 9)
                )
            )
        ])
        #expect(viewModel.isReferencesPanelVisible == true)

        viewModel.openFolder()
        try await waitUntil {
            viewModel.rootDirectory?.standardizedFileURL.path == secondRoot.standardizedFileURL.path &&
                viewModel.fileTree.map(\.name) == ["Two.swift"] &&
                viewModel.openTabs.isEmpty &&
                !viewModel.isLoadingFileTree
        }

        #expect(fileWatcher.watchedURLs.isEmpty)
        #expect(viewModel.referenceResults.isEmpty)
        #expect(viewModel.isReferencesPanelVisible == false)
    }

    @Test
    func openFolderOnlyPromptsToCreateProjectConfigOncePerProject() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let configURL = tempConfigURL()
        defer { try? FileManager.default.removeItem(at: configURL) }

        let ui = TestProjectUI(
            openPanelURLs: [rootURL, rootURL],
            confirmResponses: [.alertSecondButtonReturn]
        )
        let viewModel = makeViewModel(
            sessionStore: makeDefaults(),
            sessionKey: "project-config-prompt-once-test",
            configService: ConfigurationService(userConfigURL: configURL),
            fileWatcher: FileWatcherService(),
            ui: ui
        )

        viewModel.openFolder()
        try await waitUntil {
            viewModel.rootDirectory?.standardizedFileURL.path == rootURL.standardizedFileURL.path &&
                !viewModel.isLoadingFileTree
        }

        viewModel.openFolder()
        try await waitUntil {
            viewModel.rootDirectory?.standardizedFileURL.path == rootURL.standardizedFileURL.path &&
                !viewModel.isLoadingFileTree
        }

        #expect(ui.confirms.filter { $0.title == "Create Project Config?" }.count == 1)
    }

    @Test
    func showSearchSidebarPerformsSearchAndOpeningResultSetsCursorState() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = rootURL.appendingPathComponent("Match.swift")

        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try "line one\nline two target\n".write(to: fileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let configURL = tempConfigURL()
        defer { try? FileManager.default.removeItem(at: configURL) }

        let viewModel = makeViewModel(
            sessionStore: makeDefaults(),
            sessionKey: "search-sidebar-test",
            configService: ConfigurationService(userConfigURL: configURL),
            fileWatcher: FileWatcherService(),
            ui: TestProjectUI()
        )

        viewModel.rootDirectory = rootURL
        viewModel.projectSearchQuery = "target"
        viewModel.showSearchSidebar()

        try await waitUntil {
            viewModel.sidebarMode == .search &&
                viewModel.projectSearchResults.count == 1 &&
                !viewModel.isSearchingProject
        }

        let result = try #require(viewModel.projectSearchResults.first)
        viewModel.openSearchResult(result)

        #expect(viewModel.selectedTab?.filePath?.standardizedFileURL.path == fileURL.standardizedFileURL.path)
        #expect(viewModel.selectedTab?.cursorPosition.line == 2)
        #expect(viewModel.selectedTab?.cursorPosition.column == 1)
        #expect(viewModel.selectedTab?.pendingLineJump == 2)

        viewModel.clearPendingLineJump()
        #expect(viewModel.selectedTab?.pendingLineJump == nil)

        viewModel.showExplorerSidebar()
        #expect(viewModel.sidebarMode == .explorer)
    }

    @Test
    func externalFileChangeReloadsWhenConfirmed() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("swift")
        try "print(\"before\")".write(to: fileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let configURL = tempConfigURL()
        defer { try? FileManager.default.removeItem(at: configURL) }

        let fileWatcher = FileWatcherService()
        let ui = TestProjectUI(confirmResponses: [.alertFirstButtonReturn])
        let viewModel = makeViewModel(
            sessionStore: makeDefaults(),
            sessionKey: "external-reload-test",
            configService: ConfigurationService(userConfigURL: configURL),
            fileWatcher: fileWatcher,
            ui: ui
        )

        viewModel.openFile(at: fileURL)
        try "print(\"after\")".write(to: fileURL, atomically: true, encoding: .utf8)

        fileWatcher.onExternalFileChange?(fileURL)

        try await waitUntil {
            viewModel.openTabs.first?.content == "print(\"after\")"
        }

        #expect(viewModel.openTabs.first?.isDirty == false)
    }

    @Test
    func externalFileChangeIgnoreKeepsCurrentContent() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("swift")
        try "print(\"before\")".write(to: fileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let configURL = tempConfigURL()
        defer { try? FileManager.default.removeItem(at: configURL) }

        let fileWatcher = FileWatcherService()
        let ui = TestProjectUI(confirmResponses: [.alertSecondButtonReturn])
        let viewModel = makeViewModel(
            sessionStore: makeDefaults(),
            sessionKey: "external-ignore-test",
            configService: ConfigurationService(userConfigURL: configURL),
            fileWatcher: fileWatcher,
            ui: ui
        )

        viewModel.openFile(at: fileURL)
        try "print(\"after\")".write(to: fileURL, atomically: true, encoding: .utf8)

        fileWatcher.onExternalFileChange?(fileURL)

        #expect(viewModel.openTabs.first?.content == "print(\"before\")")
    }

    @Test
    func deleteItemRemovesDirectoryAndClosesDescendantTabs() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let groupURL = rootURL.appendingPathComponent("Group", isDirectory: true)
        let fileURL = groupURL.appendingPathComponent("Nested.swift")

        try FileManager.default.createDirectory(at: groupURL, withIntermediateDirectories: true)
        try "print(\"nested\")".write(to: fileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let configURL = tempConfigURL()
        defer { try? FileManager.default.removeItem(at: configURL) }

        let fileWatcher = FileWatcherService()
        let viewModel = makeViewModel(
            sessionStore: makeDefaults(),
            sessionKey: "delete-item-test",
            configService: ConfigurationService(userConfigURL: configURL),
            fileWatcher: fileWatcher,
            ui: TestProjectUI()
        )

        viewModel.rootDirectory = rootURL
        viewModel.reloadFileTree()
        try await waitUntil {
            viewModel.fileTree.count == 1 && !viewModel.isLoadingFileTree
        }

        let groupItem = try #require(viewModel.fileTree.first)
        viewModel.toggleExpand(groupItem)
        viewModel.openFile(at: fileURL)

        viewModel.deleteItem(groupItem)

        try await waitUntil {
            !FileManager.default.fileExists(atPath: groupURL.path) &&
                viewModel.openTabs.isEmpty &&
                viewModel.fileTree.isEmpty &&
                fileWatcher.watchedURLs.isEmpty
        }

        #expect(FileManager.default.fileExists(atPath: groupURL.path) == false)
    }

    @Test
    func duplicateItemOpensCopiedFile() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = rootURL.appendingPathComponent("Original.swift")

        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try "print(\"copy\")".write(to: fileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let configURL = tempConfigURL()
        defer { try? FileManager.default.removeItem(at: configURL) }

        let fileWatcher = FileWatcherService()
        let viewModel = makeViewModel(
            sessionStore: makeDefaults(),
            sessionKey: "duplicate-item-test",
            configService: ConfigurationService(userConfigURL: configURL),
            fileWatcher: fileWatcher,
            ui: TestProjectUI()
        )

        viewModel.rootDirectory = rootURL
        viewModel.duplicateItem(
            FileItem(name: fileURL.lastPathComponent, path: fileURL, isDirectory: false, children: [], isExpanded: false)
        )

        let copyURL = rootURL.appendingPathComponent("Original copy.swift")
        try await waitUntil {
            FileManager.default.fileExists(atPath: copyURL.path) &&
                viewModel.selectedTab?.filePath?.standardizedFileURL.path == copyURL.standardizedFileURL.path
        }

        #expect(viewModel.openTabs.count == 1)
        #expect(fileWatcher.watchedURLs == Set([copyURL]))
    }

    @Test
    func canCloseWindowSavesAllDirtyTabsWhenConfirmed() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let firstURL = rootURL.appendingPathComponent("One.swift")
        let secondURL = rootURL.appendingPathComponent("Two.swift")

        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try "print(\"one\")".write(to: firstURL, atomically: true, encoding: .utf8)
        try "print(\"two\")".write(to: secondURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let configURL = tempConfigURL()
        defer { try? FileManager.default.removeItem(at: configURL) }

        let ui = TestProjectUI(confirmResponses: [.alertFirstButtonReturn])
        let viewModel = makeViewModel(
            sessionStore: makeDefaults(),
            sessionKey: "close-window-test",
            configService: ConfigurationService(userConfigURL: configURL),
            fileWatcher: FileWatcherService(),
            ui: ui
        )

        viewModel.openFile(at: firstURL)
        viewModel.openFile(at: secondURL)
        viewModel.selectedTabIndex = 0
        viewModel.updateTabContent("print(\"one updated\")")
        viewModel.selectedTabIndex = 1
        viewModel.updateTabContent("print(\"two updated\")")

        let canClose = viewModel.canCloseWindow()

        #expect(canClose == true)
        #expect(viewModel.hasUnsavedChanges == false)
        #expect(try String(contentsOf: firstURL, encoding: .utf8) == "print(\"one updated\")")
        #expect(try String(contentsOf: secondURL, encoding: .utf8) == "print(\"two updated\")")
    }

    @Test
    func filteredFilesAndToggleExpandReflectFileTreeState() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let folderURL = rootURL.appendingPathComponent("Sources", isDirectory: true)
        let fileURL = folderURL.appendingPathComponent("Match.swift")
        let otherURL = rootURL.appendingPathComponent("Notes.md")

        let tree: [FileItem] = [
            FileItem(
                name: "Sources",
                path: folderURL,
                isDirectory: true,
                children: [
                    FileItem(name: "Match.swift", path: fileURL, isDirectory: false)
                ],
                isExpanded: false
            ),
            FileItem(name: "Notes.md", path: otherURL, isDirectory: false)
        ]

        let configURL = tempConfigURL()
        defer { try? FileManager.default.removeItem(at: configURL) }

        let viewModel = makeViewModel(
            sessionStore: makeDefaults(),
            sessionKey: "filter-tree-test",
            configService: ConfigurationService(userConfigURL: configURL),
            fileWatcher: FileWatcherService(),
            ui: TestProjectUI()
        )

        viewModel.fileTree = tree
        #expect(viewModel.flatFileList.map(\.name) == ["Match.swift", "Notes.md"])

        viewModel.commandPaletteQuery = "match"
        #expect(viewModel.filteredFiles.map(\.name) == ["Match.swift"])

        let folderItem = tree[0]
        viewModel.toggleExpand(folderItem)
        #expect(viewModel.fileTree.first?.isExpanded == true)

        let expandedFolder = try #require(viewModel.fileTree.first)
        viewModel.toggleExpand(expandedFolder)
        #expect(viewModel.fileTree.first?.isExpanded == false)
    }

    @Test
    func saveCurrentFileAndUpdateCursorPositionPersistTabState() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("swift")
        try "print(\"before\")".write(to: fileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let configURL = tempConfigURL()
        defer { try? FileManager.default.removeItem(at: configURL) }

        let viewModel = makeViewModel(
            sessionStore: makeDefaults(),
            sessionKey: "save-current-file-test",
            configService: ConfigurationService(userConfigURL: configURL),
            fileWatcher: FileWatcherService(),
            ui: TestProjectUI()
        )

        viewModel.openFile(at: fileURL)
        viewModel.updateCursorPosition(line: 7, column: 3)
        viewModel.updateTabContent("print(\"after\")")
        viewModel.saveCurrentFile()

        #expect(viewModel.selectedTab?.cursorPosition.line == 7)
        #expect(viewModel.selectedTab?.cursorPosition.column == 3)
        #expect(viewModel.selectedTab?.isDirty == false)
        #expect(try String(contentsOf: fileURL, encoding: .utf8) == "print(\"after\")")
    }

    @Test
    func createNewFolderAddsExpandedDirectoryToTree() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let configURL = tempConfigURL()
        defer { try? FileManager.default.removeItem(at: configURL) }

        let viewModel = makeViewModel(
            sessionStore: makeDefaults(),
            sessionKey: "create-folder-test",
            configService: ConfigurationService(userConfigURL: configURL),
            fileWatcher: FileWatcherService(),
            ui: TestProjectUI()
        )

        viewModel.rootDirectory = rootURL
        viewModel.createNewFolder(named: "NewFolder")

        let folderURL = rootURL.appendingPathComponent("NewFolder", isDirectory: true)
        try await waitUntil {
            FileManager.default.fileExists(atPath: folderURL.path) &&
                viewModel.fileTree.first?.name == "NewFolder" &&
                viewModel.fileTree.first?.isExpanded == true
        }

        #expect(viewModel.fileTree.map(\.name) == ["NewFolder"])
        #expect(viewModel.fileTree.first?.isExpanded == true)
    }

    @Test
    func toggleBreakpointSyncsDebuggerService() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = rootURL.appendingPathComponent("Example.swift")

        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try "print(\"hello\")".write(to: fileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let configURL = tempConfigURL()
        defer { try? FileManager.default.removeItem(at: configURL) }

        let debugSessionService = MockDebugSessionService()
        let viewModel = makeViewModel(
            sessionStore: makeDefaults(),
            sessionKey: "debug-breakpoint-sync-test",
            configService: ConfigurationService(userConfigURL: configURL),
            fileWatcher: FileWatcherService(),
            ui: TestProjectUI(),
            debugSessionService: debugSessionService
        )

        viewModel.rootDirectory = rootURL
        viewModel.openFile(at: fileURL)
        viewModel.toggleBreakpoint(line: 7)

        try await waitUntil {
            debugSessionService.updateBreakpointCalls.count == 1
        }

        #expect(debugSessionService.updateBreakpointCalls.first == [
            Breakpoint(filePath: fileURL.standardizedFileURL.path, line: 7)
        ])
    }

    @Test
    func startDebuggingUsesSelectedConfiguration() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = rootURL.appendingPathComponent("Example.swift")
        let programURL = rootURL.appendingPathComponent(".build/debug/App")
        let configURL = rootURL.appendingPathComponent(".rosewood.toml")

        try FileManager.default.createDirectory(at: programURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "print(\"hello\")".write(to: fileURL, atomically: true, encoding: .utf8)
        try "".write(to: programURL, atomically: true, encoding: .utf8)
        try """
        [debug]
        defaultConfiguration = "Debug App"

        [[debug.configurations]]
        name = "Debug App"
        adapter = "lldb"
        program = ".build/debug/App"
        cwd = "."
        args = ["--flag"]
        stopOnEntry = false
        """.write(to: configURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let userConfigURL = tempConfigURL()
        defer { try? FileManager.default.removeItem(at: userConfigURL) }

        let debugSessionService = MockDebugSessionService()
        debugSessionService.nextStartResult = .success(
            DebugSessionStartResult(
                adapterPath: "/usr/bin/lldb-dap",
                programPath: programURL.path,
                workingDirectoryPath: rootURL.path,
                executedPreLaunchTask: false
            )
        )

        let viewModel = makeViewModel(
            sessionStore: makeDefaults(),
            sessionKey: "debug-start-test",
            configService: ConfigurationService(userConfigURL: userConfigURL),
            fileWatcher: FileWatcherService(),
            ui: TestProjectUI(),
            debugSessionService: debugSessionService
        )

        viewModel.rootDirectory = rootURL
        viewModel.openFile(at: fileURL)
        viewModel.toggleBreakpoint(line: 3)
        viewModel.startDebugging()

        try await waitUntil {
            debugSessionService.startCalls.count == 1
        }

        let startCall = try #require(debugSessionService.startCalls.first)
        #expect(startCall.configuration.name == "Debug App")
        #expect(startCall.projectRoot?.standardizedFileURL.path == rootURL.standardizedFileURL.path)
        #expect(startCall.breakpoints == [
            Breakpoint(filePath: fileURL.standardizedFileURL.path, line: 3)
        ])
    }

    @Test
    func debugControlsRequireAnOpenFile() async throws {
        let configURL = tempConfigURL()
        defer { try? FileManager.default.removeItem(at: configURL) }
        let debugSessionService = MockDebugSessionService()

        let viewModel = makeViewModel(
            sessionStore: makeDefaults(),
            sessionKey: "debug-controls-state-test",
            configService: ConfigurationService(userConfigURL: configURL),
            fileWatcher: FileWatcherService(),
            ui: TestProjectUI(),
            debugSessionService: debugSessionService
        )

        #expect(viewModel.canAccessDebugControls == false)
        #expect(viewModel.canStartDebugging == false)
        #expect(viewModel.canStopDebugging == false)

        viewModel.rootDirectory = URL(fileURLWithPath: "/tmp/project", isDirectory: true)
        #expect(viewModel.canAccessDebugControls == false)

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("swift")
        try "print(\"hello\")".write(to: fileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        viewModel.openFile(at: fileURL)

        #expect(viewModel.canAccessDebugControls == true)
        #expect(viewModel.canStartDebugging == true)
        #expect(viewModel.canStopDebugging == false)

        debugSessionService.eventHandler?(.state(.running))
        try await waitUntil {
            viewModel.canStopDebugging
        }
        #expect(viewModel.canStopDebugging == true)
    }

    @Test
    func debugStoppedEventOpensFileAndTracksExecutionLine() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = rootURL.appendingPathComponent("Paused.swift")

        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try "print(\"pause\")".write(to: fileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let configURL = tempConfigURL()
        defer { try? FileManager.default.removeItem(at: configURL) }

        let debugSessionService = MockDebugSessionService()
        let viewModel = makeViewModel(
            sessionStore: makeDefaults(),
            sessionKey: "debug-stop-event-test",
            configService: ConfigurationService(userConfigURL: configURL),
            fileWatcher: FileWatcherService(),
            ui: TestProjectUI(),
            debugSessionService: debugSessionService
        )

        viewModel.rootDirectory = rootURL
        debugSessionService.eventHandler?(.state(.paused))
        debugSessionService.eventHandler?(.stopped(filePath: fileURL.path, line: 5, reason: "breakpoint"))

        try await waitUntil {
            viewModel.selectedTab?.filePath?.standardizedFileURL.path == fileURL.standardizedFileURL.path &&
                viewModel.currentExecutionLine == 5
        }

        #expect(viewModel.debugSessionState == .paused)
        #expect(viewModel.selectedTab?.pendingLineJump == 5)
        #expect(viewModel.debugStoppedFilePath == fileURL.standardizedFileURL.path)
    }

    // MARK: - Tab Management Context Menu Methods

    @Test
    func closeOtherTabsKeepsOnlyTargetTab() throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let file1 = rootURL.appendingPathComponent("a.swift")
        let file2 = rootURL.appendingPathComponent("b.swift")
        let file3 = rootURL.appendingPathComponent("c.swift")
        for file in [file1, file2, file3] {
            try "test".write(to: file, atomically: true, encoding: .utf8)
        }

        let configURL = tempConfigURL()
        defer { try? FileManager.default.removeItem(at: configURL) }

        let ui = TestProjectUI()
        let viewModel = makeViewModel(
            sessionStore: makeDefaults(),
            sessionKey: "close-others-test",
            configService: ConfigurationService(userConfigURL: configURL),
            fileWatcher: FileWatcherService(),
            ui: ui
        )

        viewModel.openFile(at: file1)
        viewModel.openFile(at: file2)
        viewModel.openFile(at: file3)
        #expect(viewModel.openTabs.count == 3)

        viewModel.closeOtherTabs(except: 1)
        #expect(viewModel.openTabs.count == 1)
        #expect(viewModel.openTabs[0].filePath == file2)
    }

    @Test
    func closeAllTabsClearsAllTabs() throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let file1 = rootURL.appendingPathComponent("a.swift")
        let file2 = rootURL.appendingPathComponent("b.swift")
        for file in [file1, file2] {
            try "test".write(to: file, atomically: true, encoding: .utf8)
        }

        let configURL = tempConfigURL()
        defer { try? FileManager.default.removeItem(at: configURL) }

        let ui = TestProjectUI()
        let viewModel = makeViewModel(
            sessionStore: makeDefaults(),
            sessionKey: "close-all-test",
            configService: ConfigurationService(userConfigURL: configURL),
            fileWatcher: FileWatcherService(),
            ui: ui
        )

        viewModel.openFile(at: file1)
        viewModel.openFile(at: file2)
        #expect(viewModel.openTabs.count == 2)

        viewModel.closeAllTabs()
        #expect(viewModel.openTabs.isEmpty)
    }

    @Test
    func closeTabsToTheRightRemovesOnlyLaterTabs() throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let file1 = rootURL.appendingPathComponent("a.swift")
        let file2 = rootURL.appendingPathComponent("b.swift")
        let file3 = rootURL.appendingPathComponent("c.swift")
        for file in [file1, file2, file3] {
            try "test".write(to: file, atomically: true, encoding: .utf8)
        }

        let configURL = tempConfigURL()
        defer { try? FileManager.default.removeItem(at: configURL) }

        let ui = TestProjectUI()
        let viewModel = makeViewModel(
            sessionStore: makeDefaults(),
            sessionKey: "close-right-test",
            configService: ConfigurationService(userConfigURL: configURL),
            fileWatcher: FileWatcherService(),
            ui: ui
        )

        viewModel.openFile(at: file1)
        viewModel.openFile(at: file2)
        viewModel.openFile(at: file3)
        #expect(viewModel.openTabs.count == 3)

        viewModel.closeTabsToTheRight(of: 0)
        #expect(viewModel.openTabs.count == 1)
        #expect(viewModel.openTabs[0].filePath == file1)
    }

    @Test
    func closeTabsToTheRightOfLastTabIsNoOp() throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let file1 = rootURL.appendingPathComponent("a.swift")
        try "test".write(to: file1, atomically: true, encoding: .utf8)

        let configURL = tempConfigURL()
        defer { try? FileManager.default.removeItem(at: configURL) }

        let ui = TestProjectUI()
        let viewModel = makeViewModel(
            sessionStore: makeDefaults(),
            sessionKey: "close-right-last-test",
            configService: ConfigurationService(userConfigURL: configURL),
            fileWatcher: FileWatcherService(),
            ui: ui
        )

        viewModel.openFile(at: file1)
        #expect(viewModel.openTabs.count == 1)

        viewModel.closeTabsToTheRight(of: 0)
        #expect(viewModel.openTabs.count == 1)
    }

    @Test
    func relativeFilePathStripsRootPrefix() {
        let root = URL(fileURLWithPath: "/Users/test/project")
        let tab = EditorTab(filePath: URL(fileURLWithPath: "/Users/test/project/Sources/main.swift"))

        let configURL = tempConfigURL()
        defer { try? FileManager.default.removeItem(at: configURL) }

        let ui = TestProjectUI()
        let viewModel = makeViewModel(
            sessionStore: makeDefaults(),
            sessionKey: "relative-path-test",
            configService: ConfigurationService(userConfigURL: configURL),
            fileWatcher: FileWatcherService(),
            ui: ui
        )
        viewModel.rootDirectory = root

        let relative = viewModel.relativeFilePath(tab: tab)
        #expect(relative == "Sources/main.swift")
    }

    @Test
    func relativeFilePathFallsBackToAbsolutePathOutsideRoot() {
        let root = URL(fileURLWithPath: "/Users/test/project")
        let tab = EditorTab(filePath: URL(fileURLWithPath: "/Users/test/other/main.swift"))

        let configURL = tempConfigURL()
        defer { try? FileManager.default.removeItem(at: configURL) }

        let ui = TestProjectUI()
        let viewModel = makeViewModel(
            sessionStore: makeDefaults(),
            sessionKey: "relative-outside-root-test",
            configService: ConfigurationService(userConfigURL: configURL),
            fileWatcher: FileWatcherService(),
            ui: ui
        )
        viewModel.rootDirectory = root

        let relative = viewModel.relativeFilePath(tab: tab)
        #expect(relative == "/Users/test/other/main.swift")
    }

    @Test
    func relativeFilePathReturnsNilWithoutRoot() {
        let tab = EditorTab(filePath: URL(fileURLWithPath: "/Users/test/main.swift"))

        let configURL = tempConfigURL()
        defer { try? FileManager.default.removeItem(at: configURL) }

        let ui = TestProjectUI()
        let viewModel = makeViewModel(
            sessionStore: makeDefaults(),
            sessionKey: "relative-no-root-test",
            configService: ConfigurationService(userConfigURL: configURL),
            fileWatcher: FileWatcherService(),
            ui: ui
        )

        let relative = viewModel.relativeFilePath(tab: tab)
        #expect(relative == nil)
    }

    @Test
    func copyFilePathReturnsAbsolutePath() {
        let tab = EditorTab(filePath: URL(fileURLWithPath: "/Users/test/main.swift"))

        let configURL = tempConfigURL()
        defer { try? FileManager.default.removeItem(at: configURL) }

        let ui = TestProjectUI()
        let viewModel = makeViewModel(
            sessionStore: makeDefaults(),
            sessionKey: "copy-path-test",
            configService: ConfigurationService(userConfigURL: configURL),
            fileWatcher: FileWatcherService(),
            ui: ui
        )

        let path = viewModel.copyFilePath(tab: tab)
        #expect(path == "/Users/test/main.swift")
    }

    @Test
    func copyFilePathReturnsNilForUntitled() {
        let tab = EditorTab()

        let configURL = tempConfigURL()
        defer { try? FileManager.default.removeItem(at: configURL) }

        let ui = TestProjectUI()
        let viewModel = makeViewModel(
            sessionStore: makeDefaults(),
            sessionKey: "copy-path-nil-test",
            configService: ConfigurationService(userConfigURL: configURL),
            fileWatcher: FileWatcherService(),
            ui: ui
        )

        let path = viewModel.copyFilePath(tab: tab)
        #expect(path == nil)
    }

    @Test
    func toggleDiagnosticsPanelShowsAndHidesProblemsPanel() {
        let configURL = tempConfigURL()
        defer { try? FileManager.default.removeItem(at: configURL) }

        let ui = TestProjectUI()
        let viewModel = makeViewModel(
            sessionStore: makeDefaults(),
            sessionKey: "diagnostics-panel-toggle-test",
            configService: ConfigurationService(userConfigURL: configURL),
            fileWatcher: FileWatcherService(),
            ui: ui
        )

        #expect(viewModel.isDiagnosticsPanelVisible == false)

        viewModel.toggleDiagnosticsPanel()
        #expect(viewModel.isDiagnosticsPanelVisible == true)
        #expect(viewModel.isDebugPanelVisible == false)

        viewModel.toggleDiagnosticsPanel()
        #expect(viewModel.isDiagnosticsPanelVisible == false)
    }

    @Test
    func openDiagnosticSetsPendingLineJumpOnSelectedTab() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("swift")
        try "let alpha = 1\n".write(to: fileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let configURL = tempConfigURL()
        defer { try? FileManager.default.removeItem(at: configURL) }

        let ui = TestProjectUI()
        let viewModel = makeViewModel(
            sessionStore: makeDefaults(),
            sessionKey: "open-diagnostic-test",
            configService: ConfigurationService(userConfigURL: configURL),
            fileWatcher: FileWatcherService(),
            ui: ui
        )

        viewModel.openFile(at: fileURL)
        let diagnostic = LSPDiagnostic(
            range: LSPRange(
                start: LSPPosition(line: 6, character: 3),
                end: LSPPosition(line: 6, character: 9)
            ),
            severity: .error,
            message: "Example error"
        )

        viewModel.openDiagnostic(diagnostic)

        #expect(viewModel.openTabs.first?.pendingLineJump == 7)
    }

    @Test
    func showReferencesOpensReferencesPanelWithSortedResults() throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let alphaURL = rootURL.appendingPathComponent("Alpha.swift")
        let betaURL = rootURL.appendingPathComponent("Beta.swift")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try "let alpha = 1\n".write(to: alphaURL, atomically: true, encoding: .utf8)
        try "let beta = alpha\n".write(to: betaURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let configURL = tempConfigURL()
        defer { try? FileManager.default.removeItem(at: configURL) }

        let ui = TestProjectUI()
        let viewModel = makeViewModel(
            sessionStore: makeDefaults(),
            sessionKey: "references-panel-test",
            configService: ConfigurationService(userConfigURL: configURL),
            fileWatcher: FileWatcherService(),
            ui: ui
        )

        viewModel.rootDirectory = rootURL
        viewModel.showReferences([
            LSPLocation(
                uri: betaURL.absoluteString,
                range: LSPRange(
                    start: LSPPosition(line: 0, character: 11),
                    end: LSPPosition(line: 0, character: 16)
                )
            ),
            LSPLocation(
                uri: alphaURL.absoluteString,
                range: LSPRange(
                    start: LSPPosition(line: 0, character: 4),
                    end: LSPPosition(line: 0, character: 9)
                )
            )
        ])

        #expect(viewModel.isReferencesPanelVisible == true)
        #expect(viewModel.referenceResults.count == 2)
        #expect(viewModel.referenceResults[0].path == "Alpha.swift")
        #expect(viewModel.referenceResults[1].path == "Beta.swift")
    }

    @Test
    func openReferenceResultOpensTargetFileAndQueuesLineJump() throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = rootURL.appendingPathComponent("Alpha.swift")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try "let alpha = 1\nlet beta = alpha\n".write(to: fileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let configURL = tempConfigURL()
        defer { try? FileManager.default.removeItem(at: configURL) }

        let ui = TestProjectUI()
        let viewModel = makeViewModel(
            sessionStore: makeDefaults(),
            sessionKey: "open-reference-test",
            configService: ConfigurationService(userConfigURL: configURL),
            fileWatcher: FileWatcherService(),
            ui: ui
        )

        let result = ReferenceResult(
            location: LSPLocation(
                uri: fileURL.absoluteString,
                range: LSPRange(
                    start: LSPPosition(line: 1, character: 11),
                    end: LSPPosition(line: 1, character: 16)
                )
            ),
            fileURL: fileURL,
            path: "Alpha.swift",
            line: 2,
            column: 12,
            lineText: "let beta = alpha"
        )

        viewModel.openReferenceResult(result)

        #expect(viewModel.selectedTab?.filePath == fileURL)
        #expect(viewModel.selectedTab?.pendingLineJump == 2)
    }

    @Test
    func openReferenceResultDoesNotJumpWhenFileOpenFails() throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = rootURL.appendingPathComponent("Alpha.swift")
        let missingURL = rootURL.appendingPathComponent("Missing.swift")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try "let alpha = 1\n".write(to: fileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let configURL = tempConfigURL()
        defer { try? FileManager.default.removeItem(at: configURL) }

        let ui = TestProjectUI()
        let viewModel = makeViewModel(
            sessionStore: makeDefaults(),
            sessionKey: "open-reference-failure-test",
            configService: ConfigurationService(userConfigURL: configURL),
            fileWatcher: FileWatcherService(),
            ui: ui
        )

        viewModel.openFile(at: fileURL)
        #expect(viewModel.selectedTab?.filePath == fileURL)
        #expect(viewModel.selectedTab?.pendingLineJump == nil)

        let result = ReferenceResult(
            location: LSPLocation(
                uri: missingURL.absoluteString,
                range: LSPRange(
                    start: LSPPosition(line: 1, character: 0),
                    end: LSPPosition(line: 1, character: 4)
                )
            ),
            fileURL: missingURL,
            path: "Missing.swift",
            line: 2,
            column: 1,
            lineText: ""
        )

        viewModel.openReferenceResult(result)

        #expect(viewModel.selectedTab?.filePath == fileURL)
        #expect(viewModel.selectedTab?.pendingLineJump == nil)
        #expect(ui.alerts.contains { $0.title == "Error" })
    }

    @Test
    func openFolderClosesVisibleReferencesPanel() throws {
        let initialRootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let replacementRootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let referenceFileURL = initialRootURL.appendingPathComponent("Alpha.swift")
        try FileManager.default.createDirectory(at: initialRootURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: replacementRootURL, withIntermediateDirectories: true)
        try "let alpha = 1\n".write(to: referenceFileURL, atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(at: initialRootURL)
            try? FileManager.default.removeItem(at: replacementRootURL)
        }

        let configURL = tempConfigURL()
        defer { try? FileManager.default.removeItem(at: configURL) }

        let ui = TestProjectUI(openPanelURLs: [replacementRootURL])
        let viewModel = makeViewModel(
            sessionStore: makeDefaults(),
            sessionKey: "open-folder-clears-references-test",
            configService: ConfigurationService(userConfigURL: configURL),
            fileWatcher: FileWatcherService(),
            ui: ui
        )

        viewModel.rootDirectory = initialRootURL
        viewModel.showReferences([
            LSPLocation(
                uri: referenceFileURL.absoluteString,
                range: LSPRange(
                    start: LSPPosition(line: 0, character: 4),
                    end: LSPPosition(line: 0, character: 9)
                )
            )
        ])

        #expect(viewModel.isReferencesPanelVisible == true)
        #expect(viewModel.referenceResults.count == 1)

        viewModel.openFolder()

        #expect(viewModel.rootDirectory == replacementRootURL)
        #expect(viewModel.isReferencesPanelVisible == false)
        #expect(viewModel.referenceResults.isEmpty)
    }
}

@MainActor
private final class TestProjectUI {
    struct AlertRecord {
        let title: String
        let message: String
        let style: NSAlert.Style
    }

    struct ConfirmRecord {
        let title: String
        let message: String
        let style: NSAlert.Style
        let buttons: [String]
    }

    var openPanelURLs: [URL?]
    var confirmResponses: [NSApplication.ModalResponse]
    private(set) var alerts: [AlertRecord] = []
    private(set) var confirms: [ConfirmRecord] = []

    init(
        openPanelURLs: [URL?] = [],
        confirmResponses: [NSApplication.ModalResponse] = []
    ) {
        self.openPanelURLs = openPanelURLs
        self.confirmResponses = confirmResponses
    }

    var handlers: ProjectViewModelUI {
        ProjectViewModelUI(
            openPanel: { [weak self] _, _, _ in
                guard let self, !self.openPanelURLs.isEmpty else { return nil }
                return self.openPanelURLs.removeFirst()
            },
            alert: { [weak self] title, message, style in
                self?.alerts.append(AlertRecord(title: title, message: message, style: style))
            },
            confirm: { [weak self] title, message, style, buttons in
                self?.confirms.append(ConfirmRecord(title: title, message: message, style: style, buttons: buttons))
                guard let self, !self.confirmResponses.isEmpty else {
                    return .alertSecondButtonReturn
                }
                return self.confirmResponses.removeFirst()
            }
        )
    }
}

@MainActor
private func makeViewModel(
    fileService: FileService = FileService(),
    sessionStore: UserDefaults,
    sessionKey: String,
    configService: ConfigurationService,
    fileWatcher: FileWatcherService,
    ui: TestProjectUI,
    lspService: LSPServiceProtocol? = nil,
    debugSessionService: DebugSessionServiceProtocol? = nil
) -> ProjectViewModel {
    ProjectViewModel(
        fileService: fileService,
        sessionStore: sessionStore,
        sessionKey: sessionKey,
        configService: configService,
        fileWatcher: fileWatcher,
        notificationCenter: NotificationCenter(),
        ui: ui.handlers,
        lspService: lspService ?? MockLSPService(),
        debugSessionService: debugSessionService
    )
}

@MainActor
private func makeDefaults() -> UserDefaults {
    let suiteName = "rosewood.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

private func tempConfigURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("toml")
}

private func configuration(fontSize: Double, autoSaveDelay: Double, autoSaveEnabled: Bool) -> String {
    """
    [editor]
    fontSize = \(fontSize)
    fontFamily = "SF Mono"
    tabSize = 4
    showLineNumbers = true
    wordWrap = false
    autoSaveDelay = \(autoSaveDelay)
    autoSaveEnabled = \(autoSaveEnabled ? "true" : "false")

    [theme]
    name = "nord"
    """
}

private func waitUntil(
    timeoutNanoseconds: UInt64 = 20_000_000_000,
    stepNanoseconds: UInt64 = 100_000_000,
    condition: @escaping () -> Bool
) async throws {
    let iterations = Int(timeoutNanoseconds / stepNanoseconds)
    for _ in 0..<iterations {
        if condition() {
            return
        }
        try await Task.sleep(nanoseconds: stepNanoseconds)
    }

    Issue.record("Timed out waiting for condition")
}
