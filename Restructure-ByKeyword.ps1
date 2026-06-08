<#
.SYNOPSIS
    Find files by keyword (name and/or content), then drive a navigable
    forensic extraction/analysis menu over the matches - or restructure them
    into a folder named after the keyword.

.DESCRIPTION
    Splits the keyword into words and finds every file whose NAME contains ALL
    of those words, in any order and regardless of separators. So "ghost key"
    matches: ghostkey, ghost.key, ghost_key, ghost-key, ghost key, key ghost...
    With -IncludeContent it ALSO matches files whose text contains all the words.

    The matches are then handed to an arrow-key navigable menu (letter shortcuts
    work too) offering forensic-style tooling: metadata/MAC timestamps, MD5/SHA256
    hashing, magic-byte signature vs extension checks, Shannon entropy, hex header
    dumps, printable-strings extraction, a chronological timeline, duplicate
    detection, content grep, an evidence-report export (CSV + JSON), plus a
    dry-run preview and the restructure (move) action.

.PARAMETER Keyword
    The words to search for, e.g. "ghost key". Prompted for if omitted.
.PARAMETER Path
    Root folder to search (recursive). Defaults to the current directory.
.PARAMETER IncludeContent
    Also match files whose text content contains all the keyword words.
.PARAMETER MaxContentSizeMB
    Skip files larger than this when reading content (default 50 MB).

.EXAMPLE
    .\Restructure-ByKeyword.ps1
    .\Restructure-ByKeyword.ps1 -Keyword "ghost key" -Path "C:\Evidence" -IncludeContent
#>

[CmdletBinding()]
param(
    [string]$Keyword,
    [string]$Path = (Get-Location).Path,
    [switch]$IncludeContent,
    [int]$MaxContentSizeMB = 50
)

# ===========================================================================
# Small helpers
# ===========================================================================

