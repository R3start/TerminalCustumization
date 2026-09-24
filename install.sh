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

DO_TOOLS=1 DO_FONTS=1 UPDATE_FONTS=0 DO_CONFIG=1 DEFAULT_NU='' FORCE=0 DRY_RUN=0 GNOME_THEME=0

usage() {
  cat <<EOF
Usage: install.sh [options]

  --skip-tools        do not install/upgrade the CLI tools
  --skip-fonts        do not install the JetBrainsMono Nerd Font
  --update-fonts      reinstall the font even if it is already installed (upgrade.sh does this)
  --skip-config       do not touch shell configuration files
  --no-default-shell  keep bash as the interactive shell (do not start Nushell automatically)
  --default-shell     start Nushell automatically again (the default on a first install)
  --gnome-terminal    also apply the font and Microverse colours to the default GNOME Terminal profile
  --force             reinstall tools and font even when the latest version is already installed
  --dry-run           only print what would be downloaded
  -h, --help          show this help

Environment: GITHUB_TOKEN (avoids API rate limits), TC_BIN_DIR, TC_HOME
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-tools) DO_TOOLS=0 ;;
    --skip-fonts) DO_FONTS=0 ;;
    --update-fonts) UPDATE_FONTS=1 ;;
    --skip-config) DO_CONFIG=0 ;;
    --no-default-shell) DEFAULT_NU=0 ;;
    --default-shell) DEFAULT_NU=1 ;;
    --gnome-terminal) GNOME_THEME=1 ;;
    --force) FORCE=1; UPDATE_FONTS=1 ;;
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

# Succeeds when <command> is already installed (anywhere on PATH) in <version>.
# Prints a note when an older copy outside $BIN_DIR is going to be shadowed.
is_latest() {
  local name=$1 version=$2 path current
  path=$(command -v "$name" 2>/dev/null) || return 1
  current=$(if [[ $name == oh-my-posh ]]; then "$path" version; else "$path" --version; fi 2>/dev/null | head -n3 || true)
  if grep -qF "$version" <<<"$current"; then
    if [[ "$path" == "$BIN_DIR/$name" ]]; then ok "$name $version (already latest)"
    else ok "$name $version (already latest, $path)"; fi
    return 0
  fi
  if [[ "$path" != "$BIN_DIR/$name" ]]; then
    warn "$name: $path is older; the latest version goes to $BIN_DIR (first in PATH). Remove the old copy with the tool that installed it."
  fi
  return 1
}

install_tool() {
  local name=$1 repo=$2 bins=$3 url version archive dir bin found
  url=$(release_assets "$repo" | pick_asset) || { warn "$name: no Linux release asset found for $(uname -m)"; return 1; }
  version=$(url_version "$url")

  if [[ $DRY_RUN == 1 ]]; then ok "$name $version  <- $url"; return 0; fi
  [[ $FORCE == 0 ]] && is_latest "$name" "$version" && return 0

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
  local version
  version=$(release_assets JanDeDobbeleer/oh-my-posh | head -n1) && version=$(url_version "$version") || version=''
  if [[ $DRY_RUN == 1 ]]; then ok "oh-my-posh ${version:-latest} <- https://ohmyposh.dev/install.sh"; return 0; fi
  [[ $FORCE == 0 && -n "$version" ]] && is_latest oh-my-posh "$version" && return 0
  # Official installer; always fetches the latest release.
  curl -fsSL https://ohmyposh.dev/install.sh | bash -s -- -d "$BIN_DIR" >/dev/null
  ok "oh-my-posh $("$BIN_DIR/oh-my-posh" version 2>/dev/null || echo installed)"
}

# --- config helpers ----------------------------------------------------------------
SCRIPT_DIR=""
if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

backup() { [[ -s "$1" ]] && cp "$1" "$1.tc-backup-$(date +%Y%m%d%H%M%S)"; return 0; }

# Moves <new> over <file>; keeps a backup of <file> only when the content really changes.
replace_if_changed() {
  local new=$1 file=$2
  if [[ -f "$file" ]] && cmp -s "$new" "$file"; then rm -f "$new"; return 0; fi
  backup "$file"
  mv "$new" "$file"
}

copy_configs() {
  local f src dst new updated=0
  for f in "${CONFIG_FILES[@]}"; do
    dst="$TC_HOME/$f"
    new="$TMP_DIR/config.new"
    mkdir -p "$(dirname "$dst")"
    src="$SCRIPT_DIR/config/$f"
    if [[ -n "$SCRIPT_DIR" && -f "$src" ]]; then
      cp "$src" "$new"
    else
      curl -fsSL "$REPO_RAW/config/$f" -o "$new" || die "Could not download config/$f"
    fi
    [[ -f "$dst" ]] && ! cmp -s "$new" "$dst" && updated=$((updated + 1))
    replace_if_changed "$new" "$dst"
  done
  if [[ $updated -gt 0 ]]; then
    ok "configs in $TC_HOME updated ($updated changed file(s); your previous versions are kept as *.tc-backup-*)"
  else
    ok "configs in $TC_HOME are up to date"
  fi
}

