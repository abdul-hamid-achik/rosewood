import SwiftUI

struct CommandPaletteView: View {
    @EnvironmentObject var projectViewModel: ProjectViewModel
    let mode: ProjectViewModel.PaletteMode
    @State private var selectedIndex: Int = 0

    private var queryBinding: Binding<String> {
        switch mode {
        case .commandPalette:
            Binding(
                get: { projectViewModel.commandPaletteQuery },
                set: { projectViewModel.commandPaletteQuery = $0 }
            )
        case .quickOpen:
            Binding(
                get: { projectViewModel.quickOpenQuery },
                set: { projectViewModel.quickOpenQuery = $0 }
            )
        }
    }

    private var titleIcon: String {
        switch mode {
        case .commandPalette:
            return "command"
        case .quickOpen:
            return "doc.text.magnifyingglass"
        }
    }

    private var placeholder: String {
        switch mode {
        case .commandPalette:
            return "Type a command..."
        case .quickOpen:
            return "Search files, :line, #symbol..."
        }
    }

    private var visibleActions: [CommandPaletteAction] {
        mode == .commandPalette ? projectViewModel.commandPaletteActions : []
    }

    private var visibleCommandSections: [CommandPaletteSection] {
        mode == .commandPalette ? projectViewModel.commandPaletteSections : []
    }

    private var commandPaletteHelpText: String {
        mode == .commandPalette ? projectViewModel.commandPaletteHelpText : ""
    }

    private var commandPaletteScopeHints: [CommandPaletteScope] {
        mode == .commandPalette ? projectViewModel.commandPaletteScopeHints : []
    }

    private var quickOpenHelpText: String? {
        mode == .quickOpen ? projectViewModel.quickOpenHelpText : nil
    }

    private var quickOpenProblemFilterHints: [QuickOpenProblemFilterHint] {
        mode == .quickOpen ? projectViewModel.quickOpenProblemFilterHints : []
    }

    private var visibleSections: [QuickOpenSection] {
        mode == .quickOpen ? projectViewModel.quickOpenSections : []
    }