function Format-Size {
    param([long]$Bytes)
    if ($Bytes -ge 1GB) { return ('{0:N2} GB' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:N2} MB' -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ('{0:N2} KB' -f ($Bytes / 1KB)) }
    return "$Bytes B"
}

function Read-Key {
    param([string]$Prompt)
    if ($Prompt) { Write-Host $Prompt -NoNewline -ForegroundColor White }
    try { $k = [System.Console]::ReadKey($true); Write-Host ""; return "$($k.KeyChar)".ToLower() }
    catch { return (Read-Host).Trim().ToLower() }
}

function Test-AllTokens {
    param([string]$Text, [string[]]$Tokens)
    if ([string]::IsNullOrEmpty($Text)) { return $false }
    $t = $Text.ToLower()
    foreach ($tok in $Tokens) { if ($t -notlike "*$($tok.ToLower())*") { return $false } }
    return $true
}

# Read up to N bytes from the front of a file (used by several forensic tools).
function Get-HeadBytes {
    param([System.IO.FileInfo]$File, [int]$Count)
    try {
        $fs = [System.IO.File]::OpenRead($File.FullName)
        try {
            $len = [Math]::Min($Count, $File.Length)
            $buf = New-Object byte[] $len
            $read = $fs.Read($buf, 0, $len)
            if ($read -lt $len) { $buf = $buf[0..([Math]::Max($read-1,0))] }
            return ,$buf
        } finally { $fs.Dispose() }
    } catch { return $null }
}

# ===========================================================================
# Known file signatures (magic bytes) for type / masquerade detection
# ===========================================================================

$script:Signatures = @(
    @{ Hex='FFD8FF';           Type='JPEG image';                 Ext=@('.jpg','.jpeg') }
    @{ Hex='89504E470D0A1A0A'; Type='PNG image';                  Ext=@('.png') }
    @{ Hex='47494638';         Type='GIF image';                  Ext=@('.gif') }
    @{ Hex='25504446';         Type='PDF document';               Ext=@('.pdf') }
    @{ Hex='504B0304';         Type='ZIP / OOXML / JAR / APK';    Ext=@('.zip','.docx','.xlsx','.pptx','.jar','.apk','.odt','.epub') }
    @{ Hex='526172211A07';     Type='RAR archive';                Ext=@('.rar') }
    @{ Hex='377ABCAF271C';     Type='7-Zip archive';              Ext=@('.7z') }
    @{ Hex='1F8B';             Type='GZIP archive';               Ext=@('.gz','.tgz') }
    @{ Hex='425A68';           Type='BZIP2 archive';              Ext=@('.bz2') }
    @{ Hex='4D5A';             Type='Windows PE (exe/dll/sys)';   Ext=@('.exe','.dll','.sys','.scr') }
    @{ Hex='7F454C46';         Type='ELF executable';             Ext=@('') }
    @{ Hex='D0CF11E0A1B11AE1'; Type='MS Office legacy (doc/xls)'; Ext=@('.doc','.xls','.ppt','.msi') }
    @{ Hex='49443303';         Type='MP3 audio (ID3)';            Ext=@('.mp3') }
    @{ Hex='424D';             Type='BMP image';                  Ext=@('.bmp') }
    @{ Hex='49492A00';         Type='TIFF image';                 Ext=@('.tif','.tiff') }
    @{ Hex='4D4D002A';         Type='TIFF image';                 Ext=@('.tif','.tiff') }
    @{ Hex='CAFEBABE';         Type='Java class';                 Ext=@('.class') }
    @{ Hex='3C3F786D6C';       Type='XML document';               Ext=@('.xml','.svg') }
    @{ Hex='255044462D';       Type='PDF document';               Ext=@('.pdf') }
)

function Get-FileSignatureInfo {
    param([System.IO.FileInfo]$File)
    $bytes = Get-HeadBytes -File $File -Count 16
    if ($null -eq $bytes) { return [pscustomobject]@{ Type='(unreadable)'; Mismatch=$false; HeaderHex='' } }
    $hex = ($bytes | ForEach-Object { $_.ToString('X2') }) -join ''
    $type = 'unknown / data'; $matched = $null
    foreach ($s in $script:Signatures) { if ($hex.StartsWith($s.Hex)) { $type = $s.Type; $matched = $s; break } }
    $mismatch = $false
    $ext = $File.Extension.ToLower()
    if ($matched -and $ext -and ($matched.Ext -notcontains $ext) -and ($matched.Ext -notcontains '')) { $mismatch = $true }
    [pscustomobject]@{ Type=$type; Mismatch=$mismatch; HeaderHex=(($hex -replace '(..)','$1 ').Trim()) }
}

function Get-ShannonEntropy {
    param([System.IO.FileInfo]$File, [int]$SampleBytes = 262144)
    $buf = Get-HeadBytes -File $File -Count $SampleBytes
    if ($null -eq $buf -or $buf.Length -eq 0) { return 0.0 }
    $counts = New-Object 'int[]' 256
    foreach ($b in $buf) { $counts[$b]++ }
    $n = $buf.Length; $entropy = 0.0
    foreach ($c in $counts) { if ($c -gt 0) { $p = $c / $n; $entropy -= $p * [Math]::Log($p, 2) } }
    return [Math]::Round($entropy, 3)
}

function Get-PrintableStrings {
    param([System.IO.FileInfo]$File, [int]$MinLen = 4, [int]$Max = 200, [int]$SampleBytes = 1048576)
    $out = New-Object System.Collections.Generic.List[string]
    $buf = Get-HeadBytes -File $File -Count $SampleBytes
    if ($null -eq $buf) { return $out }
    $sb = New-Object System.Text.StringBuilder
    foreach ($b in $buf) {
        if ($b -ge 32 -and $b -le 126) { [void]$sb.Append([char]$b) }
        else {
            if ($sb.Length -ge $MinLen) { $out.Add($sb.ToString()); if ($out.Count -ge $Max) { break } }
            [void]$sb.Clear()
        }
    }
    if ($sb.Length -ge $MinLen -and $out.Count -lt $Max) { $out.Add($sb.ToString()) }
    return $out
}

# ===========================================================================
# Get the keyword + search
# ===========================================================================

if (-not $Keyword) { $Keyword = Read-Host "Enter keyword to search for (e.g. ghost key)" }
$Keyword = $Keyword.Trim()
if ([string]::IsNullOrWhiteSpace($Keyword)) { Write-Host "No keyword provided. Exiting." -ForegroundColor Yellow; return }
$tokens = $Keyword -split '\s+' | Where-Object { $_ -ne '' }

Write-Host ""
Write-Host "Searching '$Path' for: $($tokens -join ' + ')" -ForegroundColor Cyan
if ($IncludeContent) { Write-Host "(also reading file contents - this may take a while)" -ForegroundColor DarkGray }

$maxBytes = [long]$MaxContentSizeMB * 1MB
$results  = New-Object System.Collections.Generic.List[object]

Get-ChildItem -Path $Path -File -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
    $file = $_
    $nameMatch = Test-AllTokens -Text $file.Name -Tokens $tokens
    $contentMatch = $false
    if ($IncludeContent -and -not $nameMatch -and $file.Length -le $maxBytes) {
        try { $contentMatch = Test-AllTokens -Text (Get-Content -LiteralPath $file.FullName -Raw -ErrorAction Stop) -Tokens $tokens } catch { }
    }
    if ($nameMatch -or $contentMatch) {
        $matchKind = if ($nameMatch) { 'Name' } else { 'Content' }
        $results.Add([pscustomobject]@{ File = $file; Match = $matchKind })
    }
}

