import Foundation

/// Owns debug configuration + session-DISPLAY state, extracted from ProjectViewModel so debug
/// events — program output streaming into the console, session-state transitions — re-render
/// only the debug sidebar, panel, and status bar rather than every view observing the app-wide
/// view model. Injected as its own @EnvironmentObject.
///
/// The +Debug drivers on ProjectViewModel still write these through thin forwarders, so that
/// logic and its tests are unchanged; the debug views observe this model directly. Breakpoints
/// and the stopped-location stay on ProjectViewModel — they are editor render-path /
/// breakpoint-store-coupled state, not pure debug-panel display.
@MainActor
final class DebugModel: ObservableObject {
    @Published var debugConfigurations: [DebugConfiguration] = []
    @Published var selectedDebugConfigurationName: String?
    @Published var debugConfigurationError: String?
    @Published var debugSessionState: DebugSessionState = .idle
    @Published var debugConsoleEntries: [DebugConsoleEntry] = []
    /// Full call stack at the current stop (first frame = execution point); empty when not paused.
    @Published var callStackFrames: [DAPStackFrame] = []
    /// The stack frame the user has selected to inspect (defaults to the top frame on each stop).
    @Published var selectedFrameId: Int?
}
