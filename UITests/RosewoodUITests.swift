import XCTest

final class RosewoodUITests: XCTestCase {
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
        XCTAssertTrue(app.buttons["Find"].exists)
        XCTAssertTrue(app.buttons["Replace All"].exists)
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
    func testLaunchDisablesToolbarDebugButtonsWithoutOpenFile() throws {
        let app = XCUIApplication()
        app.launchEnvironment["ROSEWOOD_UI_TEST_RESET_SESSION"] = "1"
        app.launch()

        XCTAssertFalse(app.buttons["toolbar-debug-sidebar"].isEnabled)
        XCTAssertFalse(app.buttons["toolbar-debug-start"].isEnabled)
        XCTAssertFalse(app.buttons["toolbar-debug-stop"].isEnabled)
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
}
