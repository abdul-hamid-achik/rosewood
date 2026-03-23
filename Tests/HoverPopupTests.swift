import AppKit
import Foundation
import Testing
@testable import Rosewood

@MainActor
struct HoverPopupTests {

    // MARK: - Visibility

    @Test
    func initiallyNotVisible() {
        let popup = HoverPopupController()
        #expect(!popup.isVisible)
    }

    @Test
    func showMakesVisible() {
        let popup = HoverPopupController()
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 400))
        // Need a window for popover to attach
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 500), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        popup.show(content: "func hello() -> String", at: NSRect(x: 50, y: 50, width: 10, height: 14), in: view)
        #expect(popup.isVisible)
    }

    @Test
    func dismissMakesInvisible() {
        let popup = HoverPopupController()
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 400))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 500), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        popup.show(content: "some type info", at: NSRect(x: 50, y: 50, width: 10, height: 14), in: view)
        popup.dismiss()
        #expect(!popup.isVisible)
    }

    @Test
    func dismissWhenNotVisibleIsNoOp() {
        let popup = HoverPopupController()
        popup.dismiss() // Should not crash
        #expect(!popup.isVisible)
    }

    @Test
    func showWithEmptyContentStaysHidden() {
        let popup = HoverPopupController()
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 400))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 500), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        popup.show(content: "", at: NSRect(x: 50, y: 50, width: 10, height: 14), in: view)
        #expect(!popup.isVisible)
    }

    @Test
    func showDismissesPreviousThenShowsNew() {
        let popup = HoverPopupController()
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 400))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 500), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        popup.show(content: "first", at: NSRect(x: 50, y: 50, width: 10, height: 14), in: view)
        #expect(popup.isVisible)
        popup.show(content: "second", at: NSRect(x: 100, y: 100, width: 10, height: 14), in: view)
        #expect(popup.isVisible) // Still visible with new content
    }
}
