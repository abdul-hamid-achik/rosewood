import AppKit

/// Manages a hover info popover anchored to a character range in an NSTextView.
final class HoverPopupController {
    private let popover: NSPopover
    private let contentController: HoverContentViewController

    private(set) var isVisible = false

    init() {
        contentController = HoverContentViewController()
        popover = NSPopover()
        popover.contentViewController = contentController
        popover.behavior = .transient
        popover.animates = true
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

    init() {
        textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 8, height: 6)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)

        scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        scrollView.frame = container.bounds
        scrollView.autoresizingMask = [.width, .height]
        container.addSubview(scrollView)
        view = container
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
