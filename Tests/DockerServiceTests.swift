import Foundation
import Testing
import TOMLKit
@testable import Rosewood

struct DockerTypesTests {

    @Test
    func dockerContainerStatusIcons() {
        #expect(DockerContainerStatus.running.icon == "play.circle.fill")
        #expect(DockerContainerStatus.paused.icon == "pause.circle.fill")
        #expect(DockerContainerStatus.exited.icon == "stop.circle")
        #expect(DockerContainerStatus.created.icon == "stop.circle")
        #expect(DockerContainerStatus.dead.icon == "xmark.circle.fill")
        #expect(DockerContainerStatus.restarting.icon == "arrow.triangle.2.circlepath")
    }

    @Test
    func dockerContainerStatusDisplayText() {
        #expect(DockerContainerStatus.running.displayText == "Running")
        #expect(DockerContainerStatus.paused.displayText == "Paused")
        #expect(DockerContainerStatus.exited.displayText == "Exited")
        #expect(DockerContainerStatus.created.displayText == "Created")
        #expect(DockerContainerStatus.dead.displayText == "Dead")
        #expect(DockerContainerStatus.restarting.displayText == "Restarting")
    }

    @Test
    func dockerPortDisplay() {
        let portWithHost = DockerPort(containerPort: 8080, hostPort: 80, protocolType: "tcp")
        #expect(portWithHost.display == "80:8080")

        let portWithoutHost = DockerPort(containerPort: 3000, hostPort: nil, protocolType: "tcp")
        #expect(portWithoutHost.display == "3000")
    }

    @Test
    func dockerContainerDisplayName() {
        let container = DockerContainer(
            id: "abc123def456",
            names: ["/my-container"],
            image: "nginx:latest",
            imageId: "sha256:123",
            status: .running,
            state: "running",
            ports: [],
            created: Date(),
            labels: [:]
        )
        #expect(container.displayName == "my-container")
        #expect(container.shortId == "abc123def456")
    }

    @Test
    func dockerContainerWithoutNames() {
        let container = DockerContainer(
            id: "xyz789",
            names: [],
            image: "alpine",
            imageId: "sha256:456",
            status: .exited,
            state: "exited",
            ports: [],
            created: Date(),
            labels: [:]
        )
        #expect(container.displayName == "xyz789")
    }

    @Test
    func dockerContainerComposeLabels() {
        let container = DockerContainer(
            id: "123",
            names: ["/project_service_1"],
            image: "redis",
            imageId: "sha256:789",
            status: .running,
            state: "running",
            ports: [],
            created: Date(),
            labels: [
                "com.docker.compose.project": "project",
                "com.docker.compose.service": "redis"
            ]
        )
        #expect(container.isComposeService == true)
        #expect(container.composeProject == "project")
        #expect(container.composeService == "redis")
    }

    @Test
    func dockerImageDisplayName() {
        let imageWithTag = DockerImage(
            id: "sha256:abc123",
            repoTags: ["nginx:latest"],
            size: 1024000,
            created: Date(),
            labels: [:]
        )
        #expect(imageWithTag.displayName == "nginx:latest")
        #expect(imageWithTag.sizeDisplay == "1 MB")

        let imageWithoutTag = DockerImage(
            id: "sha256:def456",
            repoTags: ["<none>:<none>"],
            size: 512000,
            created: Date(),
            labels: [:]
        )
        #expect(imageWithoutTag.displayName == "def456")

        let imageWithShortId = DockerImage(
            id: "sha123",
            repoTags: [],
            size: 0,
            created: Date(),
            labels: [:]
        )
        #expect(imageWithShortId.shortId == "sha123")
    }

    @Test
    func dockerVolumeIdentifiable() {
        let volume = DockerVolume(
            name: "my-volume",
            driver: "local",
            mountpoint: "/var/lib/docker/volumes/my-volume",
            scope: "local"
        )
        #expect(volume.id == "my-volume")
    }

