#!/usr/bin/env bash
# shellcheck disable=SC2016  # nu/pwsh expressions are meant to stay unexpanded
# TerminalCustumization - one-click installer for Linux (x86_64 / aarch64)
#
#   curl -fsSL https://raw.githubusercontent.com/R3start/TerminalCustumization/main/install.sh | bash
#   ./install.sh [options]            # from a clone
#
# Every run downloads the latest release of each tool, so re-running it upgrades everything.
# Nothing needs sudo: binaries go to ~/.local/bin, configs to ~/.config/terminal-customization.

set -euo pipefail

# The whole script is one { } block so bash reads it completely before running anything.
# That keeps `curl … | bash` safe from commands that read stdin.
{

REPO_RAW="${TC_REPO_RAW:-https://raw.githubusercontent.com/R3start/TerminalCustumization/main}"
BIN_DIR="${TC_BIN_DIR:-$HOME/.local/bin}"
TC_HOME="${TC_HOME:-$HOME/.config/terminal-customization}"
MARK_BEGIN='# >>> terminal-customization >>>'
MARK_END='# <<< terminal-customization <<<'

# name | GitHub repo | binaries to install from the archive (space separated, globs allowed)
TOOLS=(
  "eza|eza-community/eza|eza"
  "bat|sharkdp/bat|bat"
  "rg|BurntSushi/ripgrep|rg"
  "fzf|junegunn/fzf|fzf"
  "zoxide|ajeetdsouza/zoxide|zoxide"
  "duf|muesli/duf|duf"
  "dust|bootandy/dust|dust"
  "gh|cli/cli|gh"
  "nu|nushell/nushell|nu nu_plugin_*"
)

# Files copied to $TC_HOME (paths relative to the repo's config/ folder)
CONFIG_FILES=(
  oh-my-posh/microverse-power.omp.json
  bash/terminal-customization.bash
  powershell/profile.ps1
  nushell/terminal-customization.nu
  nushell/config-snippet.nu
  bat/themes/Microverse.tmTheme
  eza/theme.yml
  fzf/fzfrc
  ripgrep/ripgreprc
)

DO_TOOLS=1 DO_FONTS=1 DO_CONFIG=1 DEFAULT_NU=1 FORCE=0 DRY_RUN=0 GNOME_THEME=0

usage() {
  cat <<EOF
Usage: install.sh [options]

  --skip-tools        do not install/upgrade the CLI tools
  --skip-fonts        do not install the JetBrainsMono Nerd Font
  --skip-config       do not touch shell configuration files
  --no-default-shell  keep bash as the interactive shell (do not start Nushell automatically)
  --gnome-terminal    also apply the font and Microverse colours to the default GNOME Terminal profile
  --force             reinstall tools even when the latest version is already installed
  --dry-run           only print what would be downloaded
  -h, --help          show this help

Environment: GITHUB_TOKEN (avoids API rate limits), TC_BIN_DIR, TC_HOME
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-tools) DO_TOOLS=0 ;;
    --skip-fonts) DO_FONTS=0 ;;
    --skip-config) DO_CONFIG=0 ;;
    --no-default-shell) DEFAULT_NU=0 ;;
    --gnome-terminal) GNOME_THEME=1 ;;
    --force) FORCE=1 ;;
    --dry-run) DRY_RUN=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

# --- output helpers -------------------------------------------------------------
if [[ -t 1 ]]; then C_B=$'\e[1;34m' C_G=$'\e[32m' C_Y=$'\e[33m' C_R=$'\e[31m' C_0=$'\e[0m'; else C_B='' C_G='' C_Y='' C_R='' C_0=''; fi
step() { printf '\n%s==> %s%s\n' "$C_B" "$*" "$C_0"; }
ok()   { printf '  %s✔%s %s\n' "$C_G" "$C_0" "$*"; }
warn() { printf '  %s!%s %s\n' "$C_Y" "$C_0" "$*" >&2; }
die()  { printf '%sError:%s %s\n' "$C_R" "$C_0" "$*" >&2; exit 1; }
has()  { command -v "$1" >/dev/null 2>&1; }

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# --- prerequisites ---------------------------------------------------------------
[[ "$(uname -s)" == Linux ]] || die "install.sh is for Linux. On Windows use install.ps1."
for dep in curl tar unzip; do
  has "$dep" || die "'$dep' is required. Install it first (e.g. sudo apt install $dep)."
