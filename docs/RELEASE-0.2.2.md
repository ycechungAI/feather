# Feather 0.2.2 — Eco Memory Mode & WebKit Overhead Fixes

**Release date:** 2026-11-23  
**Baseline:** `v0.2.1` (`main` branch; AI features moved to the `ai` branch)

## Why this release exists
Feather's app binary is ~1.2 MB, but on heavy video sites like YouTube, macOS WebKit spawns an out-of-process `com.apple.WebKit.WebContent` renderer that can consume **900 MB–1.1+ GB** on a single tab—mostly from YouTube's Polymer watch-page SPA, recommendations feed, comments, and Media Source Extensions (MSE) video buffers. Because `WKWebView` enforces multi-process XPC isolation on macOS, that renderer cannot be merged into the main `Feather` process.

Feather **0.2.2** tackles this overhead directly with an on-demand **Eco Memory Mode** and eliminates background script/media waste across all tabs.

---

## Highlights & Changes

### Eco Memory Mode (Toolbar leaf button beside Home · `View ▸ Eco Memory Mode` · `⌥⌘E`)
- **Off by default:** When Eco Memory is off, Feather behaves identically to `v0.2.1`.
- **Automatic >500 MB mobile switch for any site:** While Eco Memory is ON, Feather monitors each awake tab's `WebContent` physical memory footprint (`proc_pid_rusage`) every 15 seconds. If any tab exceeds **500 MB**, Feather tears down its bloated desktop `WebContent` process and reloads the page in mobile mode (probing `m.<domain>` if available, or reloading with a Mobile Safari User-Agent).
- **Immediate Mobile YouTube & Mobile Twitch + Eco DOM/MSE diet:** YouTube (`m.youtube.com`) and Twitch (`m.twitch.tv`) switch immediately in Eco Mode, evict played MSE video/audio chunks older than 10 seconds every 5 seconds, prune heavy non-player DOM bloat, and reset `WebContent` between videos/channels so SPA leaks never accumulate.
- **Preserved Back navigation & per-site/per-tab fallback:** Clicking Back returns to your previous desktop page. **Right-click the Eco leaf button** to untick **`Mobile Mode on <site>`** persistently (for example, to keep Twitch on desktop while leaving Eco Memory ON everywhere else), or choose **Open Full Page for This Tab** for a one-time bypass. Turning Eco Memory **OFF** automatically restores desktop pages.
- **Immediate background tab sleep & process teardown:** Turning Eco Memory ON sleeps all idle background tabs right away, lowers the background idle threshold to **30 seconds**, trims `WKWebsiteDataTypeMemoryCache`, and calls WebKit's `_close` during `WKWebView` teardown so `WebContent` XPC processes exit immediately.
- **Stricter WebKit memory preferences while ON:** Applies `inactiveSchedulingPolicy = .suspend`, `invisibleMediaAutoplayNotPermitted = true`, and `offlineApplicationCacheIsEnabled = false`.

### Reduced Per-Tab & Background Overhead (Always Active)
- **Removed unconditional per-frame `PerformanceObserver`:** Feather no longer injects `streamWatcher` into every frame and iframe of every website. Video Download now inspects `performance.getEntriesByType('resource')` on demand when clicked.
- **Lazy Picture-in-Picture hooks:** `pipKeeper` is now idempotent and injected on demand into the active video's frame when Picture in Picture is triggered, instead of monkey-patching `HTMLVideoElement` and `Element.prototype.setAttribute` in every iframe on the web.
- **Host-scoped page scripts:** `Blocklist.youtubeScript` is now injected only on `youtube.com` hosts, and `addonsSiteScript` only on `addons.mozilla.org`.
- **Muted autoplaying videos no longer block tab sleep:** News and social sites (CNN, Reddit, X, Amazon) autoplay silent `<video>` loops that previously kept background tabs awake indefinitely. `TabSuspender` now ignores muted videos (`muted` or `volume === 0`) unless they are floating in Picture in Picture.

### Bug Fixes & UI Improvements
- **Live memory pill on the tab strip (`TabStripView.swift`):** Sleek rounded badge on the right edge of the tab strip showing Feather's **true total memory** (Feather app + all awake `WebContent` tabs + `WebKit.GPU` video/graphics + `WebKit.Networking`) with a color-coded status dot (green `< 500 MB`, amber `500 MB–1 GB`, red `> 1 GB`). **Click** the pill for a live breakdown menu with one-click **Sleep Idle Tabs & Trim Memory Now** and **Eco Memory Mode** toggle, or hover for a quick tooltip.
- **Compact address bar & always-visible core controls (`BrowserWindowController.swift`, `TabWindow.swift`):** **Home**, **Eco**, **Address bar** (auto-shrinking smoothly down to `60 pt`), **Bookmark (☆)**, and **Shields** all have `.user` priority with a `500 pt` minimum window width so they never disappear at any window size.
- **Bookmarks bar `»` overflow menu (`BookmarkBar.swift`):** Fixed `»` to appear only when bookmarks spill past the visible bar width and list only the spilled-over items instead of duplicating every bookmark.
- **Bookmark folder popups (`FolderPopup.swift`):** Fixed a broken `NSDragOperation` comparison (`operation == .none` always evaluated to `false`) so dragging a bookmark outside a folder popup properly closes the popup, and resolved compiler warnings.
- **Clean `WKWebView` teardown on tab close:** Closing a tab now detaches delegates, clears content scripts/handlers, and calls `_close` so its `WebContent` process is reclaimed immediately.

---

## Install / Upgrade
```bash
scripts/build-app.sh --install
```
Or download `Feather-0.2.2.zip` from GitHub Releases, unzip, and drag `Feather.app` to `/Applications`.
