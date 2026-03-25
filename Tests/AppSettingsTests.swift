import Foundation
import Testing
import TOMLKit
@testable import Rosewood

struct AppSettingsTests {

    @Test
    func defaultSettingsHaveExpectedValues() {
        let settings = AppSettings()

        #expect(settings.editor.fontSize == 13)
        #expect(settings.editor.fontFamily == "SF Mono")
        #expect(settings.editor.tabSize == 4)
        #expect(settings.editor.showLineNumbers == true)
        #expect(settings.editor.showMinimap == true)
        #expect(settings.editor.wordWrap == false)
        #expect(settings.editor.autoSaveDelay == 2.0)
        #expect(settings.editor.autoSaveEnabled == true)
        #expect(settings.theme.name == "nord")
    }

    @Test
    func settingsAreEncodableAndDecodable() throws {
        let settings = AppSettings()
        let encoder = TOMLEncoder()
        let tomlString = try encoder.encode(settings)
        let decoded = try TOMLDecoder().decode(AppSettings.self, from: tomlString)

        #expect(decoded.editor.fontSize == settings.editor.fontSize)
        #expect(decoded.editor.fontFamily == settings.editor.fontFamily)
        #expect(decoded.editor.tabSize == settings.editor.tabSize)
        #expect(decoded.editor.showMinimap == settings.editor.showMinimap)
        #expect(decoded.editor.autoSaveDelay == settings.editor.autoSaveDelay)
        #expect(decoded.theme.name == settings.theme.name)
    }

    @Test
    func settingsEncodeToTOML() throws {
        let settings = AppSettings()
        let encoder = TOMLEncoder()
        let tomlString = try encoder.encode(settings)

        #expect(tomlString.contains("fontSize"))
        #expect(tomlString.contains("fontFamily"))
        #expect(tomlString.contains("showMinimap"))
        #expect(tomlString.contains("theme"))
        #expect(tomlString.contains("nord"))
    }
}

struct ThemeDefinitionTests {

    @Test
    func nordThemeHasExpectedValues() {
        let nord = ThemeDefinition.nord

        #expect(nord.id == "nord")
        #expect(nord.name == "Nord")
        #expect(nord.highlightrTheme == "nord")
    }

    @Test
    func builtInThemesContainsNord() {
        #expect(ThemeDefinition.builtInThemes.contains { $0.id == "nord" })
        #expect(ThemeDefinition.builtInThemes.contains { $0.id == "github-light" })
        #expect(ThemeDefinition.builtInThemes.contains { $0.id == "dracula" })
    }

    @Test
    func themeDefinitionsAreEquatable() {
        let nord1 = ThemeDefinition.nord
        let nord2 = ThemeDefinition.nord

        #expect(nord1 == nord2)
    }

    @Test
    func additionalThemesHaveExpectedMetadata() {
        #expect(ThemeDefinition.githubLight.highlightrTheme == "github")
        #expect(ThemeDefinition.dracula.highlightrTheme == "dracula")
        #expect(ThemeDefinition.githubLight.name == "GitHub Light Default")
    }
}
