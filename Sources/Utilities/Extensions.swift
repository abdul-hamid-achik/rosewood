import Foundation
import SwiftUI

struct Extensions {
    static func openPanel(canChooseDirectories: Bool = true, canChooseFiles: Bool = true, allowsMultipleSelection: Bool = false) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = canChooseDirectories
        panel.canChooseFiles = canChooseFiles
        panel.allowsMultipleSelection = allowsMultipleSelection
        panel.canCreateDirectories = true

        let response = panel.runModal()
        return response == .OK ? panel.url : nil
    }

    static func savePanel(defaultName: String = "untitled", allowedTypes: [String]? = nil) -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = defaultName
        panel.canCreateDirectories = true

        if let types = allowedTypes {
            panel.allowedContentTypes = types.compactMap { UTType(filenameExtension: $0) }
        }

        let response = panel.runModal()
        return response == .OK ? panel.url : nil
    }

    static func alert(title: String, message: String, style: NSAlert.Style = .warning) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = style
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    static func confirm(
        title: String,
        message: String,
        style: NSAlert.Style = .warning,
        buttons: [String]
    ) -> NSApplication.ModalResponse {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = style
        buttons.forEach { alert.addButton(withTitle: $0) }
        return alert.runModal()
    }
}

import UniformTypeIdentifiers
