# Rust prototype: results

Measured on 2026-10-29 on this Mac (macOS 27.0.1, Apple silicon). Rust 1.99.1 with `objc2` 0.6.5,
`objc2-app-kit` / `objc2-web-kit` 0.3.2. Swift 6.4 baseline is `scripts/build-app.sh` at commit eeea52a.

**Short answer: the Rust shell makes the app 0.5 MB smaller on disk. It makes no measurable
difference to memory on YouTube.** The YouTube page varies by more than ±150 MB from run to run.
Any difference between the two shells is inside that noise. The idle app is 20–40 MB smaller,
but the prototype leaves out most of Feather's features, so that number is the most a rewrite
could save, not what Rust itself saves.

## What the prototype is

`rust/src/main.rs` (~760 lines) and `rust/src/bookmarks.rs` (~270 lines), plus the page scripts in `rust/src/js/`, which are copied
from the Swift sources. It has:

- One window group of native macOS tabs. The tab bar's + button, ⌘T and ⌘W work.
- A toolbar with Back, Forward, Reload, Home, Picture in Picture and an address field. The field
  takes a URL, a bare domain or a Google search.
- `WKWebViewConfiguration` set up as in `makeConfiguration` and `applyMemoryPreferences`:
  - the default data store and the Safari user agent suffix
  - fraudulent-site warnings, no automatic pop-ups, element fullscreen, AirPlay
  - the non-public PiP preference and the five memory and power preferences, each set through
    KVC and each skipped when WebKit no longer has the setter
  - the PiP keeper script and its message handler
  - Shields: the `feather-*` content rule list the Swift build already compiled into the shared
    container, and the YouTube script
  - back/forward swipes, magnification, and the Web Inspector only with `FEATHER_DEBUG=1`
- Links that open a new window open as a new tab. A URL given as the first argument opens in the
  first tab. URLs sent from other apps (`open -a Feather url…`) open as tabs in the front window.
- A bookmarks bar under the toolbar, read-only. It reads the Swift build's `bookmarks.json` from
  Application Support/Feather. Top-level bookmarks are buttons that open in the current tab,
  folders pop up as menus with submenus, and whatever doesn't fit goes in a » menu. It has no
  editing, drag and drop, context menus or ⌘-click into a new tab, and it doesn't reload when
  the file changes.

**Still missing compared with the Swift build:** history, extensions, settings, downloads,
address-bar suggestions, find in page, session restore and ⇧⌘T, tab sleep, the cache limiter,
private windows, the Shields menu and per-site exceptions, HTTPS-only and HTTPS upgrades,
tracking-parameter stripping, mute and the sound indicator, zoom, print, bookmark editing and
the star button, and the History, Bookmarks and Sessions menus. PiP looks only in the main frame
(the Swift build also searches iframes).

Build with `rust/build-app.sh`. It produces `rust/build/Feather.app`, signed ad hoc with the
sandbox, hardened runtime and `Support/Feather.entitlements`. `codesign --verify --strict` passes.

**Verified:** it builds and launches. https://www.google.com loads (title "Google"). YouTube
video `aqz-KE-bpKQ` loads and plays: the probe read `paused=false` with the time advancing on
every Rust run below. The bookmarks bar loaded all 14 top-level items from the real
`bookmarks.json` (probe log), and `open -a` added two URLs as tabs in the running app.

**Not verified:** clicking the toolbar buttons, the bookmark buttons and folder menus, the »
overflow at narrow widths, typing in the address field, and the PiP button. The session had no
screen-recording or accessibility permission, so nothing could be clicked or typed.

## How it was measured

`rust/measure.py APP URL SECONDS [--probe]` follows `docs/OPTIMIZATION.md`:

