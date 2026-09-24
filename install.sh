#!/usr/bin/env bash
# shellcheck disable=SC2016  # nu/pwsh expressions are meant to stay unexpanded
# TerminalCustumization - one-click installer for Linux (x86_64 / aarch64)
#
#   curl -fsSL https://raw.githubusercontent.com/R3start/TerminalCustumization/main/install.sh | bash
#   ./install.sh [options]            # from a clone
#
# Re-running it only adds what is missing and upgrades outdated tools to their latest release.
# Every download is checked against the SHA-256 published for it before it is installed.
# Nothing needs sudo: binaries go to ~/.local/bin, configs to ~/.config/terminal-customization.
# What the installer adds is recorded in ~/.local/state/terminal-customization/manifest, so
# uninstall.sh removes only that.

set -euo pipefail

# The whole script is one { } block so bash reads it completely before running anything.
# That keeps `curl … | bash` safe from commands that read stdin.
{

REPO_RAW="${TC_REPO_RAW:-https://raw.githubusercontent.com/R3start/TerminalCustumization/main}"
BIN_DIR="${TC_BIN_DIR:-$HOME/.local/bin}"
TC_HOME="${TC_HOME:-$HOME/.config/terminal-customization}"
GITHUB_API="${TC_GITHUB_API:-https://api.github.com}"   # overridable for mirrors / GitHub Enterprise
GITHUB_WEB="${TC_GITHUB_WEB:-https://github.com}"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/terminal-customization"
MANIFEST="$STATE_DIR/manifest"
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
  powershell/disable-duplicates.ps1
  nushell/terminal-customization.nu
  nushell/config-snippet.nu
  bat/themes/Microverse.tmTheme
  eza/theme.yml
  fzf/fzfrc
  ripgrep/ripgreprc
)

DO_TOOLS=1 DO_FONTS=1 UPDATE_FONTS=0 DO_CONFIG=1 DEFAULT_NU='' FORCE=0 DRY_RUN=0 GNOME_THEME=0 ALLOW_UNVERIFIED=0

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
  --force             reinstall tools and font even when the latest version is already installed, and
                      replace files in ~/.local/bin that this script did not install (they are backed up)
  --allow-unverified  install a tool even if no SHA-256 checksum is published for its download
  --dry-run           only print what would be downloaded
  -h, --help          show this help

Environment: GITHUB_TOKEN (avoids API rate limits; sent only to the GitHub API), TC_BIN_DIR, TC_HOME,
             TC_GITHUB_API / TC_GITHUB_WEB (GitHub mirror or Enterprise)
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
    --allow-unverified) ALLOW_UNVERIFIED=1 ;;
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

# Private scratch directory (mode 700): downloads, rewritten files and the auth header live here.
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# --- prerequisites ---------------------------------------------------------------
[[ "$(uname -s)" == Linux ]] || die "install.sh is for Linux. On Windows use install.ps1."
for dep in curl tar; do
  has "$dep" || die "'$dep' is required. Install it first (e.g. sudo apt install $dep)."
done
if has sha256sum; then SHA256=(sha256sum)
elif has shasum; then SHA256=(shasum -a 256)
else die "'sha256sum' (coreutils) or 'shasum' is required to verify downloads."; fi

case "$(uname -m)" in
  x86_64|amd64)  ARCH_RE='x86_64|amd64' POSH_ARCH=amd64 ;;
  aarch64|arm64) ARCH_RE='aarch64|arm64' POSH_ARCH=arm64 ;;
  *) die "Unsupported CPU architecture: $(uname -m)" ;;
esac

# The GitHub token is only ever sent to the GitHub API ($GITHUB_API). It goes into a header file inside the
# private TMP_DIR (printf is a shell builtin), so it never appears on a command line (ps).
CURL_AUTH=()
if [[ -n "${GITHUB_TOKEN:-}" ]]; then
  (umask 077 && printf 'Authorization: Bearer %s\n' "$GITHUB_TOKEN" > "$TMP_DIR/auth-header")
  CURL_AUTH=(-H "@$TMP_DIR/auth-header")
fi

# --- GitHub release helpers ------------------------------------------------------

# Reads a GitHub "latest release" JSON document on stdin and prints one line per asset:
# <download url><TAB><sha256 or empty>. GitHub lists each asset's "digest" before its
# "browser_download_url"; a missing or null digest leaves the second column empty.
parse_release_json() {
  grep -oE '"digest": *("sha256:[0-9a-fA-F]{64}"|null)|"browser_download_url": *"[^"]+"' |
    awk '
      /^"digest"/ { d = ""; if (match($0, /sha256:[0-9a-fA-F]+/)) d = substr($0, RSTART + 7, RLENGTH - 7); next }
      { sub(/^"browser_download_url": *"/, ""); sub(/"$/, ""); print $0 "\t" d; d = "" }'
}

