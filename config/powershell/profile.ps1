# TerminalCustumization - PowerShell profile
# Works with PowerShell 7+ (Windows/Linux) and Windows PowerShell 5.1.
# Dot-sourced from $PROFILE:
#   . "$HOME/.config/terminal-customization/powershell/profile.ps1"
#
# PSReadLine (part of PowerShell) is only used for the fzf key bindings Ctrl+T / Ctrl+R / Alt+C;
# its predictions and list view are not configured. Run `tc-doctor` to see what loaded.

# Load once per session: the installer adds this to both $PROFILE and profile.ps1.
if ($global:TcProfileLoaded) { return }
$global:TcProfileLoaded = $true

$TcHome = if ($env:TC_HOME) { $env:TC_HOME } else { Join-Path $HOME '.config/terminal-customization' }

# Linux: tools installed by install.sh live in ~/.local/bin
$TcLocalBin = Join-Path $HOME '.local/bin'
if (($IsLinux -or $IsMacOS) -and (Test-Path $TcLocalBin) -and
    -not (($env:PATH -split [IO.Path]::PathSeparator) -contains $TcLocalBin)) {
    $env:PATH = $TcLocalBin + [IO.Path]::PathSeparator + $env:PATH
}

# Windows: a shell started by a program that was already running before the tools were installed
# (Visual Studio and its Developer PowerShell, an old Explorer window) inherits an outdated PATH,
# so the new tools are missing or an older copy (e.g. of oh-my-posh) is found first. Put the PATH
# entries that new processes get (machine + user, from the registry) in front when they are missing.
if ($env:OS -eq 'Windows_NT') {
    $TcCurrentPath = @($env:Path -split ';' | Where-Object { $_ })
    $TcMissing = @(
        [Environment]::GetEnvironmentVariable('Path', 'Machine')
        [Environment]::GetEnvironmentVariable('Path', 'User')
        (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links')
    ) -join ';' -split ';' | Where-Object { $_ } |
        ForEach-Object { [Environment]::ExpandEnvironmentVariables($_) } |
        Where-Object { $TcCurrentPath -notcontains $_ } | Select-Object -Unique
    if ($TcMissing) { $env:Path = (@($TcMissing) + $TcCurrentPath) -join ';' }
    Remove-Variable TcCurrentPath, TcMissing
}

function Test-TcCommand([string]$Name) {
    [bool](Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue)
}

# --- Nushell as the default interactive shell -------------------------------
# A PowerShell window opened normally (Start menu, a Windows Terminal PowerShell tab, `pwsh` on
# Linux) hands over to Nushell, like bash does. PowerShell stays when:
#   - it was started to run something (-Command, -File, ...), e.g. the Visual Studio Developer
#     PowerShell, VS Code, scripts;
#   - it runs inside Nushell (TC_IN_NU is set there, so typing `powershell` in nu gives PowerShell);
#   - TC_NO_NU is set, or ~/.config/terminal-customization/no-nu exists
#     (install.ps1 -NoDefaultShell / install.sh --no-default-shell).
# If Nushell fails right away, PowerShell simply continues.
$TcExtraArgs = @([Environment]::GetCommandLineArgs() | Select-Object -Skip 1 |
    Where-Object { $_ -notmatch '^-(nologo|login|l|interactive|mta|sta)$' })
$global:TcNushellStatus = if ($env:TC_IN_NU) { 'stays PowerShell: started from Nushell (TC_IN_NU)' }
    elseif ($env:TC_NO_NU) { 'stays PowerShell: TC_NO_NU is set' }
    elseif ($TcExtraArgs.Count) { "stays PowerShell: started to run something ($($TcExtraArgs -join ' '))" }
    elseif (Test-Path (Join-Path $TcHome 'no-nu')) { 'stays PowerShell: no-nu file (install.ps1 -NoDefaultShell)' }
    elseif ($Host.Name -ne 'ConsoleHost') { "stays PowerShell: host is $($Host.Name)" }
    else { 'hands over to Nushell' }
if (-not $env:TC_IN_NU -and -not $env:TC_NO_NU -and $TcExtraArgs.Count -eq 0 -and
    $Host.Name -eq 'ConsoleHost' -and -not [Console]::IsInputRedirected -and -not [Console]::IsOutputRedirected -and
    -not (Test-Path (Join-Path $TcHome 'no-nu'))) {
    $TcNu = Get-Command nu -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $TcNu) { $global:TcNushellStatus = 'stays PowerShell: nu not found on PATH' }
    if ($TcNu) {
        $env:TC_IN_NU = '1'
        $TcStarted = Get-Date
        $TcRan = $false
        try { & $TcNu.Source; $TcRan = $true } catch { Write-Warning "Could not start Nushell: $($_.Exception.Message)" }
        if ($TcRan -and ($LASTEXITCODE -eq 0 -or ((Get-Date) - $TcStarted).TotalSeconds -gt 5)) {
            # Leaving nu closes the window, as if nu had been started directly.
            [Environment]::Exit([int]$LASTEXITCODE)
        }
        if ($TcRan) { Write-Warning "Nushell exited with code $LASTEXITCODE right after starting; staying in PowerShell." }
        $global:TcNushellStatus = 'stays PowerShell: Nushell failed to start'
        Remove-Item Env:TC_IN_NU -ErrorAction SilentlyContinue
    }
}
Remove-Variable TcExtraArgs -ErrorAction SilentlyContinue

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
# ls stays PowerShell's native Get-ChildItem (structured objects, pipeable), like Nushell keeps
# its own ls; use l for eza's colourful listing, same split as Nushell's ls/l.
if (Test-TcCommand eza) {
    function l { eza --icons=auto --group-directories-first @args }
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

    # Ctrl+T / Ctrl+R / Alt+C, like in bash and Nushell (PSReadLine key handlers only).
    if (Get-Command Set-PSReadLineKeyHandler -ErrorAction SilentlyContinue) {
        # Ctrl+T: pick files (bat preview) and insert them at the cursor
        Set-PSReadLineKeyHandler -Chord 'Ctrl+t' -BriefDescription 'FzfFiles' -Description 'fzf: insert files' -ScriptBlock {
            $picked = @(fzf --multi --scheme=path --preview 'bat --color=always --style=numbers --line-range=:300 {}')
            if ($picked.Count) {
                $quoted = foreach ($path in $picked) {
                    if ($path -match "[\s'`"``$&(){}@;,]") { "'" + ($path -replace "'", "''") + "'" } else { $path }
                }
                [Microsoft.PowerShell.PSConsoleReadLine]::Insert(($quoted -join ' '))
            }
            [Microsoft.PowerShell.PSConsoleReadLine]::InvokePrompt()
        }

        # Ctrl+R: search the command history; the chosen command replaces the line (not run)
        Set-PSReadLineKeyHandler -Chord 'Ctrl+r' -BriefDescription 'FzfHistory' -Description 'fzf: search history' -ScriptBlock {
            $line = $null
            $cursor = $null
            [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)
            $file = (Get-PSReadLineOption).HistorySavePath
            $history = @(if ($file -and (Test-Path $file)) { Get-Content $file } else { (Get-History).CommandLine })
            [array]::Reverse($history)
            $seen = New-Object 'System.Collections.Generic.HashSet[string]'
            $unique = foreach ($entry in $history) { if ($entry -and $seen.Add($entry)) { $entry } }
            $picked = $unique | fzf --no-sort --scheme=history --prompt 'history> ' --query "$line"
            if ($picked) {
                [Microsoft.PowerShell.PSConsoleReadLine]::RevertLine()
                [Microsoft.PowerShell.PSConsoleReadLine]::Insert(@($picked)[0])
            }
            [Microsoft.PowerShell.PSConsoleReadLine]::InvokePrompt()
        }

        # Alt+C: pick a directory below the current one (eza tree preview) and cd into it.
        # fzf's own walker lists directories only while FZF_DEFAULT_COMMAND is unset.
        Set-PSReadLineKeyHandler -Chord 'Alt+c' -BriefDescription 'FzfCd' -Description 'fzf: cd into a directory' -ScriptBlock {
            $saved = $env:FZF_DEFAULT_COMMAND
            $env:FZF_DEFAULT_COMMAND = $null
            try {
                $dir = fzf --walker=dir,follow,hidden --scheme=path --preview 'eza --tree --level=2 --icons=always --color=always {}'
            } finally {
                $env:FZF_DEFAULT_COMMAND = $saved
            }
            if ($dir) { Set-Location -LiteralPath $dir }
            [Microsoft.PowerShell.PSConsoleReadLine]::InvokePrompt()
        }
    }
}

