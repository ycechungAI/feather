# Research (Orcastrator/STORM) — Swift-native, Ollama-only

FeatherA 0.3.0 includes a **Swift-native STORM multi-agent Research** workflow, migrated from the Orcastrator concept but running **without runtime Python** and **without a local `:8400` server**.

## How it runs
- Open **AI panel → Research**: loads the bundled Research UI in a **new main-window browser tab** (`file://` bundled resource).
- A native/embedded bridge intercepts `/api/*` and routes to local Ollama / the Swift pipeline:
  - `ResearchBridge.swift` (native handler)
  - `StormOrchestrator.swift` (pipeline)
  - Bridge embedded in `Resources/Orcastrator/orcastrator/static/index.html` for reliable `file://` interception
- Local model backend: **Ollama** (`127.0.0.1:11434`).

## Pipeline (core parity)
- **Planning**: generate/parse focused research questions (preset-capped).
- **Research (parallel, bounded)** per question:
  - web retrieval (when enabled), round-robin merge across engines, URL dedup, source grounding
  - researcher answer grounded in numbered sources
  - **critic** approve/revise loop (configurable/preset)
  - **Extended**: challenger critique + researcher rebuttal before critic verdict
- **Synthesis**:
  - Normal: **Plan → Research → Write**
  - Extended: **Plan → Research → Draft → Review → Rewrite**
- **Citations/References**: local citations renumbered report-wide; inline citations linkified (`[[n]](url)`) or stripped; programmatic verified **References** appended.

## Retrieval engines (best-effort)
Wikipedia, OpenAlex, DuckDuckGo Instant Answer, DDG web (HTML), arXiv, Semantic Scholar, StackExchange, Hacker News, Stock quotes. External APIs can rate-limit or change; failures degrade gracefully when possible.

## UI progress protocol
SSE `progress` events include stage objects and per-question statuses (e.g. `searching`, `researching`, `challenging`, `rebutting`, `reviewing`, `revising`, `approved`, `done`, `unverified`). Final output is delivered as a `report` event; errors as `error`. Check **AI panel → `>>` Logs`** for bridge/runtime diagnostics.

## Defaults
- Model: **`granite4:3b`** (never 1B auto-select)
- Web search: **on**
- Inline citations: **on**
- Extended thinking: **off**

## Caveats
- Strong Swift port, not byte-for-byte identical to original Python behavior.
- Full/extended runs may take minutes on local hardware.
- Checkpoint/resume UX parity is limited compared to the original; treat long runs accordingly.
