<#
.SYNOPSIS
    Copy the Digital Footprint Scanner to your Desktop and create a
    double-clickable shortcut. (Reports are written to a separate
    "digital footprint" folder on your Desktop.)

.EXAMPLE
    .\Deploy-DigitalFootprint.ps1
#>

[CmdletBinding()]
param(
    [string]$FolderName = 'Digital Footprint Scanner'
)

$ErrorActionPreference = 'Stop'

$src = $PSScriptRoot
if (-not $src) { $src = (Get-Location).Path }

$files = @(
    'footprint.py',
    'config.example.json',
    'data_brokers.json',
    'sites_usernames.json',
    'Launch-DigitalFootprint.cmd',
    'Install-Footprint-Tools.ps1',
    'README.md'
)
foreach ($f in $files) {
    if (-not (Test-Path -LiteralPath (Join-Path $src $f))) {
        Write-Host "Missing '$f' next to this script - run it from the digital-footprint folder." -ForegroundColor Red
        return
    }
}

$desktop = [Environment]::GetFolderPath('Desktop')
$dest    = Join-Path $desktop $FolderName
New-Item -ItemType Directory -Path $dest -Force | Out-Null
foreach ($f in $files) { Copy-Item -LiteralPath (Join-Path $src $f) -Destination $dest -Force }

# Make sure the reports folder exists too.
New-Item -ItemType Directory -Path (Join-Path $desktop 'digital footprint') -Force | Out-Null

$lnkPath = Join-Path $desktop ($FolderName + '.lnk')
$target  = Join-Path $dest 'Launch-DigitalFootprint.cmd'
$wsh = New-Object -ComObject WScript.Shell
$sc  = $wsh.CreateShortcut($lnkPath)
$sc.TargetPath       = $target
$sc.WorkingDirectory = $dest
$sc.IconLocation     = "$env:SystemRoot\System32\imageres.dll,77"
$sc.Description       = 'Scan your own digital footprint for data-removal requests'
$sc.Save()

Write-Host "Deployed!" -ForegroundColor Green
Write-Host ""
Write-Host "  Scanner folder : $dest"
Write-Host "  Reports folder : $(Join-Path $desktop 'digital footprint')"
Write-Host "  Shortcut       : $lnkPath"
Write-Host ""
Write-Host "First: run Install-Footprint-Tools.ps1 (once) to add Sherlock/Maigret/holehe." -ForegroundColor Yellow
Write-Host "Then double-click '$FolderName' on your Desktop. Run #1 creates config.json - fill it in and run again." -ForegroundColor Yellow
