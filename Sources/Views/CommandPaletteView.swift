import SwiftUI

struct CommandPaletteView: View {
    @EnvironmentObject var projectViewModel: ProjectViewModel
    @State private var selectedIndex: Int = 0

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
                        Image(systemName: "command")
                            .foregroundColor(.secondary)
                        TextField("Type a command or search files...", text: $projectViewModel.commandPaletteQuery)
                            .textFieldStyle(.plain)
                            .font(.system(size: 14))
                            .onSubmit {
                                executeSelectedAction()
                            }
                    }
                    .padding(12)
                    .background(Color(nsColor: .textBackgroundColor))

                    Divider()
                }

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if !projectViewModel.commandPaletteActions.isEmpty {
                            Section {
                                ForEach(Array(projectViewModel.commandPaletteActions.enumerated()), id: \.element.id) { index, action in
                                    CommandPaletteItemView(
                                        action: action,
                                        isSelected: index == selectedIndex
                                    )
                                    .onTapGesture {
                                        action.action()
                                        projectViewModel.closeCommandPalette()
                                    }
                                    .onHover { hovering in
                                        if hovering {
                                            selectedIndex = index
                                        }
                                    }
                                }
                            } header: {
                                Text("Commands")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                            }
                        }

                        if !projectViewModel.filteredFiles.isEmpty && !projectViewModel.commandPaletteQuery.isEmpty {
                            Section {
                                ForEach(Array(projectViewModel.filteredFiles.enumerated()), id: \.element.id) { index, file in
                                    CommandPaletteFileItemView(
                                        file: file,
                                        isSelected: selectedIndex == projectViewModel.commandPaletteActions.count + index
                                    )
                                    .onTapGesture {
                                        projectViewModel.openFile(at: file.path)
                                        projectViewModel.closeCommandPalette()
                                    }
                                }
                            } header: {
                                Text("Files")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                            }
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
        .onChange(of: projectViewModel.commandPaletteQuery) { _, _ in
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
        let totalItems = projectViewModel.commandPaletteActions.count + projectViewModel.filteredFiles.count
        guard totalItems > 0 else { return }

        selectedIndex = (selectedIndex + direction + totalItems) % totalItems
    }

    private func executeSelectedAction() {
        let actionCount = projectViewModel.commandPaletteActions.count

        if selectedIndex < actionCount {
            projectViewModel.commandPaletteActions[selectedIndex].action()
        } else {
            let fileIndex = selectedIndex - actionCount
            guard projectViewModel.filteredFiles.indices.contains(fileIndex) else { return }
            let file = projectViewModel.filteredFiles[fileIndex]
            projectViewModel.openFile(at: file.path)
        }

        projectViewModel.closeCommandPalette()
    }
}

struct CommandPaletteItemView: View {
    let action: CommandPaletteAction
    let isSelected: Bool

    var body: some View {
        HStack {
            Text(action.title)
                .font(.system(size: 13))

            Spacer()

            Text(action.shortcut)
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            Text(action.category)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .padding(.leading, 8)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
    }
}

struct CommandPaletteFileItemView: View {
    let file: FileItem
    let isSelected: Bool

    var body: some View {
        HStack {
            Image(systemName: file.iconName)
                .foregroundColor(.secondary)

            Text(file.name)
                .font(.system(size: 13))

            Spacer()

            Text(file.path.deletingLastPathComponent().lastPathComponent)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
    }
}
