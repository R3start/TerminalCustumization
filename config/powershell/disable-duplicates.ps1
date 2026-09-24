<#
.SYNOPSIS
    Disables statements in a PowerShell profile that would load a tool a second time.

.DESCRIPTION
    Used by install.ps1 and install.sh. Uses the PowerShell parser, so a statement that spans
    several lines (a pipeline, a hashtable argument, a script block) is disabled as a whole.
    It disables only what this setup replaces:
      - oh-my-posh init ... and zoxide init powershell
      - Import-Module PSReadLine / Terminal-Icons (the previous version of this repository)
      - Set-PSReadLineOption calls that only use the old repository's settings
        (-PredictionSource, -PredictionViewStyle, -EditMode); other PSReadLine settings are kept
      - hand-added copies of the line that loads terminal-customization\powershell\profile.ps1
    Statements inside the "# >>> terminal-customization >>>" block are never touched. If the file
    has syntax errors or a statement shares a line with other code, nothing is changed for it and
    a message tells you to remove it by hand. The original file is backed up (*.tc-backup-<date>)
    and written back in place with its encoding, so symlinks and permissions are kept.
    Output: one line per event, "disabled <n>" or "skipped <line>: <reason>" or "error: <reason>".
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Path
)

$MarkBegin = '# >>> terminal-customization >>>'
$MarkEnd = '# <<< terminal-customization <<<'
$Prefix = '# disabled by terminal-customization: '
$OldReadLineParameters = 'PredictionSource', 'PredictionViewStyle', 'EditMode'

if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return }

# Read with the file's own encoding (BOM detection) so it can be written back the same way.
$reader = New-Object IO.StreamReader($Path, (New-Object Text.UTF8Encoding($false)), $true)
try { $text = $reader.ReadToEnd(); $encoding = $reader.CurrentEncoding } finally { $reader.Dispose() }

$tokens = $null
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseInput($text, [ref]$tokens, [ref]$errors)
if ($errors.Count -gt 0) {
    "error: the file has syntax errors, nothing was changed"
    return
}

$newline = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
$lines = [Collections.Generic.List[string]]($text -split '\r?\n')

# Lines of the managed block (1-based line numbers).
$blockLines = @{}
$inBlock = $false
for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -eq $MarkBegin) { $inBlock = $true }
    if ($inBlock) { $blockLines[$i + 1] = $true }
    if ($lines[$i] -eq $MarkEnd) { $inBlock = $false }
}

function Test-Duplicate([System.Management.Automation.Language.CommandAst]$Command) {
    $elements = $Command.CommandElements
    # `. "$HOME\...\profile.ps1"` has no constant command name, so check it first.
    if ($Command.InvocationOperator -eq 'Dot' -and
        $elements[0].Extent.Text -match 'terminal-customization[\\/]powershell[\\/]profile\.ps1') { return $true }
    $name = $Command.GetCommandName()
    if (-not $name) { return $false }
    $name = [IO.Path]::GetFileNameWithoutExtension($name)
    $second = if ($elements.Count -gt 1) { $elements[1].Extent.Text } else { '' }

    if ($name -eq 'oh-my-posh' -and $second -eq 'init') { return $true }
    if ($name -eq 'zoxide' -and $second -eq 'init') { return $true }
    if ($name -eq 'Import-Module') {
        $modules = $elements | Select-Object -Skip 1 |
            Where-Object { $_ -isnot [System.Management.Automation.Language.CommandParameterAst] } |
            ForEach-Object { $_.Extent.Text.Trim('''', '"') }
        return [bool]($modules | Where-Object { $_ -in 'PSReadLine', 'Terminal-Icons' })
    }
    if ($name -eq 'Set-PSReadLineOption') {
        $parameters = @($elements | Where-Object { $_ -is [System.Management.Automation.Language.CommandParameterAst] } |
            ForEach-Object { $_.ParameterName })
        if ($parameters.Count -eq 0) { return $false }
        foreach ($p in $parameters) { if ($p -notin $OldReadLineParameters) { return $false } }
        return $true
    }
    return $false
}

# The statement to disable: walk up to the statement that sits directly in the script, a function,
# or an if/loop/try body. Script blocks that are only an argument (Invoke-Expression (& { ... }))
# are walked through, so the whole outer statement is disabled.
function Get-Statement([System.Management.Automation.Language.Ast]$Node) {
    while ($Node.Parent) {
        $parent = $Node.Parent
        if ($parent -is [System.Management.Automation.Language.StatementBlockAst]) { return $Node }
        if ($parent -is [System.Management.Automation.Language.NamedBlockAst]) {
            $scriptBlock = $parent.Parent
            $owner = $scriptBlock.Parent
            if ($null -eq $owner -or $owner -is [System.Management.Automation.Language.FunctionDefinitionAst]) { return $Node }
        }
        $Node = $parent
    }
    return $Node
}

$statements = @{}
foreach ($command in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)) {
    if (-not (Test-Duplicate $command)) { continue }
    $statement = Get-Statement $command
    $statements[$statement.Extent.StartOffset] = $statement
}

$disabled = 0
$changed = @{}
foreach ($statement in ($statements.Values | Sort-Object { $_.Extent.StartOffset })) {
    $extent = $statement.Extent
    $first = $extent.StartLineNumber
    $last = $extent.EndLineNumber
    # Skip statements nested in one we already disabled.
    if ($changed.ContainsKey($first)) { continue }
    $inManagedBlock = $false
    for ($n = $first; $n -le $last; $n++) { if ($blockLines.ContainsKey($n)) { $inManagedBlock = $true } }
    if ($inManagedBlock) { continue }
    $before = $lines[$first - 1].Substring(0, $extent.StartColumnNumber - 1)
    $after = $lines[$last - 1].Substring($extent.EndColumnNumber - 1)
    if ($before.Trim() -or ($after.Trim() -and -not $after.Trim().StartsWith('#'))) {
        "skipped ${first}: shares the line with other code, remove it by hand"
        continue
    }
    for ($n = $first; $n -le $last; $n++) {
        $lines[$n - 1] = $Prefix + $lines[$n - 1]
        $changed[$n] = $true
    }
    $disabled++
}

if ($disabled -gt 0) {
    Copy-Item -LiteralPath $Path -Destination "$Path.tc-backup-$(Get-Date -Format yyyyMMddHHmmss)" -Force
    # WriteAllText writes into the existing file: a symlink keeps pointing to its target and the
    # file keeps its permissions.
    [IO.File]::WriteAllText((Resolve-Path -LiteralPath $Path).ProviderPath, ($lines -join $newline), $encoding)
    "disabled $disabled"
}
