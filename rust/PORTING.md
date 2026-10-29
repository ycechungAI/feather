# Porting plan: Rust prototype → Swift Feather on `main`

This branch's Rust build (`rust/src`, about 1,050 lines) is a measurement prototype. It was
started from `main` at `eeea52a`; `main` has since gained the custom tab bar, tab groups, pinned
tabs, Download Video and subtitles, Inspect Element and the Twitch fix. This file lists what the
Rust build needs, in order, to do everything the Swift build on `main` does. Nothing here is
written yet.

Each item names the Swift file to port from (in `Sources/Feather/` on `main`) and what "done"
means. Rust bindings: `objc2`, `objc2-app-kit`, `objc2-web-kit`, `objc2-foundation`. Non-public
WebKit calls stay guarded by `responds(to:)` and go through KVC, as in Swift.

**Rules for every step:** each one ships with tests for its model code (Rust `#[test]`, mirroring
`Tests/FeatherTests`), keeps the app building with `rust/build-app.sh`, and updates this file and
`rust/RESULTS.md`. Memory matters more than CPU: re-run `bench/bench.py feather
rust/build/Feather.app feather-rust` after steps 1, 3 and 6 and compare it with the Swift build.

## What the Rust build already has
- Native window tabs with +, ⌘T and ⌘W. Toolbar: Back, Forward, Reload, Home, PiP, address field.
- `WKWebViewConfiguration` as in `makeConfiguration`, plus the memory preferences, the PiP keeper,
  Shields' compiled rule list (read from the Swift build's store) and the YouTube script.
- A read-only bookmarks bar from `bookmarks.json`, with folders and a » menu.
- Links that open a new window, and `open -a` URLs, open as tabs.

## Step 1: Custom tab bar (the biggest gap)
The Swift build no longer uses macOS window tabs: one window holds many tabs, drawn by Feather.
- Port `TabStripModel.swift` (tab order, pinning, groups, saving) as a pure Rust module with the
  same tests as `TabStripModelTests`.
- Port `TabStripView.swift` and `TabWindow.swift`: a strip under the toolbar. Normal tabs 200 pt,
  shrinking to 72 pt; pinned tabs a fixed 36 pt (about 3–4 letters) with a site-letter badge.
  Close buttons, +, drag to reorder, middle-click to close, ⌘1–9, ⌃Tab, ⌘W closes the tab. Dragging
  a tab out opens it in a new window.
- Hidden tabs' web views are removed from the window so WebKit slows them down.
- **Done when** the strip matches the Swift build's look and shortcuts, and the bookmarks bar
  stays visible (the user calls a missing bar a deal breaker).

## Step 2: Tab groups and pinned tabs
- Port `TabGroups.swift` and `TabGroupsMenu.swift`: named groups in 8 colors, saved to
  `tab-groups.json` in the same format so both builds share it.
- Chrome-style groups in the strip: a colored label, a light tint, one colored line under the
  group, and a click on the label collapses it.
- Group chips at the left of the bookmarks bar (16 pt tall, same-color groups side by side).
- Tab right-click menu: Pin Tab, Add Tab to Group, New Group…, close commands. Pinned tabs survive
  Close Other Tabs and ask before closing.

## Step 3: Memory and disk features
- `TabSuspender.swift`: tabs idle for 5 minutes sleep (web view released), and all hidden tabs
  sleep on a system memory warning.
- `SiteData.swift`: the web cache limiter. Drop cached video, audio and large images, keep code,
  styles and fonts, keep a cache only for the top 20 sites, cap at `cacheLimitMB` (default 500).
  Also `LoginKeeper`: clearing site data keeps Google, Gmail and YouTube cookies.
- `History.swift`: 7-day history in `history.json` (same format).
- `SessionRestore.swift`: restore the last session lazily (background tabs asleep), and ⇧⌘T
  reopens up to 20 closed tabs.

## Step 4: Shields and privacy
- Build and compile the rule list itself (`Shields.rulesJSON`, `Blocklist.swift`), including
  `siteExceptions` (Twitch may reach amazon-adsystem.com) and user blocklists from `*.txt`.
- The shield toolbar menu with per-site exceptions (`shieldsAllowlist`).
- `URLTools.swift`: HTTPS-only upgrades with the "continue insecurely" prompt, and
  tracking-parameter stripping.
- Private windows with a non-persistent data store.

## Step 5: Video tools
- `VideoTools.swift`, `MediaScripts.swift`: Download Video (plain files through `WKDownload`, HLS
  streams joined into .mp4/.ts with the page's cookies; refuse encrypted, DRM and DASH), and the
  subtitles menu (the video's own tracks, Load Subtitle File… for .srt/.vtt).
- PiP across iframes (`allFrames` in `BrowserWindowController.swift`), not only the main frame.
- Mute (⌃⌘M) and the sound indicator.

## Step 6: The rest of the everyday browser
- `Downloads.swift`, `DownloadsWindowController.swift`: the downloads list and toolbar button.
- `Suggestions.swift`, `SuggestionsPopup.swift`: address-bar suggestions.
- `FindBar.swift`: find in page (⌘F, ⌘G, ⇧⌘G).
- `Settings.swift`, `SettingsWindowController.swift`: every setting, including the cache limit
  and Developer ▸ Inspect Element (developer extras on open and new tabs, ⌥⌘I).
- Bookmarks: editing, the ☆ button, drag and drop, folder popups (`BookmarkBar.swift`,
  `FolderPopup.swift`, `BookmarksMenu.swift`), import and export.
- History window, Sessions menu, zoom, print, About panel, default-browser button.

## Step 7: Extensions
- `Extensions.swift`, `ExtensionMenu.swift`: WebKit's Web Extensions (install from AMO or a file,
  permissions prompt, pinned add-ons in the toolbar, manage window). The tab model must implement
  WebKit's extension tab and window protocols.

## After the port
Re-run the full benchmark (`bench/bench.py all` plus the Rust build) and replace the comparison
in `rust/RESULTS.md`. The Rust build should only replace Swift on `main` if it is clearly lighter
with every feature in place; so far, with pages loaded, the two use about the same memory.
