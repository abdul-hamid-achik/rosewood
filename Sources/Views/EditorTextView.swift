import AppKit

protocol EditorTextViewMenuDelegate: AnyObject {
    func menu(for textView: EditorTextView, at point: NSPoint) -> NSMenu
}

final class EditorTextView: NSTextView {
    weak var menuDelegate: EditorTextViewMenuDelegate?
    var lastContextMenuPoint: NSPoint?

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        lastContextMenuPoint = point
        return menuDelegate?.menu(for: self, at: point) ?? super.menu(for: event)
    }
}
