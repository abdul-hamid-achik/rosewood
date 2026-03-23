import Foundation

enum EditorContextMenuItem: Equatable {
    case cut
    case copy
    case paste
    case selectAll
    case divider
    case goToDefinition
    case findReferences
    case showHoverInfo
    case revealInFinder
    case copyFilePath
    case copyRelativePath

    var title: String? {
        switch self {
        case .cut: return "Cut"
        case .copy: return "Copy"
        case .paste: return "Paste"
        case .selectAll: return "Select All"
        case .divider: return nil
        case .goToDefinition: return "Go to Definition"
        case .findReferences: return "Find References"
        case .showHoverInfo: return "Show Hover Info"
        case .revealInFinder: return "Reveal in Finder"
        case .copyFilePath: return "Copy File Path"
        case .copyRelativePath: return "Copy Relative Path"
        }
    }
}

struct EditorContextMenuState {
    let hasSavedFile: Bool
    let hasLanguageServer: Bool
    let hasResolvableSymbol: Bool
    let hasRelativePath: Bool

    var items: [EditorContextMenuItem] {
        var items: [EditorContextMenuItem] = [.cut, .copy, .paste, .selectAll]

        if hasLanguageServer || hasSavedFile {
            items.append(.divider)
        }

        if hasLanguageServer {
            items.append(.goToDefinition)
            items.append(.findReferences)
            items.append(.showHoverInfo)
        }

        if hasLanguageServer && hasSavedFile {
            items.append(.divider)
        }

        if hasSavedFile {
            items.append(.revealInFinder)
            items.append(.copyFilePath)
            items.append(.copyRelativePath)
        }

        return items
    }

    func isEnabled(_ item: EditorContextMenuItem) -> Bool {
        switch item {
        case .goToDefinition, .findReferences, .showHoverInfo:
            return hasLanguageServer && hasResolvableSymbol
        case .revealInFinder, .copyFilePath:
            return hasSavedFile
        case .copyRelativePath:
            return hasRelativePath
        case .cut, .copy, .paste, .selectAll, .divider:
            return true
        }
    }
}