if ($results.Count -eq 0) { Write-Host "`nNo files found containing all of: $($tokens -join ', ')" -ForegroundColor Yellow; return }

# ===========================================================================
# Listing + forensic action functions (all operate on the $Results list)
# ===========================================================================

function Show-Results {
    param($Results)
    $i = 1
    foreach ($r in $Results) {
        $tag = if ($r.Match -eq 'Content') { '[C]' } else { '[N]' }
        "{0,3}. {1} {2}" -f $i, $tag, $r.File.FullName | Write-Host
        $i++
    }
    Write-Host ""
    Write-Host "$($Results.Count) match(es).  [N] = name match   [C] = content match" -ForegroundColor Green
}

function Show-CompactList { param($Results) $i = 1; foreach ($r in $Results) { "{0,3}. {1}" -f $i, $r.File.Name | Write-Host; $i++ }; Write-Host "" }

function Select-OneFile {
    param($Results, [string]$Prompt)
    $n = Read-Host $Prompt
    [int]$idx = 0
    if (-not [int]::TryParse($n, [ref]$idx)) { Write-Host "Not a number." -ForegroundColor Yellow; return $null }
    if ($idx -lt 1 -or $idx -gt $Results.Count) { Write-Host "Out of range." -ForegroundColor Yellow; return $null }
    return $Results[$idx-1].File
}

function Invoke-Metadata {
    param($Results)
    $Results.File | Select-Object Name,
        @{N='Size';E={Format-Size $_.Length}},
        @{N='Created';E={'{0:yyyy-MM-dd HH:mm}' -f $_.CreationTime}},
        @{N='Modified';E={'{0:yyyy-MM-dd HH:mm}' -f $_.LastWriteTime}},
        @{N='Accessed';E={'{0:yyyy-MM-dd HH:mm}' -f $_.LastAccessTime}},
        @{N='Attr';E={"$($_.Attributes)"}} | Format-Table -AutoSize | Out-Host
}

