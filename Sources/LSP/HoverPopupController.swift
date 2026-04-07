import AppKit

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
        contentController = HoverContentViewController()
        contentController.configure(themeColors: initialThemeColors, font: initialFont)
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

        if isVisible {
            popover.close()
        }

        contentController.updateContent(content)
        popover.show(relativeTo: rect, of: view, preferredEdge: .maxY)
        isVisible = true
    }

    func showEnhancedContent(_ content: ParsedHoverContent, at rect: NSRect, in view: NSView) {
        if isVisible {
            popover.close()
        }

        contentController.updateWithStructuredContent(content)
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
    private let containerView: NSVisualEffectView
    private let scrollView: NSScrollView
    private let textView: NSTextView
    private let headerView: HoverHeaderView
    private var themeColors: ThemeColors = .nord
    private var font: NSFont = .monospacedSystemFont(ofSize: 12, weight: .regular)

    override init(nibName: NSNib.Name? = nil, bundle: Bundle? = nil) {
        containerView = NSVisualEffectView()
        scrollView = NSScrollView()
        textView = NSTextView()
        headerView = HoverHeaderView()
        super.init(nibName: nibName, bundle: bundle)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(themeColors: ThemeColors, font: NSFont) {
        self.themeColors = themeColors
        self.font = font
        loadViewIfNeeded()
    }

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 160))
        container.wantsLayer = true

        containerView.frame = container.bounds
        containerView.autoresizingMask = [.width, .height]
        containerView.blendingMode = .behindWindow
        containerView.material = .popover
        containerView.state = .active

        scrollView.frame = container.bounds
        scrollView.autoresizingMask = [.width, .height]

        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 12, height: 8)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.font = font
        textView.textContainer?.containerSize = NSSize(width: 320, height: CGFloat.greatestFiniteMagnitude)

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        headerView.translatesAutoresizingMaskIntoConstraints = false
        headerView.isHidden = true

        container.addSubview(containerView)
        containerView.addSubview(headerView)
        containerView.addSubview(scrollView)

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 12),
            headerView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 12),
            headerView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),

            scrollView.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -8)
        ])

        view = container
        applyTheme(themeColors: themeColors, font: font)
    }

    func applyTheme(themeColors: ThemeColors, font: NSFont) {
        self.themeColors = themeColors
        self.font = font

        guard isViewLoaded else { return }

        textView.font = font
        textView.textColor = themeColors.nsForeground
        textView.backgroundColor = .clear
        headerView.applyTheme(themeColors: themeColors, font: font)
    }

    func updateContent(_ content: String) {
        headerView.isHidden = true
        textView.string = content

        if let layoutManager = textView.layoutManager, let textContainer = textView.textContainer {
            layoutManager.ensureLayout(for: textContainer)
            let usedRect = layoutManager.usedRect(for: textContainer)
            let contentWidth = min(max(usedRect.width + 24, 180), 480)
            let contentHeight = min(usedRect.height + 24, 320)
            preferredContentSize = NSSize(width: contentWidth, height: contentHeight)
        }
    }

    func updateWithStructuredContent(_ content: ParsedHoverContent) {
        headerView.configure(with: content)
        headerView.isHidden = false

        textView.string = content.value

        if let layoutManager = textView.layoutManager, let textContainer = textView.textContainer {
            layoutManager.ensureLayout(for: textContainer)
            let usedRect = layoutManager.usedRect(for: textContainer)
            let headerHeight = headerView.intrinsicContentSize.height
            let contentWidth = min(max(max(usedRect.width + 24, headerView.intrinsicContentSize.width), 180), 480)
            let contentHeight = min(headerHeight + usedRect.height + 32, 320)
            preferredContentSize = NSSize(width: contentWidth, height: contentHeight)
        }
    }
}

// MARK: - Header View

private final class HoverHeaderView: NSView {
    private let containerStack: NSStackView
    private let iconImageView: NSImageView
    private let kindBadge: PillBadgeView
    private let docLabel: NSTextField
    private var themeColors: ThemeColors = .nord
    private var font: NSFont = .monospacedSystemFont(ofSize: 12, weight: .regular)

