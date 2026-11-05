# FeatherA Roadmap

Current AI improvement release: **0.3.0** (2026-11-05). Baseline reference discussed: **0.2.1** (mainline). FeatherA’s 0.3.x line focuses on **local, Ollama-only AI** integrated into a lightweight WebKit browser.

Goals (unchanged in spirit): low resource use, safe defaults, and standards/security via system WebKit. AI additions are **opt-in**, local-only, and measured/pragmatic.

## 0.3.0 “Local AI & Research” (released in this build)
- [x] **AI off by default** (opt-in in Settings) with Ollama checks and model guidance.
- [x] **AI panel**: Ask, Research, Agents, Tasks, Results, `>>` Logs (docked).
- [x] **Ask**: local Ollama chat with bounded page context.
- [x] **Research (STORM, Swift-native)**: web-based bundled UI in a new tab, bridged to local Ollama; **no runtime Python / no `:8400`**. Multi-agent pipeline (planning/questions, parallel research, critic/revision, citations/References, multi-source retrieval). **Extended** mode (challenge/rebuttal + draft/review/rewrite).
- [x] **Agents/Tasks**: local `.md` tasks, explicit runs, in-app scheduling while open, bundled default templates.
- [x] **Defaults**: `granite4:3b` (never 1B auto-select), web/citations on, extended off; models sorted.
- [x] **Observability**: console/errors/fetch failures mirrored to `>>` Logs.
- [x] **Setup**: non-admin Ollama install/start/pull (`scripts/setup.sh`).
- [x] **Fix**: closing tabs tears down media/webview (no background playback).

## 0.3.x (next, AI polish)
- [ ] **Research parity/polish**: stronger checkpoint/resume UX, richer source verification/snippets, better handling of rate-limited engines, optional source allow/deny profiles.
- [ ] **Citations quality**: tighter grounding checks, clearer unsourced labeling, export improvements.
- [ ] **Performance**: adaptive concurrency/timeouts per model, caching of retrieval within a run, streaming/partial report UX.
- [ ] **Task/Agent UX**: clearer run history, safer scheduling semantics, import/export tasks, per-task model/preset controls.
- [ ] **Diagnostics**: one-click “AI status” (Ollama/models/ports/bridge) and actionable errors in UI.
- [ ] **Tests**: targeted tests for citation/merge logic and bridge protocol (where feasible).

## 0.4 (browser/product maturity, planned)
- Signed/notarized distribution & update story (as appropriate).
- Deeper browser polish (permissions, profiles, reader, etc.) per baseline goals.
- Extension and platform hardening.

## Research baseline vs. AI release
- Use **0.2.1** (or your chosen baseline tag/build) for non-AI/baseline comparison.
- Use **0.3.0** for the AI improvement line (Ollama-only, STORM Research, Agents/Tasks). Keep release notes and changelog explicit when publishing both.