function Invoke-Hashes {
    param($Results)
    Write-Host "MD5 + SHA256 (integrity / IOC matching):" -ForegroundColor Cyan; Write-Host ""
    foreach ($r in $Results) {
        $f = $r.File
        try {
            Write-Host $f.Name -ForegroundColor Cyan
            "    MD5    : $((Get-FileHash -LiteralPath $f.FullName -Algorithm MD5).Hash)"    | Write-Host
            "    SHA256 : $((Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash)" | Write-Host
        } catch { Write-Host "    (could not hash: $($_.Exception.Message))" -ForegroundColor Red }
    }
}

function Invoke-SignatureCheck {
    param($Results)
    Write-Host "Magic-byte signature vs extension (mismatch = possible disguise):" -ForegroundColor Cyan; Write-Host ""
    foreach ($r in $Results) {
        $f = $r.File; $sig = Get-FileSignatureInfo -File $f
        $flag  = if ($sig.Mismatch) { '   <-- EXTENSION MISMATCH' } else { '' }
        $color = if ($sig.Mismatch) { 'Yellow' } else { 'Gray' }
        Write-Host ("  {0,-32} {1}{2}" -f $f.Name, $sig.Type, $flag) -ForegroundColor $color
    }
}

function Invoke-Entropy {
    param($Results)
    Write-Host "Shannon entropy in bits/byte (>7.5 ~ encrypted / compressed / packed):" -ForegroundColor Cyan; Write-Host ""
    foreach ($r in $Results) {
        $f = $r.File; $e = Get-ShannonEntropy -File $f
        $note  = if ($e -ge 7.5) { 'high - encrypted/compressed?' } elseif ($e -ge 6.5) { 'elevated' } else { '' }
        $color = if ($e -ge 7.5) { 'Yellow' } else { 'Gray' }
        Write-Host ("  {0,6:N3}  {1,-32} {2}" -f $e, $f.Name, $note) -ForegroundColor $color
    }
}

function Invoke-HexDump {
    param($Results)
    Show-CompactList $Results
    $f = Select-OneFile $Results "Hex-dump which file #"
    if (-not $f) { return }
    $buf = Get-HeadBytes -File $f -Count 256
    if ($null -eq $buf) { Write-Host "Cannot read file." -ForegroundColor Red; return }
    Write-Host ""; Write-Host "First $($buf.Length) bytes of $($f.Name):" -ForegroundColor Cyan; Write-Host ""
    for ($off = 0; $off -lt $buf.Length; $off += 16) {
        $line = $buf[$off..([Math]::Min($off+15, $buf.Length-1))]
        $hex  = ($line | ForEach-Object { $_.ToString('X2') }) -join ' '
        $asc  = ($line | ForEach-Object { if ($_ -ge 32 -and $_ -le 126) { [char]$_ } else { '.' } }) -join ''
        "{0:X8}  {1,-47}  {2}" -f $off, $hex, $asc | Write-Host
    }
}

function Invoke-Strings {
    param($Results)
    Show-CompactList $Results
    $f = Select-OneFile $Results "Extract strings from file #"
    if (-not $f) { return }
    Write-Host ""; Write-Host "Printable strings (>=4 chars) in $($f.Name):" -ForegroundColor Cyan; Write-Host ""
    $strs = Get-PrintableStrings -File $f
    if ($strs.Count -eq 0) { Write-Host "  (none found)" -ForegroundColor DarkGray; return }
    $strs | ForEach-Object { "  $_" | Write-Host }
    Write-Host ""; Write-Host "Showing up to 200 strings (first 1 MB scanned)." -ForegroundColor DarkGray
}

function Invoke-Timeline {
    param($Results)
    Write-Host "Chronological timeline (by last modified):" -ForegroundColor Cyan; Write-Host ""
    $Results.File | Sort-Object LastWriteTime | ForEach-Object {
        "  {0:yyyy-MM-dd HH:mm:ss}  {1,10}  {2}" -f $_.LastWriteTime, (Format-Size $_.Length), $_.Name | Write-Host
    }
}

