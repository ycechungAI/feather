# Memory and disk: what was measured, what changed, what didn't help

Measured on 2026-10-29 on this Mac, with the release build. Memory is resident memory (RSS) of
Feather and the WebKit processes it started, 75 seconds after opening a 4K YouTube video
(Big Buck Bunny, `aqz-KE-bpKQ`). Numbers vary by about ±5% between runs.

## Feather vs Safari and Brave
Measured on the same Mac (Apple M4, 16 GB, macOS 27.0.1) on 29 October 2026, with
[bench/bench.py](../bench/bench.py). Memory is the "Memory" figure Activity Monitor shows, summed
over the browser and all of its helper processes. Each figure comes from one run.

| | Feather | Safari | Brave |
|---|---|---|---|
| App on disk | **1.1 MB** | built into macOS | 604 MB |
| Data written during the test | **64 MB** | not separable | 144 MB |
| Launch to a page on screen | **0.70 s** | 1.77 s | 0.87 s |
| Memory with 1 tab | **145 MB** | 289 MB | 593 MB |
| Memory with 6 busy sites open | 1.28 GB | **1.09 GB** | 1.78 GB |
| CPU with those 6 tabs left alone | 68% | **4%** | 143% |
| Speedometer 3.1 (responsiveness, higher is better) | 27.0 | not measured | **28.8** |

- The six sites are Wikipedia, GitHub, CNN, Reddit, Amazon and YouTube, measured a minute after
  opening.
- Brave ran with a fresh, empty profile. Safari ran with the everyday profile (it has no separate
  profiles), which may slow its launch.
- Speedometer couldn't run in Safari without turning on Safari's remote automation. Safari uses the
  same WebKit engine as Feather.
- **Finding (on hold):** Feather's high CPU with the six tabs comes from **CNN's page**. Measured
  one site at a time, CNN alone drove WebKit's networking process to about 51% (82% in total),
  while Wikipedia, GitHub, Reddit, Amazon and YouTube each stayed under 1%. It happened with Shields
  off too, so it's the page's own activity, not Feather's blocker. An earlier note blaming the
  blocking rules was wrong: those runs only looked calm by chance. Safari's 4% was probably a
  quieter moment on CNN. Paused, since memory matters more than CPU and the cause is the site.
- Page-load times are left out on purpose. WebKit fires the page's load event later than Chromium
  does (Wikipedia was readable after about 0.3 s but reported "loaded" at 3.4 s), so load-event
  times make WebKit look up to 10× slower than it feels.

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
