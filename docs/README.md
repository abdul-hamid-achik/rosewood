# Rosewood Documentation

Rosewood is a lightweight, native macOS code editor built with Swift and SwiftUI/AppKit.

These pages document how to **install**, **configure**, and **use** the editor. They are plain
Markdown so they can later be published with a static-site generator (MkDocs, Docusaurus, or
GitHub Pages) once a site and domain are added.

## Contents

| Page | What it covers |
|------|----------------|
| [Getting Started](getting-started.md) | Build, run, and install Rosewood on your Mac |
| [Dependencies](dependencies.md) | Build-time and optional runtime tools (git, ripgrep, language servers, lldb-dap, Docker) and how to install them |
| [Configuration](configuration.md) | User settings (`config.toml`) and per-project settings + debug configs (`.rosewood.toml`) |
| [Features & Usage](features.md) | Editing, search, LSP, debugging, Git, Docker, and the full keyboard-shortcut reference |
| [Troubleshooting](troubleshooting.md) | Why a feature isn't working (usually a missing tool), known limitations, and build issues |

## At a glance

- **Platform:** macOS 14.0+
- **Editor core:** `NSTextView` (TextKit 1) inside SwiftUI
- **Highlighting:** 20+ languages via Highlightr, with switchable themes (Nord, GitHub Light, Dracula)
- **Language tooling:** LSP (autocomplete, diagnostics, hover, go-to-definition, find references)
- **Debugging:** DAP foundations (breakpoints, launch/reset, debug console)
- **Source control:** Git branch/status/diff/blame
- **Extras:** project-wide search & replace, Quick Open, command palette, code folding, minimap, session persistence

> Many capabilities are **optional** and light up only when the matching external tool is
> installed (see [Dependencies](dependencies.md)). The editor degrades gracefully when a tool is
> missing — e.g. project search falls back to a built-in scanner without ripgrep.
