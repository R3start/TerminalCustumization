<#
.SYNOPSIS
    TerminalCustumization - one-click installer for Windows.

.DESCRIPTION
    Installs what is missing (and upgrades what winget manages) of:
      Windows Terminal, PowerShell 7, Oh My Posh, Nushell, eza, bat, ripgrep, fzf,
      zoxide, duf, dust and the GitHub CLI.
    Then installs the JetBrainsMono Nerd Font Mono if it is missing, copies the configuration to
    ~/.config/terminal-customization, wires up PowerShell 7, Windows PowerShell 5.1
    and Nushell, adds a "Nushell (Microverse)" Windows Terminal profile and makes it
    the default on a first install. Re-running the script only adds what is missing.
    What it installs is recorded in %LOCALAPPDATA%\terminal-customization\manifest.txt,
    so uninstall.ps1 removes only that.

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
    # Do not install the JetBrainsMono Nerd Font Mono
    [switch]$SkipFonts,
    # Reinstall the font even when it is already installed (upgrade.ps1 does this)
    [switch]$UpdateFonts,
    # Do not touch profiles, Nushell or Windows Terminal settings
    [switch]$SkipConfig,
    # Keep PowerShell / your Windows Terminal default: don't start Nushell automatically
    [switch]$NoDefaultShell,
    # Start Nushell automatically again (re-runs keep your current choice otherwise)
    [switch]$DefaultShell,
    # Uninstall the PSReadLine/Terminal-Icons copies from the PowerShell Gallery that the previous
    # version of this setup told you to install (they are only reported otherwise)
    [switch]$RemoveOldModules,
    # Never change the PowerShell execution policy (only report when it blocks the profile)
    [switch]$KeepExecutionPolicy
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$RepoRaw = if ($env:TC_REPO_RAW) { $env:TC_REPO_RAW } else { 'https://raw.githubusercontent.com/R3start/TerminalCustumization/main' }
$TcHome = Join-Path $HOME '.config\terminal-customization'
$MarkBegin = '# >>> terminal-customization >>>'
$MarkEnd = '# <<< terminal-customization <<<'
$WtProfileName = 'Nushell (Microverse)'
# Fixed GUID of the Windows Terminal profile (also in config/windows-terminal/terminal-customization.json)
$WtProfileGuid = '{7c3e2a5b-4d1f-4b8e-9a6c-2f5d8e1b3a74}'
$StateDir = Join-Path $env:LOCALAPPDATA 'terminal-customization'
$Manifest = Join-Path $StateDir 'manifest.txt'
$UserFontDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'
$UserFontKey = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts'

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
    'chrisant996.Clink'         = 'clink'
}

