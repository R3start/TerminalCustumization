# zoxide – smarter `cd`

<https://github.com/ajeetdsouza/zoxide>

![zoxide in the microverse theme](../images/zoxide.png)

zoxide remembers the directories you visit and jumps to the best match from a few letters.

## Install

| | Command |
|-|---------|
| Windows | `winget install ajeetdsouza.zoxide --source winget` |
| Linux | `zoxide-<version>-<arch>-unknown-linux-musl.tar.gz` from the [latest release](https://github.com/ajeetdsouza/zoxide/releases/latest) → `~/.local/bin` |

## Shell integration (done by the installer)

```bash
eval "$(zoxide init bash)"                                   # bash, at the end of the config
```
```powershell
Invoke-Expression (& { (zoxide init powershell | Out-String) }) # PowerShell, at the end of the profile
```
```nu
zoxide init nushell | save -f ($nu.default-config-dir | path join autoload zoxide.nu)   # Nushell
```

## Everyday commands

| Command | Action |
|---------|--------|
| `z proj` | jump to the highest ranked directory matching `proj` |
| `z proj api` | match several words, in order |
| `z ..`, `z -`, `z ~/code` | behaves like `cd` for real paths |
| `zi` / `zi proj` | pick interactively with fzf |
| `zoxide query -ls` | list the database with scores |
| `zoxide add <path>` / `zoxide remove <path>` | edit the database |

Tip: `cd` is untouched. If you want `cd` itself to use zoxide, change the init line to `zoxide init bash --cmd cd`
(same flag for PowerShell and Nushell).
