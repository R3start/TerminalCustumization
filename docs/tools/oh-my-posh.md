# Oh My Posh – prompt theme engine

<https://ohmyposh.dev> · <https://github.com/JanDeDobbeleer/oh-my-posh>

Oh My Posh draws the prompt. This setup uses the **microverse-power** theme, stored in the repo at
[`config/oh-my-posh/microverse-power.omp.json`](../../config/oh-my-posh/microverse-power.omp.json)
and installed to `~/.config/terminal-customization/oh-my-posh/`.

```
 <os>  user  2026-09-24 10:15:00   ~/projects/app   main   
➜
```

Segments: OS icon · user (red) · date/time (yellow) · full path (green) · git branch + stash count (blue) ·
status (green, red when the last command failed), then `➜` on a new line.

## Install

| | Command |
|-|---------|
| Windows | `winget install JanDeDobbeleer.OhMyPosh --source winget` |
| Linux | `curl -s https://ohmyposh.dev/install.sh \| bash -s -- -d ~/.local/bin` |

Upgrade: `winget upgrade JanDeDobbeleer.OhMyPosh` / run the Linux command again (or `oh-my-posh upgrade`).

## Enable it in a shell

```bash
# bash (~/.bashrc)
eval "$(oh-my-posh init bash --config ~/.config/terminal-customization/oh-my-posh/microverse-power.omp.json)"
```
```powershell
# PowerShell ($PROFILE)
oh-my-posh init pwsh --config "$HOME\.config\terminal-customization\oh-my-posh\microverse-power.omp.json" | Invoke-Expression
```
```nu
# Nushell (last line of config.nu) - writes its script into the vendor autoload folder
oh-my-posh init nu --config ('~/.config/terminal-customization/oh-my-posh/microverse-power.omp.json' | path expand)
```

## Everyday commands

| Command | What it does |
|---------|--------------|
| `oh-my-posh font install JetBrainsMono` | install/upgrade the Nerd Font used by this setup |
| `oh-my-posh font list` | list all installable Nerd Fonts |
| `oh-my-posh version` | show the installed version |
| `oh-my-posh upgrade` | upgrade (manual/Linux installs) |
| `oh-my-posh debug` | show why a segment is slow or missing |
| `oh-my-posh config export --output ~/my.omp.json` | export the current theme so you can edit it |

## Changing the theme

Browse themes at <https://ohmyposh.dev/docs/themes>. Either edit the JSON file above or point `--config`
at another theme name (e.g. `--config jandedobbeleer`) or file. Icons need a **Nerd Font** in your terminal.
