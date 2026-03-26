import SwiftUI

struct DockerSidebarView: View {
    @EnvironmentObject var projectViewModel: ProjectViewModel
    @EnvironmentObject private var configService: ConfigurationService

    private var themeColors: ThemeColors {
        configService.currentThemeColors
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                connectionSection
                tabBar
                tabContent
            }
            .padding(12)
        }
        .background(themeColors.panelBackground)
    }

    private var connectionSection: some View {
        RosewoodSidebarCard {
            HStack(alignment: .center, spacing: 10) {
                ZStack {
                    Circle()
                        .fill(connectionColor.opacity(0.14))
                        .frame(width: 26, height: 26)

                    Image(systemName: connectionIcon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(connectionColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Docker")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(themeColors.foreground)

                    Text(connectionStatusText)
                        .font(.system(size: 11))
                        .foregroundColor(themeColors.mutedText)
                }

                Spacer()

                if projectViewModel.isRefreshingDocker {
                    ProgressView()
                        .scaleEffect(0.6)
                } else {
                    Button {
                        projectViewModel.refreshDockerState()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11))
                            .foregroundColor(themeColors.mutedText)
                    }
                    .buttonStyle(.plain)
                    .help("Refresh")
                }
            }
        }
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(DockerTab.allCases) { tab in
                Button {
                    projectViewModel.selectedDockerTab = tab
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 14))
                        Text(tab.title)
                            .font(.system(size: 10, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        projectViewModel.selectedDockerTab == tab
                            ? themeColors.accent.opacity(0.12)
                            : Color.clear
                    )
                    .foregroundColor(
                        projectViewModel.selectedDockerTab == tab
                            ? themeColors.accent
                            : themeColors.mutedText
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .background(themeColors.elevatedBackground)
        .clipShape(RoundedRectangle(cornerRadius: RosewoodUI.radiusSmall))
    }

    @ViewBuilder
    private var tabContent: some View {
        switch projectViewModel.selectedDockerTab {
        case .containers:
            containersSection
        case .images:
            imagesSection
        case .compose:
            composeSection
        case .volumes:
            volumesSection
        }
    }

    private var containersSection: some View {
        RosewoodSidebarCard {
            sectionTitle("Containers")

            if projectViewModel.dockerContainers.isEmpty {
                emptyState(
                    icon: "shippingbox",
                    message: projectViewModel.isDockerAvailable
                        ? "No containers running"
                        : "Connect to Docker to view containers"
                )
            } else {
                ForEach(projectViewModel.dockerContainers) { container in
                    ContainerRowView(container: container)
                }
            }
        }
    }

    private var imagesSection: some View {
        RosewoodSidebarCard {
            sectionTitle("Images")

            if projectViewModel.dockerImages.isEmpty {
                emptyState(
                    icon: "photo.stack",
                    message: projectViewModel.isDockerAvailable
                        ? "No images found"
                        : "Connect to Docker to view images"
                )
            } else {
                ForEach(projectViewModel.dockerImages) { image in
                    ImageRowView(image: image)
                }
            }
        }
    }

    private var composeSection: some View {
        RosewoodSidebarCard {
            sectionTitle("Compose Projects")

            if projectViewModel.dockerComposeProjects.isEmpty {
                emptyState(
                    icon: "doc.text.fill",
                    message: projectViewModel.isDockerAvailable
                        ? "No compose projects detected"
                        : "Connect to Docker to view projects"
                )
            } else {
                ForEach(projectViewModel.dockerComposeProjects) { project in
                    ComposeProjectRowView(project: project)
                }
            }
        }
    }

    private var volumesSection: some View {
        RosewoodSidebarCard {
            sectionTitle("Volumes")

            if projectViewModel.dockerVolumes.isEmpty {
                emptyState(
                    icon: "externaldrive.fill",
                    message: projectViewModel.isDockerAvailable
                        ? "No volumes found"
                        : "Connect to Docker to view volumes"
                )
            } else {
                ForEach(projectViewModel.dockerVolumes) { volume in
                    VolumeRowView(volume: volume)
                }
            }
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(themeColors.subduedText)
    }

    private func emptyState(icon: String, message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(themeColors.mutedText)
            Text(message)
                .font(.system(size: 12))
                .foregroundColor(themeColors.subduedText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    private var connectionIcon: String {
        switch projectViewModel.dockerConnectionState {
        case .connected:
            return "checkmark.circle.fill"
        case .connecting:
            return "arrow.triangle.2.circlepath"
        case .reconnecting:
            return "arrow.clockwise"
        case .disconnected:
            return "xmark.circle.fill"
        case .notInstalled:
            return "exclamationmark.triangle.fill"
        }
    }

    private var connectionColor: Color {
        switch projectViewModel.dockerConnectionState {
        case .connected:
            return themeColors.success
        case .connecting, .reconnecting:
            return themeColors.accent
        case .disconnected:
            return themeColors.danger
        case .notInstalled:
            return themeColors.warning
        }
    }

    private var connectionStatusText: String {
        switch projectViewModel.dockerConnectionState {
        case .connected:
            let runningCount = projectViewModel.dockerContainers.filter { $0.status == .running }.count
            return "\(runningCount) containers running"
        case .connecting:
            return "Connecting..."
        case .reconnecting(let timeLeft, let attempt):
            return "Reconnecting in \(timeLeft)s (attempt \(attempt))"
        case .disconnected(let error):
            return "Disconnected: \(error)"
        case .notInstalled:
            return "Docker not installed"
        }
    }
}

struct ContainerRowView: View {
    @EnvironmentObject var projectViewModel: ProjectViewModel
    @EnvironmentObject private var configService: ConfigurationService
    let container: DockerContainer

    private var themeColors: ThemeColors {
        configService.currentThemeColors
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(container.displayName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(themeColors.foreground)
                        .lineLimit(1)

                    RosewoodHeaderChip(text: container.status.displayText, tint: statusColor)
                }

                Text(container.image)
                    .font(.system(size: 11))
                    .foregroundColor(themeColors.mutedText)
                    .lineLimit(1)

                if !container.ports.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "network")
                            .font(.system(size: 9))
                            .foregroundColor(themeColors.mutedText)
                        Text(container.ports.map { $0.display }.joined(separator: ", "))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(themeColors.mutedText)
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            containerActionsMenu
        }
        .padding(.vertical, 4)
    }

    private var containerActionsMenu: some View {
        Menu {
            Button {
                if container.status == .running {
                    projectViewModel.stopContainer(container)
                } else {
                    projectViewModel.startContainer(container)
                }
            } label: {
                Label(
                    container.status == .running ? "Stop" : "Start",
                    systemImage: container.status == .running ? "stop.fill" : "play.fill"
                )
            }

            if container.status == .running {
                Button {
                    projectViewModel.restartContainer(container)
                } label: {
                    Label("Restart", systemImage: "arrow.clockwise")
                }
            }

            Button {
                projectViewModel.showContainerLogs(container)
            } label: {
                Label("View Logs", systemImage: "doc.text")
            }

            if container.status == .running {
                Button {
                    projectViewModel.openTerminalInContainer(container)
                } label: {
                    Label("Open Terminal", systemImage: "terminal")
                }
            }

            Divider()

            Button(role: .destructive) {
                projectViewModel.removeContainer(container)
            } label: {
                Label("Remove", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 12))
                .foregroundColor(themeColors.mutedText)
        }
        .buttonStyle(.plain)
    }

    private var statusColor: Color {
        switch container.status {
        case .running:
            return themeColors.success
        case .paused:
            return themeColors.warning
        case .restarting:
            return themeColors.accent
        case .created, .exited:
            return themeColors.mutedText
        case .dead, .removing:
            return themeColors.danger
        }
    }
}

struct ImageRowView: View {
    @EnvironmentObject var projectViewModel: ProjectViewModel
    @EnvironmentObject private var configService: ConfigurationService
    let image: DockerImage

    private var themeColors: ThemeColors {
        configService.currentThemeColors
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "photo")
                .font(.system(size: 12))
                .foregroundColor(themeColors.mutedText)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 4) {
                Text(image.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(themeColors.foreground)
                    .lineLimit(1)

                Text(image.sizeDisplay)
                    .font(.system(size: 11))
                    .foregroundColor(themeColors.mutedText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Menu {
                Button(role: .destructive) {
                    projectViewModel.removeImage(image)
                } label: {
                    Label("Remove", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 12))
                    .foregroundColor(themeColors.mutedText)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
}

struct ComposeProjectRowView: View {
    @EnvironmentObject var projectViewModel: ProjectViewModel
    @EnvironmentObject private var configService: ConfigurationService
    let project: DockerComposeProject

    private var themeColors: ThemeColors {
        configService.currentThemeColors
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "doc.text.fill")
                .font(.system(size: 12))
                .foregroundColor(themeColors.mutedText)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(project.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(themeColors.foreground)
                        .lineLimit(1)

                    Text("\(project.runningCount)/\(project.totalServices)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(themeColors.mutedText)
                }

                Text(project.configFileName)
                    .font(.system(size: 11))
                    .foregroundColor(themeColors.mutedText)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Menu {
                Button {
                    projectViewModel.composeUp(project: project)
                } label: {
                    Label("Start All", systemImage: "play.fill")
                }

                Button {
                    projectViewModel.composeDown(project: project)
                } label: {
                    Label("Stop All", systemImage: "stop.fill")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 12))
                    .foregroundColor(themeColors.mutedText)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
}

struct VolumeRowView: View {
    @EnvironmentObject private var configService: ConfigurationService
    let volume: DockerVolume

    private var themeColors: ThemeColors {
        configService.currentThemeColors
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "externaldrive.fill")
                .font(.system(size: 12))
                .foregroundColor(themeColors.mutedText)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 4) {
                Text(volume.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(themeColors.foreground)
                    .lineLimit(1)

                Text(volume.driver)
                    .font(.system(size: 11))
                    .foregroundColor(themeColors.mutedText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
    }
}