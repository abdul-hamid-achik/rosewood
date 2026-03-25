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
    func projectSearchQueryAutomaticallySearchesWhenSearchSidebarIsVisible() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let docsDirectory = rootURL.appendingPathComponent("Docs", isDirectory: true)
        let guideURL = docsDirectory.appendingPathComponent("Guide.md")

        try FileManager.default.createDirectory(at: docsDirectory, withIntermediateDirectories: true)
        try "Rosewood live search target".write(to: guideURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let configURL = tempConfigURL()
        defer { try? FileManager.default.removeItem(at: configURL) }

        let viewModel = makeViewModel(
            sessionStore: makeDefaults(),
            sessionKey: "live-search-test",
            configService: ConfigurationService(userConfigURL: configURL),
            fileWatcher: FileWatcherService(),
            ui: TestProjectUI(),
            projectSearchDebounceNanoseconds: 5_000_000
        )

        viewModel.rootDirectory = rootURL
        viewModel.sidebarMode = .search
        viewModel.projectSearchQuery = "rosewood"

        try await waitUntil {
            !viewModel.projectSearchResults.isEmpty && !viewModel.isSearchingProject
        }

        #expect(viewModel.projectSearchResults.count == 1)
        #expect(viewModel.projectSearchResults.first?.filePath.standardizedFileURL.path == guideURL.standardizedFileURL.path)
    }

    @Test
    func projectSearchOptionsAutomaticallyRefreshVisibleResults() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = rootURL.appendingPathComponent("Example.swift")

        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try """
        let ROSEWOOD = 1
        let rosewood_1 = 2
        let rosewood = 3
        """.write(to: fileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let configURL = tempConfigURL()
        defer { try? FileManager.default.removeItem(at: configURL) }

        let viewModel = makeViewModel(
            sessionStore: makeDefaults(),
            sessionKey: "search-options-live-test",
            configService: ConfigurationService(userConfigURL: configURL),
            fileWatcher: FileWatcherService(),
            ui: TestProjectUI(),
            projectSearchDebounceNanoseconds: 5_000_000
        )

        viewModel.rootDirectory = rootURL
        viewModel.sidebarMode = .search
        viewModel.projectSearchQuery = "rosewood"

        try await waitUntil {
            viewModel.projectSearchResults.count == 3 && !viewModel.isSearchingProject
        }

        viewModel.projectSearchWholeWord = true

        try await waitUntil {
            viewModel.projectSearchResults.count == 2 && !viewModel.isSearchingProject
        }

        viewModel.projectSearchCaseSensitive = true

        try await waitUntil {
            viewModel.projectSearchResults.count == 1 && !viewModel.isSearchingProject
        }

        #expect(viewModel.projectSearchResults.map(\.lineNumber) == [3])
    }

    @Test
    func projectSearchFiltersByGlobWhenOptionsChange() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sourcesDirectory = rootURL.appendingPathComponent("Sources", isDirectory: true)
        let docsDirectory = rootURL.appendingPathComponent("Docs", isDirectory: true)
        let sourceFile = sourcesDirectory.appendingPathComponent("Alpha.swift")
        let docsFile = docsDirectory.appendingPathComponent("Guide.md")

        try FileManager.default.createDirectory(at: sourcesDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: docsDirectory, withIntermediateDirectories: true)
        try "let rosewood = 1\n".write(to: sourceFile, atomically: true, encoding: .utf8)
        try "rosewood docs\n".write(to: docsFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let configURL = tempConfigURL()
        defer { try? FileManager.default.removeItem(at: configURL) }

        let viewModel = makeViewModel(
            sessionStore: makeDefaults(),
            sessionKey: "search-glob-live-test",
            configService: ConfigurationService(userConfigURL: configURL),
            fileWatcher: FileWatcherService(),
            ui: TestProjectUI(),
            projectSearchDebounceNanoseconds: 5_000_000
        )

        viewModel.rootDirectory = rootURL
        viewModel.sidebarMode = .search
        viewModel.projectSearchQuery = "rosewood"

        try await waitUntil {
            viewModel.projectSearchResults.count == 2 && !viewModel.isSearchingProject
        }

        viewModel.projectSearchIncludeGlob = "Sources/**/*.swift"
        viewModel.performProjectSearch()

        try await waitUntil {
            viewModel.projectSearchResults.count == 1 && !viewModel.isSearchingProject
        }

        #expect(viewModel.projectSearchResults.first?.filePath.standardizedFileURL == sourceFile.standardizedFileURL)

        viewModel.projectSearchExcludeGlob = "Sources/**"
        viewModel.performProjectSearch()

        try await waitUntil {
            viewModel.projectSearchResults.isEmpty && !viewModel.isSearchingProject
        }
    }

    @Test
    func groupedProjectSearchResultsAggregateMatchesByFile() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sourcesDirectory = rootURL.appendingPathComponent("Sources", isDirectory: true)
        let alphaURL = sourcesDirectory.appendingPathComponent("Alpha.swift")
        let betaURL = sourcesDirectory.appendingPathComponent("Beta.swift")

        try FileManager.default.createDirectory(at: sourcesDirectory, withIntermediateDirectories: true)
        try """
          rosewood and ROSEWOOD
        next rosewood
        """.write(to: alphaURL, atomically: true, encoding: .utf8)
        try "rosewood beta".write(to: betaURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let configURL = tempConfigURL()
        defer { try? FileManager.default.removeItem(at: configURL) }

        let viewModel = makeViewModel(
            sessionStore: makeDefaults(),
            sessionKey: "grouped-search-results-test",
            configService: ConfigurationService(userConfigURL: configURL),
            fileWatcher: FileWatcherService(),
            ui: TestProjectUI(),
            projectSearchDebounceNanoseconds: 5_000_000
        )

        viewModel.rootDirectory = rootURL
        viewModel.sidebarMode = .search
        viewModel.projectSearchQuery = "rosewood"

        try await waitUntil {
            viewModel.projectSearchResults.count == 3 && !viewModel.isSearchingProject
        }

        #expect(viewModel.projectSearchMatchCount == 4)
        #expect(viewModel.groupedProjectSearchResults.map(\.fileName) == ["Alpha.swift", "Beta.swift"])
        #expect(viewModel.groupedProjectSearchResults.map(\.matchCount) == [3, 1])
        #expect(viewModel.groupedProjectSearchResults.first?.results.map(\.lineNumber) == [1, 2])
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
    func commandPaletteActionsSupportAliasesAndRankBestMatchFirst() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let configURL = tempConfigURL()
        defer { try? FileManager.default.removeItem(at: configURL) }

        let viewModel = makeViewModel(
            sessionStore: makeDefaults(),
            sessionKey: "command-palette-alias-test",
            configService: ConfigurationService(userConfigURL: configURL),
            fileWatcher: FileWatcherService(),
            ui: TestProjectUI()
        )

        viewModel.rootDirectory = rootURL
        viewModel.commandPaletteQuery = "find in files"
        #expect(viewModel.commandPaletteActions.first?.id == "showProjectSearch")

        viewModel.commandPaletteQuery = "workspace symbol"
        #expect(viewModel.commandPaletteActions.first?.id == "goToSymbol")

        viewModel.commandPaletteQuery = "proj conf"
        #expect(viewModel.commandPaletteActions.first?.id == "createProjectConfig")
    }

    @Test
    func commandPaletteWorkspaceProblemActionStartsQuickOpenInProblemMode() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let alphaURL = rootURL.appendingPathComponent("Alpha.swift")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try "let alpha = 1\n".write(to: alphaURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let configURL = tempConfigURL()
        defer { try? FileManager.default.removeItem(at: configURL) }

        let lspService = MockLSPService()
        let viewModel = makeViewModel(
            sessionStore: makeDefaults(),
            sessionKey: "command-palette-problem-quick-open-test",
            configService: ConfigurationService(userConfigURL: configURL),
            fileWatcher: FileWatcherService(),
            ui: TestProjectUI(),
            lspService: lspService
        )

        viewModel.rootDirectory = rootURL
        viewModel.openFile(at: alphaURL)
        lspService.setDiagnostics(
            uri: alphaURL.absoluteString,
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

        viewModel.commandPaletteQuery = "workspace problem"
        let action = try #require(viewModel.commandPaletteActions.first)
        #expect(action.id == "goToProblem")

        viewModel.executeCommandPaletteAction(action)
        #expect(viewModel.showQuickOpen)
        #expect(viewModel.quickOpenQuery == "!")
    }

    @Test
    func commandPaletteActionsPrioritizeRecentCommandsWhenQueryIsEmpty() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let configURL = tempConfigURL()
        defer { try? FileManager.default.removeItem(at: configURL) }

        let alphaURL = rootURL.appendingPathComponent("Alpha.swift")
        try "struct Alpha {}".write(to: alphaURL, atomically: true, encoding: .utf8)

        let viewModel = makeViewModel(
            sessionStore: makeDefaults(),
            sessionKey: "command-palette-recency-test",
            configService: ConfigurationService(userConfigURL: configURL),
            fileWatcher: FileWatcherService(),
            ui: TestProjectUI()
        )

        viewModel.rootDirectory = rootURL
        viewModel.openFile(at: alphaURL)
        viewModel.commandPaletteQuery = ""

        try #require(viewModel.commandPaletteActions.first { $0.id == "goToLine" }).action()
        #expect(viewModel.commandPaletteActions.first?.id == "goToLine")

        try #require(viewModel.commandPaletteActions.first { $0.id == "showProjectSearch" }).action()
        #expect(viewModel.commandPaletteActions.prefix(2).map(\.id) == ["showProjectSearch", "goToLine"])
    }

    @Test
    func commandPaletteSectionsExposeRecentAndGroupedCategories() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let configURL = tempConfigURL()
        defer { try? FileManager.default.removeItem(at: configURL) }

        let alphaURL = rootURL.appendingPathComponent("Alpha.swift")
        try "struct Alpha {}".write(to: alphaURL, atomically: true, encoding: .utf8)

        let viewModel = makeViewModel(
            sessionStore: makeDefaults(),
            sessionKey: "command-palette-sections-test",
            configService: ConfigurationService(userConfigURL: configURL),
            fileWatcher: FileWatcherService(),
            ui: TestProjectUI()
        )

        viewModel.rootDirectory = rootURL
        viewModel.openFile(at: alphaURL)
        try #require(viewModel.commandPaletteActions.first { $0.id == "goToLine" }).action()
        try #require(viewModel.commandPaletteActions.first { $0.id == "showProjectSearch" }).action()

        viewModel.commandPaletteQuery = ""
        #expect(viewModel.commandPaletteSections.first?.title == "Recent")
        #expect(viewModel.commandPaletteSections.first?.actions.prefix(2).map(\.id) == ["showProjectSearch", "goToLine"])
        #expect(viewModel.commandPaletteSections.first?.actions.first?.badge == "Recent")

        viewModel.commandPaletteQuery = "e"
        #expect(viewModel.commandPaletteSections.map(\.title).contains("Go"))
        #expect(viewModel.commandPaletteSections.map(\.title).contains("File"))
    }

    @Test
    func commandPaletteAliasMatchesExposeAliasDetailText() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let configURL = tempConfigURL()
        defer { try? FileManager.default.removeItem(at: configURL) }

        let viewModel = makeViewModel(
            sessionStore: makeDefaults(),
            sessionKey: "command-palette-detail-test",
            configService: ConfigurationService(userConfigURL: configURL),
            fileWatcher: FileWatcherService(),
            ui: TestProjectUI()
        )

        viewModel.rootDirectory = rootURL
        viewModel.commandPaletteQuery = "find in files"

        let action = try #require(viewModel.commandPaletteSections.first?.actions.first)
        #expect(action.id == "showProjectSearch")
        #expect(action.detailText == "Alias: find in files")
    }

    @Test
    func commandPaletteScopePrefixesFilterCategoriesAndExposeScopedHelp() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let configURL = tempConfigURL()
        defer { try? FileManager.default.removeItem(at: configURL) }

        let alphaURL = rootURL.appendingPathComponent("Alpha.swift")
        try "struct Alpha {}".write(to: alphaURL, atomically: true, encoding: .utf8)

        let viewModel = makeViewModel(
            sessionStore: makeDefaults(),
            sessionKey: "command-palette-scope-test",
            configService: ConfigurationService(userConfigURL: configURL),
            fileWatcher: FileWatcherService(),
            ui: TestProjectUI()
        )

        viewModel.rootDirectory = rootURL
        viewModel.openFile(at: alphaURL)
        viewModel.commandPaletteQuery = "go:"

        #expect(viewModel.activeCommandPaletteScope?.id == "go")
        #expect(!viewModel.commandPaletteActions.isEmpty)
        #expect(Set(viewModel.commandPaletteActions.map(\.category)) == Set(["Go"]))
        #expect(viewModel.commandPaletteHelpText.contains("Scoped to Go commands"))

        viewModel.commandPaletteQuery = "search:find"
        #expect(viewModel.activeCommandPaletteScope?.id == "search")
        #expect(viewModel.commandPaletteActions.first?.id == "showProjectSearch")
    }

    @Test
    func commandPaletteScopeTogglesOffAndEmptyStateUsesScopeContext() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let configURL = tempConfigURL()
        defer { try? FileManager.default.removeItem(at: configURL) }

        let viewModel = makeViewModel(
            sessionStore: makeDefaults(),
            sessionKey: "command-palette-scope-toggle-test",
            configService: ConfigurationService(userConfigURL: configURL),
            fileWatcher: FileWatcherService(),
            ui: TestProjectUI()
        )

        viewModel.rootDirectory = rootURL
        let searchScope = try #require(viewModel.commandPaletteScopeHints.first { $0.id == "search" })
        viewModel.applyCommandPaletteScope(searchScope)
        #expect(viewModel.commandPaletteQuery == "search:")

        viewModel.applyCommandPaletteScope(searchScope)
        #expect(viewModel.commandPaletteQuery.isEmpty)

        viewModel.commandPaletteQuery = "git:status"
        #expect(viewModel.commandPaletteActions.isEmpty)
        #expect(viewModel.commandPaletteEmptyStateText.contains("No matching git commands"))
    }

    @Test
    func commandPaletteOffersTabManagementActionsForActiveEditorState() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let alphaURL = rootURL.appendingPathComponent("Alpha.swift")
        let betaURL = rootURL.appendingPathComponent("Beta.swift")
        try "struct Alpha {}".write(to: alphaURL, atomically: true, encoding: .utf8)
        try "struct Beta {}".write(to: betaURL, atomically: true, encoding: .utf8)

        let configURL = tempConfigURL()
        defer { try? FileManager.default.removeItem(at: configURL) }

        let viewModel = makeViewModel(
            sessionStore: makeDefaults(),
            sessionKey: "command-palette-tabs-test",
            configService: ConfigurationService(userConfigURL: configURL),
            fileWatcher: FileWatcherService(),
            ui: TestProjectUI()
        )

        viewModel.rootDirectory = rootURL
        viewModel.openFile(at: alphaURL)
        viewModel.openFile(at: betaURL)
        viewModel.selectTab(at: 0)

        viewModel.commandPaletteQuery = "close other"
        #expect(viewModel.commandPaletteActions.first?.id == "closeOtherTabs")

        viewModel.commandPaletteQuery = "close right"
        #expect(viewModel.commandPaletteActions.first?.id == "closeTabsToTheRight")

        viewModel.commandPaletteQuery = "close all tabs"
        #expect(viewModel.commandPaletteActions.first?.id == "closeAllTabs")
    }

    @Test
    func commandPaletteProblemsCommandTogglesProblemsPanelAndSupportsAliases() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("swift")
        try "let alpha = 1\n".write(to: fileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let configURL = tempConfigURL()
        defer { try? FileManager.default.removeItem(at: configURL) }

        let viewModel = makeViewModel(
            sessionStore: makeDefaults(),
            sessionKey: "command-palette-problems-test",
            configService: ConfigurationService(userConfigURL: configURL),
            fileWatcher: FileWatcherService(),
            ui: TestProjectUI()
        )

        viewModel.openFile(at: fileURL)

        viewModel.commandPaletteQuery = "diagnostics"
        let showProblemsAction = try #require(viewModel.commandPaletteSections.first?.actions.first)
        #expect(showProblemsAction.id == "showProblemsPanel")
        #expect(showProblemsAction.detailText == "Alias: diagnostics")

        showProblemsAction.action()
        #expect(viewModel.isDiagnosticsPanelVisible == true)

        viewModel.commandPaletteQuery = "problems"
        #expect(viewModel.commandPaletteActions.first?.id == "hideProblemsPanel")
    }

    @Test
    func commandPaletteReferencesCommandReflectsExistingReferenceResults() throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let alphaURL = rootURL.appendingPathComponent("Alpha.swift")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try "let alpha = 1\n".write(to: alphaURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let configURL = tempConfigURL()
        defer { try? FileManager.default.removeItem(at: configURL) }

        let viewModel = makeViewModel(
            sessionStore: makeDefaults(),
            sessionKey: "command-palette-references-test",
            configService: ConfigurationService(userConfigURL: configURL),
            fileWatcher: FileWatcherService(),
            ui: TestProjectUI()
        )

        viewModel.rootDirectory = rootURL
        viewModel.showReferences([
            LSPLocation(
                uri: alphaURL.absoluteString,
                range: LSPRange(
                    start: LSPPosition(line: 0, character: 4),
                    end: LSPPosition(line: 0, character: 9)
                )
            )
        ])

        viewModel.commandPaletteQuery = "references panel"
        #expect(viewModel.commandPaletteActions.first?.id == "hideReferencesPanel")

        let hideReferencesAction = try #require(viewModel.commandPaletteActions.first)
        hideReferencesAction.action()
        #expect(viewModel.isReferencesPanelVisible == false)

        viewModel.commandPaletteQuery = "reference results"
        #expect(viewModel.commandPaletteActions.first?.id == "showReferencesPanel")
    }

    @Test
    func commandPaletteOffersSidebarNavigationCommands() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let configURL = tempConfigURL()
        defer { try? FileManager.default.removeItem(at: configURL) }

        let viewModel = makeViewModel(
            sessionStore: makeDefaults(),
            sessionKey: "command-palette-sidebar-nav-test",
            configService: ConfigurationService(userConfigURL: configURL),
            fileWatcher: FileWatcherService(),
            ui: TestProjectUI()
        )

        viewModel.rootDirectory = rootURL

        viewModel.commandPaletteQuery = "explorer"
        #expect(viewModel.commandPaletteActions.first?.id == "showExplorer")

        viewModel.commandPaletteQuery = "debugger"
        #expect(viewModel.commandPaletteActions.first?.id == "showDebugSidebar")

        viewModel.commandPaletteQuery = "source control"
        #expect(viewModel.commandPaletteActions.first?.id == "showSourceControl")
    }

    @Test
    func commandPaletteFileUtilityCommandsCopyPathsAndRevealCurrentFile() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let fileURL = rootURL.appendingPathComponent("Sources").appendingPathComponent("Alpha.swift")
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "struct Alpha {}".write(to: fileURL, atomically: true, encoding: .utf8)

        let configURL = tempConfigURL()
        defer { try? FileManager.default.removeItem(at: configURL) }

        let viewModel = makeViewModel(
            sessionStore: makeDefaults(),
            sessionKey: "command-palette-file-utility-test",
            configService: ConfigurationService(userConfigURL: configURL),
            fileWatcher: FileWatcherService(),
            ui: TestProjectUI()
        )

        viewModel.rootDirectory = rootURL
        viewModel.openFile(at: fileURL)

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        viewModel.commandPaletteQuery = "copy path"
        let copyPathAction = try #require(viewModel.commandPaletteActions.first)
        copyPathAction.action()
        #expect(pasteboard.string(forType: .string) == fileURL.path)

        pasteboard.clearContents()

        viewModel.commandPaletteQuery = "copy relative path"
        let copyRelativePathAction = try #require(viewModel.commandPaletteActions.first)
        copyRelativePathAction.action()
        #expect(pasteboard.string(forType: .string) == "Sources/Alpha.swift")

        viewModel.commandPaletteQuery = "reveal file"
        #expect(viewModel.commandPaletteActions.first?.id == "revealCurrentFileInFinder")
    }

    @Test
    func commandPaletteOffersDebugCommandsAndConfigurationSelection() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = rootURL.appendingPathComponent("Alpha.swift")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try "struct Alpha {}".write(to: fileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let configURL = tempConfigURL()
        defer { try? FileManager.default.removeItem(at: configURL) }

        let viewModel = makeViewModel(
            sessionStore: makeDefaults(),
            sessionKey: "command-palette-debug-actions-test",
            configService: ConfigurationService(userConfigURL: configURL),
            fileWatcher: FileWatcherService(),
            ui: TestProjectUI()
        )

        viewModel.rootDirectory = rootURL
        viewModel.openFile(at: fileURL)
        viewModel.debugConfigurations = [
            DebugConfiguration(
                name: "App",
                adapter: "lldb",
                program: ".build/debug/App",
                cwd: ".",
                args: [],
                preLaunchTask: nil,
                stopOnEntry: false
            ),
            DebugConfiguration(
                name: "Tests",
                adapter: "lldb",
                program: ".build/debug/Tests",
                cwd: ".",
                args: ["--filter", "smoke"],
                preLaunchTask: nil,
                stopOnEntry: false
            )
        ]
        viewModel.selectedDebugConfigurationName = "App"

        viewModel.commandPaletteQuery = "run debugger"
        #expect(viewModel.commandPaletteActions.first?.id == "startDebugging")

        viewModel.commandPaletteQuery = "debug:"
        #expect(viewModel.activeCommandPaletteScope?.id == "debug")
        #expect(Set(viewModel.commandPaletteActions.map(\.category)) == Set(["Debug"]))
        #expect(viewModel.commandPaletteActions.contains { $0.id == "startDebugging" })
        #expect(viewModel.commandPaletteActions.contains { $0.id == "showDebugConsole" })
        #expect(viewModel.commandPaletteActions.contains { $0.id == "selectDebugConfiguration-tests" })
    }

    @Test
    func commandPaletteDebugCommandsDispatchToDebuggerAndConsole() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = rootURL.appendingPathComponent("Alpha.swift")
        let appProgramURL = rootURL.appendingPathComponent(".build/debug/App")
        let testsProgramURL = rootURL.appendingPathComponent(".build/debug/Tests")
        let projectConfigURL = rootURL.appendingPathComponent(".rosewood.toml")

        try FileManager.default.createDirectory(at: appProgramURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "struct Alpha {}".write(to: fileURL, atomically: true, encoding: .utf8)
        try "".write(to: appProgramURL, atomically: true, encoding: .utf8)
        try "".write(to: testsProgramURL, atomically: true, encoding: .utf8)
        try """
        [debug]
        defaultConfiguration = "App"

        [[debug.configurations]]
        name = "App"
        adapter = "lldb"
        program = ".build/debug/App"
        cwd = "."
        args = []
        stopOnEntry = false

        [[debug.configurations]]
        name = "Tests"
        adapter = "lldb"
        program = ".build/debug/Tests"
        cwd = "."
        args = ["--filter", "smoke"]
        stopOnEntry = false
        """.write(to: projectConfigURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let userConfigURL = tempConfigURL()
        defer { try? FileManager.default.removeItem(at: userConfigURL) }

        let debugSessionService = MockDebugSessionService()
        debugSessionService.nextStartResult = .success(
            DebugSessionStartResult(
                adapterPath: "/usr/bin/lldb-dap",
                programPath: testsProgramURL.path,
                workingDirectoryPath: rootURL.path,
                executedPreLaunchTask: false
            )
        )

        let viewModel = makeViewModel(
            sessionStore: makeDefaults(),
            sessionKey: "command-palette-debug-dispatch-test",
            configService: ConfigurationService(userConfigURL: userConfigURL),
            fileWatcher: FileWatcherService(),
            ui: TestProjectUI(),
            debugSessionService: debugSessionService
        )

        viewModel.rootDirectory = rootURL
        viewModel.openFile(at: fileURL)
        viewModel.debugConfigurations = [
            DebugConfiguration(
                name: "App",
                adapter: "lldb",
                program: ".build/debug/App",
                cwd: ".",
                args: [],
                preLaunchTask: nil,
                stopOnEntry: false
            ),
            DebugConfiguration(
                name: "Tests",
                adapter: "lldb",
                program: ".build/debug/Tests",
                cwd: ".",
                args: ["--filter", "smoke"],
                preLaunchTask: nil,
                stopOnEntry: false
            )
        ]
        viewModel.selectedDebugConfigurationName = "App"

        viewModel.commandPaletteQuery = "show console"
        try #require(viewModel.commandPaletteActions.first).action()
        #expect(viewModel.isDebugPanelVisible == true)

        debugSessionService.eventHandler?(.output(.info, "Debugger booted"))
        try await waitUntil {
            !viewModel.debugConsoleEntries.isEmpty
        }

        viewModel.commandPaletteQuery = "clear console"
        try #require(viewModel.commandPaletteActions.first { $0.id == "clearDebugConsole" }).action()
        #expect(viewModel.debugConsoleEntries.isEmpty)

        viewModel.commandPaletteQuery = "switch debug configuration tests"
        try #require(viewModel.commandPaletteActions.first { $0.id == "selectDebugConfiguration-tests" }).action()
        #expect(viewModel.selectedDebugConfigurationName == "Tests")

        viewModel.commandPaletteQuery = "run debugger"
        try #require(viewModel.commandPaletteActions.first { $0.id == "startDebugging" }).action()

        try await waitUntil {
            debugSessionService.startCalls.count == 1
        }

        #expect(debugSessionService.startCalls.first?.configuration.name == "Tests")

        debugSessionService.eventHandler?(.state(.running))
        let initialStopCallCount = debugSessionService.stopCallCount

        viewModel.commandPaletteQuery = "stop debugger"
        try #require(viewModel.commandPaletteActions.first { $0.id == "stopDebugging" }).action()

        try await waitUntil {
            debugSessionService.stopCallCount == initialStopCallCount + 1
        }

        #expect(debugSessionService.stopCallCount == initialStopCallCount + 1)
    }

    @Test
    func commandPaletteOffersProblemBreakpointAndStopLocationCommands() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let alphaURL = rootURL.appendingPathComponent("Alpha.swift")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try """
        let alpha = 1
        let beta = alpha + 1
        let gamma = beta + 1
        """.write(to: alphaURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let configURL = tempConfigURL()
        defer { try? FileManager.default.removeItem(at: configURL) }

        let lspService = MockLSPService()
        let debugSessionService = MockDebugSessionService()
        let viewModel = makeViewModel(
            sessionStore: makeDefaults(),
            sessionKey: "command-palette-go-actions-test",
            configService: ConfigurationService(userConfigURL: configURL),
            fileWatcher: FileWatcherService(),
            ui: TestProjectUI(),
            lspService: lspService,
            debugSessionService: debugSessionService
        )

        viewModel.rootDirectory = rootURL
        viewModel.openFile(at: alphaURL)
        let uri = try #require(viewModel.selectedTab?.documentURI)
        lspService.injectDiagnosticsForTesting(
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
        viewModel.toggleBreakpoint(line: 1)
        debugSessionService.eventHandler?(.stopped(filePath: alphaURL.path, line: 2, reason: "breakpoint"))

        try await waitUntil {
            viewModel.hasCurrentDebugStopLocation
        }

        viewModel.commandPaletteQuery = "go:"
        #expect(viewModel.activeCommandPaletteScope?.id == "go")
        #expect(viewModel.commandPaletteActions.contains { $0.id == "nextProblem" })
        #expect(viewModel.commandPaletteActions.contains { $0.id == "nextBreakpoint" })
        #expect(viewModel.commandPaletteActions.contains { $0.id == "openCurrentDebugStopLocation" })
    }

    @Test
    func commandPaletteOffersContextualGitReviewActions() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let firstURL = rootURL.appendingPathComponent("First.swift")
        let secondURL = rootURL.appendingPathComponent("Second.swift")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try "let first = 1\n".write(to: firstURL, atomically: true, encoding: .utf8)
        try "let second = 1\n".write(to: secondURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let configURL = tempConfigURL()
        defer { try? FileManager.default.removeItem(at: configURL) }

        let firstChange = GitChangedFile(
            path: "First.swift",
            previousPath: nil,
            kind: .modified,
            indexStatus: " ",
            workingTreeStatus: "M"
        )
        let secondChange = GitChangedFile(
            path: "Second.swift",
            previousPath: nil,
            kind: .modified,
            indexStatus: "M",
            workingTreeStatus: " "
        )

        let gitService = MockGitService()
        gitService.repositoryStatusResult = GitRepositoryStatus(
            repositoryRoot: rootURL,
            branchName: "main",
            changedFiles: [firstChange, secondChange],
            ignoredPaths: []
        )
        gitService.diffResults[firstChange.path] = GitDiffResult(path: firstChange.path, text: "@@ -1 +1 @@\n-let first = 0\n+let first = 1")
        gitService.diffResults[secondChange.path] = GitDiffResult(path: secondChange.path, text: "@@ -1 +1 @@\n-let second = 0\n+let second = 1")

        let viewModel = makeViewModel(
            sessionStore: makeDefaults(),
            sessionKey: "command-palette-git-review-test",
            configService: ConfigurationService(userConfigURL: configURL),
            fileWatcher: FileWatcherService(),
            ui: TestProjectUI(),
            gitService: gitService
        )

        viewModel.rootDirectory = rootURL
        viewModel.refreshGitState()
        try await waitUntil {
            viewModel.gitRepositoryStatus.changedFiles.count == 2
        }

        viewModel.openGitChangedFile(firstChange)
        try await waitUntil {
            viewModel.selectedGitDiffPath == firstChange.path
        }

        viewModel.commandPaletteQuery = "next diff"
        #expect(viewModel.commandPaletteActions.first?.id == "showNextGitChange")

        viewModel.commandPaletteQuery = "stage file"
        #expect(viewModel.commandPaletteActions.first?.id == "stageSelectedGitChange")

        viewModel.commandPaletteQuery = "open selected change"
        #expect(viewModel.commandPaletteActions.first?.id == "openSelectedGitChangeInEditor")

        viewModel.showNextGitChange()
        try await waitUntil {
            viewModel.selectedGitDiffPath == secondChange.path
        }

        viewModel.commandPaletteQuery = "previous diff"
        #expect(viewModel.commandPaletteActions.first?.id == "showPreviousGitChange")

        viewModel.commandPaletteQuery = "remove from staged"
        #expect(viewModel.commandPaletteActions.first?.id == "unstageSelectedGitChange")
    }

    @Test
    func commandPaletteGitReviewActionsDispatchToWorkspaceAndGitService() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = rootURL.appendingPathComponent("Tracked.swift")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try "let tracked = 1\n".write(to: fileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let configURL = tempConfigURL()
        defer { try? FileManager.default.removeItem(at: configURL) }

        let changedFile = GitChangedFile(
            path: "Tracked.swift",
            previousPath: nil,
            kind: .modified,
            indexStatus: " ",
            workingTreeStatus: "M"
        )

        let gitService = MockGitService()
        gitService.repositoryStatusResult = GitRepositoryStatus(
            repositoryRoot: rootURL,
            branchName: "main",
            changedFiles: [changedFile],
            ignoredPaths: []
        )
        gitService.diffResults[changedFile.path] = GitDiffResult(path: changedFile.path, text: "@@ -1 +1 @@\n-let tracked = 0\n+let tracked = 1")

        let ui = TestProjectUI(confirmResponses: [.alertFirstButtonReturn])
        let viewModel = makeViewModel(
            sessionStore: makeDefaults(),
            sessionKey: "command-palette-git-dispatch-test",
            configService: ConfigurationService(userConfigURL: configURL),
            fileWatcher: FileWatcherService(),
            ui: ui,
            gitService: gitService
        )

        viewModel.rootDirectory = rootURL
        viewModel.refreshGitState()
        try await waitUntil {
            viewModel.gitRepositoryStatus.changedFiles.count == 1
        }

        viewModel.openGitChangedFile(changedFile)
        try await waitUntil {
            viewModel.selectedGitDiffPath == changedFile.path
        }

        viewModel.commandPaletteQuery = "focus change in files"
        try #require(viewModel.commandPaletteActions.first).action()
        #expect(viewModel.sidebarMode == .explorer)
        #expect(viewModel.isGitDiffWorkspaceVisible)

        viewModel.openGitChangedFile(changedFile)
        try await waitUntil {
            viewModel.selectedGitDiffPath == changedFile.path
        }

        viewModel.commandPaletteQuery = "open diff file"
        try #require(viewModel.commandPaletteActions.first).action()
        #expect(viewModel.isGitDiffWorkspaceVisible == false)
        #expect(viewModel.selectedTab?.filePath?.standardizedFileURL.path == fileURL.standardizedFileURL.path)

        viewModel.openGitChangedFile(changedFile)
        try await waitUntil {
            viewModel.selectedGitDiffPath == changedFile.path
        }

        viewModel.commandPaletteQuery = "git add"
        try #require(viewModel.commandPaletteActions.first).action()

        try await waitUntil {
            gitService.stageCalls.count == 1
        }

        #expect(gitService.stageCalls == ["Tracked.swift"])
    }

    @Test
    func quickOpenFiltersFilesByRelativePathAndResetsQueryOnOpen() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sourcesURL = rootURL.appendingPathComponent("Sources", isDirectory: true)
        let nestedURL = sourcesURL.appendingPathComponent("Feature", isDirectory: true)
        let matchingURL = nestedURL.appendingPathComponent("Match.swift")
        let otherURL = rootURL.appendingPathComponent("Notes.md")

        try FileManager.default.createDirectory(at: nestedURL, withIntermediateDirectories: true)
        try "print(\"match\")".write(to: matchingURL, atomically: true, encoding: .utf8)
        try "# Notes".write(to: otherURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let configURL = tempConfigURL()
        defer { try? FileManager.default.removeItem(at: configURL) }

        let viewModel = makeViewModel(
            sessionStore: makeDefaults(),
            sessionKey: "quick-open-test",
            configService: ConfigurationService(userConfigURL: configURL),
            fileWatcher: FileWatcherService(),
            ui: TestProjectUI()
        )

        viewModel.rootDirectory = rootURL
        viewModel.fileTree = [
            FileItem(
                name: "Sources",
                path: sourcesURL,
                isDirectory: true,
                children: [
                    FileItem(
                        name: "Feature",
                        path: nestedURL,
                        isDirectory: true,
                        children: [
                            FileItem(name: "Match.swift", path: matchingURL, isDirectory: false)
                        ]
                    )
                ]
            ),
            FileItem(name: "Notes.md", path: otherURL, isDirectory: false)
        ]

        viewModel.quickOpenQuery = "stale"
        viewModel.toggleQuickOpen()

        #expect(viewModel.showQuickOpen == true)
        #expect(viewModel.quickOpenQuery.isEmpty)

        viewModel.quickOpenQuery = "feature"

        #expect(viewModel.quickOpenItems.compactMap { $0.file?.name } == ["Match.swift"])
        #expect(viewModel.quickOpenItems.first?.displayPath == "Sources/Feature/Match.swift")

        viewModel.closeCommandPalette()
        #expect(viewModel.showQuickOpen == false)
    }

    @Test
    func quickOpenPrioritizesOpenTabsAndStrongerMatches() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sourcesURL = rootURL.appendingPathComponent("Sources", isDirectory: true)
        let pathOnlyFolderURL = rootURL.appendingPathComponent("Match", isDirectory: true)
        let selectedURL = rootURL.appendingPathComponent("Selected.md")
        let prefixURL = sourcesURL.appendingPathComponent("MatchUtilities.swift")
        let containsURL = sourcesURL.appendingPathComponent("FeatureMatch.swift")
        let pathOnlyURL = pathOnlyFolderURL.appendingPathComponent("Utilities.swift")

        try FileManager.default.createDirectory(at: sourcesURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: pathOnlyFolderURL, withIntermediateDirectories: true)
        try "selected".write(to: selectedURL, atomically: true, encoding: .utf8)
        try "prefix".write(to: prefixURL, atomically: true, encoding: .utf8)
        try "contains".write(to: containsURL, atomically: true, encoding: .utf8)
        try "path".write(to: pathOnlyURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let configURL = tempConfigURL()
        defer { try? FileManager.default.removeItem(at: configURL) }

        let viewModel = makeViewModel(
            sessionStore: makeDefaults(),
            sessionKey: "quick-open-ranking-test",
            configService: ConfigurationService(userConfigURL: configURL),
            fileWatcher: FileWatcherService(),
            ui: TestProjectUI()
        )

        viewModel.rootDirectory = rootURL
        viewModel.fileTree = [
            FileItem(
                name: "Sources",
                path: sourcesURL,
                isDirectory: true,
                children: [
                    FileItem(name: "MatchUtilities.swift", path: prefixURL, isDirectory: false),
                    FileItem(name: "FeatureMatch.swift", path: containsURL, isDirectory: false)
                ]
            ),
            FileItem(
                name: "Match",
                path: pathOnlyFolderURL,
                isDirectory: true,
                children: [
                    FileItem(name: "Utilities.swift", path: pathOnlyURL, isDirectory: false)
                ]
            ),
            FileItem(name: "Selected.md", path: selectedURL, isDirectory: false)
        ]

        viewModel.openFile(at: selectedURL)

        #expect(viewModel.quickOpenItems.first?.file?.name == "Selected.md")

        viewModel.quickOpenQuery = "match"

        #expect(viewModel.quickOpenItems.map(\.displayPath) == [
            "Sources/MatchUtilities.swift",
            "Sources/FeatureMatch.swift",
            "Match/Utilities.swift"
        ])
    }

    @Test
    func quickOpenSupportsCurrentFileLineJumpAndFileScopedLineJump() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sourcesURL = rootURL.appendingPathComponent("Sources", isDirectory: true)
        let alphaURL = sourcesURL.appendingPathComponent("Alpha.swift")
        let betaURL = sourcesURL.appendingPathComponent("Beta.swift")

        try FileManager.default.createDirectory(at: sourcesURL, withIntermediateDirectories: true)
        try "print(\"alpha\")\nprint(\"beta\")\nprint(\"gamma\")\n".write(to: alphaURL, atomically: true, encoding: .utf8)
        try "print(\"one\")\nprint(\"two\")\n".write(to: betaURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let configURL = tempConfigURL()
        defer { try? FileManager.default.removeItem(at: configURL) }

        let viewModel = makeViewModel(
            sessionStore: makeDefaults(),
            sessionKey: "quick-open-line-jump-test",
            configService: ConfigurationService(userConfigURL: configURL),
            fileWatcher: FileWatcherService(),
            ui: TestProjectUI()
        )

        viewModel.rootDirectory = rootURL
        viewModel.fileTree = [
            FileItem(
                name: "Sources",
                path: sourcesURL,
                isDirectory: true,
                children: [
                    FileItem(name: "Alpha.swift", path: alphaURL, isDirectory: false),
                    FileItem(name: "Beta.swift", path: betaURL, isDirectory: false)
                ]
            )
        ]

        viewModel.openFile(at: alphaURL)
        viewModel.quickOpenQuery = ":3"

        let currentFileJump = try #require(viewModel.quickOpenItems.first)
        if case .lineJump(let fileURL, _, _, let line) = currentFileJump.kind {
            #expect(fileURL?.standardizedFileURL.path == alphaURL.standardizedFileURL.path)
            #expect(line == 3)
        } else {
            Issue.record("Expected a current-file line jump result.")
        }

        viewModel.executeQuickOpenItem(currentFileJump)
        #expect(viewModel.openTabs[0].pendingLineJump == 3)

        viewModel.quickOpenQuery = "beta:2"

        let betaJump = try #require(viewModel.quickOpenItems.first)
        if case .lineJump(let fileURL, _, _, let line) = betaJump.kind {
            #expect(fileURL?.standardizedFileURL.path == betaURL.standardizedFileURL.path)
            #expect(line == 2)
        } else {
            Issue.record("Expected a file-scoped line jump result.")
        }
    }

    @Test
    func quickOpenWorkspaceSymbolSearchFindsDeclarationsAndPrefersRecentFiles() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sourcesURL = rootURL.appendingPathComponent("Sources", isDirectory: true)
        let alphaURL = sourcesURL.appendingPathComponent("Alpha.swift")
        let betaURL = sourcesURL.appendingPathComponent("Beta.swift")

        try FileManager.default.createDirectory(at: sourcesURL, withIntermediateDirectories: true)
        try """
        struct AlphaSymbol {
            func alphaHelper() {
                let alphaValue = 1
            }
        }
        """.write(to: alphaURL, atomically: true, encoding: .utf8)
        try """
        struct AlphaTools {
            func alphaFactory() {}
        }
        """.write(to: betaURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let configURL = tempConfigURL()
        defer { try? FileManager.default.removeItem(at: configURL) }

        let viewModel = makeViewModel(
            sessionStore: makeDefaults(),
            sessionKey: "quick-open-symbol-test",
            configService: ConfigurationService(userConfigURL: configURL),
            fileWatcher: FileWatcherService(),
            ui: TestProjectUI()
        )

        viewModel.rootDirectory = rootURL
        viewModel.fileTree = [
            FileItem(
                name: "Sources",
                path: sourcesURL,
                isDirectory: true,
                children: [
                    FileItem(name: "Alpha.swift", path: alphaURL, isDirectory: false),
                    FileItem(name: "Beta.swift", path: betaURL, isDirectory: false)
                ]
            )
        ]

        viewModel.openFile(at: betaURL)
        viewModel.openFile(at: alphaURL)
        viewModel.quickOpenQuery = "#alpha"

        let items = viewModel.quickOpenItems
        #expect(items.count >= 2)

        let firstItem = try #require(items.first)
        if case .symbol(let symbol) = firstItem.kind {
            #expect(symbol.fileURL.standardizedFileURL.path == alphaURL.standardizedFileURL.path)
            #expect(symbol.name == "AlphaSymbol")
        } else {
            Issue.record("Expected a workspace symbol result.")
        }
    }

    @Test
    func quickOpenWorkspaceSymbolSearchRecognizesArrowFunctionsReceiverMethodsAndQualifiedExtensions() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sourcesURL = rootURL.appendingPathComponent("Sources", isDirectory: true)
        let swiftURL = sourcesURL.appendingPathComponent("Nested.swift")
        let tsURL = sourcesURL.appendingPathComponent("Actions.ts")
        let goURL = sourcesURL.appendingPathComponent("Server.go")

        try FileManager.default.createDirectory(at: sourcesURL, withIntermediateDirectories: true)
        try """
        struct Outer {
            struct Inner {}
        }

        extension Outer.Inner {
            func nestedAction() {}
        }
        """.write(to: swiftURL, atomically: true, encoding: .utf8)
        try """
        export const loadProject = async () => {
            return true
        }
        """.write(to: tsURL, atomically: true, encoding: .utf8)
        try """
        type Server struct{}

        func (s *Server) StartServer() error {
            return nil
        }
        """.write(to: goURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let configURL = tempConfigURL()
        defer { try? FileManager.default.removeItem(at: configURL) }

        let viewModel = makeViewModel(
            sessionStore: makeDefaults(),
            sessionKey: "quick-open-symbol-patterns-test",
            configService: ConfigurationService(userConfigURL: configURL),
            fileWatcher: FileWatcherService(),
            ui: TestProjectUI()
        )

        viewModel.rootDirectory = rootURL
        viewModel.fileTree = [
            FileItem(
                name: "Sources",
                path: sourcesURL,
                isDirectory: true,
                children: [
                    FileItem(name: "Nested.swift", path: swiftURL, isDirectory: false),
                    FileItem(name: "Actions.ts", path: tsURL, isDirectory: false),
                    FileItem(name: "Server.go", path: goURL, isDirectory: false)
                ]
            )
        ]

        viewModel.quickOpenQuery = "#loadproject"
        let loadProjectItem = try #require(viewModel.quickOpenItems.first)
        if case .symbol(let symbol) = loadProjectItem.kind {
            #expect(symbol.name == "loadProject")
            #expect(symbol.kindDisplayName == "Function")
            #expect(symbol.lineText.contains("loadProject"))
        } else {
            Issue.record("Expected a TypeScript arrow-function symbol result.")
        }

        viewModel.quickOpenQuery = "#startserver"
        let startServerItem = try #require(viewModel.quickOpenItems.first)
        if case .symbol(let symbol) = startServerItem.kind {
            #expect(symbol.name == "StartServer")
            #expect(symbol.fileURL.standardizedFileURL.path == goURL.standardizedFileURL.path)
        } else {
            Issue.record("Expected a Go receiver-method symbol result.")
        }

        viewModel.quickOpenQuery = "#outer.inner"
        let extensionItem = try #require(viewModel.quickOpenItems.first)
        if case .symbol(let symbol) = extensionItem.kind {
            #expect(symbol.name == "Outer.Inner")
            #expect(symbol.kindDisplayName == "Extension")
        } else {
            Issue.record("Expected a qualified Swift extension symbol result.")
        }
    }

    @Test
    func quickOpenWorkspaceSymbolSearchShowsCurrentFileSectionBeforeWorkspace() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sourcesURL = rootURL.appendingPathComponent("Sources", isDirectory: true)
        let alphaURL = sourcesURL.appendingPathComponent("Alpha.swift")
        let betaURL = sourcesURL.appendingPathComponent("Beta.swift")

        try FileManager.default.createDirectory(at: sourcesURL, withIntermediateDirectories: true)
        try """
        func alphaHelper() {}
        func alphaLocal() {}
        """.write(to: alphaURL, atomically: true, encoding: .utf8)
        try """
        func alphaWorkspaceHelper() {}
        """.write(to: betaURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let configURL = tempConfigURL()
        defer { try? FileManager.default.removeItem(at: configURL) }

        let viewModel = makeViewModel(
            sessionStore: makeDefaults(),
            sessionKey: "quick-open-symbol-sections-test",
            configService: ConfigurationService(userConfigURL: configURL),
            fileWatcher: FileWatcherService(),
            ui: TestProjectUI()
        )

        viewModel.rootDirectory = rootURL
        viewModel.fileTree = [
            FileItem(
                name: "Sources",
                path: sourcesURL,
                isDirectory: true,
                children: [
                    FileItem(name: "Alpha.swift", path: alphaURL, isDirectory: false),
                    FileItem(name: "Beta.swift", path: betaURL, isDirectory: false)
                ]
            )
        ]

        viewModel.openFile(at: alphaURL)
        viewModel.quickOpenQuery = "#alpha"

        #expect(viewModel.quickOpenSections.map(\.title) == ["Current File", "Workspace"])
        #expect(viewModel.quickOpenSections.first?.items.allSatisfy {
            guard case .symbol(let symbol) = $0.kind else { return false }
            return symbol.fileURL.standardizedFileURL.path == alphaURL.standardizedFileURL.path
        } == true)
        #expect(viewModel.quickOpenItems.first?.title == "alphaHelper")
    }

    @Test
    func quickOpenWorkspaceProblemSearchShowsCurrentFileAndWorkspaceSectionsAndOpensSelectedProblem() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let alphaURL = rootURL.appendingPathComponent("Alpha.swift")
        let betaURL = rootURL.appendingPathComponent("Beta.swift")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try """
        let alpha = 1
        let unused = alpha + 1
        """.write(to: alphaURL, atomically: true, encoding: .utf8)
        try """
        struct BetaFixture {
            let value = missingDependency
        }
        """.write(to: betaURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let configURL = tempConfigURL()
        defer { try? FileManager.default.removeItem(at: configURL) }

        let lspService = MockLSPService()
        let viewModel = makeViewModel(
            sessionStore: makeDefaults(),
            sessionKey: "quick-open-problem-sections-test",
            configService: ConfigurationService(userConfigURL: configURL),
            fileWatcher: FileWatcherService(),
            ui: TestProjectUI(),
            lspService: lspService
        )

        viewModel.rootDirectory = rootURL
        viewModel.openFile(at: alphaURL)
        lspService.setDiagnostics(
            uri: alphaURL.absoluteString,
            diagnostics: [
                LSPDiagnostic(
                    range: LSPRange(
                        start: LSPPosition(line: 1, character: 4),
                        end: LSPPosition(line: 1, character: 10)
                    ),
                    severity: .warning,
                    message: "Unused alpha binding"
                )
            ]
        )
        lspService.setDiagnostics(
            uri: betaURL.absoluteString,
            diagnostics: [
                LSPDiagnostic(
                    range: LSPRange(
                        start: LSPPosition(line: 1, character: 16),
                        end: LSPPosition(line: 1, character: 33)
                    ),
                    severity: .error,
                    message: "Missing dependency"
                )
            ]
        )

        viewModel.quickOpenQuery = "!"

        #expect(viewModel.quickOpenSections.map(\.title) == ["Current File", "Workspace"])

        let currentFileItem = try #require(viewModel.quickOpenSections.first?.items.first)
        if case .problem(let diagnostic) = currentFileItem.kind {
            #expect(diagnostic.fileURL.standardizedFileURL.path == alphaURL.standardizedFileURL.path)
            #expect(currentFileItem.badge == "Warning")
        } else {
            Issue.record("Expected a current-file problem result.")
        }

        let workspaceItem = try #require(viewModel.quickOpenSections.last?.items.first)
        if case .problem(let diagnostic) = workspaceItem.kind {
            #expect(diagnostic.fileURL.standardizedFileURL.path == betaURL.standardizedFileURL.path)
            #expect(workspaceItem.badge == "Error")
        } else {
            Issue.record("Expected a workspace problem result.")
        }

        viewModel.executeQuickOpenItem(workspaceItem)
        #expect(viewModel.selectedTab?.filePath?.standardizedFileURL.path == betaURL.standardizedFileURL.path)
        #expect(viewModel.selectedTab?.pendingLineJump == 2)
    }

    @Test
    func quickOpenWorkspaceProblemSearchSupportsSeverityFilters() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let alphaURL = rootURL.appendingPathComponent("Alpha.swift")
        let betaURL = rootURL.appendingPathComponent("Beta.swift")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try "let alpha = 1\nlet unused = alpha + 1\n".write(to: alphaURL, atomically: true, encoding: .utf8)
        try "struct BetaFixture {\n    let value = missingDependency\n}\n".write(to: betaURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let configURL = tempConfigURL()
        defer { try? FileManager.default.removeItem(at: configURL) }

        let lspService = MockLSPService()
        let viewModel = makeViewModel(
            sessionStore: makeDefaults(),
            sessionKey: "quick-open-problem-filter-test",
            configService: ConfigurationService(userConfigURL: configURL),
            fileWatcher: FileWatcherService(),
            ui: TestProjectUI(),
            lspService: lspService
        )

        viewModel.rootDirectory = rootURL
        viewModel.openFile(at: alphaURL)
        lspService.setDiagnostics(
            uri: alphaURL.absoluteString,
            diagnostics: [
                LSPDiagnostic(
                    range: LSPRange(
                        start: LSPPosition(line: 1, character: 4),
                        end: LSPPosition(line: 1, character: 10)
                    ),
                    severity: .warning,
                    message: "Unused alpha binding"
                )
            ]
        )
        lspService.setDiagnostics(
            uri: betaURL.absoluteString,
            diagnostics: [
                LSPDiagnostic(
                    range: LSPRange(
                        start: LSPPosition(line: 1, character: 16),
                        end: LSPPosition(line: 1, character: 33)
                    ),
                    severity: .error,
                    message: "Missing dependency"
                )
            ]
        )

        viewModel.quickOpenQuery = "!error"
        #expect(viewModel.quickOpenSections.map(\.title) == ["Problems"])
        #expect(viewModel.quickOpenItems.count == 1)
        #expect(viewModel.quickOpenItems.first?.badge == "Error")

        viewModel.quickOpenQuery = "!warning unused"
        #expect(viewModel.quickOpenSections.map(\.title) == ["Current File"])
        #expect(viewModel.quickOpenItems.count == 1)
        #expect(viewModel.quickOpenItems.first?.badge == "Warning")

        viewModel.quickOpenQuery = "!workspace error"
        #expect(viewModel.quickOpenSections.map(\.title) == ["Workspace"])
        #expect(viewModel.quickOpenItems.count == 1)
        #expect(viewModel.quickOpenItems.first?.badge == "Error")

        viewModel.quickOpenQuery = "!current"
        #expect(viewModel.quickOpenSections.map(\.title) == ["Current File"])
        #expect(viewModel.quickOpenItems.count == 1)
        #expect(viewModel.quickOpenItems.first?.badge == "Warning")

        viewModel.quickOpenQuery = "!hint"
        #expect(viewModel.quickOpenItems.isEmpty)
        #expect(viewModel.quickOpenEmptyStateText == "No matching hints.")

        viewModel.quickOpenQuery = "!current error"
        #expect(viewModel.quickOpenItems.isEmpty)
        #expect(viewModel.quickOpenEmptyStateText == "No matching current-file errors.")
    }

    @Test
    func quickOpenProblemFilterHintsToggleScopeAndSeverityWhilePreservingSearchText() throws {
        let configURL = tempConfigURL()
        defer { try? FileManager.default.removeItem(at: configURL) }

        let viewModel = makeViewModel(
            sessionStore: makeDefaults(),
            sessionKey: "quick-open-problem-filter-hints-test",
            configService: ConfigurationService(userConfigURL: configURL),
            fileWatcher: FileWatcherService(),
            ui: TestProjectUI()
        )

        viewModel.quickOpenQuery = "!missing dependency"
        let initialHints = viewModel.quickOpenProblemFilterHints
        #expect(initialHints.map(\.id) == ["current", "workspace", "error", "warning", "info", "hint"])
        #expect(viewModel.quickOpenHelpText == "Filter workspace problems by scope or severity while you type.")

        if let workspaceHint = initialHints.first(where: { $0.id == "workspace" }) {
            viewModel.applyQuickOpenProblemFilterHint(workspaceHint)
        } else {
            Issue.record("Expected workspace filter hint.")
        }
        #expect(viewModel.quickOpenQuery == "! workspace missing dependency")

        if let errorHint = viewModel.quickOpenProblemFilterHints.first(where: { $0.id == "error" }) {
            viewModel.applyQuickOpenProblemFilterHint(errorHint)
        } else {
            Issue.record("Expected error filter hint.")
        }
        #expect(viewModel.quickOpenQuery == "! workspace error missing dependency")

        if let workspaceHint = viewModel.quickOpenProblemFilterHints.first(where: { $0.id == "workspace" }) {
            viewModel.applyQuickOpenProblemFilterHint(workspaceHint)
        } else {
            Issue.record("Expected workspace filter hint.")
        }
        #expect(viewModel.quickOpenQuery == "! error missing dependency")
    }

    @Test
    func quickOpenHelpTextExplainsLineFileAndSymbolModes() throws {
        let configURL = tempConfigURL()
        defer { try? FileManager.default.removeItem(at: configURL) }

        let viewModel = makeViewModel(
            sessionStore: makeDefaults(),
            sessionKey: "quick-open-help-text-modes-test",
            configService: ConfigurationService(userConfigURL: configURL),
            fileWatcher: FileWatcherService(),
            ui: TestProjectUI()
        )

        #expect(viewModel.quickOpenHelpText == nil)

        viewModel.quickOpenQuery = ":42"
        #expect(viewModel.quickOpenHelpText == "Open a file first, then jump with :line, like :42.")

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("swift")
        try "func alpha() {}\n".write(to: fileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        viewModel.openFile(at: fileURL)
        viewModel.quickOpenQuery = ":42"
        #expect(viewModel.quickOpenHelpText == "Jump in the current file with :line, like :42.")

        viewModel.quickOpenQuery = "alpha.swift:18"
        #expect(viewModel.quickOpenHelpText == "Open the best matching file and jump straight to line 18.")

        viewModel.quickOpenQuery = "#"
        #expect(viewModel.quickOpenHelpText == "Search symbols with #name. Current-file matches are ranked first.")

        viewModel.quickOpenQuery = "#alpha"
        #expect(viewModel.quickOpenHelpText == "Current-file symbols stay ahead of workspace matches while you type.")
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
    func refreshGitStatePublishesBranchAndChangedFiles() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let configURL = tempConfigURL()
        defer { try? FileManager.default.removeItem(at: configURL) }

        let gitService = MockGitService()
        gitService.repositoryStatusResult = GitRepositoryStatus(
            repositoryRoot: rootURL,
            branchName: "main",
            changedFiles: [
                GitChangedFile(
                    path: "Tracked.swift",
                    previousPath: nil,
                    kind: .modified,
                    indexStatus: " ",
                    workingTreeStatus: "M"
                )
            ],
            ignoredPaths: []
        )

        let viewModel = makeViewModel(
            sessionStore: makeDefaults(),
            sessionKey: "git-state-test",
            configService: ConfigurationService(userConfigURL: configURL),
            fileWatcher: FileWatcherService(),
            ui: TestProjectUI(),
            gitService: gitService
        )

        viewModel.rootDirectory = rootURL
        viewModel.refreshGitState()

        try await waitUntil {
            viewModel.gitRepositoryStatus.branchName == "main" &&
                viewModel.gitRepositoryStatus.changedFiles.count == 1
        }

        #expect(viewModel.gitRepositoryStatus.branchName == "main")
        #expect(viewModel.gitRepositoryStatus.changedFiles.map(\.path) == ["Tracked.swift"])
        #expect(gitService.repositoryStatusCalls.map(\.standardizedFileURL.path).contains(rootURL.standardizedFileURL.path))
    }

    @Test
    func openGitChangedFileLoadsDiffAndShowsWorkspaceDiff() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = rootURL.appendingPathComponent("Tracked.swift")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try "let tracked = 1\n".write(to: fileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let configURL = tempConfigURL()
        defer { try? FileManager.default.removeItem(at: configURL) }

        let changedFile = GitChangedFile(
            path: "Tracked.swift",
            previousPath: nil,
            kind: .modified,
            indexStatus: " ",
            workingTreeStatus: "M"
        )

        let gitService = MockGitService()
        gitService.repositoryStatusResult = GitRepositoryStatus(
            repositoryRoot: rootURL,
            branchName: "main",
            changedFiles: [changedFile],
            ignoredPaths: []
        )
        gitService.diffResults[changedFile.path] = GitDiffResult(
            path: changedFile.path,
            text: "@@ -1 +1 @@\n-let tracked = 0\n+let tracked = 1"
        )

        let viewModel = makeViewModel(
            sessionStore: makeDefaults(),
            sessionKey: "git-diff-test",
            configService: ConfigurationService(userConfigURL: configURL),
            fileWatcher: FileWatcherService(),
            ui: TestProjectUI(),
            gitService: gitService
        )

        viewModel.rootDirectory = rootURL
        viewModel.refreshGitState()
        try await waitUntil {
            viewModel.gitRepositoryStatus.changedFiles.count == 1
        }

        viewModel.openGitChangedFile(changedFile)

        try await waitUntil {
            viewModel.selectedGitDiff?.path == changedFile.path &&
                viewModel.isGitDiffWorkspaceVisible
        }

        #expect(viewModel.selectedTab?.filePath?.standardizedFileURL.path == fileURL.standardizedFileURL.path)
        #expect(viewModel.selectedGitDiff?.text.contains("+let tracked = 1") == true)
        #expect(viewModel.selectedGitDiff?.hasStructuredChanges == true)
        #expect(viewModel.selectedGitDiff?.hunks.first?.rows.first?.rightText == "let tracked = 1")
    }

    @Test
    func gitWorkspaceNavigationMovesBetweenChangedFiles() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let firstURL = rootURL.appendingPathComponent("First.swift")
        let secondURL = rootURL.appendingPathComponent("Second.swift")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try "let first = 1\n".write(to: firstURL, atomically: true, encoding: .utf8)
        try "let second = 1\n".write(to: secondURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let configURL = tempConfigURL()
        defer { try? FileManager.default.removeItem(at: configURL) }

        let firstChange = GitChangedFile(
            path: "First.swift",
            previousPath: nil,
            kind: .modified,
            indexStatus: " ",
            workingTreeStatus: "M"
        )
        let secondChange = GitChangedFile(
            path: "Second.swift",
            previousPath: nil,
            kind: .modified,
            indexStatus: " ",
            workingTreeStatus: "M"
        )

        let gitService = MockGitService()
        gitService.repositoryStatusResult = GitRepositoryStatus(
            repositoryRoot: rootURL,
            branchName: "main",
            changedFiles: [firstChange, secondChange],
            ignoredPaths: []
        )
        gitService.diffResults[firstChange.path] = GitDiffResult(path: firstChange.path, text: "@@ -1 +1 @@\n-let first = 0\n+let first = 1")
        gitService.diffResults[secondChange.path] = GitDiffResult(path: secondChange.path, text: "@@ -1 +1 @@\n-let second = 0\n+let second = 1")

        let viewModel = makeViewModel(
            sessionStore: makeDefaults(),
            sessionKey: "git-workspace-nav-test",
            configService: ConfigurationService(userConfigURL: configURL),
            fileWatcher: FileWatcherService(),
            ui: TestProjectUI(),
            gitService: gitService
        )

        viewModel.rootDirectory = rootURL
        viewModel.refreshGitState()
        try await waitUntil {
            viewModel.gitRepositoryStatus.changedFiles.count == 2
        }

        viewModel.openGitChangedFile(firstChange)
        try await waitUntil {
            viewModel.selectedGitDiffPath == firstChange.path
        }

        #expect(viewModel.selectedGitChangePositionText == "Change 1 of 2")
        #expect(viewModel.canShowPreviousGitChange == false)
        #expect(viewModel.canShowNextGitChange)

        viewModel.showNextGitChange()
        try await waitUntil {
            viewModel.selectedGitDiffPath == secondChange.path
        }

        #expect(viewModel.selectedGitChangePositionText == "Change 2 of 2")
        #expect(viewModel.canShowPreviousGitChange)
        #expect(viewModel.canShowNextGitChange == false)

        viewModel.showPreviousGitChange()
        try await waitUntil {
            viewModel.selectedGitDiffPath == firstChange.path
        }
    }

    @Test
    func gitRepositoryStatusGroupsChangesForSourceControlSections() {
        let status = GitRepositoryStatus(
            repositoryRoot: URL(fileURLWithPath: "/tmp/repo"),
            branchName: "main",
            changedFiles: [
                GitChangedFile(path: "Conflict.swift", previousPath: nil, kind: .conflicted, indexStatus: "U", workingTreeStatus: "U"),
                GitChangedFile(path: "Staged.swift", previousPath: nil, kind: .modified, indexStatus: "M", workingTreeStatus: " "),
                GitChangedFile(path: "Mixed.swift", previousPath: nil, kind: .modified, indexStatus: "M", workingTreeStatus: "M"),
                GitChangedFile(path: "Notes.md", previousPath: nil, kind: .untracked, indexStatus: "?", workingTreeStatus: "?")
            ],
            ignoredPaths: []
        )

        #expect(status.conflictedCount == 1)
        #expect(status.stagedCount == 2)
        #expect(status.unstagedCount == 1)
        #expect(status.untrackedCount == 1)
        #expect(status.changeSections.map(\.section) == [.conflicted, .staged, .changes, .untracked])
        #expect(status.changeSections.first?.files.map(\.path) == ["Conflict.swift"])
        #expect(status.changeSections[1].files.map(\.path) == ["Staged.swift"])
        #expect(status.changeSections[2].files.map(\.path) == ["Mixed.swift"])
        #expect(status.changeSections[3].files.map(\.path) == ["Notes.md"])
    }

    @Test
    func gitWorkspaceViewActionsUpdateEditorAndSidebarState() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = rootURL.appendingPathComponent("Tracked.swift")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try "let tracked = 1\n".write(to: fileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let configURL = tempConfigURL()
        defer { try? FileManager.default.removeItem(at: configURL) }

        let changedFile = GitChangedFile(
            path: "Tracked.swift",
            previousPath: nil,
            kind: .modified,
            indexStatus: " ",
            workingTreeStatus: "M"
        )

        let gitService = MockGitService()
        gitService.repositoryStatusResult = GitRepositoryStatus(
            repositoryRoot: rootURL,
            branchName: "main",
            changedFiles: [changedFile],
            ignoredPaths: []
        )
        gitService.diffResults[changedFile.path] = GitDiffResult(path: changedFile.path, text: "@@ -1 +1 @@\n-let tracked = 0\n+let tracked = 1")

        let viewModel = makeViewModel(
            sessionStore: makeDefaults(),
            sessionKey: "git-workspace-view-actions-test",
            configService: ConfigurationService(userConfigURL: configURL),
            fileWatcher: FileWatcherService(),
            ui: TestProjectUI(),
            gitService: gitService
        )

        viewModel.rootDirectory = rootURL
        viewModel.refreshGitState()
        try await waitUntil {
            viewModel.gitRepositoryStatus.changedFiles.count == 1
        }

        viewModel.openGitChangedFile(changedFile)
        try await waitUntil {
            viewModel.selectedGitDiffPath == changedFile.path &&
                viewModel.isGitDiffWorkspaceVisible
        }

        #expect(viewModel.selectedGitChangeReviewLabel == "Reviewing Modified 1/1")

        viewModel.revealSelectedGitChangeInExplorer()
        #expect(viewModel.sidebarMode == .explorer)
        #expect(viewModel.isGitDiffWorkspaceVisible)

        viewModel.openSelectedGitChangeInEditor()
        #expect(viewModel.isGitDiffWorkspaceVisible == false)
        #expect(viewModel.selectedTab?.filePath?.standardizedFileURL.path == fileURL.standardizedFileURL.path)
    }

    @Test
    func gitWorkspaceActionsDispatchToGitService() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = rootURL.appendingPathComponent("Tracked.swift")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try "let tracked = 1\n".write(to: fileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let configURL = tempConfigURL()
        defer { try? FileManager.default.removeItem(at: configURL) }

        let changedFile = GitChangedFile(
            path: "Tracked.swift",
            previousPath: nil,
            kind: .modified,
            indexStatus: "M",
            workingTreeStatus: "M"
        )

        let gitService = MockGitService()
        gitService.repositoryStatusResult = GitRepositoryStatus(
            repositoryRoot: rootURL,
            branchName: "main",
            changedFiles: [changedFile],
            ignoredPaths: []
        )
        gitService.diffResults[changedFile.path] = GitDiffResult(path: changedFile.path, text: "@@ -1 +1 @@\n-let tracked = 0\n+let tracked = 1")

        let ui = TestProjectUI(confirmResponses: [.alertFirstButtonReturn])
        let viewModel = makeViewModel(
            sessionStore: makeDefaults(),
            sessionKey: "git-workspace-action-test",
            configService: ConfigurationService(userConfigURL: configURL),
            fileWatcher: FileWatcherService(),
            ui: ui,
            gitService: gitService
        )

        viewModel.rootDirectory = rootURL
        viewModel.refreshGitState()
        try await waitUntil {
            viewModel.gitRepositoryStatus.changedFiles.count == 1
        }

        viewModel.openGitChangedFile(changedFile)
        try await waitUntil {
            viewModel.selectedGitDiffPath == changedFile.path
        }

        viewModel.stageSelectedGitChange()
        viewModel.unstageSelectedGitChange()
        viewModel.discardSelectedGitChange()

        try await waitUntil {
            gitService.stageCalls.count == 1 &&
                gitService.unstageCalls.count == 1 &&
                gitService.discardCalls.count == 1
        }

        #expect(gitService.stageCalls == ["Tracked.swift"])
        #expect(gitService.unstageCalls == ["Tracked.swift"])
        #expect(gitService.discardCalls == ["Tracked.swift"])
        #expect(ui.confirms.last?.title == "Discard Working Tree Changes?")
    }

    @Test
    func updateCursorPositionRefreshesGitBlame() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = rootURL.appendingPathComponent("Tracked.swift")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try "line one\nline two\n".write(to: fileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let configURL = tempConfigURL()
        defer { try? FileManager.default.removeItem(at: configURL) }

        let gitService = MockGitService()
        gitService.blameResults["\(fileURL.standardizedFileURL.path):2"] = GitBlameInfo(
            commitHash: "1234567890abcdef",
            shortCommitHash: "12345678",
            author: "Rosewood Tests",
            summary: "Refine greeting",
            authoredDate: nil
        )

        let viewModel = makeViewModel(
            sessionStore: makeDefaults(),
            sessionKey: "git-blame-test",
            configService: ConfigurationService(userConfigURL: configURL),
            fileWatcher: FileWatcherService(),
            ui: TestProjectUI(),
            gitService: gitService
        )

        viewModel.rootDirectory = rootURL
        viewModel.openFile(at: fileURL)
        viewModel.updateCursorPosition(line: 2, column: 1)

        try await waitUntil {
            viewModel.currentLineBlame?.summary == "Refine greeting"
        }

        #expect(viewModel.currentLineBlame?.author == "Rosewood Tests")
        #expect(gitService.blameCalls.contains { $0.fileURL.standardizedFileURL.path == fileURL.standardizedFileURL.path && $0.line == 2 })
    }

    @Test
    func explorerGitHelpersReportChangedAndIgnoredItems() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let trackedURL = rootURL.appendingPathComponent("Tracked.swift")
        let ignoredURL = rootURL.appendingPathComponent("Ignored.log")
        let srcURL = rootURL.appendingPathComponent("Sources", isDirectory: true)
        let nestedURL = srcURL.appendingPathComponent("Nested.swift")

        try FileManager.default.createDirectory(at: srcURL, withIntermediateDirectories: true)
        try "let tracked = 1\n".write(to: trackedURL, atomically: true, encoding: .utf8)
        try "ignore me\n".write(to: ignoredURL, atomically: true, encoding: .utf8)
        try "let nested = true\n".write(to: nestedURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let configURL = tempConfigURL()
        defer { try? FileManager.default.removeItem(at: configURL) }

        let gitService = MockGitService()
        gitService.repositoryStatusResult = GitRepositoryStatus(
            repositoryRoot: rootURL,
            branchName: "main",
            changedFiles: [
                GitChangedFile(
                    path: "Tracked.swift",
                    previousPath: nil,
                    kind: .modified,
                    indexStatus: " ",
                    workingTreeStatus: "M"
                ),
                GitChangedFile(
                    path: "Sources/Nested.swift",
                    previousPath: nil,
                    kind: .added,
                    indexStatus: "A",
                    workingTreeStatus: " "
                )
            ],
            ignoredPaths: ["Ignored.log"]
        )

        let viewModel = makeViewModel(
            sessionStore: makeDefaults(),
            sessionKey: "git-explorer-helper-test",
            configService: ConfigurationService(userConfigURL: configURL),
            fileWatcher: FileWatcherService(),
            ui: TestProjectUI(),
            gitService: gitService
        )

        viewModel.rootDirectory = rootURL
        viewModel.refreshGitState()

        try await waitUntil {
            viewModel.gitRepositoryStatus.branchName == "main"
        }

        let trackedItem = FileItem(name: "Tracked.swift", path: trackedURL, isDirectory: false)
        let ignoredItem = FileItem(name: "Ignored.log", path: ignoredURL, isDirectory: false)
        let sourcesItem = FileItem(name: "Sources", path: srcURL, isDirectory: true)

        #expect(viewModel.gitChange(for: trackedItem)?.kind == .modified)
        #expect(viewModel.isGitIgnored(ignoredItem))
        #expect(viewModel.gitChangedDescendantCount(for: sourcesItem) == 1)
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

        #expect(viewModel.projectReplacePreview?.matchCount == 3)
        #expect(ui.alerts.isEmpty)

        viewModel.applyProjectReplacePreview()

        try await waitUntil {
            !viewModel.isReplacingInProject &&
                !viewModel.isSearchingProject &&
                viewModel.projectSearchResults.isEmpty &&
                viewModel.openTabs.first?.content.contains("cedar") == true
        }

        #expect(try String(contentsOf: fileURL, encoding: .utf8).contains("cedar"))
        #expect(viewModel.openTabs.first?.isDirty == false)
        #expect(viewModel.lastProjectReplaceTransaction?.replacementCount == 3)
        #expect(ui.alerts.contains { $0.title == "Replace Complete" })
    }

    @Test
    func replaceAllProjectResultsBuildsPreviewFromCurrentMatchCount() async throws {
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

        let ui = TestProjectUI(confirmResponses: [.alertSecondButtonReturn])
        let viewModel = makeViewModel(
            sessionStore: makeDefaults(),
            sessionKey: "replace-confirmation-test",
            configService: ConfigurationService(userConfigURL: configURL),
            fileWatcher: FileWatcherService(),
            ui: ui
        )

        viewModel.rootDirectory = rootURL
        viewModel.projectSearchQuery = "rosewood"
        viewModel.projectReplaceQuery = "cedar"
        viewModel.performProjectSearch()

        try await waitUntil {
            viewModel.projectSearchResults.count == 2 && !viewModel.isSearchingProject
        }

        viewModel.replaceAllProjectResults()

        let preview = try #require(viewModel.projectReplacePreview)
        #expect(preview.summary == "Replace 3 selected matches across 1 file.")
        #expect(preview.files.map(\.fileName) == ["Example.swift"])
        #expect(preview.matchCount == 3)
        #expect(ui.confirms.isEmpty)
        #expect(try String(contentsOf: fileURL, encoding: .utf8).contains("rosewood"))
    }

    @Test
    func replaceAllProjectResultsOnlyUpdatesSelectedResults() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = rootURL.appendingPathComponent("Example.swift")

        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try """
        let rosewood = "rosewood"
        let keep = "rosewood"
        """.write(to: fileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let configURL = tempConfigURL()
        defer { try? FileManager.default.removeItem(at: configURL) }

        let ui = TestProjectUI(confirmResponses: [.alertFirstButtonReturn])
        let viewModel = makeViewModel(
            sessionStore: makeDefaults(),
            sessionKey: "replace-selected-results-test",
            configService: ConfigurationService(userConfigURL: configURL),
            fileWatcher: FileWatcherService(),
            ui: ui
        )

        viewModel.rootDirectory = rootURL
        viewModel.projectSearchQuery = "rosewood"
        viewModel.projectReplaceQuery = "cedar"
        viewModel.performProjectSearch()

        try await waitUntil {
            viewModel.projectSearchResults.count == 2 && !viewModel.isSearchingProject
        }

        let firstResult = try #require(viewModel.projectSearchResults.first { $0.lineNumber == 1 })
        viewModel.toggleProjectSearchResultSelection(firstResult)

        #expect(viewModel.selectedProjectSearchResults.count == 1)
        #expect(viewModel.selectedProjectSearchMatchCount == 1)
        #expect(viewModel.replaceAllProjectResultsTitle == "Replace Selected (1)")

        viewModel.replaceAllProjectResults()
        #expect(viewModel.projectReplacePreview?.matchCount == 1)

        viewModel.applyProjectReplacePreview()

        try await waitUntil {
            !viewModel.isReplacingInProject && !viewModel.isSearchingProject
        }

        #expect(try String(contentsOf: fileURL, encoding: .utf8) == """
        let rosewood = "rosewood"
        let keep = "cedar"
        """)
    }

    @Test
    func replaceProjectSearchFileGroupOnlyUpdatesTargetFile() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let alphaURL = rootURL.appendingPathComponent("Alpha.swift")
        let betaURL = rootURL.appendingPathComponent("Beta.swift")

        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try """
        let rosewood = "rosewood"
        """.write(to: alphaURL, atomically: true, encoding: .utf8)
        try """
        let rosewood = "rosewood"
        """.write(to: betaURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let configURL = tempConfigURL()
        defer { try? FileManager.default.removeItem(at: configURL) }

        let ui = TestProjectUI(confirmResponses: [.alertFirstButtonReturn])
        let viewModel = makeViewModel(
            sessionStore: makeDefaults(),
            sessionKey: "replace-file-group-test",
            configService: ConfigurationService(userConfigURL: configURL),
            fileWatcher: FileWatcherService(),
            ui: ui
        )

        viewModel.rootDirectory = rootURL
        viewModel.projectSearchQuery = "rosewood"
        viewModel.projectReplaceQuery = "cedar"
        viewModel.performProjectSearch()

        try await waitUntil {
            viewModel.groupedProjectSearchResults.count == 2 && !viewModel.isSearchingProject
        }

        let alphaGroup = try #require(
            viewModel.groupedProjectSearchResults.first { $0.filePath.standardizedFileURL == alphaURL.standardizedFileURL }
        )

        viewModel.replaceProjectSearchFileGroup(alphaGroup)
        #expect(viewModel.projectReplacePreview?.files.map(\.fileName) == ["Alpha.swift"])

        viewModel.applyProjectReplacePreview()

        try await waitUntil {
            !viewModel.isReplacingInProject &&
                !viewModel.isSearchingProject &&
                viewModel.groupedProjectSearchResults.count == 1
        }

        #expect(try String(contentsOf: alphaURL, encoding: .utf8).contains("cedar"))
        #expect(try String(contentsOf: betaURL, encoding: .utf8).contains("rosewood"))
        #expect(viewModel.groupedProjectSearchResults.map(\.fileName) == ["Beta.swift"])
        #expect(ui.confirms.isEmpty)
    }

    @Test
    func replaceProjectSearchFileGroupOnlyPromptsForAffectedDirtyTabs() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let alphaURL = rootURL.appendingPathComponent("Alpha.swift")
        let betaURL = rootURL.appendingPathComponent("Beta.swift")

        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try "let rosewood = 1\n".write(to: alphaURL, atomically: true, encoding: .utf8)
        try "let beta = 1\n".write(to: betaURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let configURL = tempConfigURL()
        defer { try? FileManager.default.removeItem(at: configURL) }

        let ui = TestProjectUI(confirmResponses: [.alertFirstButtonReturn])
        let viewModel = makeViewModel(
            sessionStore: makeDefaults(),
            sessionKey: "replace-file-dirty-scope-test",
            configService: ConfigurationService(userConfigURL: configURL),
            fileWatcher: FileWatcherService(),
            ui: ui
        )

        viewModel.rootDirectory = rootURL
        viewModel.openFile(at: betaURL)
        viewModel.updateTabContent("let beta = 2\n")
        viewModel.projectSearchQuery = "rosewood"
        viewModel.projectReplaceQuery = "cedar"
        viewModel.performProjectSearch()

        try await waitUntil {
            viewModel.groupedProjectSearchResults.count == 1 && !viewModel.isSearchingProject
        }

        let alphaGroup = try #require(viewModel.groupedProjectSearchResults.first)
        viewModel.replaceProjectSearchFileGroup(alphaGroup)
        #expect(viewModel.projectReplacePreview?.files.map(\.fileName) == ["Alpha.swift"])

        viewModel.applyProjectReplacePreview()

        try await waitUntil {
            !viewModel.isReplacingInProject && !viewModel.isSearchingProject
        }

        #expect(ui.confirms.isEmpty)
        #expect(viewModel.openTabs.first?.isDirty == true)
        #expect(try String(contentsOf: betaURL, encoding: .utf8) == "let beta = 1\n")
    }

    @Test
    func undoLastProjectReplaceRestoresPreviousContent() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = rootURL.appendingPathComponent("Example.swift")

        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try """
        let rosewood = "rosewood"
        let keep = "rosewood"
        """.write(to: fileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let configURL = tempConfigURL()
        defer { try? FileManager.default.removeItem(at: configURL) }

        let ui = TestProjectUI()
        let viewModel = makeViewModel(
            sessionStore: makeDefaults(),
            sessionKey: "undo-project-replace-test",
            configService: ConfigurationService(userConfigURL: configURL),
            fileWatcher: FileWatcherService(),
            ui: ui
        )

        viewModel.rootDirectory = rootURL
        viewModel.projectSearchQuery = "rosewood"
        viewModel.projectReplaceQuery = "cedar"
        viewModel.performProjectSearch()

        try await waitUntil {
            viewModel.projectSearchResults.count == 2 && !viewModel.isSearchingProject
        }

        viewModel.replaceAllProjectResults()
        viewModel.applyProjectReplacePreview()

        try await waitUntil {
            !viewModel.isReplacingInProject &&
                viewModel.lastProjectReplaceTransaction != nil &&
                (try? String(contentsOf: fileURL, encoding: .utf8)) == """
                let cedar = "cedar"
                let keep = "cedar"
                """
        }

        viewModel.undoLastProjectReplace()

        try await waitUntil {
            !viewModel.isReplacingInProject &&
                viewModel.lastProjectReplaceTransaction == nil &&
                (try? String(contentsOf: fileURL, encoding: .utf8)) == """
                let rosewood = "rosewood"
                let keep = "rosewood"
                """
        }

        #expect(ui.alerts.contains { $0.title == "Replace Undone" })
    }

    @Test
    func changingProjectSearchQueryClearsStaleResultsAndBlocksReplaceUntilResearched() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = rootURL.appendingPathComponent("Example.swift")

        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try """
        let rosewood = "rosewood"
        let cedar = "cedar"
        """.write(to: fileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let configURL = tempConfigURL()
        defer { try? FileManager.default.removeItem(at: configURL) }

        let ui = TestProjectUI(confirmResponses: [.alertFirstButtonReturn])
        let viewModel = makeViewModel(
            sessionStore: makeDefaults(),
            sessionKey: "search-query-reset-test",
            configService: ConfigurationService(userConfigURL: configURL),
            fileWatcher: FileWatcherService(),
            ui: ui
        )

        viewModel.rootDirectory = rootURL
        viewModel.projectSearchQuery = "rosewood"
        viewModel.performProjectSearch()

        try await waitUntil {
            viewModel.projectSearchResults.count == 1 && !viewModel.isSearchingProject
        }

        #expect(viewModel.canReplaceProjectSearchResults == true)

        viewModel.projectSearchQuery = "cedar"

        #expect(viewModel.projectSearchResults.isEmpty)
        #expect(viewModel.canReplaceProjectSearchResults == false)

        viewModel.projectReplaceQuery = "pine"
        viewModel.replaceAllProjectResults()

        #expect(try String(contentsOf: fileURL, encoding: .utf8).contains("cedar"))
        #expect(!ui.alerts.contains { $0.title == "Replace Complete" })
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
    func openExternalDirectoryClearsStateAndLoadsNewRoot() async throws {
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
        let ui = TestProjectUI(confirmResponses: [.alertSecondButtonReturn, .alertSecondButtonReturn])
        let viewModel = makeViewModel(
            sessionStore: makeDefaults(),
            sessionKey: "open-external-directory-test",
            configService: ConfigurationService(userConfigURL: configURL),
            fileWatcher: fileWatcher,
            ui: ui
        )

        viewModel.openExternalItems([firstRoot])
        try await waitUntil {
            viewModel.rootDirectory?.standardizedFileURL.path == firstRoot.standardizedFileURL.path &&
                viewModel.fileTree.map(\.name) == ["One.swift"] &&
                !viewModel.isLoadingFileTree
        }

        viewModel.openFile(at: firstFile)
        viewModel.showReferences([
            LSPLocation(
                uri: firstFile.absoluteString,
                range: LSPRange(
                    start: LSPPosition(line: 0, character: 6),
                    end: LSPPosition(line: 0, character: 9)
                )
            )
        ])

        viewModel.openExternalItems([secondRoot])
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
    func openExternalFileOpensParentFolderAndSelectsFile() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = rootURL.appendingPathComponent("Alpha.swift")

        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try "let alpha = 1\n".write(to: fileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let configURL = tempConfigURL()
        defer { try? FileManager.default.removeItem(at: configURL) }

        let fileWatcher = FileWatcherService()
        let viewModel = makeViewModel(
            sessionStore: makeDefaults(),
            sessionKey: "open-external-file-test",
            configService: ConfigurationService(userConfigURL: configURL),
            fileWatcher: fileWatcher,
            ui: TestProjectUI()
        )

        viewModel.openExternalItems([fileURL])

        try await waitUntil {
            viewModel.rootDirectory?.standardizedFileURL.path == rootURL.standardizedFileURL.path &&
                viewModel.selectedTab?.filePath?.standardizedFileURL.path == fileURL.standardizedFileURL.path &&
                !viewModel.isLoadingFileTree
        }

        #expect(viewModel.openTabs.count == 1)
        #expect(fileWatcher.watchedURLs == Set([fileURL]))
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
        #expect(viewModel.selectedTab?.cursorPosition.column == 10)
        #expect(viewModel.selectedTab?.pendingLineJump == 2)

        viewModel.clearPendingLineJump()
        #expect(viewModel.selectedTab?.pendingLineJump == nil)

        viewModel.showExplorerSidebar()
        #expect(viewModel.sidebarMode == .explorer)
    }

    @Test
    func projectSearchKeyboardNavigationMovesActiveResultAndOpensIt() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let alphaURL = rootURL.appendingPathComponent("Alpha.swift")
        let betaURL = rootURL.appendingPathComponent("Beta.swift")

        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try "let alpha = 1\n".write(to: alphaURL, atomically: true, encoding: .utf8)
        try "let beta = alpha\n".write(to: betaURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let configURL = tempConfigURL()
        defer { try? FileManager.default.removeItem(at: configURL) }

        let viewModel = makeViewModel(
            sessionStore: makeDefaults(),
            sessionKey: "search-keyboard-navigation-test",
            configService: ConfigurationService(userConfigURL: configURL),
            fileWatcher: FileWatcherService(),
            ui: TestProjectUI()
        )

        viewModel.rootDirectory = rootURL
        viewModel.projectSearchQuery = "alpha"
        viewModel.showSearchSidebar()

        try await waitUntil {
            viewModel.sidebarMode == .search &&
                viewModel.orderedProjectSearchResults.count == 2 &&
                !viewModel.isSearchingProject
        }

        #expect(viewModel.activeProjectSearchResult?.filePath.standardizedFileURL == alphaURL.standardizedFileURL)

        viewModel.moveActiveProjectSearchResult(1)
        #expect(viewModel.activeProjectSearchResult?.filePath.standardizedFileURL == betaURL.standardizedFileURL)

        viewModel.moveActiveProjectSearchResult(1)
        #expect(viewModel.activeProjectSearchResult?.filePath.standardizedFileURL == alphaURL.standardizedFileURL)

        viewModel.moveActiveProjectSearchResult(-1)
        #expect(viewModel.activeProjectSearchResult?.filePath.standardizedFileURL == betaURL.standardizedFileURL)

        viewModel.openActiveProjectSearchResult()
        #expect(viewModel.selectedTab?.filePath?.standardizedFileURL == betaURL.standardizedFileURL)
        #expect(viewModel.selectedTab?.pendingLineJump == 1)
    }

    @Test
    func collapsingProjectSearchGroupLimitsVisibleNavigationAndCommands() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let alphaURL = rootURL.appendingPathComponent("Alpha.swift")
        let betaURL = rootURL.appendingPathComponent("Beta.swift")

        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try "let alpha = 1\n".write(to: alphaURL, atomically: true, encoding: .utf8)
        try "let beta = alpha\n".write(to: betaURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let configURL = tempConfigURL()
        defer { try? FileManager.default.removeItem(at: configURL) }

        let viewModel = makeViewModel(
            sessionStore: makeDefaults(),
            sessionKey: "search-collapse-test",
            configService: ConfigurationService(userConfigURL: configURL),
            fileWatcher: FileWatcherService(),
            ui: TestProjectUI()
        )

        viewModel.rootDirectory = rootURL
        viewModel.projectSearchQuery = "alpha"
        viewModel.showSearchSidebar()

        try await waitUntil {
            viewModel.groupedProjectSearchResults.count == 2 &&
                viewModel.orderedProjectSearchResults.count == 2 &&
                !viewModel.isSearchingProject
        }

        #expect(viewModel.commandPaletteActions.map(\.title).contains("Collapse Search Results"))
        #expect(viewModel.commandPaletteActions.map(\.title).contains("Next Search Result"))

        let alphaGroup = try #require(viewModel.groupedProjectSearchResults.first)

        viewModel.setActiveProjectSearchResult(try #require(alphaGroup.results.first))
        viewModel.toggleProjectSearchGroupCollapsed(alphaGroup)

        #expect(viewModel.isProjectSearchGroupCollapsed(alphaGroup))
        #expect(viewModel.visibleGroupedProjectSearchResults.map(\.fileName) == ["Beta.swift"])
        #expect(viewModel.orderedProjectSearchResults.map(\.filePath.standardizedFileURL) == [betaURL.standardizedFileURL])
        #expect(viewModel.activeProjectSearchResult?.filePath.standardizedFileURL == betaURL.standardizedFileURL)
        #expect(viewModel.commandPaletteActions.map(\.title).contains("Expand Search Results"))

        viewModel.expandAllProjectSearchGroups()

        #expect(viewModel.isProjectSearchGroupCollapsed(alphaGroup) == false)
        #expect(viewModel.visibleGroupedProjectSearchResults.map(\.fileName) == ["Alpha.swift", "Beta.swift"])
        #expect(viewModel.orderedProjectSearchResults.count == 2)
        #expect(viewModel.commandPaletteActions.map(\.title).contains("Collapse Search Results"))
        #expect(viewModel.commandPaletteActions.map(\.title).contains("Previous Search Result"))
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
    func quickOpenItemsAndToggleExpandReflectFileTreeState() throws {
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

        viewModel.quickOpenQuery = "match"
        #expect(viewModel.quickOpenItems.compactMap { $0.file?.name } == ["Match.swift"])

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
    func openNextAndPreviousProblemWrapWithinCurrentTab() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("swift")
        try """
        let alpha = 1
        let beta = alpha + 1
        let gamma = beta + 1
        """.write(to: fileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let configURL = tempConfigURL()
        defer { try? FileManager.default.removeItem(at: configURL) }

        let lspService = MockLSPService()
        let viewModel = makeViewModel(
            sessionStore: makeDefaults(),
            sessionKey: "open-next-problem-test",
            configService: ConfigurationService(userConfigURL: configURL),
            fileWatcher: FileWatcherService(),
            ui: TestProjectUI(),
            lspService: lspService
        )

        viewModel.openFile(at: fileURL)
        let uri = try #require(viewModel.selectedTab?.documentURI)
        lspService.injectDiagnosticsForTesting(
            uri: uri,
            diagnostics: [
                LSPDiagnostic(
                    range: LSPRange(
                        start: LSPPosition(line: 0, character: 4),
                        end: LSPPosition(line: 0, character: 9)
                    ),
                    severity: .error,
                    message: "First problem"
                ),
                LSPDiagnostic(
                    range: LSPRange(
                        start: LSPPosition(line: 2, character: 4),
                        end: LSPPosition(line: 2, character: 9)
                    ),
                    severity: .warning,
                    message: "Second problem"
                )
            ]
        )

        viewModel.updateCursorPosition(line: 1, column: 6)
        viewModel.openNextProblem()
        #expect(viewModel.selectedTab?.pendingLineJump == 3)

        viewModel.updateCursorPosition(line: 3, column: 20)
        if let selectedTabIndex = viewModel.selectedTabIndex {
            viewModel.openTabs[selectedTabIndex].pendingLineJump = nil
        }
        viewModel.openNextProblem()
        #expect(viewModel.selectedTab?.pendingLineJump == 1)

        viewModel.updateCursorPosition(line: 1, column: 1)
        if let selectedTabIndex = viewModel.selectedTabIndex {
            viewModel.openTabs[selectedTabIndex].pendingLineJump = nil
        }
        viewModel.openPreviousProblem()
        #expect(viewModel.selectedTab?.pendingLineJump == 3)
    }

    @Test
    func problemNavigationAdvancesFromActiveDiagnosticBeforeCursorSync() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("swift")
        try """
        let alpha = 1
        let beta = alpha + 1
        let gamma = beta + 1
        """.write(to: fileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let configURL = tempConfigURL()
        defer { try? FileManager.default.removeItem(at: configURL) }

        let lspService = MockLSPService()
        let viewModel = makeViewModel(
            sessionStore: makeDefaults(),
            sessionKey: "problem-navigation-active-diagnostic-test",
            configService: ConfigurationService(userConfigURL: configURL),
            fileWatcher: FileWatcherService(),
            ui: TestProjectUI(),
            lspService: lspService
        )

        viewModel.openFile(at: fileURL)
        let uri = try #require(viewModel.selectedTab?.documentURI)
        let firstDiagnostic = LSPDiagnostic(
            range: LSPRange(
                start: LSPPosition(line: 0, character: 4),
                end: LSPPosition(line: 0, character: 9)
            ),
            severity: .error,
            message: "First problem"
        )
        let secondDiagnostic = LSPDiagnostic(
            range: LSPRange(
                start: LSPPosition(line: 2, character: 4),
                end: LSPPosition(line: 2, character: 9)
            ),
            severity: .warning,
            message: "Second problem"
        )

        lspService.injectDiagnosticsForTesting(
            uri: uri,
            diagnostics: [firstDiagnostic, secondDiagnostic]
        )

        viewModel.openDiagnostic(firstDiagnostic)
        #expect(viewModel.activeCurrentDiagnosticID == firstDiagnostic.id)
        #expect(viewModel.currentProblemPositionText == "Problem 1 of 2")

        viewModel.openNextProblem()
        #expect(viewModel.selectedTab?.pendingLineJump == 3)
        #expect(viewModel.activeCurrentDiagnosticID == secondDiagnostic.id)
        #expect(viewModel.currentProblemPositionText == "Problem 2 of 2")

        viewModel.openNextProblem()
        #expect(viewModel.selectedTab?.pendingLineJump == 1)
        #expect(viewModel.activeCurrentDiagnosticID == firstDiagnostic.id)
    }

    @Test
    func activeProblemSelectionTracksCursorMovement() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("swift")
        try """
        let alpha = 1
        let beta = alpha + 1
        let gamma = beta + 1
        """.write(to: fileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let configURL = tempConfigURL()
        defer { try? FileManager.default.removeItem(at: configURL) }

        let lspService = MockLSPService()
        let viewModel = makeViewModel(
            sessionStore: makeDefaults(),
            sessionKey: "problem-cursor-selection-test",
            configService: ConfigurationService(userConfigURL: configURL),
            fileWatcher: FileWatcherService(),
            ui: TestProjectUI(),
            lspService: lspService
        )

        viewModel.openFile(at: fileURL)
        let uri = try #require(viewModel.selectedTab?.documentURI)
        let firstDiagnostic = LSPDiagnostic(
            range: LSPRange(
                start: LSPPosition(line: 0, character: 4),
                end: LSPPosition(line: 0, character: 9)
            ),
            severity: .error,
            message: "First problem"
        )
        let secondDiagnostic = LSPDiagnostic(
            range: LSPRange(
                start: LSPPosition(line: 2, character: 4),
                end: LSPPosition(line: 2, character: 9)
            ),
            severity: .warning,
            message: "Second problem"
        )

        lspService.injectDiagnosticsForTesting(
            uri: uri,
            diagnostics: [firstDiagnostic, secondDiagnostic]
        )

        viewModel.updateCursorPosition(line: 1, column: 1)
        #expect(viewModel.activeCurrentDiagnosticID == firstDiagnostic.id)
        #expect(viewModel.currentProblemPositionText == "Problem 1 of 2")

        viewModel.updateCursorPosition(line: 3, column: 6)
        #expect(viewModel.activeCurrentDiagnosticID == secondDiagnostic.id)
        #expect(viewModel.currentProblemPositionText == "Problem 2 of 2")
    }

    @Test
    func workspaceProblemScopeAggregatesAcrossFilesAndNavigatesBetweenFiles() throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let alphaURL = rootURL.appendingPathComponent("Alpha.swift")
        let betaURL = rootURL.appendingPathComponent("Beta.swift")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try """
        let alpha = 1
        let beta = alpha + 1
        """.write(to: alphaURL, atomically: true, encoding: .utf8)
        try """
        struct BetaFixture {
            let value = alpha
        }
        """.write(to: betaURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let configURL = tempConfigURL()
        defer { try? FileManager.default.removeItem(at: configURL) }

        let lspService = MockLSPService()
        let viewModel = makeViewModel(
            sessionStore: makeDefaults(),
            sessionKey: "workspace-problem-scope-test",
            configService: ConfigurationService(userConfigURL: configURL),
            fileWatcher: FileWatcherService(),
            ui: TestProjectUI(),
            lspService: lspService
        )

        viewModel.rootDirectory = rootURL
        viewModel.openFile(at: alphaURL)

        let alphaDiagnostic = LSPDiagnostic(
            range: LSPRange(
                start: LSPPosition(line: 0, character: 4),
                end: LSPPosition(line: 0, character: 9)
            ),
            severity: .error,
            message: "First problem"
        )
        let betaDiagnostic = LSPDiagnostic(
            range: LSPRange(
                start: LSPPosition(line: 1, character: 16),
                end: LSPPosition(line: 1, character: 21)
            ),
            severity: .warning,
            message: "Second problem"
        )

        lspService.setDiagnostics(uri: alphaURL.absoluteString, diagnostics: [alphaDiagnostic])
        lspService.setDiagnostics(uri: betaURL.absoluteString, diagnostics: [betaDiagnostic])

        #expect(viewModel.workspaceDiagnosticFileCount == 2)
        #expect(viewModel.workspaceDiagnosticCount.errors == 1)
        #expect(viewModel.workspaceDiagnosticCount.warnings == 1)

        viewModel.setDiagnosticsPanelScope(.workspace)
        #expect(viewModel.currentProblemPositionText == "Problem 1 of 2")

        viewModel.openNextProblem()
        #expect(viewModel.selectedTab?.filePath == betaURL)
        #expect(viewModel.selectedTab?.pendingLineJump == 2)
        #expect(viewModel.currentProblemPositionText == "Problem 2 of 2")

        if let selectedTabIndex = viewModel.selectedTabIndex {
            viewModel.openTabs[selectedTabIndex].pendingLineJump = nil
        }

        viewModel.openPreviousProblem()
        #expect(viewModel.selectedTab?.filePath == alphaURL)
        #expect(viewModel.selectedTab?.pendingLineJump == 1)
    }

    @Test
    func toggleDiagnosticsPanelDefaultsToWorkspaceScopeWhenCurrentFileHasNoProblems() throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let alphaURL = rootURL.appendingPathComponent("Alpha.swift")
        let betaURL = rootURL.appendingPathComponent("Beta.swift")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try "let alpha = 1\n".write(to: alphaURL, atomically: true, encoding: .utf8)
        try "let beta = alpha\n".write(to: betaURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let configURL = tempConfigURL()
        defer { try? FileManager.default.removeItem(at: configURL) }

        let lspService = MockLSPService()
        let viewModel = makeViewModel(
            sessionStore: makeDefaults(),
            sessionKey: "workspace-diagnostics-default-scope-test",
            configService: ConfigurationService(userConfigURL: configURL),
            fileWatcher: FileWatcherService(),
            ui: TestProjectUI(),
            lspService: lspService
        )

        viewModel.rootDirectory = rootURL
        viewModel.openFile(at: alphaURL)

        let workspaceDiagnostic = LSPDiagnostic(
            range: LSPRange(
                start: LSPPosition(line: 0, character: 11),
                end: LSPPosition(line: 0, character: 16)
            ),
            severity: .error,
            message: "Workspace-only problem"
        )

        lspService.setDiagnostics(uri: betaURL.absoluteString, diagnostics: [workspaceDiagnostic])

        #expect(viewModel.canNavigateCurrentProblems == false)
        #expect(viewModel.hasWorkspaceDiagnostics)

        viewModel.toggleDiagnosticsPanel()

        #expect(viewModel.isDiagnosticsPanelVisible)
        #expect(viewModel.diagnosticsPanelScope == .workspace)
        #expect(viewModel.currentProblemPositionText == "Problem 1 of 1")
    }

    @Test
    func openNextAndPreviousBreakpointWrapAcrossWorkspace() throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let alphaURL = rootURL.appendingPathComponent("Alpha.swift")
        let betaURL = rootURL.appendingPathComponent("Beta.swift")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try "let alpha = 1\n".write(to: alphaURL, atomically: true, encoding: .utf8)
        try "let beta = 2\n".write(to: betaURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let configURL = tempConfigURL()
        defer { try? FileManager.default.removeItem(at: configURL) }

        let viewModel = makeViewModel(
            sessionStore: makeDefaults(),
            sessionKey: "open-next-breakpoint-test",
            configService: ConfigurationService(userConfigURL: configURL),
            fileWatcher: FileWatcherService(),
            ui: TestProjectUI()
        )

        viewModel.rootDirectory = rootURL
        viewModel.openFile(at: alphaURL)
        viewModel.toggleBreakpoint(line: 1)
        viewModel.openFile(at: betaURL)
        viewModel.toggleBreakpoint(line: 1)

        viewModel.openFile(at: alphaURL)
        viewModel.updateCursorPosition(line: 1, column: 1)
        viewModel.openNextBreakpoint()
        #expect(viewModel.selectedTab?.filePath == betaURL)
        #expect(viewModel.selectedTab?.pendingLineJump == 1)

        viewModel.openFile(at: alphaURL)
        viewModel.updateCursorPosition(line: 1, column: 1)
        if let selectedTabIndex = viewModel.selectedTabIndex {
            viewModel.openTabs[selectedTabIndex].pendingLineJump = nil
        }
        viewModel.openPreviousBreakpoint()
        #expect(viewModel.selectedTab?.filePath == betaURL)
        #expect(viewModel.selectedTab?.pendingLineJump == 1)
    }

    @Test
    func openCurrentDebugStopLocationOpensPausedFileAndQueuesLineJump() async throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let alphaURL = rootURL.appendingPathComponent("Alpha.swift")
        let betaURL = rootURL.appendingPathComponent("Beta.swift")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try "let alpha = 1\n".write(to: alphaURL, atomically: true, encoding: .utf8)
        try "let beta = 2\nlet gamma = 3\n".write(to: betaURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let configURL = tempConfigURL()
        defer { try? FileManager.default.removeItem(at: configURL) }

        let debugSessionService = MockDebugSessionService()
        let viewModel = makeViewModel(
            sessionStore: makeDefaults(),
            sessionKey: "open-debug-stop-location-test",
            configService: ConfigurationService(userConfigURL: configURL),
            fileWatcher: FileWatcherService(),
            ui: TestProjectUI(),
            debugSessionService: debugSessionService
        )

        viewModel.rootDirectory = rootURL
        viewModel.openFile(at: alphaURL)
        debugSessionService.eventHandler?(.stopped(filePath: betaURL.path, line: 2, reason: "breakpoint"))

        try await waitUntil {
            viewModel.hasCurrentDebugStopLocation && viewModel.selectedTab?.filePath == betaURL
        }

        if let selectedTabIndex = viewModel.selectedTabIndex {
            viewModel.openTabs[selectedTabIndex].pendingLineJump = nil
        }
        viewModel.openCurrentDebugStopLocation()

        #expect(viewModel.selectedTab?.filePath == betaURL)
        #expect(viewModel.selectedTab?.pendingLineJump == 2)
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
    debugSessionService: DebugSessionServiceProtocol? = nil,
    gitService: GitServiceProtocol = MockGitService(),
    projectSearchDebounceNanoseconds: UInt64 = 250_000_000
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
        debugSessionService: debugSessionService,
        gitService: gitService,
        projectSearchDebounceNanoseconds: projectSearchDebounceNanoseconds
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

private final class MockGitService: GitServiceProtocol {
    var repositoryStatusResult: GitRepositoryStatus = .empty
    var diffResults: [String: GitDiffResult] = [:]
    var blameResults: [String: GitBlameInfo] = [:]
    var stageResult: GitOperationResult = .success
    var unstageResult: GitOperationResult = .success
    var discardResult: GitOperationResult = .success

    private let lock = NSLock()

    private(set) var repositoryStatusCalls: [URL] = []
    private(set) var diffCalls: [String] = []
    private(set) var blameCalls: [(fileURL: URL, line: Int)] = []
    private(set) var stageCalls: [String] = []
    private(set) var unstageCalls: [String] = []
    private(set) var discardCalls: [String] = []

    func repositoryStatus(for projectRoot: URL?) async -> GitRepositoryStatus {
        if let projectRoot {
            lock.lock()
            repositoryStatusCalls.append(projectRoot)
            lock.unlock()
        }
        lock.lock()
        let result = repositoryStatusResult
        lock.unlock()
        return result
    }

    func diff(for changedFile: GitChangedFile, projectRoot: URL?) async -> GitDiffResult? {
        lock.lock()
        diffCalls.append(changedFile.path)
        let result = diffResults[changedFile.path]
        lock.unlock()
        return result
    }

    func blame(for fileURL: URL?, line: Int, projectRoot: URL?) async -> GitBlameInfo? {
        guard let fileURL else { return nil }
        lock.lock()
        blameCalls.append((fileURL, line))
        let result = blameResults["\(fileURL.standardizedFileURL.path):\(line)"]
        lock.unlock()
        return result
    }

    func stage(changedFile: GitChangedFile, projectRoot: URL?) async -> GitOperationResult {
        lock.lock()
        stageCalls.append(changedFile.path)
        let result = stageResult
        lock.unlock()
        return result
    }

    func unstage(changedFile: GitChangedFile, projectRoot: URL?) async -> GitOperationResult {
        lock.lock()
        unstageCalls.append(changedFile.path)
        let result = unstageResult
        lock.unlock()
        return result
    }

    func discard(changedFile: GitChangedFile, projectRoot: URL?) async -> GitOperationResult {
        lock.lock()
        discardCalls.append(changedFile.path)
        let result = discardResult
        lock.unlock()
        return result
    }
}
