#!/usr/bin/env bash
# TerminalCustumization - upgrade everything on Linux to the latest versions
#
#   ./upgrade.sh [install.sh options]
#   curl -fsSL https://raw.githubusercontent.com/R3start/TerminalCustumization/main/upgrade.sh | bash
#
# 1. From a git clone: pulls the latest version of this repository (fast-forward only).
# 2. Runs install.sh, which downloads the latest release of every tool, refreshes the
#    JetBrainsMono Nerd Font and the configuration files. Your choices (default shell,
#    your own edits to rc files) are kept; changed config files are backed up first.
# 3. Prints the versions before and after.
#
# Useful options (passed to install.sh): --skip-fonts, --skip-config, --force

set -euo pipefail

{
REPO_RAW="${TC_REPO_RAW:-https://raw.githubusercontent.com/R3start/TerminalCustumization/main}"
BIN_DIR="${TC_BIN_DIR:-$HOME/.local/bin}"
TOOLS=(oh-my-posh nu eza bat rg fzf zoxide duf dust gh)

versions() {
  local t v
  for t in "${TOOLS[@]}"; do
    if [[ -x "$BIN_DIR/$t" ]]; then
      case "$t" in
        oh-my-posh) v=$("$BIN_DIR/$t" version 2>/dev/null) ;;
        *) v=$("$BIN_DIR/$t" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n1) ;;
      esac
    else
      v='-'
    fi
    printf '%s=%s\n' "$t" "${v:--}"
  done
}

before=$(versions)

SCRIPT_DIR=""
if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

if [[ -n "$SCRIPT_DIR" && -f "$SCRIPT_DIR/install.sh" ]]; then
  if command -v git >/dev/null 2>&1 && git -C "$SCRIPT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "==> Updating the repository in $SCRIPT_DIR"
    git -C "$SCRIPT_DIR" pull --ff-only </dev/null ||
      echo "  ! git pull failed (local changes?) - continuing with the current checkout" >&2
  fi
  bash "$SCRIPT_DIR/install.sh" "$@" </dev/null
else
  curl -fsSL "$REPO_RAW/install.sh" | bash -s -- "$@"
fi

after=$(versions)

echo
echo "==> Versions"
printf '  %-12s %-14s %s\n' tool before after
while IFS='=' read -r tool old; do
  new=$(grep "^$tool=" <<<"$after" | cut -d= -f2-)
  mark=''
  [[ "$old" != "$new" ]] && mark='  (upgraded)'
  printf '  %-12s %-14s %s%s\n' "$tool" "$old" "$new" "$mark"
done <<<"$before"
exit 0
}
