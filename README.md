# Feather

**Version 0.2.0** · [Roadmap](ROADMAP.md) · [Changelog](CHANGELOG.md)

A tiny macOS browser (about 1 MB). Feather adds no rendering engine of its own: it uses the WebKit engine
built into macOS (the same one Safari uses), so it gets web-standards and security updates through
macOS updates.

## How it compares
| | Feather | Safari | Brave |
|---|---|---|---|
| App size | **1.1 MB** | built into macOS | 604 MB |
| Memory, 1 tab | **145 MB** | 289 MB | 593 MB |
| Memory, 6 busy sites | 1.28 GB | **1.09 GB** | 1.78 GB |
| Launch to page | **0.70 s** | 1.77 s | 0.87 s |
| Speedometer 3.1 | 27.0 | same engine as Feather | **28.8** |

Apple M4, macOS 27, October 2026. Full results and method:
[docs/OPTIMIZATION.md](docs/OPTIMIZATION.md#feather-vs-safari-and-brave).

## What it does
- **Ad & tracker blocking:** WebKit content rules compiled to native code, plus YouTube ad skipping.
- **Low memory:** background tabs idle for 5 minutes go to sleep and free their memory. All hidden
  tabs sleep right away when the Mac runs low on memory. Going Back reloads the previous page
  instead of keeping it in memory.
- **Small disk cache:** the web cache stays under 500 MB (raise it in Settings). It keeps the scripts,
  styles and fonts of your 20 most visited sites, which load on every visit, and drops video, audio
  and large images. Cookies are never touched, so trimming never signs you out.
- **Efficient video:** uses Apple's hardware video decoders.
- **Safety:** App Sandbox (pages can't reach your files), HTTPS-only mode, fraudulent-site warnings,
  Gatekeeper quarantine on downloads, tracking parameters removed from URLs, private windows.

## Everyday browsing
- **Find on page (⌘F):** type to highlight matches. Return or ⌘G goes to the next match, ⇧Return or
  ⇧⌘G to the previous one, Esc closes the bar.
- **Address bar suggestions:** as you type, matching pages from your history and bookmarks appear
  below the address bar. Use ↑/↓ and Return, or click one. Search-engine suggestions are off by default,
  because they send what you type to the search engine. Turn them on in Settings.
- **Reopen closed tab (⇧⌘T):** brings back up to 20 recently closed tabs, with their back/forward history.
- **Restore last session:** your tabs come back after you quit, restart or crash. Only the tab you were
  looking at in each window loads right away; the others load when you click them, so restoring
  costs almost no memory. Turn this off in Settings, then use **History ▸ Reopen Last Session**
  when you want it.
- **Picture in Picture:** the PiP button next to Home floats the page's video, on any site, including
  YouTube and embedded players. If a YouTube ad closes the floating window, Feather reopens it.
- **Download video (⌥⌘S):** the ⤓ button next to PiP saves the page's video while it plays, into
  Downloads. Plain video files download as they are. HLS streams (most sites) are saved part by
  part with your login for the site, as an `.mp4`, or as a `.ts` for older streams (`.ts` plays in
  IINA or VLC, not QuickTime). Live streams record until you cancel them in Downloads. Encrypted or
  DRM-protected videos and DASH streams (picture and sound sent separately) can't be saved.
- **Subtitles:** the speech-bubble button lists the video's own subtitle tracks, including subtitles
  stored inside an MP4 or HLS stream, so you can turn them on or off. **Load Subtitle File…** adds an `.srt` or `.vtt` file to any video, also from the View menu.
  Players that draw their own captions (YouTube) use their own CC button.
- **Sound indicator & mute:** tabs playing sound show 🔊 in their title. **View ▸ Mute Tab (⌃⌘M)**
  silences a tab (🔇) until you unmute it.
- **Downloads (⌥⌘L):** progress, cancel, Show in Finder, open, and a list of your last 50 downloads.
  A downloads button appears in the toolbar while files download. Clearing the list leaves the files
  in your Downloads folder.

## Shields per site
Click the shield in the toolbar:
- **Block Ads & Trackers on This Site:** untick it when a site breaks or asks you to turn off your
  ad blocker. The page reloads without blocking, and the shield icon shows a slash for that site.
  The setting covers the whole site, including subdomains (for example, `example.com` also covers
  `www.example.com`).
- **Block Ads & Trackers Everywhere** turns Shields off or on for every site.
- **Manage Site Exceptions…** lists the sites where Shields are off, in Settings.

## Bookmarks
- ☆ next to the address bar (or ⌘D) saves the page to the bookmark bar, which is always shown.
- Drag a bookmark or folder to reorder it — an insertion marker shows where it'll land — or drop it onto a folder to file it there. Dropping a folder onto another folder nests it as a subfolder.
- Click a folder to pop up its contents; folders can nest. The » button shows everything that doesn't fit, folders included.
- Right-click a bookmark to open it in a new tab, rename it or delete it — or pick "New Folder with Bookmark…" to file it in a new folder. ⌘-click opens it in a background tab.
- Right-click a folder for Open All in Tabs, New Folder… (creates a subfolder), Rename or Delete. Deleting a folder deletes everything inside it.
- Right-click empty space on the bar for New Folder….
- To move a bookmark into or out of a folder (or between folders), use **Move to** in its right-click menu — on the bar or inside a folder popup. **Move Up / Move Down** inside a folder popup reorders items within that folder. Moving a folder into itself or one of its own subfolders is refused.
- **Bookmarks ▸ Import / Export** uses the standard bookmarks .html file, preserving folders. To move from Brave:
  Brave ▸ Bookmarks ▸ Bookmark Manager ▸ ⋮ ▸ Export bookmarks, then import that file into Feather.

## Sessions
- **Sessions ▸ Save Tabs as Session…** saves the frontmost window's tabs under a name you choose.
- Reopen a session later from the Sessions menu: **Restore** opens its tabs in the frontmost window
  (or a new window). Each session also offers **Rename…** and **Delete**.

## Tabs
Feather draws its own tab strip under the toolbar, like Chrome and Brave.
- Tabs have a fixed width from the left and shrink only when the window is full; past that, the »
  button at the right lists every tab. **+** (or ⌘T, or double-clicking empty strip space) opens a tab.
- **Close:** the × on a tab, a middle click, or ⌘W (the tab, not the window; ⇧⌘W closes the window).
- **Switch:** click, ⌘1–⌘8 (⌘9 is the last tab), ⌃Tab / ⌃⇧Tab, or ⇧⌘[ / ⇧⌘].
- **Move:** drag a tab along the strip to reorder it. Drag it off the strip to give it its own window,
  or onto another Feather window to move it there. Window ▸ Move Tab to New Window does the same.
- **Right-click a tab** for New Tab, Reload, Mute, **Pin Tab**, **Add Tab to Group** (or New Group…),
  Remove from Group, Close Tab, Close Other Tabs and Move Tab to New Window.
- **Pinned tabs** are narrow, at the left, and show only a site badge (the site's first letter).
  Close Other Tabs keeps them, closing one asks first, and pins are saved with the session.
- Only the selected tab's page is in the window. Other tabs' pages are set aside, so WebKit slows
  their timers and drawing, and idle ones sleep (their page is freed) until you click them.

## Tab groups
- **Tab Groups ▸ New Group from Window's Tabs…** or **New Group from Current Tab…** asks for a name
  and a color. Groups are saved in `tab-groups.json` and survive quitting.
- **Add Current Tab to Group** and **Remove Current Tab from Group** are in the same menu.
- Each saved group is a small colored chip at the left of the bookmark bar (just the name's first 3 letters;
  hover for the full name). Groups of the same color sit together. Click a chip to bring the
  group's tabs forward, or to reopen them in a new window when they're closed. Only the first tab
  loads; the others sleep until you click them.
- Right-click a chip (or use its submenu under Tab Groups) for **Rename…**, **Change Color**,
  **Open in New Window** (Move to New Window when it's open), **Close Group** and **Delete Group…**.
  Closing a group closes its tabs and keeps it saved. Deleting it leaves its open tabs open, ungrouped.
- A group follows its open tabs: navigate, open or close one and the saved group changes with it.
  Closing the group's window keeps every tab saved.

Grouped tabs sit together after a label in the group's color, and each is underlined in that color.
Click the label for the group's menu. Unlike Chrome, a group can't be collapsed in the strip (use
Close Group and the chip), and tabs can't be multi-selected, so a group starts from the current tab
or the whole window. Adding a tab to a closed group reopens the group's other tabs (asleep) next to
it, so the group keeps all of them. Private windows can't use groups.

## History
- **History ▸ Show All History (⌘Y):** search, open, or delete pages. Select rows and press Delete,
  or right-click for "Delete All from This Site".
- **History ▸ Clear History… (⇧⌘⌫):** remove the last hour, today, today and yesterday, or all
  history. You can also clear cookies, cache and site data. You stay signed in to Google, Gmail and
  YouTube: their cookies are kept.
- Private windows never record history. History is stored only on this Mac, in Feather's sandbox
  folder, and keeps the last 7 days.

## Firefox extensions
Feather runs Firefox add-ons (WebExtensions) through WebKit's built-in extension support.
- On addons.mozilla.org, click **Add to Feather**, the button Mozilla normally shows as
  "Download Firefox". Clicking any `.xpi` link also starts the install.
- Installed add-ons are pinned to the toolbar, left of the 🧩 button. Click one to open its panel,
  or right-click it to unpin it, open its settings, or remove it. Unpinned add-ons stay in the 🧩 menu.
- 🧩 ▸ **Install Add-on from File…** accepts a `.xpi`, a `.zip`, or an unpacked folder.
- Before anything installs, Feather lists the access the add-on wants. Extensions never run in
  private windows.
- 🧩 ▸ **Manage Extensions** turns add-ons on or off, opens their settings, or removes them.
- **Limits:** most popular add-ons work, such as Dark Reader, password managers and translators.
  Add-ons that rely on Firefox-only features, like blocking `webRequest`, sidebars or themes, may
  only partly work. Feather's built-in Shields already block ads.

## How engine & security updates work
The web engine is Apple's WebKit, built into macOS. Apple ships its security fixes through
macOS updates and urgent Background Security Improvements. Keep **System Settings ▸ General ▸
Software Update ▸ Automatic Updates** turned on, and Feather is patched without a rebuild.

## What it does NOT do
No telemetry, no accounts, no background processes, no login items, and no network calls of its own.
The one exception is search suggestions, which are off unless you turn them on in Settings.
It runs only when you open it. All source code is in `Sources/Feather`.

## Build & run
    scripts/build-app.sh              # creates build/Feather.app
    scripts/build-app.sh --install    # also copies it to /Applications
    open build/Feather.app
    scripts/test.sh                   # runs the unit tests

Only the Xcode Command Line Tools are needed, not full Xcode. The scripts use SwiftPM's native build
system because the newer default one fails with "Unknown error parsing property list" with the
Command Line Tools in Swift 6.4. The tests use Swift Testing, which the Command Line Tools include
(XCTest needs full Xcode). `swift scripts/make-icon.swift` redraws the app icon.

Building on an ExFAT or FAT drive works: the build script removes the hidden `._*` files that macOS
creates on those drives, which would otherwise break the app's signature.

## Optional: bigger blocklist
    scripts/update-blocklist.sh       # downloads the StevenBlack hosts list
Then choose **Shields ▸ Reload Blocklists**.

## Settings (⌘,)
**Feather ▸ Settings** covers:
- Search engine: Google, DuckDuckGo, Bing, Brave Search, Startpage, or a custom search URL.
- Home page.
- How long background tabs wait before sleeping.
- Web cache limit (250 MB to 5 GB, default 500 MB).
- Shields and HTTPS-Only Mode.
- Search suggestions.
- Restoring tabs on launch.
- Sites with Shields off.
- A button to make Feather your default browser (macOS asks you to confirm).

Changes take effect right away. The same values can still be set from Terminal, for example:

    defaults write dev.feather.browser searchURL "https://duckduckgo.com/?q="
    defaults write dev.feather.browser suspendMinutes -int 20
