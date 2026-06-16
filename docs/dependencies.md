# Dependencies

Rosewood has a small set of **build-time** requirements and a larger set of **optional runtime
tools**. Optional tools are discovered on your `PATH` (or via `xcrun`) at runtime — when one is
missing, the related feature is simply unavailable or falls back, and the rest of the editor keeps
working.

## Build-time

| Tool | Why | Install |
|------|-----|---------|
| macOS 14.0+ | Minimum deployment target | — |
| Xcode 16+ | Compiler + test runner (swift-testing needs Xcode 16; building alone works on 15+) | App Store / developer.apple.com |
| XcodeGen | Generates `Rosewood.xcodeproj` from `project.yml` | `brew install xcodegen` |
| go-task *(optional)* | Runs the `Taskfile.yml` shortcuts | `brew install go-task` |
| SwiftLint *(optional)* | `task lint` / CI lint step | `brew install swiftlint` |

Swift Package dependencies (**Highlightr** for syntax highlighting, **TOMLKit** for config files)
are resolved automatically by Xcode/SPM on first build — no manual step.

## Runtime (optional) — what unlocks each feature

### Source control — `git`

Branch status, working-tree changes, unified diff, and line blame use the `git` CLI. It's included
with the **Xcode Command Line Tools**:

```bash
xcode-select --install
```

Rosewood checks for it with `git --version`; if git isn't on your `PATH`, the Source Control
sidebar shows a "Git Not Available" state.

### Faster project search — `ripgrep` (optional)

Project-wide search (`Cmd+Shift+F`) uses [ripgrep](https://github.com/BurntSushi/ripgrep) when
available and **falls back to a built-in scanner** otherwise — so it works either way, just faster
with ripgrep:

```bash
brew install ripgrep
```

### Language tooling — Language Servers (LSP)

Autocomplete, diagnostics, hover, go-to-definition, and find-references work per language when the
matching language server is installed and on your `PATH`. Rosewood launches these automatically:

| Language | Server | Typical install |
|----------|--------|-----------------|
| Swift | `sourcekit-lsp` | Bundled with Xcode (found via `xcrun`) |
| C / C++ | `clangd` | Bundled with Xcode, or `brew install llvm` |
| Python | `pylsp` | `pipx install python-lsp-server` |
| TypeScript / JavaScript | `typescript-language-server` | `npm i -g typescript-language-server typescript` |
| Go | `gopls` | `go install golang.org/x/tools/gopls@latest` |
| Rust | `rust-analyzer` | `rustup component add rust-analyzer` |
| PHP | `intelephense` | `npm i -g intelephense` |

If a server isn't installed, editing still works — you just won't get that language's LSP features,
and the status bar reflects the language-server state. After installing a server, you can re-open
the folder or use the **Restart Language Server** command from the command palette.

### Debugging — `lldb-dap`

The debugger (breakpoints, launch/reset, debug console) speaks the Debug Adapter Protocol via
`lldb-dap`, which ships with Xcode / LLVM and is located through `xcrun`. Configure what to debug in
your project's `.rosewood.toml` — see [Configuration](configuration.md#debugging).

### Containers — `docker` (optional)

The Docker panel (containers, images, compose projects, volumes, logs) uses the `docker` CLI.
Rosewood looks for it at `/usr/local/bin/docker`, `/opt/homebrew/bin/docker`, `/usr/bin/docker`, and
on your `PATH`:

```bash
brew install --cask docker   # Docker Desktop
```

When Docker isn't installed or the daemon isn't running, the Docker sidebar shows an explanatory
state with a Refresh action rather than failing silently.

## Quick "everything" setup

A typical fully-featured setup on Apple Silicon:

```bash
# Build tooling
brew install xcodegen go-task swiftlint
# Optional runtime tools
brew install ripgrep
brew install --cask docker
# Language servers you use (examples)
npm i -g typescript-language-server typescript intelephense
pipx install python-lsp-server
rustup component add rust-analyzer
# sourcekit-lsp and clangd come with Xcode; lldb-dap comes with Xcode/LLVM
```
