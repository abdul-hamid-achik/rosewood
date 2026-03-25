import SwiftUI

struct CommandPaletteView: View {
    @EnvironmentObject var projectViewModel: ProjectViewModel
    @EnvironmentObject private var configService: ConfigurationService

    let mode: ProjectViewModel.PaletteMode

    @State private var selectedIndex: Int = 0
    @FocusState private var isQueryFieldFocused: Bool

    private var themeColors: ThemeColors {
        configService.currentThemeColors
    }

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

    private var emptyStateText: String {
        switch mode {
        case .commandPalette:
            return projectViewModel.commandPaletteEmptyStateText
        case .quickOpen:
            return projectViewModel.quickOpenEmptyStateText
        }
    }

    var body: some View {
        ZStack {
            themeColors.overlayScrim
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    projectViewModel.closeCommandPalette()
                }

            VStack(spacing: 0) {
                headerView

                ThemedDivider()

                resultsView
            }
            .background(themeColors.elevatedBackground)
            .clipShape(RoundedRectangle(cornerRadius: RosewoodUI.radiusLarge))
            .overlay(
                RoundedRectangle(cornerRadius: RosewoodUI.radiusLarge)
                    .stroke(themeColors.border.opacity(0.8), lineWidth: 1)
            )
            .shadow(color: themeColors.shadowColor, radius: 28, x: 0, y: 16)
            .frame(width: 600)
            .padding(.horizontal, RosewoodUI.spacing8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            selectedIndex = 0
            focusQueryFieldSoon()
        }
        .onExitCommand {
            projectViewModel.closeCommandPalette()
        }
        .onChange(of: queryBinding.wrappedValue) { _, _ in
            selectedIndex = 0
        }
        .onChange(of: mode) { _, _ in
            selectedIndex = 0
            focusQueryFieldSoon()
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

    private var headerView: some View {
        VStack(alignment: .leading, spacing: RosewoodUI.spacing3) {
            HStack(spacing: RosewoodUI.spacing3) {
                Image(systemName: titleIcon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(themeColors.accent)

                TextField(placeholder, text: queryBinding)
                    .focused($isQueryFieldFocused)
                    .id(mode)
                    .textFieldStyle(.plain)
                    .font(RosewoodType.body)
                    .foregroundColor(themeColors.foreground)
                    .accessibilityIdentifier(
                        mode == .commandPalette ? "command-palette-input" : "quick-open-input"
                    )
                    .onSubmit {
                        executeSelectedAction()
                    }
            }
            .padding(.horizontal, RosewoodUI.spacing5)
            .padding(.vertical, RosewoodUI.spacing4)
            .background(themeColors.background)
            .clipShape(RoundedRectangle(cornerRadius: RosewoodUI.radiusMedium))
            .overlay(
                RoundedRectangle(cornerRadius: RosewoodUI.radiusMedium)
                    .stroke(themeColors.border.opacity(0.8), lineWidth: 1)
            )

            if mode == .commandPalette {
                commandPaletteHeaderDetails
            } else if mode == .quickOpen {
                quickOpenHeaderDetails
            }
        }
        .padding(RosewoodUI.spacing5)
        .background(themeColors.panelBackground)
    }

    @ViewBuilder
    private var commandPaletteHeaderDetails: some View {
        if !commandPaletteHelpText.isEmpty {
            Text(commandPaletteHelpText)
                .font(RosewoodType.caption)
                .foregroundColor(themeColors.mutedText)
                .accessibilityIdentifier("command-palette-help-text")
        }

        if !commandPaletteScopeHints.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: RosewoodUI.spacing3) {
                    ForEach(commandPaletteScopeHints) { scope in
                        Button {
                            projectViewModel.applyCommandPaletteScope(scope)
                            focusQueryFieldSoon()
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
            }
            .scrollClipDisabled()
        }
    }

    @ViewBuilder
    private var quickOpenHeaderDetails: some View {
        if let quickOpenHelpText, !quickOpenHelpText.isEmpty {
            Text(quickOpenHelpText)
                .font(RosewoodType.caption)
                .foregroundColor(themeColors.mutedText)
                .accessibilityIdentifier("quick-open-help-text")
        }

        if !quickOpenProblemFilterHints.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: RosewoodUI.spacing3) {
                    ForEach(quickOpenProblemFilterHints) { hint in
                        Button {
                            projectViewModel.applyQuickOpenProblemFilterHint(hint)
                            focusQueryFieldSoon()
                        } label: {
                            QuickOpenProblemFilterChipView(hint: hint)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("quick-open-problem-filter-\(hint.id)")
                    }
                }
            }
            .scrollClipDisabled()
        }
    }

    private var resultsView: some View {
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
                            sectionHeader(title: section.title, count: section.actions.count)
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
                            sectionHeader(title: section.title, count: section.items.count)
                        }
                    }
                }

                if visibleActions.isEmpty && visibleItems.isEmpty {
                    Text(emptyStateText)
                        .font(RosewoodType.subheadline)
                        .foregroundColor(themeColors.mutedText)
                        .padding(RosewoodUI.spacing6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.vertical, RosewoodUI.spacing2)
        }
        .frame(maxHeight: 340)
        .background(themeColors.elevatedBackground)
    }

    private func sectionHeader(title: String, count: Int) -> some View {
        HStack(spacing: RosewoodUI.spacing3) {
            Text(title)
                .font(RosewoodType.captionStrong)
                .foregroundColor(themeColors.mutedText)

            Spacer()

            Text("\(count)")
                .font(RosewoodType.monoMicro)
                .foregroundColor(themeColors.mutedText)
        }
        .padding(.horizontal, RosewoodUI.spacing5)
        .padding(.top, RosewoodUI.spacing4)
        .padding(.bottom, RosewoodUI.spacing2)
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
            let itemIndex = selectedIndex - actionCount
            guard visibleItems.indices.contains(itemIndex) else { return }
            projectViewModel.executeQuickOpenItem(visibleItems[itemIndex])
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

    private func focusQueryFieldSoon() {
        DispatchQueue.main.async {
            isQueryFieldFocused = true
        }
    }
}

