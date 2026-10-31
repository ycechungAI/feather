# Changelog

## Unreleased: memory and disk

### Added
- **Feather's own tab strip** replaces macOS window tabs: fixed-width tabs from the left that shrink
  only when full (then a » list), narrow pinned tabs with a site badge, Chrome-style groups (colored
  label, tint and line; click the label to collapse), × and middle-click to close, drag to reorder,
  drag off to a new window or onto another window, ⌘1–9 and ⌃Tab, and ⌘W closes the tab (⇧⌘W the
  window). Only the selected tab's page is in the window, so WebKit throttles the others.
- **Inspect Element** and View ▸ Show Web Inspector (⌥⌘I), turned on in Settings ▸ Developer, for
  reading a page's console when something breaks. It also applies to tabs already open.
- **More debug logging** when Feather runs with `FEATHER_DEBUG=1`: every page request, each response
  saved as a download, each failed load and each page crash, to track down pages that fail only
  sometimes (such as amazon.ca's cart).
- **One bookmark bar per window** instead of one per tab, which saves memory with many tabs.
- **Pin Tab** in a tab's right-click menu, with Add Tab to Group and the usual close commands. Pinned
  tabs are narrow (about 3 letters) at the left, survive Close Other Tabs, ask before closing, and are
  restored.
- **Saved tab groups,** like Chrome's and Brave's. Make a group from the window's tabs or the
  current tab, with a name and one of 8 colors (Tab Groups menu). Groups show as colored chips at
  the left of the bookmark bar: click one to bring its tabs forward or reopen them in a new window,
  asleep except the first; right-click to rename, recolor, open in a new window, close or delete.
  Grouped tabs show the group's colored dot before their title. Groups are saved in
  `tab-groups.json` and keep up with their open tabs.
- **Download Video (⌥⌘S)**, next to the PiP button. It saves plain video files and HLS streams
  while they play, including streams behind a `blob:` player such as hls.js, with the site's cookies.
  It refuses encrypted, DRM and DASH streams with a message that says why.
- **Subtitles button:** turns the video's own subtitle tracks on or off, and loads `.srt` and `.vtt`
  files onto any video (View ▸ Load Subtitle File…).

### Changed
- **Web cache is capped at 500 MB** (Settings ▸ Web cache limit, 250 MB to 5 GB). Every 2 minutes
  Feather drops cached video, audio and large images, which were about 80% of the cache. It keeps
  scripts, styles and fonts at any size, and keeps a cache only for your 20 most visited sites and
  open tabs. On a real profile the cache went from 781 MB to 55 MB. Cookies and site storage are
  never touched.
- **History keeps the last 7 days.**
- **Tabs sleep after 5 minutes** in the background (was 10).
- **No back/forward page cache:** going Back reloads the page instead of keeping old pages in memory.
  Also smaller audio buffers during video and slower timers on hidden pages.
- **The PiP button sits next to Home**, at the top left.
- **The release build is optimized for size** (`-Osize`, dead stripping): the binary is 12% smaller.

### Fixed
- **YouTube stopped, or Picture in Picture closed, every few minutes.** Feather skipped YouTube ads
  by jumping to their end, and YouTube answered by interrupting playback. Ads are now muted and play
  to the end. Hidden pages (a video floating in PiP over another app) no longer have their timers
  slowed to minutes, Feather retries reopening PiP for up to 10 seconds after an ad, and a tab
  with a playing or floating video never goes to sleep.
- **Picture in Picture closed at every YouTube ad and wouldn't reopen until a reload.** When an ad
  starts or ends, YouTube swaps the video's source; macOS closes the floating window, but WebKit
  sends no event and still reports the video as in PiP. Feather now reopens PiP once the new source
  plays, resetting the video first, and the PiP button no longer does nothing when a stuck video
  or a silent page frame gets in the way.
- **Twitch showed "Error #3000" when an ad ended.** Twitch's player reports each ad to Amazon's ad
  servers and fails when it can't. Twitch may now reach them; they stay blocked on every other site.
- **Restored windows put their tabs out of order.** Every tab after the first came back in reverse.
- **YouTube ads closed Picture in Picture.** YouTube turns PiP off on its player during ads. Feather
  now keeps it allowed, and reopens the floating window if an ad still closes it.
- **Clear History's "cookies and site data" signed you out of Google.** It now keeps the cookies of
  google.com, gmail.com and youtube.com (the `keepSignedIn` setting).

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
- **Picture in Picture did nothing (button and extensions):** the App Sandbox blocked the system's
  PIPAgent, so PiP requests hung silently. Feather now has an exception for that one service only.
- **PiP finds videos in embedded players** from other sites (church streams, Vimeo, YouTube embeds),
  and shows a message instead of doing nothing when PiP can't start.
- **Extensions that can't work in WebKit say so** instead of showing a blank popup. Firefox add-ons
  that need `webRequestBlocking` (like the full uBlock Origin) are flagged when you install them, when you
  click their button, and in Manage Extensions. Feather suggests uBlock Origin Lite instead.

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
