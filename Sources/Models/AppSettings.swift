import Foundation

struct AppSettings: Codable, Equatable {
    struct Editor: Codable, Equatable {
        var fontSize: CGFloat = 13
        var fontFamily: String = "SF Mono"
        var tabSize: Int = 4
        var showLineNumbers: Bool = true
        var showMinimap: Bool = true
        var wordWrap: Bool = false
        var autoSaveDelay: TimeInterval = 2.0
        var autoSaveEnabled: Bool = true

        init() {}

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            fontSize = try container.decodeIfPresent(CGFloat.self, forKey: .fontSize) ?? 13
            fontFamily = try container.decodeIfPresent(String.self, forKey: .fontFamily) ?? "SF Mono"
            tabSize = try container.decodeIfPresent(Int.self, forKey: .tabSize) ?? 4
            showLineNumbers = try container.decodeIfPresent(Bool.self, forKey: .showLineNumbers) ?? true
            showMinimap = try container.decodeIfPresent(Bool.self, forKey: .showMinimap) ?? true
            wordWrap = try container.decodeIfPresent(Bool.self, forKey: .wordWrap) ?? false
            autoSaveDelay = try container.decodeIfPresent(TimeInterval.self, forKey: .autoSaveDelay) ?? 2.0
            autoSaveEnabled = try container.decodeIfPresent(Bool.self, forKey: .autoSaveEnabled) ?? true
        }
    }

    struct Theme: Codable, Equatable {
        var name: String = "nord"

        init() {}

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try container.decodeIfPresent(String.self, forKey: .name) ?? "nord"
        }
    }

    var editor: Editor = Editor()
    var theme: Theme = Theme()

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        editor = try container.decodeIfPresent(Editor.self, forKey: .editor) ?? Editor()
        theme = try container.decodeIfPresent(Theme.self, forKey: .theme) ?? Theme()
    }

    static let `default` = AppSettings()
}
