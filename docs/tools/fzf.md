# fzf – command-line fuzzy finder

<https://github.com/junegunn/fzf>

![fzf in the microverse theme](../images/fzf.png)

fzf filters any list interactively. In this setup it replaces **PSReadLine's** history search and
predictions: history, files and directories are all searched with fzf.

## Install

| | Command |
|-|---------|
| Windows | `winget install junegunn.fzf --source winget` |
| Linux | `fzf-<version>-linux_<amd64\|arm64>.tar.gz` from the [latest release](https://github.com/junegunn/fzf/releases/latest) → `~/.local/bin` |

## Shortcuts in this setup

| Shell | Key / command | Action |
|-------|---------------|--------|
| bash, Nushell | `Ctrl+R` | search command history |
| bash, Nushell | `Ctrl+T` | pick files (bat preview) and paste them into the command line |
| bash, Nushell | `Alt+C` | pick a directory (eza tree preview) and `cd` into it |
| bash | `vim **<Tab>` | fuzzy completion for paths (`kill -9 **<Tab>` for processes) |
| all | `zi` | pick from zoxide's frequent directories |
| PowerShell | `fh [query]` | search history and run the chosen command |
| PowerShell | `fe [query]` | pick a file and open it in `$env:EDITOR` / VS Code |
| PowerShell | `fcd [query]` | pick a directory and `cd` into it |
| PowerShell | `rgf <pattern>` | ripgrep + fzf + bat preview, opens the match in VS Code |

Inside fzf: type to filter, `Ctrl+J/K` or arrows to move, `Tab` to multi-select, `Enter` to accept, `Esc` to cancel.
Search syntax: `'exact`, `^prefix`, `suffix$`, `!exclude`, `a | b`.

## Configuration

- Defaults (layout, border, microverse colours) live in [`config/fzf/fzfrc`](../../config/fzf/fzfrc), loaded with `FZF_DEFAULT_OPTS_FILE`.
- `FZF_DEFAULT_COMMAND` uses `rg --files --hidden`, so ignored files are skipped.
- Shell integration: bash `eval "$(fzf --bash)"`; Nushell `fzf --nushell | save -f ($nu.default-config-dir | path join autoload fzf.nu)`.

## Everyday commands

```bash
vim "$(fzf)"                                  # open a picked file
git branch | fzf | xargs git switch           # switch branch
fzf --preview 'bat --color=always {}'         # browse files with preview
ps aux | fzf | awk '{print $2}' | xargs kill  # pick a process to kill
```
