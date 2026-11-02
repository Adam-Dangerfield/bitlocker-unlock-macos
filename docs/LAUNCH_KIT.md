# Launch & Discoverability Kit — BitLocker on macOS

Repo: https://github.com/Adam-Dangerfield/bitlocker-unlock-macos
Landing page (planned): https://adam-dangerfield.github.io/bitlocker-unlock-macos/

---

## 1. GitHub Repo Metadata

**Description** (repo tagline, ~1 line, shows in search results and repo header):

```
Open a BitLocker-encrypted USB drive on macOS — GUI + CLI, free and open source (GPLv2).
```

**Website** (repo "About" → Website field):

```
https://adam-dangerfield.github.io/bitlocker-unlock-macos/
```

**Topics** (repo "About" → Topics, lowercase/hyphenated, GitHub search-relevant, ~20 max):

```
bitlocker
bitlocker-to-go
macos
mac
swiftui
fuse
fuse-t
disk-encryption
decryption
usb-drive
exfat
dislocker
cross-platform
cli
gui
open-source
gplv2
mbedtls
diskarbitration
windows-interop
```

Notes:
- `bitlocker` and `bitlocker-to-go` are the highest-intent search terms — keep first.
- `dislocker` matters because people searching for the underlying crypto core (Aorimn/dislocker) on macOS should find this.
- Drop `windows-interop` first if you need to trim below 20; it's the weakest match.

---

## 2. Google Search Console — Exact Steps (do AFTER the site is live)

1. **Go to** https://search.google.com/search-console and sign in with the Google account you want to own this property.
2. **Add property → choose "URL prefix"**, not "Domain":
   - Enter `https://adam-dangerfield.github.io/bitlocker-unlock-macos/`
   - **Why URL-prefix, not Domain:** a Domain property verifies ownership of an entire domain (all subdomains/paths) via DNS TXT record, which for `github.io` would require control of DNS for `github.io` itself — you don't have that, GitHub does. Your site lives at a *path* under someone else's domain (`adam-dangerfield.github.io/<repo>/`), so URL-prefix is the only option that matches what you actually control.
