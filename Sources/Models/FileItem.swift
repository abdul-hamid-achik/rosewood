import Foundation

struct FileItem: Identifiable, Hashable {
    var id: String {
        path.standardizedFileURL.path
    }

    var name: String
    var path: URL
    var isDirectory: Bool
    var children: [FileItem]
    var isExpanded: Bool

    init(name: String, path: URL, isDirectory: Bool, children: [FileItem] = [], isExpanded: Bool = false) {
        self.name = name
        self.path = path
        self.isDirectory = isDirectory
        self.children = children
        self.isExpanded = isExpanded
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: FileItem, rhs: FileItem) -> Bool {
        lhs.id == rhs.id && lhs.isExpanded == rhs.isExpanded && lhs.name == rhs.name && lhs.children == rhs.children
    }
}

extension FileItem {
    var fileExtension: String {
        (name as NSString).pathExtension.lowercased()
    }

    var isHidden: Bool {
        name.hasPrefix(".")
    }

    var iconName: String {
        if isDirectory {
            return isExpanded ? "folder.fill" : "folder"
        }

        switch name.lowercased() {
        case ".zshrc", ".bashrc", ".zprofile", ".bash_profile", ".zshenv":
            return "terminal"
        case "dockerfile":
            return "shippingbox.fill"
        default:
            break
        }

        switch fileExtension {
        case "swift":
            return "swift"
        case "py":
            return "text.badge.star"
        case "go":
            return "chevron.left.forwardslash.chevron.right"
        case "rb":
            return "diamond"
        case "js", "mjs", "cjs":
            return "square.fill"
        case "ts", "mts", "cts":
            return "square.fill"
        case "jsx", "tsx":
            return "square.fill"
        case "vue":
            return "v.square.fill"
        case "kt", "kts":
            return "k.square.fill"
        case "ex", "exs":
            return "e.square.fill"
        case "sh", "bash", "zsh":
            return "terminal"
        case "md", "markdown":
            return "doc.richtext"
        case "dockerfile":
            return "shippingbox.fill"
        case "yml", "yaml":
            return "doc.text"
        case "json":
            return "curlybraces"
        case "toml":
            return "doc.plaintext"
        default:
            return "doc.text"
        }
    }
}
