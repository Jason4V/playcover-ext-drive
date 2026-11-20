> 中文读者请见：[本项目中文版介绍](README.zh-CN.md) — full Chinese version of this README.

# Move PlayCover Genshin Impact / Zenless Zone Zero Data to an External Drive and Free Up Internal Storage

**Fix the PlayCover symlink black screen with HFS+ sparse bundle mounting · Genshin Impact and Zenless Zone Zero tested**

Move tens of gigabytes of sandboxed app data to an external drive and reclaim internal disk space.
A symlink (`ln -s`) inside the macOS sandbox causes a black screen on launch. The only reliable approach is to create an HFS+ sparse disk image and mount it with `hdiutil attach -mountpoint` onto the app's container data subdirectory. Save files stay local. **No root, no SIP disable, no Full Disk Access required.**

**Keywords**: `macOS sandboxed app migration` `PlayCover Genshin Impact external drive` `Genshin Impact symlink black screen` `internal disk full` `game data on external drive` `sandbox symlink black screen` `Genshin Impact external drive` `HFS+ sparsebundle mount` `mount_apfs Operation not permitted` `PlayCover game data migration`

## TL;DR

| Approach | Result |
| --- | --- |
| `ln -s` container subdirectory → external disk | ❌ Black screen on launch (window screenshot only 29 KB, solid color), no crash log; disproved by A/B control |
| `mount_apfs` on an APFS volume | ❌ `Operation not permitted` without passwordless sudo; disabling SIP breaks iOS apps |
| **HFS+ sparsebundle + `hdiutil attach -mountpoint`** | ✅ Normal rendering; `lsof` confirms the game reads external `AssetBundles/*.blk` resources |

**Method**: keep the container root as a real directory; mount only the inner data-heavy subdirectory (for Genshin Impact, `Data/Library/MihoyoDownload`, ~31 GB); keep saves (`Documents`) local. A non-empty mount point shadows the original content and restores it intact on detach — so A/B testing is risk-free.

## Why

PlayCover-installed iOS games keep their asset bundles inside sandbox containers; a single Genshin Impact or Zenless Zone Zero install can exceed 30 GB. The widely circulated `ln -s` trick appears to free space, but sandboxed apps validate container paths at launch; a symlink pointing to `/Volumes` fails validation → black screen, no crash log, process still alive, which is hard to diagnose. Official discussions confirm this is by security design: allowing a symlink to read arbitrary paths would be a serious vulnerability. The fix is **mounting, not symlinking**.

## Use Cases

- Move PlayCover games (Genshin Impact, Zenless Zone Zero, Honkai Star Rail, etc.) to an external drive
- Offload a large data subdirectory of any sandboxed app (the container root cannot be symlinked)
- Internal disk full, external disk is exFAT, and you do not want to reformat

## Quick Start

Prerequisite: replace all `***placeholders***` in `scripts/*.sh`. Core steps (see `SKILL.md` for details):

```bash
# 0. Read-only recon: find the real bulk, confirm external disk space and format, no running process
du -sh "$HOME/Library/Containers/<bundle-id>/Data/Library/"* | sort -h | tail
df -h /Volumes/<external> && diskutil info /Volumes/<external> | grep -i "File System Personality"

# 1. Back up the data-heavy directory to the external disk (exclude exFAT metadata)
rsync -a --exclude='._*' "<source-dir>/" "<backup-dir>/"

# 2. Minimal feasibility probe: mount a 100 MB image on a non-empty directory, verify mount works and data is fully restored after detach
hdiutil create -size 100m -type SPARSEBUNDLE -fs HFS+ -volname Probe "/Volumes/<external>/probe.sparsebundle"
hdiutil attach -mountpoint "$HOME/Library/Containers/<bundle-id>/<data-subdir>" "/Volumes/<external>/probe.sparsebundle"
hdiutil detach "$HOME/Library/Containers/<bundle-id>/<data-subdir>"

# 3. Create the real image → load data → mount onto the container subdirectory
hdiutil create -size 60g -type SPARSEBUNDLE -fs HFS+ -volname AppData "/Volumes/<external>/AppDataHFS.sparsebundle"
hdiutil attach -nobrowse -mountpoint /tmp/stage "/Volumes/<external>/AppDataHFS.sparsebundle"
rsync -a --exclude='._*' "<backup-dir>/" /tmp/stage/ && hdiutil detach /tmp/stage
hdiutil attach -nobrowse -mountpoint "$HOME/Library/Containers/<bundle-id>/<data-subdir>" "/Volumes/<external>/AppDataHFS.sparsebundle"
```

After a reboot or replugging the external disk, just remount: `scripts/mount_external.sh`.

## Verification Checklist

All six checks are required:

| # | Check | Command / Evidence | Pass |
| --- | --- | --- | --- |
| 1 | Mount is active | `mount \| grep <target>` | an hfs entry appears |
| 2 | Readable through the mount | `du -sh <target>` + `find <target> -type f \| wc -l` | size and file count match the source |
| 3 | Non-black screen | `screencapture -x -o -l <window-id>` | screenshot far larger than 30 KB |
| 4 | **Assets are really read** | `lsof -p <pid> \| grep <target>` | `*.blk` file handles appear |
| 5 | No crash | `ls ~/Library/Logs/DiagnosticReports \| grep -i <app>` | no new entries |
| 6 | Reversible | `hdiutil detach <target>` then `du -sh <target>` | original data fully restored |

Process alive + normal screenshot = necessary but not sufficient; check #4 is mandatory.

## Verification Scope

"Verified" in the title and description means:

