# Digital Footprint Scanner

Scan the web for **your own** identifiers — name, emails, phone, usernames — to
see where your data shows up, then use the included opt-out links to request
removal from data brokers. Run it periodically; each report flags anything
**new since your last run**.

> Intended for checking your own information and accounts you control, to
> support privacy / data-removal requests. Built-in checks are best-effort and
> can return false positives or be blocked by anti-bot measures — confirm before
> acting.

---

## What it checks

| Area | How |
|------|-----|
| **Usernames / profiles** | Built-in checks across ~20 sites, plus **Sherlock** and **Maigret** (hundreds of sites) when installed. |
| **Email accounts** | **holehe** — which sites an address is registered on. |
| **Breaches** | **HaveIBeenPwned** (needs a free-tier API key). |
| **Data brokers** | ~24 major people-search/broker sites with a direct **opt-out link** each, and an optional best-effort presence probe. |
| **Search lookups** | Ready-to-click Google / Bing / DuckDuckGo queries for your name, email, phone, and handles. |
| **Change tracking** | Each run is saved and diffed against the previous one; new findings are highlighted. |

Reports (HTML + JSON) are written to **`Desktop\digital footprint\`**, plus a
`latest.html` that always points at the newest one. OneDrive-redirected
Desktops (e.g. `C:\Users\you\OneDrive\Desktop`) are detected automatically; set
`output_dir` in `config.json` to force a specific folder.

---

## Setup

**1. Install Python** (3.8+) from <https://www.python.org/downloads/> — tick
*"Add python.exe to PATH"*.

**2. Install the OSINT tools** (once):

```powershell
.\Install-Footprint-Tools.ps1
```

This installs Sherlock, Maigret, and holehe via `pipx`. The scanner still works
without them (using built-in checks), just less exhaustively.

**3. (Optional) HaveIBeenPwned key** for breach checks: get one at
<https://haveibeenpwned.com/API/Key> and paste it into `config.json` under
`hibp_api_key`.

---

## Run it

**Double-click** `Launch-DigitalFootprint.cmd` (or run `python footprint.py`).

- **First run** creates `config.json` from the template and stops — open it,
  fill in your details, and run again.
- Or put it on your Desktop with a shortcut:

  ```powershell
  .\Deploy-DigitalFootprint.ps1
  ```

Handy flags:

```powershell
python footprint.py --quick   # skip slow Maigret + broker probing
python footprint.py --open    # open the HTML report when done
```

---

## config.json

```jsonc
{
  "name": { "first": "Jane", "last": "Doe", "full": "" },  // full optional; built from first+last
  "emails": ["jane.doe@example.com"],
  "phones": ["+1 555 123 4567"],
  "usernames": ["janedoe", "jdoe"],
  "location": { "city": "Austin", "state": "TX", "country": "US" },
  "hibp_api_key": "",          // optional, enables breach checks
  "output_dir": "",            // blank = Desktop\digital footprint
  "tools": { "sherlock": true, "maigret": false, "holehe": true },
  "probe_brokers": true,       // best-effort "do I appear on this broker?" check
  "timeout": 12
}
```

- **`maigret`** is off by default (it's thorough but slow); turn it on when you
  want a deeper sweep.
- **`probe_brokers`** uses DuckDuckGo to guess whether you appear on each broker.
  It's best-effort and can be rate-limited — treat hits as "worth verifying,"
  not proof.

---

## Requesting removal

For each broker in the report, click **Opt out** and follow its process (many
ask you to find your listing, then submit a removal form or email). Removals can
take days to weeks and sometimes reappear — that's why re-running periodically
and watching the **New since last run** section is the whole point.

---

## Notes & limits

- Opt-out URLs change over time; if one 404s, search that site for "opt out" or
  "privacy."
- Username/email tools query public endpoints; some sites block automated
  requests, so absence in a report isn't a guarantee.
- This reads public sources only. It does not log in to anything, and it's for
  your own footprint — not for looking people up.
