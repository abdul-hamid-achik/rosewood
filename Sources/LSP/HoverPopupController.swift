import AppKit

/// Manages a hover info popover anchored to a character range in an NSTextView.
final class HoverPopupController {
    private let popover: NSPopover
    private let contentController: HoverContentViewController
    private var themeColors: ThemeColors = .nord
    private var font: NSFont = .monospacedSystemFont(ofSize: 12, weight: .regular)

    private(set) var isVisible = false

    init() {
        let initialThemeColors = ThemeColors.nord
        let initialFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

        themeColors = initialThemeColors
        font = initialFont
        contentController = HoverContentViewController(themeColors: initialThemeColors, font: initialFont)
        popover = NSPopover()
        popover.contentViewController = contentController
        popover.behavior = .transient
        popover.animates = true
        popover.appearance = NSAppearance(named: initialThemeColors.isLightAppearance ? .aqua : .darkAqua)
    }

    func applyTheme(_ themeColors: ThemeColors, font: NSFont) {
        self.themeColors = themeColors
        self.font = font
        popover.appearance = NSAppearance(named: themeColors.isLightAppearance ? .aqua : .darkAqua)
        contentController.applyTheme(themeColors: themeColors, font: font)
    }

    func show(content: String, at rect: NSRect, in view: NSView) {
        guard !content.isEmpty else { return }

        // Dismiss previous if showing
        if isVisible {
            popover.close()
        }

        contentController.updateContent(content)
        popover.show(relativeTo: rect, of: view, preferredEdge: .maxY)
        isVisible = true
    }

    func dismiss() {
        guard isVisible else { return }
        popover.close()
        isVisible = false
    }
}

// MARK: - Content View Controller

private final class HoverContentViewController: NSViewController {
    private let textView: NSTextView
    private let scrollView: NSScrollView
    private var themeColors: ThemeColors
    private var font: NSFont

    init(themeColors: ThemeColors, font: NSFont) {
        self.themeColors = themeColors
        self.font = font
        textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = true
        textView.textContainerInset = NSSize(width: 8, height: 6)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.font = font

        scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true

        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        container.wantsLayer = true
        scrollView.frame = container.bounds
        scrollView.autoresizingMask = [.width, .height]
        container.addSubview(scrollView)
        view = container
        applyTheme(themeColors: themeColors, font: font)
    }

    func applyTheme(themeColors: ThemeColors, font: NSFont) {
        self.themeColors = themeColors
        self.font = font

        guard isViewLoaded else { return }

        textView.font = font
        textView.textColor = themeColors.nsForeground
        textView.backgroundColor = themeColors.nsElevatedBackground
        textView.selectedTextAttributes = [
            .backgroundColor: themeColors.nsSelection.withAlphaComponent(0.45),
            .foregroundColor: themeColors.nsForeground
        ]
        scrollView.backgroundColor = themeColors.nsElevatedBackground
        scrollView.wantsLayer = true
        scrollView.layer?.backgroundColor = themeColors.nsElevatedBackground.cgColor
        view.layer?.backgroundColor = themeColors.nsElevatedBackground.cgColor
        view.layer?.cornerRadius = 10
        view.layer?.borderWidth = 1
        view.layer?.borderColor = themeColors.nsBorder.cgColor
    }

    func updateContent(_ content: String) {
        textView.string = content

        // Size the popover to fit content up to a max
        if let layoutManager = textView.layoutManager, let textContainer = textView.textContainer {
            textContainer.containerSize = NSSize(width: 380, height: CGFloat.greatestFiniteMagnitude)
            layoutManager.ensureLayout(for: textContainer)
            let usedRect = layoutManager.usedRect(for: textContainer)
            let width = min(max(usedRect.width + 24, 200), 500)
            let height = min(usedRect.height + 20, 300)
            preferredContentSize = NSSize(width: width, height: height)
        }
    }
}
