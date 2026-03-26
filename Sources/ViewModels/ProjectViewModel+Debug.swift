import Foundation

extension ProjectViewModel {
    func selectDebugConfiguration(named name: String) {
        guard debugConfigurations.contains(where: { $0.name == name }) else { return }
        selectedDebugConfigurationName = name
        persistDebugPreferences()
    }

    func toggleDebugPanel() {
        bottomPanel = isDebugPanelVisible ? nil : .debugConsole
        persistDebugPreferences()
    }

    func createProjectConfig() {
        if let rootDirectory {
            configService.setProjectRoot(rootDirectory)
        }

        do {
            try configService.createDefaultProjectConfig()
            reloadDebugConfigurations()
            refreshGitState()
        } catch {
            ui.alert("Error", "Could not create project config: \(error.localizedDescription)", .warning)
        }
    }

    func openProjectConfig(createIfNeeded: Bool = false) {
        guard let rootDirectory else { return }

        configService.setProjectRoot(rootDirectory)
        guard let projectConfigURL = configService.projectConfigURL else { return }

        if !FileManager.default.fileExists(atPath: projectConfigURL.path) {
            guard createIfNeeded else {
                ui.alert("No Project Config", "Create a .rosewood.toml file first.", .warning)
                return
            }

            do {
                try configService.createDefaultProjectConfig()
                reloadDebugConfigurations()
                refreshGitState()
            } catch {
                ui.alert("Error", "Could not create project config: \(error.localizedDescription)", .warning)
                return
            }
        }

        openFile(at: projectConfigURL)
    }

    func clearDebugConsole() {
        debugConsoleEntries = []
    }

    func openCurrentDebugStopLocation() {
        guard let debugStoppedFilePath, let debugStoppedLine else { return }
        let fileURL = URL(fileURLWithPath: debugStoppedFilePath)
        openFile(at: fileURL)
        guard let selectedTabIndex, openTabs.indices.contains(selectedTabIndex) else { return }
        openTabs[selectedTabIndex].pendingLineJump = debugStoppedLine
    }

