import Foundation

extension ProjectViewModel {
    func openGitChangedFile(_ changedFile: GitChangedFile) {
        if let repositoryRoot = gitRepositoryStatus.repositoryRoot {
            let fileURL = repositoryRoot.appendingPathComponent(changedFile.path)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                openFile(at: fileURL, preservingGitDiffWorkspace: true)
            }
        }
        sidebarMode = .sourceControl
        isGitDiffWorkspaceVisible = true
        bottomPanel = nil
        loadGitDiff(for: changedFile)
    }

    func showPreviousGitChange() {
        guard let selectedGitChangeIndex, selectedGitChangeIndex > 0 else { return }
        openGitChangedFile(gitRepositoryStatus.changedFiles[selectedGitChangeIndex - 1])
    }

    func showNextGitChange() {
        guard let selectedGitChangeIndex, selectedGitChangeIndex < gitRepositoryStatus.changedFiles.count - 1 else { return }
        openGitChangedFile(gitRepositoryStatus.changedFiles[selectedGitChangeIndex + 1])
    }

    func openSelectedGitChangeInEditor() {
        guard let selectedTabIndex else { return }
        selectTab(at: selectedTabIndex)
    }

    func openGitChangedFileInEditor(_ changedFile: GitChangedFile) {
        openGitChangedFile(changedFile)
        openSelectedGitChangeInEditor()
    }

    func revealSelectedGitChangeInExplorer() {
        guard selectedGitChangedFile != nil else { return }
        sidebarMode = .explorer
    }

    func stageSelectedGitChange() {
        guard let changedFile = selectedGitChangedFile else { return }
        stageGitChange(changedFile)
    }

    func stageGitChange(_ changedFile: GitChangedFile) {
        runGitMutation(
            task: { [gitService, rootDirectory] in
                await gitService.stage(changedFile: changedFile, projectRoot: rootDirectory)
            }
        )
    }

    func unstageSelectedGitChange() {
        guard let changedFile = selectedGitChangedFile else { return }
        unstageGitChange(changedFile)
    }

    func unstageGitChange(_ changedFile: GitChangedFile) {
        runGitMutation(
            task: { [gitService, rootDirectory] in
                await gitService.unstage(changedFile: changedFile, projectRoot: rootDirectory)
            }
        )
    }

    func discardSelectedGitChange() {
        guard let changedFile = selectedGitChangedFile else { return }
        discardGitChange(changedFile)
    }

    func discardGitChange(_ changedFile: GitChangedFile) {
        let title = changedFile.kind == .untracked ? "Discard New File?" : "Discard Working Tree Changes?"
        let message = changedFile.kind == .untracked
            ? "This will permanently delete \(changedFile.path)."
            : "This will restore \(changedFile.path) to the last committed version."
        let response = ui.confirm(title, message, .warning, ["Discard", "Cancel"])
        guard response == .alertFirstButtonReturn else { return }

        runGitMutation(
            task: { [gitService, rootDirectory] in
                await gitService.discard(changedFile: changedFile, projectRoot: rootDirectory)
            },
            onSuccess: { [weak self] in
                guard let self else { return }
                if changedFile.kind == .untracked,
                   let selectedTabIndex = self.selectedTabIndex,
                   self.openTabs.indices.contains(selectedTabIndex),
                   let filePath = self.openTabs[selectedTabIndex].filePath,
                   let repositoryRoot = self.gitRepositoryStatus.repositoryRoot,
                   self.normalizedPath(for: filePath) == self.normalizedPath(for: repositoryRoot.appendingPathComponent(changedFile.path)) {
                    _ = self.closeTab(at: selectedTabIndex, confirmUnsavedChanges: false)
                }
            }
        )
    }

    func closeGitDiffPanel() {
        dismissGitDiffWorkspace()
        selectedGitDiff = nil
        selectedGitDiffPath = nil
        isLoadingGitDiff = false
        if isGitDiffPanelVisible {
            bottomPanel = nil
        }
    }

    func refreshGitState() {
        gitStatusTask?.cancel()
        gitStatusToken = UUID()
        let token = gitStatusToken

        guard let rootDirectory else {
            resetGitState()
            return
        }

        let normalizedRootPath = normalizedPath(for: rootDirectory)
        isRefreshingGitStatus = true

        gitStatusTask = Task { [weak self] in
            guard let self else { return }
            let status = await self.gitService.repositoryStatus(for: rootDirectory)
            guard !Task.isCancelled,
                  self.gitStatusToken == token,
                  self.rootDirectory.map(self.normalizedPath(for:)) == normalizedRootPath else {
                return
            }

            self.gitRepositoryStatus = status
            self.isRefreshingGitStatus = false
            self.refreshSelectedGitDiffIfNeeded()
            self.refreshCurrentLineBlame()
        }
    }

    private func loadGitDiff(for changedFile: GitChangedFile) {
        gitDiffTask?.cancel()
        gitDiffToken = UUID()
        let token = gitDiffToken
        selectedGitDiffPath = changedFile.path
        selectedGitDiff = nil
        isLoadingGitDiff = true

        let normalizedRootPath = rootDirectory.map(normalizedPath(for:))
        gitDiffTask = Task { [weak self] in
            guard let self else { return }
            let diff = await self.gitService.diff(for: changedFile, projectRoot: self.rootDirectory)
            guard !Task.isCancelled,
                  self.gitDiffToken == token,
                  self.selectedGitDiffPath == changedFile.path,
                  self.rootDirectory.map(self.normalizedPath(for:)) == normalizedRootPath else {
                return
            }

            self.selectedGitDiff = diff
            self.isLoadingGitDiff = false
        }
    }

    private func refreshSelectedGitDiffIfNeeded() {
        guard let selectedGitDiffPath else {
            selectedGitDiff = nil
            isLoadingGitDiff = false
            return
        }

        guard let changedFile = gitRepositoryStatus.changedFiles.first(where: { $0.path == selectedGitDiffPath }) else {
            closeGitDiffPanel()
            return
        }

        if isGitDiffVisible {
            loadGitDiff(for: changedFile)
        }
    }

    func refreshCurrentLineBlame() {
        gitBlameTask?.cancel()
        gitBlameToken = UUID()
        let token = gitBlameToken

        guard let selectedTab, let fileURL = selectedTab.filePath, !selectedTab.isDirty else {
            currentLineBlame = nil
            return
        }

        currentLineBlame = nil
        let selectedPath = normalizedPath(for: fileURL)
        let selectedLine = selectedTab.cursorPosition.line
        let normalizedRootPath = rootDirectory.map(normalizedPath(for:))

        gitBlameTask = Task { [weak self] in
            guard let self else { return }
            let blame = await self.gitService.blame(
                for: fileURL,
                line: selectedLine,
                projectRoot: self.rootDirectory
            )
            guard !Task.isCancelled,
                  self.gitBlameToken == token,
                  self.selectedTab?.filePath.map(self.normalizedPath(for:)) == selectedPath,
                  self.selectedTab?.cursorPosition.line == selectedLine,
                  self.rootDirectory.map(self.normalizedPath(for:)) == normalizedRootPath else {
                return
            }

            self.currentLineBlame = blame
        }
    }

    private func runGitMutation(
        task: @escaping @Sendable () async -> GitOperationResult,
        onSuccess: (() -> Void)? = nil
    ) {
        Task { [weak self] in
            guard let self else { return }
            let result = await task()
            guard !Task.isCancelled else { return }

            if result.isSuccess {
                onSuccess?()
                self.refreshGitState()
            } else {
                self.ui.alert("Git Action Failed", result.message ?? "Git action failed.", .warning)
            }
        }
    }

    private func resetGitState() {
        gitRepositoryStatus = .empty
        selectedGitDiff = nil
        selectedGitDiffPath = nil
        currentLineBlame = nil
        isRefreshingGitStatus = false
        isLoadingGitDiff = false
        if isGitDiffPanelVisible {
            bottomPanel = nil
        }
    }

    func dismissGitDiffWorkspace() {
        isGitDiffWorkspaceVisible = false
    }
}
