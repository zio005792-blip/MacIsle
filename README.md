# MacIsle

**English** | [简体中文](README.zh-CN.md)

MacIsle gives any Mac a "Dynamic Island": a small black capsule floating in the menu bar at the top centre of the screen. Most of the time it quietly shows what's going on — an AI agent working, a timer counting down, music playing. Rest the pointer on it or click it, and it opens into a card so you can check and act without switching windows.

Made for external displays and Macs without an island; on notched MacBooks it wraps the notch.

![MacIsle preview](docs/preview.png)

---

## How to use it

| Action | What happens |
| --- | --- |
| Rest the pointer on the pill (the hot zone is 110% of the pill's area; ~0.3 s, still) | The island opens. Passing over it doesn't |
| Click the pill | Opens immediately |
| Move the pointer off the card | Closes |
| Two-finger swipe left / right, or click the dots | Switch cards |
| ⌘⇧I | Open from the keyboard; ← → switch cards, number keys jump, Esc closes and returns to your app |
| Right-click the island | Quick menu: Settings, Keep Awake, Pomodoro, camera dot |

When something is going on, the pill widens: an icon on the left, a status on the right (elapsed time, progress, waveform). If two things are happening at once, the second one buds off into a small bubble.

---

## Live Activities (shown on the closed island)

### AI tasks: Claude Code / Codex
**Why**: when several AI coding tasks run at once, you don't have to keep switching windows to see whether they're done or waiting for your approval.

- **Running**: a spinning icon with elapsed time; a badge shows how many are running
- **Needs you**: when Claude asks for permission, the island turns orange with a raised hand and a sound; once you approve it flips back to running
- **Done / failed**: a green tick or red cross with the project name and duration
- **Click a task to jump to its exact conversation**:
  - Claude desktop session → opens that session
  - Codex app thread → opens that thread
  - Running in Terminal / iTerm2 → switches to that exact tab
- Tasks that were interrupted without an end signal are cleared after 10 minutes of silence

Requires running the connect script once — see [Connect Claude Code / Codex / your terminal](#connect-claude-code--codex--your-terminal).

### Long terminal commands
When a command that ran longer than 20 seconds finishes (e.g. `xcodebuild`, `npm install`, `docker build`), the island tells you whether it succeeded and how long it took. Interactive commands such as `vim` or `ssh` are ignored.

### Timer & Pomodoro
A countdown lives on the island and alerts you with a sound when it ends. Pomodoro defaults to 25 min focus / 5 min break, cycles automatically, and counts today's sessions.

### Also
- **Music**: artwork and a live waveform; the track name pops up briefly when the song changes
- **Keep Awake**: stops your Mac from dimming or sleeping — handy for long builds or presenting
- **Hides in full screen**: watching video full screen (Douyin, Bilibili, video sites, players…) hides the island; choose always hide / always show in Settings
- **Charging**: shows the battery level when you plug in or unplug
- **Volume / brightness**: optionally replaces the system HUD (needs Accessibility)

---

## Cards (shown when the island opens)

Each card has its own size and the island morphs smoothly between them. When it opens, it jumps to the card you most likely need (see [Smart pick](#smart-pick)).

| Card | What it does |
| --- | --- |
| **Music** | Artwork, title, seekable progress bar, previous / play-pause / next |
| **AI Tasks** | All AI and long-terminal tasks; click to jump to the conversation; clear finished ones |
| **Overview** | Day, date and time; countdown to your next event (with a Join button for online meetings); four quick toggles: Keep Awake, Pomodoro, Screenshot (to clipboard), Dark Mode |
| **Timer** | Pomodoro and 1 / 3 / 5 / 10 / 25 / 60-minute timers; pause, add 1 / 5 min, or end while running |
| **Calendar** | A week strip with the day's events and reminders |
| **Client Dossier** | OCR, classify and cross-check client documents into a Word report (below) |
| **Store Screenshots** | Convert screenshots to App Store sizes (below) |
| **System** | CPU, memory and network up / down with graphs |
| **Clipboard** | Recently copied text, images and files — click to copy again; developer tools (below) |
| **Files** | A shelf: drop files on the island to park them, drag them out later, or share via AirDrop |

Hide cards you don't need or reorder them with ↑ ↓ in Settings.

### Store Screenshots
**Why**: every App Store device size needs its own screenshots, and cropping them by hand is tedious.

Drop screenshots on the card (or click to choose), tick the sizes you need (iPhone 6.9″ / 6.5″ / 6.3″ / 5.5″, iPad 13″ / 12.9″), and they're exported to `Downloads/App Store Screenshots`.
- Portrait and landscape both work; images are scaled to fill and centre-cropped
- Output is opaque PNG (screenshots with an alpha channel are rejected by the store)

### Clipboard developer tools
Each clipboard entry offers one-click conversions; the result is copied for you:
- **JSON**: pretty-print / minify
- **Timestamps**: Unix timestamp ↔ date
- **URL**: decode
- **Base64**: encode / decode
- **JWT**: show the payload
- **Identifiers**: snake_case or spaced words → camelCase

Clipboard history is kept in memory only and cleared on quit; items that password managers mark as concealed are never recorded.

### Client Dossier
**Why**: checking a pile of client documents (business licence, ID card, contracts, authorisation letters, invoices, screenshots…) for consistent details and turning them into a checklist takes ages. This feature is built for **Chinese** documents.

Drop a client **folder** on the island and it will:

1. **Read**: OCR images, scans and PDFs on-device with macOS's built-in text recognition; read Word, RTF and TXT directly
2. **Classify**: business licence, ID documents, contracts, authorisations, invoices, certificates, bank / payments, explanation letters, screenshots, and more
3. **Extract key facts**: entity name, unified social credit code, legal representative, contact, ID number, mobile, email, address, app name; invoice number, date, tax, total, buyer and seller; contract amount, signing date, parties
4. **Cross-check**: when the same fact is written differently in different files, it's flagged so you can pick the right value (or "Use Majority"). One-character differences are marked as likely OCR slips. The other party on contracts and invoices is treated as a counterparty, not a conflict
5. **Check submission materials**: for an App or a game submission — business licence, representative's ID, software copyright, ICP / App filing, privacy policy (plus game licence and anti-addiction for games)
6. **Compare with last time**: when the same client resubmits, lists added, removed and changed files and any facts that changed
7. **Create a report**: a Word document in `Downloads/Client Dossiers` with an overview, cross-checked facts, differences to confirm, an invoice summary, per-category details and the full recognised text
8. **Redacted version**: a report with ID, bank card and phone numbers hidden, plus copies of the images and PDFs with those numbers blacked out — safe to forward

You can close the island while it reads; progress shows on the island and you're notified when it's done. The generated report is in Chinese.

---

## Smart pick

Each time the island opens, it jumps to the card you're most likely to need. If that isn't the default Overview, a short line at the bottom explains why (e.g. "Picked for you · you're dragging a folder").

It looks at:
- **What's happening**: an AI task waiting for you, a running timer, music playing, a meeting within 15 minutes, something convertible just copied, documents being read
- **What you're dragging**: a folder → Client Dossier; screenshots from Xcode / Simulator → Store Screenshots; other files → Files
- **The front app**: Terminal / Claude / Codex → AI Tasks; Xcode / TestFlight → Store Screenshots; Music / video → Music; WeChat / Word → Client Dossier, Clipboard
- **Your habits**: which card you ended up using in which app and at what time of day — it gets better the more you use it. Stored on your Mac only; clear it in Settings

You can turn it off in Settings.

---

## Settings

Menu bar icon › Settings, or right-click the island › Settings.

- **General**: launch at login, interface language (System / 中文 / English), which display, behaviour in full-screen apps, menu bar icon
- **Appearance**: pill size, virtual camera dot, show the pill when idle
- **Interaction**: hover-to-open and its delay, swipe distance to page, flick distance, haptics, keyboard shortcut
- **Cards**: show / hide, reorder with ↑ ↓
- **Media & System**: Now Playing source, volume / brightness on the island, file shelf
- **Smart**: smart pick, show the reason, forget learned habits, clipboard history
- **Self-check**: one click to verify the AI task channel, OCR, permissions, folder access, gesture logic and resource usage, with any problems listed

---

## Install

Download `MacIsle-x.y.z.dmg` from [Releases](../../releases) and drag MacIsle into Applications. Requires macOS 14 or later.

MacIsle isn't notarized by Apple, so the first time, **right-click it in Finder › Open**, or run:

```bash
xattr -dr com.apple.quarantine /Applications/MacIsle.app
```

**Permissions you may be asked for** (only when you use the related feature):
- Calendars: the next event on the Overview card
- Automation (Terminal / System Events / Music): jump to a terminal tab, toggle Dark Mode, control playback
- Accessibility: replace the system volume / brightness HUD

## Connect Claude Code / Codex / your terminal

AI task and long-command alerts need a one-time setup:

```bash
scripts/connect-workflow.sh
```

This:
- adds hooks to `~/.claude/settings.json` (prompt submitted, waiting for approval, tool finished, done)
- wires MacIsle into `notify` in `~/.codex/config.toml`, keeping and still running any notifier you already had
- adds one line to `~/.zshrc` to time long commands (applies to new terminal windows)

Every file is backed up before it's changed. To undo:

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
- Clipboard history lives in memory only
- Dossier version history stores file names, sizes and key facts only — never the full text

## Credits & license

MacIsle is a modified version of the open-source [Boring Notch](https://github.com/TheBoredTeam/boring.notch) (© TheBoredTeam, GPL-3.0). It keeps Boring Notch's media, battery, calendar and file-shelf modules; the interface, interaction and new features were rewritten or added.

MacIsle is likewise licensed under **GPL-3.0** — see [LICENSE](LICENSE). Third-party components are listed in [THIRD_PARTY_LICENSES](THIRD_PARTY_LICENSES) and [NOTICE](NOTICE).

MacIsle is an independent project and is not affiliated with Apple Inc. "Dynamic Island", "MacBook" and "macOS" are trademarks of Apple Inc.
