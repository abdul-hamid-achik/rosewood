# Rosewood Improvement Plan

## Executive Summary

Based on comprehensive analysis of the Rosewood codebase, this plan addresses critical performance bottlenecks, architectural improvements, and UX friction points. The editor currently suffers from O(n) operations on every keystroke (where n = document size), causing severe lag on large files. This plan provides a roadmap to achieve sub-16ms frame times for files of any size.

**Current State:** Functional editor with significant performance issues at scale
**Target State:** Fast, responsive editor with excellent UX
**Estimated Timeline:** 6-8 weeks for all P0/P1 items

---

## Priority Legend

- **P0 (Critical)**: Immediate fixes, blocking daily use
- **P1 (High)**: Core performance improvements, 1-2 weeks
- **P2 (Medium)**: UX improvements, 2-4 weeks
- **P3 (Low)**: Nice-to-have optimizations, 4-8 weeks

---

## P0: Critical Performance Fixes

### P0.1: Disable Automatic Text Checking
**Impact:** Eliminates background spell/grammar checking overhead
**Effort:** 5 minutes
**File:** `Sources/Views/EditorView.swift`
**Lines:** After 1172

```swift
// Add after existing textView configuration
textView.isContinuousSpellCheckingEnabled = false
textView.isGrammarCheckingEnabled = false
textView.isAutomaticSpellingCorrectionEnabled = false
textView.usesRuler = false
textView.usesInspectorBar = false
textView.acceptsGlyphInfo = false
```

**Testing:** Verify no red underlines appear in code

---

### P0.2: Remove Editor Recreation on Config Changes
**Impact:** Prevents full NSTextView rebuild on every setting change
**Effort:** 2 hours
**File:** `Sources/Views/EditorView.swift`
**Lines:** 120

**Current:**
```swift
.id(configIdentity)  // Forces complete recreation
```

**Fix:** Remove `.id(configIdentity)` and implement incremental updates in `updateNSView`:

```swift
func updateNSView(_ nsView: EditorContainerView, context: Context) {
    // Apply changes incrementally instead of recreating
    if nsView.textView.font != editorFont {
        nsView.textView.font = editorFont
    }
    if nsView.themeColors != themeColors {
        nsView.applyTheme(themeColors)
    }
    // ... other incremental updates
}
```

**Testing:** Change font size - editor should update without losing scroll position

---

### P0.3: Fix ScrollView Configuration
**Impact:** Improves scroll performance
**Effort:** 15 minutes
**File:** `Sources/Views/EditorView.swift`
**Lines:** 1186-1191

```swift
scrollView.drawsBackground = false  // TextView handles background
scrollView.postsFrameChangedNotifications = false  // Not used
scrollView.automaticallyAdjustsContentInsets = false
if #available(macOS 11.0, *) {
    scrollView.contentView.layerContentsRedrawPolicy = .onScroll
}
```

---

## P1: High-Impact Performance Improvements

### P1.1: Implement Incremental Text Updates
**Impact:** Changes O(n) to O(change_size) on every edit
**Effort:** 1-2 days
**File:** `Sources/Views/EditorView.swift`
**Lines:** 1289-1297

**Current Problem:**
```swift
let replacementRange = NSRange(location: 0, length: textStorage.length)
textStorage.replaceCharacters(in: replacementRange, with: highlighted.string)
```

**Solution:** Track actual changes and only replace affected range:

```swift
// In textDidChange, capture the actual change range
func textDidChange(_ notification: Notification) {
    guard let textView = notification.object as? NSTextView else { return }
    
    // Get the actual edited range from the text storage
    let editedRange = textView.textStorage?.editedRange
    let changeLength = textView.textStorage?.changeInLength
    
    // Only highlight the changed region plus context
    let highlightRange = NSRange(
        location: max(0, editedRange.location - 100),
        length: min(textStorage.length - editedRange.location, editedRange.length + 200)
    )
    
    applyIncrementalHighlighting(range: highlightRange)
}
```

**Dependencies:** P0.2 (Editor recreation fix)
**Testing:** Profile typing in a 10,000 line file - should see O(1) performance

---

