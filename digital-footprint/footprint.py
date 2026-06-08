#!/usr/bin/env python3
"""
Digital Footprint Scanner
=========================
Search the web for YOUR OWN identifiers (name, emails, phone, usernames) so you
can see where your data shows up and request removal from data brokers.

This is intended for checking your own information and accounts you control, to
support privacy / opt-out requests. It orchestrates optional open-source OSINT
tools (Sherlock, Maigret, holehe) when they are installed, adds a few built-in
checks, and writes a timestamped HTML + JSON report to your "digital footprint"
folder, flagging anything NEW since the previous run.

Usage:
    python footprint.py                 # uses ./config.json (creates it on first run)
    python footprint.py --quick         # skip slow tools (maigret) and broker probing
    python footprint.py --open          # open the HTML report when finished
"""

import argparse
import html
import json
import os
import re
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime

HERE = os.path.dirname(os.path.abspath(__file__))
UA = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/124.0 Safari/537.36")
ANSI = re.compile(r"\x1b\[[0-9;]*m")


# --------------------------------------------------------------------------
# Small helpers
# --------------------------------------------------------------------------

def strip_ansi(s):
    return ANSI.sub("", s or "")


def default_output_dir():
    return os.path.join(os.path.expanduser("~"), "Desktop", "digital footprint")


def load_json(path, default=None):
    if not os.path.exists(path):
        return default
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except json.JSONDecodeError as e:
        print("[!] %s is not valid JSON: %s" % (path, e))
        sys.exit(1)


