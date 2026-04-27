# macSystemCleaner

> macOS System Data bloat targeted diagnostic tool.

🌐 **中文版**：[README.md](README.md) · **English**: this file

## What this tool does

Locates the root cause when your Mac's "System Data" category in **System Settings → Storage** is abnormally large (often hundreds of GB), and offers per-item cleanup with rollback support.

It targets **known macOS bugs** (icon cache corruption, mediaanalysisd re-indexing loop, Handoff clipboard archive bloat, Spotlight index runaway, Biome tombstone pileup, etc.) — 28 specific paths in total.

## How it's different from CleanMyMac / Mole / Sensei

| Those tools are good at | This tool is good at |
|---|---|
| Clearing your Downloads folder, old videos, duplicates | Locating system-level bloat from known macOS bugs |
| Friendly UI, one-click operation | Command-line, per-item confirmation, `.bak` rollback |
| Comprehensive scanning | Targeted diagnostic |
| Everyday cleanup | The "why is my System Data 500 GB" situation |

**Use this tool when**: CleanMyMac / Mole scans tell you "your Mac is clean" but the "System Data" bar is clearly not clean.

**Use other tools when**: you just want to visualize disk usage or clean everyday clutter — **OmniDiskSweeper** or **GrandPerspective** are great for that.

## What this tool deliberately does NOT do

This is a script, not a product. The following are intentional omissions:

- **No comprehensive scan + total score** — it's targeted, not a "you have 47 GB of junk" dashboard
- **No GUI** — stays as `.command` double-click + pure zsh, zero dependencies
- **No Homebrew / no Mac App Store** — a single `.command` file is enough; MAS sandbox would break system-level access
- **No automatic cleanup** — every item requires explicit confirmation. `~/Library/Containers` and `~/Library/Application Support` (WeChat chat history, Obsidian notes, Lightroom catalogs, etc.) are **never auto-cleaned**
- **No monetization** — MIT licensed, no Pro version, no subscription

## How to use

### Download

Grab the latest DMG from [Releases](https://github.com/Raven940309/macSystemCleaner/releases/latest) and double-click to mount. The DMG uses APFS, which preserves executable bits — `.command` files are ready to double-click with zero terminal / chmod.

If you prefer source:

```bash
git clone https://github.com/Raven940309/macSystemCleaner.git
cd macSystemCleaner
```

⚠️ **Don't use "Download ZIP" from the GitHub UI** — macOS strips executable bits during unzip. If you already did, run `chmod +x *.command` or launch via `zsh script-name.command`.

### Step 1: Diagnose first (recommended)

Double-click `1-系统数据诊断.command` (`verify_all.command` if you cloned).

This script **only reads, never modifies**. It outputs:

- All 28 known bloat points, scanned with actual sizes
- Top 10 sub-directories in `~/Library/{Containers,Application Support,Group Containers}` (with app names translated)
- A **plain-language analysis section** at the end: for each abnormal item, what it is, why it's big, and how to clean it manually

**For most people, this diagnostic alone is enough.** You see the root cause, and clean it yourself in the relevant app.

### Step 2: Interactive cleanup (optional)

Double-click `2-系统数据清理.command` (`MacSystemCleaner.command`).

Each item requires `y/n` confirmation. For each you see: size, reason, risk, and what you'll visually notice after cleanup.

Different categories are handled differently:

- **Icon cache** (can be hundreds of GB, no clean rollback): tool opens Finder for visual confirmation, then requires typing `DELETE` (uppercase) as a second confirmation
- **Small items** (iCloud / CoreSpotlight / Xcode DerivedData / VS Code cache / etc.): `mv` rename to `.bak-<timestamp>` — APFS same-volume O(1) rename, zero extra space cost, and fully rollback-able via the built-in rollback menu
- **System-level items** (Spotlight / logs / TM snapshots / brew / npm / pip, etc.): official CLI commands only
- **User-data items** (Mail / iOS backups / Outlook / Podcast / `~/Library/Containers`): **diagnose only, never auto-clean**

### v0.7: Rollback menu

After any cleanup, operation history is persisted to `~/Library/Application Support/macSystemCleaner/history.tsv`.

Next time you launch the tool, in the cleanup menu type `r` to enter the rollback menu. You can:

- View all past cleanups with their current backup status (`live` / `missing` / `rolled back`)
- **Per-item rollback** — pick specific cleanups to undo
- **Bulk rollback** — restore everything that still has a `.bak`
- **Delete all backups** — when you've confirmed the system is stable (24-48h recommended) and want to actually free the disk space

When rolling back, if the system has already regenerated a fresh directory at the original path, you'll be offered three choices: keep current / overwrite with backup / cancel. No silent overwrites.

If total backup size exceeds 3 GB, the main menu shows a prominent warning.

## Coverage

**28 detection items**: icon cache · Time Machine snapshots · APFS snapshots · Spotlight index · system logs · macOS update staging · GarageBand/Logic audio library · iCloud Drive (bird) · iCloud Photos (cloudphotosd) · CloudKit · CoreSpotlight · iOS backups · Xcode user-domain · Docker · Outlook · OneDrive · user app caches · Apple Mail · Podcast · dev tool caches (brew/npm/pip/cargo) · VS Code · QuickLook · Handoff clipboard archive · asitop power logs · **mediaanalysisd (Sequoia 15.1 bug)** · **Biome behavior DB** · **Xcode Simulator Runtime (system-domain)** · **Adobe Media Cache**

**2 synthetic signals**: triggered when `~/Library/Containers` > 50 GB or `~/Library/Application Support` > 30 GB, providing per-app cleanup guidance.

## Safety notes

- ✅ **Verified**: icon cache cleanup (author's own Mac, 502 GB → 30 MB), all official CLIs, QuickLook
- ⚠️ **Official CLI but not personally tested**: Spotlight rebuild, system log erase, TM snapshot deletion (using Apple's official CLI, theoretically safe)
- ❓ **Not tested**: `mv .bak` flow for iCloud / CoreSpotlight / Xcode / VS Code / etc. (rollback-able by design)

None of the unverified items will be cleaned without your explicit per-item confirmation.

## Reporting issues

GitHub Issues has structured templates for bug reports and new detection items. For non-GitHub users, the author monitors the Chinese discussion via Xiaohongshu (小红书) — if you prefer that channel, the README (Chinese) has pointers.

**Please run `verify_all.command` first** and include the log in your bug report.

## Compatibility

- Developed on macOS Sequoia (26.4) / Apple Silicon
- Theoretically compatible with macOS Ventura (13) and later, Intel + Apple Silicon
- Report compatibility issues via GitHub Issues

## Recommended workflow

1. Take a Time Machine backup before cleaning anything
2. Run `verify_all.command` first (diagnostic only)
3. If there's a clear culprit, run `MacSystemCleaner.command` and handle items one by one
4. When unsure about any prompt, type `n` to skip
5. After 24–48h of normal operation, open the rollback menu and remove `.bak` backups to actually free the space

## Disclaimer

Provided as-is. The author assumes no liability for data loss or system issues arising from use.

## License

[MIT](LICENSE)
