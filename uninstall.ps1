<#
.SYNOPSIS
    TerminalCustumization - uninstaller for Windows.

.DESCRIPTION
    Reverses install.ps1:
      - removes the terminal-customization blocks from the PowerShell profiles and Nushell's config.nu
      - removes the Nushell autoload scripts, the bat theme and ~/.config/terminal-customization
      - removes the "Nushell (Microverse)" Windows Terminal profile and restores PowerShell as the
        default profile if Nushell was the default
      - uninstalls the winget packages that install.ps1 installed (recorded in
        %LOCALAPPDATA%\terminal-customization\manifest.txt); tools you already had are kept
      - removes the JetBrainsMono Nerd Font files that install.ps1 added (a font you
        installed yourself is kept)
    Every edited file is backed up first (*.tc-backup-<date>).

.EXAMPLE
    .\uninstall.ps1

.EXAMPLE
    & ([scriptblock]::Create((irm https://raw.githubusercontent.com/R3start/TerminalCustumization/main/uninstall.ps1))) -Yes -KeepTools
#>
[CmdletBinding()]
param(
    # Keep the tools install.ps1 installed with winget
    [switch]$KeepTools,
    # Also uninstall the tools this setup uses when they are not in the install record
    # (installs made before the record existed). Windows Terminal and PowerShell 7 are always kept.
    [switch]$AllTools,
    # Keep the JetBrainsMono Nerd Font files install.ps1 added
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
$WtProfileGuid = '{7c3e2a5b-4d1f-4b8e-9a6c-2f5d8e1b3a74}'
$StateDir = Join-Path $env:LOCALAPPDATA 'terminal-customization'
$Manifest = Join-Path $StateDir 'manifest.txt'
$WingetTools = 'JanDeDobbeleer.OhMyPosh', 'Nushell.Nushell', 'eza-community.eza', 'sharkdp.bat',
    'BurntSushi.ripgrep.MSVC', 'junegunn.fzf', 'ajeetdsouza.zoxide', 'muesli.duf', 'bootandy.dust', 'GitHub.cli',
    'chrisant996.Clink'
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

function Get-ManifestEntries([string]$Kind) {
    if (-not (Test-Path $Manifest)) { return @() }
    @(Get-Content $Manifest | Where-Object { $_ -like "$Kind`t*" } | ForEach-Object { $_.Substring($Kind.Length + 1) })
}

function Remove-ManifestEntries([string]$Kind) {
    if (-not (Test-Path $Manifest)) { return }
    $keep = @(Get-Content $Manifest | Where-Object { $_ -and $_ -notlike "$Kind`t*" })
    if ($keep) { Set-Content -Path $Manifest -Value $keep -Encoding UTF8 } else { Remove-Item $Manifest -Force }
}

function Remove-IfExists([string]$Path) {
    if (Test-Path $Path) { Remove-Item $Path -Recurse -Force; Write-Ok "removed $Path" }
}

# --- plan ------------------------------------------------------------------------------
Write-Host 'This will remove the TerminalCustumization setup:'
Write-Host '  - the terminal-customization blocks in the PowerShell profiles and Nushell config.nu'
Write-Host "  - the Nushell autoload scripts, the bat 'Microverse' theme and the '$WtProfileName' Windows Terminal profile"
if (-not $KeepConfig) { Write-Host "  - $TcHome" }
$recordedTools = @(Get-ManifestEntries 'winget')
$toolsToRemove = if ($AllTools) { @($WingetTools) } else { $recordedTools }
$recordedFonts = @(Get-ManifestEntries 'font')
if (-not $KeepTools) {
    $list = if ($toolsToRemove) { $toolsToRemove -join ', ' } else { 'none recorded' }
    Write-Host "  - winget packages install.ps1 installed: $list"
}
if (-not $KeepFonts)  { Write-Host "  - JetBrainsMono Nerd Font files install.ps1 added: $($recordedFonts.Count)" }
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

$batDir = if (Test-Command bat) { Get-NativeOutput { bat --config-dir } } else { '' }
# Only a real bat prints an absolute config directory.
if ($batDir -and [IO.Path]::IsPathRooted($batDir)) {
    $theme = Join-Path $batDir 'themes\Microverse.tmTheme'
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
    # By GUID (current installs) or by name (installs made by older versions of install.ps1)
    $ours = '"defaultProfile"\s*:\s*"(' + [regex]::Escape($WtProfileGuid) + '|' + [regex]::Escape($WtProfileName) + ')"'
    if ($json -match $ours) {
        Backup-File $settings
        Write-Utf8File $settings ([regex]::Replace($json, $ours, '"defaultProfile": "' + $fallback + '"'))
        Write-Ok "default profile set back to PowerShell in $settings"
    }
}

# --- Windows Terminal font default and cmd.exe (Clink) -----------------------------------------
foreach ($settings in Get-ManifestEntries 'wt-defaults-font') {
    if (-not (Test-Path $settings)) { continue }
    $json = [IO.File]::ReadAllText($settings)
    $ours = '"defaults"\s*:\s*\{\s*"font"\s*:\s*\{\s*"face"\s*:\s*"JetBrainsMono Nerd Font"\s*\}\s*\}'
    if ($json -match $ours) {
        Backup-File $settings
        Write-Utf8File $settings ([regex]::Replace($json, $ours, '"defaults": {}', 1))
        Write-Ok "Windows Terminal profile defaults restored in $settings"
    }
}
Remove-ManifestEntries 'wt-defaults-font'

$clinkScripts = @(Get-ManifestEntries 'clink-scripts')
$clinkAutorun = @(Get-ManifestEntries 'clink-autorun')
if ($clinkScripts -or $clinkAutorun) {
    $clink = Get-Command clink -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1 | ForEach-Object { $_.Source }
    if (-not $clink) {
        foreach ($dir in @(${env:ProgramFiles(x86)}, $env:ProgramFiles, (Join-Path $env:LOCALAPPDATA 'Programs'))) {
            if ($dir -and (Test-Path (Join-Path $dir 'clink\clink.bat'))) { $clink = Join-Path $dir 'clink\clink.bat'; break }
        }
    }
    if ($clink) {
        foreach ($dir in $clinkScripts) { Invoke-Quiet { & $clink uninstallscripts $dir } | Out-Null }
        if ($clinkAutorun) { Invoke-Quiet { & $clink autorun uninstall } | Out-Null; Write-Ok 'Clink no longer starts with cmd.exe' }
        Write-Ok 'cmd.exe configuration (Clink script) removed'
    }
    Remove-ManifestEntries 'clink-scripts'
    Remove-ManifestEntries 'clink-autorun'
}

# --- fonts (before the tools, so nothing is holding them) -------------------------------------
if (-not $KeepFonts) {
    Write-Step 'Removing JetBrainsMono Nerd Font files installed by install.ps1'
    $fontKey = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts'
    foreach ($name in Get-ManifestEntries 'fontreg') {
        Remove-ItemProperty -Path $fontKey -Name $name -ErrorAction SilentlyContinue
    }
    $removed = 0
    $inUse = $false
    foreach ($file in $recordedFonts) {
        if (-not (Test-Path $file)) { continue }
        try { Remove-Item $file -Force; $removed++ }
        catch { $inUse = $true; Write-Warn "$(Split-Path $file -Leaf) is in use; close all terminals and delete it, or it goes after a reboot" }
    }
    Remove-ManifestEntries 'fontreg'
    if (-not $inUse) { Remove-ManifestEntries 'font' }
    if ($recordedFonts) { Write-Ok "$removed font file(s) removed - switch other terminals (VS Code, ...) to another font" }
    else { Write-Ok 'no font files recorded by install.ps1 (a font you installed yourself is left alone)' }
}

# --- tools ------------------------------------------------------------------------------------
if (-not $KeepTools) {
    Write-Step 'Uninstalling the tools install.ps1 installed'
    if (-not $toolsToRemove) {
        Write-Ok 'no winget packages recorded by install.ps1 (tools you already had are left alone; -AllTools removes them anyway)'
    } elseif (Test-Command winget) {
        foreach ($id in $toolsToRemove) {
            $code = Invoke-Quiet { winget uninstall --id $id --exact --silent --disable-interactivity --accept-source-agreements }
            if ($code -eq 0) { Write-Ok $id }
            elseif ($code -eq -1978335212) { Write-Ok "$id (not installed)" }
            else { Write-Warn "$id could not be uninstalled (winget exit code $code)" }
        }
        Remove-ManifestEntries 'winget'
    } else {
        Write-Warn 'winget not found; uninstall the tools from Settings > Apps'
    }
}

# --- files ------------------------------------------------------------------------------------
if (-not $KeepConfig) { Remove-IfExists $TcHome }
# Forget the install record once nothing in it is left.
if ((Test-Path $StateDir) -and -not (Test-Path $Manifest)) { Remove-Item $StateDir -Recurse -Force -ErrorAction SilentlyContinue }
if ($Purge) {
    Remove-IfExists (Join-Path $env:LOCALAPPDATA 'zoxide')
    Remove-IfExists (Join-Path $env:LOCALAPPDATA 'oh-my-posh')
}

Write-Step 'Done'
Write-Host '  Open a new terminal window. Backups of edited files are next to them as *.tc-backup-<date>.'
Write-Host '  PSReadLine is part of PowerShell and keeps working with its default settings.'
