import Foundation
import DockerSwift
import Combine

@MainActor
protocol DockerServiceProtocol: AnyObject {
    var connectionState: DockerConnectionState { get }
    var containers: [DockerContainer] { get }
    var images: [DockerImage] { get }
    var volumes: [DockerVolume] { get }
    var composeProjects: [DockerComposeProject] { get }
    var isRefreshing: Bool { get }
    
    func connect() async
    func disconnect()
    func refresh() async
    func startContainer(id: String) async throws
    func stopContainer(id: String, timeout: Int?) async throws
    func restartContainer(id: String, timeout: Int?) async throws
    func removeContainer(id: String, force: Bool) async throws
    func removeImage(id: String, force: Bool) async throws
    func composeUp(projectPath: URL) async throws
    func composeDown(projectPath: URL) async throws
    func streamLogs(containerId: String, tail: Int?) -> AsyncStream<LogLine>
}

@MainActor
final class DockerService: DockerServiceProtocol, ObservableObject {
    static let shared = DockerService()
    
    @Published private(set) var connectionState: DockerConnectionState = .connecting
    @Published private(set) var containers: [DockerContainer] = []
    @Published private(set) var images: [DockerImage] = []
    @Published private(set) var volumes: [DockerVolume] = []
    @Published private(set) var composeProjects: [DockerComposeProject] = []
    @Published private(set) var isRefreshing: Bool = false
    
    private var dockerClient: DockerClient?
    private let cli = DockerCLI()
    private var refreshTask: Task<Void, Never>?
    private var reconnectAttempts: Int = 0
    private var reconnectTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    private let configService: ConfigurationService
    private var lastDockerSettings: AppSettings.Docker

