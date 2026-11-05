# FeatherA Agentic / Local AI (0.3.0 status)

**Status: implemented (opt-in, local-only) for the 0.3.0 AI improvement release.**  
Core: **Ollama + browser only**. Research is **Swift-native** and web-bridged — **no runtime Python, no `:8400`**.

## Identity
- App: **FeatherA** (`dev.feather.a`, `FeatherA.app`), separate from baseline Feather (`dev.feather.browser`).
- AI is **off by default** (`Settings → AI`).

## What shipped in 0.3.0
### Local AI (Ollama)
- Endpoint: `http://127.0.0.1:11434`
- Recommended models: `tev1:0.8b` (router/basic), `granite4:3b` (answers/Research). `granite4:3b` is the enforced Research default (never 1B auto-select).
- Non-admin setup: `scripts/setup.sh` (installs/starts Ollama in `~/Applications`, no sudo; pulls defaults).

### AI panel
- **Ask, Research, Agents, Tasks, Results** + **`>>` Logs** (docked; same window).
- Console/JS errors, rejections, and fetch failures mirrored to `>> Logs` (bridge `[feathera]` events included).

### Ask
- Page-aware local chat (bounded context) via Ollama.

### Research (Orcastrator/STORM, Swift-native)
- Bundled Orcastrator UI loaded in a **new main-window browser tab** (opened via AI panel → Research).
- **Native bridge** (`ResearchBridge.swift`, `BrowserWindowController` handler, bridge embedded in bundled `index.html`) intercepts `/api/models`, `/api/chat`, `/api/research` (SSE), `/api/pull` and routes to local Ollama / `StormOrchestrator.swift`.
- **No runtime Python, no `:8400`.**
- Full STORM pipeline: planning/questions; parallel bounded research; Researcher/Critic (approve/revise); **Extended** challenge/rebuttal + Draft/Review/Rewrite; multi-source retrieval with round-robin merge/dedup; citations renumbered + inline linkify/strip + verified **References**. SSE stages/question statuses match the UI protocol.

### Agents & Tasks
- Local task `.md` files in Application Support; run via Ollama; in-app scheduler while open; explicit user control.
- 20 default templates bundled in `Resources/DefaultTasks/`, seeded once.

## Design/constraints (still true)
- **Local only**: no telemetry, no accounts, no cloud AI added by FeatherA.
- **Explicit control**: no autonomous disk/skill takeover.
- **Opt-in**: AI features only active when enabled.
- **Honest limitations**: STORM is a strong Swift port but best-effort vs. original Python (retrieval APIs vary/rate-limit; checkpoint/resume UX not identical; simplified probing). Extended runs can take minutes.

## Next steps
See [../ROADMAP.md](../ROADMAP.md) (0.3.x polish: citations/grounding, checkpoint/resume, performance, diagnostics/tests).