3. **Verify ownership via "HTML tag" method** (recommended here since you already control `index.html` in the repo and don't need file hosting tricks):
   - Search Console gives you a line like:
     `<meta name="google-site-verification" content="XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX" />`
   - Paste it inside the `<head>` section of `docs/index.html` (or wherever the GitHub Pages source `index.html` lives), before `</head>`.
   - Commit and push; wait for GitHub Pages to redeploy (usually 1-2 minutes; check the Pages build status under repo Settings → Pages).
   - Back in Search Console, click **Verify**.
   - (HTML-file upload method also works but is more fragile with GitHub Pages/Jekyll rebuilds; DNS TXT is not usable here for the reason above — skip both.)
4. **Create and commit a sitemap** at `https://adam-dangerfield.github.io/bitlocker-unlock-macos/sitemap.xml` (a single-URL sitemap is fine for a one-page site).
5. **Submit the sitemap**: Search Console → left nav → **Sitemaps** → enter `sitemap.xml` → Submit.
6. **Request indexing for the homepage**: left nav → **URL Inspection** → paste the full landing page URL → press Enter → click **Request Indexing**.
7. **Realistic timelines**: verification is instant once the meta tag is live. Sitemap processing usually shows up within a few hours to a day. "Request Indexing" typically gets a new page crawled within hours to a couple of days, but actual appearance in search results and ranking can take 1-4 weeks, especially with no existing backlinks — the GitHub repo linking to the site, and the site linking back, both help.

---

## 3. Bing Webmaster Tools

Worth doing — it's low effort and covers Bing plus DuckDuckGo (which sources much of its index from Bing), so it's incremental reach beyond Google for near-zero extra work. Go to https://www.bing.com/webmasters, sign in, and use **"Import from Google Search Console"** (Bing supports OAuth import of verified sites, sitemaps, and some settings directly from GSC) rather than re-verifying and re-submitting a sitemap from scratch. Confirm the imported sitemap shows as submitted, then optionally use Bing's own URL Submission tool to nudge indexing of the homepage.

---

## 4. Show HN Post

**Title:**

```
Show HN: BitLocker on macOS – open a BitLocker USB drive on a Mac
```

**First comment (post immediately after submitting, as the author):**

```
Author here. I made this because I needed to read a BitLocker-encrypted USB
drive (including BitLocker To Go / exFAT ones) on macOS and couldn't find a
maintained, native-feeling way to do it — everything else was command-line
only or long unmaintained. It's a SwiftUI app + CLI on top of the dislocker
crypto core (github.com/Aorimn/dislocker): plug in the drive, it's
auto-detected, you enter your password or 48-digit recovery key, approve a
macOS admin prompt, and it mounts in Finder — either via a decrypted image
on disk or streamed through FUSE-T so nothing touches disk.

Heads up: there's no signed release yet, so right now it's build-from-source
(cmake + Homebrew deps) and the app is unsigned, which means Gatekeeper will
complain. Notarization and a proper release are next. Would love feedback,
especially from anyone who's dealt with BitLocker To Go edge cases or has
opinions on the FUSE-T vs. disk-image approach.
```

---

## 5. Reddit Posts

### r/macapps

*Self-promo note:* r/macapps generally allows self-promotion for free/open-source tools if you're upfront about being the developer and it's not repeated spam; a "made this" framing with real substance is the norm. Don't cross-post identical copy same-day to multiple subs — space it out and tailor each.

**Title:**

```
I built a free, open-source way to open BitLocker USB drives on macOS
```

**Body:**

```
Hi r/macapps, I'm the author of this one so full disclosure up front.

BitLocker on macOS is a free, open-source (GPLv2) app + CLI for reading
BitLocker-encrypted USB drives on a Mac, including the "BitLocker To Go"
exFAT-personality drives Windows creates for removable media. Plug in the
drive, it auto-detects via DiskArbitration, you enter your password or
recovery key, approve the macOS admin prompt, and it mounts normally in
Finder.

Current state, honestly: it's build-from-source only right now (cmake,
Homebrew deps) and the app is unsigned, so Gatekeeper will flag it — there's
no signed/notarized release yet, that's the next milestone. Repo, with
build instructions, here: https://github.com/Adam-Dangerfield/bitlocker-unlock-macos

Would appreciate feedback, bug reports, or a star if it's useful — and
especially interested to hear if anyone hits issues with real-world
BitLocker To Go drives.
```

### r/DataHoarder

*Self-promo note:* r/DataHoarder tolerates self-promotion for genuinely useful tools/utilities related to data access, backup, and storage, especially FOSS — but expects it framed as "here's a tool that solves X problem," not marketing, and moderators are quick to remove anything that reads like an ad. Keep it practical and technical.

**Title:**

```
Open-sourced a tool to read BitLocker-encrypted USB/external drives on macOS
```

**Body:**

```
Posting as the author. If you've ever ended up with a BitLocker-encrypted
external drive (e.g. from a Windows machine, or a "BitLocker To Go" USB)
and needed to get data off it on a Mac, the options were pretty much
command-line dislocker builds or nothing native. I built a GUI + CLI on top
of the dislocker crypto core (Aorimn/dislocker) for macOS: it auto-detects
the drive, prompts for your password or 48-digit recovery key, and mounts
it in Finder — either decrypting to a local image or streaming via FUSE-T
so nothing extra is written to disk.

It's free, GPLv2, source here: https://github.com/Adam-Dangerfield/bitlocker-unlock-macos

Caveat: no signed release yet, so it's build-from-source and Gatekeeper
will warn on the unsigned app — notarization is planned but not done.
Figured this community would have the most real-world BitLocker-drive
scenarios to stress-test it against, so feedback and issue reports welcome.
```

---

## 6. AlternativeTo Listing

**App name:** BitLocker on macOS

**Category:** File Encryption / Disk Encryption (also cross-list under "Security & Privacy" if AlternativeTo's taxonomy allows a secondary category)

**Description:**

```
BitLocker on macOS is a free, open-source (GPLv2) app and command-line tool
that lets Mac users unlock and mount BitLocker-encrypted USB and external
drives, including "BitLocker To Go" (exFAT-personality) removable volumes
created by Windows. It provides a native SwiftUI GUI as well as a CLI, both
built on the dislocker BitLocker crypto core. Plug in a BitLocker drive,
the app auto-detects it via DiskArbitration, you unlock with your password
or 48-digit recovery key, approve a macOS admin prompt, and the volume
mounts directly in Finder — either by decrypting to a portable disk image
or by streaming the decrypted contents through FUSE-T (a userspace FUSE
implementation, no kernel extension required) so nothing is written to
disk. It currently ships as a build-from-source project (no signed release
binary yet).
```

**Alternative to:**
- BitLocker (Microsoft)
- M3 BitLoader for Mac
- Hasleo BitLocker Anywhere

**Tags:**

```
bitlocker, disk-encryption, decryption, usb-drive, external-drive, exfat,
macos, open-source, free, gplv2, fuse, cli, gui
```

**Platform:** macOS

---

## 7. Homebrew

**Honest assessment: not feasible yet.** A Homebrew Cask installs a downloadable, pre-built `.app` from a GitHub Release URL (with a checksum), and Homebrew's cask review process strongly prefers — and in practice largely requires for smooth acceptance — that the app be code-signed and notarized, since an unsigned/unnotarized app triggers Gatekeeper failures for users installing via `brew install --cask`, which reflects badly on the tap and gets flagged in review.

This project currently has:
- No tagged GitHub Release
- No downloadable `.app` artifact (build-from-source only)
- No code signing or notarization

**What needs to exist first, in order:**
1. A tagged GitHub Release with a zipped `.app` bundle attached as a release asset.
2. Code signing with an Apple Developer ID, plus notarization (`notarytool`) so Gatekeeper doesn't block it on install.
3. A stable, versioned download URL and SHA-256 checksum for that release asset.

Once those exist, a Cask definition (pointing `url`/`sha256` at the release asset, with `depends_on macos:` and a `zap`/`uninstall` stanza) becomes realistic — either submitted to `homebrew/cask` or hosted in a personal tap (`brew tap adam-dangerfield/bitlocker-unlock-macos`) as an interim step before pursuing inclusion in the main cask repo. No formula is written here since there is nothing yet to point it at.

---

## 8. Quick Wins Checklist (prioritized)

1. [owner-must-login] Set GitHub repo **Description**, **Website**, and **Topics** (Section 1) — highest leverage, zero dependencies, do first.
2. [owner-must-login] Publish the landing page (`docs/index.html` or `gh-pages`) so `adam-dangerfield.github.io/bitlocker-unlock-macos/` is live.
3. [automatable] Write and commit a minimal `sitemap.xml` for the landing page.
4. [owner-must-login] Add the Google Search Console verification meta tag to `index.html`'s `<head>`, commit, then verify + submit sitemap in Search Console (Section 2).
5. [owner-must-login] Import the verified site into Bing Webmaster Tools (Section 3).
6. [owner-must-login] Submit the AlternativeTo listing (Section 6) — high buyer-intent traffic, one-time setup.
7. [owner-must-login] Post Show HN (Section 4) — timing matters (weekday US morning); only do once site + repo metadata are live so first-click impressions are good.
8. [owner-must-login] Post to r/macapps and r/DataHoarder (Section 5), staggered by at least a day, not simultaneously.
9. [owner-must-login] Cut a tagged GitHub Release with a zipped `.app`, then pursue Apple Developer ID signing + notarization — prerequisite for Homebrew Cask (Section 7); this is the biggest remaining lift and blocks the most "trustworthy install" complaints.
10. [owner-must-login] Once signed/notarized and released, create a personal Homebrew tap, then evaluate submitting to `homebrew/cask`.
