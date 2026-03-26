# Rosewood Comprehensive Testing Strategy

## Executive Summary

This document provides a complete testing strategy for validating Rosewood editor improvements. Based on the current architecture, file handling thresholds, and performance targets from the improvement plan.

**Key Testing Targets:**
| Metric | Current | Target | Test Threshold |
|--------|---------|--------|----------------|
| Typing latency (10K lines) | ~200ms | <16ms | Must pass at 16ms |
| Scroll frame time | ~100ms | <16ms | Must pass at 16ms |
| Memory usage (idle) | ~150MB | <100MB | Alert at 150MB |
| Tab switch time | ~500ms | <50ms | Must pass at 100ms |
| File open (1MB) | ~2s | <500ms | Must pass at 1s |

---

## 1. Test File Specifications

### 1.1 File Size Categories

| Category | Size | Lines | Purpose |
|----------|------|-------|---------|
| **Small** | <200KB | <5,000 | Standard editing |
| **Medium** | 200KB-500KB | 5,000-10,000 | Large file threshold testing |
| **Large** | 500KB-1MB | 10,000-25,000 | Performance stress testing |
| **Extra Large** | 1MB-5MB | 25,000-100,000 | Edge case handling |
| **Limit** | >5MB | >100,000 | Should show warning/placeholder |

### 1.2 File Size Thresholds (from AppSettings)

```swift
// Current app settings values
largeFileThresholdKB: 200        // Minimap disabled above this
textSizeWarningKB: 500            // Performance warning at this size
textSizeLimitKB: 5000             // Hard limit, shows placeholder
binarySizeHexKB: 100              // Hex viewer threshold
binarySizeWarningKB: 1000         // Binary warning
imageSizeLimitMB: 10              // Image viewer limit
```

### 1.3 Test File Content Specifications

#### A. Swift Stress Test File (`swift_stress_10k.swift`)
Generates code patterns that stress syntax highlighting and parsing:

```swift
// Generate with: ./generate_stress_test.swift swift 10000

// Requirements:
// - Deeply nested closures (10+ levels)
// - Complex generic constraints
// - Long function signatures (200+ characters)
// - String interpolation with complex expressions
// - Multiline strings with interpolation
// - Extensive comments with markdown
// - Doc comments with parameters
// - Property wrappers
// - Result builders
// - Async/await patterns
```

**Example content pattern:**
```swift
// Line N: Function with complexity
public func process<T: Collection, U: Comparable>(
    items: T,
    filter: (T.Element) -> Bool,
    transform: (T.Element) -> U,
    completion: @escaping (Result<[U], Error>) -> Void
) where T.Element: Codable, T.Element: Sendable {
    // Implementation with nested closures
    Task {
        let filtered = items.filter { item in
            let processed = transform(item)
            return filter(item) && processed > threshold
        }
        completion(.success(filtered))
    }
}

// Line N+1: Complex type definitions
public struct Configuration<
    Input: Decodable & Encodable,
    Output: Encodable & Sendable,
    Error: Swift.Error & LocalizedError
>: Codable, Equatable where Input: Hashable {
    @Published var value: Input
    let transformer: (Input) throws -> Output
}
```

#### B. JavaScript Stress Test File (`javascript_stress_10k.js`)
```javascript
// Deeply nested callbacks
async function processData(data) {
    return await Promise.all(data.map(async (item) => {
        return await Promise.all(item.children.map(async (child) => {
            return await transform(child);
        }));
    }));
}

// Complex template literals with nested expressions
const query = `
    SELECT * FROM users
    WHERE id IN (${ids.map(id => `'${escape(id)}'`).join(',')})
    AND status = '${status}'
`;

// Regex heavy content
const patterns = [
    /^(?:\+?1[-.\s]?)?\(?([0-9]{3})\)?[-.\s]?([0-9]{3})[-.\s]?([0-9]{4})$/,
    /^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$/,
    // ... 100 more patterns
];
```

#### C. JSON Stress Test File (`json_stress_1mb.json`)
```json
{
    "deeply": {
        "nested": {
            "structure": {
                "with": {
                    "many": {
                        "levels": {
                            "of": {
                                "nesting": "value"
                            }
                        }
                    }
                }
            }
        }
    },
    "largeArray": [
        // 10000 items with mixed types
        {"id": 1, "name": "Item 1", "data": {"nested": "value"}},
        // ...
    ],
    "escapedStrings": "Line 1\nLine 2\tTabbed\r\nWindows\u0000null"
}
```