# Prints the assets of the latest release of <owner/repo> as <url><TAB><sha256 or empty>.
release_assets() {
  local repo=$1 json tag
  if json=$(curl -fsSL "${CURL_AUTH[@]}" -H 'Accept: application/vnd.github+json' \
      "$GITHUB_API/repos/$repo/releases/latest" 2>/dev/null); then
    parse_release_json <<<"$json"
    return 0
  fi
  # Fallback without the API (e.g. rate limited): follow the /releases/latest redirect and read the
  # asset list page. No digests there; published checksum files are used instead.
  tag=$(curl -fsSLI -o /dev/null -w '%{url_effective}' "$GITHUB_WEB/$repo/releases/latest") || return 1
  tag=${tag##*/}
  curl -fsSL "$GITHUB_WEB/$repo/releases/expanded_assets/$tag" |
    grep -oE 'href="/[^"]+/releases/download/[^"]+"' | sed -E "s#^href=\"#$GITHUB_WEB#; s#\"\$##; s#\$#\t#"
}

# Prints the expected SHA-256 of <url>, taken from (in this order) the GitHub asset digest, a
# <asset>.sha256 / .sha256sum file, or a combined checksum file of the release. <assets> is the
# output of release_assets. Prints nothing when no checksum is published.
expected_sha256() {
  local url=$1 assets=$2 name digest sums sum_url
  name=${url##*/}
  digest=$(awk -F '\t' -v u="$url" '$1 == u { print $2; exit }' <<<"$assets")
  if [[ -n "$digest" ]]; then echo "$digest" | tr 'A-F' 'a-f'; return 0; fi
  for sum_url in "$url.sha256" "$url.sha256sum"; do
    if cut -f1 <<<"$assets" | grep -qxF "$sum_url"; then
      curl -fsSL "$sum_url" | grep -oE '\b[0-9a-fA-F]{64}\b' | head -n1 | tr 'A-F' 'a-f'
      return 0
    fi
  done
  while IFS= read -r sum_url; do
    sums=$(curl -fsSL "$sum_url" 2>/dev/null) || continue
    # "<hash>  <name>" or "<hash> *<name>" (sha256sum / goreleaser format)
    awk -v n="$name" '$2 == n || $2 == "*" n { print tolower($1); exit }' <<<"$sums" | grep -E '^[0-9a-f]{64}$' && return 0
  done < <(cut -f1 <<<"$assets" | grep -Ei '/([^/]*checksums?[^/]*\.txt|sha256sums(\.txt)?|checksums\.sha256)$' || true)
  return 0
}

# Downloads <url> to <out> and verifies its SHA-256. On a mismatch the file is deleted. Without a
# published checksum the download is refused unless --allow-unverified was given.
# Sets VERIFIED to "sha256 verified" or "NOT verified".
download_verified() {
  local url=$1 out=$2 assets=$3 expected actual
  VERIFIED="NOT verified"
  expected=$(expected_sha256 "$url" "$assets")
  if [[ -z "$expected" && $ALLOW_UNVERIFIED == 0 ]]; then
    warn "${url##*/}: no SHA-256 checksum is published for this download, refusing to install it (re-run with --allow-unverified to install it anyway)"
    return 1
  fi
  curl -fsSL "$url" -o "$out"
  if [[ -z "$expected" ]]; then
    warn "${url##*/}: installed WITHOUT checksum verification (--allow-unverified)"
    return 0
  fi
  actual=$("${SHA256[@]}" "$out" | awk '{ print tolower($1) }')
  if [[ "$actual" != "$expected" ]]; then
    rm -f "$out"
    warn "${url##*/}: SHA-256 mismatch (expected $expected, got $actual) - download deleted, not installed"
    return 1
  fi
  VERIFIED="sha256 verified"
}

# --- install manifest: what this script installed (used by uninstall.sh) ------------
# Lines: <kind><TAB><path><TAB><extra>  (kind: bin, font, replaced)
manifest_has() { [[ -f "$MANIFEST" ]] && awk -F '\t' -v k="$1" -v p="$2" '$1 == k && $2 == p { f = 1 } END { exit !f }' "$MANIFEST"; }
manifest_set() {
  mkdir -p "$STATE_DIR"
  touch "$MANIFEST"
  awk -F '\t' -v k="$1" -v p="$2" '!($1 == k && $2 == p)' "$MANIFEST" > "$TMP_DIR/manifest"
  printf '%s\t%s\t%s\n' "$1" "$2" "${3:-}" >> "$TMP_DIR/manifest"
  cat "$TMP_DIR/manifest" > "$MANIFEST"
}

# Installs <file> as $BIN_DIR/<name>. A file there that this script did not install (put there by
# hand, a symlink such as bat -> batcat, ...) is left alone; with --force it is moved to
# $STATE_DIR/replaced/ first and restored by uninstall.sh.
place_bin() {
  local src=$1 name=$2 dst="$BIN_DIR/$2" saved
  if [[ -e "$dst" || -L "$dst" ]] && ! manifest_has bin "$dst"; then
    if [[ $FORCE == 0 ]]; then
      warn "$dst was not installed by this script - left alone (--force replaces it and keeps a backup)"
      return 1
    fi
    mkdir -p "$STATE_DIR/replaced"
    saved="$STATE_DIR/replaced/$name.$(date +%Y%m%d%H%M%S)"
    mv "$dst" "$saved"
    manifest_set replaced "$dst" "$saved"
    warn "$dst replaced (--force); the original is saved as $saved"
  fi
  install -m 0755 "$src" "$dst"
  manifest_set bin "$dst" "$("${SHA256[@]}" "$dst" | awk '{ print $1 }')"
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
  local name=$1 repo=$2 bins=$3 assets url version archive dir bin found placed
  assets=$(release_assets "$repo") || { warn "$name: could not read the latest release of $repo"; return 1; }
  url=$(cut -f1 <<<"$assets" | pick_asset) || { warn "$name: no Linux release asset found for $(uname -m)"; return 1; }
  version=$(url_version "$url")

  if [[ $DRY_RUN == 1 ]]; then
    ok "$name $version  <- $url ($([[ -n "$(expected_sha256 "$url" "$assets")" ]] && echo "sha256 published" || echo "NO checksum"))"
    return 0
  fi
  [[ $FORCE == 0 ]] && is_latest "$name" "$version" && return 0

  archive="$TMP_DIR/$name.tar.gz"
  dir="$TMP_DIR/$name"
  download_verified "$url" "$archive" "$assets" || return 1
  mkdir -p "$dir" && tar -xzf "$archive" -C "$dir" --no-same-owner
  placed=0
  for bin in $bins; do
    found=0
    while IFS= read -r -d '' f; do
      found=1
      place_bin "$f" "$(basename "$f")" && placed=1
    done < <(find "$dir" -type f -name "$bin" -print0)
    [[ $found == 1 || $bin == *'*'* ]] || { warn "$name: '$bin' not found in $url"; return 1; }
  done
  [[ $placed == 1 ]] && ok "$name $version ($VERIFIED)"
  return 0
}

# Oh My Posh: the release binary itself (no piped install script), verified like every other tool.
install_oh_my_posh() {
  local assets url version
  assets=$(release_assets JanDeDobbeleer/oh-my-posh) || { warn "oh-my-posh: could not read the latest release"; return 1; }
  url=$(cut -f1 <<<"$assets" | grep -E "/posh-linux-$POSH_ARCH\$" | head -n1) || true
  [[ -n "$url" ]] || { warn "oh-my-posh: no release binary for linux-$POSH_ARCH"; return 1; }
  version=$(url_version "$url")
  if [[ $DRY_RUN == 1 ]]; then ok "oh-my-posh $version  <- $url"; return 0; fi
  [[ $FORCE == 0 ]] && is_latest oh-my-posh "$version" && return 0
  download_verified "$url" "$TMP_DIR/oh-my-posh" "$assets" || return 1
  place_bin "$TMP_DIR/oh-my-posh" oh-my-posh && ok "oh-my-posh $version ($VERIFIED)"
  return 0
}

# --- config helpers ----------------------------------------------------------------
SCRIPT_DIR=""
if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

# Backups keep the original's permissions (cp -p), so a private file stays private.
backup() { [[ -s "$1" ]] && cp -p "$1" "$1.tc-backup-$(date +%Y%m%d%H%M%S)"; return 0; }

# Writes <new> into <file> when the content differs, keeping a backup of <file>. The file is
# rewritten in place (not replaced), so a symlink (dotfiles managers) keeps pointing to its
# target and the file keeps its owner and permissions.
replace_if_changed() {
  local new=$1 file=$2
  if [[ -f "$file" ]] && cmp -s "$new" "$file"; then rm -f "$new"; return 0; fi
  backup "$file"
  cat "$new" > "$file"
  rm -f "$new"
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

# Disables statements outside the marked block that would load a tool a second time (lines
# added by hand, by the old README or by other installers). They stay in the file as comments,
# prefixed with <prefix>, and the file is backed up. A statement continued with a trailing "\"
# is disabled as a whole. A matching line whose brackets don't balance (part of a longer
# statement) is left alone and reported, so the file never ends up half-commented.
disable_duplicates() {
  local file=$1 re=$2 prefix=$3 new result count skipped
  [[ -f "$file" ]] || return 0
  new="$TMP_DIR/disable.new"
  TC_RE="$re" TC_PREFIX="$prefix" awk -v b="$MARK_BEGIN" -v e="$MARK_END" '
    function balanced(s,   t) {
      t = s; gsub(/"[^"]*"|\047[^\047]*\047/, "", t)   # ignore quoted text
      return gsub(/[({[]/, "", t) == gsub(/[)}\]]/, "", t)
    }
    BEGIN { re = ENVIRON["TC_RE"]; p = ENVIRON["TC_PREFIX"] }
    { line[NR] = $0 }
    END {
      for (i = 1; i <= NR; i++) {
        if (line[i] == b) inblock = 1
        # a statement: this line plus the lines it continues onto with a trailing backslash
        j = i; stmt = line[i]
        while (line[j] ~ /\\$/ && j < NR) { j++; stmt = stmt "\n" line[j] }
        if (!inblock && stmt ~ re && line[i] !~ /^[[:space:]]*(:[[:space:]]*)?#/) {
          if (balanced(stmt)) { for (k = i; k <= j; k++) line[k] = p line[k]; n++ }
          else skipped = skipped " " i
        }
        for (k = i; k <= j; k++) { print line[k]; if (line[k] == e) inblock = 0 }
        i = j
      }
      print (n + 0) skipped > "/dev/stderr"
    }' "$file" > "$new" 2> "$TMP_DIR/disable.result"
  result=$(cat "$TMP_DIR/disable.result")
  count=${result%% *}
  skipped=${result#"$count"}
  if [[ $count -gt 0 ]]; then
    replace_if_changed "$new" "$file"
    warn "$file: disabled $count statement(s) that would load a tool twice (kept as comments, backup saved)"
  else
    rm -f "$new"
  fi
  [[ -z "$skipped" ]] || warn "$file: line(s)$skipped also load a tool, but are part of a longer statement - remove them by hand"
  return 0
}

# Replaces (or appends) the marked block in <file> with <content>.
write_block() {
  local file=$1 content=$2 new="$TMP_DIR/block.new"
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
  dir=$(bat --config-dir 2>/dev/null) || dir=''
  # Only a real bat prints an absolute config directory (a bat -> something-else link may not).
  [[ "$dir" == /* ]] || { warn "bat did not report its config directory, skipping theme"; return 0; }
  dir="$dir/themes"
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
  local f line
  # PowerShell profiles are handled by the PowerShell parser (multi-line statements, see the helper).
  for f in "$profile_path" "$(dirname "$profile_path")/Microsoft.PowerShell_profile.ps1" "$(dirname "$profile_path")/Microsoft.VSCode_profile.ps1"; do
    [[ -f "$f" ]] || continue
    while IFS= read -r line; do
      case "$line" in
        disabled*) warn "$f: $line statement(s) that would load a tool twice (kept as comments, backup saved)" ;;
        ?*) warn "$f: $line" ;;
      esac
    done < <(pwsh -NoLogo -NoProfile -NonInteractive -File "$TC_HOME/powershell/disable-duplicates.ps1" -Path "$f" </dev/null)
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

# oh-my-posh installs fonts into ~/.local/share/fonts (or /usr/share/fonts when run as root).
font_files() {
  local dir="$HOME/.local/share/fonts"
  [[ $EUID -eq 0 ]] && dir=/usr/share/fonts
  find "$dir" -maxdepth 1 -type f -name 'JetBrainsMono*NerdFont*' 2>/dev/null | sort
}

if [[ $DO_FONTS == 1 ]]; then
  step "Installing JetBrainsMono Nerd Font (latest)"
  ours=$([[ -f "$MANIFEST" ]] && awk -F '\t' '$1 == "font"' "$MANIFEST" | head -n1)
  if font_installed && [[ $UPDATE_FONTS == 0 ]]; then
    ok "JetBrainsMono Nerd Font already installed (upgrade.sh or --update-fonts refreshes it)"
  elif font_installed && [[ -z "$ours" ]]; then
    ok "JetBrainsMono Nerd Font is installed, but not by this script - left as it is"
  elif has oh-my-posh; then
    font_files > "$TMP_DIR/fonts.before"
    if oh-my-posh font install JetBrainsMono </dev/null; then
      has fc-cache && fc-cache -f >/dev/null 2>&1 || true
      # Record only the files this run added (a font you installed yourself is never recorded).
      font_files | comm -13 "$TMP_DIR/fonts.before" - | while IFS= read -r f; do manifest_set font "$f"; done
      ok "font installed - select 'JetBrainsMono Nerd Font' in your terminal settings"
    else
      warn "font installation failed; see README 'Fonts' for the manual steps"
    fi
  else
    warn "oh-my-posh not found, skipping the font"
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