function Invoke-SizeAndType {
    param($Results)
    $files = $Results.File
    $total = ($files | Measure-Object Length -Sum).Sum
    Write-Host "Total: $(Format-Size $total) across $($files.Count) file(s)" -ForegroundColor Green; Write-Host ""
    Write-Host "Largest:" -ForegroundColor Cyan
    $files | Sort-Object Length -Descending | Select-Object -First 8 | ForEach-Object { "  {0,10}  {1}" -f (Format-Size $_.Length), $_.Name | Write-Host }
    Write-Host ""; Write-Host "By extension:" -ForegroundColor Cyan
    $files | Group-Object { if ($_.Extension) { $_.Extension.ToLower() } else { '(none)' } } | Sort-Object Count -Descending | ForEach-Object {
        $sz = ($_.Group | Measure-Object Length -Sum).Sum
        "  {0,-8} {1,4} file(s)  {2,12}" -f $_.Name, $_.Count, (Format-Size $sz) | Write-Host
    }
}

function Invoke-DuplicateDetection {
    param($Results)
    Write-Host "Hashing files (SHA256)..." -ForegroundColor DarkGray
    $groups = $Results.File | ForEach-Object {
        try { [pscustomobject]@{ Hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256 -ErrorAction Stop).Hash; File = $_ } } catch { }
    } | Group-Object Hash | Where-Object { $_.Count -gt 1 }
    if (-not $groups) { Write-Host "No duplicates found." -ForegroundColor Green; return }
    Write-Host "Duplicate groups:" -ForegroundColor Yellow
    foreach ($g in $groups) {
        Write-Host ("  {0} identical files, {1} each:" -f $g.Count, (Format-Size $g.Group[0].File.Length)) -ForegroundColor Yellow
        $g.Group | ForEach-Object { "      $($_.File.FullName)" | Write-Host }
    }
}

function Invoke-ContentSearch {
    param($Results)
    $term = Read-Host "Search inside these files for"
    if ([string]::IsNullOrWhiteSpace($term)) { return }
    Write-Host ""
    $hits = Select-String -LiteralPath $Results.File.FullName -Pattern ([regex]::Escape($term)) -List -ErrorAction SilentlyContinue
    if (-not $hits) { Write-Host "No matches for '$term'." -ForegroundColor Yellow; return }
    foreach ($h in $hits) { Write-Host $h.Path -ForegroundColor Cyan; "    line $($h.LineNumber): $($h.Line.Trim())" | Write-Host }
    Write-Host ""; Write-Host "$($hits.Count) file(s) contain '$term'." -ForegroundColor Green
}

function Invoke-ExportReport {
    param($Results)
    $stamp = Join-Path $Path ("forensic-report-{0:yyyyMMdd-HHmmss}" -f (Get-Date))
    Write-Host "Building evidence report (hashes + metadata + signatures)..." -ForegroundColor DarkGray
    $rows = foreach ($r in $Results) {
        $f = $r.File; $md5=''; $sha=''
        try { $md5 = (Get-FileHash -LiteralPath $f.FullName -Algorithm MD5).Hash } catch { }
        try { $sha = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash } catch { }
        $sig = Get-FileSignatureInfo -File $f
        [pscustomobject]@{
            Name=$f.Name; FullName=$f.FullName; Bytes=$f.Length
            Created=$f.CreationTime; Modified=$f.LastWriteTime; Accessed=$f.LastAccessTime
            Attributes="$($f.Attributes)"; MatchedBy=$r.Match
            Signature=$sig.Type; ExtMismatch=$sig.Mismatch; MD5=$md5; SHA256=$sha
        }
    }
    $csv = "$stamp.csv"; $json = "$stamp.json"
    $rows | Export-Csv -LiteralPath $csv -NoTypeInformation -Encoding UTF8
    $rows | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $json -Encoding UTF8
    Write-Host ""; Write-Host "Wrote:" -ForegroundColor Green; Write-Host "  $csv"; Write-Host "  $json"
}

