#!/usr/bin/env bash
# shellcheck disable=SC2016  # nu/pwsh expressions are meant to stay unexpanded
# TerminalCustumization - uninstaller for Linux
#
#   ./uninstall.sh [options]
#   curl -fsSL https://raw.githubusercontent.com/R3start/TerminalCustumization/main/uninstall.sh | bash -s -- --yes
#
# Reverses install.sh: removes the shell configuration blocks and the configuration folder, plus the
# tools and font files that install.sh recorded as installed by it
# (~/.local/state/terminal-customization/manifest). Anything you installed yourself is left alone.
# Every edited file is backed up first (*.tc-backup-<date>).

set -euo pipefail

# One { } block: bash reads the whole script before running it (safe with `curl … | bash`).
{
BIN_DIR="${TC_BIN_DIR:-$HOME/.local/bin}"
TC_HOME="${TC_HOME:-$HOME/.config/terminal-customization}"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/terminal-customization"
MANIFEST="$STATE_DIR/manifest"
MARK_BEGIN='# >>> terminal-customization >>>'
MARK_END='# <<< terminal-customization <<<'
TOOL_BINS=(oh-my-posh nu eza bat rg fzf zoxide duf dust gh)

KEEP_TOOLS=0 KEEP_FONTS=0 KEEP_CONFIG=0 PURGE=0 YES=0 GNOME_THEME=0 ALL_TOOLS=0

usage() {
  cat <<EOF
Usage: uninstall.sh [options]

  --keep-tools      keep the tools install.sh put in $BIN_DIR
  --keep-fonts      keep the JetBrainsMono Nerd Font files install.sh added
  --all-tools       also remove ${TOOL_BINS[*]} and nu_plugin_* from $BIN_DIR when
                    they are not in the install record (installs made before it existed)
  --keep-config     keep $TC_HOME (shell integration is still removed)
  --gnome-terminal  reset the font/colours that install.sh --gnome-terminal set
  --purge           also delete tool data: zoxide's directory database and the oh-my-posh cache
  -y, --yes         do not ask for confirmation
  -h, --help        show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --keep-tools) KEEP_TOOLS=1 ;;
    --keep-fonts) KEEP_FONTS=1 ;;
    --all-tools) ALL_TOOLS=1 ;;
    --keep-config) KEEP_CONFIG=1 ;;
    --gnome-terminal) GNOME_THEME=1 ;;
    --purge) PURGE=1 ;;
    -y|--yes) YES=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

if [[ -t 1 ]]; then C_B=$'\e[1;34m' C_G=$'\e[32m' C_Y=$'\e[33m' C_R=$'\e[31m' C_0=$'\e[0m'; else C_B='' C_G='' C_Y='' C_R='' C_0=''; fi
step() { printf '\n%s==> %s%s\n' "$C_B" "$*" "$C_0"; }
ok()   { printf '  %s✔%s %s\n' "$C_G" "$C_0" "$*"; }
warn() { printf '  %s!%s %s\n' "$C_Y" "$C_0" "$*" >&2; }
die()  { printf '%sError:%s %s\n' "$C_R" "$C_0" "$*" >&2; exit 1; }
has()  { command -v "$1" >/dev/null 2>&1; }

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

if has sha256sum; then SHA256=(sha256sum); else SHA256=(shasum -a 256); fi

# Backups keep the original's permissions (cp -p).
backup() { [[ -s "$1" ]] && cp -p "$1" "$1.tc-backup-$(date +%Y%m%d%H%M%S)"; return 0; }

# Removes the marked block (and the blank lines before it) from <file>. The file is rewritten in
# place, so a symlink keeps pointing to its target and the file keeps its permissions.
remove_block() {
  local file=$1 new="$TMP_DIR/block.new"
  [[ -f "$file" ]] && grep -qF "$MARK_BEGIN" "$file" || return 1
  awk -v b="$MARK_BEGIN" -v e="$MARK_END" '
    $0==b {skip=1; blank=""; next} $0==e {skip=0; next} skip {next}
    /^[[:space:]]*$/ {blank=blank $0 "\n"; next}
    {printf "%s%s\n", blank, $0; blank=""}' "$file" > "$new"
  backup "$file"
  cat "$new" > "$file"
}