    override init(frame frameRect: NSRect) {
        iconImageView = NSImageView()
        kindBadge = PillBadgeView()
        docLabel = NSTextField(labelWithString: "")
        containerStack = NSStackView()
        super.init(frame: frameRect)
        setupViews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        iconImageView.imageScaling = .scaleProportionallyUpOrDown

        kindBadge.translatesAutoresizingMaskIntoConstraints = false

        docLabel.translatesAutoresizingMaskIntoConstraints = false
        docLabel.font = .systemFont(ofSize: 11)
        docLabel.textColor = .secondaryLabelColor
        docLabel.lineBreakMode = .byWordWrapping
        docLabel.maximumNumberOfLines = 2

        let topRow = NSStackView(views: [iconImageView, kindBadge])
        topRow.orientation = .horizontal
        topRow.spacing = 8
        topRow.alignment = .centerY

        containerStack.orientation = .vertical
        containerStack.spacing = 6
        containerStack.alignment = .leading
        containerStack.translatesAutoresizingMaskIntoConstraints = false

        containerStack.addArrangedSubview(topRow)
        containerStack.addArrangedSubview(docLabel)

        addSubview(containerStack)

        NSLayoutConstraint.activate([
            iconImageView.widthAnchor.constraint(equalToConstant: 18),
            iconImageView.heightAnchor.constraint(equalToConstant: 18),

            containerStack.topAnchor.constraint(equalTo: topAnchor),
            containerStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            containerStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            containerStack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    override var intrinsicContentSize: NSSize {
        let width: CGFloat = 320
        return NSSize(width: width, height: containerStack.fittingSize.height)
    }

    func applyTheme(themeColors: ThemeColors, font: NSFont) {
        self.themeColors = themeColors
        self.font = font
        kindBadge.applyTheme(themeColors: themeColors)
        docLabel.textColor = themeColors.nsMutedText
    }

    func configure(with content: ParsedHoverContent) {
        let iconName = iconForKind(content.kind)
        if let image = NSImage(systemSymbolName: iconName, accessibilityDescription: content.kind) {
            iconImageView.image = image
            iconImageView.contentTintColor = themeColors.nsAccent
            iconImageView.isHidden = false
        } else {
            iconImageView.isHidden = true
        }

        if let kind = content.kind {
            kindBadge.configure(kind: kind, themeColors: themeColors)
            kindBadge.isHidden = false
        } else {
            kindBadge.isHidden = true
        }

        if let doc = content.documentation, !doc.isEmpty {
            docLabel.stringValue = doc
            docLabel.isHidden = false
        } else {
            docLabel.isHidden = true
        }
    }

    private func iconForKind(_ kind: String?) -> String {
        guard let kind = kind?.lowercased() else {
            return "text.cursor"
        }
        switch kind {
        case "function", "method":
            return "function"
        case "class":
            return "c.square"
        case "struct":
            return "s.square"
        case "enum":
            return "e.square"
        case "protocol":
            return "p.square"
        case "interface":
            return "i.square"
        case "variable", "var":
            return "variable"
        case "constant", "let":
            return "c.circle"
        case "property", "field":
            return "field"
        case "parameter", "argument":
            return "textformat.abc"
        case "type", "typedef":
            return "t.square"
        case "module", "namespace", "package":
            return "shippingbox"
        case "file":
            return "doc"
        case "folder", "directory":
            return "folder"
        case "keyword":
            return "keyboard"
        case "operator":
            return "plus.forwardslash.minus"
        case "string":
            return "textformat"
        case "number":
            return "number"
        case "boolean":
            return "checkmark.circle"
        case "array":
            return "square.stack.3d.up"
        case "object", "dictionary":
            return "square.stack.3d.down"
        case "alias", "typealias":
            return "arrow.right.arrow.left"
        default:
            return "text.cursor"
        }
    }
}

// MARK: - Pill Badge View

private final class PillBadgeView: NSView {
    private let iconImageView: NSImageView
    private let kindLabel: NSTextField
    private var themeColors: ThemeColors = .nord

    override init(frame frameRect: NSRect) {
        iconImageView = NSImageView()
        kindLabel = NSTextField(labelWithString: "")
        super.init(frame: frameRect)
        setupViews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        wantsLayer = true
        layer?.cornerRadius = 6

        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        iconImageView.imageScaling = .scaleProportionallyUpOrDown

        kindLabel.translatesAutoresizingMaskIntoConstraints = false
        kindLabel.font = .systemFont(ofSize: 10, weight: .medium)
        kindLabel.lineBreakMode = .byTruncatingTail

        addSubview(iconImageView)
        addSubview(kindLabel)

        NSLayoutConstraint.activate([
            iconImageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            iconImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 12),
            iconImageView.heightAnchor.constraint(equalToConstant: 12),

            kindLabel.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: 4),
            kindLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            kindLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            kindLabel.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            kindLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4)
        ])
    }

    override var intrinsicContentSize: NSSize {
        let labelSize = kindLabel.intrinsicContentSize
        return NSSize(width: labelSize.width + 32, height: 24)
    }

    func applyTheme(themeColors: ThemeColors) {
        self.themeColors = themeColors
        layer?.backgroundColor = themeColors.nsAccent.withAlphaComponent(0.15).cgColor
        kindLabel.textColor = themeColors.nsAccent
        iconImageView.contentTintColor = themeColors.nsAccent
    }

    func configure(kind: String, themeColors: ThemeColors) {
        self.themeColors = themeColors
        kindLabel.stringValue = kind.capitalized

        let iconName = iconForKind(kind)
        if let image = NSImage(systemSymbolName: iconName, accessibilityDescription: kind) {
            iconImageView.image = image
            iconImageView.isHidden = false
        } else {
            iconImageView.isHidden = true
        }

        applyTheme(themeColors: themeColors)
    }

    private func iconForKind(_ kind: String?) -> String {
        guard let kind = kind?.lowercased() else {
            return "text.cursor"
        }
        switch kind {
        case "function", "method":
            return "function"
        case "class":
            return "c.square"
        case "struct":
            return "s.square"
        case "enum":
            return "e.square"
        case "protocol":
            return "p.square"
        case "interface":
            return "i.square"
        case "variable", "var":
            return "variable"
        case "constant", "let":
            return "c.circle"
        case "property", "field":
            return "field"
        case "parameter", "argument":
            return "textformat.abc"
        case "type", "typedef":
            return "t.square"
        case "module", "namespace", "package":
            return "shippingbox"
        case "file":
            return "doc"
        case "folder", "directory":
            return "folder"
        case "keyword":
            return "keyboard"
        case "operator":
            return "plus.forwardslash.minus"
        case "string":
            return "textformat"
        case "number":
            return "number"
        case "boolean":
            return "checkmark.circle"
        case "array":
            return "square.stack.3d.up"
        case "object", "dictionary":
            return "square.stack.3d.down"
        case "alias", "typealias":
            return "arrow.right.arrow.left"
        default:
            return "text.cursor"
        }
    }
}
