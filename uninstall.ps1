<#
.SYNOPSIS
    TerminalCustumization - uninstaller for Windows.

.DESCRIPTION
    Reverses install.ps1:
      - removes the terminal-customization blocks from the PowerShell profiles and Nushell's config.nu
      - removes the Nushell autoload scripts, the bat theme and ~/.config/terminal-customization
      - removes the "Nushell (Microverse)" Windows Terminal profile and restores PowerShell as the
        default profile if Nushell was the default
      - uninstalls the tools with winget (Windows Terminal and PowerShell 7 are kept)
      - removes the per-user JetBrainsMono Nerd Font
    Every edited file is backed up first (*.tc-backup-<date>).

.EXAMPLE
    .\uninstall.ps1

.EXAMPLE
    & ([scriptblock]::Create((irm https://raw.githubusercontent.com/R3start/TerminalCustumization/main/uninstall.ps1))) -Yes -KeepTools
#>
[CmdletBinding()]
param(
    # Keep the tools installed with winget
    [switch]$KeepTools,
    # Keep the JetBrainsMono Nerd Font
    [switch]$KeepFonts,
    # Keep ~/.config/terminal-customization (shell integration is still removed)
    [switch]$KeepConfig,
    # Also delete tool data: zoxide's directory database and the oh-my-posh cache
    [switch]$Purge,
    # Do not ask for confirmation
    [switch]$Yes
)

$ErrorActionPreference = 'Stop'
$TcHome = Join-Path $HOME '.config\terminal-customization'
$MarkBegin = '# >>> terminal-customization >>>'
$MarkEnd = '# <<< terminal-customization <<<'
$WtProfileName = 'Nushell (Microverse)'
$WingetTools = 'JanDeDobbeleer.OhMyPosh', 'Nushell.Nushell', 'eza-community.eza', 'sharkdp.bat',
    'BurntSushi.ripgrep.MSVC', 'junegunn.fzf', 'ajeetdsouza.zoxide', 'muesli.duf', 'bootandy.dust', 'GitHub.cli'
# Well-known Windows Terminal profile GUIDs
$Pwsh7Guid = '{574e775e-4f2a-5b96-ac1e-a2962a402336}'
$WinPsGuid = '{61c54bbd-c2c6-5271-96e7-009a87ff44bf}'

function Write-Step([string]$Text) { Write-Host "`n==> $Text" -ForegroundColor Blue }
function Write-Ok([string]$Text)   { Write-Host "  [ok] $Text" -ForegroundColor Green }
function Write-Warn([string]$Text) { Write-Host "  [!]  $Text" -ForegroundColor Yellow }
function Test-Command([string]$Name) { [bool](Get-Command $Name -ErrorAction SilentlyContinue) }

function Invoke-Quiet([scriptblock]$Command) {
    $ErrorActionPreference = 'Continue'
    & $Command 2>&1 | Out-Null
    $LASTEXITCODE
}

function Get-NativeOutput([scriptblock]$Command) {
    $ErrorActionPreference = 'Continue'
    ((& $Command 2>$null) | Out-String).Trim()
}

function Backup-File([string]$Path) {
    if ((Test-Path $Path) -and (Get-Item $Path).Length -gt 0) {
        Copy-Item $Path "$Path.tc-backup-$(Get-Date -Format yyyyMMddHHmmss)" -Force
    }
}

function Write-Utf8File([string]$Path, [string]$Content) {
    [IO.File]::WriteAllText($Path, $Content, (New-Object Text.UTF8Encoding($false)))
}

# Removes the marked block from a text file. Returns $true when something was removed.
function Remove-MarkedBlock([string]$Path) {
    if (-not (Test-Path $Path)) { return $false }
    $text = [IO.File]::ReadAllText($Path)
    if (-not $text.Contains($MarkBegin)) { return $false }
    $pattern = '(?s)(\r?\n)*' + [regex]::Escape($MarkBegin) + '.*?' + [regex]::Escape($MarkEnd) + '\r?\n?'
    Backup-File $Path
    $text = [regex]::Replace($text, $pattern, "`r`n").Trim()
    Write-Utf8File $Path ($(if ($text) { $text + "`r`n" } else { '' }))
    return $true
}

function Remove-IfExists([string]$Path) {
    if (Test-Path $Path) { Remove-Item $Path -Recurse -Force; Write-Ok "removed $Path" }
}

# --- plan ------------------------------------------------------------------------------
Write-Host 'This will remove the TerminalCustumization setup:'
Write-Host '  - the terminal-customization blocks in the PowerShell profiles and Nushell config.nu'
Write-Host "  - the Nushell autoload scripts, the bat 'Microverse' theme and the '$WtProfileName' Windows Terminal profile"
if (-not $KeepConfig) { Write-Host "  - $TcHome" }
if (-not $KeepTools)  { Write-Host "  - winget packages: $($WingetTools -join ', ')" }
if (-not $KeepFonts)  { Write-Host '  - the per-user JetBrainsMono Nerd Font' }
if ($Purge)           { Write-Host "  - zoxide's database and the oh-my-posh cache" }
if (-not $Yes) {
    $answer = Read-Host 'Continue? [y/N]'
    if ($answer -notmatch '^[yY]') { Write-Host 'Aborted.'; return }
}

# --- shells ------------------------------------------------------------------------------
Write-Step 'Removing shell integration'
$documents = [Environment]::GetFolderPath('MyDocuments')
foreach ($edition in 'PowerShell', 'WindowsPowerShell') {
    $path = Join-Path $documents "$edition\profile.ps1"
    if (Remove-MarkedBlock $path) { Write-Ok $path }
}
Write-Host '  Lines the installer commented out ("# disabled by terminal-customization:") are left as they are.' -ForegroundColor DarkGray

# Nushell: ask nu for its folders while it is still installed, otherwise use the defaults.
$nuConfigDir = Join-Path $env:APPDATA 'nushell'
$nuConfig = Join-Path $nuConfigDir 'config.nu'
$nuDataDir = Join-Path $env:APPDATA 'nushell'
if (Test-Command nu) {
    $nuConfigDir = Get-NativeOutput { nu --no-config-file -c '$nu.default-config-dir' }
    $nuConfig = Get-NativeOutput { nu --no-config-file -c '$nu.config-path' }
    $nuDataDir = Get-NativeOutput { nu --no-config-file -c '$nu.data-dir' }
}
if (Remove-MarkedBlock $nuConfig) { Write-Ok $nuConfig }
foreach ($file in 'terminal-customization.nu', 'zoxide.nu', 'fzf.nu') {
    Remove-IfExists (Join-Path $nuConfigDir "autoload\$file")
}
Remove-IfExists (Join-Path $nuDataDir 'vendor\autoload\oh-my-posh.nu')

if (Test-Command bat) {
    $theme = Join-Path (Get-NativeOutput { bat --config-dir }) 'themes\Microverse.tmTheme'
    if (Test-Path $theme) {
        Remove-Item $theme -Force
        Invoke-Quiet { bat cache --build } | Out-Null
        Write-Ok 'bat theme removed'
    }
}

# --- Windows Terminal ------------------------------------------------------------------------
Write-Step 'Restoring Windows Terminal'
Remove-IfExists (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\Fragments\TerminalCustomization')
$fallback = if (Test-Command pwsh) { $Pwsh7Guid } else { $WinPsGuid }
$settingsFiles = @(
    (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'),
    (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json'),
    (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\settings.json')
) | Where-Object { Test-Path $_ }
foreach ($settings in $settingsFiles) {
    $json = [IO.File]::ReadAllText($settings)
    $ours = '"defaultProfile"\s*:\s*"' + [regex]::Escape($WtProfileName) + '"'
    if ($json -match $ours) {
        Backup-File $settings
        Write-Utf8File $settings ([regex]::Replace($json, $ours, '"defaultProfile": "' + $fallback + '"'))
        Write-Ok "default profile set back to PowerShell in $settings"
    }
}

# --- fonts (before the tools, so nothing is holding them) -------------------------------------
if (-not $KeepFonts) {
    Write-Step 'Removing JetBrainsMono Nerd Font (per-user)'
    $fontDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'
    $fontKey = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts'
    $removed = 0
    if (Test-Path $fontKey) {
        $values = Get-ItemProperty $fontKey
        foreach ($property in $values.PSObject.Properties) {
            if ($property.Value -is [string] -and $property.Value -match 'JetBrainsMono.*NerdFont') {
                Remove-ItemProperty -Path $fontKey -Name $property.Name -ErrorAction SilentlyContinue
            }
        }
    }
    foreach ($font in Get-ChildItem $fontDir -Filter 'JetBrainsMono*NerdFont*' -ErrorAction SilentlyContinue) {
        try { Remove-Item $font.FullName -Force; $removed++ }
        catch { Write-Warn "$($font.Name) is in use; it will disappear after closing all terminals and deleting it, or after a reboot" }
    }
    Write-Ok "$removed font file(s) removed - switch other terminals (VS Code, ...) to another font"
    Write-Host '  Fonts installed for all users (C:\Windows\Fonts) are left alone.' -ForegroundColor DarkGray
}

# --- tools ------------------------------------------------------------------------------------
if (-not $KeepTools) {
    Write-Step 'Uninstalling tools with winget'
    if (Test-Command winget) {
        foreach ($id in $WingetTools) {
            $code = Invoke-Quiet { winget uninstall --id $id --exact --silent --disable-interactivity --accept-source-agreements }
            if ($code -eq 0) { Write-Ok $id }
            elseif ($code -eq -1978335212) { Write-Ok "$id (not installed)" }
            else { Write-Warn "$id could not be uninstalled (winget exit code $code)" }
        }
    } else {
        Write-Warn 'winget not found; uninstall the tools from Settings > Apps'
    }
}

# --- files ------------------------------------------------------------------------------------
if (-not $KeepConfig) { Remove-IfExists $TcHome }
if ($Purge) {
    Remove-IfExists (Join-Path $env:LOCALAPPDATA 'zoxide')
    Remove-IfExists (Join-Path $env:LOCALAPPDATA 'oh-my-posh')
}

Write-Step 'Done'
Write-Host '  Open a new terminal window. Backups of edited files are next to them as *.tc-backup-<date>.'
Write-Host '  PSReadLine is part of PowerShell and keeps working with its default settings.'
