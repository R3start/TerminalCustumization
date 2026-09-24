# GitHub CLI (`gh`)

<https://cli.github.com> · [manual](https://cli.github.com/manual/)

`gh` brings pull requests, issues, releases, Actions and more to the terminal.

## Install

| | Command |
|-|---------|
| Windows | `winget install GitHub.cli --source winget` |
| Linux | `gh_<version>_linux_<amd64\|arm64>.tar.gz` from the [latest release](https://github.com/cli/cli/releases/latest) → `~/.local/bin` (or the [official apt/dnf repos](https://github.com/cli/cli/blob/trunk/docs/install_linux.md)) |

## First run

```bash
gh auth login          # sign in (browser or token), also sets up git credentials
gh auth status
```

Tab completion is enabled in bash and PowerShell by this setup (`gh completion -s <shell>`).

## Everyday commands

```bash
gh repo clone owner/repo
gh repo view --web                 # open the repo in the browser
gh pr create --fill                # PR from the current branch
gh pr list / gh pr status
gh pr checkout 123
gh pr view 123 --web
gh pr merge --squash --delete-branch
gh issue list --assignee @me
gh issue create --title "Bug" --body "Details"
gh run list / gh run watch         # GitHub Actions
gh release create v1.0.0 --generate-notes
gh browse                          # open the current repo in the browser
gh search repos nushell --limit 5
gh alias set prs 'pr list --author @me'
```

Upgrade: `winget upgrade GitHub.cli` on Windows, re-run `install.sh` on Linux.
