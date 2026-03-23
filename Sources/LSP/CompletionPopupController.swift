import AppKit

/// Manages an autocomplete popup panel anchored to the cursor position in an NSTextView.
final class CompletionPopupController {
    private let panel: NSPanel
    private let tableView: NSTableView
    private let scrollView: NSScrollView
    private let dataSource: CompletionDataSource

    private(set) var isVisible = false
    private(set) var items: [CompletionItem] = []
    private(set) var filteredItems: [CompletionItem] = []
    private(set) var selectedIndex = 0

    var onSelect: ((CompletionItem) -> Void)?

    private static let maxVisibleRows = 10
    static let rowHeight: CGFloat = 22
    private static let panelWidth: CGFloat = 280

    init() {
        dataSource = CompletionDataSource()

        tableView = NSTableView()
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("completion"))
        column.width = Self.panelWidth - 20
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = Self.rowHeight
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.selectionHighlightStyle = .regular
        tableView.usesAlternatingRowBackgroundColors = false

        scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.panelWidth, height: Self.rowHeight * CGFloat(Self.maxVisibleRows)),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.hasShadow = true
        panel.backgroundColor = .windowBackgroundColor
        panel.contentView = scrollView
        panel.isReleasedWhenClosed = false

        tableView.dataSource = dataSource
        tableView.delegate = dataSource
        dataSource.controller = self
    }

    func show(items: [CompletionItem], at rect: NSRect, in window: NSWindow?) {
        guard !items.isEmpty, let window else {
            dismiss()
            return
        }

        self.items = items
        self.filteredItems = items
        self.selectedIndex = 0
        dataSource.items = items

        tableView.reloadData()
        if !items.isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            tableView.scrollRowToVisible(0)
        }

        let visibleRows = min(items.count, Self.maxVisibleRows)
        let panelHeight = Self.rowHeight * CGFloat(visibleRows)
        let screenRect = window.convertToScreen(rect)

        // Position below the cursor, flip above if not enough space
        var origin = NSPoint(x: screenRect.minX, y: screenRect.minY - panelHeight)
        if origin.y < (window.screen?.visibleFrame.minY ?? 0) {
            origin.y = screenRect.maxY
        }

        panel.setFrame(NSRect(x: origin.x, y: origin.y, width: Self.panelWidth, height: panelHeight), display: true)
        panel.orderFront(nil)
        isVisible = true
    }

    func dismiss() {
        guard isVisible else { return }
        panel.orderOut(nil)
        isVisible = false
        items = []
        filteredItems = []
        selectedIndex = 0
    }

    func moveSelectionDown() {
        guard !filteredItems.isEmpty else { return }
        selectedIndex = min(selectedIndex + 1, filteredItems.count - 1)
        tableView.selectRowIndexes(IndexSet(integer: selectedIndex), byExtendingSelection: false)
        tableView.scrollRowToVisible(selectedIndex)
    }

    func moveSelectionUp() {
        guard !filteredItems.isEmpty else { return }
        selectedIndex = max(selectedIndex - 1, 0)
        tableView.selectRowIndexes(IndexSet(integer: selectedIndex), byExtendingSelection: false)
        tableView.scrollRowToVisible(selectedIndex)
    }

    func confirmSelection() {
        guard selectedIndex >= 0, selectedIndex < filteredItems.count else { return }
        let item = filteredItems[selectedIndex]
        dismiss()
        onSelect?(item)
    }

    func updateFilter(_ prefix: String) {
        if prefix.isEmpty {
            filteredItems = items
        } else {
            filteredItems = items.filter { $0.label.localizedCaseInsensitiveContains(prefix) }
        }
        selectedIndex = 0
        dataSource.items = filteredItems
        tableView.reloadData()

        if filteredItems.isEmpty {
            dismiss()
        } else if isVisible {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            let visibleRows = min(filteredItems.count, Self.maxVisibleRows)
            let panelHeight = Self.rowHeight * CGFloat(visibleRows)
            var frame = panel.frame
            frame.size.height = panelHeight
            panel.setFrame(frame, display: true)
        }
    }
}

// MARK: - Data Source

private final class CompletionDataSource: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    var items: [CompletionItem] = []
    weak var controller: CompletionPopupController?

    func numberOfRows(in tableView: NSTableView) -> Int {
        items.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < items.count else { return nil }
        let item = items[row]

        let cellIdentifier = NSUserInterfaceItemIdentifier("CompletionCell")
        let cell: NSTableCellView
        if let reused = tableView.makeView(withIdentifier: cellIdentifier, owner: nil) as? NSTableCellView {
            cell = reused
        } else {
            cell = NSTableCellView()
            cell.identifier = cellIdentifier

            let imageView = NSImageView()
            imageView.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(imageView)
            cell.imageView = imageView

            let textField = NSTextField(labelWithString: "")
            textField.translatesAutoresizingMaskIntoConstraints = false
            textField.lineBreakMode = .byTruncatingTail
            textField.font = .systemFont(ofSize: 12)
            cell.addSubview(textField)
            cell.textField = textField

            NSLayoutConstraint.activate([
                imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                imageView.widthAnchor.constraint(equalToConstant: 16),
                imageView.heightAnchor.constraint(equalToConstant: 16),
                textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 4),
                textField.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -4),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
        }

        cell.textField?.stringValue = item.label
        if let symbolName = item.kind?.symbolName {
            cell.imageView?.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
            cell.imageView?.contentTintColor = .secondaryLabelColor
        } else {
            cell.imageView?.image = nil
        }

        return cell
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        CompletionPopupController.rowHeight
    }
}
