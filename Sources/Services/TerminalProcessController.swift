import AppKit
import SwiftTerm

/// Process-wide owner of the live `LocalProcessTerminalView`s, keyed by session UUID.
///
/// The terminal NSView and its child PTY process MUST outlive the SwiftUI `TerminalPanelView`,
/// which is destroyed and recreated on every bottom-panel toggle and session switch. So the views
/// live here (a `@MainActor` singleton), and the SwiftUI side only re-parents the cached view.
/// Teardown happens ONLY on explicit `closeSession` and app termination — never on SwiftUI
/// dismantle — otherwise toggling the panel would kill the shell.
@MainActor
final class TerminalProcessController: ObservableObject {
    static let shared = TerminalProcessController()

    /// Sessions whose process has exited, with the exit code (nil = unknown). Drives the
    /// restart/close overlay. Published so the panel re-renders when a shell dies.
    @Published private(set) var exitedSessions: [UUID: Int32?] = [:]

    private var views: [UUID: LocalProcessTerminalView] = [:]
    private var coordinators: [UUID: TerminalProcessCoordinator] = [:]

    private init() {}

    /// Fetch-or-create the terminal view for a session. Creates + themes + starts the process
    /// exactly once; subsequent calls return the same instance (identity preserved across toggles).
    func terminalView(for session: TerminalSession, themeColors: ThemeColors, font: NSFont) -> LocalProcessTerminalView {
        if let existing = views[session.id] {
            applyTheme(themeColors, font: font, to: existing)
            return existing
        }

        let view = LocalProcessTerminalView(frame: NSRect(x: 0, y: 0, width: 640, height: 360))
        applyTheme(themeColors, font: font, to: view)

        let coordinator = TerminalProcessCoordinator(sessionID: session.id, controller: self)
        view.processDelegate = coordinator
        coordinators[session.id] = coordinator

        let plan = TerminalLaunchPlan.make(
            for: session.type,
            workingDirectory: session.workingDirectory,
            defaultShell: "/bin/zsh",
            dockerPath: TerminalLaunchPlan.resolveDockerPath(
                fileExists: { FileManager.default.fileExists(atPath: $0) },
                pathEnvironment: ProcessInfo.processInfo.environment["PATH"]
            ),
            baseEnvironment: ProcessInfo.processInfo.environment,
            homeDirectory: NSHomeDirectory()
        )
        // startProcess is called EXACTLY once per view (guarded by the cache check above); a second
        // call on a live view would spawn a duplicate shell.
        view.startProcess(
            executable: plan.executable,
            args: plan.args,
            environment: plan.environment,
            currentDirectory: plan.currentDirectory
        )

        views[session.id] = view
        return view
    }

    /// Re-apply theme/font to a live session's view (called from updateNSView with the hosting
    /// window's per-window colors/font — NOT a shared singleton, so secondary windows theme right).
    func applyTheme(_ colors: ThemeColors, font: NSFont, to session: TerminalSession) {
        guard let view = views[session.id] else { return }
        applyTheme(colors, font: font, to: view)
    }

    private func applyTheme(_ colors: ThemeColors, font: NSFont, to view: LocalProcessTerminalView) {
        // SwiftTerm's native* setters take NSColor directly (no 0…65535 scaling); force sRGB so the
        // hex-derived theme colors are interpreted consistently.
        let foreground = colors.nsForeground.usingColorSpace(.sRGB) ?? colors.nsForeground
        let background = colors.nsBackground.usingColorSpace(.sRGB) ?? colors.nsBackground
        if view.nativeForegroundColor != foreground { view.nativeForegroundColor = foreground }
        if view.nativeBackgroundColor != background { view.nativeBackgroundColor = background }
        view.caretColor = colors.nsCursor.usingColorSpace(.sRGB) ?? colors.nsCursor
        view.selectedTextBackgroundColor = colors.nsSelection.usingColorSpace(.sRGB) ?? colors.nsSelection
        if view.font != font { view.font = font }
    }

    /// Kill a session's process and drop its view. Called from TerminalService.closeSession BEFORE
    /// the metadata is removed, so the PTY dies exactly when the user closes the session. A no-op
    /// for sessions that never spawned a view (e.g. metadata-only sessions in tests).
    func terminate(_ id: UUID) {
        if let view = views[id] {
            view.processDelegate = nil
            view.terminate()
            view.removeFromSuperview()
        }
        views[id] = nil
        coordinators[id] = nil
        exitedSessions[id] = nil
    }

    /// Terminate every live session (app quit). PTY masters also close on process death as a
    /// backstop, but this avoids leaving orphaned shells on a clean quit.
    func terminateAll() {
        for id in Array(views.keys) {
            terminate(id)
        }
    }

    /// Discard a dead session's view so the next `terminalView(for:)` spawns a fresh process.
    func restart(_ id: UUID) {
        if let view = views[id] {
            view.processDelegate = nil
            view.terminate()
            view.removeFromSuperview()
        }
        views[id] = nil
        coordinators[id] = nil
        exitedSessions[id] = nil
    }

    /// Called by the coordinator (on the main actor) when a child process exits.
    func recordExit(_ id: UUID, exitCode: Int32?) {
        guard views[id] != nil else { return }
        // updateValue (not `[id] = exitCode`): with an Int32? value type, subscript-assigning a nil
        // exitCode would REMOVE the key, so an unknown-code exit would never show the overlay.
        exitedSessions.updateValue(exitCode, forKey: id)
    }
}

/// Bridges SwiftTerm's (non-main-isolated) delegate callbacks back onto the main actor. Held
/// strongly by the controller (`processDelegate` is weak) for the life of the session.
final class TerminalProcessCoordinator: NSObject, LocalProcessTerminalViewDelegate {
    private let sessionID: UUID
    private weak var controller: TerminalProcessController?

    init(sessionID: UUID, controller: TerminalProcessController) {
        self.sessionID = sessionID
        self.controller = controller
    }

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        // SwiftTerm may deliver this off the main thread; hop explicitly before touching
        // @Published / view state.
        let id = sessionID
        Task { @MainActor [weak controller] in
            controller?.recordExit(id, exitCode: exitCode)
        }
    }
}
