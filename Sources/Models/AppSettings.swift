import Foundation

struct AppSettings: Codable, Equatable {
    struct Editor: Codable, Equatable {
        var fontSize: CGFloat = 13
        var fontFamily: String = "SF Mono"
        var tabSize: Int = 4
        var showLineNumbers: Bool = true
        var wordWrap: Bool = false
        var autoSaveDelay: TimeInterval = 2.0
        var autoSaveEnabled: Bool = true
    }

    struct Theme: Codable, Equatable {
        var name: String = "nord"
    }

    var editor: Editor = Editor()
    var theme: Theme = Theme()

    static let `default` = AppSettings()
}
