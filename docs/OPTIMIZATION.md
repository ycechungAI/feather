# Memory and disk: what was measured, what changed, what didn't help

Measured on 2026-10-29 on this Mac, with the release build. Memory is resident memory (RSS) of
Feather and the WebKit processes it started, 75 seconds after opening a 4K YouTube video
(Big Buck Bunny, `aqz-KE-bpKQ`). Numbers vary by about ±5% between runs.

## Where the memory goes

| Process | Memory | What it is |
|---|---|---|
| WebContent (the YouTube page) | 880–930 MB | YouTube's own scripts, page layout and video buffers |
| Feather (the app) | ~123 MB | Windows, toolbar, AppKit, the WebKit UI side |
| GPU | ~80 MB | Drawing the page and decoding video |
| Networking | ~32 MB | Downloads, cache, cookies |
| **Total** | **~1,160 MB** | |

**The YouTube page process is about 77% of the total. Feather's own code is a small part of the
~123 MB app process.** Most of that is AppKit and WebKit frameworks, which any app showing a web
view loads. This is the main fact behind the language question below.

## Disk cache: fixed

WebKit sizes its disk cache from the free disk space and offers no setting for it. On this profile
it was 781 MB, and much bigger on fuller profiles.

- 185 files over 1 MB used about 620 MB (~80%). 134 of them were video chunks (`video/MP2T`). About
  50 were JavaScript, CSS or WebAssembly bundles, which sites need on every visit.
- Feather now reads each cache entry's `Content-Type` and drops video, audio, and images or unknown
  types over 1 MB. It keeps code, styles and fonts at any size. Only the 20 most visited sites, plus
  open tabs, keep a cache. The total cap is 500 MB by default and can be raised in Settings.
- Result on the real profile: **781 MB → 55 MB**, and YouTube, Google and other sites still loaded.
  Cookies and site storage are never touched by the trimmer.

## Memory experiments

| Change | Result | Kept? |
|---|---|---|
| Force H.264 on YouTube (no VP9/AV1) | 1,167 MB vs 1,167–1,280 MB: no consistent change | No, removed |
| Cap YouTube at 1080p | 1,147–1,164 MB vs 1,141–1,200 MB: no change | No, removed |
| Custom process pool (no spare process, no cache of closed tabs' processes) | Pages stopped loading | No, removed |
| No back/forward page cache, low-power audio buffers, hidden-page timer throttling | Not separately measurable on a single tab; saves memory as you browse back and forth | Yes |
| Tab sleep 10 → 5 minutes | Background tabs free 100–900 MB each, sooner | Yes |
| YouTube embed player (`/embed/ID`) instead of the watch page | 342 MB total vs ~1,160 MB, **but the video probably wasn't playing** (GPU process stayed idle) | Not built yet: needs a fair measurement |

The embed-player result is the only lead that could make a large difference. It needs a run where
the video is confirmed to be playing before any conclusion.

## Screen rendering

Pages are already drawn by WebKit's GPU process with hardware compositing, and video uses Apple's
hardware decoders. Feather's UI is native AppKit, and the tab bar is the system's. There is no
software rendering path to remove. Hidden pages now run their timers less often, which saves CPU,
not memory. Further rendering gains would have to come from WebKit itself.

## Other languages

The shell (tabs, toolbar, settings) is about 6,300 lines of Swift. Rewriting it changes only the
small part of the ~123 MB app process that is Feather's own code. It cannot change the ~1 GB YouTube
page, because that runs in WebKit's processes whatever language drives them.

| Option | Expected effect on memory and disk | Notes |
|---|---|---|
| **Swift (current)** | Baseline. The Swift runtime ships with macOS, so it adds ~0 MB. | Binary 845 KB after `-Osize`. |
| **Objective-C** | Within a few MB of Swift | Same frameworks, same WebKit. |
| **C** (Objective-C runtime calls by hand) | Same as Objective-C | Much harder to maintain, nothing gained. |
| **Rust** (`objc2` bindings to AppKit and WKWebView) | Probably within ±5 MB of Swift | Memory safety without a garbage collector. Worth a branch as a prototype. |
| **Zig** | Like C | Small ecosystem for macOS UI. |
| **Python** (PyObjC) | **Worse:** +30–60 MB for the interpreter, and slower UI | Not worth it for this goal. |
| **UI in WebAssembly** (e.g. Rust compiled to Wasm, drawn as a web page) | **Worse:** the UI itself would need another WebContent process (+30–150 MB) | Wasm only runs inside a web engine, so it can't replace the native shell. It fits for logic that runs inside pages (e.g. a content filter). |
| **Another engine** (Chromium/CEF, Servo, Ladybird, Gecko) | **Much worse on disk** (100–300 MB engine shipped in the app), similar or worse memory, and loses system WebKit security updates | Brave and Chrome use Chromium. |

**Recommendation:** keep Swift and the system's WebKit on `main`. A Rust prototype on its own
branch is the one rewrite worth measuring. Treat a Wasm UI as an experiment, not an optimization.
