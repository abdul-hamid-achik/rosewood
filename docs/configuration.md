# Configuration

Rosewood reads two TOML files. Both are optional — the editor ships with sensible defaults.

| Scope | File | Purpose |
|-------|------|---------|
| **User (global)** | `~/Library/Application Support/Rosewood/config.toml` | Your personal defaults across all projects |
| **Project** | `<project-root>/.rosewood.toml` | Per-project settings overrides **and** debug configurations |

The easiest way to edit settings is the **Settings UI** (`Cmd+,`). Changes preview live and are
written back to the user config. For project settings and debug configs, use **Open Config** /
**Create Config** in the Run & Debug sidebar — "Create Config" scaffolds a valid `.rosewood.toml`
for you.

## Settings

Settings cover the editor and integrations, e.g.:

- **Editor:** font family & size, word wrap, line numbers, tab size
- **Behavior:** auto-save, large-file warning threshold (KB)
- **Appearance:** theme (Nord, GitHub Light, Dracula, …)
- **Docker:** integration toggle, socket path, terminal shell, compose scan depth, log line limit, refresh interval

A project's `.rosewood.toml` may override any of these for that folder. Prefer the Settings UI to
discover the exact keys, since the file is just the encoded settings.

## Debugging

Define debug targets in the project's `.rosewood.toml` under a `[debug]` section. Each entry maps
to a launch configuration the Run & Debug sidebar can start.

```toml
[debug]
# Name of the configuration selected by default (optional)
defaultConfiguration = "Run app"

[[debug.configurations]]
name = "Run app"          # shown in the Run & Debug picker
adapter = "lldb-dap"      # debug adapter (lldb-dap ships with Xcode/LLVM)
program = ".build/debug/MyApp"  # path to the executable to debug (relative to the project root or absolute)
cwd = "."                 # working directory (optional; defaults to the project root)
args = []                 # arguments passed to the program (optional)
preLaunchTask = "swift build"   # shell command run before launching (optional)

[[debug.configurations]]
name = "Run tests"
adapter = "lldb-dap"
program = ".build/debug/MyAppTests"
```

Notes:

- `adapter` is the Debug Adapter Protocol backend — `lldb-dap` (bundled with Xcode/LLVM, located via
  `xcrun`) is the supported adapter today.
- `cwd` is resolved relative to the project root; omit it to use the root.
- `preLaunchTask` runs before the session starts (e.g. a build), and its result is reported in the
  debug console.
- See [Dependencies → Debugging](dependencies.md#debugging--lldb-dap) for the adapter requirement,
  and [Features → Debugging](features.md#debugging-dap) for how to drive a session.

## Reloading

Both config files are watched while Rosewood is running — saving them applies changes without a
restart. Use **Reset to Defaults** in the Settings UI to revert user settings.
