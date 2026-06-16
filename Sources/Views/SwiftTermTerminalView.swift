import SwiftUI
import SwiftTerm

/// Hosts (does NOT own) the persistent `LocalProcessTerminalView` for a session. The view + its PTY
/// live in `TerminalProcessController.shared`; this representable just re-parents the cached view
/// into the current container so the process survives panel toggles and session switches.
///
/// Theme/font are passed in from the hosting view's per-window `ConfigurationService` (not a shared
/// singleton), so terminals in secondary windows theme with that window's settings.
struct SwiftTermTerminalView: NSViewRepresentable {
    let session: TerminalSession
    let themeColors: ThemeColors
    let font: NSFont

    func makeNSView(context: Context) -> NSView {
        // A throwaway container; the real terminal view is re-parented in here by updateNSView.
        NSView()
    }

    func updateNSView(_ container: NSView, context: Context) {
        let terminalView = TerminalProcessController.shared.terminalView(
            for: session,
            themeColors: themeColors,
            font: font
        )

        if terminalView.superview !== container {
            terminalView.removeFromSuperview()
            terminalView.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(terminalView)
            NSLayoutConstraint.activate([
                terminalView.topAnchor.constraint(equalTo: container.topAnchor),
                terminalView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                terminalView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                terminalView.trailingAnchor.constraint(equalTo: container.trailingAnchor)
            ])
            // Focus only on (re)attach — not on every update — so we don't steal focus when the
            // user has clicked elsewhere. Deferred because the window may not be set yet.
            DispatchQueue.main.async { [weak terminalView] in
                guard let terminalView, let window = terminalView.window else { return }
                if window.firstResponder !== terminalView {
                    window.makeFirstResponder(terminalView)
                }
            }
        } else {
            // Already attached: just keep theme/font in sync with the current window's settings.
            TerminalProcessController.shared.applyTheme(themeColors, font: font, to: session)
        }
    }

    // Detaching only — the process is owned by the controller and must NOT be torn down here, or a
    // panel toggle / session switch would kill the shell.
    static func dismantleNSView(_ container: NSView, coordinator: ()) {}
}
