import Foundation

actor DockerCLI {
    private let fileManager = FileManager.default
    
    // MARK: - Compose Operations
    
    func composeUp(projectPath: URL) async throws {
        let process = try createDockerProcess()
        process.arguments = [
            "compose",
            "-f", projectPath.path,
            "up", "-d"
        ]
        try await runProcess(process)
    }
    
    func composeDown(projectPath: URL) async throws {
        let process = try createDockerProcess()
        process.arguments = [
            "compose",
            "-f", projectPath.path,
            "down"
        ]
        try await runProcess(process)
    }
    
    // MARK: - Log Streaming
    
    func streamLogs(containerId: String, tail: Int?) async throws -> AsyncStream<LogLine> {
        let dockerPath = try findDockerPath()

        return AsyncStream { continuation in
            let process = Process()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            let stdoutBuffer = LogStreamBuffer(stream: .stdout)
            let stderrBuffer = LogStreamBuffer(stream: .stderr)

            process.executableURL = URL(fileURLWithPath: dockerPath)
            process.arguments = [
                "logs",
                "-f",
                "--tail", "\(tail ?? 500)",
                containerId
            ]
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                stdoutBuffer.append(data, into: continuation)
            }

            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                stderrBuffer.append(data, into: continuation)
            }

            process.terminationHandler = { _ in
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                stdoutBuffer.flush(into: continuation)
                stderrBuffer.flush(into: continuation)
                continuation.finish()
            }

            continuation.onTermination = { _ in
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                if process.isRunning {
                    process.terminate()
                }
            }

            do {
                try process.run()
            } catch {
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                continuation.finish()
            }
        }
    }
    
    // MARK: - Compose Detection
    
    func detectComposeProjects(
        projectRoot: URL?,
        scanDepth: Int,
        existingContainers: [DockerContainer],
        composePatterns: [String] = ["docker-compose.yml", "docker-compose.yaml", "compose.yml", "compose.yaml"]
    ) async -> [DockerComposeProject] {
        var projects: [DockerComposeProject] = []
        let patterns = composePatterns
        
        guard let root = projectRoot else { return projects }
        
        // Scan root directory
        projects.append(contentsOf: await scanForComposeFiles(
            in: root,
            patterns: patterns,
            containers: existingContainers
        ))
        
        // Scan first-level subdirectories
        if scanDepth >= 1 {
            let commonPaths = [
                root.appendingPathComponent("docker"),
                root.appendingPathComponent("infra"),
                root.appendingPathComponent("services"),
                root.appendingPathComponent("dev")
            ]
            
            for path in commonPaths where fileManager.fileExists(atPath: path.path) {
                projects.append(contentsOf: await scanForComposeFiles(
                    in: path,
                    patterns: patterns,
                    containers: existingContainers
                ))
            }
            
            // Also scan for directories containing docker-compose files
            if let contents = try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey]) {
                for item in contents {
                    if let isDir = try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory, isDir {
                        projects.append(contentsOf: await scanForComposeFiles(
                            in: item,
                            patterns: patterns,
                            containers: existingContainers
                        ))
                    }
                }
            }
        }
        
        // Deduplicate by configPath
        var seen = Set<URL>()
        return projects.filter { project in
            seen.insert(project.configPath).inserted
        }
    }
    
    // MARK: - Private Helpers
    
    private func scanForComposeFiles(
        in directory: URL,
        patterns: [String],
        containers: [DockerContainer]
    ) async -> [DockerComposeProject] {
        var projects: [DockerComposeProject] = []
        
        for pattern in patterns {
            let composePath = directory.appendingPathComponent(pattern)
            if fileManager.fileExists(atPath: composePath.path) {
                let project = await parseComposeProject(
                    configPath: composePath,
                    containers: containers
                )
                projects.append(project)
            }
        }
        
        return projects
    }
    
    private func parseComposeProject(
        configPath: URL,
        containers: [DockerContainer]
    ) async -> DockerComposeProject {
        let workingDir = configPath.deletingLastPathComponent()
        let configName = configPath.lastPathComponent
        let projectName = workingDir.lastPathComponent
        
        // Match containers to compose services
        let projectContainers = containers.filter { container in
            container.labels["com.docker.compose.project.config"] == configName ||
            container.labels["com.docker.compose.project"] == projectName
        }
        
        let services: [DockerComposeService]
        if projectContainers.isEmpty {
            // No running containers - try to parse compose file for service names
            services = await parseComposeServices(from: configPath)
        } else {
            services = projectContainers.map { DockerComposeService(from: $0) }
        }
        
        return DockerComposeProject(
            id: configPath.path,
            name: projectName,
            configPath: configPath,
            workingDirectory: workingDir,
            configFileName: configName,
            services: services
        )
    }
    
    private func parseComposeServices(from configPath: URL) async -> [DockerComposeService] {
        guard let contents = try? String(contentsOf: configPath, encoding: .utf8) else {
            return []
        }
        
        var services: [DockerComposeService] = []
        var inServicesSection = false
        
        for line in contents.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            if trimmed == "services:" {
                inServicesSection = true
                continue
            }
            
            if inServicesSection && trimmed.isEmpty {
                break
            }
            
            if inServicesSection && trimmed.hasSuffix(":") && !trimmed.hasPrefix("#") && !trimmed.hasPrefix("-") {
                let serviceName = String(trimmed.dropLast()).trimmingCharacters(in: .whitespaces)
                if !serviceName.isEmpty && !serviceName.contains("volume") && !serviceName.contains("network") {
                    services.append(DockerComposeService(name: serviceName))
                }
            }
        }
        
        return services
    }
    
    private func createDockerProcess() throws -> Process {
        let process = Process()
        let dockerPath = try findDockerPath()
        process.executableURL = URL(fileURLWithPath: dockerPath)
        return process
    }
    
    private func findDockerPath() throws -> String {
        let dockerPaths = [
            "/usr/local/bin/docker",
            "/usr/bin/docker",
            "/opt/homebrew/bin/docker"
        ]
        
        for path in dockerPaths {
            if fileManager.fileExists(atPath: path) {
                return path
            }
        }
        
        // Try PATH
        let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for dir in path.split(separator: ":") {
            let dockerPath = URL(fileURLWithPath: String(dir)).appendingPathComponent("docker").path
            if fileManager.fileExists(atPath: dockerPath) {
                return dockerPath
            }
        }
        
        throw DockerError.notConnected
    }
    
    private func runProcess(_ process: Process) async throws {
        try await withCheckedThrowingContinuation { continuation in
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            
            process.terminationHandler = { proc in
                if proc.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: NSError(
                        domain: "DockerCLI",
                        code: Int(proc.terminationStatus),
                        userInfo: [NSLocalizedDescriptionKey: "Docker command failed with exit code \(proc.terminationStatus)"]
                    ))
                }
            }
            
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

private final class LogStreamBuffer {
    private let stream: LogStream
    private var pending = Data()

    init(stream: LogStream) {
        self.stream = stream
    }

    func append(_ data: Data, into continuation: AsyncStream<LogLine>.Continuation) {
        pending.append(data)

        while let newlineIndex = pending.firstIndex(of: 0x0A) {
            let lineData = pending.prefix(upTo: newlineIndex)
            pending.removeSubrange(...newlineIndex)

            guard let text = String(data: lineData, encoding: .utf8) else { continue }
            continuation.yield(LogLine(text: text, stream: stream))
        }
    }

    func flush(into continuation: AsyncStream<LogLine>.Continuation) {
        guard !pending.isEmpty else { return }
        if let text = String(data: pending, encoding: .utf8), !text.isEmpty {
            continuation.yield(LogLine(text: text, stream: stream))
        }
        pending.removeAll(keepingCapacity: false)
    }
}
