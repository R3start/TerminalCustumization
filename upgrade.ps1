<#
.SYNOPSIS
    TerminalCustumization - upgrade everything on Windows to the latest versions.

.DESCRIPTION
    1. From a git clone: pulls the latest version of this repository (fast-forward only).
    2. Runs install.ps1, which upgrades every tool with winget, refreshes the JetBrainsMono
       Nerd Font and the configuration files. Your choices (default Windows Terminal profile,
       your own profile lines) are kept; changed config files are backed up first.
    3. Prints the versions before and after.

.EXAMPLE
    irm https://raw.githubusercontent.com/R3start/TerminalCustumization/main/upgrade.ps1 | iex

.EXAMPLE
    .\upgrade.ps1 -SkipFonts
#>
[CmdletBinding()]
param(
    [switch]$SkipTools,
    [switch]$SkipFonts,
    [switch]$SkipConfig
)

$ErrorActionPreference = 'Stop'
$RepoRaw = if ($env:TC_REPO_RAW) { $env:TC_REPO_RAW } else { 'https://raw.githubusercontent.com/R3start/TerminalCustumization/main' }
$Tools = 'oh-my-posh', 'nu', 'eza', 'bat', 'rg', 'fzf', 'zoxide', 'duf', 'dust', 'gh', 'pwsh'

function Get-ToolVersions {
    $result = [ordered]@{}
    foreach ($tool in $Tools) {
        $version = '-'
        if (Get-Command $tool -ErrorAction SilentlyContinue) {
            $ErrorActionPreference = 'Continue'
            $output = if ($tool -eq 'oh-my-posh') { & $tool version 2>&1 } else { & $tool --version 2>&1 }
            $match = [regex]::Match(($output | Out-String), '\d+\.\d+(\.\d+)?')
            if ($match.Success) { $version = $match.Value }
        }
        $result[$tool] = $version
    }
    $result
}

$before = Get-ToolVersions

$installArgs = @{ UpdateFonts = $true }
foreach ($name in 'SkipTools', 'SkipFonts', 'SkipConfig') {
    if ($PSBoundParameters.ContainsKey($name)) { $installArgs[$name] = $PSBoundParameters[$name] }
}

$localInstaller = if ($PSScriptRoot) { Join-Path $PSScriptRoot 'install.ps1' } else { $null }
if ($localInstaller -and (Test-Path $localInstaller)) {
    if ((Get-Command git -ErrorAction SilentlyContinue) -and (Test-Path (Join-Path $PSScriptRoot '.git'))) {
        Write-Host "`n==> Updating the repository in $PSScriptRoot" -ForegroundColor Blue
        $ErrorActionPreference = 'Continue'
        git -C $PSScriptRoot pull --ff-only
        if ($LASTEXITCODE -ne 0) { Write-Host '  [!]  git pull failed (local changes?) - continuing with the current checkout' -ForegroundColor Yellow }
        $ErrorActionPreference = 'Stop'
    }
    & $localInstaller @installArgs
} else {
    & ([scriptblock]::Create((Invoke-WebRequest -UseBasicParsing "$RepoRaw/install.ps1").Content)) @installArgs
}

$after = Get-ToolVersions
Write-Host "`n==> Versions" -ForegroundColor Blue
foreach ($tool in $Tools) {
    $mark = if ($before[$tool] -ne $after[$tool]) { '(upgraded)' } else { '' }
    Write-Host ('  {0,-12} {1,-14} {2} {3}' -f $tool, $before[$tool], $after[$tool], $mark)
}
