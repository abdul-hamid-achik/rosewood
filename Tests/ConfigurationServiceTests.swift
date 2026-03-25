import Foundation
import Testing
@testable import Rosewood

@Suite(.serialized)
@MainActor
struct ConfigurationServiceTests {
    @Test
    func watchesBothUserAndProjectConfigFiles() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let userConfigURL = rootURL.appendingPathComponent("user.toml")
        let projectRoot = rootURL.appendingPathComponent("Project", isDirectory: true)
        let projectConfigURL = projectRoot.appendingPathComponent(".rosewood.toml")

        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        try configuration(fontSize: 14, autoSaveDelay: 0.2, autoSaveEnabled: true).write(
            to: userConfigURL,
            atomically: true,
            encoding: .utf8
        )

        let service = ConfigurationService(userConfigURL: userConfigURL)
        service.load()

        #expect(service.settings.editor.fontSize == 14)
        #expect(service.watchedConfigURLs == Set([userConfigURL]))

        try configuration(fontSize: 18, autoSaveDelay: 0.2, autoSaveEnabled: false).write(
            to: projectConfigURL,
            atomically: true,
            encoding: .utf8
        )
        service.setProjectRoot(projectRoot)

        #expect(service.watchedConfigURLs == Set([userConfigURL, projectConfigURL]))
        #expect(service.settings.editor.fontSize == 18)
        #expect(service.settings.editor.autoSaveEnabled == false)

        try configuration(fontSize: 20, autoSaveDelay: 0.5, autoSaveEnabled: false).write(
            to: projectConfigURL,
            atomically: true,
            encoding: .utf8
        )

        try await waitUntil {
            service.settings.editor.fontSize == 20 && service.settings.editor.autoSaveDelay == 0.5
        }

        #expect(service.settings.editor.fontSize == 20)
        #expect(service.settings.editor.autoSaveDelay == 0.5)
    }

    @Test
    func userConfigChangesPreserveProjectOverridesAfterLiveReload() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let userConfigURL = rootURL.appendingPathComponent("user.toml")
        let projectRoot = rootURL.appendingPathComponent("Project", isDirectory: true)
        let projectConfigURL = projectRoot.appendingPathComponent(".rosewood.toml")

        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        try configuration(fontSize: 14, autoSaveDelay: 0.2, autoSaveEnabled: true).write(
            to: userConfigURL,
            atomically: true,
            encoding: .utf8
        )
        try configuration(fontSize: 18, autoSaveDelay: 0.4, autoSaveEnabled: false).write(
            to: projectConfigURL,
            atomically: true,
            encoding: .utf8
        )

        let service = ConfigurationService(userConfigURL: userConfigURL)
        service.setProjectRoot(projectRoot)

        #expect(service.settings.editor.fontSize == 18)
        #expect(service.settings.editor.autoSaveDelay == 0.4)
        #expect(service.settings.editor.autoSaveEnabled == false)

        try configuration(fontSize: 22, autoSaveDelay: 0.8, autoSaveEnabled: true).write(
            to: userConfigURL,
            atomically: true,
            encoding: .utf8
        )

        try await waitUntil {
            service.settings.editor.fontSize == 18 &&
                service.settings.editor.autoSaveDelay == 0.4 &&
                service.settings.editor.autoSaveEnabled == false
        }

        #expect(service.settings.editor.fontSize == 18)
        #expect(service.settings.editor.autoSaveDelay == 0.4)
        #expect(service.settings.editor.autoSaveEnabled == false)
    }

    @Test
    func deletingProjectConfigFallsBackToUserSettingsAfterLiveReload() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let userConfigURL = rootURL.appendingPathComponent("user.toml")
        let projectRoot = rootURL.appendingPathComponent("Project", isDirectory: true)
        let projectConfigURL = projectRoot.appendingPathComponent(".rosewood.toml")

        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        try configuration(fontSize: 12, autoSaveDelay: 0.1, autoSaveEnabled: true).write(
            to: userConfigURL,
            atomically: true,
            encoding: .utf8
        )
        try configuration(fontSize: 19, autoSaveDelay: 0.7, autoSaveEnabled: false).write(
            to: projectConfigURL,
            atomically: true,
            encoding: .utf8
        )

        let service = ConfigurationService(userConfigURL: userConfigURL)
        service.setProjectRoot(projectRoot)

        #expect(service.settings.editor.fontSize == 19)
        #expect(service.settings.editor.autoSaveDelay == 0.7)
        #expect(service.settings.editor.autoSaveEnabled == false)

        try FileManager.default.removeItem(at: projectConfigURL)

        try await waitUntil {
            service.settings.editor.fontSize == 12 &&
                service.settings.editor.autoSaveDelay == 0.1 &&
                service.settings.editor.autoSaveEnabled == true &&
                service.watchedConfigURLs == Set([userConfigURL])
        }

        #expect(service.settings.editor.fontSize == 12)
        #expect(service.settings.editor.autoSaveDelay == 0.1)
        #expect(service.settings.editor.autoSaveEnabled == true)
        #expect(service.watchedConfigURLs == Set([userConfigURL]))
    }

    @Test
    func createDefaultProjectConfigAndSaveUserSettingsWriteExpectedFiles() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let userConfigURL = rootURL.appendingPathComponent("user.toml")
        let projectRoot = rootURL.appendingPathComponent("Project", isDirectory: true)
        let projectConfigURL = projectRoot.appendingPathComponent(".rosewood.toml")

        defer { try? FileManager.default.removeItem(at: rootURL) }

        let service = ConfigurationService(userConfigURL: userConfigURL)
        service.setProjectRoot(projectRoot)

        #expect(service.hasProjectConfig() == false)

        try service.createDefaultProjectConfig()
        try service.saveUserSettings()

        #expect(service.hasProjectConfig() == true)
        #expect(FileManager.default.fileExists(atPath: userConfigURL.path))
        #expect(FileManager.default.fileExists(atPath: projectConfigURL.path))

        let projectConfig = try String(contentsOf: projectConfigURL, encoding: .utf8)
        let userConfig = try String(contentsOf: userConfigURL, encoding: .utf8)

        #expect(projectConfig.contains("fontSize"))
        #expect(userConfig.contains("theme"))
        #expect(service.font.pointSize == AppSettings.default.editor.fontSize)
    }

    @Test
    func syntaxHighlightThemeFollowsSelectedTheme() {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let userConfigURL = rootURL.appendingPathComponent("user.toml")
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let service = ConfigurationService(userConfigURL: userConfigURL)
        service.load()

        var updated = service.settings
        updated.theme.name = "dracula"
        service.updateSettings(updated)

        #expect(service.currentThemeDefinition.id == "dracula")
        #expect(HighlightService.shared.currentHighlightrThemeName == ThemeDefinition.dracula.highlightrTheme)
    }

    @Test
    func configuredFontUsesRequestedFamilyWhenAvailable() {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let userConfigURL = rootURL.appendingPathComponent("user.toml")
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let service = ConfigurationService(userConfigURL: userConfigURL)
        service.load()

        var updated = service.settings
        updated.editor.fontFamily = "Menlo"
        updated.editor.fontSize = 15
        service.updateSettings(updated)

        #expect(service.font.pointSize == 15)
        #expect(service.font.fontName.localizedCaseInsensitiveContains("Menlo"))
    }
}

private func configuration(fontSize: Double, autoSaveDelay: Double, autoSaveEnabled: Bool) -> String {
    """
    [editor]
    fontSize = \(fontSize)
    fontFamily = "SF Mono"
    tabSize = 4
    showLineNumbers = true
    showMinimap = true
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
