# Changelog

## 0.2.0 (unreleased: built and tested; waiting for your hands-on check)

### Added
- **Find on page:** ⌘F, ⌘G / ⇧⌘G, Esc. (#1)
- **Address bar suggestions** from history and bookmarks. Optional search-engine suggestions are off
  by default. (#2)
- **Reopen closed tab (⇧⌘T)**, up to 20 tabs with their back/forward history. (#3)
- **Restore last session** on launch. Background tabs load only when clicked, and History ▸ Reopen
  Last Session is there when automatic restore is off. (#3)
- **Settings window (⌘,):**
  - Search engine (5 presets or custom) and home page.
  - Tab sleep timer.
  - Shields, HTTPS-Only, suggestions and session restore.
  - Sites with Shields off.
  - A "Make Feather the Default Browser" button. (#4)
- **Downloads window (⌥⌘L):** progress, cancel, Show in Finder, open, and a list of the last 50 downloads;
  a toolbar button appears while downloading. Private-window downloads aren't saved to the list. (#5)
- **Per-site Shields** from the toolbar shield button, covering subdomains. (#6)
- **Tab sound indicator (🔊) and Mute Tab (⌃⌘M, 🔇),** also available to extensions. (#7)
- **App icon and an About panel** showing the Feather, WebKit and macOS versions. (#9)
- **Tests:** `scripts/test.sh` runs 83 tests, including new tests for suggestions, session restore,
  Shields exceptions and search engines.

### Fixed
- **Picture in Picture was off again:** a later change set WebKit's PiP setting in a way that left it
  disabled. It's set through KVC again, verified with a headless test.

### Changed
- **Builds:** they work with only the Command Line Tools (native SwiftPM build system, Swift Testing
  instead of XCTest) and on ExFAT drives.
- **Size:** the app binary is stripped, keeping the app at about 1 MB including its icon.

## 0.1.0 (2026-10-10)
The first version.

### Added
- **Browsing:** native macOS tabs, an address bar that also searches, a New Tab button, a Home button, private
  windows, downloads to ~/Downloads, printing and zoom.
- **Shields:** ad and tracker blocking compiled into WebKit, YouTube ad skipping, the option to add community
  blocklists, and tracking parameters removed from links.
- **Safety:** App Sandbox, HTTPS-only mode with a warning before falling back to HTTP, fraudulent-site warnings, and
  Gatekeeper quarantine on downloads.
- **Low resource use:** idle background tabs sleep after 10 minutes, and hidden tabs sleep right away when memory
  runs low.
- **Picture in Picture** for any video, including YouTube (⌥⌘P).
- **Bookmarks:** an always-visible bookmark bar, the ☆ button and ⌘D, folders and subfolders, drag-and-drop, Move to,
  and import/export as standard HTML that keeps folders.
- **History:** a searchable history window, deleting single entries or a whole site, and Clear History by time range.
- **Sessions:** save a window's tabs under a name and restore them later.
- **Firefox extensions:** install from addons.mozilla.org ("Add to Feather"), from a `.xpi` file or from a folder;
  a permission prompt before installing; add-ons pinned to the toolbar; turn on/off, open settings, or remove.
- **Tests** for bookmarks and sessions.

### Fixed
- Picture in Picture didn't start in WebKit apps, including on YouTube.
- Crashes and security issues found in an audit.
- Bookmark drag-and-drop reliability, and the width of folder pop-ups.