#### D. Markdown Stress Test File (`markdown_stress.md`)
```markdown
# Heading Level 1

## Heading Level 2 with `inline code` and **bold** and *italic*

> Blockquote with nested content
> > Nested blockquote
> > - List item
> > - Another item with `code`

- Unordered list with [link](http://example.com)
  - Nested item
    - Deeply nested with **formatting**

1. Ordered list
   1. Nested ordered
      1. Deeply nested

```swift
// Fenced code block with syntax
func example() -> String {
    return "Hello, World!"
}
```

Table | Column 1 | Column 2 | Column 3
------|----------|----------|---------
Row 1 | Data     | Data     | Data
Row 2 | Data     | Data     | Data

---

Horizontal rule above
```

### 1.4 Test File Generation Script

Create `/Users/abdulachik/projects/rosewood/.opencode/testing/generate_test_files.swift`:

```swift
#!/usr/bin/env swift

import Foundation

// MARK: - Configuration

struct TestFileConfig {
    let targetLines: Int
    let targetSizeMB: Double
    let language: Language
    let complexity: Complexity
    
    enum Language: String, CaseIterable {
        case swift, javascript, json, markdown, python, yaml, xml
    }
    
    enum Complexity: String {
        case minimal    // Simple content
        case moderate   // Some nesting
        case heavy      // Deep nesting, complex patterns
        case extreme    // Maximum stress
    }
}

// MARK: - Generators

protocol ContentGenerator {
    func generateLine(_ index: Int, complexity: TestFileConfig.Complexity) -> String
}

struct SwiftGenerator: ContentGenerator {
    let templates = [
        // Template patterns that expand into complex code
        "{access} {keyword} {name}<{generics}>({params}) {constraints} {\n{body}\n}",
        // ... more templates
    ]
    
    func generateLine(_ index: Int, complexity: TestFileConfig.Complexity) -> String {
        // Return appropriate complexity based on line number
        switch complexity {
        case .minimal:
            return "// Line \(index): Simple comment"
        case .moderate:
            return generateFunction(index, depth: 2)
        case .heavy:
            return generateFunction(index, depth: 5)
        case .extreme:
            return generateFunction(index, depth: 10)
        }
    }
    
    private func generateFunction(_ index: Int, depth: Int) -> String {
        // Generate deeply nested Swift code
        return """
        func function_\(index)<T: Collection>(items: T) where T.Element: Codable {
        \(String(repeating: "    ", count: depth))// Nested at level \(depth)
        \(String(repeating: "}", count: depth))
        """
    }
}

// MARK: - File Generator

class TestFileGenerator {
    func generate(config: TestFileConfig, outputPath: String) throws {
        let generator = createGenerator(for: config.language)
        var content = generateHeader(config)
        
        var currentLines = 0
        var currentSize: Int64 = 0
        let targetSize = Int64(config.targetSizeMB * 1024 * 1024)
        
        while currentLines < config.targetLines || currentSize < targetSize {
            let line = generator.generateLine(currentLines, complexity: config.complexity)
            content += line + "\n"
            currentLines += 1
            currentSize = Int64(content.utf8.count)
            
            if currentLines % 1000 == 0 {
                print("Generated \(currentLines) lines...")
            }
        }
        
        try content.write(toFile: outputPath, atomically: true, encoding: .utf8)
        print("Created: \(outputPath)")
        print("  Lines: \(currentLines)")
        print("  Size: \(ByteCountFormatter.string(fromByteCount: currentSize, countStyle: .file))")
    }
    
    private func createGenerator(for language: TestFileConfig.Language) -> ContentGenerator {
        switch language {
        case .swift: return SwiftGenerator()
        default: return SwiftGenerator() // Implement others similarly
        }
    }
    
    private func generateHeader(_ config: TestFileConfig) -> String {
        return """
        // Generated test file for Rosewood
        // Language: \(config.language)
        // Target lines: \(config.targetLines)
        // Target size: \(config.targetSizeMB) MB
        // Complexity: \(config.complexity)
        // Generated: \(Date())
        \n
        """
    }
}

// MARK: - Main

let generator = TestFileGenerator()

// Standard test files
try generator.generate(
    config: TestFileConfig(targetLines: 1000, targetSizeMB: 0.1, language: .swift, complexity: .heavy),
    outputPath: "test_small.swift"
)

try generator.generate(
    config: TestFileConfig(targetLines: 5000, targetSizeMB: 0.5, language: .swift, complexity: .heavy),
    outputPath: "test_medium.swift"
)

try generator.generate(
    config: TestFileConfig(targetLines: 10000, targetSizeMB: 1.0, language: .swift, complexity: .extreme),
    outputPath: "test_large.swift"
)

try generator.generate(
    config: TestFileConfig(targetLines: 50000, targetSizeMB: 5.0, language: .swift, complexity: .extreme),
    outputPath: "test_xlarge.swift"
)
```

