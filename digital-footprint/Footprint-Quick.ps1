<#
  Footprint-Quick.ps1  -  the simple, no-install version.

  Double-click Footprint-Quick.cmd. Type your details once (they're remembered).
  It opens an HTML report in your browser with:
    - ready-to-click web searches for your name / email / phone / handles
    - profile links to check on the big social sites
    - data-broker rows with a one-click OPT OUT button each

  No Python, no installs, no API keys. Reports save to your Desktop
  "digital footprint" folder (OneDrive Desktops handled automatically).
#>

# --- Helpers ---------------------------------------------------------------

function Esc([string]$s) { [System.Net.WebUtility]::HtmlEncode($s) }

function A([string]$url, [string]$text) {
    "<a href='$(Esc $url)' target='_blank' rel='noopener'>$(Esc $text)</a>"
}

function Enc([string]$s) { [uri]::EscapeDataString($s) }

function Read-List([string]$prompt) {
    $v = Read-Host $prompt
    if ([string]::IsNullOrWhiteSpace($v)) { return @() }
    return @($v -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

# --- Output folder (GetFolderPath handles OneDrive-redirected Desktops) -----

$desktop = [Environment]::GetFolderPath('Desktop')
$outDir  = Join-Path $desktop 'digital footprint'
New-Item -ItemType Directory -Path $outDir -Force | Out-Null
$profilePath = Join-Path $outDir 'profile.json'

# --- Load or collect your details ------------------------------------------

$me = $null
if (Test-Path -LiteralPath $profilePath) {
    try { $me = Get-Content -LiteralPath $profilePath -Raw | ConvertFrom-Json } catch { $me = $null }
}

if ($me) {
    Write-Host ""
    Write-Host "Saved profile:" -ForegroundColor Cyan
    Write-Host "  Name     : $($me.name)"
    Write-Host "  Location : $($me.city) $($me.state)"
    Write-Host "  Emails   : $(@($me.emails) -join ', ')"
    Write-Host "  Phones   : $(@($me.phones) -join ', ')"
    Write-Host "  Usernames: $(@($me.usernames) -join ', ')"
    $ans = Read-Host "Use this profile? (Y/n)"
    if ($ans.Trim().ToLower() -eq 'n') { $me = $null }
}

if (-not $me) {
    Write-Host ""
    Write-Host "Enter your details. Separate multiples with commas; leave blank to skip." -ForegroundColor Cyan
    $name      = Read-Host "Full name"
    $city      = Read-Host "City"
    $state     = Read-Host "State/Region"
    $emails    = Read-List "Email(s)"
    $phones    = Read-List "Phone(s)"
    $usernames = Read-List "Username/handle(s)"
    $me = [pscustomobject]@{
        name = $name; city = $city; state = $state
        emails = $emails; phones = $phones; usernames = $usernames
    }
    $me | ConvertTo-Json | Set-Content -LiteralPath $profilePath -Encoding UTF8
    Write-Host "Saved (so next time is instant): $profilePath" -ForegroundColor Green
}

# --- Reference data --------------------------------------------------------

$userSites = @(
    @{ name = 'Instagram';   url = 'https://www.instagram.com/{u}/' }
    @{ name = 'Facebook';    url = 'https://www.facebook.com/{u}' }
    @{ name = 'X / Twitter'; url = 'https://x.com/{u}' }
    @{ name = 'TikTok';      url = 'https://www.tiktok.com/@{u}' }
    @{ name = 'YouTube';     url = 'https://www.youtube.com/@{u}' }
    @{ name = 'Reddit';      url = 'https://www.reddit.com/user/{u}' }
    @{ name = 'GitHub';      url = 'https://github.com/{u}' }
    @{ name = 'LinkedIn';    url = 'https://www.linkedin.com/in/{u}' }
    @{ name = 'Pinterest';   url = 'https://www.pinterest.com/{u}/' }
    @{ name = 'Snapchat';    url = 'https://www.snapchat.com/add/{u}' }
    @{ name = 'Twitch';      url = 'https://www.twitch.tv/{u}' }
    @{ name = 'Telegram';    url = 'https://t.me/{u}' }
    @{ name = 'Medium';      url = 'https://medium.com/@{u}' }
    @{ name = 'SoundCloud';  url = 'https://soundcloud.com/{u}' }
    @{ name = 'Steam';       url = 'https://steamcommunity.com/id/{u}' }
    @{ name = 'Venmo';       url = 'https://venmo.com/u/{u}' }
)

$brokers = @(
    @{ n = 'Spokeo';                   d = 'spokeo.com';                   o = 'https://www.spokeo.com/optout' }
    @{ n = 'Whitepages';               d = 'whitepages.com';               o = 'https://www.whitepages.com/suppression-requests' }
    @{ n = 'BeenVerified';             d = 'beenverified.com';             o = 'https://www.beenverified.com/app/optout/search' }
    @{ n = 'Intelius';                 d = 'intelius.com';                 o = 'https://www.intelius.com/opt-out/' }
    @{ n = 'PeopleFinders';            d = 'peoplefinders.com';            o = 'https://www.peoplefinders.com/opt-out' }
    @{ n = 'TruePeopleSearch';         d = 'truepeoplesearch.com';         o = 'https://www.truepeoplesearch.com/removal' }
    @{ n = 'FastPeopleSearch';         d = 'fastpeoplesearch.com';         o = 'https://www.fastpeoplesearch.com/removal' }
    @{ n = 'Radaris';                  d = 'radaris.com';                  o = 'https://radaris.com/control/privacy' }
    @{ n = 'MyLife';                   d = 'mylife.com';                   o = 'https://www.mylife.com/ccpa/index.pubview' }
    @{ n = 'PeekYou';                  d = 'peekyou.com';                  o = 'https://www.peekyou.com/about/contact/optout/' }
    @{ n = 'US Search';                d = 'ussearch.com';                 o = 'https://www.ussearch.com/opt-out/' }
    @{ n = 'Instant Checkmate';        d = 'instantcheckmate.com';         o = 'https://www.instantcheckmate.com/opt-out/' }
    @{ n = 'TruthFinder';              d = 'truthfinder.com';              o = 'https://www.truthfinder.com/opt-out/' }
    @{ n = 'Nuwber';                   d = 'nuwber.com';                   o = 'https://nuwber.com/removal/link' }
    @{ n = 'ClustrMaps';               d = 'clustrmaps.com';               o = 'https://clustrmaps.com/bl/opt-out' }
    @{ n = 'AdvancedBackgroundChecks'; d = 'advancedbackgroundchecks.com'; o = 'https://www.advancedbackgroundchecks.com/removal' }
    @{ n = 'CheckPeople';              d = 'checkpeople.com';              o = 'https://www.checkpeople.com/opt-out' }
    @{ n = 'FamilyTreeNow';            d = 'familytreenow.com';            o = 'https://www.familytreenow.com/optout' }
    @{ n = 'SearchPeopleFree';         d = 'searchpeoplefree.com';         o = 'https://www.searchpeoplefree.com/opt-out' }
    @{ n = 'ThatsThem';                d = 'thatsthem.com';                o = 'https://thatsthem.com/optout' }
)

# --- Build the report ------------------------------------------------------

$searchRows = New-Object System.Collections.Generic.List[string]
function Add-Search([string]$label, [string]$query) {
    $q = Enc $query
    $g = A "https://www.google.com/search?q=$q" 'Google'
    $b = A "https://www.bing.com/search?q=$q" 'Bing'
    $d = A "https://duckduckgo.com/?q=$q" 'DuckDuckGo'
    $script:searchRows.Add("<tr><td>$(Esc $label)</td><td>$g &middot; $b &middot; $d</td></tr>")
}

if ($me.name) {
    $q = '"' + $me.name + '"'
    $lbl = 'Name'
    if ($me.city) { $q += ' "' + $me.city + '"'; $lbl = 'Name + city' }
    Add-Search $lbl $q
}
foreach ($e in @($me.emails    | Where-Object { $_ })) { Add-Search "Email: $e"    ('"' + $e + '"') }
foreach ($p in @($me.phones    | Where-Object { $_ })) { Add-Search "Phone: $p"    ('"' + $p + '"') }
foreach ($u in @($me.usernames | Where-Object { $_ })) { Add-Search "Username: $u" ('"' + $u + '"') }

$profileBlocks = New-Object System.Collections.Generic.List[string]
foreach ($u in @($me.usernames | Where-Object { $_ })) {
    $enc = Enc $u
    $links = foreach ($s in $userSites) { A ($s.url.Replace('{u}', $enc)) $s.name }
    $profileBlocks.Add("<div class='card'><b>@$(Esc $u)</b><div class='links'>$([string]::Join(' &middot; ', $links))</div></div>")
}

$brokerRows = New-Object System.Collections.Generic.List[string]
foreach ($b in $brokers) {
    $dork = 'site:' + $b.d + ' "' + $me.name + '"'
    if ($me.city) { $dork += ' "' + $me.city + '"' }
    $search = "https://duckduckgo.com/?q=$(Enc $dork)"
    $optout = "<a class='optout' href='$(Esc $b.o)' target='_blank' rel='noopener'>Opt out</a>"
    $brokerRows.Add("<tr><td>$(Esc $b.n)<div class='muted'>$(Esc $b.d)</div></td><td>$(A $search 'search for me')</td><td>$optout</td></tr>")
}

$css = @"
body{font-family:'Segoe UI',Arial,sans-serif;margin:0;background:#0f1115;color:#e7e7ea}
.wrap{max-width:920px;margin:0 auto;padding:26px}
h1{font-size:23px;margin:0 0 2px}h2{font-size:18px;margin:26px 0 10px;border-bottom:1px solid #2a2e37;padding-bottom:6px}
.sub{color:#9aa0aa;font-size:13px;margin-bottom:14px}
.tip{background:#161a21;border:1px solid #242833;border-radius:10px;padding:12px 14px;color:#c8ccd4;font-size:14px}
.card{background:#161a21;border:1px solid #242833;border-radius:10px;padding:12px 14px;margin:8px 0}
.links{margin-top:4px}
a{color:#7db5ff;text-decoration:none}a:hover{text-decoration:underline}
table{width:100%;border-collapse:collapse;font-size:14px}
th,td{text-align:left;padding:7px 8px;border-bottom:1px solid #242833;vertical-align:top}
.optout{display:inline-block;background:#1f6feb;color:#fff;border-radius:6px;padding:3px 12px}
.optout:hover{background:#2a7bff;text-decoration:none}
.muted{color:#8a8f99;font-size:12px}
.foot{margin-top:28px;color:#7a7f88;font-size:12px;border-top:1px solid #242833;padding-top:14px}
"@

$generated = Get-Date -Format 'yyyy-MM-dd HH:mm'
$html = @"
<!doctype html><html><head><meta charset='utf-8'>
<meta name='viewport' content='width=device-width,initial-scale=1'>
<title>Digital Footprint</title><style>$css</style></head><body><div class='wrap'>
<h1>Digital Footprint</h1>
<div class='sub'>$(Esc $me.name) &middot; generated $generated</div>
<div class='tip'><b>How to use:</b> click the searches to see where you show up, then use the blue
<b>Opt out</b> buttons to ask each data broker to remove you. Re-run any time to re-check.</div>

<h2>Web searches</h2>
<table><tr><th>Look up</th><th>Run on</th></tr>
$([string]::Join("`n", $searchRows))
</table>

<h2>Profiles to check</h2>
$(if ($profileBlocks.Count) { [string]::Join("`n", $profileBlocks) } else { "<div class='muted'>No usernames entered.</div>" })

<h2>Data brokers &mdash; request removal</h2>
<div class='muted'>Opt-out links can change; if one 404s, search that site for &quot;opt out&quot;.</div>
<table><tr><th>Site</th><th>Find me</th><th>Remove me</th></tr>
$([string]::Join("`n", $brokerRows))
</table>

<div class='foot'>For checking your own information to support privacy / removal requests.</div>
</div></body></html>
"@

$stamp  = Get-Date -Format 'yyyyMMdd-HHmmss'
$report = Join-Path $outDir "footprint-quick-$stamp.html"
$html | Set-Content -LiteralPath $report -Encoding UTF8

Write-Host ""
Write-Host "Report saved: $report" -ForegroundColor Green
Write-Host "Opening it in your browser..." -ForegroundColor Cyan
Start-Process $report
