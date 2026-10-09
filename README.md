# Feather

A tiny macOS browser (~320 KB). Feather adds no rendering engine of its own: it uses the WebKit engine
built into macOS (the same one Safari uses), so it gets web-standards and security updates through
macOS updates.

## What it does
- **Ad & tracker blocking:** WebKit content rules compiled to native code, plus YouTube ad skipping.
- **Low memory:** background tabs idle for 10 minutes go to sleep and free their memory. All hidden
  tabs sleep right away when the Mac runs low on memory.
- **Efficient video:** uses Apple's hardware video decoders.
- **Safety:** App Sandbox (pages can't reach your files), HTTPS-only mode, fraudulent-site warnings,
  Gatekeeper quarantine on downloads, tracking parameters removed from URLs, private windows.

## Bookmarks
- ☆ next to the address bar (or ⌘D) saves the page to the bookmark bar, which is always shown.
- Drag a bookmark to reorder it, or drop it onto a folder to file it there.
- Click a folder to pop up its contents; folders can nest. The » button shows everything that doesn't fit, folders included.
- Right-click a bookmark to open it in a new tab, rename it or delete it — or pick "New Folder with Bookmark…" to file it in a new folder. ⌘-click opens it in a background tab.
- Right-click a folder for Open All in Tabs, Rename or Delete. Deleting a folder deletes everything inside it.
- Right-click empty space on the bar for New Folder….
- **Bookmarks ▸ Import / Export** uses the standard bookmarks .html file, preserving folders. To move from Brave:
  Brave ▸ Bookmarks ▸ Bookmark Manager ▸ ⋮ ▸ Export bookmarks, then import that file into Feather.

## History
- **History ▸ Show All History (⌘Y):** search, open, or delete pages. Select rows and press Delete,
  or right-click for "Delete All from This Site".
- **History ▸ Clear History… (⇧⌘⌫):** remove the last hour, today, today and yesterday, or all
  history. You can also clear cookies, cache and site data.
- Private windows never record history. History is stored only on this Mac, in Feather's sandbox
  folder, and keeps the latest 5,000 visits.

## Firefox extensions
Feather runs Firefox add-ons (WebExtensions) through WebKit's built-in extension support.
- On addons.mozilla.org, click **Add to Feather**, the button Mozilla normally shows as
  "Download Firefox". Clicking any `.xpi` link also starts the install.
- Installed add-ons are pinned to the toolbar, left of the PiP button. Click one to open its panel,
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
It runs only when you open it. All source code is in `Sources/Feather`.

## Build & run
    scripts/build-app.sh              # creates build/Feather.app
    scripts/build-app.sh --install    # also copies it to /Applications
    open build/Feather.app

## Optional: bigger blocklist
    scripts/update-blocklist.sh       # downloads the StevenBlack hosts list
Then choose **Shields ▸ Reload Blocklists**.

## Settings (Terminal)
    defaults write dev.feather.browser searchURL "https://www.google.com/search?q="
    defaults write dev.feather.browser suspendMinutes -int 20
