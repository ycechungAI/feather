# Changelog

## 0.3.0 (2026-11-05) — AI improvement release (FeatherA)
A major opt-in local AI upgrade over the 0.2.x baseline. Core AI/Research is **Ollama-only + browser**, with **no runtime Python** and **no local `:8400` server**.

### Added
- **AI opt-in (off by default)**: `Settings → AI` gates all AI features. When enabled, FeatherA checks local Ollama and helps confirm/pull recommended models.
- **AI panel** (docked bottom/left/right): **Ask, Research, Agents, Tasks, Results**, plus **`>>` Logs**.
- **Ask**: local Ollama chat with bounded current-page context; improved layout (larger input, history/scrolling).
- **Research (Swift-native STORM / Orcastrator migration)**:
  - Bundled Research UI opens in a **new main-window browser tab** (better viewing) via **AI panel → Research**.
  - Native bridge (`ResearchBridge.swift` + embedded web bridge) intercepts `/api/*` for `file://` and routes to local Ollama/STORM — **no runtime Python, no `:8400`**.
  - Full multi-agent STORM pipeline (`StormOrchestrator.swift`): planning/questions; parallel bounded research; Researcher/Critic approve/revise loop; **Extended** mode (Plan → Research → Draft → Review → Rewrite + challenge/rebuttal); multi-source retrieval (round-robin, dedup, verified links where applicable; Wikipedia/OpenAlex/Instant Answer/DDG web/arXiv/Semantic Scholar/StackExchange/Hacker News/Stock quotes); citations renumbered report-wide; inline citation linkification/strip; programmatic verified **References**.
  - UI-compatible SSE progress: stages, per-question statuses (`searching/researching/challenging/rebutting/reviewing/revising/approved/done/restored/unverified`), logs, report/error events.
- **Agents & Tasks (local, explicit)**:
  - Local noskill-style task `.md` files in `Application Support/FeatherA/tasks/`.
  - Run via local Ollama; in-app scheduler while FeatherA is open.
  - Task/agent status UX (running/failed/success/disabled), edit schedule/next run/enable, row actions, pagination by dock layout.
  - **20 default task templates** bundled in `Resources/DefaultTasks/`, seeded once (respects deletions).
- **Model defaults & UX**: **`granite4:3b` default no matter what** (never auto-selects 1B; non-1B fallback prefers granite4). Models sorted by name. Web search on, inline citations on, extended thinking off by default. In-app “Pull Models”/progress flows (Ollama HTTP API / safe fallbacks).
- **Logging**: console `log/warn/error/info/debug`, window errors, unhandled rejections, and fetch failures mirrored to **AI panel → `>>` Logs** (same window), plus `[feathera]` bridge events.
- **Setup**: `scripts/setup.sh` for non-admin/no-sudo Ollama install/start in `~/Applications`, restart, and auto-pull of recommended models (`tev1:0.8b`, `granite4:3b`).

### Changed
- Research migrated from Python-runtime assumptions to a **Swift-native, web-bridged** implementation in the app.
- Build/install workflow supports bundling resources and installing to `~/Applications/FeatherA.app` (`scripts/build-app.sh --install`).

### Fixed
- **Research bridge/CORS for `file://` UI**: embedded native bridge in bundled `index.html` so `/api/models`/research calls are intercepted (fixes `file:///api/models` CORS/fetch failures / “web server running?” false path).
- **Research stuck at planning**: SSE payloads encoded for UI parsing and stage/question events emitted correctly (Plan → Research → Write / extended stages).
- **Model default override**: fixed UI fallback that selected `llama3.2`; enforced `granite4:3b` default (no 1B auto-select).
- **Tab close leaves media playing**: `tabWillClose()` now pauses media, stops loading, navigates blank, removes script message handlers (breaks retain cycles), clears delegates, removes/releases the webview.

### Known limitations
- Swift STORM port is strong but best-effort vs. original Python (external retrieval APIs may rate-limit/change; checkpoint/resume UX not identical; simplified capability/memory probing).
- Extended/full research can take minutes on local hardware.
- AI requires local Ollama and models; features remain opt-in.

## 0.2.0 (2026-11-01)
The first public release (baseline).

### Added
- 214 tests, tab strip/groups/pinning, Find on Page, address bar suggestions, reopen/restore session, Settings, Downloads, per-site Shields, tab audio/mute, app icon/About, PiP/subtitles/download-video improvements, Firefox extension support experiments, and related browser features (see prior release notes).

### Changed
- Web cache capped (default 500 MB) with trimming strategy; history retention 7 days; tab sleep 5 minutes; reduced back/forward/cache/audio/timer overhead; release build size optimizations.

### Fixed
- Tracking-parameter handling, local-network HTTP behavior, YouTube/PiP/ad/timer issues, Twitch ad edge case, tab restore ordering, history clearing sign-in behavior, sandbox/PiP and extension diagnostics.

## 0.1.0 (2026-10-10)
The first version (baseline): WebKit browsing, Shields, sandbox/safety basics, tab sleeping, PiP, bookmarks/history/sessions, Firefox extension experiments, initial tests.
