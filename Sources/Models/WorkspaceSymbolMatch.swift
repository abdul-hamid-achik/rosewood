import Foundation

struct WorkspaceSymbolMatch: Identifiable, Hashable {
    let name: String
    let kind: String
    let fileURL: URL
    let displayPath: String
    let line: Int
    let column: Int
    let lineText: String
    let originalIndex: Int

    var id: String {
        "\(fileURL.standardizedFileURL.path):\(line):\(column):\(name)"
    }

    var kindDisplayName: String {
        switch kind.lowercased() {
        case "func", "function", "def", "fn", "fun":
            return "Function"
        case "class":
            return "Class"
        case "struct":
            return "Struct"
        case "enum":
            return "Enum"
        case "protocol", "interface":
            return "Protocol"
        case "actor":
            return "Actor"
        case "macro":
            return "Macro"
        case "var", "let", "const":
            return "Variable"
        case "typealias", "type":
            return "Type"
        case "extension":
            return "Extension"
        case "object":
            return "Object"
        default:
            return kind.capitalized
        }
    }

    var iconName: String {
        switch kind.lowercased() {
        case "func", "function", "def", "fn", "fun":
            return "function"
        case "class", "actor":
            return "shippingbox"
        case "struct", "protocol", "interface", "enum", "typealias", "type", "object":
            return "cube.box"
        case "var", "let", "const":
            return "character.cursor.ibeam"
        case "extension":
            return "square.stack.3d.up"
        case "macro":
            return "wand.and.stars"
        default:
            return "number"
        }
    }
}
