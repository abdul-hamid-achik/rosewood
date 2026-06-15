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

    @Test
    func terminalModelSyncsWithSharedServiceOnInit() {
        let service = TerminalService.shared
        resetTerminalService(service)
        defer { resetTerminalService(service) }

        // A session opened in another window lives in the shared singleton.
        let session1 = service.createSession(type: .local(shell: "/bin/zsh"))
        #expect(service.sessions.count == 1)

        // A freshly constructed model (as a new window would create) must see it immediately.
        let model = TerminalModel(configService: ConfigurationService())
        #expect(model.terminalSessions.count == 1)
        #expect(model.currentTerminalSessionId == session1.id)
        #expect(model.terminalSessions.first?.id == session1.id)

        // A later model picks up all existing sessions and the current selection.
        let session2 = service.createSession(type: .local(shell: "/bin/bash"))
        let model2 = TerminalModel(configService: ConfigurationService())
        #expect(model2.terminalSessions.count == 2)
        #expect(model2.currentTerminalSessionId == session2.id)
    }

    private func resetTerminalService(_ service: TerminalService) {
        for sessionID in service.sessions.map(\.id) {
            service.closeSession(sessionID)
        }
    }
}
