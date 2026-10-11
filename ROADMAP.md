# Feather Roadmap

Current version: **0.2.0** (built; waiting for your check before it's called released). Version **0.4** is the last planned release for now.

Feather's goals don't change from version to version: very little memory and battery use, especially for
video; safety on by default; and web standards kept current by the WebKit engine built into macOS.

---

## v0.2 "Daily driver" (built)

| # | Feature | What you get | Size |
|---|---------|--------------|------|
| 1 | **Find in page** | ⌘F opens a find bar; ⌘G / ⇧⌘G jump to the next/previous match; Esc closes it. | S |
| 2 | **Address bar suggestions** | As you type, matching pages from your history and bookmarks appear under the address bar. Search-engine suggestions are optional and off by default for privacy. | M |
| 3 | **Reopen closed tab and restore last session** | ⇧⌘T brings back the last closed tab (up to 20). Your tabs come back after a restart or crash. | S |
| 4 | **Settings window (⌘,)** | Search engine, home page, sleep timer, Shields, HTTPS-only, suggestions, session restore, and a "Make Feather the default browser" button, without needing Terminal. | M |
| 5 | **Downloads panel** | Progress, cancel, show in Finder, open, and a list of recent downloads (⌥⌘L). | M |
| 6 | **Per-site Shields** | Turn ad blocking off for just one site when it breaks, from the shield button. | M |
| 7 | **Tab audio indicator and mute** | 🔊 shows on tabs playing sound; mute a tab with one shortcut. | S |
| 9 | **App icon and About panel** | A real icon, and an About window showing the Feather, WebKit and macOS versions. | S |

All eight are built and covered by automated tests. Numbers match the original top-10 list; #8 and #10 were moved to later versions.

---

## v0.3 "Privacy and power"
- **Tab shortcuts (from #8):** ⌘1–9 to jump to a tab, ⌥⌘←/→ to switch, and Duplicate Tab.
- **Site permissions panel:** camera, microphone, autoplay and pop-ups, set per site.
- **Profiles:** separate cookie jars, for example Work and Personal, so sites can't link them.
- **Cookie-banner and annoyance hiding:** an optional cosmetic filter list.
- **Reader mode:** a clean, text-only view of articles.
- **Bookmark manager window:** search and bulk-edit bookmarks.
- **Memory view:** memory use per tab, and "Sleep this tab now".
- **Import history** from Brave or Chrome.

## v0.4 "Sync and release" (final planned version)
- **iCloud sync** for bookmarks, sessions and settings.
- **Tab groups and tab search.**
- **Extension auto-updates** from Firefox Add-ons.
- **Signed, notarized download with update check (from #10):** installs without Gatekeeper warnings.
  Needs an Apple Developer account ($99/year).

---

## Ideas, not planned
- An accessibility pass (VoiceOver, keyboard-only use).
- Translations of the interface.
- Published memory and battery benchmarks against Brave and Safari.