# Entries of the install record: manifest_list <kind> prints "<path><TAB><extra>" lines.
manifest_list() { [[ -f "$MANIFEST" ]] && awk -F '\t' -v k="$1" '$1 == k { print $2 "\t" $3 }' "$MANIFEST"; return 0; }
manifest_drop() {
  [[ -f "$MANIFEST" ]] || return 0
  awk -F '\t' -v k="$1" '$1 != k' "$MANIFEST" > "$TMP_DIR/manifest"
  cat "$TMP_DIR/manifest" > "$MANIFEST"
}

confirm() {
  [[ $YES == 1 ]] && return 0
  local answer
  if [[ -r /dev/tty ]]; then
    read -r -p "Continue? [y/N] " answer </dev/tty
  else
    die "no terminal to ask for confirmation; re-run with --yes"
  fi
  [[ $answer == [yY]* ]] || { echo "Aborted."; exit 1; }
}

[[ "$(uname -s)" == Linux ]] || die "uninstall.sh is for Linux. On Windows use uninstall.ps1."

# --- plan ------------------------------------------------------------------------------
echo "This will remove the TerminalCustumization setup:"
echo "  - the terminal-customization blocks in ~/.bashrc, Nushell's config.nu and the PowerShell profile"
echo "  - the Nushell autoload scripts and the bat 'Microverse' theme"
[[ $KEEP_CONFIG == 0 ]] && echo "  - $TC_HOME"
if [[ $KEEP_TOOLS == 0 ]]; then
  recorded=$(manifest_list bin | cut -f1 | xargs -r -n1 basename | tr '\n' ' ')
  echo "  - tools install.sh installed: ${recorded:-none recorded}"
  [[ -n "$(manifest_list replaced)" ]] && echo "  - and restore the files install.sh --force replaced"
  [[ $ALL_TOOLS == 1 ]] && echo "  - plus any ${TOOL_BINS[*]} nu_plugin_* left in $BIN_DIR (--all-tools)"
fi
if [[ $KEEP_FONTS == 0 ]]; then
  echo "  - JetBrainsMono Nerd Font files install.sh added: $(manifest_list font | grep -c . || true)"
fi
[[ $GNOME_THEME == 1 ]] && echo "  - font/colour settings of the default GNOME Terminal profile (reset to defaults)"
[[ $PURGE == 1 ]] && echo "  - zoxide's database and the oh-my-posh cache"
confirm

# --- shells -----------------------------------------------------------------------------
step "Removing shell integration"
if remove_block "$HOME/.bashrc"; then ok "$HOME/.bashrc"; fi
if [[ -f "$HOME/.bashrc" ]] && grep -q 'disabled by terminal-customization: ' "$HOME/.bashrc"; then
  warn "$HOME/.bashrc still has lines commented out by the installer ('# disabled by terminal-customization:'); restore them by hand if you want them back"
fi

# Nushell: ask nu for its folders while it is still installed, otherwise use the defaults.
nu_cfg_dir="$HOME/.config/nushell" nu_cfg="$HOME/.config/nushell/config.nu" nu_data_dir="$HOME/.local/share/nushell"
if has nu; then
  nu_cfg_dir=$(nu --no-config-file -c '$nu.default-config-dir' </dev/null)
  nu_cfg=$(nu --no-config-file -c '$nu.config-path' </dev/null)
  nu_data_dir=$(nu --no-config-file -c '$nu.data-dir' </dev/null)
fi
if remove_block "$nu_cfg"; then ok "$nu_cfg"; fi
for f in "$nu_cfg_dir/autoload/terminal-customization.nu" "$nu_cfg_dir/autoload/zoxide.nu" \
         "$nu_cfg_dir/autoload/fzf.nu" "$nu_data_dir/vendor/autoload/oh-my-posh.nu"; do
  [[ -f "$f" ]] && rm -f "$f" && ok "removed $f"
done

if has pwsh; then
  profile_path=$(pwsh -NoLogo -NoProfile -Command 'Write-Output $PROFILE.CurrentUserAllHosts' </dev/null)
  if remove_block "$profile_path"; then ok "$profile_path"; fi
fi