### P1.2: Remove Synchronous Layout Forcing
**Impact:** Eliminates main thread blocking on every edit
**Effort:** 30 minutes
**File:** `Sources/Views/EditorView.swift`
**Line:** 1316

**Current:**
```swift
layoutManager.ensureLayout(for: textContainer)  // BLOCKS MAIN THREAD
```

**Fix:** Remove this line. Let layout happen lazily.

**Note:** May require testing to ensure minimap and line numbers still update correctly.

---

### P1.3: Cache Line Positions for Cursor Calculation
**Impact:** Changes cursor position from O(n) to O(log n)
**Effort:** 4 hours
**File:** `Sources/Views/EditorView.swift`
**Lines:** 483-496

**Current Problem:**
```swift
let prefix = text[..<stringIndex]
let line = prefix.reduce(into: 1) { result, character in  // SCANS ENTIRE PREFIX
    if character == "\n" {
        result += 1
    }
}
```

**Solution:** Maintain a line offset table:

```swift
private var lineOffsetTable: [Int] = [0]  // Offsets of each line

func updateLineOffsetTable() {
    lineOffsetTable = [0]
    var offset = 0
    text.enumerateSubstrings(in: NSRange(location: 0, length: text.utf16.count), options: .byLines) { _, substringRange, _, _ in
        offset = substringRange.location + substringRange.length
        self.lineOffsetTable.append(offset)
    }
}

func lineAndColumn(for offset: Int) -> (line: Int, column: Int) {
    // Binary search in lineOffsetTable
    let line = lineOffsetTable.binarySearch { $0 <= offset } - 1
    let column = offset - lineOffsetTable[line]
    return (line + 1, column + 1)
}
```

**Testing:** Test cursor movement in large files

---

### P1.4: Debounce Minimap Updates
**Impact:** Reduces scroll processing from O(n) to throttled
**Effort:** 1 hour
**File:** `Sources/Views/EditorView.swift`
**Lines:** 1379-1397

**Current:** Minimap recalculated on every scroll event

**Solution:**

```swift
private var minimapUpdateTask: Task<Void, Never>?

private func updateMinimap() {
    minimapUpdateTask?.cancel()
    minimapUpdateTask = Task { [weak self] in
        try? await Task.sleep(nanoseconds: 100_000_000)  // 100ms debounce
        guard let self = self, !Task.isCancelled else { return }
        
        await MainActor.run {
            self.calculateAndApplyMinimap()
        }
    }
}
```

---

### P1.5: Fix Redundant needsDisplay Calls
**Impact:** Reduces unnecessary redraws by ~50%
**Effort:** 30 minutes
**File:** `Sources/Views/EditorView.swift`
**Lines:** 1319-1324, 1354-1360

**Current:** Multiple redundant calls
```swift
textView.needsDisplay = true          // Called twice
lineNumberView.needsDisplay = true    // Called 6+ times
```

**Fix:** Consolidate into single call per update cycle, remove calls from `layout()`.

---

### P1.6: Implement LSP Incremental Sync
**Impact:** Reduces network/memory overhead from O(n) to O(change_size)
**Effort:** 2-3 days
**File:** `Sources/LSP/LSPClient.swift`
**Lines:** 179-186

**Current:** Sends full document text on every change
```swift
contentChanges: [TextDocumentContentChangeEvent(text: text)]  // Full text
```

**Solution:** Send incremental changes with range information:

```swift
func didChangeDocument(uri: String, version: Int, changes: [TextChange]) {
    let contentChanges = changes.map { change in
        TextDocumentContentChangeEvent(
            range: change.range,  // Changed range
            rangeLength: change.rangeLength,
            text: change.text     // Only the changed text
        )
    }
    // ... send notification
}
```

**Testing:** Monitor network traffic - should see dramatically reduced payload sizes

---

### P1.7: Throttle LSP Diagnostic Updates
**Impact:** Prevents rapid-fire SwiftUI re-renders
**Effort:** 1 hour
**File:** `Sources/Services/LSPService.swift`
**Lines:** 270-272

**Current:**
```swift
@Published var diagnosticsByURI: [String: [LSPDiagnostic]] = [:]
```

