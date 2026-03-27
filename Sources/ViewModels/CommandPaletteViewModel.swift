import Foundation
import Combine

@MainActor
class CommandPaletteViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var commandPaletteQuery: String = ""
    @Published private(set) var activePalette: PaletteMode?
    
    // MARK: - Dependencies
    private let commandDispatcher: AppCommandDispatcher
    private var recentCommandPaletteActionIDs: [String] = []
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    init(commandDispatcher: AppCommandDispatcher) {
        self.commandDispatcher = commandDispatcher
    }
    
    // MARK: - Public Methods
    func toggleCommandPalette() {
        if activePalette == .commandPalette {
            activePalette = nil
        } else {
            activePalette = .commandPalette
        }
    }
    
    func closeCommandPalette() {
        activePalette = nil
    }
    
    func executeCommand(_ action: CommandPaletteAction) {
        recordCommandPaletteActionAccess(id: action.id)
        action.action()
        activePalette = nil
    }
    
    // MARK: - Command Palette Data
    var commandPaletteSections: [CommandPaletteSection] {
        let query = commandPaletteQuery
        let context = commandPaletteQueryContext(for: query)
        let allActions = commandPaletteActions
        
        let scopedActions = scopedCommandPaletteActions(allActions, scope: context.scope)
        let filteredActions = filteredCommandPaletteActions(scopedActions, query: context.searchText)
        let decoratedActions = filteredActions.map { decoratedCommandPaletteAction($0, query: query) }
        
        return commandPaletteCategorySections(for: decoratedActions, query: query)
    }
    
    // MARK: - Private Properties
    private var commandPaletteActions: [CommandPaletteAction] {
        commandDispatcher.availableCommands.map { command in
            CommandPaletteAction(
                id: command.id,
                title: command.title,
                shortcut: command.shortcut,
                category: command.category,
                aliases: command.aliases,
                detailText: nil,
                badge: nil,
                action: { [weak self] in
                    self?.commandDispatcher.dispatch(command)
                }
            )
        }
    }
    
    // MARK: - Filtering & Scoring
    private func filteredCommandPaletteActions(_ actions: [CommandPaletteAction], query: String) -> [CommandPaletteAction] {
        let normalizedQuery = normalizedCommandPaletteSearchText(query)
        
        guard !normalizedQuery.isEmpty else {
            return actions.sorted(by: compareCommandPaletteActions)
        }
        
        return actions
            .compactMap { action -> (action: CommandPaletteAction, score: Int)? in
                guard let score = commandPaletteMatchScore(for: action, query: normalizedQuery) else {
                    return nil
                }
                return (action, score + commandPaletteRecencyBoost(for: action.id))
            }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score {
                    return lhs.score > rhs.score
                }
                return compareCommandPaletteActions(lhs.action, rhs.action)
            }
            .map(\.action)
    }
    
    private func scopedCommandPaletteActions(_ actions: [CommandPaletteAction], scope: CommandPaletteScope?) -> [CommandPaletteAction] {
        guard let scope else { return actions }
        let normalizedScopeCategory = normalizedCommandPaletteSearchText(scope.category)
        return actions.filter { normalizedCommandPaletteSearchText($0.category) == normalizedScopeCategory }
    }
    
    private func compareCommandPaletteActions(_ lhs: CommandPaletteAction, _ rhs: CommandPaletteAction) -> Bool {
        let lhsRecency = commandPaletteRecencyBoost(for: lhs.id)
        let rhsRecency = commandPaletteRecencyBoost(for: rhs.id)
        
        if lhsRecency != rhsRecency {
            return lhsRecency > rhsRecency
        }
        
        let categoryComparison = lhs.category.localizedStandardCompare(rhs.category)
        if categoryComparison != .orderedSame {
            return categoryComparison == .orderedAscending
        }
        
        return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }
    
    private func decoratedCommandPaletteAction(_ action: CommandPaletteAction, query: String) -> CommandPaletteAction {
        let aliasMatch = commandPaletteMatchingAlias(for: action, query: query)
        let recentBadge = query.isEmpty && commandPaletteRecencyBoost(for: action.id) > 0 ? "Recent" : nil
        
        return CommandPaletteAction(
            id: action.id,
            title: action.title,
            shortcut: action.shortcut,
            category: action.category,
            aliases: action.aliases,
            detailText: aliasMatch.map { "Alias: \($0)" },
            badge: recentBadge,
            action: action.action
        )
    }
    
    private func commandPaletteCategorySections(for actions: [CommandPaletteAction], query: String) -> [CommandPaletteSection] {
        let grouped = Dictionary(grouping: actions, by: \.category)
        
        return grouped.keys
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .compactMap { category in
                guard let categoryActions = grouped[category], !categoryActions.isEmpty else { return nil }
                return CommandPaletteSection(
                    title: category,
                    actions: categoryActions.map { decoratedCommandPaletteAction($0, query: query) }
                )
            }
    }
    
    // MARK: - Scoring Logic
    private func commandPaletteMatchScore(for action: CommandPaletteAction, query: String) -> Int? {
        let normalizedTitle = normalizedCommandPaletteSearchText(action.title)
        let normalizedCategory = normalizedCommandPaletteSearchText(action.category)
        let normalizedAliases = action.aliases.map(normalizedCommandPaletteSearchText)
        let queryTerms = commandPaletteSearchTerms(fromNormalizedText: query)
        let condensedQuery = condensedCommandPaletteSearchText(query)
        let titleWords = commandPaletteSearchTerms(fromNormalizedText: normalizedTitle)
        var bestScore: Int?
        
        func consider(_ score: Int?) {
            guard let score else { return }
            bestScore = max(bestScore ?? .min, score)
        }
        
        if normalizedTitle == query {
            consider(1_700)
        }
        
        if normalizedAliases.contains(query) {
            consider(1_660)
        }
        
        if normalizedTitle.hasPrefix(query) {
            consider(1_560)
        }
        
        if normalizedAliases.contains(where: { $0.hasPrefix(query) }) {
            consider(1_520)
        }
        
        if !queryTerms.isEmpty, commandPaletteWordPrefixMatch(words: titleWords, queryTerms: queryTerms) {
            consider(1_460)
        }
        
        if !queryTerms.isEmpty,
           normalizedAliases.contains(where: {
               commandPaletteWordPrefixMatch(
                   words: commandPaletteSearchTerms(fromNormalizedText: $0),
                   queryTerms: queryTerms
               )
           }) {
            consider(1_420)
        }
        
        if normalizedTitle.contains(query) {
            consider(1_340)
        }
        
        if normalizedAliases.contains(where: { $0.contains(query) }) {
            consider(1_300)
        }
        
        if !queryTerms.isEmpty && queryTerms.allSatisfy({ normalizedTitle.contains($0) }) {
            consider(1_260 + min(queryTerms.count * 10, 40))
        }
        
        if !queryTerms.isEmpty && normalizedAliases.contains(where: { alias in
            queryTerms.allSatisfy { alias.contains($0) }
        }) {
            consider(1_220 + min(queryTerms.count * 10, 40))
        }
        
        if normalizedCategory.contains(query) {
            consider(1_100)
        }
        
        if !condensedQuery.isEmpty {
            let titleInitialism = commandPaletteInitialism(forWords: titleWords)
            if titleInitialism.hasPrefix(condensedQuery) {
                consider(1_060)
            }
            
            let aliasInitialismScore = normalizedAliases
                .map { commandPaletteInitialism(forWords: commandPaletteSearchTerms(fromNormalizedText: $0)) }
                .contains { $0.hasPrefix(condensedQuery) }
            if aliasInitialismScore {
                consider(1_020)
            }
            
            consider(commandPaletteFuzzyScore(haystack: condensedCommandPaletteSearchText(normalizedTitle), query: condensedQuery))
            consider(
                normalizedAliases
                    .compactMap { commandPaletteFuzzyScore(haystack: condensedCommandPaletteSearchText($0), query: condensedQuery) }
                    .max()
                    .map { $0 - 20 }
            )
        }
        
        return bestScore
    }
    
    private func commandPaletteMatchingAlias(for action: CommandPaletteAction, query: String) -> String? {
        guard !query.isEmpty else { return nil }
        
        return action.aliases.first { alias in
            let normalizedAlias = normalizedCommandPaletteSearchText(alias)
            if normalizedAlias == query || normalizedAlias.hasPrefix(query) || normalizedAlias.contains(query) {
                return true
            }
            
            let queryTerms = commandPaletteSearchTerms(fromNormalizedText: query)
            let aliasTerms = commandPaletteSearchTerms(fromNormalizedText: normalizedAlias)
            if !queryTerms.isEmpty && commandPaletteWordPrefixMatch(words: aliasTerms, queryTerms: queryTerms) {
                return true
            }
            
            return false
        }
    }
    
    // MARK: - Helper Methods
    private func normalizedCommandPaletteSearchText(_ text: String) -> String {
        text
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private var availableCommandPaletteScopes: [CommandPaletteScope] {
        [
            CommandPaletteScope(id: "file", title: "File", category: "File", queryToken: "file:", aliases: ["file", "files", "f"]),
            CommandPaletteScope(id: "go", title: "Go", category: "Go", queryToken: "go:", aliases: ["go", "goto", "g"]),
            CommandPaletteScope(id: "search", title: "Search", category: "Search", queryToken: "search:", aliases: ["search", "find", "s"]),
            CommandPaletteScope(id: "edit", title: "Edit", category: "Edit", queryToken: "edit:", aliases: ["edit", "e"]),
            CommandPaletteScope(id: "debug", title: "Debug", category: "Debug", queryToken: "debug:", aliases: ["debug", "dbg", "run"]),
            CommandPaletteScope(id: "git", title: "Git", category: "Git", queryToken: "git:", aliases: ["git", "scm"]),
            CommandPaletteScope(id: "project", title: "Project", category: "Project", queryToken: "project:", aliases: ["project", "workspace", "p"]),
            CommandPaletteScope(id: "view", title: "View", category: "View", queryToken: "view:", aliases: ["view", "panel", "v"])
        ]
    }
    
    private func commandPaletteQueryContext(for query: String) -> CommandPaletteQueryContext {
        let normalizedQuery = normalizedCommandPaletteSearchText(query)
        guard let separatorIndex = normalizedQuery.firstIndex(of: ":") else {
            return CommandPaletteQueryContext(scope: nil, searchText: normalizedQuery)
        }
        
        let scopeToken = String(normalizedQuery[..<separatorIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let scope = availableCommandPaletteScopes.first(where: { $0.aliases.contains(scopeToken) }) else {
            return CommandPaletteQueryContext(scope: nil, searchText: normalizedQuery)
        }
        
        let searchStart = normalizedQuery.index(after: separatorIndex)
        let searchText = String(normalizedQuery[searchStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return CommandPaletteQueryContext(scope: scope, searchText: searchText)
    }
    
    private func condensedCommandPaletteSearchText(_ text: String) -> String {
        normalizedCommandPaletteSearchText(text)
            .filter { $0.isLetter || $0.isNumber }
    }
    
    private func commandPaletteSearchTerms(fromNormalizedText text: String) -> [String] {
        text.split { character in
            !character.isLetter && !character.isNumber
        }
        .map(String.init)
    }
    
    private func commandPaletteWordPrefixMatch(words: [String], queryTerms: [String]) -> Bool {
        guard !words.isEmpty, !queryTerms.isEmpty else { return false }
        var wordIndex = 0
        
        for term in queryTerms {
            guard let matchIndex = words[wordIndex...].firstIndex(where: { $0.hasPrefix(term) }) else {
                return false
            }
            wordIndex = words.index(after: matchIndex)
        }
        
        return true
    }
    
    private func commandPaletteInitialism(forWords words: [String]) -> String {
        String(words.compactMap(\.first))
    }
    
    private func commandPaletteFuzzyScore(haystack: String, query: String) -> Int? {
        guard !haystack.isEmpty, !query.isEmpty else { return nil }
        var searchIndex = haystack.startIndex
        var matched = 0
        var gapPenalty = 0
        
        for character in query {
            guard let matchIndex = haystack[searchIndex...].firstIndex(of: character) else {
                return nil
            }
            
            gapPenalty += haystack.distance(from: searchIndex, to: matchIndex)
            matched += 1
            searchIndex = haystack.index(after: matchIndex)
        }
        
        return max(900 - gapPenalty * 8 - max(0, haystack.count - matched) * 2, 700)
    }
    
    private func commandPaletteRecencyBoost(for actionID: String) -> Int {
        guard let index = recentCommandPaletteActionIDs.firstIndex(of: actionID) else {
            return 0
        }
        
        return max(220 - index * 24, 40)
    }
    
    private func recordCommandPaletteActionAccess(id: String) {
        recentCommandPaletteActionIDs.removeAll { $0 == id }
        recentCommandPaletteActionIDs.insert(id, at: 0)
        recentCommandPaletteActionIDs = Array(recentCommandPaletteActionIDs.prefix(8))
    }
}
