import AppKit
import Foundation
import Testing
@testable import Rosewood

@MainActor
struct CompletionPopupTests {

    private func makeItem(label: String, kind: CompletionItemKind? = .function, detail: String? = nil, insertText: String? = nil) -> CompletionItem {
        CompletionItem(label: label, kind: kind, detail: detail, documentation: nil, insertText: insertText, textEdit: nil, filterText: nil, sortText: nil)
    }

    private func sampleItems(_ count: Int = 5) -> [CompletionItem] {
        (0..<count).map { i in
            makeItem(label: "item\(i)", detail: "Detail \(i)", insertText: "item\(i)()")
        }
    }

    // MARK: - Visibility

    @Test
    func initiallyNotVisible() {
        let popup = CompletionPopupController()
        #expect(!popup.isVisible)
    }

    @Test
    func showMakesVisible() {
        let popup = CompletionPopupController()
        let window = NSWindow()
        popup.show(items: sampleItems(), at: NSRect(x: 100, y: 100, width: 10, height: 14), in: window)
        #expect(popup.isVisible)
    }

    @Test
    func dismissMakesInvisible() {
        let popup = CompletionPopupController()
        let window = NSWindow()
        popup.show(items: sampleItems(), at: NSRect(x: 100, y: 100, width: 10, height: 14), in: window)
        popup.dismiss()
        #expect(!popup.isVisible)
    }

    @Test
    func dismissWhenNotVisibleIsNoOp() {
        let popup = CompletionPopupController()
        popup.dismiss()
        #expect(!popup.isVisible)
    }

    @Test
    func emptyItemsStaysHidden() {
        let popup = CompletionPopupController()
        let window = NSWindow()
        popup.show(items: [], at: NSRect(x: 100, y: 100, width: 10, height: 14), in: window)
        #expect(!popup.isVisible)
    }

    @Test
    func showWithNilWindowStaysHidden() {
        let popup = CompletionPopupController()
        popup.show(items: sampleItems(), at: NSRect(x: 100, y: 100, width: 10, height: 14), in: nil)
        #expect(!popup.isVisible)
    }

    // MARK: - Selection

    @Test
    func selectedIndexStartsAtZero() {
        let popup = CompletionPopupController()
        let window = NSWindow()
        popup.show(items: sampleItems(), at: NSRect(x: 100, y: 100, width: 10, height: 14), in: window)
        #expect(popup.selectedIndex == 0)
    }

    @Test
    func moveSelectionDown() {
        let popup = CompletionPopupController()
        let window = NSWindow()
        popup.show(items: sampleItems(), at: NSRect(x: 100, y: 100, width: 10, height: 14), in: window)
        popup.moveSelectionDown()
        #expect(popup.selectedIndex == 1)
    }

    @Test
    func moveSelectionUp() {
        let popup = CompletionPopupController()
        let window = NSWindow()
        popup.show(items: sampleItems(), at: NSRect(x: 100, y: 100, width: 10, height: 14), in: window)
        popup.moveSelectionDown()
        popup.moveSelectionDown()
        popup.moveSelectionUp()
        #expect(popup.selectedIndex == 1)
    }

    @Test
    func moveSelectionDownStopsAtEnd() {
        let popup = CompletionPopupController()
        let window = NSWindow()
        let items = sampleItems(3)
        popup.show(items: items, at: NSRect(x: 100, y: 100, width: 10, height: 14), in: window)
        popup.moveSelectionDown()
        popup.moveSelectionDown()
        popup.moveSelectionDown() // Past end
        popup.moveSelectionDown() // Way past end
        #expect(popup.selectedIndex == 2) // Stays at last
    }

    @Test
    func moveSelectionUpAtZeroStays() {
        let popup = CompletionPopupController()
        let window = NSWindow()
        popup.show(items: sampleItems(), at: NSRect(x: 100, y: 100, width: 10, height: 14), in: window)
        popup.moveSelectionUp()
        #expect(popup.selectedIndex == 0)
    }

    // MARK: - Filtering

    @Test
    func filterItems() {
        let popup = CompletionPopupController()
        let window = NSWindow()
        let items = [
            makeItem(label: "stringValue", kind: .property),
            makeItem(label: "string"),
            makeItem(label: "intValue", kind: .property),
        ]
        popup.show(items: items, at: NSRect(x: 100, y: 100, width: 10, height: 14), in: window)
        popup.updateFilter("str")
        #expect(popup.filteredItems.count == 2)
    }