# --- tc-doctor: what this setup loaded in the current session ------------------
function Test-TerminalCustomization {
    "PowerShell $($PSVersionTable.PSVersion) ($($PSVersionTable.PSEdition)), host: $($Host.Name)"
    "Command line : $([Environment]::CommandLine)"
    "Config folder: $TcHome (exists: $(Test-Path $TcHome))"
    "Nushell      : $global:TcNushellStatus"
    ''
    'Profile files ([block] = contains the terminal-customization block):'
    foreach ($name in 'AllUsersAllHosts', 'AllUsersCurrentHost', 'CurrentUserAllHosts', 'CurrentUserCurrentHost') {
        $path = $PROFILE.$name
        $state = if (-not (Test-Path $path)) { 'missing' }
            elseif (Select-String -Path $path -SimpleMatch '# >>> terminal-customization >>>' -Quiet) { 'exists [block]' }
            else { 'exists' }
        '  {0,-23} {1} ({2})' -f $name, $path, $state
    }
    ''
    'Tools (first match on PATH wins):'
    foreach ($tool in 'oh-my-posh', 'nu', 'eza', 'bat', 'rg', 'fzf', 'zoxide', 'duf', 'dust', 'gh') {
        $found = @(Get-Command $tool -CommandType Application -All -ErrorAction SilentlyContinue | ForEach-Object { $_.Source } | Select-Object -Unique)
        if (-not $found) { '  {0,-11} NOT FOUND' -f $tool; continue }
        $version = try {
            $text = if ($tool -eq 'oh-my-posh') { & $found[0] version 2>$null } else { & $found[0] --version 2>$null }
            (($text | Out-String) -split "`n" | Where-Object { $_.Trim() } | Select-Object -First 1).Trim()
        } catch { '?' }
        '  {0,-11} {1}  [{2}]' -f $tool, $found[0], $version
        foreach ($other in ($found | Select-Object -Skip 1)) { '  {0,-11} also: {1}' -f '', $other }
    }
    ''
    'Commands:'
    foreach ($name in 'ls', 'l', 'll', 'la', 'lt', 'cat', 'df', 'du', 'z', 'zi', 'fe', 'fcd', 'fh', 'rgf') {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue | Select-Object -First 1
        $what = if (-not $cmd) { 'not defined' }
            elseif ($cmd.CommandType -eq 'Alias') { "alias -> $($cmd.Definition)" }
            elseif ($cmd.CommandType -eq 'Function') { 'function: ' + (($cmd.Definition -split "`n" | Where-Object { $_.Trim() } | Select-Object -First 1).Trim()) }
            else { "$($cmd.CommandType): $($cmd.Source)" }
        '  {0,-4} {1}' -f $name, $what
    }
    ''
    'Key bindings:'
    if (Get-Command Get-PSReadLineKeyHandler -ErrorAction SilentlyContinue) {
        $bound = @(Get-PSReadLineKeyHandler -Bound | Where-Object { $_.Key -in 'Ctrl+t', 'Ctrl+r', 'Alt+c' })
        foreach ($key in 'Ctrl+t', 'Ctrl+r', 'Alt+c') {
            $handler = $bound | Where-Object { $_.Key -eq $key } | Select-Object -First 1
            '  {0,-7} {1}' -f $key, $(if ($handler) { $handler.Function } else { 'not bound' })
        }
    } else {
        '  PSReadLine is not loaded in this host'
    }
}
Set-Alias tc-doctor Test-TerminalCustomization

# --- gh: GitHub CLI completion ----------------------------------------------
if (Test-TcCommand gh) {
    gh completion -s powershell | Out-String | Invoke-Expression
}

# --- zoxide: smarter cd (z, zi). Keep last: it hooks into the prompt. -----------
if (Test-TcCommand zoxide) {
    Invoke-Expression (& { (zoxide init powershell | Out-String) })
}