- It launches the app with `open -n`, so it runs beside the user's own Feather.
- It counts the app plus the WebKit processes macOS lists as belonging to it (their "responsible
  process"). The other Feather's processes are left out.
- It sets `restoreSession` to false before every launch. The test copy shares the sandbox
  container, and during this session the key was deleted from outside, which made two early Swift
  runs reopen the user's saved tabs. Those runs were thrown away.
- With `--probe`, the app logs the page's video state every 10 seconds. The Rust build has this
  behind `FEATHER_PROBE=1`. For the Swift runs marked "probed", a copy of eeea52a was built with
  the same probe added. That patch was not committed.

CPU use turned out to be no sign of playback. A confirmed-playing 480p video sometimes used under
1% CPU, so only the probe counts as proof.

The window opened at the size saved under `FeatherWindow` (981×496), so YouTube streamed at 480p
(854×480), not 4K. That is why these totals are lower than the ~1,160 MB in `OPTIMIZATION.md`. Both
builds used the same saved size.

## Results

### Disk

| | Swift | Rust |
|---|---|---|
| Binary (stripped) | 841,584 bytes (822 KB) | 354,256 bytes (346 KB) |
| `.app` on disk (`du`) | 992 KB | 516 KB |

Both use only system frameworks. The Swift build links the `libswift*` libraries, which ship with
macOS, so they add nothing to the app.

### Idle: one blank tab (`about:blank`), 20 seconds after launch

| Run | Swift app | Swift total | Rust app | Rust total |
|---|---|---|---|---|
| 1 | 124.8 MB | 189.8 MB | 86.2 MB | 143.1 MB |
| 2 | 125.3 MB | 190.7 MB | 99.6 MB | 163.1 MB |
| 3 | 124.7 MB | 189.4 MB | 105.9 MB | 180.2 MB |

The Swift app process is steady at about 125 MB. The Rust one is 86–106 MB. The ~25 MB gap comes
mostly from code the prototype doesn't have: the extension controller, bookmarks and history
loaded at launch, the bookmark bar, menus and settings. Leaving out unused frameworks from the
Rust binary (`-dead_strip_dylibs`, which drops CloudKit, CoreData and others the objc2 crates link)
showed no clear change: 99.0 and 99.2 MB with every framework linked.

### YouTube `aqz-KE-bpKQ`, 75 seconds after opening

| Run | Build | Video state (probe) | App | WebContent | GPU | Networking | **Total** |
|---|---|---|---|---|---|---|---|
| 1 | Swift | not probed | 128.9 | 684.0 + 27.6 | 85.8 | 28.7 | **955.0 MB** |
| 2 | Swift | not probed | 124.0 | 769.1 + 25.0 | 77.0 | 34.5 | **1,029.7 MB** |
| 3 | Swift (probed) | playing, t=58 s | 85.6 | 533.2 + 14.0 | 57.5 | 16.9 | **707.3 MB** |
| 4 | Swift (probed) | playing, t=41 s | 113.7 | 585.8 + 10.6 | 54.9 | 22.8 | **787.9 MB** |
| 1 | Rust | playing, t=24 s | 112.0 | 668.8 + 32.1 | 83.5 | 32.7 | **929.2 MB** |
| 2 | Rust | playing, t=43 s | 114.6 | 786.6 + 28.8 | 84.4 | 32.3 | **1,046.8 MB** |
| 3 | Rust | playing, t=67 s | 138.3 | 669.6 + 25.8 | 65.1 | 25.0 | **923.7 MB** |
| 4 | Rust | playing, t=67 s | 104.9 | 544.3 + 20.7 | 56.5 | 24.9 | **751.3 MB** |

Swift runs 1–2 and Rust runs 1–2 ran back to back. Runs 3–4 of each also ran back to back, about
10 minutes later. Swift runs 1–2 have no playback proof.

- Totals range from 707 to 1,047 MB, and the two builds overlap almost completely. Run for run,
  the WebContent process (YouTube's own page) explains nearly all of the spread.
- The app process ranged from 86 to 138 MB in both builds while YouTube played, also overlapping.
  RSS on this machine moves with memory pressure (the user's own Feather was playing media in the
  background), so single readings are rough.
- So the measurement can't tell the two shells apart on a video page. A real difference would
  have to be well under ~100 MB to hide in this noise. That fits the expectation of a few MB.

## Shared benchmark suite (`bench/bench.py`, main 311f52b)

Run on the Rust build with the bookmarks bar, on 2026-10-29 at 01:49, with nothing else running:
`python3 -I bench/bench.py feather rust/build/Feather.app feather-rust`. The Swift column comes
from the other session's `bench.py all` run at 01:53, which stopped after two stages. There is no
Brave result yet.

| | Swift (feather) | Rust (feather-rust) |
|---|---|---|
| App on disk (MB) | 1.1 | 0.5 |
| Profile after run (MB) | – | 68.6 |
| Launch to page shown (ms, median of 3) | 652 | 553 |
| Memory, 1 blank tab (MB) ¹ | 38 | 31 |
| Memory, 6 sites (MB) ¹ | – | 63 |
| Idle CPU, 6 tabs (%) ¹ | – | 1.0 |
| Speedometer 3.1 ² | – | 26.4 |
| Load en.wikipedia.org cold / warm (ms) ² | – | 3617 / 3418 |
| Load github.com cold / warm (ms) ² | – | 1370 / 860 |
| Load www.cnn.com cold / warm (ms) ² | – | 4324 / 4431 |
| Load www.reddit.com cold / warm (ms) ² | – | 2186 / 2130 |
| Load www.amazon.com cold / warm (ms) ² | – | 514 / 266 |

¹ **These count only the app's own process.** The suite adds up every process whose macOS
"responsible process" is the app. It starts the app's binary directly from a shell, though, and
then macOS attributes WebKit's processes to the shell's host app, not to Feather. 63 MB for six
open sites is the app process alone. This affects the Swift build the same way, and I've reported
it to the session that owns the suite. Corrected numbers are below.

² The page loads and Speedometer don't run in the app. They come from `bench/engine/main.swift`,
a Swift harness that sets up WebKit the way Feather does, so they are the same for any shell and
say nothing about Rust.

### Memory and CPU with the app launched by `open -n`

`rust/bench_open.py` uses the suite's own code (its physical-footprint sum, the local test page, and the 15 s /
60 s / 30 s timings), changed only to launch the app with `open -n`. That makes the app its own
responsible process, so WebKit's processes are counted too (7 with one tab, 13 with six sites).
Swift is eeea52a, and Rust is this branch. Both runs alternated, 01:54–02:03.

| Run | Swift: 1 tab | Swift: 6 sites | Swift: idle CPU | Rust: 1 tab | Rust: 6 sites | Rust: idle CPU |
|---|---|---|---|---|---|---|
| 1 | 114 MB | 1,373 MB | 68.2% | 140 MB | 1,251 MB | 1.5% |
| 2 | 92 MB | 1,202 MB | 68.5% | 83 MB | 1,279 MB | 67.4% |

The two builds overlap on every row. With six sites the spread between runs (170 MB for Swift) is
bigger than the gap between the shells. The ~68% idle CPU comes from the pages, which keep
playing video previews and ads, not from the shell. One Rust run caught a quiet moment at 1.5%.
Launch is 553 ms against 652 ms, but that's one benchmark run each (median of 3 launches), and the
Rust app has less to load at launch.

## Conclusion

- **Disk:** Rust saves about 490 KB (the binary goes from 822 KB to 346 KB). This is real, but small
  next to WebKit's disk cache (capped at 500 MB) and the profile.
- **Memory:** no measurable change on a video page or with six sites open (benchmark section). The page runs in WebKit's processes whatever
  language drives them. The smaller idle app process comes from missing features. A full port
  would add those back, and most of that memory is AppKit and WebKit objects, not Swift.
- **Cost:** almost every AppKit and WebKit call is `unsafe` in `objc2`. Delegates, KVO and
  target-action need `define_class!`, and WebKit's non-public API needs raw `msg_send!`. Porting
  the remaining ~6,000 lines would be a large rewrite for about 0.5 MB.

**Recommendation:** keep Swift on `main`, as `docs/OPTIMIZATION.md` already suggests. Keep this
branch as the record of the measurement. Memory work is better spent on the page side: tab sleep,
the cache, and the embed-player lead.

## Reproduce

```bash
rust/build-app.sh
scripts/build-app.sh
rust/measure.py build/Feather.app about:blank 20
rust/measure.py rust/build/Feather.app about:blank 20
rust/measure.py build/Feather.app "https://www.youtube.com/watch?v=aqz-KE-bpKQ" 75
rust/measure.py rust/build/Feather.app "https://www.youtube.com/watch?v=aqz-KE-bpKQ" 75 --probe
defaults delete ~/Library/Containers/dev.feather.browser/Data/Library/Preferences/dev.feather.browser restoreSession
```

With a checkout of `main` that has `bench/` (at ../Feather here):

```bash
python3 -I ../Feather/bench/bench.py feather rust/build/Feather.app feather-rust
python3 -I rust/bench_open.py ../Feather/bench build/Feather.app feather-swift
python3 -I rust/bench_open.py ../Feather/bench rust/build/Feather.app feather-rust
```

The test copy shares the sandbox container, so when it quits it overwrites `last-session.json`.
Back that file up first if the real Feather's saved tabs matter.
