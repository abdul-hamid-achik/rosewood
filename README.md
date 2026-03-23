# Rosewood

A lightweight, native macOS code editor built with Swift and SwiftUI/AppKit.

![macOS](https://img.shields.io/badge/macOS-14.0%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)
![License](https://img.shields.io/badge/license-MIT-green)

## Features

- **Multi-tab editing** with dirty state indicators and keyboard shortcuts
- **Syntax highlighting** for 20+ languages via Highlightr with switchable editor themes
- **Language tooling via LSP** with autocomplete, diagnostics, hover, go-to-definition, and find references
- **Debugger foundations via DAP** with breakpoints, launch/reset, and debug console output
- **Project-wide search & replace** with line-level results
- **In-file find & replace** with the native macOS find bar
- **File tree browser** with expand/collapse, create, rename, duplicate, and delete
- **Command palette** (Cmd+P) with fuzzy search for commands and files
- **Bracket matching** and auto-closing pairs
- **Settings UI** for font, wrapping, line numbers, auto-save, and theme selection
- **Auto-save** plus reload prompts for externally modified files
- **Multiple built-in themes** including Nord, GitHub Light, and Dracula
- **Code folding** from the editor gutter for nested brace and indentation blocks
- **Interactive minimap** with click-to-scroll document navigation
- **Session persistence** across app restarts
- **Line numbers** with gutter divider, breakpoints, and fold controls
- **Status bar** showing cursor position, encoding, language, LSP state, and diagnostics

## Quick Start

### Prerequisites

- macOS 14.0+
- Xcode 15.0+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

### Build & Run

```bash
# Generate the Xcode project
xcodegen generate

# Build
xcodebuild build -scheme Rosewood -configuration Debug -destination 'platform=macOS'

# Or open in Xcode
open Rosewood.xcodeproj
```

### Run Tests

```bash
xcodebuild test -scheme RosewoodTests -destination 'platform=macOS'
```

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| Cmd+O | Open Folder |
| Cmd+N | New File |
| Cmd+S | Save |
| Cmd+W | Close Tab |
| Cmd+P | Command Palette |
| Cmd+F | Find in File |
| Cmd+Opt+F | Replace in File |
| Cmd+G | Find Next |
| Cmd+Shift+G | Find Previous |
| Cmd+Shift+F | Find in Project |
| F12 | Go to Definition |
| Shift+F12 | Find References |
| Cmd+Z | Undo |
| Cmd+Shift+Z | Redo |

## Architecture

```
Sources/
  App/                  Entry point (SwiftUI + NSApplication)
  Models/               FileItem, EditorTab
  ViewModels/           ProjectViewModel (@MainActor, single source of truth)
  Views/                SwiftUI views + NSViewRepresentable editor
  Services/             FileService (I/O), HighlightService (syntax colors)
  Utilities/            NSAlert/NSOpenPanel extensions
Tests/                  Swift Testing unit tests
UITests/                XCTest UI tests
```

**Key patterns:**
- MVVM with `@MainActor` for thread-safe state
- SwiftUI/AppKit hybrid: SwiftUI for layout, NSTextView (TextKit 1) for the editor
- Singleton services for file I/O and syntax highlighting

## Tech Stack

| Component | Technology |
|-----------|-----------|
| Language | Swift 5.9 |
| UI | SwiftUI + AppKit |
| Editor | NSTextView (TextKit 1) |
| Highlighting | [Highlightr](https://github.com/raspu/Highlightr) 2.2.1 |
| Theme | Nord, GitHub Light, Dracula |
| Build | XcodeGen + SPM |
| Testing | Swift Testing, XCTest |

## Roadmap

### Completed

- [x] Multi-tab file editing
- [x] File tree with CRUD operations
- [x] Syntax highlighting (20+ languages)
- [x] Project-wide search & replace
- [x] In-file find & replace
- [x] Command palette
- [x] Bracket matching & auto-close pairs
- [x] Line numbers with gutter
- [x] Session persistence
- [x] Status bar (cursor position, encoding, language, diagnostics, LSP status)
- [x] Nord theme throughout
- [x] Multiple themes / theme switcher
- [x] Code folding
- [x] Minimap
- [x] Settings UI
- [x] Configurable font size and font family
- [x] Auto-save
- [x] File watcher for external changes
- [x] LSP integration — autocomplete, diagnostics, go-to-definition, hover info, references
- [x] Debugger foundations — breakpoints, launch/reset, debug console, project debug configs

### Planned

- [ ] AI agent panel — inline code assistance, chat, code generation
- [ ] AI code autocomplete — ghost text suggestions, tab-to-accept, context-aware completions
- [ ] ACP (Agent Communication Protocol) support — interop with external AI agents and tools
- [ ] Git integration (branch, diff, blame)
- [ ] Terminal panel
- [ ] Split editor panes
- [ ] Extension / plugin system
- [ ] Debug stepping and inspection — continue/step in/step over, variables, call stack

## Contributing

1. Fork the repository
2. Create a feature branch
3. Run `xcodegen generate` after adding new source files
4. Ensure tests pass: `xcodebuild test -scheme RosewoodTests -destination 'platform=macOS'`
5. Submit a pull request

## License

MIT
