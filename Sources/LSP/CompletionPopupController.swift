import AppKit

/// Manages an autocomplete popup panel anchored to the cursor position in an NSTextView.
final class CompletionPopupController {
    private let panel: NSPanel
    private let tableView: NSTableView
    private let scrollView: NSScrollView
    private let dataSource: CompletionDataSource
    private var themeColors: ThemeColors = .nord
    private var font: NSFont = .monospacedSystemFont(ofSize: 13, weight: .regular)

    private(set) var isVisible = false
    private(set) var items: [CompletionItem] = []
    private(set) var filteredItems: [CompletionItem] = []
    private(set) var selectedIndex = 0

    var onSelect: ((CompletionItem) -> Void)?

    private static let maxVisibleRows = 10
    static let rowHeight: CGFloat = 22
    private static let panelWidth: CGFloat = 280

    init() {
        let initialThemeColors = ThemeColors.nord
        let initialFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

        themeColors = initialThemeColors
        font = initialFont
        dataSource = CompletionDataSource()

        tableView = NSTableView()
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("completion"))
        column.width = Self.panelWidth - 20
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = Self.rowHeight
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.selectionHighlightStyle = .none
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.backgroundColor = initialThemeColors.nsElevatedBackground

        scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = initialThemeColors.nsElevatedBackground

        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.panelWidth, height: Self.rowHeight * CGFloat(Self.maxVisibleRows)),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.hasShadow = true
        panel.backgroundColor = initialThemeColors.nsElevatedBackground
        panel.contentView = scrollView
        panel.isReleasedWhenClosed = false
        panel.appearance = NSAppearance(named: initialThemeColors.isLightAppearance ? .aqua : .darkAqua)

        tableView.dataSource = dataSource
        tableView.delegate = dataSource
        dataSource.controller = self
        applyTheme(initialThemeColors, font: initialFont)
    }

    func applyTheme(_ themeColors: ThemeColors, font: NSFont) {
        self.themeColors = themeColors
        self.font = font
        panel.backgroundColor = themeColors.nsElevatedBackground
        panel.appearance = NSAppearance(named: themeColors.isLightAppearance ? .aqua : .darkAqua)
        scrollView.backgroundColor = themeColors.nsElevatedBackground
        scrollView.wantsLayer = true
        scrollView.layer?.backgroundColor = themeColors.nsElevatedBackground.cgColor
        scrollView.layer?.borderColor = themeColors.nsBorder.cgColor
        scrollView.layer?.borderWidth = 1
        scrollView.layer?.cornerRadius = 10
        tableView.backgroundColor = themeColors.nsElevatedBackground
        dataSource.themeColors = themeColors
        dataSource.font = font
        tableView.reloadData()
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
    var themeColors: ThemeColors = .nord
    var font: NSFont = .monospacedSystemFont(ofSize: 13, weight: .regular)

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
            textField.font = font
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
        cell.textField?.font = font
        cell.textField?.textColor = themeColors.nsForeground
        if let symbolName = item.kind?.symbolName {
            cell.imageView?.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
            cell.imageView?.contentTintColor = themeColors.nsAccent
        } else {
            cell.imageView?.image = nil
        }

        return cell
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let rowView = ThemedCompletionRowView()
        rowView.themeColors = themeColors
        return rowView
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        CompletionPopupController.rowHeight
    }
}

private final class ThemedCompletionRowView: NSTableRowView {
    var themeColors: ThemeColors = .nord

    override func drawBackground(in dirtyRect: NSRect) {
        themeColors.nsElevatedBackground.setFill()
        dirtyRect.fill()
    }

    override func drawSelection(in dirtyRect: NSRect) {
        guard selectionHighlightStyle != .none || isSelected else { return }

        let selectionRect = bounds.insetBy(dx: 4, dy: 1)
        let path = NSBezierPath(roundedRect: selectionRect, xRadius: 7, yRadius: 7)
        themeColors.nsSelection.withAlphaComponent(themeColors.isLightAppearance ? 0.95 : 0.65).setFill()
        path.fill()
    }
}
