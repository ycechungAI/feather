# FeatherA Local AI (0.3.0)

FeatherA’s AI features are **opt-in, local-only**, and designed to run with **Ollama + browser only**.

## Enable
1. **Settings → AI** → enable.
2. Ensure Ollama is running at `http://127.0.0.1:11434`.
3. Pull recommended models (`scripts/setup.sh --pull-models` or in-app pull).

## Features
- **Ask**: local model answers with bounded current-page context.
- **Research**: Swift-native STORM multi-agent research (see [RESEARCH.md](RESEARCH.md)).
- **Agents/Tasks**: local `.md` tasks executed via Ollama; scheduled in-app while open.
- **Results**: run outputs/summaries.
- **`>>` Logs**: mirrored console/errors/rejections/fetch failures and `[feathera]` bridge events.

## Defaults
- Research/answer default model: **`granite4:3b`** (never 1B auto-select).
- Research: web search **on**, inline citations **on**, extended thinking **off** by default.

## Privacy
- No cloud AI calls added by FeatherA. AI requests go to **local Ollama**.
- AI is off by default and actions are explicit.

## Troubleshooting
- Check **AI panel → `>>` Logs** (same window).
- Verify Ollama: `curl http://127.0.0.1:11434/api/version` and `ollama list`.
- For Research: close stale tabs and reopen via **AI panel → Research**.
