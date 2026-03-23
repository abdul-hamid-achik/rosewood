# Rosewood - AGENTS.md

## Project Overview

**Rosewood** is a native macOS code editor built with Swift and SwiftUI/AppKit. It provides a VS Code-like editing experience with syntax highlighting, multi-tab editing, file tree navigation, project-wide search, and a command palette.

- **Language:** Swift 5.9
- **Platform:** macOS 14.0+
- **Architecture:** MVVM with `@MainActor` ViewModels
- **UI Framework:** Hybrid SwiftUI + AppKit (using `NSViewRepresentable`/`NSViewControllerRepresentable` bridges)

---

## Directory Structure

```
Sources/
├── App/           # App entry point (main.swift, RosewoodApp.swift)
├── Models/        # Data models (EditorTab, FileItem)
├── ViewModels/    # Observable ViewModels (ProjectViewModel)
├── Views/         # SwiftUI views and AppKit bridges
├── Services/      # Singletons (FileService, HighlightService)
├── Utilities/     # Extensions and helpers
Tests/             # Unit tests (Swift Testing framework)
UITests/           # UI tests (XCTest)
Resources/         # Assets, entitlements
```

---

## Build & Test Commands

### Build the project
```bash
xcodebuild build -project Rosewood.xcodeproj -scheme Rosewood
```

### Run all tests
```bash
xcodebuild test -project Rosewood.xcodeproj -scheme Rosewood
```

### Run unit tests only
```bash
xcodebuild test -project Rosewood.xcodeproj -scheme RosewoodTests
```

### Run UI tests only
```bash
xcodebuild test -project Rosewood.xcodeproj -scheme RosewoodUITests
```

### Regenerate Xcode project (after modifying project.yml)
```bash
xcodegen generate
```

### Build for release
```bash
xcodebuild build -project Rosewood.xcodeprod -scheme Rosewood -configuration Release
```

---

## Testing Guidelines

### Always verify your work with tests

Before considering any change complete, ensure:
1. All existing tests pass
2. New functionality is covered by unit tests
3. UI changes are tested via the UITest framework

### Testing Framework

- **Unit Tests:** Swift Testing (`@Test` attribute, `#expect` assertions)
- **UI Tests:** XCTest (`XCUIApplication`, `accessibilityIdentifier`)

### Test Conventions

- Test structs are named `{Component}Tests` (e.g., `FileServiceTests`)
- Use `try`/`throw` for error handling in tests
- Create unique temporary files using `UUID().uuidString`
- Always clean up temporary resources with `defer`

### Running Specific Tests

```bash
# Run a specific test suite
xcodebuild test -project Rosewood.xcodeproj -scheme RosewoodTests -only-testing:Tests/FileServiceTests

# Reset UI test session state
ROSEWOOD_UI_TEST_RESET_SESSION="1" xcodebuild test ...
```

---

## Code Style & Conventions

### Naming
- **Types/Classes:** PascalCase (`ProjectViewModel`, `FileService`)
- **Methods/Properties:** camelCase (`openTabs`, `selectedTabIndex`)
- **Private members:** lowercase with underscore suffix where needed

### Import Organization
```swift
import Foundation       // Standard library
import AppKit           // macOS AppKit
import SwiftUI          // SwiftUI
import Highlightr       // Third-party syntax highlighting
```

### Patterns
- **Services:** Singleton pattern with `static let shared` and `private init()`
- **ViewModels:** `@MainActor` classes conforming to `ObservableObject`
- **Views:** `struct` conforming to `View`
- **Models:** Simple structs/classes

### SwiftUI Conventions
- Use `some View` for computed `body` properties
- Use `@EnvironmentObject` for dependency injection
- Use `@State` for local state, `@Binding` for two-way data flow
- Use `DispatchQueue.main.async` for thread-safe ViewModel updates

---

## UI/UX Guidelines

### Nord Theme (Artic Studio Components)

All UI components throughout the application use the **Nord color palette** for consistency and a unified aesthetic. The Nord theme is applied via:

- **`HighlightService.shared.themeColors()`** - Provides the `ThemeColors` struct with all Nord colors
- Components reference `HighlightService.shared.themeColors` for theming

#### Nord Color Palette

| Token | Hex | Usage |
|-------|-----|-------|
| `background` | `#2E3440` | Main background |
| `foreground` | `#ECEFF4` | Primary text |
| `accent` | `#88C0D0` | Selection, highlights |
| `warning` | `#EBCB8B` | Warning states |
| `danger` | `#BF616A` | Error states |
| `success` | `#A3BE8C` | Success states |
| `panelBackground` | `#3B4252` | Sidebar, panels |

### Syntax Highlighting

- Uses **Highlightr** library (wraps highlight.js)
- Nordic theme is applied through `HighlightService.shared.highlightedAttributedString()`
- Supported languages: Swift, Python, Go, Ruby, JavaScript, TypeScript, YAML, JSON, Markdown, and more

---

## Key Services

### FileService (Singleton)
- All file operations: read, write, search, delete, rename
- `FileManager` enumeration for directory trees
- Hidden files (dotfiles) are excluded

### HighlightService (Singleton)
- Provides Nord theme colors via `themeColors()`
- Syntax highlighting via `highlightedAttributedString()`

---

## Session Persistence

- Uses `UserDefaults` with key `"rosewood.session"`
- Stores: root directory, expanded paths, open tabs, selected tab
- Reset UI tests with environment variable: `ROSEWOOD_UI_TEST_RESET_SESSION = "1"`

---

## Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| Highlightr | 2.2.1 | Syntax highlighting |

Dependencies are managed via **Swift Package Manager** (resolved in `project.xcworkspace`).

---

## Workflow Checklist

Before marking any change as complete:

- [ ] Code compiles without errors
- [ ] All existing tests pass (`xcodebuild test`)
- [ ] New functionality has unit test coverage
- [ ] UI changes have corresponding UITests
- [ ] No new warnings introduced
- [ ] Code follows existing naming conventions and patterns
- [ ] Regenerate Xcode project if `project.yml` was modified (`xcodegen generate`)