# Build the move plan and either preview (dry run) or carry it out.
function Invoke-Restructure {
    param($Results, [switch]$DryRun)
    $target = Join-Path -Path $Path -ChildPath $Keyword
    if ($DryRun) { Write-Host "DRY RUN - nothing will be moved." -ForegroundColor Yellow }
    Write-Host "Target folder: $target" -ForegroundColor Cyan; Write-Host ""
    $targetFull = if (Test-Path -LiteralPath $target) { (Resolve-Path -LiteralPath $target).Path } else { $target }

    $plan = New-Object System.Collections.Generic.List[object]; $used = @{}
    foreach ($r in $Results) {
        $f = $r.File
        if ($f.DirectoryName -eq $targetFull) { continue }
        $dest = Join-Path $target $f.Name
        if ((Test-Path -LiteralPath $dest) -or $used.ContainsKey($dest.ToLower())) {
            $base = [IO.Path]::GetFileNameWithoutExtension($f.Name); $ext = [IO.Path]::GetExtension($f.Name); $n = 1
            do { $dest = Join-Path $target ("{0} ({1}){2}" -f $base, $n, $ext); $n++ }
            while ((Test-Path -LiteralPath $dest) -or $used.ContainsKey($dest.ToLower()))
        }
        $used[$dest.ToLower()] = $true
        $plan.Add([pscustomobject]@{ From = $f.FullName; To = $dest })
    }
    if ($plan.Count -eq 0) { Write-Host "Nothing to move (all matches already in the target folder)." -ForegroundColor Yellow; return }

    foreach ($p in $plan) { "  $($p.From)" | Write-Host; "    -> $($p.To)" | Write-Host -ForegroundColor DarkGray }
    Write-Host ""; Write-Host "$($plan.Count) file(s) would be moved." -ForegroundColor Green
    if ($DryRun) { return }

    if ((Read-Key "Proceed with moving these files? (y/n) ") -ne 'y') { Write-Host "Cancelled - no changes made." -ForegroundColor Yellow; return }
    if (-not (Test-Path -LiteralPath $target)) { New-Item -ItemType Directory -Path $target | Out-Null; Write-Host "Created folder: $target" -ForegroundColor Green }
    $moved = 0
    foreach ($p in $plan) {
        try { Move-Item -LiteralPath $p.From -Destination $p.To -ErrorAction Stop; $moved++ }
        catch { Write-Host "Failed: $($p.From) - $($_.Exception.Message)" -ForegroundColor Red }
    }
    Write-Host ""; Write-Host "Done. Moved $moved file(s) into '$target'." -ForegroundColor Green
    Write-Host "(Re-run the search to keep analyzing the moved files.)" -ForegroundColor DarkGray
}

# ===========================================================================
# Navigable menu engine (arrow keys + letter shortcuts; numbered fallback)
# ===========================================================================

