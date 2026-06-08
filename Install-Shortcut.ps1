<#
.SYNOPSIS
    Install (or remove) a shell shortcut for Restructure-ByKeyword.ps1 so you
    can run it from anywhere as `restruct` or `fkr`.

.DESCRIPTION
    Adds a small, clearly-marked block to your PowerShell profile that defines a
    wrapper function plus two aliases pointing at Restructure-ByKeyword.ps1 in
    this folder. Re-running is safe (the block is replaced, not duplicated).

.EXAMPLE
    .\Install-Shortcut.ps1
    .\Install-Shortcut.ps1 -Uninstall
#>

[CmdletBinding()]
param(
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'

$scriptDir = $PSScriptRoot
if (-not $scriptDir) { $scriptDir = (Get-Location).Path }
$targetPs1 = Join-Path $scriptDir 'Restructure-ByKeyword.ps1'

if (-not (Test-Path -LiteralPath $targetPs1)) {
    Write-Host "Cannot find Restructure-ByKeyword.ps1 next to this installer." -ForegroundColor Red
    return
}

$startMarker = '# >>> keyword-restructure shortcut >>>'
$endMarker   = '# <<< keyword-restructure shortcut <<<'

# Ensure the profile file exists.
$profilePath = $PROFILE
if (-not (Test-Path -LiteralPath $profilePath)) {
    New-Item -ItemType File -Path $profilePath -Force | Out-Null
}

# Strip any existing shortcut block so install is idempotent and uninstall works.
$content = Get-Content -LiteralPath $profilePath -Raw -ErrorAction SilentlyContinue
if ($null -eq $content) { $content = '' }
$pattern = "(?s)\r?\n?" + [regex]::Escape($startMarker) + ".*?" + [regex]::Escape($endMarker)
$content = [regex]::Replace($content, $pattern, '')

if ($Uninstall) {
    Set-Content -LiteralPath $profilePath -Value $content.TrimEnd() -Encoding UTF8
    Write-Host "Removed the keyword-restructure shortcut from your profile." -ForegroundColor Green
    Write-Host "Open a new shell (or run '. `$PROFILE') to apply." -ForegroundColor DarkGray
    return
}

$block = @"
$startMarker
function Invoke-KeywordRestructure { & "$targetPs1" @args }
Set-Alias restruct Invoke-KeywordRestructure
Set-Alias fkr      Invoke-KeywordRestructure
$endMarker
"@

$content = $content.TrimEnd() + "`r`n`r`n" + $block + "`r`n"
Set-Content -LiteralPath $profilePath -Value $content -Encoding UTF8

Write-Host "Installed!" -ForegroundColor Green
Write-Host ""
Write-Host "Profile updated : $profilePath"
Write-Host "New commands    : " -NoNewline
Write-Host "restruct" -ForegroundColor Cyan -NoNewline
Write-Host "  or  " -NoNewline
Write-Host "fkr" -ForegroundColor Cyan
Write-Host ""
Write-Host "Reload now with : . `$PROFILE" -ForegroundColor Yellow
Write-Host "Then try        : restruct `"ghost key`"" -ForegroundColor Yellow
Write-Host ""
Write-Host "Tip: if scripts are blocked, run once -> Set-ExecutionPolicy -Scope CurrentUser RemoteSigned" -ForegroundColor DarkGray
