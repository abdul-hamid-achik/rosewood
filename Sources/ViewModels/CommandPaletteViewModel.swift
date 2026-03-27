import Foundation

@MainActor
final class CommandPaletteViewModel: ObservableObject {
    @Published var commandPaletteQuery: String = ""
    @Published private(set) var activePalette: PaletteMode?

    init(commandDispatcher _: AppCommandDispatcher) {}

    func toggleCommandPalette() {
        if activePalette == .commandPalette {
            closePalette()
        } else {
            showCommandPalette()
        }
    }

    func toggleQuickOpen() {
        if activePalette == .quickOpen {
            closePalette()
        } else {
            showQuickOpen()
        }
    }

    func showCommandPalette() {
        activePalette = .commandPalette
    }

    func showQuickOpen() {
        activePalette = .quickOpen
    }

    func closePalette() {
        activePalette = nil
    }
}