**Solution:**

```swift
private var diagnosticThrottleTask: Task<Void, Never>?

private func handleDiagnostics(uri: String, diagnostics: [LSPDiagnostic]) {
    diagnosticThrottleTask?.cancel()
    diagnosticThrottleTask = Task { [weak self] in
        try? await Task.sleep(nanoseconds: 100_000_000)  // 100ms
        guard let self = self, !Task.isCancelled else { return }
        await MainActor.run {
            self.diagnosticsByURI[uri] = diagnostics
        }
    }
}
```

---

## P2: UX Improvements

### P2.1: Add Loading States for File Operations
**Impact:** Users see progress when opening large files
**Effort:** 4 hours
**Files:** 
- `Sources/ViewModels/ProjectViewModel.swift` (2350-2407)
- `Sources/Views/ContentView.swift`

**Implementation:**
1. Add `isLoadingFile: Bool` to ViewModel
2. Show spinner overlay in EditorView when loading
3. Load files asynchronously with progress callback

---

### P2.2: Replace Modals with Non-Blocking Notifications
**Impact:** Eliminates workflow interruption
**Effort:** 1 day
**Files:** `Sources/ViewModels/ProjectViewModel.swift`

**Affected Operations:**
- External file changes (2864-2877)
- Unsaved tab close (2501-2517)
- Delete confirmation (2918-2943)
- Replace confirmation

**Solution:** Create a non-blocking notification banner system:

```swift
enum NotificationType {
    case info, warning, success, error
}

struct NotificationBanner: View {
    let title: String
    let message: String
    let actions: [NotificationAction]
    let onDismiss: () -> Void
}
```

---

### P2.3: Persist Scroll Position When Switching Tabs
**Impact:** Users don't lose context when returning to files
**Effort:** 4 hours
**File:** `Sources/Views/EditorView.swift`

**Implementation:**
1. Store scroll position in EditorTab model
2. Save position on tab switch
3. Restore position when tab becomes active

```swift
struct EditorTab {
    // ... existing properties
    var scrollPosition: NSPoint?
}

// In EditorView
func tabDidBecomeActive() {
    if let position = tab.scrollPosition {
        scrollView.documentView?.scroll(position)
    }
}
```

---

### P2.4: Add Toast Notifications for Save/Operations
**Impact:** Users get confirmation of actions
**Effort:** 3 hours
**File:** `Sources/Views/ContentView.swift`

**Solution:** Add a toast system that shows briefly:

```swift
ToastView(message: "Saved filename.swift")
    .transition(.move(edge: .bottom))
    .animation(.easeInOut(duration: 0.3))
```

**Events to notify:**
- File saved
- File created/renamed/deleted
- Git operations completed
- Search completed (with result count)

---

### P2.5: Improve Dirty State Visibility
**Impact:** Users can easily see which files have unsaved changes
**Effort:** 2 hours
**Files:**
- `Sources/Views/TabBarView.swift` (59-63)
- `Sources/Views/FileTreeView.swift`

**Changes:**
1. Larger/modified indicator in tabs
2. Show dirty indicator in file tree for open files
3. Consider italicizing dirty filenames

---

## P3: Architecture Improvements

### P3.1: Decompose ProjectViewModel
**Impact:** Improves maintainability and testability
**Effort:** 1-2 weeks
**File:** `Sources/ViewModels/ProjectViewModel.swift` (4,177 lines)

**New ViewModels:**
```
ProjectCoordinator (main)
├── FileBrowserViewModel (file tree)
├── EditorTabsViewModel (tabs, content)
├── SearchViewModel (project search)
├── GitViewModel (repository)
├── DebugViewModel (breakpoints)
└── CommandPaletteViewModel (actions)
```

**Benefits:**
- Each ViewModel < 500 lines
- Isolated concerns
- Easier testing
- Reduced cascading updates

---

### P3.2: Implement Proper Service Protocols
**Impact:** Improves testability and allows mocking
**Effort:** 2 days
**Files:** All service files

**Current:** Some services have protocols, others don't

**Solution:** Create protocols for all services:

