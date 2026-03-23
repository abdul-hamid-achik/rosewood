import Foundation

struct ThemeDefinition: Identifiable, Equatable {
    let id: String
    let name: String
    let highlightrTheme: String

    static let nord = ThemeDefinition(
        id: "nord",
        name: "Nord",
        highlightrTheme: "nord"
    )

    static let githubLight = ThemeDefinition(
        id: "github-light",
        name: "GitHub Light",
        highlightrTheme: "github"
    )

    static let dracula = ThemeDefinition(
        id: "dracula",
        name: "Dracula",
        highlightrTheme: "dracula"
    )

    static let builtInThemes: [ThemeDefinition] = [
        .nord,
        .githubLight,
        .dracula
    ]
}
