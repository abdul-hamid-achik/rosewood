import XCTest

final class RosewoodUITests: XCTestCase {
    private func hasAccessibilityIdentifier(_ app: XCUIApplication, _ identifier: String) -> Bool {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch.exists
    }

    private func waitForElementCount(
        _ query: XCUIElementQuery,
        count expectedCount: Int,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if query.count == expectedCount {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return query.count == expectedCount
    }

    private func waitForCondition(timeout: TimeInterval, _ condition: @escaping () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if condition() {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        } while Date() < deadline

        return condition()
    }

    private func waitForElementValue(
        in element: XCUIElement,
        toEqual expectedValue: String,
        timeout: TimeInterval = 2
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if (element.value as? String) == expectedValue {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        } while Date() < deadline

        return (element.value as? String) == expectedValue
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchShowsMainShellAndSearchSidebar() throws {
        let app = XCUIApplication()
        app.launchEnvironment["ROSEWOOD_UI_TEST_RESET_SESSION"] = "1"
        app.launch()

        XCTAssertTrue(app.staticTexts["No Folder Open"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Open Folder"].exists)
        XCTAssertTrue(app.staticTexts["Select a file to edit"].exists)

        app.typeKey("f", modifierFlags: [.command, .shift])

        XCTAssertTrue(app.textFields["Search in project"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.textFields["Replace with"].exists)
        XCTAssertFalse(app.buttons["Find"].exists)
        XCTAssertTrue(hasAccessibilityIdentifier(app, "project-search-replace-all"))
        XCTAssertTrue(hasAccessibilityIdentifier(app, "project-search-case-sensitive"))
        XCTAssertTrue(hasAccessibilityIdentifier(app, "project-search-whole-word"))
        XCTAssertTrue(hasAccessibilityIdentifier(app, "project-search-regex"))
        XCTAssertTrue(hasAccessibilityIdentifier(app, "project-search-include-glob"))
        XCTAssertTrue(hasAccessibilityIdentifier(app, "project-search-exclude-glob"))
    }

    @MainActor
    func testLaunchSupportsQuickOpenAndCommandPaletteShortcuts() throws {
        let app = XCUIApplication()
        app.launchEnvironment["ROSEWOOD_UI_TEST_RESET_SESSION"] = "1"
        app.launch()
        activateAndFocus(app)

        app.typeKey("p", modifierFlags: [.command])
        XCTAssertTrue(app.textFields["quick-open-input"].waitForExistence(timeout: 2))

        app.typeKey("p", modifierFlags: [.command, .shift])
        XCTAssertTrue(app.textFields["command-palette-input"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testCommandPaletteAliasSearchCanOpenWorkspaceSymbolMode() throws {
        let app = XCUIApplication()
        app.launchEnvironment["ROSEWOOD_UI_TEST_RESET_SESSION"] = "1"
        app.launchEnvironment["ROSEWOOD_UI_TEST_NAVIGATION_FIXTURE"] = "1"
        app.launch()
        activateAndFocus(app)

        app.typeKey("p", modifierFlags: [.command, .shift])

        let commandField = app.textFields["command-palette-input"]
        XCTAssertTrue(commandField.waitForExistence(timeout: 2))

        commandField.click()
        commandField.typeText("workspace symbol")

        let symbolAction = app.buttons["command-palette-action-goToSymbol"]
        XCTAssertTrue(symbolAction.waitForExistence(timeout: 5))
        app.typeKey(XCUIKeyboardKey.return.rawValue, modifierFlags: [])

        let quickOpenField = app.textFields["quick-open-input"]
        XCTAssertTrue(quickOpenField.waitForExistence(timeout: 2))

        quickOpenField.click()
        quickOpenField.typeText("alphahelper")
        XCTAssertTrue(app.buttons["quick-open-symbol-0"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testCommandPaletteShowsRecentSectionAfterRunningCommand() throws {
        let app = XCUIApplication()
        app.launchEnvironment["ROSEWOOD_UI_TEST_RESET_SESSION"] = "1"
        app.launchEnvironment["ROSEWOOD_UI_TEST_NAVIGATION_FIXTURE"] = "1"
        app.launch()
        activateAndFocus(app)

        app.typeKey("p", modifierFlags: [.command, .shift])

        let commandField = app.textFields["command-palette-input"]
        XCTAssertTrue(commandField.waitForExistence(timeout: 2))

        commandField.click()
        commandField.typeText("workspace symbol")
        XCTAssertTrue(app.buttons["command-palette-action-goToSymbol"].waitForExistence(timeout: 2))
        app.typeKey(XCUIKeyboardKey.return.rawValue, modifierFlags: [])

        let quickOpenField = app.textFields["quick-open-input"]
        XCTAssertTrue(quickOpenField.waitForExistence(timeout: 2))
        app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])

        app.typeKey("p", modifierFlags: [.command, .shift])
        XCTAssertTrue(commandField.waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Recent"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["command-palette-action-goToSymbol"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testCommandPaletteScopeChipsCanNarrowCommandCategories() throws {
        let app = XCUIApplication()
        app.launchEnvironment["ROSEWOOD_UI_TEST_RESET_SESSION"] = "1"
        app.launchEnvironment["ROSEWOOD_UI_TEST_NAVIGATION_FIXTURE"] = "1"
        app.launch()
        activateAndFocus(app)

        app.typeKey("p", modifierFlags: [.command, .shift])

        let commandField = app.textFields["command-palette-input"]
        XCTAssertTrue(commandField.waitForExistence(timeout: 2))
        let helpText = app.descendants(matching: .any).matching(identifier: "command-palette-help-text").firstMatch
        XCTAssertTrue(helpText.waitForExistence(timeout: 2))

        let searchScope = app.buttons["command-palette-scope-search"]
        XCTAssertTrue(searchScope.waitForExistence(timeout: 5))
        searchScope.click()

        XCTAssertTrue(app.buttons["command-palette-action-showProjectSearch"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["command-palette-action-newFile"].exists)
    }

    @MainActor
    func testCommandPaletteCanOpenProblemsPanel() throws {
        let app = XCUIApplication()
        app.launchEnvironment["ROSEWOOD_UI_TEST_RESET_SESSION"] = "1"
        app.launchEnvironment["ROSEWOOD_UI_TEST_DIAGNOSTICS_FIXTURE"] = "1"
        app.launch()
        activateAndFocus(app)

        app.typeKey("p", modifierFlags: [.command, .shift])

        let commandField = app.textFields["command-palette-input"]
        XCTAssertTrue(commandField.waitForExistence(timeout: 2))

        commandField.click()
        commandField.typeText("workspace problems")

        let workspaceProblemsAction = app.buttons["command-palette-action-showWorkspaceProblems"]
        XCTAssertTrue(workspaceProblemsAction.waitForExistence(timeout: 2))
        app.typeKey(XCUIKeyboardKey.return.rawValue, modifierFlags: [])

        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "problems-panel").firstMatch.waitForExistence(timeout: 2))
    }

    @MainActor
    func testCommandPaletteCanSwitchFromSourceControlToExplorer() throws {
        let app = XCUIApplication()
        app.launchEnvironment["ROSEWOOD_UI_TEST_RESET_SESSION"] = "1"
        app.launchEnvironment["ROSEWOOD_UI_TEST_GIT_FIXTURE"] = "1"
        app.launch()
        activateAndFocus(app)

        let sourceControlSidebar = app.descendants(matching: .any).matching(identifier: "source-control-sidebar").firstMatch
        XCTAssertTrue(sourceControlSidebar.waitForExistence(timeout: 5))

        app.typeKey("p", modifierFlags: [.command, .shift])

        let commandField = app.textFields["command-palette-input"]
        XCTAssertTrue(commandField.waitForExistence(timeout: 2))

        commandField.click()
        commandField.typeText("explorer")

        let explorerAction = app.buttons["command-palette-action-showExplorer"]
        XCTAssertTrue(explorerAction.waitForExistence(timeout: 2))
        app.typeKey(XCUIKeyboardKey.return.rawValue, modifierFlags: [])

        let trackedRow = app.descendants(matching: .any).matching(identifier: "file-tree-row-Tracked.swift").firstMatch
        XCTAssertTrue(trackedRow.waitForExistence(timeout: 5))
    }

    @MainActor
    func testCommandPaletteShowsContextualGitChangeActions() throws {
        let app = XCUIApplication()
        app.launchEnvironment["ROSEWOOD_UI_TEST_RESET_SESSION"] = "1"
        app.launchEnvironment["ROSEWOOD_UI_TEST_GIT_FIXTURE"] = "1"
        app.launch()
        activateAndFocus(app)

        let changedFile = app.descendants(matching: .any).matching(identifier: "git-change-row-0").firstMatch
        XCTAssertTrue(changedFile.waitForExistence(timeout: 5))
        changedFile.click()

        let diffWorkspace = app.descendants(matching: .any).matching(identifier: "git-diff-workspace").firstMatch
        XCTAssertTrue(diffWorkspace.waitForExistence(timeout: 8))

        app.typeKey("p", modifierFlags: [.command, .shift])

        let commandField = app.textFields["command-palette-input"]
        XCTAssertTrue(commandField.waitForExistence(timeout: 2))

        commandField.click()
        commandField.typeText("git:")

        let revealExplorerAction = app.buttons["command-palette-action-revealSelectedGitChangeInExplorer"]
        XCTAssertTrue(revealExplorerAction.waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["command-palette-action-openSelectedGitChangeInEditor"].exists)
        XCTAssertTrue(app.buttons["command-palette-action-stageSelectedGitChange"].exists)
    }

    @MainActor
    func testQuickOpenSupportsLineAndSymbolNavigation() throws {
        let app = XCUIApplication()
        app.launchEnvironment["ROSEWOOD_UI_TEST_RESET_SESSION"] = "1"
        app.launchEnvironment["ROSEWOOD_UI_TEST_NAVIGATION_FIXTURE"] = "1"
        app.launch()
        activateAndFocus(app)

        app.typeKey("p", modifierFlags: [.command])

        let quickOpenField = app.textFields["quick-open-input"]
        XCTAssertTrue(quickOpenField.waitForExistence(timeout: 2))

        quickOpenField.click()
        quickOpenField.typeText(":3")
        XCTAssertTrue(app.staticTexts["quick-open-help-text"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["quick-open-line-jump-0"].waitForExistence(timeout: 2))
        app.typeKey(XCUIKeyboardKey.return.rawValue, modifierFlags: [])

        XCTAssertTrue(app.staticTexts["Line 3, Col 1"].waitForExistence(timeout: 2))

        app.typeKey("p", modifierFlags: [.command])
        XCTAssertTrue(quickOpenField.waitForExistence(timeout: 2))

        quickOpenField.click()
        quickOpenField.typeText("#alphahelper")
        XCTAssertTrue(app.staticTexts["quick-open-help-text"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["quick-open-symbol-0"].waitForExistence(timeout: 2))
        app.typeKey(XCUIKeyboardKey.return.rawValue, modifierFlags: [])

        XCTAssertTrue(app.staticTexts["Line 2, Col 1"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testQuickOpenSymbolSearchShowsCurrentFileAndWorkspaceSections() throws {
        let app = XCUIApplication()
        app.launchEnvironment["ROSEWOOD_UI_TEST_RESET_SESSION"] = "1"
        app.launchEnvironment["ROSEWOOD_UI_TEST_NAVIGATION_FIXTURE"] = "1"
        app.launch()
        activateAndFocus(app)

        app.typeKey("p", modifierFlags: [.command])

        let quickOpenField = app.textFields["quick-open-input"]
        XCTAssertTrue(quickOpenField.waitForExistence(timeout: 2))

        quickOpenField.click()
        quickOpenField.typeText("#alpha")

        XCTAssertTrue(app.staticTexts["Current File"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Workspace"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testQuickOpenProblemSearchOpensWorkspaceDiagnostic() throws {
        let app = XCUIApplication()
        app.launchEnvironment["ROSEWOOD_UI_TEST_RESET_SESSION"] = "1"
        app.launchEnvironment["ROSEWOOD_UI_TEST_DIAGNOSTICS_FIXTURE"] = "1"
        app.launch()
        activateAndFocus(app)

        let diagnosticsToggle = app.buttons["statusbar-diagnostics-toggle"]
        XCTAssertTrue(diagnosticsToggle.waitForExistence(timeout: 2))

        app.typeKey("p", modifierFlags: [.command, .shift])

        let commandField = app.textFields["command-palette-input"]
        XCTAssertTrue(commandField.waitForExistence(timeout: 2))
        commandField.click()
        commandField.typeText("workspace problem")

        let problemCommand = app.buttons["command-palette-action-goToProblem"]
        XCTAssertTrue(problemCommand.waitForExistence(timeout: 2))
        app.typeKey(XCUIKeyboardKey.return.rawValue, modifierFlags: [])

        let quickOpenField = app.textFields["quick-open-input"]
        XCTAssertTrue(quickOpenField.waitForExistence(timeout: 2))
        XCTAssertEqual(quickOpenField.value as? String, "!")

        let quickOpenHelp = app.staticTexts["quick-open-help-text"]
        XCTAssertTrue(quickOpenHelp.waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["quick-open-problem-filter-workspace"].waitForExistence(timeout: 2))

        quickOpenField.click()
        quickOpenField.typeText("error")

        let problemResult = app.buttons["quick-open-problem-0"]
        XCTAssertTrue(problemResult.waitForExistence(timeout: 2))
        problemResult.click()

        let betaTab = app.descendants(matching: .any).matching(identifier: "tab-item-1").firstMatch
        XCTAssertTrue(betaTab.waitForExistence(timeout: 2))
        XCTAssertFalse(app.textFields["quick-open-input"].exists)
    }

    @MainActor
    func testProjectSearchUpdatesResultsWhileTyping() throws {
        let app = XCUIApplication()
        app.launchEnvironment["ROSEWOOD_UI_TEST_RESET_SESSION"] = "1"
        app.launchEnvironment["ROSEWOOD_UI_TEST_CONTEXT_MENU_FIXTURE"] = "1"
        app.launch()
        activateAndFocus(app)

        app.typeKey("f", modifierFlags: [.command, .shift])

        let searchField = app.textFields["Search in project"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 2))

        searchField.click()
        searchField.typeText("alpha")

        let replaceAllButton = app.buttons["project-search-replace-all"]
        XCTAssertTrue(replaceAllButton.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForCondition(timeout: 5) { replaceAllButton.isEnabled })
    }

    @MainActor
    func testProjectSearchKeyboardNavigationOpensActiveResult() throws {
        let app = XCUIApplication()
        app.launchEnvironment["ROSEWOOD_UI_TEST_RESET_SESSION"] = "1"
        app.launchEnvironment["ROSEWOOD_UI_TEST_SEARCH_FIXTURE"] = "1"
        app.launch()
        activateAndFocus(app)

        app.typeKey("f", modifierFlags: [.command, .shift])

        let searchField = app.textFields["Search in project"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 2))

        searchField.click()
        searchField.typeText("alpha")

        let collapseButton = app.buttons["project-search-collapse-all"]
        XCTAssertTrue(collapseButton.waitForExistence(timeout: 5))

        app.typeKey(XCUIKeyboardKey.downArrow.rawValue, modifierFlags: [])
        app.typeKey(XCUIKeyboardKey.return.rawValue, modifierFlags: [])
        let betaTab = app.descendants(matching: .any).matching(identifier: "tab-item-1").firstMatch
        XCTAssertTrue(betaTab.waitForExistence(timeout: 2))
    }

    @MainActor
    func testProjectSearchFileGroupsCanCollapseAndExpand() throws {
        let app = XCUIApplication()
        app.launchEnvironment["ROSEWOOD_UI_TEST_RESET_SESSION"] = "1"
        app.launchEnvironment["ROSEWOOD_UI_TEST_SEARCH_FIXTURE"] = "1"
        app.launch()

        app.typeKey("f", modifierFlags: [.command, .shift])

        let searchField = app.textFields["Search in project"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 2))

        searchField.click()
        searchField.typeText("alpha")

        let collapseButton = app.buttons["project-search-collapse-all"]
        XCTAssertTrue(collapseButton.waitForExistence(timeout: 5))
        collapseButton.click()

        let expandButton = app.buttons["project-search-expand-all"]
        XCTAssertTrue(expandButton.waitForExistence(timeout: 5))
        expandButton.click()
        XCTAssertTrue(collapseButton.waitForExistence(timeout: 5))
    }

    @MainActor
    func testProjectReplaceShowsPreviewBeforeApply() throws {
        let app = XCUIApplication()
        app.launchEnvironment["ROSEWOOD_UI_TEST_RESET_SESSION"] = "1"
        app.launchEnvironment["ROSEWOOD_UI_TEST_CONTEXT_MENU_FIXTURE"] = "1"
        app.launch()

        app.typeKey("f", modifierFlags: [.command, .shift])

        let searchField = app.textFields["Search in project"]
        let replaceField = app.textFields["Replace with"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 2))
        XCTAssertTrue(replaceField.exists)

        searchField.click()
        searchField.typeText("alpha")
        replaceField.click()
        replaceField.typeText("omega")

        let replaceButton = app.buttons["Replace Selected (1)"]
        XCTAssertTrue(replaceButton.exists)
        replaceButton.click()

        XCTAssertTrue(app.staticTexts["Replace Preview"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["Apply Replace"].exists)
        XCTAssertTrue(app.buttons["Cancel"].exists)
    }

    @MainActor
    func testLaunchShowsDebugSidebarEmptyState() throws {
        let app = XCUIApplication()
        app.launchEnvironment["ROSEWOOD_UI_TEST_RESET_SESSION"] = "1"
        app.launchEnvironment["ROSEWOOD_UI_TEST_DEBUG_SIDEBAR"] = "1"
        app.launch()

        XCTAssertTrue(app.staticTexts["Open a folder to configure debugging."].waitForExistence(timeout: 2))
    }

    @MainActor
    func testCommandPaletteDebugScopeShowsSessionAndConfigurationActions() throws {
        let app = XCUIApplication()
        app.launchEnvironment["ROSEWOOD_UI_TEST_RESET_SESSION"] = "1"
        app.launchEnvironment["ROSEWOOD_UI_TEST_DEBUG_COMMANDS_FIXTURE"] = "1"
        app.launch()
        activateAndFocus(app)

        app.typeKey("p", modifierFlags: [.command, .shift])

        let commandField = app.textFields["command-palette-input"]
        XCTAssertTrue(commandField.waitForExistence(timeout: 2))

        commandField.click()
        commandField.typeText("debug:")

        XCTAssertTrue(app.buttons["command-palette-action-startDebugging"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["command-palette-action-showDebugConsole"].exists)
        XCTAssertTrue(app.buttons["command-palette-action-selectDebugConfiguration-tests"].exists)
    }

    @MainActor
    func testCommandPaletteGoScopeShowsBreakpointAndStopLocationActions() throws {
        let app = XCUIApplication()
        app.launchEnvironment["ROSEWOOD_UI_TEST_RESET_SESSION"] = "1"
        app.launchEnvironment["ROSEWOOD_UI_TEST_GO_COMMANDS_FIXTURE"] = "1"
        app.launch()
        activateAndFocus(app)

        app.typeKey("p", modifierFlags: [.command, .shift])

        let commandField = app.textFields["command-palette-input"]
        XCTAssertTrue(commandField.waitForExistence(timeout: 2))

        commandField.click()
        commandField.typeText("go:")

        XCTAssertTrue(app.buttons["command-palette-action-nextBreakpoint"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["command-palette-action-previousBreakpoint"].exists)
        XCTAssertTrue(app.buttons["command-palette-action-openCurrentDebugStopLocation"].exists)
    }

    @MainActor
    func testLaunchUsesSidebarNavigationWithoutRedundantToolbar() throws {
        let app = XCUIApplication()
        app.launchEnvironment["ROSEWOOD_UI_TEST_RESET_SESSION"] = "1"
        app.launch()

        XCTAssertTrue(app.buttons["activity-sidebar-explorer"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["activity-sidebar-search"].exists)
        XCTAssertFalse(app.buttons["toolbar-debug-sidebar"].exists)
        XCTAssertFalse(app.buttons["toolbar-debug-start"].exists)
        XCTAssertFalse(app.buttons["toolbar-debug-stop"].exists)
    }

    @MainActor
    func testTabContextMenuShowsFileActionsOnlyForSavedTabs() throws {
        let app = XCUIApplication()
        app.launchEnvironment["ROSEWOOD_UI_TEST_RESET_SESSION"] = "1"
        app.launchEnvironment["ROSEWOOD_UI_TEST_CONTEXT_MENU_FIXTURE"] = "1"
        app.launch()

        let savedTab = app.descendants(matching: .any).matching(identifier: "tab-item-0").firstMatch
        let untitledTab = app.descendants(matching: .any).matching(identifier: "tab-item-1").firstMatch

        XCTAssertTrue(savedTab.waitForExistence(timeout: 5))
        XCTAssertTrue(untitledTab.waitForExistence(timeout: 5))

        savedTab.rightClick()
        XCTAssertTrue(app.menuItems["Close"].waitForExistence(timeout: 1))
        XCTAssertTrue(app.menuItems["Copy Path"].exists)
        XCTAssertTrue(app.menuItems["Copy Relative Path"].exists)
        XCTAssertTrue(app.menuItems["Reveal in Finder"].exists)

        app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])

        untitledTab.rightClick()
        XCTAssertTrue(app.menuItems["Close"].waitForExistence(timeout: 1))
        XCTAssertFalse(app.menuItems["Copy Path"].waitForExistence(timeout: 1))
        XCTAssertFalse(app.menuItems["Copy Relative Path"].exists)
        XCTAssertFalse(app.menuItems["Reveal in Finder"].exists)
    }

    @MainActor
    func testDiagnosticsFixtureShowsProblemsPanel() throws {
        let app = XCUIApplication()
        app.launchEnvironment["ROSEWOOD_UI_TEST_RESET_SESSION"] = "1"
        app.launchEnvironment["ROSEWOOD_UI_TEST_DIAGNOSTICS_FIXTURE"] = "1"
        app.launchEnvironment["ROSEWOOD_UI_TEST_OPEN_DIAGNOSTICS_PANEL"] = "1"
        app.launch()

        let toggle = app.buttons["statusbar-diagnostics-toggle"]
        let problemsPanel = app.descendants(matching: .any).matching(identifier: "problems-panel").firstMatch
        let firstDiagnostic = app.descendants(matching: .any).matching(identifier: "diagnostic-row-0").firstMatch
        let secondDiagnostic = app.descendants(matching: .any).matching(identifier: "diagnostic-row-1").firstMatch
        let closeButton = app.descendants(matching: .any).matching(identifier: "problems-panel-close").firstMatch

        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertTrue(problemsPanel.waitForExistence(timeout: 2))
        XCTAssertTrue(firstDiagnostic.exists)
        XCTAssertTrue(secondDiagnostic.exists)
        XCTAssertTrue(closeButton.exists)
    }

    @MainActor
    func testWorkspaceProblemsRemainAvailableInStatusBarAfterClosingLastTab() throws {
        let app = XCUIApplication()
        app.launchEnvironment["ROSEWOOD_UI_TEST_RESET_SESSION"] = "1"
        app.launchEnvironment["ROSEWOOD_UI_TEST_DIAGNOSTICS_FIXTURE"] = "1"
        app.launch()
        activateAndFocus(app)

        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "tab-item-0").firstMatch.waitForExistence(timeout: 2))
        app.typeKey("w", modifierFlags: [.command])

        let toggle = app.buttons["statusbar-diagnostics-toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 2))
        toggle.click()

        let problemsPanel = app.descendants(matching: .any).matching(identifier: "problems-panel").firstMatch
        let workspaceScope = app.buttons["problems-scope-workspace"]

        XCTAssertTrue(toggle.waitForExistence(timeout: 2))
        XCTAssertFalse(problemsPanel.exists)
        XCTAssertFalse(workspaceScope.exists)
    }

    @MainActor
    func testProblemsShortcutOpensPanelWithNavigationControls() throws {
        let app = XCUIApplication()
        app.launchEnvironment["ROSEWOOD_UI_TEST_RESET_SESSION"] = "1"
        app.launchEnvironment["ROSEWOOD_UI_TEST_DIAGNOSTICS_FIXTURE"] = "1"
        app.launch()
        activateAndFocus(app)
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))

        app.typeKey("m", modifierFlags: [.command, .shift])

        let problemsPanel = app.descendants(matching: .any).matching(identifier: "problems-panel").firstMatch
        let summary = app.staticTexts["problems-panel-summary"]
        let previousButton = app.buttons["problems-panel-previous"]
        let nextButton = app.buttons["problems-panel-next"]

        XCTAssertTrue(problemsPanel.waitForExistence(timeout: 2))
        XCTAssertTrue(summary.exists)
        XCTAssertTrue(previousButton.exists)
        XCTAssertTrue(nextButton.exists)
    }

    @MainActor
    func testProblemsPanelShowsActiveProblemPosition() throws {
        let app = XCUIApplication()
        app.launchEnvironment["ROSEWOOD_UI_TEST_RESET_SESSION"] = "1"
        app.launchEnvironment["ROSEWOOD_UI_TEST_DIAGNOSTICS_FIXTURE"] = "1"
        app.launchEnvironment["ROSEWOOD_UI_TEST_OPEN_DIAGNOSTICS_PANEL"] = "1"
        app.launch()

        let position = app.staticTexts["problems-panel-position"]

        XCTAssertTrue(position.waitForExistence(timeout: 2))
        XCTAssertEqual(position.value as? String, "Problem 1 of 2")
    }

    @MainActor
    func testProblemsPanelCanSwitchToWorkspaceScope() throws {
        let app = XCUIApplication()
        app.launchEnvironment["ROSEWOOD_UI_TEST_RESET_SESSION"] = "1"
        app.launchEnvironment["ROSEWOOD_UI_TEST_DIAGNOSTICS_FIXTURE"] = "1"
        app.launchEnvironment["ROSEWOOD_UI_TEST_OPEN_DIAGNOSTICS_PANEL"] = "1"
        app.launch()

        let workspaceScope = app.buttons["problems-scope-workspace"]
        XCTAssertTrue(workspaceScope.waitForExistence(timeout: 2))
        workspaceScope.click()

        let scopeSummary = app.staticTexts["problems-panel-scope-summary"]
        let workspaceRow = app.buttons["workspace-diagnostic-row-0"]
        let position = app.staticTexts["problems-panel-position"]

        XCTAssertTrue(scopeSummary.waitForExistence(timeout: 2))
        XCTAssertTrue(workspaceRow.waitForExistence(timeout: 2))
        XCTAssertTrue(position.waitForExistence(timeout: 2))
    }

    @MainActor
    func testReferencesFixtureShowsReferencesPanel() throws {
        let app = XCUIApplication()
        app.launchEnvironment["ROSEWOOD_UI_TEST_RESET_SESSION"] = "1"
        app.launchEnvironment["ROSEWOOD_UI_TEST_REFERENCES_FIXTURE"] = "1"
        app.launchEnvironment["ROSEWOOD_UI_TEST_OPEN_REFERENCES_PANEL"] = "1"
        app.launch()

        let referencesPanel = app.descendants(matching: .any).matching(identifier: "references-panel").firstMatch
        let firstReference = app.descendants(matching: .any).matching(identifier: "reference-row-0").firstMatch
        let secondReference = app.descendants(matching: .any).matching(identifier: "reference-row-1").firstMatch
        let closeButton = app.descendants(matching: .any).matching(identifier: "references-panel-close").firstMatch

        XCTAssertTrue(referencesPanel.waitForExistence(timeout: 5))
        XCTAssertTrue(firstReference.exists)
        XCTAssertTrue(secondReference.exists)
        XCTAssertTrue(closeButton.exists)
    }

    @MainActor
    func testFoldingFixtureCollapsesAndExpandsFromGutter() throws {
        let app = XCUIApplication()
        app.launchEnvironment["ROSEWOOD_UI_TEST_RESET_SESSION"] = "1"
        app.launchEnvironment["ROSEWOOD_UI_TEST_FOLDING_FIXTURE"] = "1"
        app.launch()

        let textView = app.descendants(matching: .any).matching(identifier: "editor-text-view").firstMatch
        let gutter = app.descendants(matching: .any).matching(identifier: "editor-gutter").firstMatch

        XCTAssertTrue(textView.waitForExistence(timeout: 5))
        XCTAssertTrue(gutter.waitForExistence(timeout: 5))
        XCTAssertTrue(currentEditorText(in: textView).contains("print(\"hi\")"))

        let foldToggle = gutter.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 23, dy: 16))
        foldToggle.click()

        XCTAssertTrue(waitForEditorText(in: textView, toContain: "{ ...\n"))
        XCTAssertFalse(currentEditorText(in: textView).contains("print(\"hi\")"))

        foldToggle.click()

        XCTAssertTrue(waitForEditorText(in: textView, toContain: "print(\"hi\")"))
    }

    @MainActor
    func testMinimapFixtureClickMovesVisibleRange() throws {
        let app = XCUIApplication()
        app.launchEnvironment["ROSEWOOD_UI_TEST_RESET_SESSION"] = "1"
        app.launchEnvironment["ROSEWOOD_UI_TEST_MINIMAP_FIXTURE"] = "1"
        app.launch()

        let minimap = app.descendants(matching: .any).matching(identifier: "editor-minimap").firstMatch

        XCTAssertTrue(minimap.waitForExistence(timeout: 5))
        let initialRange = minimap.value as? String
        XCTAssertNotNil(initialRange)
        XCTAssertTrue((initialRange ?? "").hasPrefix("1-"))

        minimap.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)).click()

        XCTAssertTrue(waitForElementValueChange(in: minimap, from: initialRange))
        let updatedRange = minimap.value as? String
        XCTAssertNotEqual(updatedRange, initialRange)
    }

    @MainActor
    func testGitFixtureShowsSourceControlSidebarAndDiffPanel() throws {
        let app = XCUIApplication()
        app.launchEnvironment["ROSEWOOD_UI_TEST_RESET_SESSION"] = "1"
        app.launchEnvironment["ROSEWOOD_UI_TEST_GIT_FIXTURE"] = "1"
        app.launch()

        let sidebar = app.descendants(matching: .any).matching(identifier: "source-control-sidebar").firstMatch
        let branch = app.descendants(matching: .any).matching(identifier: "git-branch-label").firstMatch
        let branchText = app.staticTexts["main"].firstMatch
        let summary = app.descendants(matching: .any).matching(identifier: "git-change-summary").firstMatch
        let changesSection = app.descendants(matching: .any).matching(identifier: "git-section-changes").firstMatch
        let changedFile = app.descendants(matching: .any).matching(identifier: "git-change-row-0").firstMatch

        XCTAssertTrue(sidebar.waitForExistence(timeout: 5))
        XCTAssertTrue(branch.waitForExistence(timeout: 5))
        XCTAssertTrue(branchText.exists)
        XCTAssertTrue(summary.exists)
        XCTAssertTrue(changesSection.exists)
        XCTAssertTrue(changedFile.exists)

        changedFile.click()

        let diffWorkspace = app.descendants(matching: .any).matching(identifier: "git-diff-workspace").firstMatch
        let splitView = app.descendants(matching: .any).matching(identifier: "git-diff-split-view").firstMatch
        let beforeColumn = app.descendants(matching: .any).matching(identifier: "git-diff-column-before").firstMatch
        let afterColumn = app.descendants(matching: .any).matching(identifier: "git-diff-column-after").firstMatch
        let stageButton = app.descendants(matching: .any).matching(identifier: "git-diff-stage").firstMatch
        let discardButton = app.descendants(matching: .any).matching(identifier: "git-diff-discard").firstMatch
        let revealButton = app.descendants(matching: .any).matching(identifier: "git-diff-reveal-explorer").firstMatch
        let editorButton = app.descendants(matching: .any).matching(identifier: "git-diff-open-editor").firstMatch
        let hunkLabel = app.descendants(matching: .any).matching(identifier: "git-diff-hunk-label").firstMatch
        XCTAssertTrue(diffWorkspace.waitForExistence(timeout: 5))
        XCTAssertTrue(splitView.waitForExistence(timeout: 5))
        XCTAssertTrue(beforeColumn.exists)
        XCTAssertTrue(afterColumn.exists)
        XCTAssertTrue(stageButton.exists)
        XCTAssertTrue(discardButton.exists)
        XCTAssertTrue(revealButton.exists)
        XCTAssertTrue(editorButton.exists)
        XCTAssertTrue(hunkLabel.exists)

        revealButton.click()

        let trackedRow = app.descendants(matching: .any).matching(identifier: "file-tree-row-Tracked.swift").firstMatch
        XCTAssertTrue(trackedRow.waitForExistence(timeout: 5))

        editorButton.click()
        XCTAssertFalse(diffWorkspace.waitForExistence(timeout: 1))
    }

    @MainActor
    func testGitFixtureExplorerShowsChangedAndIgnoredStates() throws {
        let app = XCUIApplication()
        app.launchEnvironment["ROSEWOOD_UI_TEST_RESET_SESSION"] = "1"
        app.launchEnvironment["ROSEWOOD_UI_TEST_GIT_FIXTURE"] = "1"
        app.launchEnvironment["ROSEWOOD_UI_TEST_GIT_EXPLORER"] = "1"
        app.launch()

        let trackedRow = app.descendants(matching: .any).matching(identifier: "file-tree-row-Tracked.swift").firstMatch
        let ignoredRow = app.descendants(matching: .any).matching(identifier: "file-tree-row-Ignored.log").firstMatch

        XCTAssertTrue(trackedRow.waitForExistence(timeout: 5))
        XCTAssertTrue(ignoredRow.waitForExistence(timeout: 5))
        XCTAssertEqual(trackedRow.value as? String, "Modified")
        XCTAssertEqual(ignoredRow.value as? String, "Ignored")
    }

    @MainActor
    func testExplorerSupportsKeyboardNavigationIntoNestedFiles() throws {
        let app = XCUIApplication()
        app.launchEnvironment["ROSEWOOD_UI_TEST_RESET_SESSION"] = "1"
        app.launchEnvironment["ROSEWOOD_UI_TEST_EXPLORER_FIXTURE"] = "1"
        app.launch()
        activateAndFocus(app)

        let sourcesRow = app.descendants(matching: .any).matching(identifier: "file-tree-row-Sources").firstMatch
        XCTAssertTrue(sourcesRow.waitForExistence(timeout: 5))

        sourcesRow.click()

        let featuresRow = app.descendants(matching: .any).matching(identifier: "file-tree-row-Features").firstMatch
        XCTAssertTrue(featuresRow.waitForExistence(timeout: 2))

        app.typeKey(XCUIKeyboardKey.rightArrow.rawValue, modifierFlags: [])
        app.typeKey(XCUIKeyboardKey.rightArrow.rawValue, modifierFlags: [])

        let alphaRow = app.descendants(matching: .any).matching(identifier: "file-tree-row-Alpha.swift").firstMatch
        XCTAssertTrue(alphaRow.waitForExistence(timeout: 2))

        app.typeKey(XCUIKeyboardKey.rightArrow.rawValue, modifierFlags: [])
        app.typeKey(XCUIKeyboardKey.return.rawValue, modifierFlags: [])

        let outlineSidebar = app.descendants(matching: .any).matching(identifier: "outline-sidebar").firstMatch
        XCTAssertTrue(outlineSidebar.waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Line 1, Col 1"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testOutlineSidebarShowsCurrentFileSymbols() throws {
        let app = XCUIApplication()
        app.launchEnvironment["ROSEWOOD_UI_TEST_RESET_SESSION"] = "1"
        app.launchEnvironment["ROSEWOOD_UI_TEST_NAVIGATION_FIXTURE"] = "1"
        app.launch()
        activateAndFocus(app)

        let outlineSidebar = app.descendants(matching: .any).matching(identifier: "outline-sidebar").firstMatch
        XCTAssertTrue(outlineSidebar.waitForExistence(timeout: 5))

        let typeRow = app.buttons["outline-symbol-row-AlphaSymbol"]
        let helperRow = app.buttons["outline-symbol-row-alphaHelper"]
        XCTAssertTrue(typeRow.waitForExistence(timeout: 2))
        XCTAssertTrue(helperRow.waitForExistence(timeout: 2))
    }

    private func currentEditorText(in textView: XCUIElement) -> String {
        textView.value as? String ?? ""
    }

    private func waitForEditorText(in textView: XCUIElement, toContain expectedSubstring: String, timeout: TimeInterval = 2) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if currentEditorText(in: textView).contains(expectedSubstring) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        } while Date() < deadline

        return currentEditorText(in: textView).contains(expectedSubstring)
    }

    private func waitForElementValueChange(in element: XCUIElement, from oldValue: String?, timeout: TimeInterval = 2) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if (element.value as? String) != oldValue {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        } while Date() < deadline

        return (element.value as? String) != oldValue
    }

    private func activateAndFocus(_ app: XCUIApplication) {
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))

        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5))
        window.click()

        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }
}