struct CommandPaletteItemView: View {
    @EnvironmentObject private var configService: ConfigurationService

    let action: CommandPaletteAction
    let isSelected: Bool

    private var themeColors: ThemeColors {
        configService.currentThemeColors
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: RosewoodUI.spacing3) {
                Text(action.title)
                    .font(RosewoodType.body)
                    .foregroundColor(themeColors.foreground)

                Spacer(minLength: RosewoodUI.spacing3)

                if let badge = action.badge {
                    Text(badge)
                        .font(RosewoodType.micro)
                        .foregroundColor(themeColors.mutedText)
                }

                if !action.shortcut.isEmpty {
                    Text(action.shortcut)
                        .font(RosewoodType.caption)
                        .foregroundColor(themeColors.mutedText)
                }

                Text(action.category)
                    .font(RosewoodType.caption)
                    .foregroundColor(themeColors.mutedText)
            }

            if let detailText = action.detailText {
                Text(detailText)
                    .font(RosewoodType.caption)
                    .foregroundColor(themeColors.mutedText)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, RosewoodUI.spacing5)
        .padding(.vertical, RosewoodUI.spacing3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? themeColors.rowSelection : Color.clear)
    }
}

struct CommandPaletteScopeChipView: View {
    @EnvironmentObject private var configService: ConfigurationService

    let scope: CommandPaletteScope
    let isActive: Bool

    private var themeColors: ThemeColors {
        configService.currentThemeColors
    }

    var body: some View {
        HStack(spacing: RosewoodUI.spacing2) {
            Text(scope.queryToken)
                .font(RosewoodType.monoCaptionStrong)

            Text(scope.title)
                .font(RosewoodType.caption)
        }
        .foregroundColor(isActive ? themeColors.accentStrong : themeColors.subduedText)
        .padding(.horizontal, RosewoodUI.spacing4)
        .padding(.vertical, RosewoodUI.spacing2)
        .background(
            Capsule()
                .fill(isActive ? themeColors.selection : themeColors.inactiveChipBackground)
        )
        .overlay(
            Capsule()
                .stroke(isActive ? themeColors.accent.opacity(0.55) : themeColors.border.opacity(0.55), lineWidth: 1)
        )
    }
}

struct QuickOpenProblemFilterChipView: View {
    @EnvironmentObject private var configService: ConfigurationService

    let hint: QuickOpenProblemFilterHint

    private var themeColors: ThemeColors {
        configService.currentThemeColors
    }

    var body: some View {
        HStack(spacing: RosewoodUI.spacing2) {
            Text(hint.token)
                .font(RosewoodType.monoCaptionStrong)

            Text(hint.title)
                .font(RosewoodType.caption)
        }
        .foregroundColor(hint.isActive ? themeColors.accentStrong : themeColors.subduedText)
        .padding(.horizontal, RosewoodUI.spacing4)
        .padding(.vertical, RosewoodUI.spacing2)
        .background(
            Capsule()
                .fill(hint.isActive ? themeColors.selection : themeColors.inactiveChipBackground)
        )
        .overlay(
            Capsule()
                .stroke(hint.isActive ? themeColors.accent.opacity(0.55) : themeColors.border.opacity(0.55), lineWidth: 1)
        )
    }
}

struct CommandPaletteQuickOpenItemView: View {
    @EnvironmentObject private var configService: ConfigurationService

    let item: QuickOpenItem
    let isSelected: Bool

    private var themeColors: ThemeColors {
        configService.currentThemeColors
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: RosewoodUI.spacing3) {
                Image(systemName: item.iconName)
                    .foregroundColor(isSelected ? themeColors.accentStrong : themeColors.mutedText)

                Text(item.title)
                    .font(RosewoodType.body)
                    .foregroundColor(themeColors.foreground)

                Spacer(minLength: RosewoodUI.spacing3)

                if let badge = item.badge {
                    Text(badge)
                        .font(RosewoodType.micro)
                        .foregroundColor(themeColors.mutedText)
                }
            }

            Text(item.subtitle)
                .font(RosewoodType.caption)
                .foregroundColor(themeColors.mutedText)
                .lineLimit(1)

            if let detailText = item.detailText {
                Text(detailText)
                    .font(RosewoodType.monoCaption)
                    .foregroundColor(themeColors.mutedText)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, RosewoodUI.spacing5)
        .padding(.vertical, RosewoodUI.spacing3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? themeColors.rowSelection : Color.clear)
    }
}
