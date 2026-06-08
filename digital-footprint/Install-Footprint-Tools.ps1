<#
.SYNOPSIS
    Install the open-source OSINT tools the Digital Footprint Scanner can use:
    Sherlock (usernames), Maigret (usernames), and holehe (email accounts).

.DESCRIPTION
    Verifies Python is present, then installs the tools with pipx (preferred,
    isolated) or falls back to "pip install --user". Re-running is safe.

.EXAMPLE
    .\Install-Footprint-Tools.ps1
#>

[CmdletBinding()]
param()

function Get-Python {
    foreach ($c in @('py -3', 'python', 'python3')) {
        $exe = ($c -split ' ')[0]
        if (Get-Command $exe -ErrorAction SilentlyContinue) { return $c }
    }
    return $null
}

$py = Get-Python
if (-not $py) {
    Write-Host "Python was not found. Install it from https://www.python.org/downloads/" -ForegroundColor Red
    Write-Host "(check 'Add python.exe to PATH' during setup), then re-run this script." -ForegroundColor Yellow
    return
}
Write-Host "Using Python: $py" -ForegroundColor Green

# Make sure pip + pipx are available.
Invoke-Expression "$py -m pip install --upgrade --user pip pipx" 2>&1 | Out-Host
Invoke-Expression "$py -m pipx ensurepath" 2>&1 | Out-Host

$tools = @('sherlock-project', 'maigret', 'holehe')
$usePipx = $true
try { Invoke-Expression "$py -m pipx --version" 2>$null | Out-Null } catch { $usePipx = $false }

foreach ($t in $tools) {
    Write-Host ""
    Write-Host "Installing $t ..." -ForegroundColor Cyan
    if ($usePipx) {
        Invoke-Expression "$py -m pipx install $t" 2>&1 | Out-Host
    } else {
        Invoke-Expression "$py -m pip install --user $t" 2>&1 | Out-Host
    }
}

Write-Host ""
Write-Host "Done. Open a NEW terminal so PATH updates take effect, then check:" -ForegroundColor Green
Write-Host "  sherlock --help" -ForegroundColor DarkGray
Write-Host "  maigret --help"  -ForegroundColor DarkGray
Write-Host "  holehe --help"   -ForegroundColor DarkGray
Write-Host ""
Write-Host "Note: 'sherlock-project' provides the 'sherlock' command. If any tool" -ForegroundColor DarkGray
Write-Host "isn't found, the scanner still runs using its built-in checks." -ForegroundColor DarkGray
