<#
.SYNOPSIS
    Copy the Keyword Forensic Toolkit to your Desktop and create a
    double-clickable shortcut.

.DESCRIPTION
    Copies the toolkit files into a folder on your Desktop and drops a shortcut
    named "Keyword Forensic Toolkit" on the Desktop that points at the launcher.
    Re-running is safe - it overwrites the copies and refreshes the shortcut.

.EXAMPLE
    .\Deploy-ToDesktop.ps1
    .\Deploy-ToDesktop.ps1 -FolderName "Forensics"
#>

[CmdletBinding()]
param(
    [string]$FolderName = 'Keyword Forensic Toolkit'
)

$ErrorActionPreference = 'Stop'

$src = $PSScriptRoot
if (-not $src) { $src = (Get-Location).Path }

$files = @(
    'Restructure-ByKeyword.ps1',
    'Launch-ForensicToolkit.cmd',
    'Restructure-ByKeyword.md'
)
foreach ($f in $files) {
    if (-not (Test-Path -LiteralPath (Join-Path $src $f))) {
        Write-Host "Missing '$f' next to this script - run it from the toolkit folder." -ForegroundColor Red
        return
    }
}

# Copy the files into a folder on the Desktop.
$desktop = [Environment]::GetFolderPath('Desktop')
$dest    = Join-Path $desktop $FolderName
New-Item -ItemType Directory -Path $dest -Force | Out-Null
foreach ($f in $files) { Copy-Item -LiteralPath (Join-Path $src $f) -Destination $dest -Force }

# Drop a double-clickable shortcut on the Desktop itself.
$lnkPath = Join-Path $desktop ($FolderName + '.lnk')
$target  = Join-Path $dest 'Launch-ForensicToolkit.cmd'
$wsh = New-Object -ComObject WScript.Shell
$sc  = $wsh.CreateShortcut($lnkPath)
$sc.TargetPath       = $target
$sc.WorkingDirectory = $dest
$sc.IconLocation     = "$env:SystemRoot\System32\imageres.dll,3"
$sc.Description       = 'Search files by keyword and run a forensic analysis menu'
$sc.Save()

Write-Host "Deployed!" -ForegroundColor Green
Write-Host ""
Write-Host "  Files folder : $dest"
Write-Host "  Shortcut     : $lnkPath"
Write-Host ""
Write-Host "Double-click '$FolderName' on your Desktop to launch." -ForegroundColor Yellow
Write-Host "Tip: you can also drag any folder onto the shortcut to search it." -ForegroundColor DarkGray
