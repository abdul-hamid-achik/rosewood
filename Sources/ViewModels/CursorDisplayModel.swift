import Foundation

/// Holds the live caret position for the selected tab so the status bar's line:col display updates
/// as the caret moves WITHOUT re-rendering every view observing ProjectViewModel. The caret moves on
/// every keystroke/arrow/click; routing the display through this child ObservableObject (mirroring
/// GitModel/DiagnosticsModel) is what keeps a caret move from firing ProjectViewModel.objectWillChange.
///
/// The authoritative per-tab caret still lives on EditorTab.cursorPosition (for tab-switch restore +
/// session persistence); ProjectViewModel feeds this model the live value and flushes the committed
/// value into the tab struct at boundaries.
@MainActor
final class CursorDisplayModel: ObservableObject {
    @Published var position: CursorPosition = CursorPosition()
}