# Disables lines outside the marked block that would load a tool a second time
# (lines added by hand, by the old README or by other installers). The lines are kept,
# prefixed with <prefix>, and the file is backed up.
disable_duplicates() {
  local file=$1 re=$2 prefix=$3 new count
  [[ -f "$file" ]] || return 0
  new="$file.tc-tmp"
  TC_RE="$re" TC_PREFIX="$prefix" awk -v b="$MARK_BEGIN" -v e="$MARK_END" '
    BEGIN { re = ENVIRON["TC_RE"]; p = ENVIRON["TC_PREFIX"] }
    $0 == b { inblock = 1 }
    !inblock && $0 ~ re && $0 !~ /^[[:space:]]*(:[[:space:]]*)?#/ { print p $0; n++; next }
    { print }
    $0 == e { inblock = 0 }
    END { print n + 0 > "/dev/stderr" }' "$file" > "$new" 2> "$TMP_DIR/count"
  count=$(cat "$TMP_DIR/count")
  if [[ $count -gt 0 ]]; then
    replace_if_changed "$new" "$file"
    warn "$file: disabled $count line(s) that would load a tool twice (kept as comments, backup saved)"
  else
    rm -f "$new"
  fi
}

# Replaces (or appends) the marked block in <file> with <content>.
write_block() {
  local file=$1 content=$2 new="$1.tc-tmp"
  mkdir -p "$(dirname "$file")"
  touch "$file"
  # Drop the old block and trailing blank lines, then append the new block.
  awk -v b="$MARK_BEGIN" -v e="$MARK_END" '
    $0==b {skip=1; next} $0==e {skip=0; next} skip {next}
    /^[[:space:]]*$/ {blank=blank $0 "\n"; next}
    {printf "%s%s\n", blank, $0; blank=""}' "$file" > "$new"
  [[ -s "$new" ]] && printf '\n' >> "$new"
  printf '%s\n' "$content" >> "$new"
  replace_if_changed "$new" "$file"
}

setup_bash() {
  local rc="$HOME/.bashrc"
  # `:` keeps an if/fi block valid when its only line is disabled.
  disable_duplicates "$rc" \
    'oh-my-posh init bash|zoxide init bash|fzf --bash|[.]fzf[.]bash|terminal-customization[.]bash' \
    ': # disabled by terminal-customization: '
  write_block "$rc" "$MARK_BEGIN
[ -f \"\$HOME/.config/terminal-customization/bash/terminal-customization.bash\" ] && . \"\$HOME/.config/terminal-customization/bash/terminal-customization.bash\"
$MARK_END"
  ok "$HOME/.bashrc sources the bash config"

  # Only change the default shell when asked; re-runs and upgrades keep the current choice.
  [[ $DEFAULT_NU == 1 ]] && rm -f "$TC_HOME/no-nu"
  [[ $DEFAULT_NU == 0 ]] && touch "$TC_HOME/no-nu"
  if [[ -e "$TC_HOME/no-nu" ]]; then
    ok "bash stays the interactive shell (install.sh --default-shell starts Nushell automatically)"
  else
    ok "Nushell starts automatically in new terminals (TC_NO_NU=1 bash to skip once)"
  fi
}

setup_bat() {
  has bat || { warn "bat not found, skipping theme"; return 0; }
  local dir
  dir="$(bat --config-dir)/themes"
  mkdir -p "$dir"
  if cmp -s "$TC_HOME/bat/themes/Microverse.tmTheme" "$dir/Microverse.tmTheme" && bat --list-themes 2>/dev/null | grep -q '^Microverse'; then
    ok "bat theme 'Microverse' already installed"
    return 0
  fi
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
  disable_duplicates "$cfg" \
    'oh-my-posh init nu|zoxide init nushell|fzf --nushell|source .*[.]zoxide[.]nu|source .*oh-my-posh[.]nu' \
    '# disabled by terminal-customization: '
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
  local f
  for f in "$profile_path" "$(dirname "$profile_path")/Microsoft.PowerShell_profile.ps1" "$(dirname "$profile_path")/Microsoft.VSCode_profile.ps1"; do
    disable_duplicates "$f" \
      'oh-my-posh(\.exe)? +init|zoxide init powershell|terminal-customization[/\\]powershell[/\\]profile[.]ps1|Import-Module +(-Name +)?(Terminal-Icons|PSReadLine)|Set-PSReadLineOption' \
      '# disabled by terminal-customization: '
  done
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
  gsettings set "$path" background-color '#0C0C0C'
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

font_installed() {
  if has fc-list; then
    fc-list : family 2>/dev/null | grep -qi 'JetBrainsMono Nerd Font'
  else
    compgen -G "$HOME/.local/share/fonts/JetBrainsMono*NerdFont*" >/dev/null ||
      compgen -G "/usr/share/fonts/**/JetBrainsMono*NerdFont*" >/dev/null
  fi
}

if [[ $DO_FONTS == 1 ]]; then
  step "Installing JetBrainsMono Nerd Font (latest)"
  if [[ $UPDATE_FONTS == 0 ]] && font_installed; then
    ok "JetBrainsMono Nerd Font already installed (upgrade.sh or --update-fonts refreshes it)"
  elif has oh-my-posh && oh-my-posh font install JetBrainsMono </dev/null; then
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