    private init() {
        configService = ConfigurationService.shared
        lastDockerSettings = configService.settings.docker

        configService.$settings
            .map(\.docker)
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] settings in
                Task { @MainActor [weak self] in
                    self?.handleSettingsChange(settings)
                }
            }
            .store(in: &cancellables)

        if lastDockerSettings.enableDockerIntegration {
            Task { await connect() }
        } else {
            connectionState = .disconnected(error: "Docker integration disabled")
        }
    }
    
    var isAvailable: Bool {
        if case .connected = connectionState { return true }
        return false
    }
    
    // MARK: - Connection Management
    
    func connect() async {
        guard configService.settings.docker.enableDockerIntegration else {
            disconnect(reason: "Docker integration disabled", clearState: true)
            return
        }

        reconnectTimer?.invalidate()
        reconnectTimer = nil
        connectionState = .connecting
        
        let socketPath = configService.settings.docker.resolvedSocketPath
        
        do {
            guard let daemonURL = URL(httpURLWithSocketPath: socketPath) else {
                throw DockerError.notConnected
            }
            dockerClient = DockerClient(daemonURL: daemonURL)
            _ = try await dockerClient?.version()
            connectionState = .connected
            reconnectAttempts = 0
            startAutoRefresh()
            
            await MainActor.run {
                NotificationManager.shared.show(NotificationItem(
                    type: .success,
                    title: "Docker Connected",
                    message: "Successfully connected to Docker daemon",
                    duration: 2.0
                ))
            }
        } catch {
            handleConnectionError(error)
        }
    }
    
    private func handleConnectionError(_ error: Error) {
        let errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        
        if errorMessage.contains("ENOENT") || errorMessage.contains("No such file or directory") || errorMessage.contains("Connection refused") {
            connectionState = .notInstalled
            
            Task { @MainActor in
                NotificationManager.shared.show(NotificationItem(
                    type: .error,
                    title: "Docker Not Found",
                    message: "Install Docker Desktop or configure socket path in Settings",
                    actions: [
                        NotificationAction(title: "Settings", action: {
                            AppCommandDispatcher.shared.send(.settings)
                        })
                    ],
                    autoDismiss: false
                ))
            }
        } else {
            connectionState = .disconnected(error: errorMessage)
            scheduleReconnect()
        }
    }
    
    private func scheduleReconnect() {
        let settings = configService.settings.docker
        let maxAttempts = settings.maxReconnectAttempts
        let baseDelay = settings.refreshIntervalSeconds

        reconnectTimer?.invalidate()
        reconnectTimer = nil
        
        guard settings.enableDockerIntegration, reconnectAttempts < maxAttempts else { return }
        
        reconnectAttempts += 1
        let delay = min(baseDelay * Int(pow(2.0, Double(reconnectAttempts - 1))), 30)
        
        connectionState = .reconnecting(timeLeft: delay, attempt: reconnectAttempts)
        
        var timeLeft = delay
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            Task { @MainActor [weak self] in
                guard let self else { return }
                
                timeLeft -= 1
                if timeLeft <= 0 {
                    timer.invalidate()
                    await self.connect()
                } else {
                    self.connectionState = .reconnecting(timeLeft: timeLeft, attempt: self.reconnectAttempts)
                }
            }
        }
    }
    
    func disconnect() {
        disconnect(reason: "Disconnected")
    }

    private func disconnect(reason: String, clearState: Bool = false) {
        refreshTask?.cancel()
        refreshTask = nil
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        dockerClient = nil
        if clearState {
            containers = []
            images = []
            volumes = []
            composeProjects = []
        }
        connectionState = .disconnected(error: reason)
    }
    
    // MARK: - Auto Refresh
    
    private func startAutoRefresh() {
        let interval = configService.settings.docker.refreshIntervalSeconds

        refreshTask?.cancel()
        refreshTask = nil
        
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000)
                await self?.refresh()
            }
        }
    }
    
    // MARK: - Data Refresh
    
    func refresh() async {
        guard case .connected = connectionState, let client = dockerClient else { return }
        
        isRefreshing = true
        defer { isRefreshing = false }
        
        do {
            async let containersTask = refreshContainers(client)
            async let imagesTask = refreshImages(client)
            async let volumesTask = refreshVolumes(client)
            let newContainers = try await containersTask
            async let composeTask = refreshComposeProjects(containers: newContainers)
            let (newImages, newVolumes, newProjects) = try await (imagesTask, volumesTask, composeTask)
            
            await MainActor.run {
                self.containers = newContainers
                self.images = newImages
                self.volumes = newVolumes
                self.composeProjects = newProjects
            }
        } catch {
            handleConnectionError(error)
        }
    }

    private func handleSettingsChange(_ settings: AppSettings.Docker) {
        let previousSettings = lastDockerSettings
        lastDockerSettings = settings

        guard settings.enableDockerIntegration else {
            disconnect(reason: "Docker integration disabled", clearState: true)
            return
        }

        if !previousSettings.enableDockerIntegration {
            Task { await connect() }
            return
        }

        if previousSettings.resolvedSocketPath != settings.resolvedSocketPath {
            Task { await connect() }
            return
        }

        if previousSettings.refreshIntervalSeconds != settings.refreshIntervalSeconds,
           case .connected = connectionState {
            startAutoRefresh()
        }
    }
    
    // MARK: - Container Operations
    
    func startContainer(id: String) async throws {
        guard let client = dockerClient else { throw DockerError.notConnected }
        try await client.containers.start(id)
        await refresh()
    }
    
    func stopContainer(id: String, timeout: Int? = nil) async throws {
        guard let client = dockerClient else { throw DockerError.notConnected }
        let timeoutValue = timeout.map { UInt($0) }
        try await client.containers.stop(id, timeout: timeoutValue)
        await refresh()
    }
    
    func restartContainer(id: String, timeout: Int? = nil) async throws {
        guard let client = dockerClient else { throw DockerError.notConnected }
        let timeoutValue = timeout.map { UInt($0) }
        try await client.containers.stop(id, timeout: timeoutValue)
        try await client.containers.start(id)
        await refresh()
    }
    
    func removeContainer(id: String, force: Bool = false) async throws {
        guard let client = dockerClient else { throw DockerError.notConnected }
        try await client.containers.remove(id, force: force, removeAnonymousVolumes: false)
        await refresh()
    }
    
    // MARK: - Image Operations
    
    func removeImage(id: String, force: Bool = false) async throws {
        guard let client = dockerClient else { throw DockerError.notConnected }
        try await client.images.remove(id, force: force)
        await refresh()
    }
    
    // MARK: - Compose Operations (via CLI)
    
    func composeUp(projectPath: URL) async throws {
        try await cli.composeUp(projectPath: projectPath)
        await refresh()
    }
    
    func composeDown(projectPath: URL) async throws {
        try await cli.composeDown(projectPath: projectPath)
        await refresh()
    }
    
    // MARK: - Log Streaming
    
    func streamLogs(containerId: String, tail: Int? = 500) -> AsyncStream<LogLine> {
        AsyncStream { continuation in
            Task {
                do {
                    let stream = try await cli.streamLogs(containerId: containerId, tail: tail)
                    for await line in stream {
                        continuation.yield(line)
                    }
                } catch {
                    continuation.finish()
                }
            }
        }
    }
    
    // MARK: - Private Helpers
    
    private func refreshContainers(_ client: DockerClient) async throws -> [DockerContainer] {
        let result = try await client.containers.list(all: true)
        return result.map { container in
            DockerContainer(
                id: container.id,
                names: container.names,
                image: container.image,
                imageId: container.imageId,
                status: mapContainerStatus(container.state.rawValue),
                state: container.state.rawValue,
                ports: container.ports.map { port in
                    DockerPort(
                        containerPort: Int(port.privatePort),
                        hostPort: port.publicPort.map { Int($0) },
                        protocolType: port.type.rawValue
                    )
                },
                created: container.createdAt,
                labels: container.labels
            )
        }
    }
    
    private func mapContainerStatus(_ state: String?) -> DockerContainerStatus {
        guard let state = state else { return .exited }
        switch state.lowercased() {
        case "running": return .running
        case "paused": return .paused
        case "restarting": return .restarting
        case "created": return .created
        case "exited", "dead": return .exited
        default: return .exited
        }
    }
    
    private func refreshImages(_ client: DockerClient) async throws -> [DockerImage] {
        let result = try await client.images.list(all: true)
        return result.map { image in
            DockerImage(
                id: image.id,
                repoTags: image.repoTags ?? [],
                size: Int64(image.size),
                created: image.created,
                labels: image.labels
            )
        }
    }
    
    private func refreshVolumes(_ client: DockerClient) async throws -> [DockerVolume] {
        let result = try await client.volumes.list()
        return result.map { volume in
            DockerVolume(
                name: volume.name,
                driver: volume.driver,
                mountpoint: volume.mountPoint,
                scope: volume.scope.rawValue
            )
        }
    }
    
    private func refreshComposeProjects(containers: [DockerContainer]) async -> [DockerComposeProject] {
        guard configService.settings.docker.autoDetectComposeFiles else { return [] }
        
        let projectRoot = configService.projectConfigURL?.deletingLastPathComponent()
        let patterns = configService.settings.docker.composeFilePatterns
        return await cli.detectComposeProjects(
            projectRoot: projectRoot,
            scanDepth: configService.settings.docker.composeScanDepth,
            existingContainers: containers,
            composePatterns: patterns
        )
    }
}

enum DockerError: LocalizedError {
    case notConnected
    case containerNotFound(id: String)
    case imageNotFound(id: String)
    case composeFileNotFound(path: String)
    case invalidSocketPath(path: String)
    
    var errorDescription: String? {
        switch self {
        case .notConnected: return "Docker is not connected"
        case .containerNotFound(let id): return "Container not found: \(id)"
        case .imageNotFound(let id): return "Image not found: \(id)"
        case .composeFileNotFound(let path): return "Compose file not found: \(path)"
        case .invalidSocketPath(let path): return "Invalid Docker socket path: \(path)"
        }
    }
}
