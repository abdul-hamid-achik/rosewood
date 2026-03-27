import Foundation
import SwiftUI

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
                NotificationManager.shared.show(NotificationItem(
                    type: .success,
                    title: "Container Started",
                    message: "\(container.displayName) is now running",
                    duration: 3.0
                ))
            } catch {
                await MainActor.run {
                    NotificationManager.shared.show(NotificationItem(
                        type: .error,
                        title: "Start Failed",
                        message: "Could not start container: \(error.localizedDescription)",
                        autoDismiss: false
                    ))
                }
            }
        }
    }
    
    func stopContainer(_ container: DockerContainer) {
        Task {
            do {
                try await dockerService.stopContainer(id: container.id)
                await refreshDockerState()
                NotificationManager.shared.show(NotificationItem(
                    type: .success,
                    title: "Container Stopped",
                    message: "\(container.displayName) has been stopped",
                    duration: 3.0
                ))
            } catch {
                await MainActor.run {
                    NotificationManager.shared.show(NotificationItem(
                        type: .error,
                        title: "Stop Failed",
                        message: "Could not stop container: \(error.localizedDescription)",
                        autoDismiss: false
                    ))
                }
            }
        }
    }
    
    func restartContainer(_ container: DockerContainer) {
        Task {
            do {
                try await dockerService.restartContainer(id: container.id)
                await refreshDockerState()
                NotificationManager.shared.show(NotificationItem(
                    type: .success,
                    title: "Container Restarted",
                    message: "\(container.displayName) has been restarted",
                    duration: 3.0
                ))
            } catch {
                await MainActor.run {
                    NotificationManager.shared.show(NotificationItem(
                        type: .error,
                        title: "Restart Failed",
                        message: "Could not restart container: \(error.localizedDescription)",
                        autoDismiss: false
                    ))
                }
            }
        }
    }
    
    func removeContainer(_ container: DockerContainer, force: Bool = false) {
        // Use non-blocking notification instead of modal
        NotificationManager.shared.show(NotificationItem(
            type: .warning,
            title: "Remove Container",
            message: "Are you sure you want to remove \(container.displayName)?\(force ? " This will stop the container first." : "")",
            actions: [
                NotificationAction(title: "Remove", action: { [weak self] in
                    Task {
                        do {
                            try await self?.dockerService.removeContainer(id: container.id, force: force)
                            await self?.refreshDockerState()
                            NotificationManager.shared.show(NotificationItem(
                                type: .success,
                                title: "Container Removed",
                                message: "\(container.displayName) has been removed",
                                duration: 3.0
                            ))
                        } catch {
                            await MainActor.run {
                                NotificationManager.shared.show(NotificationItem(
                                    type: .error,
                                    title: "Remove Failed",
                                    message: "Could not remove container: \(error.localizedDescription)",
                                    autoDismiss: false
                                ))
                            }
                        }
                    }
                }),
                NotificationAction(title: "Cancel", action: { })
            ],
            duration: 10.0,
            autoDismiss: false
        ))
    }
    
    // MARK: - Image Actions
    
    func removeImage(_ image: DockerImage, force: Bool = false) {
        NotificationManager.shared.show(NotificationItem(
            type: .warning,
            title: "Remove Image",
            message: "Are you sure you want to remove \(image.displayName)?",
            actions: [
                NotificationAction(title: "Remove", action: { [weak self] in
                    Task {
                        do {
                            try await self?.dockerService.removeImage(id: image.id, force: force)
                            await self?.refreshDockerState()
                            NotificationManager.shared.show(NotificationItem(
                                type: .success,
                                title: "Image Removed",
                                message: "\(image.displayName) has been removed",
                                duration: 3.0
                            ))
                        } catch {
                            await MainActor.run {
                                NotificationManager.shared.show(NotificationItem(
                                    type: .error,
                                    title: "Remove Failed",
                                    message: "Could not remove image: \(error.localizedDescription)",
                                    autoDismiss: false
                                ))
                            }
                        }
                    }
                }),
                NotificationAction(title: "Cancel", action: { })
            ],
            duration: 10.0,
            autoDismiss: false
        ))
    }
    
    // MARK: - Compose Actions
    
    func composeUp(project: DockerComposeProject) {
        Task {
            do {
                try await dockerService.composeUp(projectPath: project.configPath)
                await refreshDockerState()
                NotificationManager.shared.show(NotificationItem(
                    type: .success,
                    title: "Compose Started",
                    message: "\(project.name) is now running",
                    duration: 3.0
                ))
            } catch {
                await MainActor.run {
                    NotificationManager.shared.show(NotificationItem(
                        type: .error,
                        title: "Compose Up Failed",
                        message: "Could not start compose project: \(error.localizedDescription)",
                        autoDismiss: false
                    ))
                }
            }
        }
    }
    
    func composeDown(project: DockerComposeProject) {
        NotificationManager.shared.show(NotificationItem(
            type: .warning,
            title: "Stop Compose Project",
            message: "Stop all services in \(project.name)?",
            actions: [
                NotificationAction(title: "Stop", action: { [weak self] in
                    Task {
                        do {
                            try await self?.dockerService.composeDown(projectPath: project.configPath)
                            await self?.refreshDockerState()
                            NotificationManager.shared.show(NotificationItem(
                                type: .success,
                                title: "Compose Stopped",
                                message: "\(project.name) has been stopped",
                                duration: 3.0
                            ))
                        } catch {
                            await MainActor.run {
                                NotificationManager.shared.show(NotificationItem(
                                    type: .error,
                                    title: "Compose Down Failed",
                                    message: "Could not stop compose project: \(error.localizedDescription)",
                                    autoDismiss: false
                                ))
                            }
                        }
                    }
                }),
                NotificationAction(title: "Cancel", action: { })
            ],
            duration: 10.0,
            autoDismiss: false
        ))
    }
    
    // MARK: - Terminal Integration
    
    func openTerminalInContainer(_ container: DockerContainer) {
        createTerminalSession(type: .dockerExec(containerId: container.id))
        bottomPanel = .terminal
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