$ConfigFiles = @(
    'oh-my-posh/microverse-power.omp.json'
    'powershell/profile.ps1'
    'powershell/disable-duplicates.ps1'
    'nushell/terminal-customization.nu'
    'nushell/config-snippet.nu'
    'bat/themes/Microverse.tmTheme'
    'eza/theme.yml'
    'fzf/fzfrc'
    'ripgrep/ripgreprc'
    'windows-terminal/terminal-customization.json'
    'clink/terminal-customization.lua'
    'clink/z.cmd'
    'clink/zi.cmd'
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

# WriteAllText writes into the existing file, so a symlinked profile keeps its link and the file
# keeps its permissions (ACL).
function Write-Utf8File([string]$Path, [string]$Content) {
    $dir = Split-Path $Path -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [IO.File]::WriteAllText($Path, $Content, (New-Object Text.UTF8Encoding($false)))
}

function Backup-File([string]$Path) {
    if ((Test-Path $Path) -and (Get-Item $Path).Length -gt 0) {
        Copy-Item $Path "$Path.tc-backup-$(Get-Date -Format yyyyMMddHHmmss)" -Force
    }
}

# Writes the file only when the content changes; keeps a backup of the previous version.
# Returns $true when the file was changed.
function Update-FileIfChanged([string]$Path, [string]$Content) {
    if ((Test-Path $Path) -and [IO.File]::ReadAllText($Path) -ceq $Content) { return $false }
    Backup-File $Path
    Write-Utf8File $Path $Content
    return $true
}

# --- install manifest: what this script installed (read by uninstall.ps1) ---------------
# Lines: <kind><TAB><value>   kinds: winget (package id), font (file), fontreg (HKCU value name)
function Add-ManifestEntry([string]$Kind, [string]$Value) {
    New-Item -ItemType Directory -Path $StateDir -Force | Out-Null
    $line = "$Kind`t$Value"
    $existing = if (Test-Path $Manifest) { @(Get-Content $Manifest) } else { @() }
    if ($existing -notcontains $line) { Add-Content -Path $Manifest -Value $line -Encoding UTF8 }
}

function Get-ManifestEntries([string]$Kind) {
    if (-not (Test-Path $Manifest)) { return @() }
    @(Get-Content $Manifest | Where-Object { $_ -like "$Kind`t*" } | ForEach-Object { $_.Substring($Kind.Length + 1) })
}

# Per-user JetBrainsMono Nerd Font Mono files and their HKCU registry values.
function Get-FontSnapshot {
    $files = @(Get-ChildItem $UserFontDir -Filter 'JetBrainsMono*NerdFont*' -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
    $values = @()
    if (Test-Path $UserFontKey) {
        $values = @((Get-ItemProperty $UserFontKey).PSObject.Properties |
            Where-Object { $_.Value -is [string] -and $_.Value -match 'JetBrainsMono.*NerdFont' } | ForEach-Object { $_.Name })
    }
    @{ Files = $files; Values = $values }
}

# Disables statements outside the marked block of Nushell's config.nu that would load a tool a
# second time. They stay as comments and the file is backed up. A matching line whose brackets
# don't balance (part of a longer statement) is left alone and reported instead.
function Disable-DuplicateNuLines([string]$Path, [string]$Pattern) {
    if (-not (Test-Path $Path)) { return }
    $text = [IO.File]::ReadAllText($Path)
    $newline = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
    $inBlock = $false
    $count = 0
    $skipped = @()
    $number = 0
    $lines = foreach ($line in ($text -split '\r?\n')) {
        $number++
        if ($line -eq $MarkBegin) { $inBlock = $true }
        $result = $line
        if (-not $inBlock -and $line -match $Pattern -and $line -notmatch '^\s*#') {
            $unquoted = [regex]::Replace($line, '"[^"]*"|''[^'']*''', '')
            if (([regex]::Matches($unquoted, '[({\[]')).Count -eq ([regex]::Matches($unquoted, '[)}\]]')).Count) {
                $count++
                $result = "# disabled by terminal-customization: $line"
            } else {
                $skipped += $number
            }
        }
        if ($line -eq $MarkEnd) { $inBlock = $false }
        $result
    }
    if ($count -gt 0) {
        [void](Update-FileIfChanged $Path ($lines -join $newline))
        Write-Warn "${Path}: disabled $count line(s) that would load a tool twice (kept as comments, backup saved)"
    }
    if ($skipped) { Write-Warn "${Path}: line(s) $($skipped -join ', ') also load a tool, but are part of a longer statement - remove them by hand" }
}

# Runs config/powershell/disable-duplicates.ps1 (PowerShell parser based) on a profile. It is run
# as a script block, so it works whatever the execution policy is.
function Disable-DuplicateProfileStatements([string]$Path) {
    if (-not (Test-Path $Path)) { return }
    $helper = [scriptblock]::Create([IO.File]::ReadAllText((Join-Path $TcHome 'powershell\disable-duplicates.ps1')))
    foreach ($message in (& $helper -Path $Path)) {
        if ($message -like 'disabled *') { Write-Warn "${Path}: $message statement(s) that would load a tool twice (kept as comments, backup saved)" }
        else { Write-Warn "${Path}: $message" }
    }
}

function Test-NerdFontInstalled {
    $dirs = @((Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'), (Join-Path $env:WINDIR 'Fonts'))
    foreach ($dir in $dirs) {
        if (Get-ChildItem $dir -Filter 'JetBrainsMono*NerdFont*' -ErrorAction SilentlyContinue | Select-Object -First 1) { return $true }
    }
    return $false
}

# The profile files each PowerShell edition really loads, asked from the shell itself (so a moved or
# OneDrive-redirected Documents folder is handled). Falls back to the usual Documents paths.
function Get-PowerShellProfiles {
    $documents = [Environment]::GetFolderPath('MyDocuments')
    if (-not $documents) { $documents = Join-Path $HOME 'Documents' }
    foreach ($edition in @(@{ Shell = 'pwsh'; Folder = 'PowerShell' }, @{ Shell = 'powershell'; Folder = 'WindowsPowerShell' })) {
        $paths = @()
        if (Get-Command $edition.Shell -ErrorAction SilentlyContinue) {
            $ErrorActionPreference = 'Continue'
            $paths = @(& $edition.Shell -NoLogo -NoProfile -NonInteractive -Command '$PROFILE.CurrentUserCurrentHost; $PROFILE.CurrentUserAllHosts' 2>$null |
                ForEach-Object { "$_".Trim() } | Where-Object { $_ -match '\.ps1$' })
            $ErrorActionPreference = 'Stop'
        }
        if ($paths.Count -ne 2) {
            $dir = Join-Path $documents $edition.Folder
            $paths = @((Join-Path $dir 'Microsoft.PowerShell_profile.ps1'), (Join-Path $dir 'profile.ps1'))
        }
        [pscustomobject]@{ Edition = $edition.Folder; CurrentHost = $paths[0]; AllHosts = $paths[1] }
    }
}

# Replaces (or appends) the marked block in a text file.
function Set-MarkedBlock([string]$Path, [string]$Block) {
    $text = if (Test-Path $Path) { [IO.File]::ReadAllText($Path) } else { '' }
    $pattern = '(?s)\r?\n?' + [regex]::Escape($MarkBegin) + '.*?' + [regex]::Escape($MarkEnd)
    $text = [regex]::Replace($text, $pattern, '').TrimEnd()
    if ($text) { $text += "`r`n`r`n" }
    [void](Update-FileIfChanged $Path ($text + $Block.Trim() + "`r`n"))
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
    $upToDateCodes = @(-1978335189, -1978335135)
    $failed = @()
    foreach ($id in $Packages.Keys) {
        $command = $Packages[$id]
        Write-Host "  ... $id" -ForegroundColor DarkGray
        $managed = (Invoke-Quiet { winget list --id $id --exact --accept-source-agreements --disable-interactivity }) -eq 0
        $existing = Get-Command $command -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($managed) {
            # Installed with winget (or the Store): only upgrade, never install a second copy.
            $code = Invoke-Quiet { winget upgrade --id $id --exact --silent `
                --accept-package-agreements --accept-source-agreements --disable-interactivity }
            if ($code -eq 0) { Write-Ok "$id upgraded to the latest version" }
            elseif ($upToDateCodes -contains $code) { Write-Ok "$id already latest" }
            else { Write-Warn "$id upgrade failed (winget exit code $code)"; $failed += $id }
        } elseif ($existing) {
            # Installed some other way (scoop, choco, manual): leave it alone instead of adding a duplicate.
            Write-Warn "$id skipped: '$command' is already installed at $($existing.Source) (not by winget); update it with the tool you installed it with"
        } else {
            $code = Invoke-Quiet { winget install --id $id --exact --source winget --silent `
                --accept-package-agreements --accept-source-agreements --disable-interactivity }
            # Recorded, so uninstall.ps1 removes only packages this script installed.
            if ($code -eq 0) { Add-ManifestEntry 'winget' $id; Write-Ok "$id installed" }
            elseif ($upToDateCodes -contains $code) { Write-Ok "$id installed" }
            else { Write-Warn "$id failed (winget exit code $code)"; $failed += $id }
        }
    }
    Update-SessionPath
    if ($failed) { Write-Warn "Some packages failed: $($failed -join ', '). Re-run the script or install them manually (see README)." }
}
Update-SessionPath

# --- 2. font ------------------------------------------------------------------------
if (-not $SkipFonts) {
    Write-Step 'Installing JetBrainsMono Nerd Font Mono (latest release)'
    $ourFonts = @(Get-ManifestEntries 'font')
    if (-not $UpdateFonts -and (Test-NerdFontInstalled)) {
        Write-Ok 'JetBrainsMono Nerd Font Mono already installed (upgrade.ps1 or -UpdateFonts refreshes it)'
    } elseif ((Test-NerdFontInstalled) -and $ourFonts.Count -eq 0) {
        Write-Ok 'JetBrainsMono Nerd Font Mono is installed, but not by this script - left as it is'
    } elseif (Test-Command oh-my-posh) {
        $before = Get-FontSnapshot
        oh-my-posh font install JetBrainsMono
        if ($LASTEXITCODE -eq 0) {
            # Record only what this run added; a font you installed yourself is never recorded.
            $after = Get-FontSnapshot
            $after.Files | Where-Object { $before.Files -notcontains $_ } | ForEach-Object { Add-ManifestEntry 'font' $_ }
            $after.Values | Where-Object { $before.Values -notcontains $_ } | ForEach-Object { Add-ManifestEntry 'fontreg' $_ }
            Write-Ok 'JetBrainsMono Nerd Font Mono installed'
        } else {
            Write-Warn 'Font installation failed, see README "Fonts" for the manual steps'
        }
    } else {
        Write-Warn 'oh-my-posh not found, skipping font installation'
    }
}

if ($SkipConfig) { Write-Step 'Done (configuration skipped)'; return }

# --- 3. configuration files ------------------------------------------------------------
Write-Step "Copying configuration to $TcHome"
$updated = 0
foreach ($file in $ConfigFiles) {
    $destination = Join-Path $TcHome $file
    $source = if ($PSScriptRoot) { Join-Path $PSScriptRoot "config/$file" } else { $null }
    $content = if ($source -and (Test-Path $source)) {
        [IO.File]::ReadAllText($source)
    } else {
        (Invoke-WebRequest -UseBasicParsing -Uri "$RepoRaw/config/$file").Content
    }
    $existed = Test-Path $destination
    if ((Update-FileIfChanged $destination $content) -and $existed) { $updated++ }
    Unblock-File $destination -ErrorAction SilentlyContinue
}
if ($updated) { Write-Ok "configuration updated ($updated changed file(s); previous versions kept as *.tc-backup-*)" }
else { Write-Ok 'configuration is up to date' }

# --- 4. PowerShell profiles (PowerShell 7 + Windows PowerShell 5.1) ------------------------------
# The block goes into $PROFILE (Microsoft.PowerShell_profile.ps1, what the consoles load, appended last
# so it wins over anything earlier in the file) and into profile.ps1 (all hosts, e.g. VS Code).
# The profile only loads once per session, so having it in both costs nothing.
Write-Step 'Configuring PowerShell profiles'
$profileBlock = @"
$MarkBegin
. "`$HOME\.config\terminal-customization\powershell\profile.ps1"
$MarkEnd
"@
# Statements from the previous version of this repo (PSReadLine, Terminal-Icons, oh-my-posh), other
# zoxide init lines and hand-added copies of the line below would load things twice.
foreach ($profiles in Get-PowerShellProfiles) {
    $dir = Split-Path $profiles.CurrentHost -Parent
    foreach ($file in @($profiles.CurrentHost, $profiles.AllHosts, (Join-Path $dir 'Microsoft.VSCode_profile.ps1')) | Select-Object -Unique) {
        Disable-DuplicateProfileStatements $file
    }
    Set-MarkedBlock $profiles.AllHosts $profileBlock
    Set-MarkedBlock $profiles.CurrentHost $profileBlock
    Write-Ok "$($profiles.Edition): $($profiles.CurrentHost) and $(Split-Path $profiles.AllHosts -Leaf)"
}

# Profiles are local scripts. The only policy this script changes is the untouched Windows client
# default (Restricted, nothing set in any scope) for Windows PowerShell 5.1, and only to
# RemoteSigned for the current user. A policy that you or an administrator set (AllSigned,
# Restricted, group policy, ...) is never changed - you only get told that it blocks the profile.
$policyCheck = @'
$set = Get-ExecutionPolicy -List | Where-Object { $_.Scope -ne 'Process' -and $_.ExecutionPolicy -ne 'Undefined' } | Select-Object -First 1
if ($set) { "$($set.Scope)=$($set.ExecutionPolicy)" } else { 'default' }
'@
$isClientWindows = try { (Get-CimInstance Win32_OperatingSystem).ProductType -eq 1 } catch { $true }
# The 32-bit Windows PowerShell (used by Visual Studio's "Developer PowerShell" shortcut) has its own
# machine-wide policy, so it is checked separately.
$powershell32 = Join-Path $env:WINDIR 'SysWOW64\WindowsPowerShell\v1.0\powershell.exe'
$policyShells = @('powershell', 'pwsh')
if ([Environment]::Is64BitOperatingSystem -and (Test-Path $powershell32)) { $policyShells += $powershell32 }
foreach ($shell in $policyShells) {
    if (-not (Test-Command $shell)) { continue }
    $ErrorActionPreference = 'Continue'
    $state = ((& $shell -NoLogo -NoProfile -NonInteractive -Command $policyCheck 2>$null) | Out-String).Trim()
    $ErrorActionPreference = 'Stop'
    $isWindowsPowerShell = $shell -ne 'pwsh'
    $effective = if ($state -eq 'default') {
        if ($isWindowsPowerShell -and $isClientWindows) { 'Restricted' } else { 'RemoteSigned' }
    } else { ($state -split '=')[-1] }
    if ($shell -eq $powershell32) { $shell = 'powershell (32-bit)' }
    if ($effective -notin 'Restricted', 'AllSigned') { continue }
    if ($state -eq 'default' -and -not $KeepExecutionPolicy) {
        # The CurrentUser scope is shared by the 32-bit and 64-bit Windows PowerShell.
        Invoke-Quiet { & powershell -NoLogo -NoProfile -NonInteractive -Command 'Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force' } | Out-Null
        Write-Ok "${shell}: execution policy for the current user set to RemoteSigned (was the Windows default, Restricted)"
    } else {
        $where = if ($state -eq 'default') { 'Windows default' } else { $state }
        Write-Warn "${shell}: execution policy is $effective ($where), so the profile will not load. If that is OK for you: Set-ExecutionPolicy RemoteSigned -Scope CurrentUser (or sign the profile scripts)."
    }
}

# PSReadLine prerelease / Terminal-Icons from the PowerShell Gallery (installed for the previous
# version of this setup) are no longer used. They are only removed when you ask (-RemoveOldModules).
$moduleCheck = "Get-InstalledModule PSReadLine, Terminal-Icons -ErrorAction SilentlyContinue | ForEach-Object { `$_.Name + ' ' + `$_.Version }"
$moduleRemove = "foreach (`$m in 'PSReadLine','Terminal-Icons') { Get-InstalledModule `$m -AllVersions -ErrorAction SilentlyContinue | Uninstall-Module -Force -ErrorAction SilentlyContinue }"
foreach ($shell in 'powershell', 'pwsh') {
    if (-not (Test-Command $shell)) { continue }
    $ErrorActionPreference = 'Continue'
    $found = @(& $shell -NoLogo -NoProfile -NonInteractive -Command $moduleCheck 2>$null)
    $ErrorActionPreference = 'Stop'
    if (-not $found) { continue }
    if ($RemoveOldModules) {
        Invoke-Quiet { & $shell -NoLogo -NoProfile -NonInteractive -Command $moduleRemove } | Out-Null
        Write-Ok "${shell}: removed $($found -join ', ') from the PowerShell Gallery installs (-RemoveOldModules)"
    } else {
        Write-Warn "${shell}: $($found -join ', ') from the PowerShell Gallery are no longer used by this setup. Remove them with -RemoveOldModules or: Uninstall-Module PSReadLine, Terminal-Icons -AllVersions"
    }
}

# Nushell as the default shell: the PowerShell profile hands a normally opened PowerShell window
# over to Nushell unless ~/.config/terminal-customization/no-nu exists. Only changed when asked.
$noNuFile = Join-Path $TcHome 'no-nu'
if ($NoDefaultShell) { New-Item -ItemType File -Path $noNuFile -Force | Out-Null }
if ($DefaultShell) { Remove-Item $noNuFile -Force -ErrorAction SilentlyContinue }
if (Test-Path $noNuFile) { Write-Ok 'PowerShell stays PowerShell (install.ps1 -DefaultShell starts Nushell automatically)' }
else { Write-Ok 'PowerShell windows open Nushell (type powershell inside nu, or set TC_NO_NU=1, for plain PowerShell)' }

# Several oh-my-posh.exe on PATH (an old manual or Store install): the first one wins.
$ompCopies = @(Get-Command oh-my-posh.exe -All -CommandType Application -ErrorAction SilentlyContinue | ForEach-Object { $_.Source } | Select-Object -Unique)
if ($ompCopies.Count -gt 1) {
    Write-Warn "several oh-my-posh.exe are on PATH, the first one is used: $($ompCopies -join ', '). Uninstall the older copy (Settings > Apps) if it is not the winget one."
}

# --- cmd.exe (incl. Visual Studio "Developer Command Prompt"): Clink -------------------------
# Clink adds a real line editor to cmd.exe and runs config/clink/terminal-customization.lua in every
# cmd window: Oh My Posh prompt, ls/ll/la/lt/cat/df/du aliases, z/zi (zoxide).
Write-Step 'Configuring cmd.exe (Clink)'
function Find-Clink {
    $found = Get-Command clink -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) { return $found.Source }
    foreach ($dir in @(${env:ProgramFiles(x86)}, $env:ProgramFiles, (Join-Path $env:LOCALAPPDATA 'Programs'))) {
        if ($dir -and (Test-Path (Join-Path $dir 'clink\clink.bat'))) { return (Join-Path $dir 'clink\clink.bat') }
    }
    return $null
}
$clink = Find-Clink
if (-not $clink) {
    Write-Warn 'Clink not found, cmd.exe is not configured (winget install chrisant996.Clink, then run this script again)'
} else {
    $clinkScripts = Join-Path $TcHome 'clink'
    Invoke-Quiet { & $clink installscripts $clinkScripts } | Out-Null
    Add-ManifestEntry 'clink-scripts' $clinkScripts
    $autorun = @('HKCU:\Software\Microsoft\Command Processor', 'HKLM:\Software\Microsoft\Command Processor') |
        ForEach-Object { (Get-ItemProperty $_ -Name AutoRun -ErrorAction SilentlyContinue).AutoRun } |
        Where-Object { $_ -match 'clink' }
    if (-not $autorun) {
        Invoke-Quiet { & $clink autorun install -- --quiet } | Out-Null
        Add-ManifestEntry 'clink-autorun' 'HKCU'
        Write-Ok 'Clink now starts in every cmd.exe (clink autorun)'
    }
    Write-Ok "cmd.exe uses $clinkScripts\terminal-customization.lua (also in the Visual Studio Developer Command Prompt)"
}

# --- 5. bat theme --------------------------------------------------------------------------
$batDir = if (Test-Command bat) { ((bat --config-dir 2>$null) | Out-String).Trim() } else { '' }
# Only a real bat prints an absolute config directory.
if ($batDir -and [IO.Path]::IsPathRooted($batDir)) {
    $batThemes = Join-Path $batDir 'themes'
    New-Item -ItemType Directory -Path $batThemes -Force | Out-Null
    $theme = Join-Path $TcHome 'bat/themes/Microverse.tmTheme'
    $installedTheme = Join-Path $batThemes 'Microverse.tmTheme'
    if ((Test-Path $installedTheme) -and [IO.File]::ReadAllText($installedTheme) -ceq [IO.File]::ReadAllText($theme)) {
        Write-Ok "bat theme 'Microverse' already installed"
    } else {
        Copy-Item $theme $batThemes -Force
        Invoke-Quiet { bat cache --build } | Out-Null
        Write-Ok "bat theme 'Microverse' installed"
    }
}

# --- 6. Nushell ------------------------------------------------------------------------
Write-Step 'Configuring Nushell'
if (Test-Command nu) {
    $nuConfigDir = (nu --no-config-file -c '$nu.default-config-dir' | Out-String).Trim()
    $nuConfig = (nu --no-config-file -c '$nu.config-path' | Out-String).Trim()
    $autoload = Join-Path $nuConfigDir 'autoload'
    New-Item -ItemType Directory -Path $autoload -Force | Out-Null
    Copy-Item (Join-Path $TcHome 'nushell/terminal-customization.nu') $autoload -Force
    Disable-DuplicateNuLines $nuConfig 'oh-my-posh(\.exe)?\s+init\s+nu|zoxide(\.exe)?\s+init\s+nushell|fzf(\.exe)?\s+--nushell|source\s+.*\.zoxide\.nu|source\s+.*oh-my-posh\.nu'
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

# Windows Terminal starts the profile with the PATH it was launched with, which may not include
# Nushell yet (a fresh install, or an Explorer session started before it). So the profile gets
# the full path of nu.exe instead of a bare "nu.exe".
function Find-NuExe {
    $found = Get-Command nu.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) { return $found.Source }
    $candidates = @(
        (Join-Path $env:ProgramFiles 'nu\bin\nu.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\nu\bin\nu.exe'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links\nu.exe')
    )
    if (${env:ProgramFiles(x86)}) { $candidates += Join-Path ${env:ProgramFiles(x86)} 'nu\bin\nu.exe' }
    foreach ($candidate in $candidates) { if (Test-Path $candidate) { return $candidate } }
    return $null
}

$settingsFiles = @(
    (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'),
    (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json'),
    (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\settings.json')
) | Where-Object { Test-Path $_ }

$fragmentDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\Fragments\TerminalCustomization'
$fragmentFile = Join-Path $fragmentDir 'terminal-customization.json'
$firstInstall = -not (Test-Path $fragmentFile)
$nuExe = Find-NuExe
if (-not $nuExe) {
    Write-Warn "nu.exe was not found, so the '$WtProfileName' profile was not added. Install Nushell (winget install Nushell.Nushell) and run this script again."
    # An earlier run may have added the profile and made it the default; a default that can't start
    # would leave Windows Terminal unusable, so fall back to PowerShell until Nushell is installed.
    if (Test-Path $fragmentFile) { Remove-Item $fragmentDir -Recurse -Force; Write-Ok "removed the '$WtProfileName' profile" }
    $fallback = if (Get-Command pwsh -ErrorAction SilentlyContinue) { '{574e775e-4f2a-5b96-ac1e-a2962a402336}' } else { '{61c54bbd-c2c6-5271-96e7-009a87ff44bf}' }
    $ours = '"defaultProfile"\s*:\s*"(' + [regex]::Escape($WtProfileGuid) + '|' + [regex]::Escape($WtProfileName) + ')"'
    foreach ($settings in $settingsFiles) {
        $json = [IO.File]::ReadAllText($settings)
        if ($json -match $ours -and (Update-FileIfChanged $settings ([regex]::Replace($json, $ours, '"defaultProfile": "' + $fallback + '"')))) {
            Write-Ok "default profile set back to PowerShell in $settings"
        }
    }
} else {
    $fragment = [IO.File]::ReadAllText((Join-Path $TcHome 'windows-terminal\terminal-customization.json')) | ConvertFrom-Json
    $fragment.profiles[0].commandline = '"' + $nuExe + '"'
    $fragment.profiles[0].icon = $nuExe
    New-Item -ItemType Directory -Path $fragmentDir -Force | Out-Null
    [void](Update-FileIfChanged $fragmentFile ($fragment | ConvertTo-Json -Depth 10))
    Write-Ok "profile '$WtProfileName' ($nuExe) and colour scheme 'Microverse' added"

    # Only change the default profile on a first install or when asked; re-runs and upgrades keep
    # your choice. A default set by an older version of this script (by name) is moved to the GUID.
    $makeDefault = $DefaultShell -or ($firstInstall -and -not $NoDefaultShell)
    if ($makeDefault -and -not $settingsFiles) {
        Write-Warn "Windows Terminal settings not found. Start Windows Terminal once and re-run, or pick '$WtProfileName' in Settings > Startup > Default profile."
    }
    $byName = '"defaultProfile"\s*:\s*"' + [regex]::Escape($WtProfileName) + '"'
    $entry = '"defaultProfile": "' + $WtProfileGuid + '"'
    foreach ($settings in $settingsFiles) {
        $json = [IO.File]::ReadAllText($settings)
        if ($json -match $byName) {
            $json = [regex]::Replace($json, $byName, $entry, 1)
        } elseif (-not $makeDefault) {
            continue
        } elseif ($json -match '"defaultProfile"\s*:\s*"[^"]*"') {
            $json = [regex]::Replace($json, '"defaultProfile"\s*:\s*"[^"]*"', $entry, 1)
        } else {
            $json = ([regex]'\{').Replace($json, "{`r`n    $entry,", 1)
        }
        if (Update-FileIfChanged $settings $json) { Write-Ok "default profile set to '$WtProfileName' in $settings" }
    }
}

# Other Windows Terminal profiles (PowerShell, Command Prompt, Visual Studio's Developer PowerShell /
# Developer Command Prompt, ...) need the Nerd Font for the prompt icons. The font is only set when
# the profile defaults are still empty ("defaults": {}); your own defaults are never changed.
foreach ($settings in $settingsFiles) {
    $json = [IO.File]::ReadAllText($settings)
    $emptyDefaults = '"defaults"\s*:\s*\{\s*\}'
    if ($json -match $emptyDefaults) {
        $json = [regex]::Replace($json, $emptyDefaults, '"defaults": { "font": { "face": "JetBrainsMono NFM" } }', 1)
        if (Update-FileIfChanged $settings $json) {
            Add-ManifestEntry 'wt-defaults-font' $settings
            Write-Ok "all Windows Terminal profiles use JetBrainsMono Nerd Font Mono ($settings)"
        }
    } elseif ($json -notmatch 'Nerd Font|NFM?P?\b') {
        Write-Warn "Windows Terminal: set the font of your other profiles (Settings > Defaults > Appearance > Font face) to 'JetBrainsMono NFM' for the icons."
    }
}

# --- VS Code integrated terminal font ------------------------------------------------------
# VS Code has its own font setting (terminal.integrated.fontFamily), unrelated to Windows
# Terminal's. Only set when missing, so your own choice is never overwritten.
Write-Step 'Configuring the VS Code integrated terminal font'
$vscodeSettingsFiles = @(
    (Join-Path $env:APPDATA 'Code\User\settings.json')
    (Join-Path $env:APPDATA 'Code - Insiders\User\settings.json')
) | Where-Object { Test-Path $_ }
if (-not $vscodeSettingsFiles) {
    Write-Ok 'VS Code not found (no settings.json yet)'
} else {
    foreach ($settings in $vscodeSettingsFiles) {
        $json = [IO.File]::ReadAllText($settings)
        if ($json -match '"terminal\.integrated\.fontFamily"') {
            Write-Ok "VS Code already has a terminal font set, left alone ($settings)"
            continue
        }
        $updated = ([regex]'\{').Replace($json, "{`r`n    ""terminal.integrated.fontFamily"": ""JetBrainsMono NFM"",", 1)
        if (Update-FileIfChanged $settings $updated) {
            Add-ManifestEntry 'vscode-font' $settings
            Write-Ok "VS Code integrated terminal uses JetBrainsMono NFM ($settings)"
        }
    }
}

# --- done --------------------------------------------------------------------------------
Write-Step 'Done'
Write-Host '  Open a new Windows Terminal tab/window to start Nushell with the new prompt.'
Write-Host "  Other terminals (Visual Studio's terminal, conhost): set the font to 'JetBrainsMono NFM'."
Write-Host '  Restart Visual Studio (and other programs that were open during the install) so their shells get the new PATH.'
Write-Host '  Prompt still looks old? Run: Get-Content $PROFILE  - and look for oh-my-posh lines outside the terminal-customization block.'
if ((Test-Command gh) -and (Invoke-Quiet { gh auth status }) -ne 0) { Write-Host "  Run 'gh auth login' to sign in to GitHub." }
