#!/usr/bin/env bash
#
# check-deps.sh — report which Rosewood build-time and optional runtime tools are
# installed, and how to install the ones that are missing. Optional runtime tools
# only enable the matching feature (LSP, debugging, search, Docker); the editor
# degrades gracefully without them. See docs/dependencies.md.
#
# Usage: scripts/check-deps.sh   (or: task doctor)

set -uo pipefail

if [ -t 1 ]; then
  green=$'\033[32m'; red=$'\033[31m'; yellow=$'\033[33m'; dim=$'\033[2m'; bold=$'\033[1m'; reset=$'\033[0m'
else
  green=""; red=""; yellow=""; dim=""; bold=""; reset=""
fi

present=0
missing_required=0
missing_optional=0

# mark <label> <ok:0|1> <required:yes|no> <hint>
mark() {
  local label="$1" found="$2" required="$3" hint="$4"
  if [ "$found" -eq 1 ]; then
    printf "  ${green}✓${reset} %-30s\n" "$label"
    present=$((present + 1))
  elif [ "$required" = "yes" ]; then
    printf "  ${red}✗${reset} %-30s ${red}REQUIRED${reset} ${dim}— %s${reset}\n" "$label" "$hint"
    missing_required=$((missing_required + 1))
  else
    printf "  ${yellow}○${reset} %-30s ${dim}optional — %s${reset}\n" "$label" "$hint"
    missing_optional=$((missing_optional + 1))
  fi
}

has_cmd()   { command -v "$1" >/dev/null 2>&1 && echo 1 || echo 0; }
has_xcrun() { xcrun --find "$1" >/dev/null 2>&1 && echo 1 || echo 0; }

echo
echo "${bold}Rosewood — dependency check${reset}"
echo
echo "${bold}Build-time${reset}"
mark "Xcode (xcodebuild)" "$(has_cmd xcodebuild)" yes "install Xcode 16+ from the App Store"
mark "XcodeGen"           "$(has_cmd xcodegen)"   yes "brew install xcodegen"
mark "go-task (task)"     "$(has_cmd task)"       no  "brew install go-task"
mark "SwiftLint"          "$(has_cmd swiftlint)"  no  "brew install swiftlint"

echo
echo "${bold}Runtime — version control & search${reset}"
mark "git"                "$(has_cmd git)"        no  "xcode-select --install"
mark "ripgrep (rg)"       "$(has_cmd rg)"         no  "brew install ripgrep (search falls back to a built-in scanner)"

echo
echo "${bold}Runtime — debugging${reset}"
mark "lldb-dap"           "$(has_xcrun lldb-dap)" no  "ships with Xcode / LLVM"

echo
echo "${bold}Runtime — language servers (LSP)${reset}"
mark "sourcekit-lsp (Swift)"               "$(has_xcrun sourcekit-lsp)"            no "ships with Xcode"
mark "clangd (C/C++)"                      "$([ "$(has_xcrun clangd)" = 1 ] || [ "$(has_cmd clangd)" = 1 ] && echo 1 || echo 0)" no "ships with Xcode, or brew install llvm"
mark "pylsp (Python)"                      "$(has_cmd pylsp)"                      no "pipx install python-lsp-server"
mark "typescript-language-server (TS/JS)"  "$(has_cmd typescript-language-server)" no "npm i -g typescript-language-server typescript"
mark "gopls (Go)"                          "$(has_cmd gopls)"                      no "go install golang.org/x/tools/gopls@latest"
mark "rust-analyzer (Rust)"                "$(has_cmd rust-analyzer)"              no "rustup component add rust-analyzer"
mark "intelephense (PHP)"                  "$(has_cmd intelephense)"               no "npm i -g intelephense"

echo
echo "${bold}Runtime — containers${reset}"
mark "docker"             "$(has_cmd docker)"     no  "brew install --cask docker (Docker Desktop)"

echo
echo "${bold}Summary:${reset} ${green}${present} present${reset}, ${yellow}${missing_optional} optional missing${reset}, ${red}${missing_required} required missing${reset}"
if [ "$missing_required" -gt 0 ]; then
  echo "${red}Some required build tools are missing — see hints above.${reset}"
  exit 1
fi
echo "${dim}Optional tools only enable their matching feature; the editor works without them.${reset}"
echo