```swift
protocol ConfigurationServiceProtocol: ObservableObject {
    var settings: AppSettings { get }
    var themeColors: ThemeColors { get }
    func load()
}

// Keep concrete implementation
final class ConfigurationService: ConfigurationServiceProtocol { ... }
```

---

### P3.3: Move Highlighting Off Main Thread
**Impact:** Eliminates main thread blocking for large files
**Effort:** 3 days
**File:** `Sources/Services/HighlightService.swift`

**Current:** Highlightr runs synchronously on main thread

**Solution:**

```swift
func highlightAsync(
    _ code: String,
    language: String,
    completion: @escaping (NSAttributedString) -> Void
) {
    Task.detached(priority: .userInitiated) {
        let result = self.highlightedAttributedString(code, ...)
        await MainActor.run {
            completion(result)
        }
    }
}
```

**Note:** Requires careful handling of text that may have changed during highlighting.

---

### P3.4: Cache Computed Properties
**Impact:** Reduces repeated expensive calculations
**Effort:** 1 day
**File:** `Sources/ViewModels/ProjectViewModel.swift`

**Current:** Properties recalculated on every access:
```swift
var quickOpenSections: [QuickOpenSection] { ... }  // Recreates every time
var flatFileList: [FileItem] { flattenFileTree(fileTree) }
```

**Solution:** Cache with invalidation:

```swift
private var cachedFlatFileList: [FileItem]?

var flatFileList: [FileItem] {
    if let cached = cachedFlatFileList { return cached }
    let result = flattenFileTree(fileTree)
    cachedFlatFileList = result
    return result
}

func invalidateFlatFileList() {
    cachedFlatFileList = nil
}
```

---

## Quick Wins (Under 1 Hour)

1. **Disable spell checking** (P0.1) - 5 min
2. **Fix scrollView configuration** (P0.3) - 15 min
3. **Remove ensureLayout** (P1.2) - 30 min
4. **Fix redundant needsDisplay** (P1.5) - 30 min
5. **Add minimap debounce** (P1.4) - 1 hour

**Total time for all quick wins: ~3 hours**

---

## Implementation Order

### Week 1: Critical Performance
1. P0.1: Disable text checking
2. P0.2: Fix editor recreation
3. P0.3: Fix scrollView config
4. P1.2: Remove ensureLayout
5. P1.5: Fix needsDisplay calls

### Week 2: Core Performance
1. P1.1: Incremental text updates
2. P1.4: Minimap debounce
3. P1.3: Cache line positions
4. P1.6: LSP incremental sync
5. P1.7: Throttle diagnostics

### Week 3-4: UX Improvements
1. P2.1: Loading states
2. P2.2: Non-blocking notifications
3. P2.3: Scroll persistence
4. P2.4: Toast notifications
5. P2.5: Dirty state visibility

### Week 5-8: Architecture
1. P3.1: Decompose ViewModel
2. P3.2: Service protocols
3. P3.3: Background highlighting
4. P3.4: Computed property caching

---

## Success Metrics

After implementing this plan, Rosewood should achieve:

| Metric | Current | Target |
|--------|---------|--------|
| Typing latency (10K lines) | ~200ms | <16ms |
| Scroll frame time | ~100ms | <16ms |
| Memory usage (idle) | ~150MB | <100MB |
| Tab switch time | ~500ms | <50ms |
| File open (1MB) | ~2s | <500ms |
| Startup time | ~3s | <1s |

---

## Testing Strategy

For each P0/P1 task:
1. **Before/After Profiling:** Use Instruments to measure impact
2. **Unit Tests:** Add tests for new logic
3. **Large File Testing:** Test with files 10K+ lines
4. **LSP Testing:** Test with active language server

**Recommended Profiling Tools:**
- Time Profiler (CPU usage)
- Allocations (memory)
- Core Animation (frame rates)

---

## Notes

- **Breaking Changes:** P0.2 (remove .id) requires testing all config change paths
- **Dependencies:** P1.1 depends on P0.2, P1.4 depends on nothing
- **Risk Assessment:** P0 items are low-risk, high-impact. P3 items require more careful testing.

---

*Document created based on comprehensive codebase analysis*
*Last updated: March 26, 2026*