    @Test
    func filterCaseInsensitive() {
        let popup = CompletionPopupController()
        let window = NSWindow()
        let items = [
            makeItem(label: "StringValue", kind: .property),
            makeItem(label: "intValue", kind: .property),
        ]
        popup.show(items: items, at: NSRect(x: 100, y: 100, width: 10, height: 14), in: window)
        popup.updateFilter("string")
        #expect(popup.filteredItems.count == 1)
        #expect(popup.filteredItems.first?.label == "StringValue")
    }

    @Test
    func filterResetsSelection() {
        let popup = CompletionPopupController()
        let window = NSWindow()
        popup.show(items: sampleItems(), at: NSRect(x: 100, y: 100, width: 10, height: 14), in: window)
        popup.moveSelectionDown()
        popup.moveSelectionDown()
        #expect(popup.selectedIndex == 2)
        popup.updateFilter("item")
        #expect(popup.selectedIndex == 0)
    }

    @Test
    func filterToEmptyDismisses() {
        let popup = CompletionPopupController()
        let window = NSWindow()
        popup.show(items: sampleItems(), at: NSRect(x: 100, y: 100, width: 10, height: 14), in: window)
        popup.updateFilter("zzzznonexistent")
        #expect(!popup.isVisible)
    }

    @Test
    func emptyFilterShowsAll() {
        let popup = CompletionPopupController()
        let window = NSWindow()
        let items = sampleItems(3)
        popup.show(items: items, at: NSRect(x: 100, y: 100, width: 10, height: 14), in: window)
        popup.updateFilter("item")
        popup.updateFilter("")
        #expect(popup.filteredItems.count == 3)
    }

    // MARK: - Confirm Selection

    @Test
    func confirmSelectionCallsCallback() {
        let popup = CompletionPopupController()
        let window = NSWindow()
        let items = sampleItems(3)
        var selectedItem: CompletionItem?
        popup.onSelect = { selectedItem = $0 }
        popup.show(items: items, at: NSRect(x: 100, y: 100, width: 10, height: 14), in: window)
        popup.moveSelectionDown()
        popup.confirmSelection()
        #expect(selectedItem?.label == "item1")
        #expect(!popup.isVisible)
    }

    @Test
    func confirmSelectionUsesInsertText() {
        let popup = CompletionPopupController()
        let window = NSWindow()
        let items = [makeItem(label: "myFunc", insertText: "myFunc()")]
        var selectedItem: CompletionItem?
        popup.onSelect = { selectedItem = $0 }
        popup.show(items: items, at: NSRect(x: 100, y: 100, width: 10, height: 14), in: window)
        popup.confirmSelection()
        #expect(selectedItem?.insertText == "myFunc()")
    }

    @Test
    func confirmWithNoItemsIsNoOp() {
        let popup = CompletionPopupController()
        var called = false
        popup.onSelect = { _ in called = true }
        popup.confirmSelection()
        #expect(!called)
    }

    // MARK: - Items State

    @Test
    func showSetsItems() {
        let popup = CompletionPopupController()
        let window = NSWindow()
        let items = sampleItems(3)
        popup.show(items: items, at: NSRect(x: 100, y: 100, width: 10, height: 14), in: window)
        #expect(popup.items.count == 3)
        #expect(popup.filteredItems.count == 3)
    }

    @Test
    func dismissClearsItems() {
        let popup = CompletionPopupController()
        let window = NSWindow()
        popup.show(items: sampleItems(), at: NSRect(x: 100, y: 100, width: 10, height: 14), in: window)
        popup.dismiss()
        #expect(popup.items.isEmpty)
        #expect(popup.filteredItems.isEmpty)
    }

    @Test
    func showReplacesExistingItems() {
        let popup = CompletionPopupController()
        let window = NSWindow()
        popup.show(items: sampleItems(3), at: NSRect(x: 100, y: 100, width: 10, height: 14), in: window)
        let newItems = sampleItems(7)
        popup.show(items: newItems, at: NSRect(x: 100, y: 100, width: 10, height: 14), in: window)
        #expect(popup.items.count == 7)
    }
}