function Start-ForensicMenu {
    param($Items, [string]$Title)

    $raw = $true
    try { $null = [System.Console]::KeyAvailable } catch { $raw = $false }
    $sel = 0

    while ($true) {
        if ($raw) {
            Clear-Host
            Write-Host $Title -ForegroundColor Cyan
            Write-Host ('=' * $Title.Length) -ForegroundColor Cyan
            Write-Host ""
            for ($i = 0; $i -lt $Items.Count; $i++) {
                $it = $Items[$i]; $line = " [{0}] {1}" -f $it.Key, $it.Label
                if ($i -eq $sel) { Write-Host (">" + $line) -ForegroundColor Black -BackgroundColor Cyan }
                else            { Write-Host (" " + $line) }
            }
            Write-Host ""
            Write-Host " Up/Down move   Enter run   press a letter   Q quit" -ForegroundColor DarkGray

            $key = [System.Console]::ReadKey($true); $act = $null
            switch ($key.Key) {
                'UpArrow'   { $sel = ($sel - 1 + $Items.Count) % $Items.Count }
                'DownArrow' { $sel = ($sel + 1) % $Items.Count }
                'Enter'     { $act = $Items[$sel] }
                'Escape'    { return }
                default {
                    $ch = "$($key.KeyChar)".ToLower()
                    $hit = $Items | Where-Object { $_.Key.ToLower() -eq $ch } | Select-Object -First 1
                    if ($hit) { $act = $hit; $sel = [array]::IndexOf($Items, $hit) }
                }
            }
            if ($act) {
                Clear-Host
                Write-Host (">> {0}" -f $act.Label) -ForegroundColor Cyan; Write-Host ""
                if ((& $act.Action) -eq 'quit') { return }
                Write-Host ""; Write-Host "Press any key to return to the menu..." -ForegroundColor DarkGray
                $null = [System.Console]::ReadKey($true)
            }
        }
        else {
            Write-Host ""; Write-Host $Title -ForegroundColor Cyan
            for ($i = 0; $i -lt $Items.Count; $i++) { "  {0,2}) [{1}] {2}" -f ($i+1), $Items[$i].Key, $Items[$i].Label | Write-Host }
            $s = (Read-Host "Select number or letter").Trim(); $hit = $null; [int]$num = 0
            if ([int]::TryParse($s, [ref]$num) -and $num -ge 1 -and $num -le $Items.Count) { $hit = $Items[$num-1] }
            else { $hit = $Items | Where-Object { $_.Key.ToLower() -eq $s.ToLower() } | Select-Object -First 1 }
            if ($hit) { Write-Host ""; if ((& $hit.Action) -eq 'quit') { return } }
            else { Write-Host "Unknown selection." -ForegroundColor Yellow }
        }
    }
}

# ===========================================================================
# Wire up the menu and launch
# ===========================================================================

$menuItems = @(
    @{ Key='L'; Label='List matches (full paths)';                  Action={ Show-Results          -Results $results } }
    @{ Key='I'; Label='Metadata  (MAC timestamps, size, attrs)';    Action={ Invoke-Metadata       -Results $results } }
    @{ Key='H'; Label='Hashes  (MD5 + SHA256)';                     Action={ Invoke-Hashes         -Results $results } }
    @{ Key='G'; Label='Signature check  (magic bytes vs extension)';Action={ Invoke-SignatureCheck -Results $results } }
    @{ Key='E'; Label='Entropy  (spot encrypted / packed files)';   Action={ Invoke-Entropy        -Results $results } }
    @{ Key='X'; Label='Hex header dump  (pick a file)';             Action={ Invoke-HexDump        -Results $results } }
    @{ Key='S'; Label='Strings extraction  (pick a file)';          Action={ Invoke-Strings        -Results $results } }
    @{ Key='T'; Label='Timeline  (chronological by mtime)';         Action={ Invoke-Timeline       -Results $results } }
    @{ Key='Z'; Label='Size & type breakdown';                      Action={ Invoke-SizeAndType    -Results $results } }
    @{ Key='D'; Label='Duplicate scan  (identical by hash)';        Action={ Invoke-DuplicateDetection -Results $results } }
    @{ Key='C'; Label='Content search  (grep inside matches)';      Action={ Invoke-ContentSearch  -Results $results } }
    @{ Key='R'; Label='Export evidence report  (CSV + JSON)';       Action={ Invoke-ExportReport   -Results $results } }
    @{ Key='P'; Label='Preview restructure  (dry run)';             Action={ Invoke-Restructure    -Results $results -DryRun } }
    @{ Key='M'; Label="Restructure  (move into '$Keyword' folder)"; Action={ Invoke-Restructure    -Results $results } }
    @{ Key='Q'; Label='Quit';                                       Action={ 'quit' } }
)

Start-ForensicMenu -Items $menuItems -Title "Forensic toolkit - $($results.Count) match(es) for '$Keyword'"
