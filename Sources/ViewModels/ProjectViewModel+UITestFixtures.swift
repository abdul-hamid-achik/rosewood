import Foundation

extension ProjectViewModel {
    func installUITestEditorFixturesIfNeeded() {
        let environment = ProcessInfo.processInfo.environment
        let shouldInstallContextMenuFixture = environment["ROSEWOOD_UI_TEST_CONTEXT_MENU_FIXTURE"] == "1"
        let shouldInstallSearchFixture = environment["ROSEWOOD_UI_TEST_SEARCH_FIXTURE"] == "1"
        let shouldInstallDiagnosticsFixture = environment["ROSEWOOD_UI_TEST_DIAGNOSTICS_FIXTURE"] == "1"
        let shouldOpenDiagnosticsPanel = environment["ROSEWOOD_UI_TEST_OPEN_DIAGNOSTICS_PANEL"] == "1"
        let shouldInstallReferencesFixture = environment["ROSEWOOD_UI_TEST_REFERENCES_FIXTURE"] == "1"
        let shouldOpenReferencesPanel = environment["ROSEWOOD_UI_TEST_OPEN_REFERENCES_PANEL"] == "1"
        let shouldInstallFoldingFixture = environment["ROSEWOOD_UI_TEST_FOLDING_FIXTURE"] == "1"
        let shouldInstallMinimapFixture = environment["ROSEWOOD_UI_TEST_MINIMAP_FIXTURE"] == "1"
        let shouldInstallGitFixture = environment["ROSEWOOD_UI_TEST_GIT_FIXTURE"] == "1"
        let shouldInstallNavigationFixture = environment["ROSEWOOD_UI_TEST_NAVIGATION_FIXTURE"] == "1"
        let shouldInstallExplorerFixture = environment["ROSEWOOD_UI_TEST_EXPLORER_FIXTURE"] == "1"
        let shouldInstallDebugCommandsFixture = environment["ROSEWOOD_UI_TEST_DEBUG_COMMANDS_FIXTURE"] == "1"
        let shouldInstallGoCommandsFixture = environment["ROSEWOOD_UI_TEST_GO_COMMANDS_FIXTURE"] == "1"
        guard shouldInstallContextMenuFixture
            || shouldInstallSearchFixture
            || shouldInstallDiagnosticsFixture
            || shouldInstallReferencesFixture
            || shouldInstallFoldingFixture
            || shouldInstallMinimapFixture
            || shouldInstallGitFixture
            || shouldInstallNavigationFixture
            || shouldInstallExplorerFixture
            || shouldInstallDebugCommandsFixture
            || shouldInstallGoCommandsFixture else {
            return
        }

        let fileManager = FileManager.default
        let fixtureFileName: String
        if shouldInstallDiagnosticsFixture {
            fixtureFileName = "Alpha.swift"
        } else if shouldInstallGitFixture {
            fixtureFileName = "Tracked.swift"
        } else {
            fixtureFileName = "Alpha.swift"
        }
        let rootURL = fileManager.temporaryDirectory.appendingPathComponent(
            "rosewood-ui-context-menu-\(UUID().uuidString)",
            isDirectory: true
        )
        let alphaURL = rootURL.appendingPathComponent(fixtureFileName)
        let betaURL = rootURL.appendingPathComponent("Beta.swift")

        do {
            try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
            let alphaContents: String
            if shouldInstallSearchFixture {
                alphaContents = "let alpha = 1\n"
            } else if shouldInstallDiagnosticsFixture {
                alphaContents = """
                let alpha = 1
                let beta = alpha + 1
                let gamma = beta + 1
                """
            } else if shouldInstallNavigationFixture {
                alphaContents = """
                struct AlphaSymbol {
                    func alphaHelper() {
                        let alphaValue = 1
                    }
                }
                """
            } else if shouldInstallExplorerFixture {
                alphaContents = """
                struct ExplorerFeature {
                    func firstThing() {}
                    func secondThing() {}
                }
                """
            } else if shouldInstallGoCommandsFixture {
                alphaContents = """
                let alpha = 1
                let beta = alpha + 1
                let gamma = beta + 1
                """
            } else if shouldInstallFoldingFixture {
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
            } else if shouldInstallGitFixture {
                alphaContents = "let tracked = 1\n"
            } else {
                alphaContents = "let alpha = 1\n"
            }
            try alphaContents.write(to: alphaURL, atomically: true, encoding: .utf8)

            if shouldInstallSearchFixture {
                try "let beta = alpha\n".write(to: betaURL, atomically: true, encoding: .utf8)
            } else if shouldInstallDiagnosticsFixture {
                try """
                struct BetaFixture {
                    let value = alpha
                }
                """.write(to: betaURL, atomically: true, encoding: .utf8)
            } else if shouldInstallNavigationFixture {
                try """
                func betaHelper() {
                    let betaValue = 2
                }

                func alphaWorkspaceHelper() {
                    let alphaCopy = 1
                }
                """.write(to: betaURL, atomically: true, encoding: .utf8)
            } else if shouldInstallExplorerFixture {
                let sourcesURL = rootURL.appendingPathComponent("Sources", isDirectory: true)
                let featuresURL = sourcesURL.appendingPathComponent("Features", isDirectory: true)
                let nestedAlphaURL = featuresURL.appendingPathComponent("Alpha.swift")
                let nestedBetaURL = sourcesURL.appendingPathComponent("Beta.swift")

                try fileManager.createDirectory(at: featuresURL, withIntermediateDirectories: true)
                try alphaContents.write(to: nestedAlphaURL, atomically: true, encoding: .utf8)
                try "func betaThing() {}\n".write(to: nestedBetaURL, atomically: true, encoding: .utf8)
                try? fileManager.removeItem(at: alphaURL)
            }

            if shouldInstallGitFixture {
                try installGitFixture(at: rootURL, trackedFileURL: alphaURL)
            } else if shouldInstallDebugCommandsFixture {
                let configURL = rootURL.appendingPathComponent(".rosewood.toml")
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
                """.write(to: configURL, atomically: true, encoding: .utf8)
            }
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
        clearProjectSearchResults()

        configService.setProjectRoot(rootURL)
        lspService.setProjectRoot(rootURL)
        reloadDebuggerState(resetConsole: true)
        reloadFileTree()

        if !shouldInstallExplorerFixture {
            openFile(at: alphaURL)
        }
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
                            start: LSPPosition(line: 2, character: 4),
                            end: LSPPosition(line: 2, character: 9)
                        ),
                        severity: .warning,
                        source: "sourcekit-lsp",
                        message: "Unused variable declaration"
                    )
                ]
            )

            lspService.injectDiagnosticsForTesting(
                uri: betaURL.absoluteString,
                diagnostics: [
                    LSPDiagnostic(
                        range: LSPRange(
                            start: LSPPosition(line: 1, character: 16),
                            end: LSPPosition(line: 1, character: 21)
                        ),
                        severity: .error,
                        source: "sourcekit-lsp",
                        message: "Cannot find 'alpha' in scope"
                    )
                ]
            )

            if shouldOpenDiagnosticsPanel {
                bottomPanel = .diagnostics
            }
        }

        if shouldInstallGoCommandsFixture, let uri = openTabs.first?.documentURI {
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
                            start: LSPPosition(line: 2, character: 4),
                            end: LSPPosition(line: 2, character: 9)
                        ),
                        severity: .warning,
                        source: "sourcekit-lsp",
                        message: "Unused variable declaration"
                    )
                ]
            )
            breakpoints = [
                Breakpoint(filePath: normalizedPath(for: alphaURL), line: 1),
                Breakpoint(filePath: normalizedPath(for: alphaURL), line: 3)
            ]
            debugStoppedFilePath = normalizedPath(for: alphaURL)
            debugStoppedLine = 2
        }

        if shouldInstallReferencesFixture {
            let betaReferenceURL = rootURL.appendingPathComponent("Beta.txt")
            try? "let beta = alpha\n".write(to: betaReferenceURL, atomically: true, encoding: .utf8)
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
                        uri: betaReferenceURL.absoluteString,
                        range: LSPRange(
                            start: LSPPosition(line: 0, character: 11),
                            end: LSPPosition(line: 0, character: 16)
                        )
                    ),
                    fileURL: betaReferenceURL,
                    path: relativeDisplayPath(for: betaReferenceURL),
                    line: 1,
                    column: 12,
                    lineText: "let beta = alpha"
                )
            ]

            if shouldOpenReferencesPanel {
                bottomPanel = .references
            }
        }

        if shouldInstallGitFixture {
            sidebarMode = environment["ROSEWOOD_UI_TEST_GIT_EXPLORER"] == "1" ? .explorer : .sourceControl
        }

        persistSession()
        refreshGitState()
    }

    func installGitFixture(at rootURL: URL, trackedFileURL: URL) throws {
        let gitignoreURL = rootURL.appendingPathComponent(".gitignore")
        let ignoredFileURL = rootURL.appendingPathComponent("Ignored.log")
        try "Ignored.log\nIgnoredDir/\n".write(to: gitignoreURL, atomically: true, encoding: .utf8)

        func run(_ arguments: [String]) throws {
            let process = Process()
            let stderrPipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["git"] + arguments
            process.currentDirectoryURL = rootURL
            process.standardError = stderrPipe
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus != 0 {
                let stderr = String(
                    data: stderrPipe.fileHandleForReading.readDataToEndOfFile(),
                    encoding: .utf8
                ) ?? ""
                throw GitServiceError.commandFailed(stderr.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }

        try run(["init", "--initial-branch=main"])
        try run(["config", "user.name", "Rosewood UITests"])
        try run(["config", "user.email", "rosewood-ui@example.com"])
        try run(["add", trackedFileURL.lastPathComponent, gitignoreURL.lastPathComponent])
        try run(["commit", "-m", "Initial commit"])
        try "let tracked = 2\n".write(to: trackedFileURL, atomically: true, encoding: .utf8)
        try "ignore me\n".write(to: ignoredFileURL, atomically: true, encoding: .utf8)
    }
}