    private var visibleItems: [QuickOpenItem] {
        mode == .quickOpen ? projectViewModel.quickOpenItems : []
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture {
                    projectViewModel.closeCommandPalette()
                }

            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: titleIcon)
                            .foregroundColor(.secondary)
                        TextField(placeholder, text: queryBinding)
                            .id(mode)
                            .textFieldStyle(.plain)
                            .font(.system(size: 14))
                            .accessibilityIdentifier(
                                mode == .commandPalette ? "command-palette-input" : "quick-open-input"
                            )
                            .onSubmit {
                                executeSelectedAction()
                            }
                    }
                    .padding(12)
                    .background(Color(nsColor: .textBackgroundColor))

                    if mode == .commandPalette {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(commandPaletteHelpText)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 12)
                                .accessibilityIdentifier("command-palette-help-text")

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(commandPaletteScopeHints) { scope in
                                        Button {
                                            projectViewModel.applyCommandPaletteScope(scope)
                                        } label: {
                                            CommandPaletteScopeChipView(
                                                scope: scope,
                                                isActive: projectViewModel.activeCommandPaletteScope?.id == scope.id
                                            )
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityIdentifier("command-palette-scope-\(scope.id)")
                                    }
                                }
                                .padding(.horizontal, 12)
                            }
                        }
                        .padding(.bottom, 8)
                    }

                    if mode == .quickOpen, let quickOpenHelpText {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(quickOpenHelpText)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 12)
                                .accessibilityIdentifier("quick-open-help-text")

                            if !quickOpenProblemFilterHints.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(quickOpenProblemFilterHints) { hint in
                                            Button {
                                                projectViewModel.applyQuickOpenProblemFilterHint(hint)
                                            } label: {
                                                QuickOpenProblemFilterChipView(hint: hint)
                                            }
                                            .buttonStyle(.plain)
                                            .accessibilityIdentifier("quick-open-problem-filter-\(hint.id)")
                                        }
                                    }
                                    .padding(.horizontal, 12)
                                }
                            }
                        }
                        .padding(.bottom, 8)
                    }

                    Divider()
                }

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if !visibleCommandSections.isEmpty {
                            ForEach(visibleCommandSections) { section in
                                Section {
                                    ForEach(Array(section.actions.enumerated()), id: \.element.id) { index, action in
                                        let selectionOffset = commandSelectionOffset(for: section)

                                        Button {
                                            DispatchQueue.main.async {
                                                projectViewModel.executeCommandPaletteAction(action)
                                            }
                                        } label: {
                                            CommandPaletteItemView(
                                                action: action,
                                                isSelected: selectedIndex == selectionOffset + index
                                            )
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityIdentifier("command-palette-action-\(action.id)")
                                        .onHover { hovering in
                                            if hovering {
                                                selectedIndex = selectionOffset + index
                                            }
                                        }
                                    }
                                } header: {
                                    HStack {
                                        Text(section.title)
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundColor(.secondary)

                                        Spacer()

                                        Text("\(section.actions.count)")
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundColor(.secondary.opacity(0.8))
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                }
                            }
                        }

                        if !visibleSections.isEmpty {
                            ForEach(visibleSections) { section in
                                Section {
                                    ForEach(Array(section.items.enumerated()), id: \.element.id) { index, item in
                                        let selectionOffset = quickOpenSelectionOffset(for: section)

                                        Button {
                                            projectViewModel.executeQuickOpenItem(item)
                                            projectViewModel.closeCommandPalette()
                                        } label: {
                                            CommandPaletteQuickOpenItemView(
                                                item: item,
                                                isSelected: selectedIndex == selectionOffset + index
                                            )
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityIdentifier(
                                            quickOpenAccessibilityIdentifier(
                                                for: item,
                                                index: selectionOffset - visibleActions.count + index
                                            )
                                        )
                                        .onHover { hovering in
                                            if hovering {
                                                selectedIndex = selectionOffset + index
                                            }
                                        }
                                    }
                                } header: {
                                    if mode == .quickOpen {
                                        Text(section.title)
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundColor(.secondary)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                    }
                                }
                            }
                        }

                        if visibleActions.isEmpty && visibleItems.isEmpty {
                            Text(mode == .commandPalette ? projectViewModel.commandPaletteEmptyStateText : projectViewModel.quickOpenEmptyStateText)
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .padding(16)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(maxHeight: 300)
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.white.opacity(0.08))
            }
            .shadow(color: .black.opacity(0.35), radius: 24, x: 0, y: 14)
            .frame(width: 560)
            .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            selectedIndex = 0
        }
        .onExitCommand {
            projectViewModel.closeCommandPalette()
        }
        .onChange(of: queryBinding.wrappedValue) { _, _ in
            selectedIndex = 0
        }
        .onKeyPress { event in
            switch event.key {
            case .escape:
                projectViewModel.closeCommandPalette()
                return .handled
            case .upArrow:
                moveSelection(-1)
                return .handled
            case .downArrow:
                moveSelection(1)
                return .handled
            case .return:
                executeSelectedAction()
                return .handled
            default:
                return .ignored
            }
        }
    }

    private func moveSelection(_ direction: Int) {
        let totalItems = visibleActions.count + visibleItems.count
        guard totalItems > 0 else { return }

        selectedIndex = (selectedIndex + direction + totalItems) % totalItems
    }

    private func executeSelectedAction() {
        let actionCount = visibleActions.count

        if selectedIndex < actionCount {
            projectViewModel.executeCommandPaletteAction(visibleActions[selectedIndex])
        } else {
            let fileIndex = selectedIndex - actionCount
            guard visibleItems.indices.contains(fileIndex) else { return }
            let item = visibleItems[fileIndex]
            projectViewModel.executeQuickOpenItem(item)
            projectViewModel.closeCommandPalette()
        }
    }

    private func quickOpenAccessibilityIdentifier(for item: QuickOpenItem, index: Int) -> String {
        switch item.kind {
        case .file:
            return "quick-open-file-\(index)"
        case .lineJump:
            return "quick-open-line-jump-\(index)"
        case .symbol:
            return "quick-open-symbol-\(index)"
        case .problem:
            return "quick-open-problem-\(index)"
        }
    }

    private func quickOpenSelectionOffset(for targetSection: QuickOpenSection) -> Int {
        var offset = visibleActions.count

        for section in visibleSections {
            if section.id == targetSection.id {
                break
            }
            offset += section.items.count
        }

        return offset
    }

    private func commandSelectionOffset(for targetSection: CommandPaletteSection) -> Int {
        var offset = 0

        for section in visibleCommandSections {
            if section.id == targetSection.id {
                break
            }
            offset += section.actions.count
        }

        return offset
    }
}

struct CommandPaletteItemView: View {
    let action: CommandPaletteAction
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(action.title)
                    .font(.system(size: 13))

                Spacer()

                if let badge = action.badge {
                    Text(badge)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                }

                if !action.shortcut.isEmpty {
                    Text(action.shortcut)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Text(action.category)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(.leading, 8)
            }

            if let detailText = action.detailText {
                Text(detailText)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.9))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
    }
}

struct CommandPaletteScopeChipView: View {
    let scope: CommandPaletteScope
    let isActive: Bool

    var body: some View {
        HStack(spacing: 6) {
            Text(scope.queryToken)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))

            Text(scope.title)
                .font(.system(size: 11))
        }
        .foregroundColor(isActive ? .accentColor : .secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(isActive ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.08))
        )
    }
}

struct QuickOpenProblemFilterChipView: View {
    let hint: QuickOpenProblemFilterHint

    var body: some View {
        HStack(spacing: 6) {
            Text(hint.token)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))

            Text(hint.title)
                .font(.system(size: 11))
        }
        .foregroundColor(hint.isActive ? .accentColor : .secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(hint.isActive ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.08))
        )
    }
}

struct CommandPaletteQuickOpenItemView: View {
    let item: QuickOpenItem
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: item.iconName)
                    .foregroundColor(.secondary)

                Text(item.title)
                    .font(.system(size: 13))

                Spacer()

                if let badge = item.badge {
                    Text(badge)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                }
            }

            Text(item.subtitle)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .lineLimit(1)

            if let detailText = item.detailText {
                Text(detailText)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.9))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
    }
}
