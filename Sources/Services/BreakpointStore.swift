import Foundation

final class BreakpointStore {
    private let userDefaults: UserDefaults
    private let storageKey: String

    init(userDefaults: UserDefaults = .standard, storageKey: String = "rosewood.breakpoints") {
        self.userDefaults = userDefaults
        self.storageKey = storageKey
    }

    func breakpoints(for projectRoot: URL?) -> [Breakpoint] {
        guard let key = projectKey(for: projectRoot) else { return [] }
        let storage = loadStorage()
        return sort(storage[key] ?? [])
    }

    func setBreakpoints(_ breakpoints: [Breakpoint], for projectRoot: URL?) {
        guard let key = projectKey(for: projectRoot) else { return }
        var storage = loadStorage()
        storage[key] = sort(breakpoints)
        saveStorage(storage)
    }

    @discardableResult
    func toggleBreakpoint(fileURL: URL, line: Int, projectRoot: URL?) -> [Breakpoint] {
        guard line > 0 else { return breakpoints(for: projectRoot) }

        let normalizedPath = normalizedPath(for: fileURL)
        var projectBreakpoints = breakpoints(for: projectRoot)

        if let existingIndex = projectBreakpoints.firstIndex(where: { $0.filePath == normalizedPath && $0.line == line }) {
            projectBreakpoints.remove(at: existingIndex)
        } else {
            projectBreakpoints.append(Breakpoint(filePath: normalizedPath, line: line))
        }

        setBreakpoints(projectBreakpoints, for: projectRoot)
        return sort(projectBreakpoints)
    }

    @discardableResult
    func removeBreakpoint(_ breakpoint: Breakpoint, for projectRoot: URL?) -> [Breakpoint] {
        let updated = breakpoints(for: projectRoot).filter { $0 != breakpoint }
        setBreakpoints(updated, for: projectRoot)
        return updated
    }

    @discardableResult
    func removeBreakpoints(
        inside url: URL,
        includeDescendants: Bool,
        for projectRoot: URL?
    ) -> [Breakpoint] {
        let normalizedTarget = normalizedPath(for: url)
        let targetPrefix = normalizedTarget + "/"
        let updated = breakpoints(for: projectRoot).filter { breakpoint in
            if includeDescendants {
                return breakpoint.filePath != normalizedTarget && !breakpoint.filePath.hasPrefix(targetPrefix)
            }
            return breakpoint.filePath != normalizedTarget
        }
        setBreakpoints(updated, for: projectRoot)
        return updated
    }

    @discardableResult
    func moveBreakpoints(
        from oldURL: URL,
        to newURL: URL,
        includeDescendants: Bool,
        for projectRoot: URL?
    ) -> [Breakpoint] {
        let oldPath = normalizedPath(for: oldURL)
        let newPath = normalizedPath(for: newURL)
        let descendantPrefix = oldPath + "/"

        let updated = breakpoints(for: projectRoot).map { breakpoint in
            guard includeDescendants else {
                guard breakpoint.filePath == oldPath else { return breakpoint }
                return Breakpoint(
                    filePath: newPath,
                    line: breakpoint.line,
                    isEnabled: breakpoint.isEnabled
                )
            }

            guard breakpoint.filePath == oldPath || breakpoint.filePath.hasPrefix(descendantPrefix) else {
                return breakpoint
            }

            let suffix = breakpoint.filePath.dropFirst(oldPath.count)
            return Breakpoint(
                filePath: newPath + suffix,
                line: breakpoint.line,
                isEnabled: breakpoint.isEnabled
            )
        }

        setBreakpoints(updated, for: projectRoot)
        return sort(updated)
    }

    private func loadStorage() -> [String: [Breakpoint]] {
        guard let data = userDefaults.data(forKey: storageKey),
              let storage = try? JSONDecoder().decode([String: [Breakpoint]].self, from: data) else {
            return [:]
        }
        return storage
    }

    private func saveStorage(_ storage: [String: [Breakpoint]]) {
        guard let data = try? JSONEncoder().encode(storage) else { return }
        userDefaults.set(data, forKey: storageKey)
    }

    private func projectKey(for projectRoot: URL?) -> String? {
        guard let projectRoot else { return nil }
        return normalizedPath(for: projectRoot)
    }

    private func normalizedPath(for url: URL) -> String {
        url.standardizedFileURL.path
    }

    private func sort(_ breakpoints: [Breakpoint]) -> [Breakpoint] {
        breakpoints.sorted { lhs, rhs in
            if lhs.filePath == rhs.filePath {
                return lhs.line < rhs.line
            }
            return lhs.filePath.localizedStandardCompare(rhs.filePath) == .orderedAscending
        }
    }
}
