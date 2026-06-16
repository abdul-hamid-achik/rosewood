# Troubleshooting

Most "feature X isn't working" cases come down to a missing optional tool. Run **`task doctor`**
(or `./scripts/check-deps.sh`) first — it lists what's installed and how to install the rest.
See [Dependencies](dependencies.md) for details.

## A feature isn't working

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| Autocomplete / go-to-definition / hover / find-references do nothing | No language server for that language | Install the matching server ([Dependencies → Language tooling](dependencies.md#language-tooling-language-servers-lsp)); the status bar shows the language-server state. After installing, run **Restart Language Server** from the command palette. |
| Project-wide search feels slow | ripgrep not installed | `brew install ripgrep` (search otherwise uses a slower built-in scanner) |
| Source Control sidebar says **"Git Not Available"** | `git` not on your `PATH` | `xcode-select --install` |
| Source Control says **"Not a Git Repository"** | The open folder has no `.git` | Open a folder that is a git repository, or run `git init` there |
| Docker panel is empty or **"Docker Disconnected"** | Docker not installed, or the daemon isn't running | Install Docker Desktop and start it, then press Refresh |
| A diff shows **"Couldn't Load Diff"** | git couldn't produce the diff (repo state changed) | Use the Refresh action / refresh Git status |
| A Settings toggle didn't take effect | — | Editor toggles (line numbers, minimap, word wrap, tab size), font, and theme apply live. If something still looks stale, switch tabs to force a refresh. |

## App won't open ("unidentified developer")

Local/debug builds are ad-hoc signed, so Gatekeeper may block a double-click. Right-click the app
→ **Open** the first time, or build and install it yourself (`task install`). A distributed,
notarized build is required to remove this prompt for other users.

## Known limitations (on the roadmap)

These are intentionally incomplete today — the editor is honest about them in the UI rather than
failing silently:

- **Debugger** supports launching, breakpoints, and console output, but **not yet** execution
  control — continue/resume, step over/into/out, variable inspection, or the call stack. A
  breakpoint currently pauses execution; resuming/stepping is planned.
- **Integrated terminal** is a placeholder — an interactive PTY terminal is planned. Docker
  "Open Terminal" / compose-exec depend on it.
- **Git** supports status, diff, blame, stage/unstage/discard, and **commit**, but **not yet**
  push / pull / fetch with a remote.
- **Semantic-token highlighting** (LSP) is not yet applied in the editor; syntax highlighting via
  Highlightr is always on.

See the project's README roadmap for the broader plan (AI assistance, split panes, plugins).

## Build / development issues

| Symptom | Fix |
|---------|-----|
| `xcodegen: command not found` | `brew install xcodegen`, then `task gen` |
| `task: command not found` | `brew install go-task` (or run the `xcodebuild` commands directly) |
| Tests don't run / `import Testing` fails | Use **Xcode 16+** — swift-testing isn't in Xcode 15 |
| The Xcode project looks stale after adding files | Re-run `task gen` (`xcodegen generate`) |

Run `task doctor` to confirm your toolchain in one shot.
