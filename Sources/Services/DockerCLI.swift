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
        return Self.parseComposeServiceNames(from: contents)
    }

    /// Pure parsing of service names from a compose file's text. Split on any newline
    /// (`Character.isNewline` matches LF, CRLF, and lone CR — `split(separator: "\n")`
    /// would not, because the `"\r\n"` grapheme cluster never equals the `"\n"` separator,
    /// leaving Windows/Docker-Desktop files completely unparsed). Empty subsequences are kept
    /// so the first blank line still terminates the `services:` block.
    static func parseComposeServiceNames(from contents: String) -> [DockerComposeService] {
        var services: [DockerComposeService] = []
        var inServicesSection = false

        for line in contents.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
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
        guard let executableURL = process.executableURL else {
            throw NSError(domain: "DockerCLI", code: 0, userInfo: [NSLocalizedDescriptionKey: "Docker executable is not configured"])
        }

        try await Task.detached(priority: .utility) {
            let result = try ProcessRunner.run(
                executableURL: executableURL,
                arguments: process.arguments ?? [],
                currentDirectoryURL: process.currentDirectoryURL,
                environment: process.environment
            )

            if result.terminationStatus != 0 {
                let message = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                throw NSError(
                    domain: "DockerCLI",
                    code: Int(result.terminationStatus),
                    userInfo: [
                        NSLocalizedDescriptionKey: message.isEmpty
                            ? "Docker command failed with exit code \(result.terminationStatus)"
                            : message
                    ]
                )
            }
        }.value
    }
}

final class LogStreamBuffer {
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

            // Lossy UTF-8 decoding: a single invalid byte anywhere in the line must not
            // discard the whole line. `String(decoding:as:)` substitutes U+FFFD for bad
            // sequences instead of returning nil, so the line is still surfaced.
            let text = String(decoding: lineData, as: UTF8.self)
            continuation.yield(LogLine(text: text, stream: stream))
        }
    }

    func flush(into continuation: AsyncStream<LogLine>.Continuation) {
        guard !pending.isEmpty else { return }
        let text = String(decoding: pending, as: UTF8.self)
        if !text.isEmpty {
            continuation.yield(LogLine(text: text, stream: stream))
        }
        pending.removeAll(keepingCapacity: false)
    }
}