    @Test
    func dockerComposeProjectServices() {
        let project = DockerComposeProject(
            id: "/path/to/project",
            name: "myproject",
            configPath: URL(fileURLWithPath: "/path/to/docker-compose.yml"),
            workingDirectory: URL(fileURLWithPath: "/path/to"),
            configFileName: "docker-compose.yml",
            services: [
                DockerComposeService(name: "web", state: .running, ports: []),
                DockerComposeService(name: "db", state: .exited, ports: []),
                DockerComposeService(name: "redis", state: .running, ports: [])
            ]
        )
        #expect(project.runningCount == 2)
        #expect(project.totalServices == 3)
    }

    @Test
    func dockerComposeServiceFromContainer() {
        let container = DockerContainer(
            id: "cont123",
            names: ["/proj_web_1"],
            image: "nginx",
            imageId: "sha256:img",
            status: .running,
            state: "running",
            ports: [DockerPort(containerPort: 80, hostPort: 8080, protocolType: "tcp")],
            created: Date(),
            labels: [
                "com.docker.compose.project": "proj",
                "com.docker.compose.service": "web"
            ]
        )

        let service = DockerComposeService(from: container)
        #expect(service.name == "web")
        #expect(service.state == .running)
        #expect(service.containerId == "cont123")
        #expect(service.ports.count == 1)
    }

    @Test
    func dockerConnectionStateDisplayText() {
        #expect(DockerConnectionState.connected.displayText == "Connected")
        #expect(DockerConnectionState.connecting.displayText == "Connecting...")
        #expect(DockerConnectionState.notInstalled.displayText == "Docker not installed")
        #expect(DockerConnectionState.disconnected(error: "Error").displayText == "Disconnected: Error")
        #expect(DockerConnectionState.reconnecting(timeLeft: 5, attempt: 2).displayText == "Reconnecting in 5s (attempt 2)")
    }

    @Test
    func dockerConnectionStateIsReconnecting() {
        #expect(DockerConnectionState.reconnecting(timeLeft: 5, attempt: 1).isReconnecting == true)
        #expect(DockerConnectionState.connected.isReconnecting == false)
        #expect(DockerConnectionState.disconnected(error: "").isReconnecting == false)
    }

    @Test
    func dockerTabProperties() {
        #expect(DockerTab.containers.title == "Containers")
        #expect(DockerTab.images.title == "Images")
        #expect(DockerTab.compose.title == "Compose")
        #expect(DockerTab.volumes.title == "Volumes")

        #expect(DockerTab.containers.icon == "shippingbox")
        #expect(DockerTab.images.icon == "photo.stack")
        #expect(DockerTab.compose.icon == "doc.text.fill")
        #expect(DockerTab.volumes.icon == "externaldrive.fill")

        #expect(DockerTab.allCases.count == 4)
    }
}

struct TerminalSessionTests {

    @Test
    func terminalSessionTypeLocalTitle() {
        let type = TerminalSessionType.local(shell: "/bin/zsh")
        #expect(type.defaultTitle == "zsh")

        let typeBash = TerminalSessionType.local(shell: "/bin/bash")
        #expect(typeBash.defaultTitle == "bash")
    }

    @Test
    func terminalSessionTypeDockerExecTitle() {
        let type = TerminalSessionType.dockerExec(containerId: "abc123def456", user: nil)
        #expect(type.defaultTitle == "docker: abc123def456")

        let shortId = TerminalSessionType.dockerExec(containerId: "short", user: nil)
        #expect(shortId.defaultTitle == "docker: short")
    }

    @Test
    func terminalSessionTypeComposeExecTitle() {
        let type = TerminalSessionType.dockerComposeExec(
            projectPath: URL(fileURLWithPath: "/project"),
            service: "web",
            user: nil
        )
        #expect(type.defaultTitle == "compose: web")
    }

