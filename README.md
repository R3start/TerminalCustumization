# Terminal Customization

A modern, consistent terminal on **Windows** and **Linux**: an Oh My Posh prompt, Nushell as the
default shell, and a set of fast CLI tools that all share the same *microverse-power* colour palette.

![screenshot.png](screenshot.png "Screenshot")

- [What gets installed](#what-gets-installed)
- [One-click install](#one-click-install)
- [Manual installation – Windows](#manual-installation--windows)
- [Manual installation – Linux](#manual-installation--linux)
- [Updating](#updating) · [Uninstalling](#uninstalling) · [Troubleshooting](#troubleshooting)
- [Tool guides](docs/tools/README.md)

## What gets installed

| Tool | Purpose | Guide |
|------|---------|-------|
| [Oh My Posh](https://ohmyposh.dev) | prompt theme engine (theme: *microverse-power*) | [guide](docs/tools/oh-my-posh.md) |
| [Nushell](https://www.nushell.sh) | structured-data shell, **opens by default** in new terminals | [guide](docs/tools/nushell.md) |
| [JetBrainsMono Nerd Font](https://www.nerdfonts.com) | font with the icons used by the prompt and eza | [Fonts](#3-font) |
| [eza](https://github.com/eza-community/eza) | `ls` with icons, git status, tree view | [guide](docs/tools/eza.md) |
| [bat](https://github.com/sharkdp/bat) | `cat` with syntax highlighting | [guide](docs/tools/bat.md) |
| [ripgrep](https://github.com/BurntSushi/ripgrep) | very fast recursive search (`rg`) | [guide](docs/tools/ripgrep.md) |
| [fzf](https://github.com/junegunn/fzf) | fuzzy finder for history, files and directories | [guide](docs/tools/fzf.md) |
| [zoxide](https://github.com/ajeetdsouza/zoxide) | smarter `cd` (`z`, `zi`) | [guide](docs/tools/zoxide.md) |
| [duf](https://github.com/muesli/duf) | disk free overview (`df`) | [guide](docs/tools/duf.md) |
| [dust](https://github.com/bootandy/dust) | disk usage tree (`du`) | [guide](docs/tools/dust.md) |
| [GitHub CLI](https://cli.github.com) | GitHub from the terminal (`gh`) | [guide](docs/tools/gh.md) |
| Windows only: [Windows Terminal](https://github.com/microsoft/terminal), [PowerShell 7](https://github.com/PowerShell/PowerShell) | terminal and modern PowerShell | |

**Changes compared to the previous version of this repo**

- PSReadLine and Terminal-Icons are no longer used. fzf (history, files, directories), zoxide (jumping)
  and eza (icons) replace them. The installer removes the copies installed from the PowerShell Gallery.
  The copy of PSReadLine that ships inside PowerShell can't be removed; this setup simply doesn't configure it.
- The bundled Nerd Font v2 files are gone. The latest JetBrainsMono Nerd Font (v3, family name
  `JetBrainsMono Nerd Font`) is downloaded instead.
- Oh My Posh no longer ships themes in `POSH_THEMES_PATH`/`~/.poshthemes`. The theme is now kept in this repo.
- All configuration lives in [`config/`](config) and is shared by bash, PowerShell (5.1 and 7) and Nushell.

### Keyboard shortcuts and aliases

| Shortcut / alias | Action | Shells |
|------------------|--------|--------|
| `Ctrl+R` | fuzzy search history | bash, Nushell (`fh` in PowerShell) |
| `Ctrl+T` | fuzzy pick files (bat preview) | bash, Nushell (`fe` in PowerShell) |
| `Alt+C` | fuzzy `cd` into a sub-directory | bash, Nushell (`fcd` in PowerShell) |
| `z <name>` / `zi` | jump to a frequently used directory | all |
| `ls`, `ll`, `la`, `lt` | eza: list, long, long + hidden, tree | all (Nushell keeps its own `ls`; use `l`) |
| `cat` | bat | all |
| `df` / `du` | duf / dust | all (Nushell keeps its own `du`) |
| `rgf <pattern>` | ripgrep + fzf, opens the match in VS Code | PowerShell |

## One-click install

The installers are safe to run again. Each run installs the **latest release** of every tool, so running
one again is also how you update. Existing configuration files are never overwritten.
A marked block (`# >>> terminal-customization >>>`) is added to them, and a `*.tc-backup-<date>` copy is
kept whenever a file is changed.

### Windows 10/11

Open **PowerShell** (no admin rights needed) and run:

```powershell
irm https://raw.githubusercontent.com/R3start/TerminalCustumization/main/install.ps1 | iex
```

Or from a clone: `.\install.ps1` (if blocked: `powershell -ExecutionPolicy Bypass -File .\install.ps1`).

Options (from a clone, or with `& ([scriptblock]::Create((irm <url>))) -Option`):

| Option | Effect |
|--------|--------|
| `-SkipTools` | don't install/upgrade anything with winget |
| `-SkipFonts` | don't install the Nerd Font |
| `-SkipConfig` | only install tools and font |
| `-NoDefaultShell` | keep your current default Windows Terminal profile |
| `-KeepOldModules` | don't remove PSReadLine/Terminal-Icons installed from the PowerShell Gallery |

What it does:
1. Uses `winget install` to install or upgrade Windows Terminal, PowerShell 7, Oh My Posh, Nushell, eza, bat,
   ripgrep, fzf, zoxide, duf, dust and gh.
2. Runs `oh-my-posh font install JetBrainsMono`.
3. Copies `config/` to `%USERPROFILE%\.config\terminal-customization`.
4. Adds one line to `Documents\PowerShell\profile.ps1` and `Documents\WindowsPowerShell\profile.ps1`.
   Those profiles apply to all hosts, including the VS Code terminal. It also comments out old
   PSReadLine/Terminal-Icons lines.
5. Configures Nushell and the bat theme.
6. Adds a **Nushell (Microverse)** Windows Terminal profile with the Microverse colour scheme and the Nerd Font,
   and makes it the default profile.

### Linux (x86_64 / aarch64, any distribution)

Requires `curl`, `tar` and `unzip`. No root access is needed.

```bash
curl -fsSL https://raw.githubusercontent.com/R3start/TerminalCustumization/main/install.sh | bash
```

Or from a clone: `./install.sh`. Pass options with `curl … | bash -s -- --option`:

| Option | Effect |
|--------|--------|
| `--skip-tools` | don't download the tools |
| `--skip-fonts` | don't install the Nerd Font |
| `--skip-config` | don't change any shell configuration |
| `--no-default-shell` | keep bash as the interactive shell |
| `--gnome-terminal` | also set the font and Microverse colours in the default GNOME Terminal profile |
| `--force` | reinstall tools even if the latest version is already installed |
| `--dry-run` | print which release files would be downloaded |

`GITHUB_TOKEN=<token>` avoids GitHub API rate limits on shared networks.

What it does:
1. Downloads the latest release of each tool from GitHub (static musl builds where available) into `~/.local/bin`.
   Oh My Posh comes from its official install script.
2. Runs `oh-my-posh font install JetBrainsMono` (into `~/.local/share/fonts`).
3. Copies `config/` to `~/.config/terminal-customization`.
4. Adds one line to `~/.bashrc` and comments out an old `oh-my-posh init bash` line if there is one.
   Also sets up Nushell, the bat theme, and PowerShell if `pwsh` is installed.
5. New interactive terminals start Nushell automatically.

After installing, **select `JetBrainsMono Nerd Font` in your terminal's settings**. The Windows Terminal
profile and `--gnome-terminal` do this for you.

---

## Manual installation – Windows

Do everything in a normal (non-admin) PowerShell window unless noted. The file references below are to this repository.

### 1. Terminal and PowerShell 7

```powershell
winget install Microsoft.WindowsTerminal --source winget
winget install Microsoft.PowerShell --source winget
```

### 2. Tools

```powershell
winget install JanDeDobbeleer.OhMyPosh --source winget
winget install Nushell.Nushell         --source winget
winget install eza-community.eza       --source winget
winget install sharkdp.bat             --source winget
winget install BurntSushi.ripgrep.MSVC --source winget
winget install junegunn.fzf            --source winget
winget install ajeetdsouza.zoxide      --source winget
winget install muesli.duf              --source winget
winget install bootandy.dust           --source winget
winget install GitHub.cli              --source winget
```

Close and reopen the terminal so the new `PATH` is picked up.

### 3. Font

```powershell
oh-my-posh font install JetBrainsMono
```

Alternatively, download `JetBrainsMono.zip` from the latest [Nerd Fonts release](https://github.com/ryanoasis/nerd-fonts/releases/latest),
extract it, select all `.ttf` files, then right-click → **Install** (or **Install for all users**).

Then set the font in each terminal:
- **Windows Terminal**: *Settings → Profiles → Defaults → Appearance → Font face* → `JetBrainsMono Nerd Font`.
- **VS Code**: `"terminal.integrated.fontFamily": "JetBrainsMono Nerd Font"` in `settings.json`.

### 4. Shared configuration files

Copy the repo's `config` folder to `%USERPROFILE%\.config\terminal-customization`:

```powershell
git clone https://github.com/R3start/TerminalCustumization.git
New-Item -ItemType Directory "$HOME\.config" -Force | Out-Null
Copy-Item -Recurse -Force .\TerminalCustumization\config "$HOME\.config\terminal-customization"
```

### 5. PowerShell profile

Allow local scripts once: `Set-ExecutionPolicy RemoteSigned -Scope CurrentUser`.

Open the profile for all hosts (`notepad $PROFILE.CurrentUserAllHosts`; create it with
`New-Item -Force $PROFILE.CurrentUserAllHosts` if it doesn't exist) and add:

```powershell
. "$HOME\.config\terminal-customization\powershell\profile.ps1"
```

Do this in both PowerShell 7 and Windows PowerShell 5.1 if you use both.
Remove any old `Import-Module PSReadLine`, `Set-PSReadLineOption`, `Import-Module Terminal-Icons` and
`oh-my-posh init` lines from `$PROFILE`. To also remove the modules the old setup installed:

```powershell
Uninstall-Module PSReadLine -AllVersions -Force      # only the PowerShell Gallery copy
Uninstall-Module Terminal-Icons -AllVersions -Force
```

What [`profile.ps1`](config/powershell/profile.ps1) does, if you prefer to copy only parts of it:

```powershell
oh-my-posh init pwsh --config "$HOME\.config\terminal-customization\oh-my-posh\microverse-power.omp.json" | Invoke-Expression
$env:EZA_CONFIG_DIR        = "$HOME\.config\terminal-customization\eza"
$env:FZF_DEFAULT_OPTS_FILE = "$HOME\.config\terminal-customization\fzf\fzfrc"
$env:RIPGREP_CONFIG_PATH   = "$HOME\.config\terminal-customization\ripgrep\ripgreprc"
$env:BAT_THEME             = 'Microverse'
Remove-Item Alias:ls -Force; function ls { eza --icons=auto --group-directories-first @args }
Remove-Item Alias:cat -Force; function cat { bat --paging=never @args }
function df { duf @args }; function du { dust @args }
gh completion -s powershell | Out-String | Invoke-Expression
Invoke-Expression (& { (zoxide init powershell | Out-String) })   # keep last
# plus the fzf helpers fe, fcd, fh and rgf
```

### 6. bat theme

```powershell
New-Item -ItemType Directory "$(bat --config-dir)\themes" -Force | Out-Null
Copy-Item "$HOME\.config\terminal-customization\bat\themes\Microverse.tmTheme" "$(bat --config-dir)\themes\"
bat cache --build
```

### 7. Nushell

Run these **inside `nu`**:

```nu
mkdir ($nu.default-config-dir | path join autoload)
cp ~/.config/terminal-customization/nushell/terminal-customization.nu ($nu.default-config-dir | path join autoload)
config nu      # opens config.nu: paste the contents of config/nushell/config-snippet.nu at the end
```

[`config-snippet.nu`](config/nushell/config-snippet.nu) runs `oh-my-posh init nu`, `zoxide init nushell` and
`fzf --nushell` on every start, so the integrations always match the installed versions. Restart `nu`.

### 8. Make Nushell the default shell

Copy [`config/windows-terminal/terminal-customization.json`](config/windows-terminal/terminal-customization.json) to
`%LOCALAPPDATA%\Microsoft\Windows Terminal\Fragments\TerminalCustomization\`. This adds the **Nushell (Microverse)**
profile and the **Microverse** colour scheme. Restart Windows Terminal, then open *Settings → Startup → Default profile* →
**Nushell (Microverse)** → *Save*.

Without the fragment, you can add a profile by hand: *Settings → Add a new profile → New empty profile*, command line `nu.exe`,
font `JetBrainsMono Nerd Font`.

VS Code: add `"terminal.integrated.defaultProfile.windows": "Nushell"` and a profile entry
`"terminal.integrated.profiles.windows": { "Nushell": { "path": "nu.exe" } }`.

### 9. GitHub CLI

```powershell
gh auth login
```

---

## Manual installation – Linux

Most distribution packages are outdated or missing (for example `eza`, `dust` and `duf`, or `bat` installed as
`batcat`), so these steps use the official GitHub release binaries. Replace `x86_64`/`amd64` with
`aarch64`/`arm64` on ARM machines.

### 1. Tools

Make sure `~/.local/bin` exists and is in your `PATH`:

```bash
mkdir -p ~/.local/bin && export PATH="$HOME/.local/bin:$PATH"
```

**Oh My Posh** (official installer):

```bash
curl -s https://ohmyposh.dev/install.sh | bash -s -- -d ~/.local/bin
```

**Everything else**: open each tool's *latest release* page, download the archive listed, extract it, and copy the
binary to `~/.local/bin`:

| Tool | Latest release | Archive (x86_64) | Binary |
|------|----------------|------------------|--------|
| Nushell | [nushell/nushell](https://github.com/nushell/nushell/releases/latest) | `nu-<ver>-x86_64-unknown-linux-musl.tar.gz` | `nu` |
| eza | [eza-community/eza](https://github.com/eza-community/eza/releases/latest) | `eza_x86_64-unknown-linux-musl.tar.gz` | `eza` |
| bat | [sharkdp/bat](https://github.com/sharkdp/bat/releases/latest) | `bat-v<ver>-x86_64-unknown-linux-musl.tar.gz` | `bat` |
| ripgrep | [BurntSushi/ripgrep](https://github.com/BurntSushi/ripgrep/releases/latest) | `ripgrep-<ver>-x86_64-unknown-linux-musl.tar.gz` | `rg` |
| fzf | [junegunn/fzf](https://github.com/junegunn/fzf/releases/latest) | `fzf-<ver>-linux_amd64.tar.gz` | `fzf` |
| zoxide | [ajeetdsouza/zoxide](https://github.com/ajeetdsouza/zoxide/releases/latest) | `zoxide-<ver>-x86_64-unknown-linux-musl.tar.gz` | `zoxide` |
| duf | [muesli/duf](https://github.com/muesli/duf/releases/latest) | `duf_<ver>_linux_x86_64.tar.gz` | `duf` |
| dust | [bootandy/dust](https://github.com/bootandy/dust/releases/latest) | `dust-v<ver>-x86_64-unknown-linux-musl.tar.gz` | `dust` |
| gh | [cli/cli](https://github.com/cli/cli/releases/latest) | `gh_<ver>_linux_amd64.tar.gz` | `bin/gh` |

Example for one tool:

```bash
cd /tmp
curl -LO https://github.com/eza-community/eza/releases/latest/download/eza_x86_64-unknown-linux-musl.tar.gz
tar -xzf eza_x86_64-unknown-linux-musl.tar.gz
install -m 755 eza ~/.local/bin/
eza --version
```

(`./install.sh --skip-fonts --skip-config` does exactly this for every tool.)

### 2. Font

```bash
oh-my-posh font install JetBrainsMono
fc-cache -f
```

Alternatively, download `JetBrainsMono.tar.xz` from the latest [Nerd Fonts release](https://github.com/ryanoasis/nerd-fonts/releases/latest)
and extract it into `~/.local/share/fonts`. Then select **JetBrainsMono Nerd Font** in your terminal's preferences.
On WSL, install the font on **Windows** instead; the terminal runs there.

### 3. Shared configuration files

```bash
git clone https://github.com/R3start/TerminalCustumization.git
mkdir -p ~/.config/terminal-customization
cp -r TerminalCustumization/config/. ~/.config/terminal-customization/
```

### 4. bash

Add to the end of `~/.bashrc` and remove any old `oh-my-posh init bash --config ~/.poshthemes/...` line:

```bash
[ -f "$HOME/.config/terminal-customization/bash/terminal-customization.bash" ] && . "$HOME/.config/terminal-customization/bash/terminal-customization.bash"
```

[`terminal-customization.bash`](config/bash/terminal-customization.bash) initialises Oh My Posh, fzf (`eval "$(fzf --bash)"`),
zoxide and gh completion, and sets the eza/bat/duf/dust aliases. It also hands the terminal over to Nushell (see step 7).
Run `exec bash` to reload.

### 5. bat theme

```bash
mkdir -p "$(bat --config-dir)/themes"
cp ~/.config/terminal-customization/bat/themes/Microverse.tmTheme "$(bat --config-dir)/themes/"
bat cache --build
```

### 6. Nushell

Run these **inside `nu`**:

```nu
mkdir ($nu.default-config-dir | path join autoload)
cp ~/.config/terminal-customization/nushell/terminal-customization.nu ($nu.default-config-dir | path join autoload)
config nu      # paste the contents of config/nushell/config-snippet.nu at the end
```

### 7. Make Nushell the default shell

The bash config from step 4 runs `exec nu` in interactive terminals, so every new terminal opens Nushell.
Your login shell stays bash, so scripts, `ssh host command` and system tools keep working. To turn it off:

```bash
touch ~/.config/terminal-customization/no-nu     # permanently
TC_NO_NU=1 bash                                  # just this once
```

If you'd rather configure your terminal emulator, set its command to `nu` (for example in GNOME Terminal: *Preferences →
Profile → Command → Run a custom command instead of my shell* → `nu`).

### 8. Terminal colours (optional)

The Microverse palette as terminal colours (0–15):
`#242424 #F1184C #33DD2D #FFBB00 #3A86FF #B45CFF #2EC4E6 #D0D0D0 #6C6C6C #FF4D74 #66F060 #FFD24D #6FA8FF #CC8CFF #6FDAF2 #FFFFFF`,
background `#1B1B1B`, foreground `#E6E6E6`. `./install.sh --skip-tools --skip-fonts --gnome-terminal` applies them to GNOME Terminal.

### 9. PowerShell on Linux (optional)

If you use `pwsh`, add `. "$HOME/.config/terminal-customization/powershell/profile.ps1"` to `$PROFILE.CurrentUserAllHosts`.

### 10. GitHub CLI

```bash
gh auth login
```

---

## Updating

- **One-click:** run the installer again. Tools are upgraded to their latest releases and the config files are refreshed.
- **Windows, manually:** `winget upgrade --all` (or `winget upgrade <id>`), then `oh-my-posh font install JetBrainsMono`.
- **Linux, manually:** repeat the download step for each tool, and use `oh-my-posh upgrade`.

## Uninstalling

1. Remove the `# >>> terminal-customization >>>` … `# <<< terminal-customization <<<` blocks from `~/.bashrc`,
   the PowerShell `profile.ps1` files and Nushell's `config.nu`. The `.tc-backup-*` files next to them are the previous versions.
2. Delete `~/.config/terminal-customization`, plus `terminal-customization.nu`, `zoxide.nu` and `fzf.nu` from Nushell's `autoload` folder.
3. Windows: delete `%LOCALAPPDATA%\Microsoft\Windows Terminal\Fragments\TerminalCustomization` and choose another default profile.
   To remove the tools: `winget uninstall <id>`.
4. Linux: delete the binaries from `~/.local/bin` (`nu nu_plugin_* eza bat rg fzf zoxide duf dust gh oh-my-posh`).

## Troubleshooting

| Problem | Fix |
|---------|-----|
| Squares or `?` instead of icons | Select **JetBrainsMono Nerd Font** in the terminal settings. On WSL/SSH, install the font on the machine running the terminal. |
| `command not found` right after installing | Open a new terminal. On Linux, check that `~/.local/bin` is in `PATH`. |
| PowerShell: "running scripts is disabled" | `Set-ExecutionPolicy RemoteSigned -Scope CurrentUser` |
| Want bash/PowerShell back as the default | Linux: `touch ~/.config/terminal-customization/no-nu`. Windows: pick another default profile in Windows Terminal. |
| `install.sh` fails with HTTP 403 from api.github.com | GitHub rate limit: set `GITHUB_TOKEN` or wait an hour. The script also falls back to the release web pages. |
| winget errors on an old Windows 10 | Update **App Installer** from the Microsoft Store (<https://aka.ms/getwinget>). |
| Nushell prompt has no theme | Oh My Posh needs Nushell ≥ 0.104: upgrade Nushell and re-run the installer. |

## Repository layout

```
install.ps1                       Windows one-click installer (winget)
install.sh                        Linux one-click installer (GitHub releases)
config/
  oh-my-posh/microverse-power.omp.json   prompt theme
  bash/terminal-customization.bash       bash config
  powershell/profile.ps1                 PowerShell 5.1/7 config
  nushell/terminal-customization.nu      Nushell config (autoload)
  nushell/config-snippet.nu              block appended to config.nu
  bat/themes/Microverse.tmTheme          bat theme
  eza/theme.yml                          eza colours
  fzf/fzfrc                              fzf defaults and colours
  ripgrep/ripgreprc                      ripgrep defaults and colours
  windows-terminal/terminal-customization.json   Windows Terminal profile + colour scheme
docs/tools/                       one usage guide per tool
```

## License

[The Unlicense](LICENSE) (public domain)