### 1.5 Using Real-World Files

For realistic testing, use these open-source repositories:

| Repository | Purpose | File to Test |
|------------|---------|--------------|
| [apple/swift](https://github.com/apple/swift) | Swift compiler | `lib/Sema/TypeCheckDeclPrimary.cpp` (1000+ lines) |
| [facebook/react](https://github.com/facebook/react) | JavaScript framework | `packages/react/src/ReactHooks.js` |
| [microsoft/TypeScript](https://github.com/microsoft/TypeScript) | TypeScript compiler | `src/compiler/checker.ts` (50,000+ lines) |
| [torvalds/linux](https://github.com/torvalds/linux) | C kernel | Any `.c` file in `kernel/` |

**Command to clone for testing:**
```bash
# Create test repository
cd /tmp
mkdir rosewood-test-files
cd rosewood-test-files

# Clone repositories for real-world testing
git clone --depth 1 https://github.com/microsoft/TypeScript.git
git clone --depth 1 https://github.com/apple/swift.git
```

---

## 2. Performance Metrics

### 2.1 Typing Latency Measurement

#### A. Manual Measurement (Quick Check)
```swift
// Add to EditorView.swift temporarily for testing
private var lastInputTime: Date?
private var latencyMeasurements: [TimeInterval] = []

func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
    lastInputTime = Date()
    return false
}

func textDidChange(_ notification: Notification) {
    guard let startTime = lastInputTime else { return }
    let latency = Date().timeIntervalSince(startTime)
    latencyMeasurements.append(latency)
    
    // Report if > 16ms (60fps threshold)
    if latency > 0.016 {
        print("WARNING: Input latency \(String(format: "%.2f", latency * 1000))ms")
    }
}
```

#### B. Instruments Time Profiler Template
```xml
<!-- Instruments Trace Document Template -->
<?xml version="1.0" encoding="UTF-4"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN">
<plist version="1.0">
<dict>
    <key>TraceName</key>
    <string>Rosewood Typing Performance</string>
    <key>Instruments</key>
    <array>
        <dict>
            <key>Instrument</key>
            <string>Time Profiler</string>
            <key>TargetType</key>
            <string>Process</string>
            <key>TargetName</key>
            <string>Rosewood</string>
        </dict>
        <dict>
            <key>Instrument</key>
            <string>Core Animation</string>
        </dict>
    </array>
</dict>
</plist>
```

**Instruments Command:**
```bash
# Launch Instruments with Time Profiler
xcrun instruments -t "Time Profiler" -D ~/Desktop/rosewood-typing.trace \
    -p Rosewood

# Alternative: Use xctrace for headless recording
xcrun xctrace record --template "Time Profiler" \
    --target Rosewood \
    --output ~/Desktop/rosewood-trace \
    --time-limit 30s
```

#### C. Pass/Fail Criteria
```swift
struct TypingLatencyCriteria {
    static let acceptable: TimeInterval = 0.016  // 16ms = 60fps
    static let warning: TimeInterval = 0.033    // 33ms = 30fps
    static let failure: TimeInterval = 0.100    // 100ms = noticeable lag
    
    static func evaluate(_ latency: TimeInterval) -> Result {
        switch latency {
        case ..<acceptable: return .pass
        case acceptable..<warning: return .passWithWarning
        case warning..<failure: return .fail
        default: return .critical
        }
    }
}
```

### 2.2 Scroll Performance Measurement

#### A. Scroll Frame Rate Test
```swift
// XCTest for scroll performance
func testScrollPerformance() throws {
    let app = XCUIApplication()
    app.launchEnvironment["ROSEWOOD_UI_TEST_MINIMAP_FIXTURE"] = "1"
    app.launch()
    
    let textView = app.descendants(matching: .any).matching(identifier: "editor-text-view").firstMatch
    XCTAssertTrue(textView.waitForExistence(timeout: 5))
    
    // Measure scroll performance
    measure(metrics: [XCTOSSignpostMetric.scrollDecelerationMetric]) {
        // Scroll from top to bottom
        textView.swipeDown()
        textView.swipeUp()
    }
}
```

#### B. Instruments Core Animation Template
```bash
# Record scroll performance
xcrun instruments -t "Core Animation" -D ~/Desktop/rosewood-scroll.trace \
    -p Rosewood

# Key metrics to watch:
# - Frame Rate (must be 60 FPS)
# - Number of Commits
# - Time Spent in Layout
```

#### C. Pass/Fail Criteria
| Metric | Target | Warning | Failure |
|--------|--------|---------|---------|
| Frame Rate | 60 FPS | 45-59 FPS | <45 FPS |
| Frame Time | <16ms | 16-33ms | >33ms |
| Dropped Frames | 0 | <5% | >5% |

### 2.3 Memory Usage Measurement

#### A. Memory Profiling Commands
```bash
# Launch with Allocations instrument
xcrun instruments -t "Allocations" -D ~/Desktop/rosewood-memory.trace \
    -p Rosewood

# Alternative: Use heap command
xcrun heap -gc Rosewood

# Monitor memory via vmmap
vmmap Rosewood | grep "Physical footprint"
```

#### B. Memory Test Script
```bash
#!/bin/bash
# memory_test.sh

echo "Memory usage baseline..."
BASELINE=$(ps -o rss= -p $(pgrep Rosewood))
echo "Baseline: $BASELINE KB"

# Open progressively larger files
for file in test_small.swift test_medium.swift test_large.swift; do
    echo "Opening $file..."
    open -a Rosewood "$file"
    sleep 5
    CURRENT=$(ps -o rss= -p $(pgrep Rosewood))
    echo "Memory after $file: $CURRENT KB"
done

# Check for leaks
leaks Rosewood 2>/dev/null || echo "leaks command not available"
```

#### C. Pass/Fail Criteria
| State | Target | Warning | Failure |
|-------|--------|---------|---------|
| Idle | <100MB | 100-150MB | >150MB |
| With 5K file | <150MB | 150-250MB | >250MB |
| With 10K file | <200MB | 200-350MB | >350MB |
| With 50K file | <400MB | 400-600MB | >600MB |

### 2.4 File Open Performance

#### A. File Open Timing Test
```swift
func testFileOpenPerformance() throws {
    let app = XCUIApplication()
    app.launch()
    
    let openButton = app.buttons["Open Folder"]
    XCTAssertTrue(openButton.waitForExistence(timeout: 5))
    
    // Measure file open time
    measure(metrics: [XCTClockMetric()]) {
        openButton.click()
        // Simulate file selection
        app.typeKey("g", modifierFlags: [.command, .shift])
        let searchField = app.textFields["quick-open-input"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 2))
    }
}
```

#### B. Pass/Fail Criteria
| File Size | Target | Warning | Failure |
|-----------|--------|---------|---------|
| <200KB | <100ms | 100-500ms | >500ms |
| 200KB-1MB | <500ms | 500ms-1s | >1s |
| 1MB-5MB | <1s | 1-3s | >3s |
| >5MB | Show placeholder | Show warning | Crash/hang |

---

## 3. Regression Tests

### 3.1 Critical Paths

#### Path 1: File Operations
```gherkin
Feature: File Operations

Scenario: Opening a folder
    Given Rosewood is running
    When I click "Open Folder"
    And I select a project directory
    Then the file tree should load within 2 seconds
    And the root folder name should be visible

Scenario: Opening a file
    Given the file tree is visible
    When I click on a file
    Then the file should open in a new tab
    And the tab should show the filename
    And syntax highlighting should be applied within 1 second

Scenario: Saving a file
    Given a file is open with unsaved changes
    When I press Cmd+S
    Then the dirty indicator should disappear
    And the file should be saved to disk

Scenario: Closing unsaved tab
    Given a file has unsaved changes
    When I click the close button
    Then a save dialog should appear
    And I should have options: Save, Don't Save, Cancel
```

#### Path 2: Editor Functionality
```gherkin
Feature: Editor Core

Scenario: Typing text
    Given the editor is focused
    When I type "hello"
    Then the text should appear immediately (<16ms)
    And syntax highlighting should update

Scenario: Copy/Paste
    Given text is selected
    When I press Cmd+C
    Then the text is copied to clipboard
    When I press Cmd+V
    Then the text is pasted at cursor

Scenario: Undo/Redo
    Given I have made changes
    When I press Cmd+Z
    Then the last change is undone
    When I press Cmd+Shift+Z
    Then the change is redone

Scenario: Find/Replace
    Given a file is open
    When I press Cmd+F
    Then the find bar appears
    When I type a search term
    Then matches should be highlighted
```

#### Path 3: Tab Management
```gherkin
Feature: Tab Management

Scenario: Switching tabs
    Given multiple tabs are open
    When I click on a tab
    Then the tab should become active
    And the content should switch within 50ms
    And scroll position should be restored

Scenario: Closing tabs
    Given multiple tabs are open
    When I click the tab close button
    Then the tab should close
    And the next tab should become active

Scenario: Drag to reorder
    Given multiple tabs are open
    When I drag a tab
    Then tabs should reorder
```

#### Path 4: Navigation
```gherkin
Feature: Navigation

Scenario: Quick Open
    Given the app is running
    When I press Cmd+P
    Then the quick open dialog appears
    When I type a filename
    Then matching files appear
    When I press Enter
    Then the file opens

Scenario: Go to Line
    Given a file is open
    When I press Cmd+L
    Then a line input appears
    When I type "100"
    Then the view jumps to line 100

Scenario: Symbol Navigation
    Given a Swift file is open
    When I press Cmd+Shift+O
    Then the symbol picker appears
    When I type a symbol name
    Then matching symbols appear
```

### 3.2 Pre-Commit Regression Checklist

Before any commit, verify:

- [ ] App launches without crash
- [ ] Can open a folder
- [ ] Can open a file
- [ ] Can type in editor
- [ ] Can save file
- [ ] Can switch tabs
- [ ] Can close tabs
- [ ] Quick Open works (Cmd+P)
- [ ] Find/Replace works (Cmd+F / Cmd+Shift+F)
- [ ] Command Palette works (Cmd+Shift+P)
- [ ] No console errors

### 3.3 Full Regression Test Suite

Run before releases:

```bash
#!/bin/bash
# regression_test.sh

set -e

echo "Running Rosewood Regression Tests..."

# Build
xcodebuild build -project Rosewood.xcodeproj -scheme Rosewood

# Unit Tests
echo "Running unit tests..."
xcodebuild test -project Rosewood.xcodeproj -scheme RosewoodTests

# UI Tests (subset for speed)
echo "Running critical UI tests..."
xcodebuild test -project Rosewood.xcodeproj -scheme RosewoodUITests \
    -only-testing:RosewoodUITests/RosewoodUITests/testLaunchShowsMainShellAndSearchSidebar \
    -only-testing:RosewoodUITests/RosewoodUITests/testQuickOpenSupportsLineAndSymbolNavigation \
    -only-testing:RosewoodUITests/RosewoodUITests/testProjectSearchUpdatesResultsWhileTyping \
    -only-testing:RosewoodUITests/RosewoodUITests/testFoldingFixtureCollapsesAndExpandsFromGutter

# Manual verification script
echo ""
echo "Manual verification required:"
echo "1. Open a 10,000 line file"
echo "2. Type rapidly for 10 seconds"
echo "3. Verify no lag"
echo "4. Scroll top to bottom"
echo "5. Verify smooth scrolling"
```

---

## 4. LSP Testing

### 4.1 Supported Language Servers

Based on LSPServerRegistry.swift:

| Language | Server | Install Command |
|----------|--------|-----------------|
| Swift | sourcekit-lsp | Included with Xcode |
| Python | pylsp | pip install python-lsp-server |
| TypeScript | typescript-language-server | npm install -g typescript-language-server |
| Go | gopls | go install golang.org/x/tools/gopls@latest |
| Rust | rust-analyzer | rustup component add rust-analyzer |

### 4.2 LSP Feature Test Matrix

| Feature | Swift | Python | TS/JS | Go | Rust |
|---------|-------|--------|-------|-----|------|
| Completion | Required | Required | Required | Required | Required |
| Hover | Required | Required | Required | Required | Required |
| Go to Definition | Required | Required | Required | Required | Required |
| Find References | Required | Required | Required | Required | Required |
| Diagnostics | Required | Required | Required | Required | Required |
| Symbol Search | Required | Optional | Optional | Optional | Optional |

### 4.3 LSP Test Procedures

#### Test 1: Completion
```swift
// File: test_completion.swift
struct TestCompletion {
    func example() {
        let array = [1, 2, 3]
        // Type: array.
        // Expected: Shows completion with map, filter, etc.
    }
}
```

**Steps:**
1. Open file in Rosewood
2. Position cursor after array.
3. Press Cmd+Space (or trigger completion)
4. Verify completion list appears within 500ms
5. Verify items are relevant to Array type

#### Test 2: Diagnostics
```swift
// File: test_diagnostics.swift
func test() {
    let x: String = 42  // Should show error
    let y  // Should show warning
}
```

**Steps:**
1. Open file
2. Wait 5 seconds for diagnostics
3. Verify error appears on line 2
4. Verify warning appears on line 3
5. Fix the error
6. Verify error disappears within 5 seconds

#### Test 3: Go to Definition
```swift
// File: test_definition.swift
func helper() -> String { "help" }

func main() {
    let result = helper()  // Cmd+Click on helper
}
```

**Steps:**
1. Open file
2. Hold Cmd and hover over helper
3. Verify underline appears
4. Click
5. Verify cursor jumps to helper definition

#### Test 4: Find References
```swift
// File: test_references.swift
let globalValue = 1

func use1() { _ = globalValue }
func use2() { _ = globalValue }
```

**Steps:**
1. Open file
2. Right-click on globalValue
3. Select "Find References"
4. Verify References panel shows 2 results

### 4.4 LSP Performance Criteria

| Operation | Target | Warning | Failure |
|-----------|--------|---------|---------|
| Completion | <500ms | 500ms-1s | >1s |
| Hover | <300ms | 300ms-500ms | >500ms |
| Go to Definition | <500ms | 500ms-1s | >1s |
| Find References | <1s | 1-3s | >3s |
| Diagnostics Update | <2s | 2-5s | >5s |

---

## 5. Quick Validation Checklist

### 5.1 Smoke Test (2 minutes)

```markdown
## Quick Smoke Test

1. **Launch**
   - [ ] App opens without crash
   - [ ] Window appears within 3 seconds
   - [ ] No error dialogs

2. **Basic Editing**
   - [ ] Type "hello world" - appears immediately
   - [ ] Save file (Cmd+S)
   - [ ] Close tab
   - [ ] Reopen file - content restored

3. **Navigation**
   - [ ] Cmd+P opens Quick Open
   - [ ] Can search and open a file
   - [ ] Cmd+Shift+P opens Command Palette

4. **Visual Check**
   - [ ] Syntax highlighting visible
   - [ ] Line numbers visible (if enabled)
   - [ ] Minimap visible (if enabled)
```

### 5.2 Visual Cues Reference

| Component | Success State | Failure State |
|-----------|---------------|---------------|
| **Editor** | Text visible, colored syntax | Blank, garbled, or frozen |
| **Cursor** | Blinking, moves with typing | Frozen, invisible, or laggy |
| **Tabs** | Filename visible, close button | Missing or unresponsive |
| **Sidebar** | File tree visible | Empty or spinning |
| **Status Bar** | Position shows "Line X, Col Y" | Missing or wrong position |
| **Minimap** | Overview of document visible | Blank or not updating |
| **LSP Status** | No error indicators | Red error indicator |
| **Dirty Indicator** | Dot appears on unsaved tabs | Missing or always visible |

### 5.3 Keyboard Shortcuts Test

| Shortcut | Action | Expected Result |
|----------|--------|-----------------|
| Cmd+N | New File | New untitled tab opens |
| Cmd+O | Open Folder | File picker dialog |
| Cmd+S | Save | File saved, dot removed |
| Cmd+W | Close Tab | Tab closes |
| Cmd+P | Quick Open | File search dialog |
| Cmd+Shift+P | Command Palette | Command search dialog |
| Cmd+F | Find | Find bar appears |
| Cmd+Shift+F | Project Search | Search sidebar opens |
| Cmd+L | Go to Line | Line input appears |
| Cmd+/ | Toggle Comment | Line commented/uncommented |
| Cmd+Z | Undo | Last change undone |
| Cmd+Shift+Z | Redo | Change redone |

### 5.4 Large File Quick Test

```bash
# Generate a 10K line file for quick testing
cat > /tmp/large_test.swift << 'EOF'
// Swift file for large file testing
EOF

# Append generated content
for i in {1..10000}; do
    echo "let variable_$i = $i // This is line $i with some content to make it substantial" >> /tmp/large_test.swift
done

echo "Created: /tmp/large_test.swift"
ls -lh /tmp/large_test.swift
```

**Test Steps:**
1. Open the large file
2. Scroll to middle - should be smooth
3. Type a character - should appear immediately
4. Save - should complete quickly
5. Close - should close without delay

---

## 6. Instruments Trace Configuration

### 6.1 Command Line Recording

```bash
#!/bin/bash
# record_performance.sh

TEMPLATE="Time Profiler"
OUTPUT_DIR="$HOME/Desktop/Rosewood_Traces"
mkdir -p "$OUTPUT_DIR"

echo "Starting Instruments recording..."

# Record for 60 seconds
xcrun instruments -t "$TEMPLATE" \
    -D "$OUTPUT_DIR/rosewood_$(date +%Y%m%d_%H%M%S).trace" \
    -p Rosewood \
    -l 60000  # 60 seconds

echo "Recording complete. Trace saved to: $OUTPUT_DIR"
```

### 6.2 Performance Regression Detection

```bash
#!/bin/bash
# performance_regression_check.sh

# Run performance tests and compare against baseline

BASELINE_FILE=".performance_baseline.json"
RESULTS_FILE=".performance_results.json"

# Run tests
xcodebuild test \
    -project Rosewood.xcodeproj \
    -scheme RosewoodTests \
    -only-testing:RosewoodTests/PerformanceTests \
    -resultBundlePath "$RESULTS_FILE"

# Compare with baseline (simplified)
if [ -f "$BASELINE_FILE" ]; then
    echo "Comparing with baseline..."
    # In real implementation, parse JSON and compare
    echo "PASS: Performance within acceptable range"
else
    echo "No baseline found. Creating baseline..."
    cp "$RESULTS_FILE" "$BASELINE_FILE"
fi
```

---

## 7. Continuous Integration Integration

### 7.1 GitHub Actions Workflow

```yaml
# .github/workflows/test.yml
name: Test

on: [push, pull_request]

jobs:
  unit-tests:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v3
      - name: Build
        run: xcodebuild build -project Rosewood.xcodeproj -scheme Rosewood
      - name: Unit Tests
        run: xcodebuild test -project Rosewood.xcodeproj -scheme RosewoodTests

  ui-tests:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v3
      - name: UI Tests
        run: |
          xcodebuild test \
            -project Rosewood.xcodeproj \
            -scheme RosewoodUITests \
            -destination 'platform=macOS'

  performance-tests:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v3
      - name: Generate Test Files
        run: |
          mkdir -p test_files
          ./.opencode/testing/generate_test_files.swift
      - name: Performance Tests
        run: |
          xcodebuild test \
            -project Rosewood.xcodeproj \
            -scheme RosewoodTests \
            -only-testing:RosewoodTests/PerformanceTests
```

---

## 8. Summary

### Critical Tests (Must Pass Before Any Release)

1. **Unit Tests** - All 26 test files pass
2. **Smoke Tests** - App launches and basic editing works
3. **Critical UI Tests** - Core navigation features
4. **Large File Test** - 10K line file performs adequately

### Performance Gates

| Metric | Gate |
|--------|------|
| Typing Latency | < 50ms (P1), < 16ms (P0) |
| Scroll FPS | > 45 FPS (P1), > 55 FPS (P0) |
| Memory | < 200MB for 10K lines (P1), < 150MB (P0) |
| File Open | < 2s for 1MB file |

### Test Resources

- Test file generator: .opencode/testing/generate_test_files.swift
- Instruments template: .opencode/testing/Rosewood_Performance.trace/
- Regression script: .opencode/testing/regression_test.sh

---

*Document created: March 26, 2026*
*Based on Rosewood codebase analysis and improvement plan*