    @Test
    func terminalSessionTypeIconNames() {
        #expect(TerminalSessionType.local(shell: "/bin/sh").iconName == "terminal")
        #expect(TerminalSessionType.dockerExec(containerId: "id", user: nil).iconName == "container")
        #expect(TerminalSessionType.dockerComposeExec(projectPath: URL(fileURLWithPath: "/"), service: "svc", user: nil).iconName == "doc.text.fill")
    }

    @Test
    func terminalSessionTypeDisplayName() {
        let local = TerminalSessionType.local(shell: "/bin/zsh")
        #expect(local.displayName == "Local (zsh)")

        let dockerExec = TerminalSessionType.dockerExec(containerId: "abcdef123456", user: nil)
        #expect(dockerExec.displayName == "Docker Exec (abcdef123456)")

        let compose = TerminalSessionType.dockerComposeExec(
            projectPath: URL(fileURLWithPath: "/proj"),
            service: "api",
            user: nil
        )
        #expect(compose.displayName == "Compose: api")
    }

    @Test
    func terminalSessionInit() {
        let session = TerminalSession(type: .local(shell: "/bin/bash"))
        #expect(session.title == "bash")
        #expect(session.isActive == true)
        #expect(session.processId == nil)
    }

    @Test
    func terminalSessionWithCustomTitle() {
        let session = TerminalSession(type: .local(shell: "/bin/zsh"), title: "My Terminal")
        #expect(session.title == "My Terminal")
        #expect(session.displayName == "My Terminal")
    }

    @Test
    func terminalSessionEquality() {
        let session1 = TerminalSession(type: .local(shell: "/bin/sh"))
        let session2 = TerminalSession(type: .local(shell: "/bin/sh"))
        
        #expect(session1 != session2)
        #expect(session1 == session1)
    }
}

struct AppSettingsDockerTests {

    @Test
    func dockerDefaultSettings() {
        let settings = AppSettings.Docker()
        
        #expect(settings.socketPath == "")
        #expect(settings.enableDockerIntegration == true)
        #expect(settings.autoDetectComposeFiles == true)
        #expect(settings.terminalFont == "SF Mono")
        #expect(settings.terminalFontSize == 12)
        #expect(settings.terminalShell == "/bin/zsh")
        #expect(settings.logLineLimit == 500)
        #expect(settings.refreshIntervalSeconds == 5)
        #expect(settings.maxReconnectAttempts == 10)
        #expect(settings.composeScanDepth == 1)
    }

    @Test
    func dockerComposeFilePatternsDefaults() {
        let settings = AppSettings.Docker()
        
        #expect(settings.composeFilePatterns.contains("docker-compose.yml"))
        #expect(settings.composeFilePatterns.contains("docker-compose.yaml"))
        #expect(settings.composeFilePatterns.contains("compose.yml"))
        #expect(settings.composeFilePatterns.contains("compose.yaml"))
    }

    @Test
    func dockerResolvedSocketPathCustom() {
        var settings = AppSettings.Docker()
        settings.socketPath = "/custom/path/docker.sock"
        
        #expect(settings.resolvedSocketPath == "/custom/path/docker.sock")
    }

    @Test
    func dockerResolvedSocketPathDefault() {
        let settings = AppSettings.Docker()
        
        // Should default to /var/run/docker.sock when no custom path
        // or home docker path if it exists
        #expect(settings.resolvedSocketPath.contains("docker.sock"))
    }

    @Test
    func dockerSettingsCodable() throws {
        let settings = AppSettings.Docker()
        let encoder = TOMLEncoder()
        let tomlString = try encoder.encode(settings)
        
        #expect(tomlString.contains("socket_path"))
        #expect(tomlString.contains("enable_docker_integration"))
        #expect(tomlString.contains("terminal_shell"))
        
        let decoder = TOMLDecoder()
        let decoded = try decoder.decode(AppSettings.Docker.self, from: tomlString)
        
        #expect(decoded.socketPath == settings.socketPath)
        #expect(decoded.enableDockerIntegration == settings.enableDockerIntegration)
        #expect(decoded.terminalShell == settings.terminalShell)
    }
}