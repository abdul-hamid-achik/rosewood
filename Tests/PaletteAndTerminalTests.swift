import Foundation
import Testing
@testable import Rosewood

@Suite(.serialized)
@MainActor
struct PaletteAndTerminalTests {
    @Test
    func commandPaletteViewModelSwitchesBetweenModes() {
        let viewModel = CommandPaletteViewModel(commandDispatcher: .shared)

        #expect(viewModel.activePalette == nil)

        viewModel.toggleCommandPalette()
        #expect(viewModel.activePalette == .commandPalette)

        viewModel.toggleQuickOpen()
        #expect(viewModel.activePalette == .quickOpen)

        viewModel.closePalette()
        #expect(viewModel.activePalette == nil)
    }

    @Test
    func terminalServiceKeepsCurrentSessionSelectionConsistent() {
        let service = TerminalService.shared
        resetTerminalService(service)
        defer { resetTerminalService(service) }

        let first = service.createSession(type: .local(shell: "/bin/zsh"))
        #expect(service.currentSessionId == first.id)
        #expect(service.sessions.first?.isActive == true)

        let second = service.createSession(type: .local(shell: "/bin/bash"))
        #expect(service.currentSessionId == second.id)
        #expect(service.sessions.first(where: { $0.id == first.id })?.isActive == false)
        #expect(service.sessions.first(where: { $0.id == second.id })?.isActive == true)

        service.selectSession(first.id)
        #expect(service.currentSessionId == first.id)
        #expect(service.sessions.first(where: { $0.id == first.id })?.isActive == true)
        #expect(service.sessions.first(where: { $0.id == second.id })?.isActive == false)

        service.closeSession(first.id)
        #expect(service.currentSessionId == second.id)
        #expect(service.sessions.count == 1)
        #expect(service.sessions.first?.isActive == true)
    }

    private func resetTerminalService(_ service: TerminalService) {
        for sessionID in service.sessions.map(\.id) {
            service.closeSession(sessionID)
        }
    }
}
