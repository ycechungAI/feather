# FeatherA 0.3.0 — AI Improvement Release Notes

**Release:** 0.3.0 (AI improvement)  
**Baseline reference:** 0.2.1 (mainline, for comparison)  
**Date:** 2026-11-05  
**Bundle:** `dev.feather.a` / `FeatherA.app`

## Summary
FeatherA 0.3.0 is a clear local-AI upgrade: **Ollama-only** Ask, Agents, Tasks, Results, and a **Swift-native STORM multi-agent Research** workflow, integrated into a lightweight WebKit browser. **No runtime Python, no `:8400` server, no cloud AI added.** AI is **off by default**.

## Highlights
- Opt-in AI panel: **Ask / Research / Agents / Tasks / Results / `>>` Logs**
- **Research**: full STORM pipeline (planning/questions, parallel multi-agent research, critic/revision, citations + verified References, multi-source retrieval). **Extended** adds challenge/rebuttal + draft/review/rewrite (5 stages).
- Research UI opens in a **new browser tab** (bridged to local Ollama/Swift pipeline).
- Defaults: **`granite4:3b`** (never 1B), web search on, inline citations on, extended off.
- Non-admin Ollama setup: `scripts/setup.sh` (no sudo, `~/Applications`).
- Fix: closing tabs stops media and fully tears down the webview.

## Requirements
- macOS with WebKit; Xcode CLT to build from source.
- Local **Ollama** at `127.0.0.1:11434` with recommended models (`tev1:0.8b`, `granite4:3b`).

## Publishing guidance
- Publish **0.3.0** as the AI-improvement line/build.
- Keep **0.2.1** artifacts/notes available for baseline comparison.
- Include checksums; sign/notarize for broad distribution as appropriate.
- Note known caveats: Swift STORM is best-effort parity; external retrieval APIs can rate-limit; extended runs take time.

## Upgrade/compat notes
- AI is opt-in; existing browsing behavior remains available with AI off.
- Research requires opening via **AI panel → Research** (fresh bridged tab). Close stale `:8400`/old Research tabs.
- Use **`>>` Logs`** for diagnostics.

## Files/docs
- [README.md](README.md), [CHANGELOG.md](CHANGELOG.md), [ROADMAP.md](ROADMAP.md)
- [docs/AI.md](docs/AI.md), [docs/RESEARCH.md](docs/RESEARCH.md), [docs/SETUP-OLLAMA.md](docs/SETUP-OLLAMA.md), [docs/AGENTIC.md](docs/AGENTIC.md), [docs/OPTIMIZATION.md](docs/OPTIMIZATION.md)
