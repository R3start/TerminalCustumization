<#
.SYNOPSIS
    TerminalCustumization - one-click installer for Windows.

.DESCRIPTION
    Installs (or upgrades to the latest version) with winget:
      Windows Terminal, PowerShell 7, Oh My Posh, Nushell, eza, bat, ripgrep, fzf,
      zoxide, duf, dust and the GitHub CLI.
    Then installs the latest JetBrainsMono Nerd Font, copies the configuration to
    ~/.config/terminal-customization, wires up PowerShell 7, Windows PowerShell 5.1
    and Nushell, adds a "Nushell (Microverse)" Windows Terminal profile and makes it
    the default. Re-running the script upgrades everything.

.EXAMPLE
    irm https://raw.githubusercontent.com/R3start/TerminalCustumization/main/install.ps1 | iex

.EXAMPLE
    & ([scriptblock]::Create((irm https://raw.githubusercontent.com/R3start/TerminalCustumization/main/install.ps1))) -NoDefaultShell

.EXAMPLE
    .\install.ps1 -SkipFonts
#>
[CmdletBinding()]
param(
    # Do not install/upgrade the tools with winget
    [switch]$SkipTools,
    # Do not install the JetBrainsMono Nerd Font
    [switch]$SkipFonts,
    # Do not touch profiles, Nushell or Windows Terminal settings
    [switch]$SkipConfig,
    # Keep the current default Windows Terminal profile (do not open Nushell by default)
    [switch]$NoDefaultShell,
    # Keep PSReadLine/Terminal-Icons modules installed from the PowerShell Gallery
    [switch]$KeepOldModules
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$RepoRaw = if ($env:TC_REPO_RAW) { $env:TC_REPO_RAW } else { 'https://raw.githubusercontent.com/R3start/TerminalCustumization/main' }
$TcHome = Join-Path $HOME '.config\terminal-customization'
$MarkBegin = '# >>> terminal-customization >>>'
$MarkEnd = '# <<< terminal-customization <<<'
$WtProfileName = 'Nushell (Microverse)'

# winget package id -> command it provides
$Packages = [ordered]@{
    'Microsoft.WindowsTerminal' = 'wt'
    'Microsoft.PowerShell'      = 'pwsh'
    'JanDeDobbeleer.OhMyPosh'   = 'oh-my-posh'
    'Nushell.Nushell'           = 'nu'
    'eza-community.eza'         = 'eza'
    'sharkdp.bat'               = 'bat'
    'BurntSushi.ripgrep.MSVC'   = 'rg'
    'junegunn.fzf'              = 'fzf'
    'ajeetdsouza.zoxide'        = 'zoxide'
    'muesli.duf'                = 'duf'
    'bootandy.dust'             = 'dust'
    'GitHub.cli'                = 'gh'
}

$ConfigFiles = @(
    'oh-my-posh/microverse-power.omp.json'
    'powershell/profile.ps1'
    'nushell/terminal-customization.nu'
    'nushell/config-snippet.nu'
    'bat/themes/Microverse.tmTheme'
    'eza/theme.yml'
    'fzf/fzfrc'
    'ripgrep/ripgreprc'
    'windows-terminal/terminal-customization.json'
)

# --- output helpers -------------------------------------------------------------
function Write-Step([string]$Text) { Write-Host "`n==> $Text" -ForegroundColor Blue }
function Write-Ok([string]$Text)   { Write-Host "  [ok] $Text" -ForegroundColor Green }
function Write-Warn([string]$Text) { Write-Host "  [!]  $Text" -ForegroundColor Yellow }
function Test-Command([string]$Name) { [bool](Get-Command $Name -ErrorAction SilentlyContinue) }

# Runs a native command without letting its stderr stop the script (Windows PowerShell 5.1
# turns redirected stderr into errors). Returns the exit code.
function Invoke-Quiet([scriptblock]$Command) {
    $ErrorActionPreference = 'Continue'
    & $Command 2>&1 | Out-Null
    $LASTEXITCODE
}

function Update-SessionPath {
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user = [Environment]::GetEnvironmentVariable('Path', 'User')
    $links = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links'
    $env:Path = (@($machine, $user, $links) | Where-Object { $_ }) -join ';'
}

function Write-Utf8File([string]$Path, [string]$Content) {
    $dir = Split-Path $Path -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [IO.File]::WriteAllText($Path, $Content, (New-Object Text.UTF8Encoding($false)))
}

function Backup-File([string]$Path) {
    if (Test-Path $Path) { Copy-Item $Path "$Path.tc-backup-$(Get-Date -Format yyyyMMddHHmmss)" -Force }
}

# Replaces (or appends) the marked block in a text file.
function Set-MarkedBlock([string]$Path, [string]$Block) {
    $text = if (Test-Path $Path) { [IO.File]::ReadAllText($Path) } else { '' }
    if ($text.Contains($MarkBegin)) {
        Backup-File $Path
        $pattern = '(?s)\r?\n?' + [regex]::Escape($MarkBegin) + '.*?' + [regex]::Escape($MarkEnd)
        $text = [regex]::Replace($text, $pattern, '')
    }
    $text = $text.TrimEnd() + "`r`n`r`n" + $Block.Trim() + "`r`n"
    Write-Utf8File $Path $text.TrimStart()
}

# --- prerequisites ---------------------------------------------------------------
if ($PSVersionTable.PSEdition -eq 'Core' -and -not $IsWindows) {
    throw 'install.ps1 is for Windows. On Linux run install.sh.'
}

# --- 1. tools ------------------------------------------------------------------------
if (-not $SkipTools) {
    Write-Step 'Installing / upgrading tools with winget (always the latest version)'
    if (-not (Test-Command winget)) {
        throw 'winget was not found. Install "App Installer" from the Microsoft Store (https://aka.ms/getwinget) and run this script again.'
    }
    # 0x8A15002B = no newer version available, 0x8A150061 = already installed
    $okCodes = @(0, -1978335189, -1978335135)
    $failed = @()
    foreach ($id in $Packages.Keys) {
        # `winget install` upgrades an already installed package to the latest version.
        Write-Host "  ... $id" -ForegroundColor DarkGray
        $code = Invoke-Quiet { winget install --id $id --exact --source winget --silent `
            --accept-package-agreements --accept-source-agreements --disable-interactivity }
        if ($okCodes -contains $code) {
            Write-Ok $id
        } else {
            Write-Warn "$id failed (winget exit code $code)"
            $failed += $id
        }
    }
    Update-SessionPath
    if ($failed) { Write-Warn "Some packages failed: $($failed -join ', '). Re-run the script or install them manually (see README)." }
}
Update-SessionPath

# --- 2. font ------------------------------------------------------------------------
if (-not $SkipFonts) {
    Write-Step 'Installing JetBrainsMono Nerd Font (latest release)'
    if (Test-Command oh-my-posh) {
        oh-my-posh font install JetBrainsMono
        if ($LASTEXITCODE -eq 0) { Write-Ok 'JetBrainsMono Nerd Font installed' }
        else { Write-Warn 'Font installation failed, see README "Fonts" for the manual steps' }
    } else {
        Write-Warn 'oh-my-posh not found, skipping font installation'
    }
}

if ($SkipConfig) { Write-Step 'Done (configuration skipped)'; return }

# --- 3. configuration files ------------------------------------------------------------
Write-Step "Copying configuration to $TcHome"
foreach ($file in $ConfigFiles) {
    $destination = Join-Path $TcHome $file
    $dir = Split-Path $destination -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $source = if ($PSScriptRoot) { Join-Path $PSScriptRoot "config/$file" } else { $null }
    if ($source -and (Test-Path $source)) {
        Copy-Item $source $destination -Force
    } else {
        Invoke-WebRequest -UseBasicParsing -Uri "$RepoRaw/config/$file" -OutFile $destination
    }
    Unblock-File $destination -ErrorAction SilentlyContinue
}
Write-Ok 'configuration copied'

# --- 4. PowerShell profiles (PowerShell 7 + Windows PowerShell 5.1, all hosts incl. VS Code) ----
Write-Step 'Configuring PowerShell profiles'
$documents = [Environment]::GetFolderPath('MyDocuments')
$profileBlock = @"
$MarkBegin
. "`$HOME\.config\terminal-customization\powershell\profile.ps1"
$MarkEnd
"@
$oldLinePattern = '^\s*[^#].*(oh-my-posh(\.exe)?\s+init|Import-Module\s+(-Name\s+)?(Terminal-Icons|PSReadLine)|Set-PSReadLineOption)'
foreach ($edition in 'PowerShell', 'WindowsPowerShell') {
    $dir = Join-Path $documents $edition
    # Comment out lines from the previous version of this repo (PSReadLine, Terminal-Icons, old oh-my-posh init).
    foreach ($name in 'Microsoft.PowerShell_profile.ps1', 'Microsoft.VSCode_profile.ps1', 'profile.ps1') {
        $path = Join-Path $dir $name
        if (-not (Test-Path $path)) { continue }
        $lines = @(Get-Content $path)
        if (-not ($lines | Where-Object { $_ -match $oldLinePattern })) { continue }
        Backup-File $path
        $lines = $lines | ForEach-Object { if ($_ -match $oldLinePattern) { "# disabled by terminal-customization: $_" } else { $_ } }
        Write-Utf8File $path (($lines -join "`r`n") + "`r`n")
        Write-Warn "commented out old PSReadLine/Terminal-Icons/oh-my-posh lines in $path"
    }
    Set-MarkedBlock (Join-Path $dir 'profile.ps1') $profileBlock
    Write-Ok "$edition profile: $(Join-Path $dir 'profile.ps1')"
}

# Profiles are local scripts; make sure the current user may run them.
try {
    $policy = Get-ExecutionPolicy -Scope CurrentUser
    if ($policy -in 'Undefined', 'Restricted', 'AllSigned' -and (Get-ExecutionPolicy) -in 'Restricted', 'AllSigned') {
        Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
        Write-Ok 'execution policy for the current user set to RemoteSigned'
    }
} catch {
    Write-Warn "Could not set the execution policy: $($_.Exception.Message)"
}

# Remove modules the old setup installed from the PowerShell Gallery (PSReadLine prerelease, Terminal-Icons).
# The PSReadLine copy bundled with PowerShell itself cannot be removed and is simply no longer configured.
if (-not $KeepOldModules) {
    $uninstall = "foreach (`$m in 'PSReadLine','Terminal-Icons') { Get-InstalledModule `$m -AllVersions -ErrorAction SilentlyContinue | Uninstall-Module -Force -ErrorAction SilentlyContinue }"
    foreach ($shell in 'powershell', 'pwsh') {
        if (Test-Command $shell) { Invoke-Quiet { & $shell -NoLogo -NoProfile -NonInteractive -Command $uninstall } | Out-Null }
    }
    Write-Ok 'old PSReadLine / Terminal-Icons gallery modules removed (if they were installed)'
}

# --- 5. bat theme --------------------------------------------------------------------------
if (Test-Command bat) {
    $batThemes = Join-Path (bat --config-dir) 'themes'
    New-Item -ItemType Directory -Path $batThemes -Force | Out-Null
    Copy-Item (Join-Path $TcHome 'bat/themes/Microverse.tmTheme') $batThemes -Force
    bat cache --build | Out-Null
    Write-Ok "bat theme 'Microverse' installed"
}

# --- 6. Nushell ------------------------------------------------------------------------
Write-Step 'Configuring Nushell'
if (Test-Command nu) {
    $nuConfigDir = (nu --no-config-file -c '$nu.default-config-dir' | Out-String).Trim()
    $nuConfig = (nu --no-config-file -c '$nu.config-path' | Out-String).Trim()
    $autoload = Join-Path $nuConfigDir 'autoload'
    New-Item -ItemType Directory -Path $autoload -Force | Out-Null
    Copy-Item (Join-Path $TcHome 'nushell/terminal-customization.nu') $autoload -Force
    Set-MarkedBlock $nuConfig ([IO.File]::ReadAllText((Join-Path $TcHome 'nushell/config-snippet.nu')))
    # Generate the integration scripts once now; config.nu refreshes them on every start.
    if (Test-Command zoxide) { Write-Utf8File (Join-Path $autoload 'zoxide.nu') ((zoxide init nushell) -join "`n") }
    if (Test-Command fzf) { Write-Utf8File (Join-Path $autoload 'fzf.nu') ((fzf --nushell) -join "`n") }
    if (Test-Command oh-my-posh) { oh-my-posh init nu --config (Join-Path $TcHome 'oh-my-posh/microverse-power.omp.json') | Out-Null }
    Write-Ok "Nushell config: $nuConfig"
} else {
    Write-Warn 'nu not found (open a new terminal and re-run the script if it was just installed)'
}

# --- 7. Windows Terminal: profile + colour scheme + default shell --------------------------
Write-Step 'Configuring Windows Terminal'
$fragmentDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\Fragments\TerminalCustomization'
New-Item -ItemType Directory -Path $fragmentDir -Force | Out-Null
Copy-Item (Join-Path $TcHome 'windows-terminal/terminal-customization.json') $fragmentDir -Force
Write-Ok "profile '$WtProfileName' and colour scheme 'Microverse' added"

if (-not $NoDefaultShell) {
    $settingsFiles = @(
        (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'),
        (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\settings.json')
    ) | Where-Object { Test-Path $_ }
    if (-not $settingsFiles) {
        Write-Warn "Windows Terminal settings not found. Start Windows Terminal once and re-run, or pick '$WtProfileName' in Settings > Startup > Default profile."
    }
    foreach ($settings in $settingsFiles) {
        Backup-File $settings
        $json = [IO.File]::ReadAllText($settings)
        $entry = '"defaultProfile": "' + $WtProfileName + '"'
        if ($json -match '"defaultProfile"\s*:\s*"[^"]*"') {
            $json = [regex]::Replace($json, '"defaultProfile"\s*:\s*"[^"]*"', $entry, 1)
        } else {
            $json = ([regex]'\{').Replace($json, "{`r`n    $entry,", 1)
        }
        Write-Utf8File $settings $json
        Write-Ok "default profile set in $settings"
    }
}

# --- done --------------------------------------------------------------------------------
Write-Step 'Done'
Write-Host '  Open a new Windows Terminal tab/window to start Nushell with the new prompt.'
Write-Host "  Other terminals (VS Code, conhost): set the font to 'JetBrainsMono Nerd Font'."
if ((Test-Command gh) -and (Invoke-Quiet { gh auth status }) -ne 0) { Write-Host "  Run 'gh auth login' to sign in to GitHub." }
