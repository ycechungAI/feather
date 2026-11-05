---
id: docs-refresh
name: docs-refresh
schedule: "0 3 * * *"
enabled: true
model: granite4:3b
next_run_at: ""
---

Adapted from noskill `docs-refresh` (original: `noskill schedule add local-docs --name docs-refresh --prompt "refresh the document index" --cron "0 3 * * *" --missed skip --notify none`). FeatherA standalone runs as a local Ollama prompt (no local-docs index service integration).

Prompt:
Refresh the document index / documentation notes I provide.

What to do:
- Review the docs/index content pasted below and produce a refreshed summary/index, noting stale items and updates needed.
- Keep output structured and actionable.

Paste docs/index content when running:
