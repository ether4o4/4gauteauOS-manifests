# Keyword Forensic Toolkit (`Restructure-ByKeyword.ps1`)

Find every file matching a keyword anywhere under a folder, then run a small
**navigable forensic extraction/analysis menu** over the matches — or
**restructure** them into a folder named exactly after the keyword.

---

## Files

| File | What it is |
|------|------------|
| `Restructure-ByKeyword.ps1` | The tool itself (search + forensic menu + restructure). |
| `Launch-ForensicToolkit.cmd` | Double-clickable launcher (no command line needed). |
| `Deploy-ToDesktop.ps1` | Copies the toolkit to your Desktop + makes a clickable shortcut. |
| `Install-Shortcut.ps1` | Wires the tool into your PowerShell profile as `restruct` / `fkr`. |
| `Restructure-ByKeyword.md` | This guide. |

---

## Put it on your Desktop (double-click to launch)

**Easiest:** with all the toolkit files in one folder, run this once:

```powershell
.\Deploy-ToDesktop.ps1
```

It copies the toolkit into `Desktop\Keyword Forensic Toolkit\` and drops a
**"Keyword Forensic Toolkit"** shortcut on your Desktop. Double-click it and the
toolkit opens in a console window — it asks which folder to search (default:
your Desktop), then drops you into the menu.

> You can also **drag any folder onto the shortcut** to search that folder.

**Manual alternative:** copy `Restructure-ByKeyword.ps1` and
`Launch-ForensicToolkit.cmd` (keep them together) anywhere you like — e.g. your
Desktop — and double-click `Launch-ForensicToolkit.cmd`. The `.cmd` already runs
PowerShell with the execution policy bypassed, so there's nothing else to set
up.

---

## Quick start

```powershell
# From the folder containing the script:
.\Restructure-ByKeyword.ps1                      # prompts for a keyword, searches current folder
.\Restructure-ByKeyword.ps1 -Keyword "ghost key"
.\Restructure-ByKeyword.ps1 -Keyword "ghost key" -Path "C:\Evidence"
.\Restructure-ByKeyword.ps1 -Keyword "ghost key" -IncludeContent   # also search inside files
```

If Windows blocks scripts, allow them once (per user, recommended):

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
# ...or, just for the current window:
Set-ExecutionPolicy -Scope Process Bypass
```

---

## Install as a shell shortcut

Run the installer once. It adds a small, clearly-marked block to your
PowerShell profile so you can call the tool from **any** folder:

```powershell
.\Install-Shortcut.ps1        # install
. $PROFILE                    # reload the profile (or just open a new window)

restruct "ghost key"          # now works anywhere
fkr "ghost key" -IncludeContent
```

To remove it again:

```powershell
.\Install-Shortcut.ps1 -Uninstall
```

`restruct` and `fkr` are aliases for the same command and accept all the same
parameters (`-Keyword`, `-Path`, `-IncludeContent`, `-MaxContentSizeMB`).

---

## How matching works

The keyword is split on spaces; **each** word must appear in the file name, in
**any order** and ignoring separators. So `"ghost key"` matches all of:

```
ghostkey.txt   ghost.key   ghost_key.png   ghost-key.doc   ghost key.pdf   key ghost.zip
```

- By default it matches **file names**. Add `-IncludeContent` to also match
  files whose **text** contains all the words (skips files larger than
  `-MaxContentSizeMB`, default 50 MB).
- Matching is intentionally loose substring matching, so `key` also matches
  `keyboard` / `monkey`. That's why nothing is moved until you confirm — review
  the list first. In the listing, `[N]` = matched by name, `[C]` = by content.

---

## The forensic menu

After the search, you land in a navigable menu. **Up/Down** to move,
**Enter** to run the highlighted item, or just press its **letter**. **Q**
quits. (On hosts without raw-key support, e.g. the ISE, it falls back to a
numbered prompt.)

| Key | Tool | What it does |
|-----|------|--------------|
| **L** | List matches | Re-print the full match list with paths. |
| **I** | Metadata | MAC timestamps (Created/Modified/Accessed), size, attributes. |
| **H** | Hashes | MD5 + SHA256 per file — integrity / IOC matching. |
| **G** | Signature check | Magic bytes vs. extension; flags disguised/renamed files. |
| **E** | Entropy | Shannon entropy (bits/byte); >7.5 ≈ encrypted/compressed/packed. |
| **X** | Hex header dump | Classic offset/hex/ASCII dump of a chosen file's first 256 bytes. |
| **S** | Strings extraction | Printable ASCII strings (≥4 chars) from a chosen file. |
| **T** | Timeline | Chronological listing by last-modified time. |
| **Z** | Size & type | Totals, largest files, and a per-extension breakdown. |
| **D** | Duplicate scan | Groups byte-for-byte identical files by SHA256. |
| **C** | Content search | Grep for a literal term inside the matched files. |
| **R** | Export report | Writes `forensic-report-<timestamp>.csv` + `.json` (metadata, hashes, signatures). |
| **P** | Preview restructure | **Dry run** — shows exactly what would move where, no changes. |
| **M** | Restructure | Moves matches into a folder named exactly the keyword (after a confirm). |
| **Q** | Quit | Exit the menu. |

### Restructure / preview

- **Preview (P)** prints the full move plan (`source -> destination`) and makes
  **no changes** — use it to sanity-check before committing.
- **Restructure (M)** runs the same plan, asks `y/n`, then moves the files into
  a new folder named exactly your keyword. Name collisions are auto-suffixed
  `(1)`, `(2)`, … so nothing is ever overwritten, and files already in the
  target folder are skipped.

---

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-Keyword` | *(prompted)* | Words to search for, e.g. `"ghost key"`. |
| `-Path` | current directory | Root folder to search (recursive). |
| `-IncludeContent` | off | Also match files whose text content contains all the words. |
| `-MaxContentSizeMB` | `50` | Skip files larger than this when reading content. |

---

## Notes & caveats

- **Read-only by design** except for **Restructure (M)**. Every analysis tool
  only reads; the only thing that moves files is `M`, and only after you
  confirm.
- Hashing and content/entropy scans read file bytes, so large match sets can
  take a moment. Entropy/strings sample the first 256 KB / 1 MB respectively
  for speed.
- This is a triage/educational toolkit, not a court-grade acquisition tool — it
  reads live files in place (which updates the Accessed time) rather than
  working from a write-blocked image.
