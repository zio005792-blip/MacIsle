# MacIsle

**English** | [简体中文](README.zh-CN.md)

A Dynamic Island–style companion for any Mac: a small capsule floating in the menu bar that shows what's going on, and opens into a stack of useful cards. Designed for external displays and Macs without an island, and it also wraps the notch on notched MacBooks.

![MacIsle preview](docs/preview.png)

## Features

**Look & motion**
- Proportions taken from the island on the MacBook Pro (PROLED XDR): a resting pill that scales with your menu bar, and Apple-sized rounded cards when expanded
- Spring animations, a liquid "bubble" that buds off for a second activity, finger-following two-finger paging; GPU-rendered, ~0% CPU when idle
- Hugs the notch on notched screens; floats on external displays, with an optional virtual camera dot

**Live Activities**
- **AI tasks**: see at a glance when Claude Code / Codex is running, needs your approval, finished or failed — click to jump back to the terminal
- **Long terminal commands**: commands running longer than 20 s report success / failure and duration when they finish
- Timer & Pomodoro, Keep Awake, Now Playing, charging, volume / brightness HUD

**Cards**
- Music, Overview (clock / next event / quick toggles), Timer, Calendar, System monitor, Clipboard (one-click JSON / URL / Base64 / timestamp conversions), File shelf
- **App Store screenshots**: drop screenshots and export the exact 6.9″ / 6.5″ / iPad 13″ … sizes (opaque PNG)
- **Client dossier** (built for Chinese business documents): drop a folder → on-device OCR → classified (business licence, ID, contract, invoice…) → cross-checked with mismatches flagged → Word report; plus redacted export, comparison with the previous submission, and an App / game submission checklist

**Smart**
- **Smart pick**: opens on the card you most likely need, based on the front app, what you're dragging, running tasks and your habits (learned on-device only)
- Keyboard: ⌘⇧I to open, ← → to switch cards, number keys to jump, Esc to return
- English and Chinese interface — follows the system, or choose in Settings

## Install

Download `MacIsle-x.y.z.dmg` from [Releases](../../releases) and drag MacIsle into Applications.

MacIsle isn't notarized by Apple, so the first time, **right-click it in Finder › Open**, or run:

```bash
xattr -dr com.apple.quarantine /Applications/MacIsle.app
```

Requires macOS 14 or later.

## Connect Claude Code / Codex / your terminal (optional)

```bash
scripts/connect-workflow.sh
```

This adds a hook to `~/.claude/settings.json`, `~/.codex/config.toml` and `~/.zshrc` (each file is backed up first; an existing Codex `notify` command is kept and chained). To undo:

```bash
scripts/connect-workflow.sh --undo
```

Hooks notify MacIsle with `open -g "macisle://agent?..."`, so they never steal focus.

## Build from source

Requires Xcode 26 or later.

```bash
scripts/install-local.sh      # build and install to /Applications
scripts/package-release.sh    # create the zip and dmg in dist/
```

## Privacy

- OCR, the client dossier, clipboard history and learned habits are all processed on your Mac; nothing is uploaded
- Clipboard history lives in memory only, and items password managers mark as concealed are skipped
- Dossier version history stores file names, sizes and key facts only — never the full text

## Credits & license

MacIsle is a modified version of the open-source [Boring Notch](https://github.com/TheBoredTeam/boring.notch) (© TheBoredTeam, GPL-3.0). It keeps Boring Notch's media, battery, calendar and file-shelf modules; the interface, interaction and new features were rewritten or added.

MacIsle is likewise licensed under **GPL-3.0** — see [LICENSE](LICENSE). Third-party components are listed in [THIRD_PARTY_LICENSES](THIRD_PARTY_LICENSES) and [NOTICE](NOTICE).

MacIsle is an independent project and is not affiliated with Apple Inc. "Dynamic Island", "MacBook" and "macOS" are trademarks of Apple Inc.