def http_get(url, timeout=12):
    req = urllib.request.Request(
        url, headers={"User-Agent": UA, "Accept-Language": "en-US,en;q=0.9"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            body = resp.read(300000).decode("utf-8", "ignore")
            return resp.getcode(), body
    except urllib.error.HTTPError as e:
        return e.code, ""
    except Exception:
        return None, ""


def host_of(url):
    try:
        h = urllib.parse.urlparse(url).netloc.lower()
        return h[4:] if h.startswith("www.") else h
    except Exception:
        return url


def have(tool):
    return shutil.which(tool) is not None


# --------------------------------------------------------------------------
# Username checks  (built-in best-effort + Sherlock / Maigret)
# --------------------------------------------------------------------------

def check_username_site(site, username, timeout):
    url = site["url"].format(u=urllib.parse.quote(username))
    status, body = http_get(url, timeout)
    found = False
    if status == 200:
        low = body.lower()
        if "absent_text" in site:
            found = site["absent_text"].lower() not in low
        elif "present_text" in site:
            found = site["present_text"].lower() in low
        else:
            found = True
    return site["name"], url, found


def builtin_username_scan(username, sites, timeout, workers=20):
    hits = []
    with ThreadPoolExecutor(max_workers=workers) as ex:
        futs = [ex.submit(check_username_site, s, username, timeout) for s in sites]
        for f in as_completed(futs):
            name, url, found = f.result()
            if found:
                hits.append({"site": name, "url": url})
    return sorted(hits, key=lambda x: x["site"].lower())


def _parse_found_urls(text):
    urls = []
    for line in strip_ansi(text).splitlines():
        if "[+]" in line:
            m = re.search(r"(https?://\S+)", line)
            if m:
                urls.append(m.group(1).rstrip(").,"))
    # de-dupe, keep order
    seen, out = set(), []
    for u in urls:
        if u not in seen:
            seen.add(u)
            out.append(u)
    return out


def run_sherlock(username, timeout):
    if not have("sherlock"):
        return None
    try:
        p = subprocess.run(["sherlock", username, "--timeout", "10"],
                           capture_output=True, text=True, timeout=max(120, timeout * 25))
        return _parse_found_urls(p.stdout)
    except Exception:
        return []


def run_maigret(username, timeout):
    if not have("maigret"):
        return None
    try:
        p = subprocess.run(["maigret", username, "--timeout", "10"],
                           capture_output=True, text=True, timeout=max(240, timeout * 45))
        return _parse_found_urls(p.stdout)
    except Exception:
        return []


# --------------------------------------------------------------------------
# Email checks  (holehe + HaveIBeenPwned)
# --------------------------------------------------------------------------

def run_holehe(email, timeout):
    if not have("holehe"):
        return None
    try:
        p = subprocess.run(["holehe", email, "--only-used"],
                           capture_output=True, text=True, timeout=max(120, timeout * 25))
        sites = []
        for line in strip_ansi(p.stdout).splitlines():
            line = line.strip()
            if line.startswith("[+]"):
                sites.append(line[3:].strip())
        return sorted(set(sites))
    except Exception:
        return []


def check_hibp(email, api_key, timeout):
    if not api_key:
        return None
    url = ("https://haveibeenpwned.com/api/v3/breachedaccount/"
           + urllib.parse.quote(email) + "?truncateResponse=false")
    req = urllib.request.Request(
        url, headers={"hibp-api-key": api_key, "User-Agent": "DigitalFootprintScanner"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return json.loads(r.read().decode("utf-8", "ignore"))
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return []                      # no breaches for this address
        return {"error": "HTTP %s" % e.code}
    except Exception as e:
        return {"error": str(e)}


# --------------------------------------------------------------------------
# Data brokers
# --------------------------------------------------------------------------

def probe_broker(domain, full_name, timeout):
    q = 'site:%s "%s"' % (domain, full_name)
    url = "https://html.duckduckgo.com/html/?q=" + urllib.parse.quote(q)
    status, body = http_get(url, timeout)
    if status == 200 and domain.lower() in body.lower():
        return "possible match"
    if status == 200:
        return "no result"
    return "check manually"


def scan_brokers(brokers, full_name, city, probe, timeout):
    out = []
    for b in brokers:
        dork = 'site:%s "%s"' % (b["domain"], full_name)
        if city:
            dork += ' "%s"' % city
        rec = {
            "name": b["name"],
            "domain": b["domain"],
            "optout_url": b.get("optout_url", ""),
            "notes": b.get("notes", ""),
            "search_url": "https://duckduckgo.com/?q=" + urllib.parse.quote(dork),
            "status": "not probed",
        }
        if probe and full_name:
            rec["status"] = probe_broker(b["domain"], full_name, timeout)
            time.sleep(0.5)
        out.append(rec)
    return out


# --------------------------------------------------------------------------
# Search-engine dorks
# --------------------------------------------------------------------------

def build_dorks(cfg):
    dorks = []

    def add(label, q):
        dorks.append({
            "label": label,
            "google": "https://www.google.com/search?q=" + urllib.parse.quote(q),
            "bing": "https://www.bing.com/search?q=" + urllib.parse.quote(q),
            "ddg": "https://duckduckgo.com/?q=" + urllib.parse.quote(q),
        })

    full = cfg["_full_name"]
    city = cfg.get("location", {}).get("city", "")
    if full:
        q = '"%s"' % full + (' "%s"' % city if city else "")
        add("Name" + (" + city" if city else ""), q)
    for e in cfg.get("emails", []):
        add("Email: " + e, '"%s"' % e)
    for ph in cfg.get("phones", []):
        add("Phone: " + ph, '"%s"' % ph)
    for u in cfg.get("usernames", []):
        add("Username: " + u, '"%s"' % u)
    return dorks


# --------------------------------------------------------------------------
# Findings / diff
# --------------------------------------------------------------------------

def collect_findings(results):
    fs = set()
    for u, data in results["usernames"].items():
        urls = set(i["url"] for i in data.get("builtin", []))
        urls.update(data.get("sherlock") or [])
        urls.update(data.get("maigret") or [])
        for url in urls:
            fs.add("social::%s::%s" % (u.lower(), host_of(url)))
    for e, data in results["emails"].items():
        for s in data.get("holehe") or []:
            fs.add("email::%s::%s" % (e.lower(), s.lower()))
        br = data.get("breaches")
        if isinstance(br, list):
            for b in br:
                name = b.get("Name") or b.get("Title") or str(b)
                fs.add("breach::%s::%s" % (e.lower(), name))
    for b in results["brokers"]:
        if b.get("status") == "possible match":
            fs.add("broker::%s" % b["domain"].lower())
    return fs


def previous_findings(outdir, current_path):
    reports = [os.path.join(outdir, f) for f in os.listdir(outdir)
               if f.startswith("footprint-") and f.endswith(".json")]
    reports = [r for r in reports if os.path.abspath(r) != os.path.abspath(current_path)]
    if not reports:
        return set()
    reports.sort()
    prev = load_json(reports[-1], default={})
    return set(prev.get("findings", []))


def humanize(key):
    p = key.split("::")
    if p[0] == "social":
        return "Profile for '%s' on %s" % (p[1], p[2])
    if p[0] == "email":
        return "Account for %s on %s" % (p[1], p[2])
    if p[0] == "breach":
        return "Breach: %s in %s" % (p[1], p[2])
    if p[0] == "broker":
        return "Possible data-broker listing on %s" % p[1]
    return key


# --------------------------------------------------------------------------
# HTML report
# --------------------------------------------------------------------------

CSS = """
body{font-family:'Segoe UI',Arial,sans-serif;margin:0;background:#0f1115;color:#e7e7ea}
.wrap{max-width:980px;margin:0 auto;padding:28px}
h1{font-size:24px;margin:0 0 2px}
h2{font-size:18px;margin:28px 0 10px;border-bottom:1px solid #2a2e37;padding-bottom:6px}
.sub{color:#9aa0aa;font-size:13px;margin-bottom:16px}
.chips{display:flex;flex-wrap:wrap;gap:8px;margin:14px 0}
.chip{background:#1b1f27;border:1px solid #2a2e37;border-radius:14px;padding:4px 12px;font-size:13px}
.chip.new{background:#3a2410;border-color:#7a4a12;color:#ffcf8f}
.card{background:#161a21;border:1px solid #242833;border-radius:10px;padding:14px 16px;margin:10px 0}
.k{color:#9aa0aa}
a{color:#7db5ff;text-decoration:none}
a:hover{text-decoration:underline}
table{width:100%;border-collapse:collapse;font-size:14px}
th,td{text-align:left;padding:7px 8px;border-bottom:1px solid #242833;vertical-align:top}
.optout{display:inline-block;background:#1f6feb;color:#fff;border-radius:6px;padding:3px 10px;font-size:13px}
.optout:hover{background:#2a7bff;text-decoration:none}
.tag{font-size:12px;border-radius:5px;padding:1px 7px;border:1px solid #2a2e37}
.hit{background:#26341f;border-color:#3d6b2c;color:#bff0a4}
.miss{color:#8a8f99}
.newbox{background:#241a0e;border:1px solid #6b4a1c;border-radius:10px;padding:14px 16px;margin:14px 0}
.newbox li{color:#ffcf8f}
.muted{color:#8a8f99;font-size:13px}
.foot{margin-top:30px;color:#7a7f88;font-size:12px;border-top:1px solid #242833;padding-top:14px}
"""


def _a(url, text=None):
    return '<a href="%s" target="_blank" rel="noopener">%s</a>' % (
        html.escape(url, quote=True), html.escape(text or url))


def build_html(results, new_findings, summary, cfg):
    E = html.escape
    P = []
    P.append("<!doctype html><html><head><meta charset='utf-8'>")
    P.append("<meta name='viewport' content='width=device-width,initial-scale=1'>")
    P.append("<title>Digital Footprint Report</title><style>%s</style></head><body><div class='wrap'>" % CSS)
    P.append("<h1>Digital Footprint Report</h1>")
    who = cfg["_full_name"] or "(name not set)"
    P.append("<div class='sub'>Subject: <b>%s</b> &middot; Generated %s</div>" % (E(who), E(results["generated"])))

    P.append("<div class='chips'>")
    P.append("<span class='chip'>%d profiles</span>" % summary["profiles"])
    P.append("<span class='chip'>%d email accounts</span>" % summary["email_accounts"])
    P.append("<span class='chip'>%d breaches</span>" % summary["breaches"])
    P.append("<span class='chip'>%d broker hits</span>" % summary["broker_hits"])
    P.append("<span class='chip new'>%d NEW since last run</span>" % len(new_findings))
    P.append("</div>")

    if new_findings:
        P.append("<div class='newbox'><b>New since your last run</b><ul>")
        for k in sorted(new_findings):
            P.append("<li>%s</li>" % E(humanize(k)))
        P.append("</ul></div>")

    # Usernames
    P.append("<h2>Usernames &amp; profiles</h2>")
    if not results["usernames"]:
        P.append("<div class='muted'>No usernames configured.</div>")
    for u, data in results["usernames"].items():
        P.append("<div class='card'><div><b>@%s</b></div>" % E(u))
        urls = {}
        for i in data.get("builtin", []):
            urls[i["url"]] = i["site"]
        for src in ("sherlock", "maigret"):
            for url in (data.get(src) or []):
                urls.setdefault(url, host_of(url))
        if urls:
            P.append("<table>")
            for url, site in sorted(urls.items(), key=lambda x: x[1].lower()):
                P.append("<tr><td>%s</td><td>%s</td></tr>" % (E(site), _a(url)))
            P.append("</table>")
        else:
            P.append("<div class='muted'>No profiles detected.</div>")
        notes = []
        if data.get("sherlock") is None:
            notes.append("Sherlock not installed")
        if data.get("maigret") is None:
            notes.append("Maigret not installed/enabled")
        if notes:
            P.append("<div class='muted'>%s</div>" % " &middot; ".join(E(x) for x in notes))
        P.append("</div>")

    # Emails
    P.append("<h2>Email exposure</h2>")
    if not results["emails"]:
        P.append("<div class='muted'>No emails configured.</div>")
    for e, data in results["emails"].items():
        P.append("<div class='card'><div><b>%s</b></div>" % E(e))
        used = data.get("holehe")
        if used is None:
            P.append("<div class='muted'>holehe not installed &mdash; account discovery skipped.</div>")
        elif used:
            P.append("<div class='k'>Registered on:</div><div>")
            P.append(", ".join("<span class='tag hit'>%s</span>" % E(s) for s in used))
            P.append("</div>")
        else:
            P.append("<div class='muted'>No registered accounts found by holehe.</div>")
        br = data.get("breaches")
        if br is None:
            P.append("<div class='muted'>HIBP not configured (add a free API key for breach checks).</div>")
        elif isinstance(br, dict) and br.get("error"):
            P.append("<div class='muted'>HIBP error: %s</div>" % E(br["error"]))
        elif isinstance(br, list) and br:
            names = []
            for b in br:
                nm = b.get("Title") or b.get("Name") or "?"
                dt = b.get("BreachDate", "")
                names.append("%s%s" % (nm, " (%s)" % dt if dt else ""))
            P.append("<div class='k'>Breaches:</div><div>")
            P.append(", ".join("<span class='tag'>%s</span>" % E(n) for n in names))
            P.append("</div>")
        elif isinstance(br, list):
            P.append("<div class='muted'>No breaches found for this address.</div>")
        P.append("</div>")

    # Brokers
    P.append("<h2>Data brokers &amp; people-search sites</h2>")
    P.append("<div class='muted'>Click <b>Opt out</b> to start a removal request. "
             "Opt-out URLs can change &mdash; verify on the site if a link 404s.</div>")
    P.append("<table><tr><th>Site</th><th>Status</th><th>Search</th><th>Removal</th></tr>")
    for b in results["brokers"]:
        st = b.get("status", "")
        cls = "hit" if st == "possible match" else ""
        status_html = "<span class='tag %s'>%s</span>" % (cls, E(st)) if st else ""
        optout = ("<a class='optout' href='%s' target='_blank' rel='noopener'>Opt out</a>"
                  % html.escape(b["optout_url"], quote=True)) if b.get("optout_url") else ""
        P.append("<tr><td>%s<div class='muted'>%s</div></td><td>%s</td><td>%s</td><td>%s</td></tr>" % (
            E(b["name"]), E(b.get("notes", "")), status_html, _a(b["search_url"], "search"), optout))
    P.append("</table>")

    # Dorks
    P.append("<h2>Search-engine lookups</h2>")
    P.append("<table><tr><th>Query</th><th>Run on</th></tr>")
    for d in results["dorks"]:
        engines = " &middot; ".join([_a(d["google"], "Google"), _a(d["bing"], "Bing"), _a(d["ddg"], "DuckDuckGo")])
        P.append("<tr><td>%s</td><td>%s</td></tr>" % (E(d["label"]), engines))
    P.append("</table>")

    P.append("<div class='foot'>For checking your own information to support privacy / data-removal "
             "requests. Built-in checks are best-effort and can produce false positives or be blocked "
             "by anti-bot measures &mdash; confirm before acting. Re-run periodically; new findings are "
             "highlighted at the top.</div>")
    P.append("</div></body></html>")
    return "".join(P)


# --------------------------------------------------------------------------
# Main
# --------------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser(description="Scan your own digital footprint.")
    ap.add_argument("--config", default=os.path.join(HERE, "config.json"))
    ap.add_argument("--output", default=None, help="Output folder (overrides config).")
    ap.add_argument("--quick", action="store_true",
                    help="Skip slow tools (maigret) and broker probing.")
    ap.add_argument("--open", action="store_true", help="Open the HTML report when done.")
    args = ap.parse_args()

    # First run: seed config from the template and stop so the user can edit it.
    if not os.path.exists(args.config):
        example = os.path.join(HERE, "config.example.json")
        if os.path.exists(example):
            shutil.copyfile(example, args.config)
            print("[*] Created %s from the template." % args.config)
            print("[*] Open it, fill in your details, then run this again.")
        else:
            print("[!] No config.json or config.example.json found next to footprint.py.")
        return

    cfg = load_json(args.config) or {}
    name = cfg.get("name", {})
    cfg["_full_name"] = (name.get("full") or
                         (" ".join(x for x in [name.get("first", ""), name.get("last", "")] if x))).strip()

    outdir = args.output or cfg.get("output_dir") or default_output_dir()
    os.makedirs(outdir, exist_ok=True)

    tools = cfg.get("tools", {})
    use_sherlock = tools.get("sherlock", True)
    use_maigret = tools.get("maigret", False) and not args.quick
    use_holehe = tools.get("holehe", True)
    probe = cfg.get("probe_brokers", False) and not args.quick
    timeout = int(cfg.get("timeout", 12))

    sites = load_json(os.path.join(HERE, "sites_usernames.json"), default=[])
    brokers = load_json(os.path.join(HERE, "data_brokers.json"), default=[])

    results = {
        "generated": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "subject": cfg["_full_name"],
        "usernames": {},
        "emails": {},
        "brokers": [],
        "dorks": [],
        "tools_available": {"sherlock": have("sherlock"),
                            "maigret": have("maigret"),
                            "holehe": have("holehe")},
    }

    print("=== Digital Footprint Scan ===")
    print("Subject : %s" % (cfg["_full_name"] or "(name not set)"))
    print("Output  : %s" % outdir)
    print("Tools   : sherlock=%s maigret=%s holehe=%s  (probe brokers=%s)" % (
        results["tools_available"]["sherlock"],
        results["tools_available"]["maigret"],
        results["tools_available"]["holehe"], probe))
    print()

    # Usernames
    for u in cfg.get("usernames", []):
        print("[*] Username: %s" % u)
        entry = {"builtin": builtin_username_scan(u, sites, timeout)}
        entry["sherlock"] = run_sherlock(u, timeout) if use_sherlock else None
        entry["maigret"] = run_maigret(u, timeout) if use_maigret else None
        n = len(set([i["url"] for i in entry["builtin"]]) |
                set(entry["sherlock"] or []) | set(entry["maigret"] or []))
        print("    -> %d profile(s)" % n)
        results["usernames"][u] = entry

    # Emails
    for e in cfg.get("emails", []):
        print("[*] Email: %s" % e)
        entry = {"holehe": run_holehe(e, timeout) if use_holehe else None}
        entry["breaches"] = check_hibp(e, cfg.get("hibp_api_key", ""), timeout)
        if isinstance(entry["breaches"], (list, dict)):
            time.sleep(1.6)              # be gentle with the HIBP rate limit
        results["emails"][e] = entry

    # Brokers + dorks
    print("[*] Data brokers (%d)%s" % (len(brokers), " - probing" if probe else ""))
    results["brokers"] = scan_brokers(brokers, cfg["_full_name"],
                                      cfg.get("location", {}).get("city", ""), probe, timeout)
    results["dorks"] = build_dorks(cfg)

    # Findings + diff
    findings = collect_findings(results)
    results["findings"] = sorted(findings)

    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    json_path = os.path.join(outdir, "footprint-%s.json" % stamp)
    html_path = os.path.join(outdir, "footprint-%s.html" % stamp)

    new_findings = findings - previous_findings(outdir, json_path)

    summary = {
        "profiles": sum(len(set([i["url"] for i in d.get("builtin", [])]) |
                            set(d.get("sherlock") or []) | set(d.get("maigret") or []))
                        for d in results["usernames"].values()),
        "email_accounts": sum(len(d.get("holehe") or []) for d in results["emails"].values()),
        "breaches": sum(len(d["breaches"]) for d in results["emails"].values()
                        if isinstance(d.get("breaches"), list)),
        "broker_hits": sum(1 for b in results["brokers"] if b.get("status") == "possible match"),
    }

    with open(json_path, "w", encoding="utf-8") as f:
        json.dump(results, f, indent=2)
    with open(html_path, "w", encoding="utf-8") as f:
        f.write(build_html(results, new_findings, summary, cfg))
    # convenience copy that always points at the newest report
    try:
        shutil.copyfile(html_path, os.path.join(outdir, "latest.html"))
    except Exception:
        pass

    print()
    print("=== Summary ===")
    print("Profiles found    : %d" % summary["profiles"])
    print("Email accounts    : %d" % summary["email_accounts"])
    print("Breaches          : %d" % summary["breaches"])
    print("Broker hits       : %d" % summary["broker_hits"])
    print("NEW since last run: %d" % len(new_findings))
    print()
    print("Report: %s" % html_path)

    if args.open:
        try:
            if sys.platform.startswith("win"):
                os.startfile(html_path)        # noqa
            else:
                import webbrowser
                webbrowser.open("file://" + os.path.abspath(html_path))
        except Exception:
            pass


if __name__ == "__main__":
    main()