bat_dir=$(has bat && bat --config-dir 2>/dev/null) || bat_dir=''
if [[ "$bat_dir" == /* ]]; then
  theme="$bat_dir/themes/Microverse.tmTheme"
  if [[ -f "$theme" ]]; then
    rm -f "$theme"
    bat cache --build >/dev/null 2>&1 || true
    ok "bat theme removed"
  fi
fi

if [[ $GNOME_THEME == 1 ]]; then
  if has gsettings && id=$(gsettings get org.gnome.Terminal.ProfilesList default 2>/dev/null | tr -d "'") && [[ -n "$id" ]]; then
    path="org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:$id/"
    for key in use-system-font font use-theme-colors background-color foreground-color palette; do
      gsettings reset "$path" "$key"
    done
    ok "GNOME Terminal profile reset"
  else
    warn "GNOME Terminal profile not found"
  fi
fi

# --- tools / fonts / files -------------------------------------------------------------
if [[ $KEEP_TOOLS == 0 ]]; then
  step "Removing tools installed by install.sh"
  while IFS=$'\t' read -r path sum; do
    [[ -n "$path" ]] || continue
    if [[ ! -e "$path" ]]; then continue; fi
    if [[ -n "$sum" && "$("${SHA256[@]}" "$path" | awk '{ print $1 }')" != "$sum" ]]; then
      warn "$path changed since install.sh installed it - left alone"
      continue
    fi
    rm -f "$path" && ok "removed $path"
  done < <(manifest_list bin)
  # Put back files that install.sh --force replaced.
  while IFS=$'\t' read -r path saved; do
    [[ -n "$path" ]] || continue
    [[ -e "$saved" || -L "$saved" ]] || continue
    if [[ -e "$path" || -L "$path" ]]; then warn "$path exists again - your original stays at $saved"; continue; fi
    mv "$saved" "$path" && ok "restored your original $path"
  done < <(manifest_list replaced)
  manifest_drop bin
  manifest_drop replaced
  if [[ $ALL_TOOLS == 1 ]]; then
    for f in "${TOOL_BINS[@]/#/$BIN_DIR/}" "$BIN_DIR"/nu_plugin_*; do
      [[ -e "$f" || -L "$f" ]] && rm -f "$f" && ok "removed $f (--all-tools)"
    done
  fi
  hash -r
  left=()
  for bin in "${TOOL_BINS[@]}"; do has "$bin" && left+=("$bin"); done
  [[ ${#left[@]} -eq 0 ]] || warn "still on PATH (not installed by install.sh, so left alone): ${left[*]}"
fi

if [[ $KEEP_FONTS == 0 ]]; then
  step "Removing JetBrainsMono Nerd Font files installed by install.sh"
  removed=0
  while IFS=$'\t' read -r path _; do
    [[ -n "$path" && -f "$path" ]] || continue
    rm -f "$path" && removed=$((removed + 1))
  done < <(manifest_list font)
  manifest_drop font
  if [[ $removed -gt 0 ]]; then
    has fc-cache && fc-cache -f >/dev/null 2>&1 || true
    ok "$removed font file(s) removed - switch your terminal to another font"
  else
    ok "no font files recorded by install.sh (a font you installed yourself is left alone)"
  fi
fi

# Forget the install record once nothing in it is left.
if [[ -f "$MANIFEST" && ! -s "$MANIFEST" ]]; then
  rm -f "$MANIFEST"
  rmdir "$STATE_DIR/replaced" "$STATE_DIR" 2>/dev/null || true
fi

if [[ $KEEP_CONFIG == 0 && -d "$TC_HOME" ]]; then
  rm -rf "$TC_HOME"
  ok "removed $TC_HOME"
fi

if [[ $PURGE == 1 ]]; then
  rm -rf "${_ZO_DATA_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/zoxide}" "${XDG_CACHE_HOME:-$HOME/.cache}/oh-my-posh"
  ok "zoxide database and oh-my-posh cache removed"
fi

step "Done"
echo "  Backups of edited files are next to them as *.tc-backup-<date>."
# Whatever shell you ran this from (Nushell, or a bash/PowerShell session that already sourced the
# old setup) already loaded the oh-my-posh prompt hook and would keep failing to find it on every
# prompt, since a running shell can't un-load a hook mid-session. Hand off to a fresh bash instead
# of leaving you there - only when there's a real terminal to hand off to (not `curl | bash`).
if [[ -t 0 && -t 1 ]]; then
  echo "  Switching to a fresh bash so a stale prompt hook doesn't keep erroring. 'exit' to leave it."
  exec bash -i
fi
echo "  Open a new terminal to get your previous bash setup back."
exit 0
}