- **Genshin Impact** — full end-to-end verification: HFS+ image mounted → game launched → normal "Click to Start" screen → `lsof` confirmed the process reading `AssetBundles/*.blk` from the external image (198 file handles), with multiple A/B single-variable control experiments confirming symlink failure and mount success.
- **Zenless Zone Zero** — only **backup migration** (29 GB container moved to the external disk, file counts verified) plus an exFAT symlink read/write probe; **no game launch verification** (its app bundle was absent on the test machine). It is not evidence that the mount approach works for that game, but the backup migration itself did succeed.

## Failure Catalog

| # | Pitfall | Avoidance |
| --- | --- | --- |
| F1 | Symlink → black screen | no symlinks; A/B control + `lsof` check |
| F2 | APFS mount needs root | probe with `sudo -n true`; use HFS+ if no passwordless sudo |
| F3 | `rm -rf` silently fails (TCC protection) | verify after delete; ask the user to delete manually |
| F4 | Trash item auto-renamed (false data-loss alarm) | `ls -lat ~/.Trash \| grep -i <kw>` to list all matches |
| F5 | Cross-disk `mv` → EXDEV | use `cp -a` or `rsync -a` |
| F6 | exFAT `._*` AppleDouble doubles the file count | add `--exclude='._*'` to verification |

Full four-element postmortems: `references/failure-catalog.md`.

## Repository Files

Nine files, each with a distinct role:

| File | What it is | When to read |
| --- | --- | --- |
| `SKILL.md` | Main guide: decision tree + 8 iron rules + 5-phase workflow + 6 verification checks | Read before starting to judge whether the approach applies and which path to take; AI assistants use it to decide when to activate this skill |
| `references/probe-and-verify.md` | Command handbook: 100 MB probe, APFS/HFS+ privilege differences, window forensics, A/B control, `lsof` checks, with copyable commands | Copy commands; tell a real black screen from occlusion; perform asset-level verification |
| `references/failure-catalog.md` | Four-element postmortems (symptom / root cause / why it happened / how to avoid) for 6 failure paths | Check here when hitting pitfalls: symlink black screen, APFS privilege failure, silent TCC delete failure, etc. |
| `references/sources.md` | Original key quotes and links from official discussions #473 / #1712, Bilibili video, and technical articles | Use for source tracing and verifying why symlinks fail |
| `scripts/migrate_to_external.sh` | First-migration skeleton (placeholder version): recon → backup → probe → create image → mount → verify → free space | Execute step by step on first migration; verify each step before continuing; never run it all blind |
| `scripts/mount_external.sh` | Remount script for after reboot / replugging: exits if already mounted, detects running app, checks image presence, reports resource file count after mount | Run once after each reboot or disk replug |
| `LICENSE` | MIT license | Understand usage and redistribution terms |
| `README.md` | This page (English) | Quick overview and navigation |
| `README.zh-CN.md` | Full Chinese version of this README | Click the link at the top for the Chinese introduction |

## Installation & Usage

### 1. Install

**As a WorkBuddy skill (recommended)**: the verified user-level skill directory on this machine is `~/.workbuddy/skills/`. Clone the repository into it, with the directory name matching the `name` in `SKILL.md`:

```bash
git clone https://github.com/Jason4V/playcover-ext-drive.git \
  "$HOME/.workbuddy/skills/macos-sandbox-app-external-drive"
```

Then just describe the task in natural language, e.g. "move my PlayCover Genshin Impact data to an external drive to free up space". The assistant decides whether to activate the skill based on the `description` in `SKILL.md`. You can also name it explicitly: "use the macos-sandbox-app-external-drive skill". For other AI tools, place the whole repository in that tool's skill directory, with `SKILL.md` at the root of the subdirectory.

### 2. Use as documentation only

No installation needed: read the decision tree in `SKILL.md` → run the probe in `references/probe-and-verify.md` → run the commands in Quick Start manually. The scripts are templates, not install-and-run packages.

### 3. Using the scripts

- All `***...***` in the scripts are placeholders; replace them with real values: bundle id, container data subdirectory, external disk path, image name, app process keyword.
- `migrate_to_external.sh`: execute step by step, verifying each step before the next; step 6 ("free local space") is only a comment — deleting local data requires your explicit confirmation and must be done manually.
- `mount_external.sh`: runnable after replacing placeholders; exits immediately if already mounted, refuses to mount while the app is running; run once after reboot or replugging.
- The external disk must be connected and mounted; keep quotes around paths containing spaces.

### 4. Minimal workflow

1. Read-only recon: use `du` to find the bulk; confirm external disk space and format; ensure the app is not running.
2. Backup: `rsync -a --exclude='._*' ...`.
3. 100 MB probe: mount onto the real target directory, then `detach` and confirm the file count is unchanged.
4. Create the HFS+ image → load data → mount onto the container subdirectory.
5. Launch the game and verify against the six checks above (especially #4, `lsof`).
6. Only after everything passes, delete the original local directory to free space.

## Sources

- PlayCover official #473 (why symlinks fail): https://github.com/PlayCover/PlayCover/discussions/473
- PlayCover official #1712 (mount migration tutorial): https://github.com/PlayCover/PlayCover/discussions/1712
- Bilibili hands-on video: https://www.bilibili.com/video/BV1i4mKYiEtt/
- Independent symlink-vs-mount evidence: https://www.panwenbin.com/mac-softwares/运行ios-app
- Creating an image on exFAT and mounting it to a data directory: https://egeek.me/2025/01/05/snapshots-for-ios-backups
- Ready-made auto-mount tool: https://github.com/PhiLiaO93/auto-mount-Playcover

## License

MIT — see `LICENSE`.