done

case "$(uname -m)" in
  x86_64|amd64)  ARCH_RE='x86_64|amd64' ;;
  aarch64|arm64) ARCH_RE='aarch64|arm64' ;;
  *) die "Unsupported CPU architecture: $(uname -m)" ;;
esac

CURL_AUTH=()
[[ -n "${GITHUB_TOKEN:-}" ]] && CURL_AUTH=(-H "Authorization: Bearer $GITHUB_TOKEN")

# --- GitHub release helpers ------------------------------------------------------

# Prints the download URLs of all assets of the latest release of <owner/repo>.
release_assets() {
  local repo=$1 json tag
  if json=$(curl -fsSL "${CURL_AUTH[@]}" -H 'Accept: application/vnd.github+json' \
      "https://api.github.com/repos/$repo/releases/latest" 2>/dev/null); then
    grep -oE '"browser_download_url": *"[^"]+"' <<<"$json" | sed -E 's/.*"(https[^"]+)"$/\1/'
    return 0
  fi
  # Fallback without the API (e.g. rate limited): follow the /releases/latest redirect
  # and read the asset list page.
  tag=$(curl -fsSLI -o /dev/null -w '%{url_effective}' "https://github.com/$repo/releases/latest") || return 1
  tag=${tag##*/}
  curl -fsSL "https://github.com/$repo/releases/expanded_assets/$tag" |
    grep -oE 'href="/[^"]+/releases/download/[^"]+"' | sed -E 's#^href="#https://github.com#; s#"$##'
}

# Reads asset URLs on stdin and prints the best Linux .tar.gz for this CPU (musl > gnu > other).
pick_asset() {
  local urls
  urls=$(grep -E '\.tar\.gz$' | grep -i 'linux' | grep -Ei "$ARCH_RE" |
         grep -Eiv 'armv[67]|gnueabi|musleabi|android|\.sha|\.sig|\.asc' || true)
  [[ -n "$urls" ]] || return 1
  local flavour match
  for flavour in musl gnu ''; do
    match=$(grep -i -- "$flavour" <<<"$urls" || true)
    if [[ -n "$match" ]]; then head -n1 <<<"$match"; return 0; fi
  done
}

# Tag of a release download URL (…/releases/download/<tag>/<file>), without a leading "v".
url_version() { local v=${1%/*}; v=${v##*/}; echo "${v#v}"; }

install_tool() {
  local name=$1 repo=$2 bins=$3 url version archive dir bin found current
  url=$(release_assets "$repo" | pick_asset) || { warn "$name: no Linux release asset found for $(uname -m)"; return 1; }
  version=$(url_version "$url")

  if [[ $DRY_RUN == 1 ]]; then ok "$name $version  <- $url"; return 0; fi

  if [[ $FORCE == 0 && -x "$BIN_DIR/$name" ]]; then
    current=$("$BIN_DIR/$name" --version 2>/dev/null | head -n3 || true)
    if grep -qF "$version" <<<"$current"; then ok "$name $version (already latest)"; return 0; fi
  fi

  archive="$TMP_DIR/$name.tar.gz"
  dir="$TMP_DIR/$name"
  curl -fsSL "$url" -o "$archive"
  mkdir -p "$dir" && tar -xzf "$archive" -C "$dir"
  for bin in $bins; do
    found=0
    while IFS= read -r -d '' f; do
      install -m 0755 "$f" "$BIN_DIR/$(basename "$f")"
      found=1
    done < <(find "$dir" -type f -name "$bin" -print0)
    [[ $found == 1 || $bin == *'*'* ]] || { warn "$name: '$bin' not found in $url"; return 1; }
  done
  ok "$name $version"
}

install_oh_my_posh() {
  if [[ $DRY_RUN == 1 ]]; then ok "oh-my-posh <- https://ohmyposh.dev/install.sh"; return 0; fi
  # Official installer; always fetches the latest release.
  curl -fsSL https://ohmyposh.dev/install.sh | bash -s -- -d "$BIN_DIR" >/dev/null
  ok "oh-my-posh $("$BIN_DIR/oh-my-posh" version 2>/dev/null || echo installed)"
}

# --- config helpers ----------------------------------------------------------------
SCRIPT_DIR=""
if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

copy_configs() {
  local f src dst
  for f in "${CONFIG_FILES[@]}"; do
    dst="$TC_HOME/$f"
    mkdir -p "$(dirname "$dst")"
    src="$SCRIPT_DIR/config/$f"
    if [[ -n "$SCRIPT_DIR" && -f "$src" ]]; then
      cp "$src" "$dst"
    else
      curl -fsSL "$REPO_RAW/config/$f" -o "$dst" || die "Could not download config/$f"
    fi
  done
  ok "configs copied to $TC_HOME"
}

backup() { [[ -f "$1" ]] && cp "$1" "$1.tc-backup-$(date +%Y%m%d%H%M%S)"; return 0; }

# Replaces (or appends) the marked block in <file> with <content>.
write_block() {
  local file=$1 content=$2
  mkdir -p "$(dirname "$file")"
  touch "$file"
  if grep -qF "$MARK_BEGIN" "$file"; then
    backup "$file"
    awk -v b="$MARK_BEGIN" -v e="$MARK_END" '
      $0==b {skip=1; next} $0==e {skip=0; next} !skip {print}' "$file" > "$file.tc-tmp"
    mv "$file.tc-tmp" "$file"
  fi
  printf '\n%s\n' "$content" >> "$file"
}

setup_bash() {
  local rc="$HOME/.bashrc"
  # Disable prompt lines from the old manual instructions (~/.poshthemes), the block below replaces them.
  if [[ -f "$rc" ]] && grep -Eq '^[^#]*oh-my-posh init bash' "$rc" && ! grep -qF "$MARK_BEGIN" "$rc"; then
    backup "$rc"
    sed -i -E 's/^([^#]*oh-my-posh init bash.*)$/# disabled by terminal-customization: \1/' "$rc"
    warn "commented out an old oh-my-posh line in ~/.bashrc"
  fi
  write_block "$rc" "$MARK_BEGIN
[ -f \"\$HOME/.config/terminal-customization/bash/terminal-customization.bash\" ] && . \"\$HOME/.config/terminal-customization/bash/terminal-customization.bash\"
$MARK_END"
  ok "$HOME/.bashrc sources the bash config"

  if [[ $DEFAULT_NU == 1 ]]; then
    rm -f "$TC_HOME/no-nu"
    ok "Nushell starts automatically in new terminals (TC_NO_NU=1 bash to skip once)"
  else
    touch "$TC_HOME/no-nu"
    ok "bash stays the interactive shell (delete $TC_HOME/no-nu to start Nushell automatically)"
  fi
}

setup_bat() {
  has bat || { warn "bat not found, skipping theme"; return 0; }
  local dir
  dir="$(bat --config-dir)/themes"
  mkdir -p "$dir"
  cp "$TC_HOME/bat/themes/Microverse.tmTheme" "$dir/"
  bat cache --build >/dev/null
  ok "bat theme 'Microverse' installed"
}

setup_nushell() {
  has nu || { warn "nu not found, skipping Nushell config"; return 0; }
  local cfg_dir cfg autoload
  cfg_dir=$(nu --no-config-file -c '$nu.default-config-dir' </dev/null)
  cfg=$(nu --no-config-file -c '$nu.config-path' </dev/null)
  autoload="$cfg_dir/autoload"
  mkdir -p "$autoload"
  cp "$TC_HOME/nushell/terminal-customization.nu" "$autoload/"
  write_block "$cfg" "$(cat "$TC_HOME/nushell/config-snippet.nu")"   # snippet carries its own markers
  # Generate the integration scripts once now (config.nu refreshes them on every start).
  has zoxide && zoxide init nushell > "$autoload/zoxide.nu"
  has fzf && fzf --nushell > "$autoload/fzf.nu"
  has oh-my-posh && oh-my-posh init nu --config "$TC_HOME/oh-my-posh/microverse-power.omp.json" >/dev/null
  ok "Nushell config in $cfg_dir"
}

setup_pwsh() {
  has pwsh || return 0
  local profile_path
  profile_path=$(pwsh -NoLogo -NoProfile -Command 'Write-Output $PROFILE.CurrentUserAllHosts' </dev/null)
  write_block "$profile_path" "$MARK_BEGIN
. \"\$HOME/.config/terminal-customization/powershell/profile.ps1\"
$MARK_END"
  ok "PowerShell profile: $profile_path"
}

setup_gnome_terminal() {
  has gsettings || { warn "gsettings not found, skipping GNOME Terminal"; return 0; }
  local id path
  id=$(gsettings get org.gnome.Terminal.ProfilesList default 2>/dev/null | tr -d "'") || { warn "GNOME Terminal not found"; return 0; }
  [[ -n "$id" ]] || { warn "GNOME Terminal has no default profile"; return 0; }
  path="org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:$id/"
  gsettings set "$path" use-system-font false
  gsettings set "$path" font 'JetBrainsMono Nerd Font 11'
  gsettings set "$path" use-theme-colors false
  gsettings set "$path" background-color '#1B1B1B'
  gsettings set "$path" foreground-color '#E6E6E6'
  gsettings set "$path" palette "['#242424', '#F1184C', '#33DD2D', '#FFBB00', '#3A86FF', '#B45CFF', '#2EC4E6', '#D0D0D0', '#6C6C6C', '#FF4D74', '#66F060', '#FFD24D', '#6FA8FF', '#CC8CFF', '#6FDAF2', '#FFFFFF']"
  ok "GNOME Terminal profile $id uses JetBrainsMono Nerd Font + Microverse colours"
}

# --- main ----------------------------------------------------------------------------
mkdir -p "$BIN_DIR"
export PATH="$BIN_DIR:$PATH"

if [[ $DO_TOOLS == 1 ]]; then
  step "Installing the latest CLI tools into $BIN_DIR"
  install_oh_my_posh || warn "oh-my-posh installation failed"
  failed=()
  for entry in "${TOOLS[@]}"; do
    IFS='|' read -r name repo bins <<<"$entry"
    install_tool "$name" "$repo" "$bins" || failed+=("$name")
  done
  [[ ${#failed[@]} -eq 0 ]] || warn "failed: ${failed[*]} (re-run later or set GITHUB_TOKEN if rate limited)"
fi

[[ $DRY_RUN == 1 ]] && exit 0

if [[ $DO_FONTS == 1 ]]; then
  step "Installing JetBrainsMono Nerd Font (latest)"
  if has oh-my-posh && oh-my-posh font install JetBrainsMono </dev/null; then
    has fc-cache && fc-cache -f >/dev/null 2>&1 || true
    ok "font installed - select 'JetBrainsMono Nerd Font' in your terminal settings"
  else
    warn "font installation failed; see README 'Fonts' for the manual steps"
  fi
fi

if [[ $DO_CONFIG == 1 ]]; then
  step "Configuring shells"
  copy_configs
  setup_bash
  setup_bat
  setup_nushell
  setup_pwsh
  [[ $GNOME_THEME == 1 ]] && setup_gnome_terminal
fi

step "Done"
echo "  Open a new terminal (or run: exec bash) to start using the new setup."
has gh && ! gh auth status >/dev/null 2>&1 && echo "  Run 'gh auth login' to sign in to GitHub."
exit 0
}
