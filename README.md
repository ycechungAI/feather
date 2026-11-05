# FeatherA

**Version 0.3.0 (AI improvement release)** · [Release notes](RELEASE-0.3.0.md) · [Changelog](CHANGELOG.md) · [Roadmap](ROADMAP.md) · [AI](docs/AI.md) · [Research](docs/RESEARCH.md) · [Ollama setup](docs/SETUP-OLLAMA.md)

FeatherA is a lightweight macOS WebKit browser with an **opt-in, local-only AI workspace**. It uses the WebKit engine built into macOS (the same engine family Safari uses) and adds no cloud AI, no telemetry, and no accounts.

**0.3.0** is a clear AI upgrade over the 0.2.x baseline: local **Ask, Research (STORM), Agents, Tasks, Results, and Logs** powered by **Ollama only**. Research is web-based in the app and **Swift-native** (bridged to local Ollama) — **no runtime Python and no local `:8400` server**.

## What’s new in 0.3.0
- **AI is off by default** (opt-in): `Settings → AI`. When enabled, FeatherA checks local Ollama, helps you confirm/pull recommended models, and reveals AI features.
- **Local AI panel** (docked bottom/left/right): **Ask, Research, Agents, Tasks, Results** + **`>>` Logs**.
- **Ask**: chat with the current page context (bounded) via local Ollama.
- **Research (Orcastrator/STORM, Swift-native)**: opens in a **new browser tab** for better viewing; runs a full multi-agent research pipeline (planning/questions, parallel research, critic/revision, optional extended challenge/rebuttal + draft/review/rewrite), multi-source retrieval, citations, and a verified **References** section. Streams live stages/question status and writes a report. **No runtime Python.**
- **Agents + Tasks**: local, explicit, user-controlled task files (`.md`) in Application Support; run via local Ollama; in-app scheduling while FeatherA is open. No autonomous disk/skill control.
- **Defaults**: Research defaults to **`granite4:3b`** (never auto-selects a 1B model), web search on, inline citations on, extended thinking off. Model lists are sorted by name.
- **Reliability/logging**: page/JS console, errors, rejections, and fetch failures are mirrored to **AI panel → `>>` Logs** (same window). Research bridge issues are surfaced there.
- **Browser fix**: closing a tab properly tears down media (stops video/audio playback), navigates to blank, removes script handlers, and releases the webview.
- **Non-admin setup**: `scripts/setup.sh` can install/start Ollama in `~/Applications` (no sudo) and auto-pull recommended models.

## Core requirements (AI)
- **Ollama + browser only** for core AI/Tasks/Agents/Ask/Research.
- Local Ollama endpoint: `http://127.0.0.1:11434`.
- Recommended models (defaults used by setup/UI): **`tev1:0.8b`** (router/basic), **`granite4:3b`** (answers/Research), optional **`nomic-embed-text:latest`**.

See [docs/SETUP-OLLAMA.md](docs/SETUP-OLLAMA.md).

## Privacy & safety
- **Local-only AI**: AI features call **local Ollama** on `localhost`. FeatherA adds no cloud AI calls.
- **AI off by default**; features run only when you enable them and take explicit actions.
- No telemetry, no accounts, no background daemons started by the app.
- The browser retains FeatherA’s WebKit-based privacy/safety posture (App Sandbox, HTTPS-only options, Shields, etc.). Review [CHANGELOG.md](CHANGELOG.md) and source for details.

## Browser features (baseline)
FeatherA remains a small WebKit browser with features including ad/tracker blocking (Shields), low-memory tab sleeping, session/tab management, bookmarks/history, downloads, Find in Page, Picture in Picture, extensions support experiments, and per-site controls. For historical baseline behavior and prior measurements, see [CHANGELOG.md](CHANGELOG.md) and [docs/OPTIMIZATION.md](docs/OPTIMIZATION.md).

## Install
FeatherA is built from source in this repo. For a packaged release, publish `FeatherA.app` (version 0.3.0) with checksums/signing appropriate for your distribution.

If macOS blocks an unsigned/unnotarized build, you may need to allow it (right-click → **Open**, or **System Settings → Privacy & Security → Open Anyway**), or clear quarantine for a local build:

```bash
xattr -dr com.apple.quarantine /Applications/FeatherA.app
```

## Build & run
```bash
scripts/build-app.sh              # creates build/FeatherA.app
scripts/build-app.sh --install    # also installs to ~/Applications/FeatherA.app
open build/FeatherA.app
scripts/test.sh                   # runs tests
```

Requires Xcode Command Line Tools (not full Xcode).

## Ollama setup (non-admin)
```bash
scripts/setup.sh                  # installs/starts Ollama in ~/Applications (no sudo) + pulls defaults
scripts/setup.sh --pull-models    # pull tev1:0.8b, granite4:3b
scripts/setup.sh --restart        # restart local Ollama
```

## Using AI & Research
1. Enable **Settings → AI**.
2. Ensure Ollama is running and models are available.
3. Open the AI panel: **Ask / Research / Agents / Tasks / Results** (`>>` Logs).
4. For Research, open via **AI panel → Research** (fresh bridged tab). Default model **`granite4:3b`**; web search/citations on; extended thinking optional.

Troubleshooting: check **AI panel → `>>` Logs** (same window). Close stale Research tabs and reopen via the AI panel.

## Known caveats
- **Research/STORM** is a Swift-native port: strong core parity (stages, question statuses, multi-agent passes, retrieval, citations/References), but best-effort vs. the original Python implementation (e.g., external retrieval engines can rate-limit/change; full checkpoint/resume UX is not identical; capability/memory probing is simplified).
- Full/extended research can take several minutes depending on model/hardware.
- AI features are opt-in and depend on a working local Ollama installation.

## Source layout (selected)
- `Sources/FeatherA/` — app/browser/UI/AI integration
- `Sources/FeatherA/ResearchBridge.swift` — native bridge for bundled Research UI (`/api/*` → local Ollama/STORM)
- `Sources/FeatherA/StormOrchestrator.swift` — Swift-native STORM multi-agent pipeline
- `Resources/Orcastrator/.../static/index.html` — bundled Research UI (loaded in-app; bridged)
- `Resources/DefaultTasks/` — seeded local agent task templates
- `scripts/setup.sh`, `scripts/build-app.sh`, `scripts/test.sh`

## License / status
See repository license and commit history. 0.3.0 is an AI-focused improvement release built on the FeatherA WebKit browser baseline.
