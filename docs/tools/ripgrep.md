# ripgrep (`rg`) – fast recursive search

<https://github.com/BurntSushi/ripgrep>

![ripgrep (`rg`) in the microverse theme](../images/ripgrep.png)

ripgrep searches file contents recursively, respects `.gitignore` and is much faster than `grep`/`Select-String`.

## Install

| | Command |
|-|---------|
| Windows | `winget install BurntSushi.ripgrep.MSVC --source winget` |
| Linux | `ripgrep-<version>-<arch>-unknown-linux-musl.tar.gz` from the [latest release](https://github.com/BurntSushi/ripgrep/releases/latest) → `~/.local/bin` |

## In this setup

- Defaults in [`config/ripgrep/ripgreprc`](../../config/ripgrep/ripgreprc) via `RIPGREP_CONFIG_PATH`:
  smart case, search hidden files (but not `.git/`), microverse colours (green paths, blue line numbers, red matches).
- fzf uses `rg --files` to list files, so `Ctrl+T` respects `.gitignore`.
- PowerShell: `rgf <pattern>` searches, lets you pick a match in fzf with a bat preview and opens it in VS Code.

## Everyday commands

```bash
rg TODO                      # search the current directory
rg -w user_id src/           # whole word, in src/
rg -t py import              # only Python files (rg --type-list)
rg -g '*.md' install         # glob filter
rg -l pattern                # only file names
rg -C 3 panic                # 3 lines of context
rg -F 'a.b(c)'               # literal string, no regex
rg -uu secret                # also ignored + hidden files
rg foo -r bar                # show what a replace would look like (does not edit files)
rg --files | rg config       # find files by name
```