    func startDebugging() {
        guard let rootDirectory else {
            ui.alert("No Folder Open", "Please open a folder first.", .warning)
            return
        }

        reloadDebugConfigurations()
        guard let configuration = selectedDebugConfiguration else {
            showDebugSidebar()
            ui.alert("No Debug Configuration", "Add a [debug] configuration to .rosewood.toml first.", .warning)
            return
        }

        guard prepareForSessionTransition(
            title: "Start Debugger",
            message: "Do you want to save changes before starting the debug session?"
        ) else {
            return
        }

        showDebugSidebar()
        bottomPanel = .debugConsole
        persistDebugPreferences()
        clearStoppedLocation()
        debugSessionState = .starting
        appendDebugConsole("Starting \"\(configuration.name)\"...", kind: .info)

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let result = try await self.debugSessionService.start(
                    configuration: configuration,
                    projectRoot: rootDirectory,
                    breakpoints: self.breakpoints
                )
                if result.executedPreLaunchTask {
                    self.appendDebugConsole("preLaunchTask completed successfully.", kind: .success)
                }
                self.appendDebugConsole("Found lldb-dap at \(result.adapterPath)", kind: .success)
                self.appendDebugConsole("Program ready at \(result.programPath)", kind: .success)
            } catch {
                let message = error.localizedDescription
                self.debugSessionState = .failed(message)
                self.clearStoppedLocation()
                self.appendDebugConsole(message, kind: .error)
                self.ui.alert("Debug Start Failed", message, .warning)
            }
        }
    }

    func stopDebugging() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.debugSessionService.stop()
        }
    }

    func toggleBreakpoint(line: Int) {
        guard let rootDirectory, let fileURL = selectedTab?.filePath else { return }
        breakpoints = breakpointStore.toggleBreakpoint(fileURL: fileURL, line: line, projectRoot: rootDirectory)
        syncActiveDebugBreakpoints()
    }

    func openBreakpoint(_ breakpoint: Breakpoint) {
        let fileURL = URL(fileURLWithPath: breakpoint.filePath)
        openFile(at: fileURL)
        if let selectedTabIndex, openTabs.indices.contains(selectedTabIndex) {
            openTabs[selectedTabIndex].pendingLineJump = breakpoint.line
        }
    }

    func openNextBreakpoint() {
        guard let breakpoint = navigatedBreakpoint(step: 1) else { return }
        openBreakpoint(breakpoint)
    }

    func openPreviousBreakpoint() {
        guard let breakpoint = navigatedBreakpoint(step: -1) else { return }
        openBreakpoint(breakpoint)
    }

    func reloadDebuggerState(resetConsole: Bool) {
        Task { @MainActor [weak self] in
            await self?.debugSessionService.stop()
        }
        loadBreakpoints()
        reloadDebugConfigurations()
        clearStoppedLocation()
        debugSessionState = .idle
        if resetConsole {
            debugConsoleEntries = []
        }
    }

    private func navigatedBreakpoint(step: Int) -> Breakpoint? {
        guard !breakpoints.isEmpty else { return nil }

        let sortedBreakpoints = breakpoints.sorted { lhs, rhs in
            if lhs.filePath != rhs.filePath {
                return lhs.filePath.localizedStandardCompare(rhs.filePath) == .orderedAscending
            }
            return lhs.line < rhs.line
        }

        let currentKey = selectedTab?.filePath.map(normalizedPath(for:)) ?? ""
        let currentLine = selectedTab?.cursorPosition.line ?? 1
        let currentIndex = sortedBreakpoints.firstIndex { breakpoint in
            breakpoint.filePath == currentKey && breakpoint.line == currentLine
        }

        if let currentIndex {
            let nextIndex = (currentIndex + step + sortedBreakpoints.count) % sortedBreakpoints.count
            return sortedBreakpoints[nextIndex]
        }

        if step >= 0 {
            return sortedBreakpoints.first(where: { breakpoint in
                breakpoint.filePath.localizedStandardCompare(currentKey) == .orderedDescending
                    || (breakpoint.filePath == currentKey && breakpoint.line >= currentLine)
            }) ?? sortedBreakpoints.first
        }

        return sortedBreakpoints.last(where: { breakpoint in
            breakpoint.filePath.localizedStandardCompare(currentKey) == .orderedAscending
                || (breakpoint.filePath == currentKey && breakpoint.line <= currentLine)
        }) ?? sortedBreakpoints.last
    }

    func loadBreakpoints() {
        breakpoints = breakpointStore.breakpoints(for: rootDirectory)
    }

    func reloadDebugConfigurations() {
        do {
            let configuration = try debugConfigurationService.loadProjectConfiguration(for: rootDirectory)
            debugConfigurationError = nil
            debugConfigurations = configuration.configurations

            let resolvedSelection = [
                selectedDebugConfigurationName,
                storedSelectedDebugConfigurationName(for: rootDirectory),
                configuration.defaultConfiguration,
                configuration.configurations.first?.name
            ]
                .compactMap { $0 }
                .first { candidate in
                    configuration.configurations.contains(where: { $0.name == candidate })
                }

            selectedDebugConfigurationName = resolvedSelection
            persistDebugPreferences()
        } catch {
            debugConfigurations = []
            selectedDebugConfigurationName = nil
            debugConfigurationError = error.localizedDescription
        }
    }

    private func appendDebugConsole(_ message: String, kind: DebugConsoleEntry.Kind) {
        debugConsoleEntries.append(DebugConsoleEntry(kind: kind, message: message))
    }

    func handleDebugSessionEvent(_ event: DebugSessionEvent) {
        switch event {
        case let .output(kind, message):
            appendDebugConsole(message, kind: kind)
        case let .state(state):
            debugSessionState = state
            if case .idle = state {
                clearStoppedLocation()
            }
        case let .stopped(filePath, line, reason):
            debugStoppedFilePath = filePath.map { normalizedPath(for: URL(fileURLWithPath: $0)) }
            debugStoppedLine = line
            appendDebugConsole("Paused: \(reason)", kind: .warning)

            guard let filePath, let line else { return }
            let fileURL = URL(fileURLWithPath: filePath)
            openFile(at: fileURL)
            if let selectedTabIndex, openTabs.indices.contains(selectedTabIndex) {
                openTabs[selectedTabIndex].pendingLineJump = line
            }
        case .terminated:
            clearStoppedLocation()
            appendDebugConsole("Debug session terminated.", kind: .info)
        }
    }

    func clearStoppedLocation() {
        debugStoppedFilePath = nil
        debugStoppedLine = nil
    }

    func syncActiveDebugBreakpoints() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.debugSessionService.updateBreakpoints(self.breakpoints, projectRoot: self.rootDirectory)
        }
    }

    func storedSelectedDebugConfigurationName(for projectRoot: URL?) -> String? {
        guard let projectRoot else { return nil }
        let selections = sessionStore.dictionary(forKey: debugSelectedConfigurationsKey) as? [String: String] ?? [:]
        return selections[normalizedPath(for: projectRoot)]
    }

    func persistDebugPreferences() {
        sessionStore.set(isDebugPanelVisible, forKey: debugPanelVisibilityKey)

        guard let rootDirectory, let selectedDebugConfigurationName else { return }

        var selections = sessionStore.dictionary(forKey: debugSelectedConfigurationsKey) as? [String: String] ?? [:]
        selections[normalizedPath(for: rootDirectory)] = selectedDebugConfigurationName
        sessionStore.set(selections, forKey: debugSelectedConfigurationsKey)
    }
}
