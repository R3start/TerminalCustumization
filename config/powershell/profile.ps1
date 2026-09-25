# TerminalCustumization - PowerShell profile
# Works with PowerShell 7+ (Windows/Linux) and Windows PowerShell 5.1.
# Dot-sourced from $PROFILE:
#   . "$HOME/.config/terminal-customization/powershell/profile.ps1"
#
# PSReadLine is intentionally not configured; history search, file search and
# directory jumping are provided by fzf and zoxide instead.

$TcHome = if ($env:TC_HOME) { $env:TC_HOME } else { Join-Path $HOME '.config/terminal-customization' }

# Linux: tools installed by install.sh live in ~/.local/bin
$TcLocalBin = Join-Path $HOME '.local/bin'
if (($IsLinux -or $IsMacOS) -and (Test-Path $TcLocalBin) -and
    -not (($env:PATH -split [IO.Path]::PathSeparator) -contains $TcLocalBin)) {
    $env:PATH = $TcLocalBin + [IO.Path]::PathSeparator + $env:PATH
}

function Test-TcCommand([string]$Name) {
    [bool](Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue)
}

# --- shared tool settings (same files as bash / Nushell) --------------------
$env:EZA_CONFIG_DIR        = Join-Path $TcHome 'eza'
$env:FZF_DEFAULT_OPTS_FILE = Join-Path $TcHome 'fzf/fzfrc'
$env:RIPGREP_CONFIG_PATH   = Join-Path $TcHome 'ripgrep/ripgreprc'
$env:BAT_THEME             = 'Microverse'
if (Test-TcCommand rg) {
    $env:FZF_DEFAULT_COMMAND = 'rg --files --hidden --glob "!.git/"'
}

# --- oh-my-posh prompt ------------------------------------------------------
if (Test-TcCommand oh-my-posh) {
    $TcTheme = Join-Path $TcHome 'oh-my-posh/microverse-power.omp.json'
    oh-my-posh init pwsh --config $TcTheme | Invoke-Expression
}

# --- eza: modern ls (replaces Terminal-Icons) -------------------------------
if (Test-TcCommand eza) {
    Remove-Item Alias:ls -Force -ErrorAction SilentlyContinue
    function ls { eza --icons=auto --group-directories-first @args }
    function ll { eza --icons=auto --group-directories-first --long --header --git @args }
    function la { eza --icons=auto --group-directories-first --long --header --git --all @args }
    function lt { eza --icons=auto --group-directories-first --tree --level=2 @args }
}

# --- bat: cat with syntax highlighting --------------------------------------
if (Test-TcCommand bat) {
    Remove-Item Alias:cat -Force -ErrorAction SilentlyContinue
    function cat { bat --paging=never @args }
}

# --- duf / dust: disk usage -------------------------------------------------
if (Test-TcCommand duf)  { function df { duf @args } }
if (Test-TcCommand dust) { function du { dust @args } }

# --- fzf helpers --------------------------------------------------------------
if (Test-TcCommand fzf) {
    # fe [query]  - pick a file (bat preview) and open it in $env:EDITOR / VS Code / notepad
    function fe {
        $file = fzf --query "$args" --preview 'bat --color=always --style=numbers --line-range=:300 {}'
        if (-not $file) { return }
        $editor = if ($env:EDITOR) { $env:EDITOR } elseif (Test-TcCommand code) { 'code' } elseif ($IsLinux) { 'nano' } else { 'notepad' }
        & $editor $file
    }

    # fcd [query] - pick a directory (eza tree preview) and cd into it
    function fcd {
        $list = if (Test-TcCommand rg) {
            rg --files --hidden 2>$null | ForEach-Object { Split-Path $_ -Parent } | Where-Object { $_ } | Sort-Object -Unique
        } else {
            Get-ChildItem -Directory -Recurse -Name -ErrorAction SilentlyContinue
        }
        $dir = $list | fzf --query "$args" --preview 'eza --tree --level=2 --icons=always --color=always {}'
        if ($dir) { Set-Location $dir }
    }

    # fh [query]  - search command history and run the selected command
    function fh {
        $historyFile = if ($IsLinux -or $IsMacOS) {
            Join-Path $HOME '.local/share/powershell/PSReadLine/ConsoleHost_history.txt'
        } else {
            Join-Path $env:APPDATA 'Microsoft/Windows/PowerShell/PSReadLine/ConsoleHost_history.txt'
        }
        $history = @(if (Test-Path $historyFile) { Get-Content $historyFile } else { (Get-History).CommandLine })
        [array]::Reverse($history)
        $command = $history | Select-Object -Unique | fzf --query "$args" --no-sort --prompt 'history> '
        if ($command) {
            Write-Host $command -ForegroundColor DarkGray
            Invoke-Expression $command
        }
    }

    # rgf <pattern> - ripgrep, pick a match (bat preview), open file at that line in VS Code or print it
    function rgf {
        if (-not (Test-TcCommand rg)) { Write-Warning 'ripgrep (rg) is not installed'; return }
        # Fields are separated by a tab, not ':', so Windows paths (C:\...) are not split.
        $hit = rg --line-number --no-heading --color=always --field-match-separator "`t" @args |
            fzf --ansi --delimiter "`t" --preview 'bat --color=always --highlight-line {2} {1}' --preview-window '+{2}-/2'
        if (-not $hit) { return }
        $file, $line, $null = $hit -split "`t", 3
        if (Test-TcCommand code) { code --goto "${file}:${line}" } else { bat --paging=never --highlight-line $line $file }
    }
}

# --- gh: GitHub CLI completion ----------------------------------------------
if (Test-TcCommand gh) {
    gh completion -s powershell | Out-String | Invoke-Expression
}

# --- zoxide: smarter cd (z, zi). Keep last: it hooks into the prompt. -----------
if (Test-TcCommand zoxide) {
    Invoke-Expression (& { (zoxide init powershell | Out-String) })
}
