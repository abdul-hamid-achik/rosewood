import Foundation

extension ProjectViewModel {
    
    // MARK: - Computed Properties
    
    var isDockerAvailable: Bool {
        if case .connected = dockerConnectionState { return true }
        return false
    }
    
    var dockerBadgeCount: String? {
        let runningCount = dockerContainers.filter { $0.status == .running }.count
        return runningCount > 0 ? "\(runningCount)" : nil
    }
    
    // MARK: - Docker Service Reference
    
    private var dockerService: DockerService {
        DockerService.shared
    }
    
    // MARK: - Connection Management
    
    func refreshDockerState() {
        Task {
            isRefreshingDocker = true
            await dockerService.refresh()
            
            await MainActor.run {
                dockerContainers = dockerService.containers
                dockerImages = dockerService.images
                dockerVolumes = dockerService.volumes
                dockerComposeProjects = dockerService.composeProjects
                dockerConnectionState = dockerService.connectionState
            }
            
            isRefreshingDocker = false
        }
    }
    
    // MARK: - Container Actions
    
    func startContainer(_ container: DockerContainer) {
        Task {
            do {
                try await dockerService.startContainer(id: container.id)
                await refreshDockerState()
            } catch {
                await MainActor.run {
                    ui.alert("Start Failed", "Could not start container: \(error.localizedDescription)", .warning)
                }
            }
        }
    }
    
    func stopContainer(_ container: DockerContainer) {
        Task {
            do {
                try await dockerService.stopContainer(id: container.id)
                await refreshDockerState()
            } catch {
                await MainActor.run {
                    ui.alert("Stop Failed", "Could not stop container: \(error.localizedDescription)", .warning)
                }
            }
        }
    }
    
    func restartContainer(_ container: DockerContainer) {
        Task {
            do {
                try await dockerService.restartContainer(id: container.id)
                await refreshDockerState()
            } catch {
                await MainActor.run {
                    ui.alert("Restart Failed", "Could not restart container: \(error.localizedDescription)", .warning)
                }
            }
        }
    }
    
    func removeContainer(_ container: DockerContainer, force: Bool = false) {
        let response = ui.confirm(
            "Remove Container",
            "Are you sure you want to remove \(container.displayName)?\(force ? " Force removal will stop the container first." : "")",
            .warning,
            ["Remove", "Cancel"]
        )
        
        if response == .alertFirstButtonReturn {
            Task {
                do {
                    try await dockerService.removeContainer(id: container.id, force: force)
                    await refreshDockerState()
                } catch {
                    await MainActor.run {
                        ui.alert("Remove Failed", "Could not remove container: \(error.localizedDescription)", .warning)
                    }
                }
            }
        }
    }
    
    // MARK: - Image Actions
    
    func removeImage(_ image: DockerImage, force: Bool = false) {
        let response = ui.confirm(
            "Remove Image",
            "Are you sure you want to remove \(image.displayName)?",
            .warning,
            ["Remove", "Cancel"]
        )
        
        if response == .alertFirstButtonReturn {
            Task {
                do {
                    try await dockerService.removeImage(id: image.id, force: force)
                    await refreshDockerState()
                } catch {
                    await MainActor.run {
                        ui.alert("Remove Failed", "Could not remove image: \(error.localizedDescription)", .warning)
                    }
                }
            }
        }
    }
    
    // MARK: - Compose Actions
    
    func composeUp(project: DockerComposeProject) {
        Task {
            do {
                try await dockerService.composeUp(projectPath: project.configPath)
                await refreshDockerState()
            } catch {
                await MainActor.run {
                    ui.alert("Compose Up Failed", "Could not start compose project: \(error.localizedDescription)", .warning)
                }
            }
        }
    }
    
    func composeDown(project: DockerComposeProject) {
        let response = ui.confirm(
            "Stop Compose Project",
            "Stop all services in \(project.name)?",
            .warning,
            ["Stop", "Cancel"]
        )
        
        if response == .alertFirstButtonReturn {
            Task {
                do {
                    try await dockerService.composeDown(projectPath: project.configPath)
                    await refreshDockerState()
                } catch {
                    await MainActor.run {
                        ui.alert("Compose Down Failed", "Could not stop compose project: \(error.localizedDescription)", .warning)
                    }
                }
            }
        }
    }
    
    // MARK: - Terminal Integration
    
    func openTerminalInContainer(_ container: DockerContainer) {
        let session = TerminalService.shared.createSession(
            type: .dockerExec(containerId: container.id)
        )
        bottomPanel = .terminal
        TerminalService.shared.selectSession(session.id)
    }
    
    // MARK: - Log Viewing
    
    func showContainerLogs(_ container: DockerContainer) {
        selectedContainer = container
        bottomPanel = .dockerLogs
    }
    
    func getLogStream(for containerId: String, tail: Int? = 500) -> AsyncStream<LogLine> {
        DockerService.shared.streamLogs(containerId: containerId, tail: tail)
    }
}

// MARK: - Docker Tab

enum DockerTab: String, CaseIterable, Identifiable {
    case containers, images, compose, volumes
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .containers: return "Containers"
        case .images: return "Images"
        case .compose: return "Compose"
        case .volumes: return "Volumes"
        }
    }
    
    var icon: String {
        switch self {
        case .containers: return "shippingbox"
        case .images: return "photo.stack"
        case .compose: return "doc.text.fill"
        case .volumes: return "externaldrive.fill"
        }
    }
}