import Foundation
import Combine

enum AppCommand: Equatable {
    case newFile
    case openFile
    case openFolder
    case save
    case saveAs
    case saveAll
    case nextTab
    case previousTab
    case goToTab(Int)
    case reopenClosedTab
    case quickOpen
    case commandPalette
    case toggleProblems
    case toggleTerminal
    case closeTab
    case projectSearch
    case findInFile
    case findNext
    case findPrevious
    case useSelectionForFind
    case showReplace
    case goToLine
    case settings
    case goToDefinition
    case findReferences
    case nextProblem
    case previousProblem
}

final class AppCommandDispatcher: ObservableObject {
    static let shared = AppCommandDispatcher()

    private let subject = PassthroughSubject<AppCommand, Never>()

    var publisher: AnyPublisher<AppCommand, Never> {
        subject.eraseToAnyPublisher()
    }

    func send(_ command: AppCommand) {
        subject.send(command)
    }
}
