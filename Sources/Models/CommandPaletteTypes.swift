import Foundation

// MARK: - Command Palette Types

enum PaletteMode {
    case quickOpen
    case commandPalette
}

struct CommandPaletteAction: Identifiable {
    let id: String
    let title: String
    let shortcut: String?
    let category: String
    let aliases: [String]
    let detailText: String?
    let badge: String?
    let action: () -> Void
}

struct CommandPaletteSection: Identifiable {
    let title: String
    let actions: [CommandPaletteAction]
    
    var id: String { title }
}

struct CommandPaletteScope: Identifiable, Hashable {
    let id: String
    let title: String
    let category: String
    let queryToken: String
    let aliases: [String]
}

struct CommandPaletteQueryContext {
    let scope: CommandPaletteScope?
    let searchText: String
}
