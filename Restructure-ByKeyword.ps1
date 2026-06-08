<#
.SYNOPSIS
    Search files by keyword and optionally restructure matches into a folder
    named exactly after the keyword.

.DESCRIPTION
    Splits the keyword into words and finds every file whose name contains ALL
    of those words, in any order and regardless of separators. So "ghost key"
    matches: ghostkey, ghost.key, ghost_key, ghost-key, ghost key, key ghost...

.EXAMPLE
    .\Restructure-ByKeyword.ps1
    .\Restructure-ByKeyword.ps1 -Keyword "ghost key" -Path "C:\Stuff"
#>

[CmdletBinding()]
param(
    [string]$Keyword,
    [string]$Path = (Get-Location).Path
)

# --- Get the keyword ---
if (-not $Keyword) {
    $Keyword = Read-Host "Enter keyword to search for (e.g. ghost key)"
}
$Keyword = $Keyword.Trim()
if ([string]::IsNullOrWhiteSpace($Keyword)) {
    Write-Host "No keyword provided. Exiting." -ForegroundColor Yellow
    return
}

# Each word must appear in the file name (any order, any separator)
$tokens = $Keyword -split '\s+' | Where-Object { $_ -ne '' }

Write-Host ""
Write-Host "Searching '$Path' for files matching: $($tokens -join ' + ')" -ForegroundColor Cyan
Write-Host ""

# --- Search every folder ---
$results = Get-ChildItem -Path $Path -File -Recurse -ErrorAction SilentlyContinue |
    Where-Object {
        $name = $_.Name.ToLower()
        $ok = $true
        foreach ($t in $tokens) {
            if ($name -notlike "*$($t.ToLower())*") { $ok = $false; break }
        }
        $ok
    }

if (-not $results) {
    Write-Host "No files found containing all of: $($tokens -join ', ')" -ForegroundColor Yellow
    return
}

# --- Print the list ---
$i = 1
foreach ($f in $results) {
    "{0,3}. {1}" -f $i, $f.FullName | Write-Host
    $i++
}
Write-Host ""
Write-Host "Found $($results.Count) file(s)." -ForegroundColor Green
Write-Host ""

# --- Ask to restructure ---
$answer = Read-Host "Restructure these into a folder named '$Keyword'? (yes/no)"
if ($answer.Trim().ToLower() -notin @('y', 'yes', 'restructure')) {
    Write-Host "No changes made." -ForegroundColor Yellow
    return
}

# --- Create the target folder (named exactly the keyword) ---
$target = Join-Path -Path $Path -ChildPath $Keyword
if (-not (Test-Path -LiteralPath $target)) {
    New-Item -ItemType Directory -Path $target | Out-Null
    Write-Host "Created folder: $target" -ForegroundColor Green
}
$targetFull = (Resolve-Path -LiteralPath $target).Path

# --- Move the files ---
$moved = 0
foreach ($f in $results) {
    # Don't try to move files that are already in the target folder
    if ($f.DirectoryName -eq $targetFull) { continue }

    $dest = Join-Path -Path $target -ChildPath $f.Name

    # Handle name collisions: "file (1).txt", "file (2).txt", ...
    if (Test-Path -LiteralPath $dest) {
        $base = [IO.Path]::GetFileNameWithoutExtension($f.Name)
        $ext  = [IO.Path]::GetExtension($f.Name)
        $n = 1
        do {
            $dest = Join-Path $target ("{0} ({1}){2}" -f $base, $n, $ext)
            $n++
        } while (Test-Path -LiteralPath $dest)
    }

    try {
        Move-Item -LiteralPath $f.FullName -Destination $dest -ErrorAction Stop
        $moved++
    } catch {
        Write-Host "Failed to move $($f.FullName): $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "Done. Moved $moved file(s) into '$target'." -ForegroundColor Green
